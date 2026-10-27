import '../../core/network/api_response_parser.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/network_exceptions.dart';
import '../dto/common/task_log_dto.dart';
import '../dto/firewall/firewall_base_info_dto.dart';
import '../dto/firewall/unified_firewall_dto.dart';

enum FirewallApiVersion { legacy, unified }

/// The read-only probe never sends an old rule mutation to the new /port route.
class UnifiedFirewallApi {
  UnifiedFirewallApi(this._client);

  final DioClient _client;
  FirewallApiVersion? _version;

  Future<FirewallApiVersion> detectVersion({bool refresh = false}) async {
    if (!refresh && _version != null) return _version!;
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/v2/hosts/firewall/settings',
      );
      ApiResponseParser.map(response);
      return _version = FirewallApiVersion.unified;
    } on HttpException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 405) {
        return _version = FirewallApiVersion.legacy;
      }
      rethrow;
    }
  }

  Future<FirewallBaseInfoDto> loadBase() async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/base',
      data: {'name': 'base'},
    );
    return ApiResponseParser.object(response, FirewallBaseInfoDto.fromJson);
  }

  Future<UnifiedFirewallInventory> search({
    required String provider,
    required int page,
    required int pageSize,
    String info = '',
    List<String> families = const [],
    List<String> actions = const [],
    List<String> states = const [],
    bool refresh = false,
  }) async {
    await _requireUnified();
    final response = await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/rules/search',
      data: {
        'scopes': scopesFor(provider),
        'page': page,
        'pageSize': pageSize,
        'info': info,
        'families': families,
        'actions': actions,
        'states': states,
        'excludeChains': provider == 'iptables' || provider == 'nftables'
            ? ['1PANEL_BASIC_BEFORE', '1PANEL_BASIC_AFTER']
            : <String>[],
        'refresh': refresh,
      },
    );
    return ApiResponseParser.object(
      response,
      UnifiedFirewallInventory.fromJson,
    );
  }

  Future<FirewallTaskSubmission> create(
    List<Map<String, dynamic>> rules, {
    String sourceKind = 'user',
  }) async {
    await _requireUnified();
    final response = await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/rules',
      data: {
        'items': rules
            .map((rule) => {'rule': rule, 'sourceKind': sourceKind})
            .toList(),
      },
    );
    return _task(response);
  }

  Future<void> update(String uuid, Map<String, dynamic> rule) async {
    await _requireUnified();
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/rules/update',
      data: {'uuid': uuid, 'rule': rule},
    );
  }

  Future<void> updateDescription(String uuid, String description) async {
    await _requireUnified();
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/rules/update',
      data: {'uuid': uuid, 'description': description},
    );
  }

  Future<void> adopt(UnifiedFirewallItem item) async {
    if (!item.canAdopt) throw StateError('当前规则不支持纳管');
    await _requireUnified();
    final observedRule = Map<String, dynamic>.from(
      item.observed['rule'] as Map? ?? const <String, dynamic>{},
    );
    final locator = item.observed['locator'];
    if (locator is Map && locator['position'] != null) {
      observedRule['orderIndex'] = locator['position'];
    }
    final instanceKey = '${item.observed['instanceKey'] ?? ''}';
    if (item.rule.provider == 'nftables' && instanceKey.isEmpty) {
      throw StateError('当前规则缺少实例标识，无法纳管');
    }
    final response = await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/rules/adopt',
      data: {
        'scope': item.rule.scope,
        if (instanceKey.isNotEmpty) 'instanceKey': instanceKey,
        if (observedRule.isNotEmpty) 'rule': observedRule,
        if ('${item.observed['marker'] ?? ''}'.isNotEmpty)
          'marker': item.observed['marker'],
      },
    );
    ApiResponseParser.ok(response);
  }

  Future<FirewallTaskSubmission> delete(List<UnifiedFirewallItem> items) async {
    await _requireUnified();
    final response = await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/rules/delete',
      data: {
        'uuids': items
            .where((e) => e.canDeleteManaged)
            .map((e) => e.uuid)
            .toSet()
            .toList(),
        'beforeRules': items
            .where((e) => e.canDeleteBefore)
            .map((e) => e.deleteTarget)
            .toList(),
      },
    );
    return _task(response);
  }

  Future<TaskLogDto> readTask(String taskID) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/v2/logs/tasks/read',
      data: {'taskID': taskID, 'page': 1, 'pageSize': 500, 'latest': true},
    );
    return ApiResponseParser.object(response, TaskLogDto.fromJson);
  }

  Future<FirewallTaskSubmission?> operateService(String operation) async {
    await _requireUnified();
    final response = await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/operate',
      data: {'operation': operation, 'withDockerRestart': false},
    );
    final result = ApiResponseParser.object(
      response,
      FirewallTaskSubmission.fromJson,
    );
    if (result.queued && result.taskID.isEmpty) {
      throw const ApiFormatException('防火墙任务缺少 taskID');
    }
    return result.queued ? result : null;
  }

  Future<FirewallTaskSubmission?> operateBaseChain(String operation) async {
    await _requireUnified();
    final response = await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/filter/operate',
      data: {'name': '1PANEL_BASIC', 'operate': operation},
    );
    final result = ApiResponseParser.object(
      response,
      FirewallTaskSubmission.fromJson,
    );
    if (result.queued && result.taskID.isEmpty) {
      throw const ApiFormatException('防火墙任务缺少 taskID');
    }
    return result.queued ? result : null;
  }

  Future<void> _requireUnified() async {
    if (await detectVersion(refresh: true) != FirewallApiVersion.unified) {
      throw StateError('当前防火墙 API 不支持统一规则');
    }
  }

  FirewallTaskSubmission _task(dynamic response) {
    final result = ApiResponseParser.object(
      response,
      FirewallTaskSubmission.fromJson,
    );
    if (!result.queued || result.taskID.isEmpty) {
      throw const ApiFormatException('防火墙任务未成功提交');
    }
    return result;
  }

  static List<Map<String, dynamic>> scopesFor(String provider) {
    switch (provider) {
      case 'iptables':
      case 'nftables':
        return [
          for (final family in ['ipv4', 'ipv6'])
            for (final chain in [
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
            'provider': provider,
            'family': 'inet',
            'zone': 'public',
            'direction': 'input',
          },
        ];
      case 'ufw':
        return [
          {
            'provider': provider,
            'family': 'inet',
            'chain': 'incoming',
            'direction': 'input',
          },
        ];
      default:
        throw StateError('不支持的防火墙后端: $provider');
    }
  }

  static Map<String, dynamic> scopeFor(String provider, String family) {
    if (provider == 'iptables' || provider == 'nftables') {
      return {
        'provider': provider,
        'family': family,
        'table': 'filter',
        'chain': '1PANEL_BASIC',
        'direction': 'input',
      };
    }
    if (provider == 'firewalld') {
      return {
        'provider': provider,
        'family': family,
        'zone': 'public',
        'direction': 'input',
      };
    }
    if (provider == 'ufw') {
      return {
        'provider': provider,
        'family': family,
        'chain': 'incoming',
        'direction': 'input',
      };
    }
    throw StateError('不支持的防火墙后端: $provider');
  }
}
