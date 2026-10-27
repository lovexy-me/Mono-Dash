import 'package:dio/dio.dart';

import '../../core/network/api_response_parser.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/network_exceptions.dart';
import '../dto/common/page_result.dart';
import '../dto/firewall/firewall_base_info_dto.dart';
import '../dto/firewall/rule_info_dto.dart';
import 'unified_firewall_api.dart';

class FirewallApi {
  FirewallApi(this._client);

  final DioClient _client;

  Future<void> _requireLegacyRules() async {
    final version = await UnifiedFirewallApi(
      _client,
    ).detectVersion(refresh: true);
    if (version != FirewallApiVersion.legacy) {
      throw StateError('防火墙已升级，请重新打开规则页面');
    }
  }

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
    return ApiResponseParser.object(resp, FirewallBaseInfoDto.fromJson);
  }

  Future<Response<Map<String, dynamic>>> _postBaseInfo(String path) {
    return _client.post<Map<String, dynamic>>(path, data: {'name': 'base'});
  }

  bool _shouldFallbackBaseInfoGet(AppNetworkException error) {
    return error is HttpException &&
        (error.statusCode == 404 || error.statusCode == 405);
  }

  /// 搜索防火墙规则（分页）。
  ///
  /// [type] 为规则类型：`port`、`address`、`forward`。
  Future<PageResult<RuleInfoDto>> searchRules({
    required String type,
    int page = 1,
    int pageSize = 15,
    String info = '',
    String strategy = '',
  }) async {
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
    await _requireLegacyRules();
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/port',
      data: body,
    );
  }

  /// 添加/删除 IP 规则。
  Future<void> operateIpRule(Map<String, dynamic> body) async {
    await _requireLegacyRules();
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/ip',
      data: body,
    );
  }

  /// 更新端口规则（先删旧规则，再加新规则）。
  Future<void> updatePortRule(Map<String, dynamic> body) async {
    await _requireLegacyRules();
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/update/port',
      data: body,
    );
  }

  /// 更新地址规则（先删旧规则，再加新规则）。
  Future<void> updateAddrRule(Map<String, dynamic> body) async {
    await _requireLegacyRules();
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/update/addr',
      data: body,
    );
  }

  /// 批量操作规则（删除）。
  Future<void> batchOperate(Map<String, dynamic> body) async {
    await _requireLegacyRules();
    await _client.post<Map<String, dynamic>>(
      '/api/v2/hosts/firewall/batch',
      data: body,
    );
  }

  /// 更新规则描述。
  Future<void> updateDescription(Map<String, dynamic> body) async {
    await _requireLegacyRules();
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
}
