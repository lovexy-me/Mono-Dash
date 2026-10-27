import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/localization/l10n_x.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../common/app_toast.dart';
import '../../../../data/repositories_impl/database_repository_impl.dart';
import '../../../../data/repositories_impl/server_repository_impl.dart';
import '../../app_store/screens/app_store_page.dart';
import '../widgets/database_connection_info_sheet.dart';
import '../widgets/database_create_database_sheet.dart';
import '../widgets/pg_create_database_sheet.dart';
import '../../../common/components/floating_tab_bar.dart';
import '../../../common/components/frosted_header.dart';
import '../../../common/components/in_app_browser_page.dart';
import '../../../common/components/frosted_overlay_menu.dart';
import '../../../common/components/terminal/app_terminal.dart';
import '../../server_detail/providers/active_server_provider.dart';
import '../models/database_state.dart';
import '../providers/database_provider.dart';
import '../widgets/database_list_tab.dart';
import '../widgets/settings_tab.dart';
import '../widgets/status_tab.dart';

/// MySQL / MariaDB 数据库管理页面（4 Tab：列表 / 状态 / 终端 / 设置）。
class MysqlManagementPage extends StatelessWidget {
  const MysqlManagementPage({
    super.key,
    required this.serverId,
    required this.dbType,
    required this.dbName,
    required this.dbVersion,
    required this.dbId,
    required this.dbFrom,
  });

  final int serverId;
  final String dbType;
  final String dbName;
  final String dbVersion;
  final int dbId;
  final String dbFrom;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [activeServerIdProvider.overrideWithValue(serverId)],
      child: _MysqlManagementContent(
        dbType: dbType,
        dbName: dbName,
        dbVersion: dbVersion,
        dbId: dbId,
        dbFrom: dbFrom,
      ),
    );
  }
}

class _MysqlManagementContent extends ConsumerStatefulWidget {
  const _MysqlManagementContent({
    required this.dbType,
    required this.dbName,
    required this.dbVersion,
    required this.dbId,
    required this.dbFrom,
  });

  final String dbType;
  final String dbName;
  final String dbVersion;
  final int dbId;
  final String dbFrom;

  @override
  ConsumerState<_MysqlManagementContent> createState() =>
      _MysqlManagementPageState();
}

class _MysqlManagementPageState extends ConsumerState<_MysqlManagementContent> {
  List<FloatingTabItemData> _tabItems(BuildContext context) => [
    FloatingTabItemData(
      icon: TablerIcons.list,
      activeIcon: TablerIcons.list,
      label: context.l10n.nav_list,
      nativeSymbol: 'list.bullet',
    ),
    FloatingTabItemData(
      icon: TablerIcons.chart_area_line,
      activeIcon: TablerIcons.chart_area_line,
      label: context.l10n.nav_status,
      nativeSymbol: 'chart.line.uptrend.xyaxis',
    ),
    FloatingTabItemData(
      icon: TablerIcons.terminal_2,
      activeIcon: TablerIcons.terminal_2,
      label: context.l10n.nav_terminal,
      nativeSymbol: 'terminal',
    ),
    FloatingTabItemData(
      icon: TablerIcons.settings,
      activeIcon: TablerIcons.settings,
      label: context.l10n.nav_settings,
      nativeSymbol: 'gearshape.fill',
    ),
  ];

  int _selectedIndex = 0;
  bool _isOverlapping = false;
  bool _terminalOpened = false;

  bool get _isRemote => widget.dbFrom == 'remote';

