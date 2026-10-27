import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/network/dio_client_provider.dart';
import '../../domain/repositories/database_repository.dart';
import '../../presentation/features/server_detail/providers/active_server_provider.dart';
import '../api/app_api.dart';
import '../api/database_api.dart';
import '../api/file_api.dart';
import '../dto/common/page_result.dart';
import '../dto/database/database_instance_dto.dart';
import '../dto/database/slow_log_file_dto.dart';

part 'database_repository_impl.g.dart';

/// [DatabaseRepository] 的默认实现。
class DatabaseRepositoryImpl implements DatabaseRepository {
  DatabaseRepositoryImpl(this._api, this._fileApi, this._appApi);

  final DatabaseApi _api;
  final FileApi _fileApi;
  final AppApi _appApi;

  @override
  Future<List<DatabaseInstanceDto>> listInstances(String types) =>
      _api.listInstances(types);

  @override
  Future<DatabaseCheckDto> checkInstalled({
    required String key,
    required String name,
  }) => _appApi.checkInstalledByKey(key: key, name: name);

  @override
  Future<int> getInstalledAppPort({required String type, String name = ''}) =>
      _appApi.getInstalledAppPort(type: type, name: name);

  @override
  Future<PageResult<DatabaseSearchItemDto>> searchDatabases({
    required String database,
    int page = 1,
    int pageSize = 20,
  }) =>
      _api.searchDatabases(database: database, page: page, pageSize: pageSize);

  @override
  Future<Map<String, String>> getStatus({
    required String type,
    required String name,
  }) => _api.getStatus(type: type, name: name);

  @override
  Future<PageResult<DatabaseSearchItemDto>> searchPgDatabases({
    required String database,
    int page = 1,
    int pageSize = 20,
  }) => _api.searchPgDatabases(
    database: database,
    page: page,
    pageSize: pageSize,
  );

  @override
  Future<void> loadPgFromRemote({required String database}) =>
      _api.loadPgFromRemote(database: database);

  @override
  Future<List<DBResourceDto>> checkDelete({
    required int id,
    required String type,
    required String database,
  }) => _api.checkDelete(id: id, type: type, database: database);

  @override
  Future<void> deleteDatabase({
    required int id,
    required String type,
    required String database,
    bool forceDelete = false,
    bool deleteBackup = false,
  }) => _api.deleteDatabase(
    id: id,
    type: type,
    database: database,
    forceDelete: forceDelete,
    deleteBackup: deleteBackup,
  );

  @override
  Future<void> changePassword({
    required int id,
    required String from,
    required String type,
    required String database,
    required String value,
  }) => _api.changePassword(
    id: id,
    from: from,
    type: type,
    database: database,
    value: value,
  );

  @override
  Future<void> changeAccess({
    required int id,
    required String from,
    required String type,
    required String database,
    required String value,
  }) => _api.changeAccess(
    id: id,
    from: from,
    type: type,
    database: database,
    value: value,
  );

  @override
  Future<bool> checkRemoteConnection(Map<String, dynamic> body) =>
      _api.checkRemoteConnection(body);

  @override
  Future<void> createRemoteDatabase(Map<String, dynamic> body) =>
      _api.createRemoteDatabase(body);

  @override
  Future<Map<String, dynamic>> getConnInfo({
    required String type,
    required String name,
  }) => _appApi.getInstalledConnInfo(type: type, name: name);

  @override
  Future<bool> getRemoteAccess({required String type, required String name}) =>
      _api.getRemoteAccess(type: type, name: name);

  @override
  Future<void> updateRemoteAccess({
    required String type,
    required String database,
    required bool remote,
  }) => _api.updateRemoteAccess(type: type, database: database, remote: remote);

  @override
  Future<Map<String, dynamic>> getDatabase(String name) =>
      _api.getDatabase(name);

  @override
  Future<void> updateRemoteDatabase(Map<String, dynamic> body) =>
      _api.updateRemoteDatabase(body);

