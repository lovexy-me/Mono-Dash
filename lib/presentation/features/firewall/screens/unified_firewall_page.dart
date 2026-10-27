import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/localization/l10n_x.dart';
import '../../../../core/network/network_exceptions.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/api/unified_firewall_api.dart';
import '../../../../data/dto/firewall/firewall_base_info_dto.dart';
import '../../../../data/dto/firewall/unified_firewall_dto.dart';
import '../../../common/app_toast.dart';
import '../../../common/components/action_sheet_launcher.dart';
import '../../../common/components/action_sheet_scaffold.dart';
import '../../../common/components/app_action_components.dart';
import '../../../common/components/app_confirm_sheet.dart';
import '../../../common/components/app_empty_state.dart';
import '../../../common/components/app_header_search_field.dart';
import '../../../common/components/app_picker.dart';
import '../../../common/components/cupertino_grouped_form.dart';
import '../../../common/components/frosted_overlay_menu.dart';
import '../../../common/components/frosted_scaffold.dart';
import '../../../common/components/task_log_sheet.dart';

class UnifiedFirewallPage extends ConsumerStatefulWidget {
  const UnifiedFirewallPage({super.key, required this.api});

  final UnifiedFirewallApi api;

  @override
  ConsumerState<UnifiedFirewallPage> createState() =>
      _UnifiedFirewallPageState();
}

class _UnifiedFirewallPageState extends ConsumerState<UnifiedFirewallPage> {
  final _search = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isSearching = false;
  Timer? _searchTimer;
  FirewallBaseInfoDto? _base;
  UnifiedFirewallInventory? _inventory;
  Object? _error;
  bool _loading = true;
  int _page = 1;
  static const _pageSize = 30;
  String _family = '';
  String _action = '';
  int _loadSerial = 0;
  bool _selectionMode = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  bool get _ready {
    final base = _base;
    if (base == null || !base.isExist) return false;
    if (base.name == 'iptables' || base.name == 'nftables') {
      return base.isInit && base.isBind;
    }
    return base.isActive;
  }

