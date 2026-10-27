import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../data/repositories_impl/setting_repository_impl.dart';
import '../../../../core/storage/storage_service.dart';
import '../../server_detail/providers/active_server_provider.dart';
import '../models/panel_settings_view_state.dart';

part 'panel_settings_provider.g.dart';

@Riverpod(dependencies: [settingRepository])
class PanelSettingsController extends _$PanelSettingsController {
  @override
  Future<PanelSettingsViewState> build() async {
    final repo = await ref.watch(settingRepositoryProvider.future);
    final results = await Future.wait([
      repo.searchSettings(),
      repo.searchCoreSettings(),
    ]);
    final state = PanelSettingsViewState.fromSettings(results[0], results[1]);
    final serverId = ref.read(activeServerIdProvider);
    final localApiKey = await ref
        .read(storageServiceProvider)
        .getApiKey(serverId);
    return state.copyWith(apiKey: localApiKey ?? '');
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// 更新 Core 侧配置并刷新本地状态。
  Future<void> updateCoreSetting(String key, String value) async {
    final repo = await ref.read(settingRepositoryProvider.future);
    await repo.updateCoreSetting(key: key, value: value);
    _applyLocalUpdate(key, value);
  }

  /// 更新 Agent 侧配置并刷新本地状态。
  Future<void> updateAgentSetting(String key, String value) async {
    final repo = await ref.read(settingRepositoryProvider.future);
    await repo.updateSetting(key: key, value: value);
    _applyLocalUpdate(key, value);
  }

  /// 更新面板登录密码。
  Future<void> updatePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final repo = await ref.read(settingRepositoryProvider.future);
    await repo.updatePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
  }

  /// 生成新的 API 密钥。
  Future<String> generateApiKey() async {
    final repo = await ref.read(settingRepositoryProvider.future);
    final newKey = await repo.generateApiKey();
    final prev = state.valueOrNull;
    if (prev != null) {
      state = AsyncValue.data(prev.copyWith(apiKey: newKey));

      // 同步到本地存储
      final serverId = ref.read(activeServerIdProvider);
      final storage = ref.read(storageServiceProvider);
      await storage.saveApiKey(serverId, newKey);
    }
    return newKey;
  }

  /// 更新 API 接口配置。
  Future<void> updateApiConfig({
    required String apiKey,
    required String ipWhiteList,
    required String apiInterfaceStatus,
    required int apiKeyValidityTime,
  }) async {
    final repo = await ref.read(settingRepositoryProvider.future);
    await repo.updateApiConfig({
      'apiKey': apiKey,
      'ipWhiteList': ipWhiteList,
      'apiInterfaceStatus': apiInterfaceStatus,
      'apiKeyValidityTime': apiKeyValidityTime,
    });

    final prev = state.valueOrNull;
    if (prev != null) {
      // 如果 API Key 发生了变化，同步到本地存储
      if (prev.apiKey != apiKey) {
        final serverId = ref.read(activeServerIdProvider);
        final storage = ref.read(storageServiceProvider);
        await storage.saveApiKey(serverId, apiKey);
      }

      state = AsyncValue.data(
        prev.copyWith(
          apiKey: apiKey,
          ipWhiteList: ipWhiteList,
          apiInterfaceStatus: apiInterfaceStatus,
          apiKeyValidityTime: apiKeyValidityTime,
        ),
      );
    }
  }

  void _applyLocalUpdate(String key, String value) {
    final prev = state.valueOrNull;
    if (prev == null) return;
    switch (key) {
      case 'userName':
      case 'UserName':
        state = AsyncValue.data(prev.copyWith(userName: value));
      case 'theme':
      case 'Theme':
        state = AsyncValue.data(prev.copyWith(theme: value));
      case 'language':
      case 'Language':
        state = AsyncValue.data(prev.copyWith(language: value));
      case 'sessionTimeout':
      case 'SessionTimeout':
        state = AsyncValue.data(
          prev.copyWith(sessionTimeout: int.tryParse(value) ?? 0),
        );
      case 'developerMode':
      case 'DeveloperMode':
        state = AsyncValue.data(
          prev.copyWith(developerMode: value.toLowerCase() == 'enable'),
        );
      case 'menuTabs':
      case 'MenuTabs':
        state = AsyncValue.data(
          prev.copyWith(menuTabs: value.toLowerCase() != 'disable'),
        );
      case 'systemIP':
        state = AsyncValue.data(prev.copyWith(systemIP: value));
      default:
        break;
    }
  }
}
