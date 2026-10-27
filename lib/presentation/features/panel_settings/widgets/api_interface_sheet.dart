import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/localization/l10n_x.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../common/app_toast.dart';
import '../../../common/components/action_sheet_launcher.dart';
import '../../../common/components/action_sheet_scaffold.dart';
import '../../../common/components/app_action_components.dart';
import '../models/panel_settings_view_state.dart';

/// Only the locally stored connection key is available through API Key auth.
Future<void> showApiInterfaceSheet(
  BuildContext context, {
  required PanelSettingsViewState state,
}) => showActionSheet<void>(
  context: context,
  useRootNavigator: true,
  builder: (_) => _ApiInterfaceSheet(state: state),
);

class _ApiInterfaceSheet extends StatelessWidget {
  const _ApiInterfaceSheet({required this.state});

  final PanelSettingsViewState state;

  @override
  Widget build(BuildContext context) {
    final key = state.apiKey;
    final masked = key.isEmpty
        ? '—'
        : key.length <= 8
        ? '••••••••'
        : '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
    return ActionSheetScaffold(
      isAdaptive: true,
      showHandle: false,
      isFloating: true,
      panelHeader: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Row(
          children: [
            const Icon(TablerIcons.api, color: CupertinoColors.activeBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.panelSettings_apiInterface,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.label(context),
                ),
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.common_done),
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: context.l10n.panelSettings_localApiKey,
            icon: TablerIcons.key,
          ),
          AppActionGroup(
            children: [
              AppActionRow(
                title: context.l10n.panelSettings_apiKey,
                subtitle: Text(masked),
                trailing: key.isEmpty
                    ? null
                    : const Icon(TablerIcons.copy, size: 18),
                onTap: key.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: key));
                        if (context.mounted) {
                          showAppSuccessToast(
                            context.l10n.panelSettings_keyCopied,
                          );
                        }
                      },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.panelSettings_webPanelRequired,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ],
      ),
    );
  }
}