  Future<void> _load({bool refresh = false}) async {
    if (!mounted) return;
    final serial = ++_loadSerial;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = await widget.api.loadBase();
      final inventory =
          !base.isExist ||
              ((base.name == 'iptables' || base.name == 'nftables')
                  ? !(base.isInit && base.isBind)
                  : !base.isActive)
          ? null
          : await widget.api.search(
              provider: base.name,
              page: _page,
              pageSize: _pageSize,
              info: _search.text.trim(),
              families: _family.isEmpty ? [] : [_family],
              actions: _action.isEmpty ? [] : [_action],
              refresh: refresh,
            );
      if (!mounted || serial != _loadSerial) return;
      setState(() {
        _base = base;
        _inventory = inventory;
        _loading = false;
        if (inventory != null) {
          final available = inventory.items.map(_selectionKey).toSet();
          _selected.removeWhere((key) => !available.contains(key));
        }
      });
    } catch (error) {
      if (!mounted || serial != _loadSerial) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _queueSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 400), () {
      _page = 1;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final base = _base;
    final inventory = _inventory;
    return FrostedScaffold(
      title: _isSearching ? '' : l10n.firewall_title,
      showBackButton: !_isSearching,
      trailingBuilder: (isDark, isOverlapping) => _isSearching
          ? AppHeaderSearchField(
              controller: _search,
              focusNode: _searchFocusNode,
              placeholder: l10n.firewall_searchPortRules,
              onChanged: _queueSearch,
              onSubmitted: (_) {
                _searchTimer?.cancel();
                _page = 1;
                _load();
              },
              onClear: () {
                _searchTimer?.cancel();
                _page = 1;
                _load();
              },
              onCancel: () {
                _searchTimer?.cancel();
                setState(() {
                  _isSearching = false;
                  _search.clear();
                });
                _page = 1;
                _load();
              },
            )
          : FrostedOverlayMenuButton(
              label: l10n.common_menu,
              isDark: isDark,
              isOverlapping: isOverlapping,
              items: [
                if (_ready) ...[
                  FrostedMenuItem(
                    text: l10n.firewall_searchPortRules,
                    icon: TablerIcons.search,
                    action: () {
                      setState(() => _isSearching = true);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _searchFocusNode.requestFocus();
                      });
                    },
                  ),
                  FrostedMenuItem(
                    text: l10n.firewall_familyFilter,
                    icon: TablerIcons.world,
                    action: () {},
                    children: [
                      for (final entry in {
                        '': l10n.firewall_allFamilies,
                        'ipv4': 'IPv4',
                        'ipv6': 'IPv6',
                      }.entries)
                        FrostedMenuItem(
                          text: entry.value,
                          icon: _family == entry.key
                              ? TablerIcons.check
                              : TablerIcons.circle,
                          action: () => _setFamily(entry.key),
                        ),
                    ],
                  ),
                  FrostedMenuItem(
                    text: l10n.firewall_filterStrategy,
                    icon: TablerIcons.filter,
                    action: () {},
                    children: [
                      for (final entry in {
                        '': l10n.firewall_allStrategies,
                        'accept': l10n.firewall_acceptLabel,
                        'deny': l10n.firewall_dropLabel,
                      }.entries)
                        FrostedMenuItem(
                          text: entry.value,
                          icon: _action == entry.key
                              ? TablerIcons.check
                              : TablerIcons.circle,
                          action: () => _setAction(entry.key),
                        ),
                    ],
                  ),
                ],
                if (base != null)
                  FrostedMenuItem(
                    text: l10n.firewall_serviceMenu,
                    icon: _ready
                        ? TablerIcons.shield_check
                        : TablerIcons.shield_off,
                    action: () => _showStatusActions(base),
                  ),
                if (_ready) ...[
                  FrostedMenuItem(
                    text: l10n.firewall_createRule,
                    icon: TablerIcons.plus,
                    action: _create,
                  ),
                  FrostedMenuItem(
                    text: l10n.firewall_importRules,
                    icon: TablerIcons.file_import,
                    iconColor: CupertinoColors.systemIndigo,
                    action: _importRules,
                  ),
                  FrostedMenuItem(
                    text: _selectionMode
                        ? l10n.firewall_exitMultiSelect
                        : l10n.firewall_selectRules,
                    icon: TablerIcons.square_rounded_check,
                    iconColor: CupertinoColors.systemOrange,
                    action: () => setState(() {
                      _selectionMode = !_selectionMode;
                      if (!_selectionMode) _selected.clear();
                    }),
                  ),
                ],
                FrostedMenuItem(
                  text: l10n.firewall_refreshRules,
                  icon: TablerIcons.refresh,
                  action: () => _load(refresh: true),
                ),
              ],
            ),
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: FrostedScaffold.contentTopPadding(context) + 12,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 130),
            sliver: SliverList.list(
              children: [
                if (_loading && inventory == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 56),
                    child: Center(child: CupertinoActivityIndicator()),
                  ),
                if (_error != null)
                  AppEmptyState(
                    icon: TablerIcons.alert_circle,
                    title: l10n.common_loadingFailed,
                    subtitle: '$_error',
                    actionLabel: l10n.common_retry,
                    onAction: () => _load(refresh: true),
                  ),
                if (base != null && !_ready && _error == null)
                  AppEmptyState(
                    icon: TablerIcons.shield_off,
                    title: base.isExist
                        ? l10n.firewall_notStarted
                        : l10n.firewall_notDetected,
                    subtitle:
                        base.isExist &&
                            (base.name == 'iptables' || base.name == 'nftables')
                        ? base.isInit
                              ? l10n.firewall_bindBasicChainContent
                              : l10n.firewall_initializeFirst
                        : '',
                    actionLabel: l10n.common_refresh,
                    onAction: () => _load(refresh: true),
                  ),
                if (_ready && _error == null) ...[
                  if (_selectionMode) ...[
                    _selectionBar(),
                    const SizedBox(height: 10),
                  ],
                  if (inventory != null && inventory.notices.isNotEmpty)
                    _noticeCard(inventory.notices),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CupertinoActivityIndicator()),
                    )
                  else if (inventory?.items.isEmpty ?? true)
                    AppEmptyState(
                      icon: TablerIcons.shield,
                      title: l10n.firewall_noPortRules,
                      subtitle: l10n.firewall_noPortRulesSubtitle,
                    )
                  else ...[
                    for (final item in inventory!.items) _ruleCard(item),
                    const SizedBox(height: 6),
                    _pagination(inventory),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(FirewallBaseInfoDto base) {
    final active = _ready;
    final color =
        (active ? CupertinoColors.systemGreen : CupertinoColors.systemOrange)
            .resolveFrom(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        color: AppColors.secondaryBackground(context).withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.separator(context).withValues(alpha: 0.14),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              active ? TablerIcons.shield_check : TablerIcons.shield_off,
              size: 21,
              color: color,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  base.name == '-' ? context.l10n.firewall_title : base.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.label(context),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  base.lifecycleTaskID.isNotEmpty
                      ? context.l10n.firewall_operationInProgress
                      : !base.isExist
                      ? context.l10n.firewall_notDetected
                      : active
                      ? context.l10n.panelSettings_enabled
                      : context.l10n.firewall_notStarted,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                if (base.reason.isNotEmpty || base.syncError.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      base.reason,
                      base.syncError,
                    ].where((value) => value.isNotEmpty).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.tertiaryLabel(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _setFamily(String value) {
    if (_family == value) return;
    setState(() => _family = value);
    _page = 1;
    _load();
  }

  void _setAction(String value) {
    if (_action == value) return;
    setState(() => _action = value);
    _page = 1;
    _load();
  }

  Widget _noticeCard(List<String> notices) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: CupertinoColors.systemOrange
          .resolveFrom(context)
          .withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          TablerIcons.alert_circle,
          size: 17,
          color: CupertinoColors.systemOrange.resolveFrom(context),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            notices.map(_noticeLabel).join('\n'),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
      ],
    ),
  );

  String _noticeLabel(String code) => switch (code) {
    'family_unavailable' => context.l10n.firewall_noticeFamilyUnavailable,
    'default_scope_mismatch' =>
      context.l10n.firewall_noticeDefaultScopeMismatch,
    'managed_scope_inactive' =>
      context.l10n.firewall_noticeManagedScopeInactive,
    'unmanaged_active_scopes' => context.l10n.firewall_noticeUnmanagedScopes,
    'runtime_permanent_mismatch' => context.l10n.firewall_noticeRuntimeMismatch,
    'default_policy' => context.l10n.firewall_noticeDefaultPolicy,
    'managed_scope_missing' => context.l10n.firewall_noticeManagedScopeMissing,
    _ => code.replaceAll('_', ' '),
  };

  String _selectionKey(UnifiedFirewallItem item) => item.uuid.isNotEmpty
      ? item.uuid
      : jsonEncode({
          'scope': item.rule.scope,
          'instanceKey': item.observed['instanceKey'],
          'rule': item.rule.json,
        });

  List<UnifiedFirewallItem> get _selectedItems =>
      _inventory?.items
          .where((item) => _selected.contains(_selectionKey(item)))
          .toList() ??
      const [];

  Widget _selectionBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: CupertinoColors.activeBlue
          .resolveFrom(context)
          .withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(
          TablerIcons.checkbox,
          size: 19,
          color: CupertinoColors.activeBlue.resolveFrom(context),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.l10n.firewall_selectedRules(_selected.length),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.label(context),
            ),
          ),
        ),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(30, 32),
          onPressed: _selected.isEmpty ? null : _exportSelected,
          child: Icon(
            TablerIcons.file_export,
            size: 19,
            color: CupertinoColors.activeBlue.resolveFrom(context),
          ),
        ),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(30, 32),
          onPressed: _selectedItems.any((item) => item.canDelete)
              ? _deleteSelected
              : null,
          child: const Icon(
            TablerIcons.trash,
            size: 19,
            color: CupertinoColors.systemRed,
          ),
        ),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(30, 32),
          onPressed: () => setState(() {
            _selectionMode = false;
            _selected.clear();
          }),
          child: Icon(
            TablerIcons.x,
            size: 19,
            color: AppColors.secondaryLabel(context),
          ),
        ),
      ],
    ),
  );

  Future<void> _deleteSelected() async {
    final items = _selectedItems.where((item) => item.canDelete).toList();
    if (items.isEmpty) return;
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => AppConfirmSheet(
        title: context.l10n.firewall_batchDeleteTitle,
        content: context.l10n.firewall_batchDeleteContent(items.length),
        confirmText: context.l10n.common_delete,
        confirmColor: CupertinoColors.systemRed,
      ),
    );
    if (confirmed != true) return;
    try {
      final task = await widget.api.delete(items);
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _selectionMode = false;
      });
      await _showTask(task.taskID);
    } catch (error) {
      if (mounted) {
        showAppErrorToast(
          context.l10n.firewall_batchDeleteFailed,
          description: '$error',
        );
      }
    }
  }

  Future<void> _exportSelected() async {
    final items = _selectedItems;
    if (items.isEmpty) return;
    try {
      final rows = items
          .map(
            (item) => {
              'family': item.rule.family,
              'address': item.rule.sourceAddress,
              'port': item.rule.destinationPort,
              'protocol': item.rule.protocol,
              'strategy': item.rule.action,
              'description': item.rule.description,
            },
          )
          .toList();
      final name =
          '1panel-firewall-rules-${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${(await getTemporaryDirectory()).path}/$name');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(rows),
      );
      await SharePlus.instance.share(
        ShareParams(
          title: name,
          subject: name,
          files: [XFile(file.path, mimeType: 'application/json')],
          fileNameOverrides: [name],
        ),
      );
    } on MissingPluginException {
      if (mounted) showAppErrorToast(context.l10n.taskLog_sharePluginMissing);
    } catch (error) {
      if (mounted) {
        showAppErrorToast(
          context.l10n.firewall_exportFailed,
          description: '$error',
        );
      }
    }
  }

  Future<void> _importRules() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty || !mounted) return;
      final file = picked.files.single;
      final content = file.bytes != null
          ? utf8.decode(file.bytes!)
          : await File(file.path!).readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! List) {
        throw const FormatException('JSON root must be an array');
      }
      final rules = <Map<String, dynamic>>[];
      for (final row in decoded) {
        if (row is! Map) throw const FormatException('Rule must be an object');
        final input = _RuleInput(
          addresses: '${row['address'] ?? ''}',
          ports: '${row['port'] ?? ''}',
          protocol: '${row['protocol'] ?? ''}',
          action: '${row['strategy'] ?? ''}',
          description: '${row['description'] ?? ''}',
          family: '${row['family'] ?? 'ipv4'}',
        );
        if ((input.ports.trim().isEmpty && input.addresses.trim().isEmpty) ||
            !{'tcp', 'udp', 'tcp/udp', 'all'}.contains(input.protocol) ||
            !{'accept', 'drop'}.contains(input.action)) {
          throw const FormatException('Invalid rule in import file');
        }
        rules.addAll(input.createRules(_base!.name));
        if (rules.length > 500) throw const FormatException('Too many rules');
      }
      if (rules.isEmpty) return;
      if (!mounted) return;
      final confirmed = await showCupertinoModalPopup<bool>(
        context: context,
        builder: (context) => AppConfirmSheet(
          title: context.l10n.firewall_importPortRules,
          content: context.l10n.firewall_importCount(rules.length),
          confirmText: context.l10n.firewall_importRules,
        ),
      );
      if (confirmed != true) return;
      final task = await widget.api.create(rules, sourceKind: 'imported');
      if (!mounted) return;
      await _showTask(task.taskID);
    } catch (error) {
      if (mounted) {
        showAppErrorToast(
          context.l10n.firewall_importFailed,
          description: '$error',
        );
      }
    }
  }

  Widget _ruleCard(UnifiedFirewallItem item) {
    final rule = item.rule;
    final accepted = rule.action == 'accept';
    final color =
        (accepted ? CupertinoColors.systemGreen : CupertinoColors.systemRed)
            .resolveFrom(context);
    final hasPort = rule.destinationPort.isNotEmpty;
    final selected = _selected.contains(_selectionKey(item));
    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: 0.9,
      onPressed: () {
        if (_selectionMode) {
          setState(() {
            final key = _selectionKey(item);
            if (!_selected.add(key)) _selected.remove(key);
          });
        } else {
          _showRuleActions(item);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.secondaryBackground(context).withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? CupertinoColors.activeBlue
                      .resolveFrom(context)
                      .withValues(alpha: 0.45)
                : AppColors.separator(context).withValues(alpha: 0.14),
            width: selected ? 1 : 0.5,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    hasPort
                        ? accepted
                              ? TablerIcons.plug_connected
                              : TablerIcons.plug_x
                        : accepted
                        ? TablerIcons.shield_check
                        : TablerIcons.shield_x,
                    size: 18,
                    color: color,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    hasPort
                        ? rule.destinationPort
                        : (rule.sourceAddress.isEmpty
                              ? context.l10n.firewall_allAddresses
                              : rule.sourceAddress),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: AppColors.label(context),
                    ),
                  ),
                ),
                _badge(
                  accepted
                      ? context.l10n.firewall_acceptLabel
                      : context.l10n.firewall_dropLabel,
                  color,
                ),
                const SizedBox(width: 9),
                Icon(
                  _selectionMode
                      ? selected
                            ? TablerIcons.circle_check_filled
                            : TablerIcons.circle
                      : item.canEdit || item.canEditDescription
                      ? TablerIcons.edit
                      : item.canAdopt
                      ? TablerIcons.link
                      : TablerIcons.lock,
                  size: _selectionMode ? 21 : 17,
                  color: _selectionMode && selected
                      ? CupertinoColors.activeBlue.resolveFrom(context)
                      : AppColors.tertiaryLabel(context),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                height: 0.5,
                color: AppColors.separator(context).withValues(alpha: 0.1),
              ),
            ),
            _ruleInfoLine(
              TablerIcons.protocol,
              context.l10n.firewall_protocolLabel,
              rule.protocol.toUpperCase(),
            ),
            const SizedBox(height: 8),
            _ruleInfoLine(
              TablerIcons.world,
              context.l10n.firewall_sourceLabel,
              rule.sourceAddress.isEmpty
                  ? context.l10n.firewall_allAddresses
                  : rule.sourceAddress,
            ),
            if (rule.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ruleInfoLine(
                TablerIcons.file_text,
                context.l10n.firewall_descriptionLabel,
                rule.description,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  rule.family.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.tertiaryLabel(context),
                  ),
                ),
                const Spacer(),
                _badge(
                  _stateLabel(item.state),
                  _stateColor(item.state),
                  small: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ruleInfoLine(IconData icon, String label, String value) => Row(
    children: [
      Icon(icon, size: 15, color: AppColors.tertiaryLabel(context)),
      const SizedBox(width: 10),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.secondaryLabel(context),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.label(context),
          ),
        ),
      ),
    ],
  );

  Widget _badge(String label, Color color, {bool small = false}) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: small ? 7 : 8,
      vertical: small ? 3 : 4,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: small ? 10 : 11,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );

  Color _stateColor(String state) => switch (state) {
    'protected' => CupertinoColors.systemOrange.resolveFrom(context),
    'drifted' => CupertinoColors.systemRed.resolveFrom(context),
    'external' => CupertinoColors.systemGrey.resolveFrom(context),
    _ => CupertinoColors.activeBlue.resolveFrom(context),
  };

  String _stateLabel(String state) => switch (state) {
    'managed' => context.l10n.firewall_stateManaged,
    'adopted' => context.l10n.firewall_stateAdopted,
    'external' => context.l10n.firewall_stateExternal,
    'drifted' => context.l10n.firewall_stateDrifted,
    'protected' => context.l10n.firewall_stateProtected,
    _ => state,
  };

  Widget _pagination(UnifiedFirewallInventory inventory) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CupertinoButton(
          padding: const EdgeInsets.all(8),
          minimumSize: const Size(36, 36),
          onPressed: _page > 1
              ? () {
                  _page--;
                  _load();
                }
              : null,
          child: const Icon(TablerIcons.chevron_left, size: 18),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.secondaryBackground(
              context,
            ).withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$_page / ${(inventory.total + _pageSize - 1) ~/ _pageSize}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        CupertinoButton(
          padding: const EdgeInsets.all(8),
          minimumSize: const Size(36, 36),
          onPressed: _page * _pageSize < inventory.total
              ? () {
                  _page++;
                  _load();
                }
              : null,
          child: const Icon(TablerIcons.chevron_right, size: 18),
        ),
      ],
    ),
  );

  Future<void> _showRuleActions(UnifiedFirewallItem item) async {
    final action = await showActionSheet<String>(
      context: context,
      builder: (context) => ActionSheetScaffold(
        isAdaptive: true,
        panelHeader: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _stateColor(item.state).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  TablerIcons.shield,
                  size: 19,
                  color: _stateColor(item.state),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.rule.destinationPort.isEmpty
                          ? item.rule.sourceAddress
                          : item.rule.destinationPort,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.label(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.rule.protocol.toUpperCase()} · ${_stateLabel(item.state)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryLabel(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSectionHeader(
              title: context.l10n.firewall_ruleInfo,
              icon: TablerIcons.info_circle,
            ),
            AppActionGroup(
              children: [
                AppActionRow(
                  icon: TablerIcons.world,
                  iconColor: CupertinoColors.systemTeal,
                  title: context.l10n.firewall_sourceLabel,
                  subtitle: Text(
                    item.rule.sourceAddress.isEmpty
                        ? context.l10n.firewall_allAddresses
                        : item.rule.sourceAddress,
                  ),
                  trailing: const SizedBox.shrink(),
                ),
                AppActionRow(
                  icon: TablerIcons.shield,
                  iconColor: _stateColor(item.state),
                  title: _stateLabel(item.state),
                  subtitle: Text(
                    '${item.rule.family.toUpperCase()} · ${item.rule.action.toUpperCase()}',
                  ),
                  trailing: const SizedBox.shrink(),
                ),
              ],
            ),
            if (item.canAdopt) ...[
              const SizedBox(height: 22),
              AppSectionHeader(
                title: context.l10n.firewall_ruleManagement,
                icon: TablerIcons.settings,
              ),
              AppActionGroup(
                children: [
                  AppActionRow(
                    icon: TablerIcons.link,
                    iconColor: CupertinoColors.activeBlue,
                    title: context.l10n.firewall_adoptRule,
                    subtitle: Text(context.l10n.firewall_adoptRuleHint),
                    onTap: () => Navigator.pop(context, 'adopt'),
                  ),
                ],
              ),
            ],
            if (!item.canAdopt &&
                !item.canEdit &&
                !item.canEditDescription &&
                !item.canDelete) ...[
              const SizedBox(height: 22),
              AppActionGroup(
                children: [
                  AppActionRow(
                    icon: TablerIcons.lock,
                    iconColor: CupertinoColors.systemOrange,
                    title: context.l10n.firewall_readOnlyRule,
                    subtitle: Text(context.l10n.firewall_readOnlyRuleHint),
                    trailing: const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
            if (item.canEdit || item.canEditDescription) ...[
              const SizedBox(height: 22),
              AppSectionHeader(
                title: context.l10n.firewall_ruleManagement,
                icon: TablerIcons.settings,
              ),
              AppActionGroup(
                children: [
                  if (item.canEdit &&
                      ['tcp', 'udp', 'all'].contains(item.rule.protocol))
                    AppActionRow(
                      icon: TablerIcons.edit,
                      iconColor: CupertinoColors.systemBlue,
                      title: context.l10n.firewall_editRule,
                      subtitle: Text(
                        context.l10n.firewall_editPortRuleDescription,
                      ),
                      onTap: () => Navigator.pop(context, 'edit'),
                    ),
                  if (item.canEditDescription &&
                      (!item.canEdit ||
                          !['tcp', 'udp', 'all'].contains(item.rule.protocol)))
                    AppActionRow(
                      icon: TablerIcons.file_text,
                      iconColor: CupertinoColors.systemBlue,
                      title: context.l10n.common_description,
                      subtitle: Text(item.rule.description),
                      onTap: () => Navigator.pop(context, 'description'),
                    ),
                ],
              ),
            ],
            if (item.canDelete) ...[
              const SizedBox(height: 22),
              AppSectionHeader(
                title: context.l10n.runtime_dangerZone,
                icon: TablerIcons.alert_triangle,
              ),
              AppActionGroup(
                children: [
                  AppActionRow(
                    icon: TablerIcons.trash,
                    iconColor: CupertinoColors.systemRed,
                    title: context.l10n.firewall_deleteRule,
                    subtitle: Text(context.l10n.firewall_removeThisRule),
                    isDestructive: true,
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') await _edit(item);
    if (action == 'adopt') await _adopt(item);
    if (action == 'description') await _editDescription(item);
    if (action == 'delete') await _delete(item);
  }

  Future<void> _create() async {
    final input = await showActionSheet<_RuleInput>(
      context: context,
      builder: (context) => const _UnifiedRuleForm(),
    );
    if (input == null || !mounted) return;
    try {
      final rules = input.createRules(_base!.name);
      final task = await widget.api.create(rules);
      if (!mounted) return;
      await _showTask(task.taskID);
    } catch (error) {
      if (mounted) {
        _showRuleError(error, context.l10n.firewall_operationFailed);
      }
    }
  }

  Future<void> _adopt(UnifiedFirewallItem item) async {
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => AppConfirmSheet(
        title: context.l10n.firewall_adoptRule,
        content: context.l10n.firewall_adoptRuleConfirm,
        confirmText: context.l10n.common_confirm,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.adopt(item);
      if (!mounted) return;
      showAppSuccessToast(context.l10n.panelSettings_settingUpdated);
      await _load(refresh: true);
    } catch (error) {
      if (mounted) _showRuleError(error, context.l10n.firewall_operationFailed);
    }
  }

  Future<void> _edit(UnifiedFirewallItem item) async {
    final input = await showActionSheet<_RuleInput>(
      context: context,
      builder: (context) => _UnifiedRuleForm(item: item),
    );
    if (input == null || !mounted) return;
    try {
      final updated = input.updateRule(item);
      await widget.api.update(item.uuid, updated);
      if (!mounted) return;
      showAppSuccessToast(context.l10n.firewall_ruleUpdated);
      await _load(refresh: true);
    } catch (error) {
      if (mounted) {
        _showRuleError(error, context.l10n.firewall_strategyUpdateFailed);
      }
    }
  }

  Future<void> _editDescription(UnifiedFirewallItem item) async {
    final controller = TextEditingController(text: item.rule.description);
    try {
      final description = await showCupertinoDialog<String>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(context.l10n.common_description),
          content: CupertinoTextField(controller: controller),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.common_cancel),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(context.l10n.common_save),
            ),
          ],
        ),
      );
      if (description == null) return;
      await widget.api.updateDescription(item.uuid, description);
      if (!mounted) return;
      showAppSuccessToast(context.l10n.firewall_ruleUpdated);
      await _load(refresh: true);
    } catch (error) {
      if (mounted) {
        _showRuleError(error, context.l10n.firewall_strategyUpdateFailed);
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _delete(UnifiedFirewallItem item) async {
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => AppConfirmSheet(
        title: context.l10n.firewall_deleteRule,
        content:
            '${item.rule.protocol.toUpperCase()} / ${item.rule.destinationPort}',
        confirmText: context.l10n.common_delete,
        confirmColor: CupertinoColors.systemRed,
      ),
    );
    if (confirmed != true) return;
    try {
      final task = await widget.api.delete([item]);
      if (!mounted) return;
      await _showTask(task.taskID);
    } catch (error) {
      if (mounted) {
        _showRuleError(error, context.l10n.firewall_deleteFailed);
      }
    }
  }

  Future<void> _showTask(String taskID) async {
    await showTaskLogSheet(
      context,
      title: context.l10n.firewall_ruleManagement,
      taskID: taskID,
      reader: widget.api.readTask,
    );
    if (mounted) await _load(refresh: true);
  }

  void _showRuleError(Object error, String title) {
    if (!mounted) return;
    if (error is ApiBusinessException) {
      if (error.errorCode == 'FW_RULE_STALE' ||
          error.errorCode == 'FW_RULE_REVISION_CONFLICT') {
        showAppErrorToast(context.l10n.firewall_ruleStale);
        _load(refresh: true);
        return;
      }
      if (error.errorCode == 'FW_LOCKOUT_RISK') {
        showAppErrorToast(context.l10n.firewall_lockoutRisk);
        return;
      }
    }
    showAppErrorToast(title, description: '$error');
  }

  Future<void> _showStatusActions(FirewallBaseInfoDto base) async {
    final direct = base.name == 'iptables' || base.name == 'nftables';
    final choices = !base.isExist
        ? <String, String>{}
        : direct
        ? <String, String>{
            if (!base.isInit) 'init-base': context.l10n.firewall_initBasicChain,
            if (base.isInit && !base.isBind)
              'bind-base': context.l10n.firewall_bindBasicChain,
            if (base.isBind)
              'unbind-base': context.l10n.firewall_unbindBasicChain,
          }
        : <String, String>{
            if (!base.isActive) 'start': context.l10n.firewall_startService,
            if (base.isActive) ...{
              'restart': context.l10n.firewall_restartService,
              'stop': context.l10n.firewall_stopService,
            },
          };
    if (base.isExist && base.pingStatus != 'None') {
      choices[base.isPingEnabled
          ? 'disableBanPing'
          : 'enableBanPing'] = base.isPingEnabled
          ? context.l10n.firewall_disableBanPing
          : context.l10n.firewall_enableBanPing;
    }
    final operation = await showActionSheet<String>(
      context: context,
      builder: (context) => ActionSheetScaffold(
        title: context.l10n.firewall_serviceMenu,
        isAdaptive: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusCard(base),
            if (base.lifecycleTaskID.isNotEmpty) ...[
              const SizedBox(height: 18),
              AppActionGroup(
                children: [
                  AppActionRow(
                    icon: TablerIcons.progress,
                    title: context.l10n.firewall_operationInProgress,
                    subtitle: const SizedBox.shrink(),
                    onTap: () => Navigator.pop(context, 'task'),
                  ),
                ],
              ),
            ],
            if (choices.isNotEmpty && base.lifecycleTaskID.isEmpty) ...[
              const SizedBox(height: 18),
              AppActionGroup(
                children: [
                  for (final choice in choices.entries)
                    AppActionRow(
                      icon: switch (choice.key) {
                        'start' => TablerIcons.player_play,
                        'stop' => TablerIcons.player_stop,
                        'restart' => TablerIcons.refresh,
                        'init-base' => TablerIcons.replace,
                        'bind-base' => TablerIcons.link,
                        'unbind-base' => TablerIcons.unlink,
                        _ => TablerIcons.shield_check,
                      },
                      iconColor:
                          choice.key == 'stop' || choice.key == 'unbind-base'
                          ? CupertinoColors.systemRed
                          : CupertinoColors.activeBlue,
                      title: choice.value,
                      subtitle: const SizedBox.shrink(),
                      isDestructive:
                          choice.key == 'stop' || choice.key == 'unbind-base',
                      onTap: () => Navigator.pop(context, choice.key),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    if (operation == null || !mounted) return;
    if (operation == 'task') {
      await _showTask(base.lifecycleTaskID);
      return;
    }
    final content = switch (operation) {
      'init-base' => context.l10n.firewall_initBasicChainContent,
      'bind-base' => context.l10n.firewall_bindBasicChainContent,
      'unbind-base' => context.l10n.firewall_unbindBasicChainContent,
      'start' => context.l10n.firewall_startContent,
      'stop' => context.l10n.firewall_stopContent,
      'enableBanPing' => context.l10n.firewall_enableBanPingContent,
      'disableBanPing' => context.l10n.firewall_disableBanPingContent,
      _ => context.l10n.firewall_restartContent,
    };
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => AppConfirmSheet(
        title: choices[operation]!,
        content: content,
        confirmText: context.l10n.common_confirm,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final task = direct && operation.endsWith('-base')
          ? await widget.api.operateBaseChain(operation)
          : await widget.api.operateService(operation);
      if (!mounted) return;
      if (task != null) {
        await _showTask(task.taskID);
      } else {
        showAppSuccessToast(context.l10n.panelSettings_settingUpdated);
        await _load(refresh: true);
      }
    } catch (error) {
      if (mounted) {
        showAppErrorToast(
          context.l10n.firewall_operationFailed,
          description: '$error',
        );
      }
    }
  }
}

class _RuleInput {
  const _RuleInput({
    required this.addresses,
    required this.ports,
    required this.protocol,
    required this.action,
    required this.description,
    this.family = 'ipv4',
  });

  final String addresses;
  final String ports;
  final String protocol;
  final String action;
  final String description;
  final String family;

  List<Map<String, dynamic>> createRules(String provider) {
    if (addresses.trim().isEmpty && ports.trim().isEmpty) {
      throw const FormatException('请填写来源地址或端口');
    }
    final sources = addresses.trim().isEmpty
        ? ['']
        : addresses
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
    final destinationPorts = ports.trim().isEmpty
        ? ['']
        : ports
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
    final protocols = protocol == 'tcp/udp'
        ? provider == 'ufw' &&
                  destinationPorts.length == 1 &&
                  destinationPorts.single.isNotEmpty &&
                  !destinationPorts.single.contains('-')
              ? ['all']
              : ['tcp', 'udp']
        : [protocol];
    if (sources.length * destinationPorts.length * protocols.length > 500) {
      throw const FormatException('规则数量不能超过 500');
    }
    final rules = <Map<String, dynamic>>[];
    for (final source in sources) {
      final ruleFamily = source.isEmpty
          ? provider == 'firewalld'
                ? 'inet'
                : family == 'ipv6'
                ? 'ipv6'
                : 'ipv4'
          : _familyOf(source, provider);
      for (final port in destinationPorts) {
        if (port.isNotEmpty && !_validPort(port)) {
          throw FormatException('无效端口: $port');
        }
        final normalizedPort = port.replaceAll(':', '-');
        for (final proto in protocols) {
          rules.add({
            'scope': UnifiedFirewallApi.scopeFor(provider, ruleFamily),
            'protocol': proto,
            'sourceAddress': source,
            'destinationPort': normalizedPort,
            'action': action,
            'description': description,
          });
        }
      }
    }
    return rules;
  }

  Map<String, dynamic> updateRule(UnifiedFirewallItem item) {
    final sources = addresses.split(',');
    final destinations = ports.split(',');
    if (sources.length != 1 ||
        destinations.length != 1 ||
        protocol == 'tcp/udp') {
      throw const FormatException('编辑时只能使用一个来源、端口和协议');
    }
    final source = addresses.trim();
    final port = ports.trim();
    if (source.isNotEmpty &&
        _familyOf(source, item.rule.provider) != item.rule.family) {
      throw const FormatException('不能在编辑时改变规则的 IP 类型');
    }
    if (port.isNotEmpty && !_validPort(port)) {
      throw FormatException('无效端口: $port');
    }
    final rule = Map<String, dynamic>.from(item.rule.json);
    rule['sourceAddress'] = source;
    rule['destinationPort'] = port.replaceAll(':', '-');
    rule['protocol'] = protocol;
    rule['action'] = item.rule.action == 'reject' && action == 'drop'
        ? 'reject'
        : action;
    rule['description'] = description;
    return rule;
  }

  static bool _validPort(String value) {
    final parts = value.split(RegExp('[-:]'));
    if (parts.length > 2) return false;
    final start = int.tryParse(parts[0]);
    final end = parts.length == 2 ? int.tryParse(parts[1]) : start;
    return start != null &&
        end != null &&
        start >= 1 &&
        end <= 65535 &&
        start <= end;
  }

  static String _familyOf(String address, String provider) {
    if (address.isEmpty) return provider == 'firewalld' ? 'inet' : 'ipv4';
    final host = address.split('/').first;
    final parsed = InternetAddress.tryParse(host);
    if (parsed == null) throw FormatException('无效来源地址: $address');
    final parts = address.split('/');
    if (parts.length > 2) throw FormatException('无效来源地址: $address');
    if (parts.length == 2) {
      final prefix = int.tryParse(parts[1]);
      final max = parsed.type == InternetAddressType.IPv6 ? 128 : 32;
      if (prefix == null || prefix < 0 || prefix > max) {
        throw FormatException('无效来源地址: $address');
      }
    }
    return parsed.type == InternetAddressType.IPv6 ? 'ipv6' : 'ipv4';
  }
}

class _UnifiedRuleForm extends StatefulWidget {
  const _UnifiedRuleForm({this.item});

  final UnifiedFirewallItem? item;

  @override
  State<_UnifiedRuleForm> createState() => _UnifiedRuleFormState();
}

class _UnifiedRuleFormState extends State<_UnifiedRuleForm> {
  late final TextEditingController _address;
  late final TextEditingController _port;
  late final TextEditingController _description;
  late String _protocol;
  late String _action;
  late String _family;
  bool _pickerExpanded = false;

  @override
  void initState() {
    super.initState();
    final rule = widget.item?.rule;
    _address = TextEditingController(text: rule?.sourceAddress ?? '');
    _port = TextEditingController(text: rule?.destinationPort ?? '');
    _description = TextEditingController(text: rule?.description ?? '');
    _address.addListener(() => setState(() {}));
    _protocol = rule?.protocol ?? 'tcp';
    _action = rule?.action == 'drop' || rule?.action == 'reject'
        ? 'drop'
        : 'accept';
    _family = rule?.family == 'ipv6' ? 'ipv6' : 'ipv4';
  }

  @override
  void dispose() {
    _address.dispose();
    _port.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ActionSheetScaffold(
      isAdaptive: true,
      showHandle: false,
      contentPadding: EdgeInsets.zero,
      scrollPhysics: _pickerExpanded
          ? const NeverScrollableScrollPhysics()
          : null,
      panelHeader: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onPressed: () => Navigator.pop(context),
                child: Text(
                  l10n.common_cancel,
                  style: TextStyle(color: AppColors.secondaryLabel(context)),
                ),
              ),
            ),
            Text(
              widget.item == null
                  ? l10n.firewall_createRule
                  : l10n.firewall_editRule,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: AppColors.label(context),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onPressed: () => Navigator.pop(
                  context,
                  _RuleInput(
                    addresses: _address.text,
                    ports: _port.text,
                    protocol: _protocol,
                    action: _action,
                    description: _description.text,
                    family: _family,
                  ),
                ),
                child: Text(
                  widget.item == null ? l10n.common_create : l10n.common_save,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.activeBlue.resolveFrom(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCupertinoSectionHeader(title: l10n.firewall_ruleInfo),
          AppCupertinoGroupedBox(
            children: [
              AppCupertinoFormTile(
                label: l10n.firewall_port,
                child: _field(_port, l10n.firewall_portPlaceholder),
              ),
              AppCupertinoFormTile(
                label: l10n.firewall_protocol,
                child: _picker(_protocol, [
                  const AppPickerOption(value: 'tcp', label: 'TCP'),
                  const AppPickerOption(value: 'udp', label: 'UDP'),
                  if (widget.item == null)
                    const AppPickerOption(value: 'tcp/udp', label: 'TCP/UDP'),
                  const AppPickerOption(value: 'all', label: 'ALL'),
                ], (value) => setState(() => _protocol = value)),
              ),
              AppCupertinoFormTile(
                label: l10n.firewall_strategy,
                isLast: true,
                child: _picker(_action, [
                  AppPickerOption(
                    value: 'accept',
                    label: l10n.firewall_acceptLabel,
                  ),
                  AppPickerOption(
                    value: 'drop',
                    label: l10n.firewall_dropLabel,
                  ),
                ], (value) => setState(() => _action = value)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          AppCupertinoSectionHeader(title: l10n.firewall_source),
          AppCupertinoGroupedBox(
            children: [
              AppCupertinoFormTile(
                label: l10n.firewall_address,
                isLast: widget.item != null || _address.text.trim().isNotEmpty,
                child: _field(_address, l10n.firewall_addressPlaceholder),
              ),
              if (widget.item == null && _address.text.trim().isEmpty)
                AppCupertinoFormTile(
                  label: l10n.firewall_familyFilter,
                  isLast: true,
                  child: _picker(_family, const [
                    AppPickerOption(value: 'ipv4', label: 'IPv4'),
                    AppPickerOption(value: 'ipv6', label: 'IPv6'),
                  ], (value) => setState(() => _family = value)),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Text(
              l10n.firewall_createPortHint,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.tertiaryLabel(context),
              ),
            ),
          ),
          const SizedBox(height: 24),
          AppCupertinoSectionHeader(title: l10n.firewall_descriptionOptional),
          AppCupertinoGroupedBox(
            children: [
              AppCupertinoFormTile(
                label: l10n.common_description,
                isLast: true,
                child: _field(
                  _description,
                  l10n.firewall_descriptionPlaceholder,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String placeholder) =>
      CupertinoTextField(
        controller: controller,
        placeholder: placeholder,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(),
        style: TextStyle(fontSize: 15, color: AppColors.label(context)),
      );

  Widget _picker(
    String value,
    List<AppPickerOption<String>> options,
    ValueChanged<String> onChanged,
  ) => AppInlinePicker<String>(
    value: value,
    options: options,
    anchorHeight: 44,
    backgroundColor: CupertinoColors.transparent,
    onChanged: onChanged,
    onExpandChanged: (expanded) => setState(() => _pickerExpanded = expanded),
  );
}