  List<FloatingTabItemData> _effectiveTabItems(BuildContext context) {
    final tabItems = _tabItems(context);
    return [
      tabItems[0], // 列表
      if (!_isRemote && !_isPg) tabItems[1], // 状态（远程/PG 隐藏）
      if (!_isRemote) tabItems[2], // 终端（远程隐藏）
      tabItems[3], // 设置
    ];
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTabItems = _effectiveTabItems(context);
    // Remote instances skip runtime checks and use a synthetic running state.
    final state = _isRemote
        ? const AsyncData<DatabaseManagementState>(DatabaseManagementState())
        : ref.watch(
            databaseManagementControllerProvider(widget.dbType, widget.dbName),
          );

    return CupertinoPageScaffold(
      backgroundColor: AppColors.background(context),
      child: Stack(
        children: [
          // 内容区域
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.depth != 0) return false;
              final isOverlapping = notification.metrics.pixels > 10;
              if (isOverlapping != _isOverlapping) {
                setState(() => _isOverlapping = isOverlapping);
              }
              return false;
            },
            child: _buildSelectedTab(state),
          ),

          // 顶部导航栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FrostedHeader(
              title: widget.dbName,
              onBack: () => Navigator.of(context).maybePop(),
              isOverlapping: _isOverlapping,
              trailingBuilder: (isDark, isOverlapping) =>
                  FrostedOverlayMenuButton(
                    label: context.l10n.databases_manage,
                    isDark: isDark,
                    isOverlapping: isOverlapping,
                    items: [
                      FrostedMenuItem(
                        text: context.l10n.databases_new,
                        icon: TablerIcons.plus,
                        action: () {
                          void onSuccess() => ref.invalidate(
                            _isPg
                                ? pgDatabaseListProvider((
                                    dbType: widget.dbType,
                                    dbName: widget.dbName,
                                  ))
                                : mysqlDatabaseListProvider((
                                    dbType: widget.dbType,
                                    dbName: widget.dbName,
                                  )),
                          );
                          if (_isPg) {
                            showPgCreateDatabaseSheet(
                              context,
                              dbType: widget.dbType,
                              dbName: widget.dbName,
                              dbFrom: widget.dbFrom,
                              onSuccess: onSuccess,
                            );
                          } else {
                            showCreateDatabaseSheet(
                              context,
                              dbType: widget.dbType,
                              dbName: widget.dbName,
                              dbFrom: widget.dbFrom,
                              onSuccess: onSuccess,
                            );
                          }
                        },
                      ),
                      FrostedMenuItem(
                        text: context.l10n.databases_syncFromServer,
                        icon: TablerIcons.refresh,
                        action: _syncFromServer,
                      ),
                      FrostedMenuItem(
                        text: context.l10n.databases_viewConnectionInfo,
                        icon: TablerIcons.link,
                        action: () => showDatabaseConnectionInfoSheet(
                          context,
                          dbType: widget.dbType,
                          dbName: widget.dbName,
                          dbId: widget.dbId,
                          dbFrom: widget.dbFrom,
                          isRemote: _isRemote,
                        ),
                      ),
                      if (_isPg)
                        FrostedMenuItem(
                          text: 'pgAdmin 4',
                          icon: TablerIcons.world,
                          action: () => _openDatabaseManager(
                            appKey: 'pgadmin4',
                            displayName: 'pgAdmin 4',
                          ),
                        ),
                      if (!_isPg)
                        FrostedMenuItem(
                          text: 'phpMyAdmin',
                          icon: TablerIcons.world,
                          action: () => _openDatabaseManager(
                            appKey: 'phpmyadmin',
                            displayName: 'phpMyAdmin',
                          ),
                        ),
                      if (!_isPg)
                        FrostedMenuItem(
                          text: 'Adminer',
                          icon: TablerIcons.world,
                          action: () => _openDatabaseManager(
                            appKey: 'adminer',
                            displayName: 'Adminer',
                          ),
                        ),
                    ],
                  ),
            ),
          ),

          // 底部 Tab 栏
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: FloatingTabBar(
              items: effectiveTabItems,
              selectedIndex: _isRemote
                  ? _selectedIndex
                  : _isPg && _selectedIndex >= 2
                  ? _selectedIndex - 1
                  : _selectedIndex,
              onTabSelected: (index) {
                if (_isRemote) {
                  // 远程：0=列表, 1=设置，直接映射
                  setState(() => _selectedIndex = index);
                  return;
                }
                // 本地：映射回原始索引 (0:列表, 1:状态, 2:终端, 3:设置)
                var originalIndex = index;
                if (_isPg && index >= 1) {
                  originalIndex = index + 1;
                }
                if (originalIndex == 2) {
                  _openTerminal();
                  return;
                }
                setState(() => _selectedIndex = originalIndex);
              },
            ),
          ),
        ],
      ),
    );
  }

  bool get _isPg => widget.dbType.contains('postgresql');

  String get _dbDisplayName => switch (widget.dbType) {
    'mariadb' => 'MariaDB',
    _ when _isPg => 'PostgreSQL',
    _ => 'MySQL',
  };

  Future<void> _openDatabaseManager({
    required String appKey,
    required String displayName,
  }) async {
    try {
      final repo = await ref.read(databaseRepositoryProvider.future);
      final port = await repo.getInstalledAppPort(type: appKey);
      if (!mounted) return;

      if (port <= 0) {
        final openStore = await showCupertinoDialog<bool>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: Text(
              context.l10n.databases_managerNotInstalled(displayName),
            ),
            content: Text(context.l10n.databases_managerInstallPrompt),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.l10n.common_cancel),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(context.l10n.databases_goToAppStore),
              ),
            ],
          ),
        );
        if (openStore == true && mounted) {
          final serverId = ref.read(activeServerIdProvider);
          await Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => AppStorePage(serverId: serverId),
            ),
          );
        }
        return;
      }

      final serverId = ref.read(activeServerIdProvider);
      final server = await ref.read(serverRepositoryProvider).find(serverId);
      if (!mounted) return;
      if (server == null) {
        throw StateError(context.l10n.databases_serverAddressUnavailable);
      }
      final uri = Uri(scheme: 'http', host: server.host, port: port);
      await Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => InAppBrowserPage(title: displayName, initialUrl: uri),
        ),
      );
    } catch (e) {
      if (mounted) {
        showAppErrorToast(
          context.l10n.databases_openManagerFailed(displayName),
          description: '$e',
        );
      }
    }
  }

  Future<void> _syncFromServer() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(context.l10n.databases_syncFromServer),
        content: Text(
          context.l10n.databases_syncFromServerConfirm(_dbDisplayName),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_cancel),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.databases_sync),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = await ref.read(databaseRepositoryProvider.future);
      if (_isPg) {
        await repo.loadPgFromRemote(database: widget.dbName);
      } else {
        await repo.loadFromRemote(
          from: widget.dbFrom,
          type: widget.dbType,
          database: widget.dbName,
        );
      }

      if (mounted) {
        showAppSuccessToast(context.l10n.databases_syncCompleted);
        ref.invalidate(
          _isPg
              ? pgDatabaseListProvider((
                  dbType: widget.dbType,
                  dbName: widget.dbName,
                ))
              : mysqlDatabaseListProvider((
                  dbType: widget.dbType,
                  dbName: widget.dbName,
                )),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppErrorToast(context.l10n.databases_syncFailed, description: '$e');
      }
    }
  }

  void _openTerminal() {
    if (_terminalOpened) return;
    _terminalOpened = true;

    showAppTerminal(
      context,
      containerId: widget.dbName,
      command: 'bash',
      source: 'database',
      databaseType: widget.dbType,
      databaseName: widget.dbName,
    ).then((_) {
      _terminalOpened = false;
    });
  }

  Widget _buildSelectedTab(AsyncValue<DatabaseManagementState> state) {
    if (_isRemote) {
      return switch (_selectedIndex) {
        0 => DatabaseListTab(
          dbType: widget.dbType,
          dbName: widget.dbName,
          checkState: state,
          isPg: _isPg,
          isRemote: true,
          onRefresh: () => ref.invalidate(
            mysqlDatabaseListProvider((
              dbType: widget.dbType,
              dbName: widget.dbName,
            )),
          ),
        ),
        _ => SettingsTab(
          dbType: widget.dbType,
          dbName: widget.dbName,
          checkState: state,
          isRemote: true,
          dbId: widget.dbId,
        ),
      };
    }
    return switch (_selectedIndex) {
      0 => DatabaseListTab(
        dbType: widget.dbType,
        dbName: widget.dbName,
        checkState: state,
        isPg: _isPg,
        onRefresh: () => ref.invalidate(
          _isPg
              ? pgDatabaseListProvider((
                  dbType: widget.dbType,
                  dbName: widget.dbName,
                ))
              : mysqlDatabaseListProvider((
                  dbType: widget.dbType,
                  dbName: widget.dbName,
                )),
        ),
      ),
      1 => StatusTab(
        dbType: widget.dbType,
        dbName: widget.dbName,
        checkState: state,
      ),
      _ => SettingsTab(
        dbType: widget.dbType,
        dbName: widget.dbName,
        checkState: state,
      ),
    };
  }
}
