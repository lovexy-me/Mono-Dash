import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/localization/locale_controller.dart';
import '../../../../core/network/dio_client_provider.dart';
import '../../../../core/network/network_exceptions.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../core/widgets/ios_server_widget_bridge.dart';
import '../../../../data/api/dashboard_api.dart';
import '../../../../data/api/setting_api.dart';
import '../../../../data/repositories_impl/server_repository_impl.dart';
import '../../../../domain/entities/dashboard.dart';
import '../../../../domain/entities/server.dart';
import '../../../../domain/repositories/server_repository.dart';
import '../../settings/providers/app_settings_provider.dart';

part 'servers_provider.g.dart';

/// 面板列表状态。
///
/// 只负责持久化与展示，连通性测试通过 [DashboardApi.getOsInfo] 走真实 API，
/// 验证 MD5 鉴权链路是否通畅。
@riverpod
class ServersNotifier extends _$ServersNotifier {
  @override
  FutureOr<List<Server>> build() async {
    final storage = ref.watch(storageServiceProvider);
    final subscription = storage.serversChanged.listen((_) {
      ref.invalidateSelf();
    });
    ref.onDispose(subscription.cancel);

    final repo = ref.watch(serverRepositoryProvider);
    final servers = await repo.list();
    unawaited(_syncServerWidgetData(repo, servers));
    return servers;
  }

  /// Probes authentication with candidate settings before adding a panel.
  Future<void> testConnection({
    required String host,
    required int port,
    required String apiKey,
    bool isHttps = false,
    bool allowInsecureConnections = false,
    CancelToken? cancelToken,
  }) async {
    final settings = await ref.read(appSettingsControllerProvider.future);
    final client = await createProbeClient(
      host: host,
      port: port,
      apiKey: apiKey,
      isHttps: isHttps,
      requestTimeoutSeconds: settings.requestTimeoutSeconds,
      customHeaders: settings.customHeaders,
      allowInsecureConnections: allowInsecureConnections,
    );
    try {
      await DashboardApi(client).getOsInfo(cancelToken: cancelToken);
    } finally {
      client.dispose();
    }
  }

  Future<void> addServer({
    required String name,
    required String host,
    required int port,
    required String apiKey,
    bool isHttps = false,
    bool allowInsecureConnections = false,
  }) async {
    final repo = ref.read(serverRepositoryProvider);

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await repo.add(
        name: name.isEmpty ? null : name,
        host: host,
        port: port,
        isHttps: isHttps,
        allowInsecureConnections: allowInsecureConnections,
        apiKey: apiKey,
      );
      final servers = await repo.list();
      unawaited(_syncServerWidgetData(repo, servers));
      return servers;
    });
  }

  Future<void> removeServer(int id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(serverRepositoryProvider);
      await repo.remove(id);
      final servers = await repo.list();
      unawaited(IosServerWidgetBridge.removeServer(id));
      unawaited(_syncServerWidgetData(repo, servers));
      return servers;
    });
  }

  Future<void> updateServer({
    required int id,
    required String name,
    required String host,
    required int port,
    required bool isHttps,
    required bool allowInsecureConnections,
    String? apiKey,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(serverRepositoryProvider);
      final server = await repo.find(id);
      if (server == null) {
        throw StateError(
          ref.read(appLocalizationsProvider).common_serverNotFound,
        );
      }
      server
        ..name = name.isEmpty ? null : name
        ..host = host
        ..port = port
        ..isHttps = isHttps
        ..allowInsecureConnections = allowInsecureConnections;
      await repo.update(
        server,
        apiKey: apiKey != null && apiKey.isNotEmpty ? apiKey : null,
      );
      ref.invalidate(dioClientProvider(id));
      ref.invalidate(serverDashboardSnapshotProvider(id));
      final servers = await repo.list();
      unawaited(_syncServerWidgetData(repo, servers));
      return servers;
    });
  }

  Future<void> reorderServers(List<int> orderedIds) async {
    final repo = ref.read(serverRepositoryProvider);
    final current = state.valueOrNull;
    if (current != null) {
      final byId = {for (final server in current) server.id: server};
      state = AsyncValue.data([
        for (var i = 0; i < orderedIds.length; i++)
          if (byId[orderedIds[i]] case final server?) server..sortIndex = i,
      ]);
    }
    await repo.reorder(orderedIds);
    state = await AsyncValue.guard(() async {
      final servers = await repo.list();
      unawaited(_syncServerWidgetData(repo, servers));
      return servers;
    });
  }

  Future<void> _syncServerWidgetData(
    ServerRepository repo,
    List<Server> servers,
  ) async {
    final settings = await ref.read(appSettingsControllerProvider.future);
    final apiKeys = <int, String>{};
    for (final server in servers) {
      final apiKey = await repo.getApiKey(server.id);
      if (apiKey != null && apiKey.isNotEmpty) {
        apiKeys[server.id] = apiKey;
      }
    }
    await IosServerWidgetBridge.syncServers(
      servers,
      apiKeys: apiKeys,
      requestTimeoutSeconds: settings.requestTimeoutSeconds,
      customHeaders: settings.customHeaders,
      appLocaleCode: ref
          .read(localeControllerProvider)
          .widgetLocaleCode(WidgetsBinding.instance.platformDispatcher.locale),
    );
  }
}

class ServerDashboardSnapshot {
  const ServerDashboardSnapshot({
    required this.dashboard,
    required this.fetchMs,
  });

  final Dashboard dashboard;
  final int fetchMs;
}

final serverDashboardSnapshotProvider = FutureProvider.autoDispose
    .family<ServerDashboardSnapshot, int>((ref, serverId) async {
      final client = await ref.watch(dioClientProvider(serverId).future);
      final stopWatch = Stopwatch()..start();
      final dashboard = await DashboardApi(client).getDashboardSnapshot();
      final snapshot = ServerDashboardSnapshot(
        dashboard: dashboard,
        fetchMs: stopWatch.elapsedMilliseconds,
      );
      final server = await ref.read(serverRepositoryProvider).find(serverId);
      if (server != null) {
        unawaited(
          IosServerWidgetBridge.upsertSnapshot(
            server: server,
            dashboard: dashboard,
            latencyMs: snapshot.fetchMs,
          ),
        );
      }
      return snapshot;
    });

final serverMemoControllerProvider = StateNotifierProvider.autoDispose
    .family<ServerMemoController, AsyncValue<String>, int>(
      ServerMemoController.new,
      dependencies: [dioClientProvider],
    );

class ServerMemoController extends StateNotifier<AsyncValue<String>> {
  ServerMemoController(this.ref, this.serverId)
    : super(const AsyncValue.loading()) {
    unawaited(refresh());
  }

  final Ref ref;
  final int serverId;

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final client = await ref.read(dioClientProvider(serverId).future);
      try {
        return await SettingApi(client).getMemo();
      } on HttpException catch (e) {
        if (e.statusCode != 404) rethrow;
        return ref.read(storageServiceProvider).getServerMemo(serverId);
      }
    });
  }

  Future<void> save(String content) async {
    final previous = state;
    state = AsyncValue.data(content);
    try {
      final client = await ref.read(dioClientProvider(serverId).future);
      try {
        await SettingApi(client).saveMemo(content);
      } on HttpException catch (e) {
        if (e.statusCode != 404) rethrow;
        await ref
            .read(storageServiceProvider)
            .saveServerMemo(serverId, content);
      }
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}
