import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/network/api_response_parser.dart';
import '../../core/network/dio_client.dart';
import '../dto/app/app_catalog_dto.dart';
import '../dto/app/app_catalog_search_req.dart';
import '../dto/app/app_detail_dto.dart';
import '../dto/app/app_install_config_dto.dart';
import '../dto/app/app_install_req.dart';
import '../dto/app/app_installed_dto.dart';
import '../dto/app/app_installed_check_req.dart';
import '../dto/app/app_installed_check_res.dart';
import '../dto/app/app_installed_info_dto.dart';
import '../dto/app/app_installed_search_req.dart';
import '../dto/app/app_service_dto.dart';
import '../dto/app/app_tag_dto.dart';
import '../dto/app/app_update_version_dto.dart';
import '../dto/app/app_ignored_dto.dart';
import '../dto/app/app_store_config_dto.dart';
import '../dto/app/app_installed_params_dto.dart';
import '../dto/common/page_result.dart';
import '../dto/database/database_instance_dto.dart';

/// App API。
///
/// 对应 1Panel `/apps` 相关接口。
class AppApi {
  AppApi(this._client);

  final DioClient _client;

  /// 检查应用是否安装
  Future<AppInstalledCheckRes> checkAppInstalled(
    AppInstalledCheckReq req,
  ) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/installed/check',
      data: req.toJson(),
    );

    return AppInstalledCheckRes.fromJson(ApiResponseParser.map(resp));
  }

  /// 检查应用是否安装。
  Future<DatabaseCheckDto> checkInstalledByKey({
    required String key,
    required String name,
  }) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/installed/check',
      data: {'key': key, 'name': name},
    );
    return ApiResponseParser.object(resp, DatabaseCheckDto.fromJson);
  }

  /// 获取已安装应用连接信息。
  Future<Map<String, dynamic>> getInstalledConnInfo({
    required String type,
    required String name,
  }) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/installed/conninfo',
      data: {'type': type, 'name': name},
    );
    return (resp.data?['data'] as Map<String, dynamic>?) ?? {};
  }

  /// 获取已安装应用暴露的主端口。
  ///
  /// 1Panel 在应用未安装时返回 `0`，调用方可据此引导用户前往应用商店。
  Future<int> getInstalledAppPort({
    required String type,
    String name = '',
  }) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/installed/loadport',
      data: {'type': type, 'name': name},
    );
    final value = resp.data?['data'];
    return switch (value) {
      int port => port,
      num port => port.toInt(),
      String port => int.tryParse(port) ?? 0,
      _ => 0,
    };
  }

  /// 查询已安装应用。
  Future<PageResult<AppInstalledDto>> searchInstalledApps(
    AppInstalledSearchReq req,
  ) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/installed/search',
      data: req.toJson(),
    );
    return PageResult<AppInstalledDto>.fromJson(
      ApiResponseParser.map(resp),
      AppInstalledDto.fromJson,
    );
  }

  /// 获取已安装应用详情。
  Future<AppInstalledInfoDto> getInstalledInfo(int id) async {
    final resp = await _client.get<Map<String, dynamic>>(
      '/api/v2/apps/installed/info/$id',
    );
    return ApiResponseParser.object(resp, AppInstalledInfoDto.fromJson);
  }

  /// 查询应用商店全部应用。
  Future<PageResult<AppCatalogDto>> searchApps(AppCatalogSearchReq req) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/search',
      data: req.toJson(),
    );
    return PageResult<AppCatalogDto>.fromJson(
      ApiResponseParser.map(resp),
      AppCatalogDto.fromJson,
    );
  }

  /// 查询应用标签。
  Future<List<AppTagDto>> listAppTags() async {
    final resp = await _client.get<Map<String, dynamic>>('/api/v2/apps/tags');
    return ApiResponseParser.list(resp, AppTagDto.fromJson);
  }

  /// 获取应用详情（应用商店）。
  Future<AppDetailDto> getAppDetail(String key) async {
    final resp = await _client.get<Map<String, dynamic>>('/api/v2/apps/$key');
    return ApiResponseParser.object(resp, AppDetailDto.fromJson);
  }

  /// 获取应用服务列表（数据库连接等）。
  /// GET /api/v2/apps/services/{key}
  Future<List<AppServiceDto>> getAppServices(String key) async {
    final resp = await _client.get<Map<String, dynamic>>(
      '/api/v2/apps/services/$key',
    );
    return ApiResponseParser.list(resp, AppServiceDto.fromJson);
  }

  /// 获取应用安装配置。
  /// GET /api/v2/apps/detail/{appId}/{version}/app
  Future<AppInstallConfigDto> getAppInstallConfig(
    int appId,
    String version,
  ) async {
    final resp = await _client.get<Map<String, dynamic>>(
      '/api/v2/apps/detail/$appId/$version/app',
    );
    return ApiResponseParser.object(resp, AppInstallConfigDto.fromJson);
  }

  /// 获取运行环境应用配置。
  /// GET /api/v2/apps/detail/{appId}/{version}/runtime
  Future<AppInstallConfigDto> getAppRuntimeConfig(
    int appId,
    String version,
  ) async {
    final resp = await _client.get<Map<String, dynamic>>(
      '/api/v2/apps/detail/$appId/$version/runtime',
    );
    return ApiResponseParser.object(resp, AppInstallConfigDto.fromJson);
  }

  /// 安装应用。
  /// POST /api/v2/apps/install
  Future<void> installApp(AppInstallReq req) async {
    await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/install',
      data: req.toJson(),
    );
  }

  Future<void> _postInstalledOp({
    required int installId,
    required int detailId,
    required String operate,
    bool favorite = false,
  }) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/installed/op',
      data: {
        'installId': installId,
        'operate': operate,
        'detailId': detailId,
        'favorite': favorite,
      },
    );
    ApiResponseParser.ok(resp);
  }

  /// 已安装应用操作（收藏 / 取消收藏等）。
  Future<void> operateInstalled({
    required int installId,
    required int detailId,
    required bool favorite,
  }) => _postInstalledOp(
    installId: installId,
    detailId: detailId,
    operate: 'favorite',
    favorite: favorite,
  );

  /// 重建已安装应用（重新创建容器）。
  Future<void> rebuildInstalled({
    required int installId,
    required int detailId,
  }) => _postInstalledOp(
    installId: installId,
    detailId: detailId,
    operate: 'rebuild',
  );

  /// 重启已安装应用。
  Future<void> restartInstalled({
    required int installId,
    required int detailId,
  }) => _postInstalledOp(
    installId: installId,
    detailId: detailId,
    operate: 'restart',
  );

  /// 停止已安装应用。
  Future<void> stopInstalled({required int installId, required int detailId}) =>
      _postInstalledOp(
        installId: installId,
        detailId: detailId,
        operate: 'stop',
      );

  /// 启动已安装应用。
  Future<void> startInstalled({
    required int installId,
    required int detailId,
  }) => _postInstalledOp(
    installId: installId,
    detailId: detailId,
    operate: 'start',
  );

  /// 重载已安装应用（如 OpenResty reload）。
  Future<void> reloadInstalled({
    required int installId,
    required int detailId,
  }) => _postInstalledOp(
    installId: installId,
    detailId: detailId,
    operate: 'reload',
  );

  /// 卸载应用。
  /// POST /api/v2/apps/installed/op
  Future<void> uninstallApp({
    required int installId,
    required int detailId,
    required String taskID,
    bool forceDelete = false,
    bool deleteBackup = false,
    bool deleteImage = false,
    bool deleteDB = true,
  }) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/installed/op',
      data: {
        'operate': 'delete',
        'installId': installId,
        'detailId': detailId,
        'taskID': taskID,
        'forceDelete': forceDelete,
        'deleteBackup': deleteBackup,
        'deleteImage': deleteImage,
        'deleteDB': deleteDB,
      },
    );
    ApiResponseParser.ok(resp);
  }

  /// 获取应用图标二进制数据。
  Future<Uint8List> getAppIcon(String appName) async {
    if (appName.trim().isEmpty) return Uint8List(0);
    final encodedName = Uri.encodeComponent(appName);
    final resp = await _client.get<List<int>>(
      '/api/v2/apps/icon/$encodedName',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = Uint8List.fromList(resp.data ?? const []);
    return _isSupportedRasterImage(bytes) ? bytes : Uint8List(0);
  }

  /// 获取可升级版本。
  /// POST /api/v2/apps/installed/update/versions
  Future<List<AppUpdateVersionDto>> getUpdateVersions(
    int appInstallID, {
    String? updateVersion,
  }) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/installed/update/versions',
      data: {
        'appInstallID': appInstallID,
        if (updateVersion != null) 'updateVersion': updateVersion,
      },
    );
    return ApiResponseParser.list(resp, AppUpdateVersionDto.fromJson);
  }

  /// 升级应用。
  /// POST /api/v2/apps/installed/op
  Future<void> upgradeApp({
    required int installId,
    required int detailId,
    required String version,
    required String dockerCompose,
    required String taskID,
    bool backup = true,
    bool pullImage = true,
  }) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/installed/op',
      data: {
        'operate': 'upgrade',
        'installId': installId,
        'detailId': detailId,
        'version': version,
        'dockerCompose': dockerCompose,
        'taskID': taskID,
        'backup': backup,
        'pullImage': pullImage,
      },
    );
    ApiResponseParser.ok(resp);
  }

  /// 忽略更新。
  /// POST /api/v2/apps/installed/ignore
  Future<void> ignoreUpdate({
    required int appId,
    required int appDetailId,
    required String scope,
  }) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/installed/ignore',
      data: {'appID': appId, 'appDetailID': appDetailId, 'scope': scope},
    );
    ApiResponseParser.ok(resp);
  }

  static bool _isSupportedRasterImage(Uint8List bytes) {
    if (bytes.length < 4) return false;

    final isPng =
        bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;
    if (isPng) return true;

    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    if (isJpeg) return true;

    final isGif =
        bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38;
    if (isGif) return true;

    final isWebp =
        bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return isWebp;
  }

  /// 同步远程应用，返回接口提示信息（若有）。
  Future<String?> syncRemoteApps(String taskID) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/sync/remote',
      data: {'taskID': taskID},
    );
    ApiResponseParser.ok(resp);
    final body = resp.data;
    if (body == null) return null;
    final msg = (body['msg'] ?? body['message'])?.toString().trim() ?? '';
    return msg.isEmpty ? null : msg;
  }

  /// 同步本地应用。
  Future<void> syncLocalApps(String taskID) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/sync/local',
      data: {'taskID': taskID},
    );
    ApiResponseParser.ok(resp);
  }

  /// 获取忽略的应用列表。
  /// GET /api/v2/apps/ignored/detail
  Future<List<AppIgnoredDto>> getIgnoredApps() async {
    final resp = await _client.get<Map<String, dynamic>>(
      '/api/v2/apps/ignored/detail',
    );
    return ApiResponseParser.list(resp, AppIgnoredDto.fromJson);
  }

  /// 取消忽略。
  /// POST /api/v2/apps/ignored/cancel
  Future<void> cancelIgnore(int id) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/ignored/cancel',
      data: {'id': id},
    );
    ApiResponseParser.ok(resp);
  }

  /// 获取应用商店配置。
  /// GET /api/v2/core/settings/apps/store/config
  Future<AppStoreConfigDto> getStoreConfig() async {
    final resp = await _client.get<Map<String, dynamic>>(
      '/api/v2/core/settings/apps/store/config',
    );
    return ApiResponseParser.object(resp, AppStoreConfigDto.fromJson);
  }

  /// 更新应用商店配置。
  /// POST /api/v2/core/settings/apps/store/update
  Future<void> updateStoreConfig({
    required String scope,
    required bool enable,
  }) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/core/settings/apps/store/update',
      data: {'scope': scope, 'status': enable ? 'Enable' : 'Disable'},
    );
    ApiResponseParser.ok(resp);
  }

  /// 获取已安装应用参数。
  /// GET /api/v2/apps/installed/params/{installId}
  Future<AppInstalledParamsDto> getInstalledParams(int installId) async {
    final resp = await _client.get<Map<String, dynamic>>(
      '/api/v2/apps/installed/params/$installId',
    );
    return ApiResponseParser.object(resp, AppInstalledParamsDto.fromJson);
  }

  /// 更新已安装应用参数。
  /// POST /api/v2/apps/installed/params/update
  Future<void> updateInstalledParams(AppInstalledParamsUpdateReq req) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/installed/params/update',
      data: req.toJson(),
    );
    ApiResponseParser.ok(resp);
  }

  /// 修改已安装应用的端口。
  /// POST /api/v2/apps/installed/port/change
  Future<void> changePort({
    required String key,
    required String name,
    required int port,
  }) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/api/v2/apps/installed/port/change',
      data: {'key': key, 'name': name, 'port': port},
    );
    ApiResponseParser.ok(resp);
  }
}
