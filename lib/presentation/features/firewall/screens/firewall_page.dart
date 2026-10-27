import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/localization/l10n_x.dart';
import '../../../../data/dto/firewall/firewall_base_info_dto.dart';
import '../../../../data/api/unified_firewall_api.dart';
import '../../../../core/network/dio_client_provider.dart';
import '../../../../data/repositories_impl/firewall_repository_impl.dart';
import '../../../common/app_toast.dart';
import '../../../common/components/app_confirm_sheet.dart';
import '../../../common/components/app_empty_state.dart';
import '../../../common/components/app_header_search_field.dart';
import '../../../common/components/floating_tab_bar.dart';
import '../../../common/components/frosted_overlay_menu.dart';
import '../../../common/components/frosted_scaffold.dart';
import '../../server_detail/providers/active_server_provider.dart';
import '../providers/firewall_provider.dart';
import '../widgets/firewall_port_multi_select_bar.dart';
import '../widgets/ip_rule_form_sheet.dart';
import '../widgets/ip_rules_tab.dart';
import '../widgets/port_rules_tab.dart';
import 'unified_firewall_page.dart';

class FirewallPage extends StatelessWidget {
  const FirewallPage({super.key, required this.serverId});

  final int serverId;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [activeServerIdProvider.overrideWithValue(serverId)],
      child: const _FirewallRoute(),
    );
  }
}

class _FirewallRoute extends ConsumerStatefulWidget {
  const _FirewallRoute();

  @override
  ConsumerState<_FirewallRoute> createState() => _FirewallRouteState();
}

class _FirewallRouteState extends ConsumerState<_FirewallRoute> {
  late Future<(UnifiedFirewallApi, FirewallApiVersion)> _version;

  @override
  void initState() {
    super.initState();
    _version = _detect();
  }

  Future<(UnifiedFirewallApi, FirewallApiVersion)> _detect() async {
    final serverId = ref.read(activeServerIdProvider);
    final client = await ref.read(dioClientProvider(serverId).future);
    final api = UnifiedFirewallApi(client);
    final version = await api.detectVersion(refresh: true);
    return (api, version);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(UnifiedFirewallApi, FirewallApiVersion)>(
      future: _version,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return FrostedScaffold(
            title: context.l10n.firewall_title,
            body: Center(
              child: AppEmptyState(
                icon: TablerIcons.alert_circle,
                title: context.l10n.common_loadingFailed,
                subtitle: '${snapshot.error}',
                actionLabel: context.l10n.common_retry,
                onAction: () => setState(() => _version = _detect()),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return FrostedScaffold(
            title: context.l10n.firewall_title,
            body: const Center(child: CupertinoActivityIndicator()),
          );
        }
        final (api, version) = snapshot.data!;
        return version == FirewallApiVersion.unified
            ? UnifiedFirewallPage(api: api)
            : const _FirewallContent();
      },
    );
  }
}

class _FirewallContent extends ConsumerStatefulWidget {
  const _FirewallContent();

  @override
  ConsumerState<_FirewallContent> createState() => _FirewallContentState();
}

class _FirewallContentState extends ConsumerState<_FirewallContent> {
  final _portRulesController = PortRulesTabController();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  bool _isSearchMode = false;
  int _selectedTab = 0;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _portRulesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseInfoAsync = ref.watch(firewallBaseInfoProvider);
    final baseInfo = baseInfoAsync.valueOrNull;

