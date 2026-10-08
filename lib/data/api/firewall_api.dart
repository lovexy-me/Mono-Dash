import 'package:dio/dio.dart';

import '../../core/network/api_response_parser.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/network_exceptions.dart';
import '../dto/common/page_result.dart';
import '../dto/firewall/firewall_base_info_dto.dart';
import '../dto/firewall/rule_info_dto.dart';
import 'firewall_rules_v2.dart';

class FirewallApi {
  FirewallApi(this._client);

  final DioClient _client;

  /// 获取防火墙基本信息。
  Future<FirewallBaseInfoDto> getBaseInfo() async {
    const path = '/api/v2/hosts/firewall/base';
    // 兼容 1Panel API：新版使用 POST，v2.0.0 使用 GET。
    // 优先按新版协议请求，旧版返回方法不支持时回退 GET。
    late final Response<Map<String, dynamic>> resp;
    try {
      resp = await _postBaseInfo(path);
    } on AppNetworkException catch (error) {
      if (!_shouldFallbackBaseInfoGet(error)) rethrow;
      resp = await _client.get<Map<String, dynamic>>(path);
    }
    return ApiResponseParser.object(resp, (json) {
      final backend = (json['backend'] ?? '').toString();
      final name = (json['name'] ?? '').toString();
      _provider = backend.isNotEmpty ? backend : name;
      return FirewallBaseInfoDto.fromJson(json);
    });
  }

  Future<Response<Map<String, dynamic>>> _postBaseInfo(String path) {
    return _client.post<Map<String, dynamic>>(path, data: {'name': 'base'});
  }

  bool _shouldFallbackBaseInfoGet(AppNetworkException error) {
    final statusCode = error.statusCode;
    return statusCode == 404 || statusCode == 405;
  }

