import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/localization/l10n_x.dart';
import '../../../common/app_toast.dart';
import '../../../common/components/app_empty_state.dart';
import '../../../common/components/frosted_scaffold.dart';
import '../../server_detail/providers/active_server_provider.dart';
import '../providers/panel_settings_provider.dart';
import '../widgets/panel_settings_components.dart';
import '../../../common/components/app_action_picker_sheet.dart';
import '../../../common/components/app_picker.dart';
import '../widgets/edit_setting_value_sheet.dart';
import '../widgets/api_interface_sheet.dart';

class PanelPage extends StatelessWidget {
  const PanelPage({super.key, required this.serverId});

  final int serverId;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [activeServerIdProvider.overrideWithValue(serverId)],
      child: const _PanelContent(),
    );
  }
}

class _PanelContent extends ConsumerWidget {
  const _PanelContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(panelSettingsControllerProvider);
    final l10n = context.l10n;

    return FrostedScaffold(
      title: l10n.panelSettings_panel,
      body: state.when(
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (e, _) => AppErrorState(
          title: l10n.common_loadingFailed,
          error: e,
          onRetry: () => ref.invalidate(panelSettingsControllerProvider),
        ),
        data: (settings) => ListView(
          padding: EdgeInsets.fromLTRB(
            0,
            FrostedScaffold.contentTopPadding(context) + 12,
            0,
            40,
          ),
          children: [
            // ── 基本信息 ──
            PanelSectionHeader(title: l10n.panelSettings_basicInfo),
            PanelGroupedBox(
              children: [
                PanelSettingsTile(
                  icon: TablerIcons.world,
                  iconColor: CupertinoColors.systemBlue,
                  title: l10n.panelSettings_defaultAccessAddress,
                  subtitle: settings.systemIP.isEmpty
                      ? l10n.panelSettings_notSet
                      : settings.systemIP,
                  onTap: () async {
                    final result = await showEditValueSheet(
                      context,
                      title: l10n.panelSettings_defaultAccessAddress,
                      initialValue: settings.systemIP,
                      placeholder:
                          l10n.panelSettings_defaultAccessAddressPlaceholder,
                      keyboardType: TextInputType.url,
                    );
                    if (result != null && context.mounted) {
                      await _updateSetting(
                        ref,
                        context,
                        'systemIP',
                        result,
                        isAgent: true,
                      );
                    }
                  },
                ),
                PanelSettingsTile(
                  icon: TablerIcons.user,
                  iconColor: CupertinoColors.systemTeal,
                  title: l10n.panelSettings_panelUsername,
                  subtitle: settings.userName.isEmpty
                      ? '--'
                      : settings.userName,
                  onTap: () =>
                      showAppErrorToast(l10n.panelSettings_webPanelRequired),
                ),
                PanelSettingsTile(
                  icon: TablerIcons.lock,
                  iconColor: CupertinoColors.systemOrange,
                  title: l10n.panelSettings_panelLoginPassword,
                  subtitle: l10n.panelSettings_changePanelLoginPassword,
                  onTap: () =>
                      showAppErrorToast(l10n.panelSettings_webPanelRequired),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── 显示设置 ──
            PanelSectionHeader(
              title: l10n.panelSettings_displaySettingsWebOnly,
            ),
            PanelGroupedBox(
              children: [
                PanelSettingsTile(
                  icon: TablerIcons.sun,
                  iconColor: CupertinoColors.systemYellow,
                  title: l10n.panelSettings_theme,
                  subtitle: settings.themeLabel(l10n),
                  onTap: () async {
                    final result = await showAppActionPickerSheet<String>(
                      context,
                      title: l10n.panelSettings_theme,
                      selectedValue: settings.theme,
                      options: [
                        AppPickerOption(
                          value: 'light',
                          label: l10n.panelSettings_themeLight,
                          icon: TablerIcons.sun,
                        ),
                        AppPickerOption(
                          value: 'dark',
                          label: l10n.panelSettings_themeDark,
                          icon: TablerIcons.moon,
                        ),
                        AppPickerOption(
                          value: 'auto',
                          label: l10n.common_systemDefault,
                          icon: TablerIcons.device_mobile,
                        ),
                      ],
                    );
                    if (result != null && context.mounted) {
                      await _updateSetting(ref, context, 'Theme', result);
                    }
                  },
                ),
                PanelSettingsTile(
                  icon: TablerIcons.language,
                  iconColor: CupertinoColors.systemIndigo,
                  title: l10n.panelSettings_language,
                  subtitle: settings.languageLabel(l10n),
                  onTap: () async {
                    final result = await showAppActionPickerSheet<String>(
                      context,
                      title: l10n.panelSettings_language,
                      selectedValue: settings.language,
                      options: [
                        AppPickerOption(
                          value: 'zh',
                          label: l10n.panelSettings_languageZh,
                        ),
                        const AppPickerOption(value: 'en', label: 'English'),
                        AppPickerOption(
                          value: 'ja',
                          label: l10n.panelSettings_languageJa,
                        ),
                        AppPickerOption(
                          value: 'ms',
                          label: l10n.panelSettings_languageMs,
                        ),
                        AppPickerOption(
                          value: 'pt-BR',
                          label: l10n.panelSettings_languagePtBr,
                        ),
                        AppPickerOption(
                          value: 'zh-Hant',
                          label: l10n.panelSettings_languageZhHant,
                        ),
                      ],
                    );
                    if (result != null && context.mounted) {
                      await _updateSetting(ref, context, 'Language', result);
                    }
                  },
                ),
                PanelSwitchTile(
                  icon: TablerIcons.layout_2,
                  iconColor: CupertinoColors.systemPurple,
                  title: l10n.panelSettings_tabNavigation,
                  subtitle: l10n.panelSettings_tabNavigationSubtitle,
                  value: settings.menuTabs,
                  onChanged: (v) => _updateSetting(
                    ref,
                    context,
                    'MenuTabs',
                    v ? 'Enable' : 'Disable',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── 安全设置 ──
            PanelSectionHeader(title: l10n.panelSettings_securitySettings),
            PanelGroupedBox(
              children: [
                PanelSettingsTile(
                  icon: TablerIcons.clock,
                  iconColor: CupertinoColors.systemRed,
                  title: l10n.panelSettings_sessionTimeout,
                  subtitle: settings.sessionTimeout <= 0
                      ? l10n.panelSettings_neverTimeout
                      : l10n.panelSettings_secondsValue(
                          settings.sessionTimeout.toString(),
                        ),
                  onTap: () async {
                    final result = await showEditValueSheet(
                      context,
                      title: l10n.panelSettings_sessionTimeout,
                      initialValue: settings.sessionTimeout <= 0
                          ? ''
                          : settings.sessionTimeout.toString(),
                      placeholder: l10n.panelSettings_sessionTimeoutPlaceholder,
                      description: l10n.panelSettings_sessionTimeoutDescription,
                      keyboardType: TextInputType.number,
                    );
                    if (result != null && context.mounted) {
                      await _updateSetting(
                        ref,
                        context,
                        'SessionTimeout',
                        result,
                      );
                    }
                  },
                ),
                PanelSwitchTile(
                  icon: TablerIcons.code,
                  iconColor: CupertinoColors.systemGrey,
                  title: l10n.panelSettings_previewProgram,
                  subtitle: l10n.panelSettings_previewProgramSubtitle,
                  value: settings.developerMode,
                  onChanged: (v) => _updateSetting(
                    ref,
                    context,
                    'DeveloperMode',
                    v ? 'Enable' : 'Disable',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── 高级设置 ──
            PanelSectionHeader(title: l10n.panelSettings_advancedSettings),
            PanelGroupedBox(
              children: [
                PanelSettingsTile(
                  icon: TablerIcons.api_app,
                  iconColor: CupertinoColors.systemGreen,
                  title: l10n.panelSettings_apiInterface,
                  subtitle: settings.apiKey.isNotEmpty
                      ? l10n.panelSettings_localApiKey
                      : l10n.panelSettings_webPanelRequired,
                  onTap: () => showApiInterfaceSheet(context, state: settings),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateSetting(
    WidgetRef ref,
    BuildContext context,
    String key,
    String value, {
    bool isAgent = false,
  }) async {
    try {
      final controller = ref.read(panelSettingsControllerProvider.notifier);
      if (isAgent) {
        await controller.updateAgentSetting(key, value);
      } else {
        await controller.updateCoreSetting(key, value);
      }
      if (context.mounted) {
        showAppSuccessToast(context.l10n.panelSettings_settingUpdated);
      }
    } catch (e) {
      if (context.mounted) {
        showAppErrorToast(
          context.l10n.panelSettings_updateFailed,
          description: e.toString(),
        );
      }
    }
  }
}