    return FrostedScaffold(
      title: _isSearchMode ? '' : context.l10n.firewall_title,
      trailingBuilder: (isDark, isOverlapping) =>
          _buildTrailing(context, baseInfo, isDark, isOverlapping),
      body: Stack(
        children: [
          CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: FrostedScaffold.contentTopPadding(context) + 8,
                ),
              ),
              SliverToBoxAdapter(child: _buildSelectedTab(baseInfoAsync)),
              const SliverToBoxAdapter(child: SizedBox(height: 132)),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingTabBar(
              items: [
                FloatingTabItemData(
                  icon: TablerIcons.plug,
                  activeIcon: TablerIcons.plug_connected,
                  label: context.l10n.nav_portRules,
                  nativeSymbol: 'powerplug.fill',
                ),
                FloatingTabItemData(
                  icon: TablerIcons.shield,
                  activeIcon: TablerIcons.shield_check,
                  label: context.l10n.nav_ipRules,
                  nativeSymbol: 'checkmark.shield.fill',
                ),
              ],
              selectedIndex: _selectedTab,
              onTabSelected: _switchTab,
            ),
          ),
          if (_selectedTab == 0)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.fastOutSlowIn,
              left: 0,
              right: 0,
              bottom: 104,
              child: FirewallPortMultiSelectBar(
                controller: _portRulesController,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectedTab(AsyncValue<FirewallBaseInfoDto> baseInfoAsync) {
    if (baseInfoAsync.hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: AppEmptyState(
          icon: TablerIcons.alert_circle,
          title: context.l10n.firewall_loadStatusFailed,
          subtitle: baseInfoAsync.error.toString(),
          actionLabel: context.l10n.common_retry,
          onAction: () => ref.invalidate(firewallBaseInfoProvider),
          useCardStyle: false,
        ),
      );
    }
    final baseInfo = baseInfoAsync.valueOrNull;
    if (_isFirewallServiceMissing(baseInfo)) {
      return _buildFirewallServiceMissingState();
    }
    if (_selectedTab == 1) return const IpRulesTab();
    return PortRulesTab(baseInfo: baseInfo, controller: _portRulesController);
  }

  bool _isFirewallServiceMissing(FirewallBaseInfoDto? info) {
    if (info == null) return false;
    return !info.isExist && info.name.trim() == '-';
  }