  /// 搜索防火墙规则（分页）。
  ///
  /// [type] 为规则类型：`port`、`address`、`forward`。
  ///
  /// 新版 1Panel v2 用统一的 `/hosts/firewall/rules/*` 接口取代了
  /// `/hosts/firewall/search`；这里优先请求新接口，服务端返回 404/405
  /// 时回退到旧接口，两种服务端都能用。
  Future<PageResult<RuleInfoDto>> searchRules({
    required String type,
    int page = 1,
    int pageSize = 15,
    String info = '',
    String strategy = '',
  }) async {
    if (type != 'forward' && await _useUnifiedRules()) {
      final all = await _searchUnified(info: info);
      final result = legacyPage(
        all,
        type: type,
        page: page,
        pageSize: pageSize,
        strategy: strategy,
      );
      return PageResult<RuleInfoDto>(
        total: result.total,
        items: result.items.map(RuleInfoDto.fromJson).toList(),
      );
    }
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/search',
      data: {
        'type': type,
        'page': page,
        'pageSize': pageSize,
        'info': info,
        'strategy': strategy,
      },
    );
    return PageResult<RuleInfoDto>.fromJson(
      ApiResponseParser.map(resp),
      RuleInfoDto.fromJson,
    );
  }

  /// 操作防火墙服务（启动/停止/重启/禁用 ping）。
  Future<void> operate(
    String operation, {
    bool withDockerRestart = false,
  }) async {
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/operate',
      data: {'operation': operation, 'withDockerRestart': withDockerRestart},
    );
  }

  /// 添加/删除端口规则。
  Future<void> operatePortRule(Map<String, dynamic> body) async {
    if (await _useUnifiedRules()) {
      return _applyLegacyOperation(body, isPort: true);
    }
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/port',
      data: body,
    );
  }

  /// 添加/删除 IP 规则。
  Future<void> operateIpRule(Map<String, dynamic> body) async {
    if (await _useUnifiedRules()) {
      return _applyLegacyOperation(body, isPort: false);
    }
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/ip',
      data: body,
    );
  }

  /// 更新端口规则（先删旧规则，再加新规则）。
  Future<void> updatePortRule(Map<String, dynamic> body) async {
    if (await _useUnifiedRules()) {
      return _updateUnified(body, isPort: true);
    }
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/update/port',
      data: body,
    );
  }

  /// 更新地址规则（先删旧规则，再加新规则）。
  Future<void> updateAddrRule(Map<String, dynamic> body) async {
    if (await _useUnifiedRules()) {
      return _updateUnified(body, isPort: false);
    }
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/update/addr',
      data: body,
    );
  }

  /// 批量操作规则（删除）。
  Future<void> batchOperate(Map<String, dynamic> body) async {
    if (await _useUnifiedRules()) {
      final isPort = body['type'] != 'address';
      final rules = (body['rules'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      return _deleteUnified(rules, isPort: isPort);
    }
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/batch',
      data: body,
    );
  }

  /// 更新规则描述。
  Future<void> updateDescription(Map<String, dynamic> body) async {
    if (await _useUnifiedRules()) {
      final legacy = <String, dynamic>{
        'address': body['address'] ?? body['srcIP'] ?? '',
        'port': body['port'] ?? body['dstPort'] ?? '',
        'protocol': body['protocol'] ?? '',
        'strategy': body['strategy'] ?? 'accept',
      };
      final isPort = body['type'] != 'address';
      final targets = await _resolveManaged(legacy, isPort: isPort);
      for (final uuid in targets) {
        await _client.post<Map<String, dynamic>>(
          '/api/v2/hosts/firewall/rules/update',
          data: {'uuid': uuid, 'description': body['description'] ?? ''},
        );
      }
      return;
    }
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/update/description',
      data: body,
    );
  }

  /// 操作 iptables filter 链（初始化、绑定、解绑）。
  Future<void> operateFilterChain({
    required String name,
    required String operate,
  }) async {
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/filter/operate',
      data: {'name': name, 'operate': operate},
    );
  }

  // ---------------------------------------------------------------------------
  // 统一规则接口（/hosts/firewall/rules/*）适配
  // ---------------------------------------------------------------------------

  static const _unifiedPageSize = 500;
  static const _unifiedMaxRules = 5000;

  bool? _unified;
  String? _provider;

  /// 探测服务端是否提供统一规则接口；结果按连接缓存。
  ///
  /// 只有路由不存在（404/405）才判定为旧版；参数错误等其他响应说明
  /// 新接口存在。连接类错误不缓存，下次重新探测。
  Future<bool> _useUnifiedRules() async {
    final cached = _unified;
    if (cached != null) return cached;
    try {
      await _client.post<Map<String, dynamic>>(
        '/api/v2/hosts/firewall/rules/search',
        data: {'page': 1, 'pageSize': 1, 'info': '', 'scopes': const []},
      );
      _unified = true;
    } on NetworkConnectionException {
      rethrow;
    } on AuthException {
      rethrow;
    } on AppNetworkException catch (error) {
      _unified = !(error.statusCode == 404 || error.statusCode == 405);
    } catch (_) {
      _unified = true;
    }
    return _unified!;
  }

  Future<String> _currentProvider() async {
    final cached = _provider;
    if (cached != null && cached.isNotEmpty) return cached;
    await getBaseInfo();
    return _provider ?? '';
  }

  /// 与 1Panel 前端 providerScopes() 一致的检索范围。
  List<Map<String, dynamic>> _scopesFor(String provider) {
    switch (provider) {
      case 'iptables':
      case 'nftables':
        return [
          for (final family in const ['ipv4', 'ipv6'])
            for (final chain in const [
              '1PANEL_BASIC_BEFORE',
              '1PANEL_BASIC',
              '1PANEL_BASIC_AFTER',
            ])
              {
                'provider': provider,
                'family': family,
                'table': 'filter',
                'chain': chain,
                'direction': 'input',
              },
        ];
      case 'firewalld':
        return [
          {
            'provider': 'firewalld',
            'family': 'inet',
            'zone': 'public',
            'direction': 'input',
          },
        ];
      case 'ufw':
        return [
          {
            'provider': 'ufw',
            'family': 'inet',
            'chain': 'incoming',
            'direction': 'input',
          },
        ];
      default:
        return const [];
    }
  }

  Future<Map<String, dynamic>> _searchUnifiedPage({
    required int page,
    required int pageSize,
    required String info,
  }) async {
    final provider = await _currentProvider();
    final scopes = _scopesFor(provider);
    if (scopes.isEmpty) {
      // 防火墙未安装或后端未识别，没有可检索的规则。
      return {'total': 0, 'items': const []};
    }
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/rules/search',
      data: {
        'scopes': scopes,
        'info': info,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return ApiResponseParser.map(resp);
  }

  Future<List<V2RuleItem>> _searchUnified({String info = ''}) async {
    final items = <V2RuleItem>[];
    var page = 1;
    while (true) {
      final data = await _searchUnifiedPage(
        page: page,
        pageSize: _unifiedPageSize,
        info: info,
      );
      final batch = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => V2RuleItem(e.cast<String, dynamic>()))
          .toList();
      items.addAll(batch);
      final total = (data['total'] as num?)?.toInt() ?? items.length;
      if (batch.isEmpty ||
          items.length >= total ||
          items.length >= _unifiedMaxRules) {
        break;
      }
      page++;
    }
    return items;
  }

  Future<void> _applyLegacyOperation(
    Map<String, dynamic> body, {
    required bool isPort,
  }) async {
    if ((body['operation'] ?? 'add') == 'remove') {
      return _deleteUnified([body], isPort: isPort);
    }
    await _createUnified(rulesFromLegacyBody(body, isPort: isPort));
  }

  Future<void> _createUnified(List<Map<String, dynamic>> rules) async {
    if (rules.isEmpty) return;
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/rules',
      data: {
        'items': [
          for (final rule in rules) {'rule': rule, 'sourceKind': 'user'},
        ],
      },
    );
    _throwOnPartialFailure(resp, '添加规则失败');
  }

  /// 找到旧格式规则对应的托管规则 UUID；外部规则先接管（adopt）再返回。
  Future<List<String>> _resolveManaged(
    Map<String, dynamic> body, {
    required bool isPort,
  }) async {
    var matches = (await _searchUnified())
        .where((item) => itemMatchesLegacyBody(item, body, isPort: isPort))
        .toList();
    final unmanaged = matches.where((item) => item.uuid == null).toList();
    if (unmanaged.isNotEmpty) {
      for (final item in unmanaged) {
        final adopt = item.adoptRequest;
        if (adopt == null) {
          throw const FirewallRuleException('该规则为系统保护或无法解析的规则，无法修改');
        }
        await _client.post<Map<String, dynamic>>(
          '/api/v2/hosts/firewall/rules/adopt',
          data: adopt,
        );
      }
      matches = (await _searchUnified())
          .where((item) => itemMatchesLegacyBody(item, body, isPort: isPort))
          .toList();
    }
    return matches
        .map((item) => item.uuid)
        .whereType<String>()
        .toSet()
        .toList();
  }

  Future<void> _deleteUnified(
    List<Map<String, dynamic>> bodies, {
    required bool isPort,
  }) async {
    if (bodies.isEmpty) return;
    final all = await _searchUnified();
    final uuids = <String>{};
    final beforeRules = <Map<String, dynamic>>[];
    final toAdopt = <V2RuleItem>[];
    for (final item in all) {
      if (!bodies.any((b) => itemMatchesLegacyBody(item, b, isPort: isPort))) {
        continue;
      }
      final uuid = item.uuid;
      if (uuid != null) {
        uuids.add(uuid);
      } else if (item.isDeletableBeforeRule) {
        beforeRules.add({'scope': item.scope, 'instanceKey': item.instanceKey});
      } else {
        toAdopt.add(item);
      }
    }
    if (toAdopt.isNotEmpty) {
      for (final item in toAdopt) {
        final adopt = item.adoptRequest;
        if (adopt == null) {
          throw const FirewallRuleException('该规则为系统保护或无法解析的规则，无法删除');
        }
        await _client.post<Map<String, dynamic>>(
          '/api/v2/hosts/firewall/rules/adopt',
          data: adopt,
        );
      }
      for (final item in await _searchUnified()) {
        if (bodies.any((b) => itemMatchesLegacyBody(item, b, isPort: isPort))) {
          final uuid = item.uuid;
          if (uuid != null) uuids.add(uuid);
        }
      }
    }
    if (uuids.isEmpty && beforeRules.isEmpty) {
      throw const FirewallRuleException('未找到要删除的规则，请刷新后重试');
    }
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/rules/delete',
      data: {
        'uuids': uuids.toList(),
        if (beforeRules.isNotEmpty) 'beforeRules': beforeRules,
      },
    );
    _throwOnPartialFailure(resp, '删除规则失败');
  }

  /// 旧接口语义为“删旧加新”。新接口下：单条且同地址族时原地更新，
  /// 否则先建新规则再删旧规则，避免中途失败导致端口被关。
  Future<void> _updateUnified(
    Map<String, dynamic> body, {
    required bool isPort,
  }) async {
    final oldRule = (body['oldRule'] as Map? ?? const {})
        .cast<String, dynamic>();
    final newRule = (body['newRule'] as Map? ?? const {})
        .cast<String, dynamic>();
    final newRules = rulesFromLegacyBody(newRule, isPort: isPort);
    final targets = await _resolveManaged(oldRule, isPort: isPort);
    if (targets.isEmpty) {
      throw const FirewallRuleException('未找到要修改的规则，请刷新后重试');
    }
    if (targets.length == 1 && newRules.length == 1) {
      final all = await _searchUnified();
      final current = all.where((i) => i.uuid == targets.first).firstOrNull;
      final rule = Map<String, dynamic>.from(newRules.first);
      final newAddress = (rule['sourceAddress'] ?? '').toString();
      final currentFamily = current?.family ?? '';
      final familyChanges = newAddress.isNotEmpty &&
          currentFamily != 'inet' &&
          (newAddress.contains(':') != (currentFamily == 'ipv6'));
      if (current != null && !familyChanges) {
        rule['scope'] = current.scope;
        if ((current.rule['nativeKind'] ?? '').toString().isNotEmpty) {
          rule['nativeKind'] = current.rule['nativeKind'];
        }
        if (!rule.containsKey('description')) rule['description'] = '';
        await _client.post<Map<String, dynamic>>(
          '/api/v2/hosts/firewall/rules/update',
          data: {'uuid': targets.first, 'rule': rule},
        );
        return;
      }
    }
    await _createUnified(newRules);
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/rules/delete',
      data: {'uuids': targets},
    );
    _throwOnPartialFailure(resp, '删除旧规则失败');
  }

  void _throwOnPartialFailure(Response<Map<String, dynamic>> resp, String what) {
    Map<String, dynamic> data;
    try {
      data = ApiResponseParser.map(resp);
    } catch (_) {
      return;
    }
    final failed = (data['failed'] as num?)?.toInt() ?? 0;
    if (failed <= 0) return;
    final errors = (data['errors'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => (e['error'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .toList();
    throw FirewallRuleException(
      errors.isEmpty ? what : '$what：${errors.first}',
    );
  }
}

class FirewallRuleException implements Exception {
  const FirewallRuleException(this.message);

  final String message;

  @override
  String toString() => message;
}