  @override
  Future<void> deleteRemoteDatabase({
    required int id,
    required String database,
    bool forceDelete = false,
    bool deleteBackup = false,
  }) => _api.deleteRemoteDatabase(
    id: id,
    database: database,
    forceDelete: forceDelete,
    deleteBackup: deleteBackup,
  );

  @override
  Future<List<FormatCollationOption>> getFormatOptions(String name) =>
      _api.getFormatOptions(name);

  @override
  Future<void> createDatabase(Map<String, dynamic> body) =>
      _api.createDatabase(body);

  @override
  Future<void> createPgDatabase(Map<String, dynamic> body) =>
      _api.createPgDatabase(body);

  @override
  Future<void> loadFromRemote({
    required String from,
    required String type,
    required String database,
  }) => _api.loadFromRemote(from: from, type: type, database: database);

  @override
  Future<String> loadConfigFile({required String type, required String name}) =>
      _api.loadConfigFile(type: type, name: name);

  @override
  Future<void> updateConfigFile({
    required String type,
    required String database,
    required String file,
  }) => _api.updateConfigFile(type: type, database: database, file: file);

  @override
  Future<MysqlVariables> loadVariables({
    required String type,
    required String name,
  }) => _api.loadVariables(type: type, name: name);

  @override
  Future<void> updateVariables({
    required String type,
    required String database,
    required List<Map<String, dynamic>> variables,
  }) => _api.updateVariables(
    type: type,
    database: database,
    variables: variables,
  );

  @override
  Future<SlowLogFileDto> readSlowLog({
    required String type,
    required String name,
    int page = 1,
    bool latest = true,
  }) => _fileApi.readFile<SlowLogFileDto>(
    id: 0,
    type: '$type-slow-logs',
    name: name,
    fromJson: SlowLogFileDto.fromJson,
    page: page,
    pageSize: 500,
    latest: latest,
  );

  // ── Redis 专用 ──────────────────────────────────────────────

  @override
  Future<Map<String, String>> getRedisStatus({
    required String type,
    required String name,
  }) => _api.getRedisStatus(type: type, name: name);

  @override
  Future<RedisConfDto> getRedisConf({
    required String type,
    required String name,
  }) => _api.getRedisConf(type: type, name: name);

  @override
  Future<void> updateRedisConf({
    required String dbType,
    required String database,
    required String timeout,
    required String maxclients,
    required String maxmemory,
  }) => _api.updateRedisConf(
    dbType: dbType,
    database: database,
    timeout: timeout,
    maxclients: maxclients,
    maxmemory: maxmemory,
  );

  @override
  Future<void> changeRedisPassword({
    required String database,
    required String value,
  }) => _api.changeRedisPassword(database: database, value: value);

  @override
  Future<RedisPersistenceDto> getRedisPersistence({
    required String type,
    required String name,
  }) => _api.getRedisPersistence(type: type, name: name);

  @override
  Future<void> updateRedisAofPersistence({
    required String dbType,
    required String database,
    required String appendonly,
    required String appendfsync,
  }) => _api.updateRedisAofPersistence(
    dbType: dbType,
    database: database,
    appendonly: appendonly,
    appendfsync: appendfsync,
  );

  @override
  Future<void> updateRedisRdbPersistence({
    required String dbType,
    required String database,
    required String save,
  }) => _api.updateRedisRdbPersistence(
    dbType: dbType,
    database: database,
    save: save,
  );

  @override
  Future<void> installRedisCli() => _api.installRedisCli();
}

/// 基于当前激活服务器的仓库 Provider。
@Riverpod(dependencies: [activeServerId])
Future<DatabaseRepository> databaseRepository(Ref ref) async {
  final serverId = ref.watch(activeServerIdProvider);
  final client = await ref.watch(dioClientProvider(serverId).future);
  return DatabaseRepositoryImpl(
    DatabaseApi(client),
    FileApi(client),
    AppApi(client),
  );
}