  Widget _buildFirewallServiceMissingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: AppEmptyState(
        icon: TablerIcons.shield_off,
        title: context.l10n.firewall_serviceMissingTitle,
        subtitle: context.l10n.firewall_serviceMissingSubtitle,
        actionLabel: context.l10n.firewall_refreshStatus,
        onAction: () => ref.invalidate(firewallBaseInfoProvider),
        useCardStyle: false,
      ),
    );
  }

  Widget _buildTrailing(
    BuildContext context,
    FirewallBaseInfoDto? baseInfo,
    bool isDark,
    bool isOverlapping,
  ) {
    if (_isSearchMode) {
      return AppHeaderSearchField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        placeholder: _selectedTab == 0
            ? context.l10n.firewall_searchPortRules
            : context.l10n.firewall_searchIpRules,
        onChanged: _searchDebounced,
        onClear: _clearSearchOnly,
        onCancel: _exitSearchMode,
      );
    }

    return ListenableBuilder(
      listenable: _portRulesController,
      builder: (context, _) => _buildFirewallMenu(
        context,
        baseInfo: baseInfo,
        isDark: isDark,
        isOverlapping: isOverlapping,
      ),
    );
  }

  Widget _buildFirewallMenu(
    BuildContext context, {
    required FirewallBaseInfoDto? baseInfo,
    required bool isDark,
    required bool isOverlapping,
  }) {
    final info = baseInfo;
    final items = <FrostedMenuItem>[
      ...(_selectedTab == 0
          ? _buildPortRuleMenuItems()
          : _buildIpRuleMenuItems()),
    ];

    if (info != null && info.isExist) {
      final isIptables = info.name.toLowerCase() == 'iptables';
      items.add(
        FrostedMenuItem(
          text: context.l10n.firewall_serviceMenu,
          icon: TablerIcons.shield_lock,
          iconColor: CupertinoColors.activeBlue,
          action: () {},
          children: _buildServiceMenuItems(info),
        ),
      );
      if (isIptables) {
        items.add(
          FrostedMenuItem(
            text: 'iptables',
            icon: TablerIcons.link,
            iconColor: CupertinoColors.systemPurple,
            action: () {},
            children: _buildIptablesMenuItems(info),
          ),
        );
      }
    } else {
      items.add(
        FrostedMenuItem(
          text: context.l10n.firewall_refreshStatus,
          icon: TablerIcons.refresh,
          iconColor: CupertinoColors.activeBlue,
          action: _refreshFirewallStatus,
        ),
      );
    }

    return FrostedOverlayMenuButton(
      label: context.l10n.common_menu,
      items: items,
      isDark: isDark,
      isOverlapping: isOverlapping,
    );
  }

  List<FrostedMenuItem> _buildPortRuleMenuItems() {
    return [
      FrostedMenuItem(
        text: context.l10n.firewall_newPortRule,
        icon: TablerIcons.plus,
        iconColor: CupertinoColors.activeBlue,
        action: _portRulesController.createRule,
      ),
      FrostedMenuItem(
        text: context.l10n.firewall_searchPortRules,
        icon: TablerIcons.search,
        iconColor: CupertinoColors.activeBlue,
        action: _enterSearchMode,
      ),
      FrostedMenuItem(
        text: _portRulesController.selectionMode
            ? context.l10n.firewall_exitMultiSelect
            : context.l10n.firewall_selectRules,
        icon: _portRulesController.selectionMode
            ? TablerIcons.square_rounded_x
            : TablerIcons.square_rounded_check,
        iconColor: CupertinoColors.systemOrange,
        action: _portRulesController.toggleSelectionMode,
      ),
      FrostedMenuItem(
        text: _portRulesController.importing
            ? context.l10n.firewall_importing
            : context.l10n.firewall_importRules,
        icon: TablerIcons.file_import,
        iconColor: CupertinoColors.systemIndigo,
        action: _portRulesController.importing
            ? () {}
            : _portRulesController.importRules,
      ),
      FrostedMenuItem(
        text: context.l10n.firewall_filterStrategy,
        icon: TablerIcons.filter,
        iconColor: CupertinoColors.systemGrey,
        action: () {},
        children: [
          FrostedMenuItem(
            text: context.l10n.firewall_allStrategies,
            icon: TablerIcons.list,
            action: () => ref
                .read(firewallPortRulesControllerProvider.notifier)
                .search(strategy: ''),
          ),
          FrostedMenuItem(
            text: 'Accept',
            icon: TablerIcons.shield_check,
            iconColor: CupertinoColors.systemGreen,
            action: () => ref
                .read(firewallPortRulesControllerProvider.notifier)
                .search(strategy: 'accept'),
          ),
          FrostedMenuItem(
            text: 'Drop',
            icon: TablerIcons.shield_x,
            iconColor: CupertinoColors.systemRed,
            action: () => ref
                .read(firewallPortRulesControllerProvider.notifier)
                .search(strategy: 'drop'),
          ),
        ],
      ),
      FrostedMenuItem(
        text: context.l10n.firewall_refreshRules,
        icon: TablerIcons.refresh,
        action: () =>
            ref.read(firewallPortRulesControllerProvider.notifier).refresh(),
      ),
    ];
  }

  List<FrostedMenuItem> _buildIpRuleMenuItems() {
    return [
      FrostedMenuItem(
        text: context.l10n.firewall_newIpRule,
        icon: TablerIcons.plus,
        iconColor: CupertinoColors.activeBlue,
        action: _createIpRule,
      ),
      FrostedMenuItem(
        text: context.l10n.firewall_searchIpRules,
        icon: TablerIcons.search,
        iconColor: CupertinoColors.activeBlue,
        action: _enterSearchMode,
      ),
      FrostedMenuItem(
        text: context.l10n.firewall_filterStrategy,
        icon: TablerIcons.filter,
        iconColor: CupertinoColors.systemGrey,
        action: () {},
        children: [
          FrostedMenuItem(
            text: context.l10n.firewall_allStrategies,
            icon: TablerIcons.list,
            action: () => ref
                .read(firewallIpRulesControllerProvider.notifier)
                .search(strategy: ''),
          ),
          FrostedMenuItem(
            text: 'Accept',
            icon: TablerIcons.shield_check,
            iconColor: CupertinoColors.systemGreen,
            action: () => ref
                .read(firewallIpRulesControllerProvider.notifier)
                .search(strategy: 'accept'),
          ),
          FrostedMenuItem(
            text: 'Drop',
            icon: TablerIcons.shield_x,
            iconColor: CupertinoColors.systemRed,
            action: () => ref
                .read(firewallIpRulesControllerProvider.notifier)
                .search(strategy: 'drop'),
          ),
        ],
      ),
      FrostedMenuItem(
        text: context.l10n.firewall_refreshRules,
        icon: TablerIcons.refresh,
        action: () =>
            ref.read(firewallIpRulesControllerProvider.notifier).refresh(),
      ),
    ];
  }

  List<FrostedMenuItem> _buildServiceMenuItems(FirewallBaseInfoDto info) {
    final items = <FrostedMenuItem>[
      FrostedMenuItem(
        text: context.l10n.firewall_refreshStatus,
        icon: TablerIcons.refresh,
        iconColor: CupertinoColors.activeBlue,
        action: _refreshFirewallStatus,
      ),
      FrostedMenuItem(
        text: info.isActive
            ? context.l10n.firewall_stopService
            : context.l10n.firewall_startService,
        icon: info.isActive ? TablerIcons.player_stop : TablerIcons.player_play,
        iconColor: info.isActive
            ? CupertinoColors.systemRed
            : CupertinoColors.systemGreen,
        isDestructive: info.isActive,
        action: () => _confirmFirewallOperation(
          operation: info.isActive ? 'stop' : 'start',
          title: info.isActive
              ? context.l10n.firewall_stopTitle
              : context.l10n.firewall_startTitle,
          content: info.isActive
              ? context.l10n.firewall_stopContent
              : context.l10n.firewall_startContent,
          confirmText: info.isActive
              ? context.l10n.runtime_stop
              : context.l10n.runtime_start,
          confirmColor: info.isActive
              ? CupertinoColors.systemRed
              : CupertinoColors.systemGreen,
        ),
      ),
      FrostedMenuItem(
        text: context.l10n.firewall_restartService,
        icon: TablerIcons.refresh,
        iconColor: CupertinoColors.activeBlue,
        action: () => _confirmFirewallOperation(
          operation: 'restart',
          title: context.l10n.firewall_restartTitle,
          content: context.l10n.firewall_restartContent,
          confirmText: context.l10n.runtime_restart,
        ),
      ),
    ];

    if (info.pingStatus != 'None') {
      final enableBan = !info.isPingEnabled;
      items.add(
        FrostedMenuItem(
          text: enableBan
              ? context.l10n.firewall_enableBanPing
              : context.l10n.firewall_disableBanPing,
          icon: enableBan ? TablerIcons.shield_check : TablerIcons.shield_off,
          iconColor: CupertinoColors.systemOrange,
          action: () => _confirmFirewallOperation(
            operation: enableBan ? 'enableBanPing' : 'disableBanPing',
            title: enableBan
                ? context.l10n.firewall_enableBanPing
                : context.l10n.firewall_disableBanPing,
            content: enableBan
                ? context.l10n.firewall_enableBanPingContent
                : context.l10n.firewall_disableBanPingContent,
            confirmText: enableBan
                ? context.l10n.firewall_enableAction
                : context.l10n.firewall_disableAction,
            confirmColor: CupertinoColors.systemOrange,
          ),
        ),
      );
    }

    return items;
  }

  List<FrostedMenuItem> _buildIptablesMenuItems(FirewallBaseInfoDto info) {
    if (!info.isInit) {
      return [
        FrostedMenuItem(
          text: context.l10n.firewall_initBasicChain,
          icon: TablerIcons.replace,
          iconColor: CupertinoColors.systemPurple,
          action: () => _confirmFilterChainOperation(
            name: '1PANEL_BASIC',
            operate: 'init-base',
            title: context.l10n.firewall_initIptables,
            content: context.l10n.firewall_initBasicChainContent,
            confirmText: context.l10n.firewall_initIptables,
          ),
        ),
      ];
    }

    return [
      FrostedMenuItem(
        text: info.isBind
            ? context.l10n.firewall_unbindBasicChain
            : context.l10n.firewall_bindBasicChain,
        icon: info.isBind ? TablerIcons.unlink : TablerIcons.link,
        iconColor: info.isBind
            ? CupertinoColors.systemRed
            : CupertinoColors.systemPurple,
        isDestructive: info.isBind,
        action: () => _confirmFilterChainOperation(
          name: '1PANEL_BASIC',
          operate: info.isBind ? 'unbind-base' : 'bind-base',
          title: info.isBind
              ? context.l10n.firewall_unbindIptablesTitle
              : context.l10n.firewall_bindIptablesTitle,
          content: info.isBind
              ? context.l10n.firewall_unbindBasicChainContent
              : context.l10n.firewall_bindBasicChainContent,
          confirmText: info.isBind
              ? context.l10n.firewall_unbindBasicChain
              : context.l10n.firewall_bindBasicChain,
          confirmColor: info.isBind
              ? CupertinoColors.systemRed
              : CupertinoColors.systemPurple,
        ),
      ),
    ];
  }

  void _switchTab(int index) {
    if (index == _selectedTab) return;
    _exitSearchMode();
    _portRulesController.clearSelection();
    setState(() => _selectedTab = index);
  }

  void _enterSearchMode() {
    setState(() => _isSearchMode = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _exitSearchMode() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _clearSearchOnly();
    if (mounted) setState(() => _isSearchMode = false);
  }

  void _clearSearchOnly() {
    _searchDebounce?.cancel();
    if (_selectedTab == 0) {
      ref.read(firewallPortRulesControllerProvider.notifier).search(info: '');
    } else {
      ref.read(firewallIpRulesControllerProvider.notifier).search(info: '');
    }
  }

  void _searchDebounced(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final info = value.trim();
      if (_selectedTab == 0) {
        ref
            .read(firewallPortRulesControllerProvider.notifier)
            .search(info: info);
      } else {
        ref.read(firewallIpRulesControllerProvider.notifier).search(info: info);
      }
    });
  }

  void _refreshFirewallStatus() {
    ref.invalidate(firewallBaseInfoProvider);
    ref.invalidate(firewallPortRulesControllerProvider);
    ref.invalidate(firewallIpRulesControllerProvider);
  }

  Future<void> _createIpRule() async {
    await showIpRuleFormSheet(context);
  }

  Future<void> _operateFirewall(String operation) async {
    try {
      final repo = await ref.read(firewallRepositoryProvider.future);
      await repo.operate(operation);
      if (!mounted) return;
      ref.invalidate(firewallBaseInfoProvider);
      ref.invalidate(firewallPortRulesControllerProvider);
      ref.invalidate(firewallIpRulesControllerProvider);
      showAppSuccessToast(context.l10n.firewall_operationSucceeded);
    } catch (e) {
      if (!mounted) return;
      showAppErrorToast(
        context.l10n.firewall_operationFailed,
        description: e.toString(),
      );
    }
  }

  Future<void> _confirmFirewallOperation({
    required String operation,
    required String title,
    required String content,
    required String confirmText,
    CupertinoDynamicColor confirmColor = CupertinoColors.activeBlue,
  }) async {
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (_) => AppConfirmSheet(
        title: title,
        content: content,
        confirmText: confirmText,
        confirmColor: confirmColor.resolveFrom(context),
      ),
    );
    if (confirmed == true) await _operateFirewall(operation);
  }

  Future<void> _confirmFilterChainOperation({
    required String name,
    required String operate,
    required String title,
    required String content,
    required String confirmText,
    CupertinoDynamicColor confirmColor = CupertinoColors.systemPurple,
  }) async {
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (_) => AppConfirmSheet(
        title: title,
        content: content,
        confirmText: confirmText,
        confirmColor: confirmColor.resolveFrom(context),
      ),
    );
    if (confirmed != true) return;
    try {
      final repo = await ref.read(firewallRepositoryProvider.future);
      await repo.operateFilterChain(name: name, operate: operate);
      if (!mounted) return;
      ref.invalidate(firewallBaseInfoProvider);
      ref.invalidate(firewallPortRulesControllerProvider);
      ref.invalidate(firewallIpRulesControllerProvider);
      showAppSuccessToast(context.l10n.firewall_operationSucceeded);
    } catch (e) {
      if (!mounted) return;
      showAppErrorToast(
        context.l10n.firewall_operationFailed,
        description: e.toString(),
      );
    }
  }
}
