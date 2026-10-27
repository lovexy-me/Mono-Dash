class UnifiedFirewallRule {
  const UnifiedFirewallRule(this.json);

  final Map<String, dynamic> json;

  Map<String, dynamic> get scope => _map(json['scope']);
  String get provider => '${scope['provider'] ?? ''}';
  String get family => '${scope['family'] ?? ''}';
  String get protocol => '${json['protocol'] ?? ''}';
  String get sourceAddress => '${json['sourceAddress'] ?? ''}';
  String get destinationPort => '${json['destinationPort'] ?? ''}';
  String get action => '${json['action'] ?? ''}';
  String get description => '${json['description'] ?? ''}';

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}

class UnifiedFirewallItem {
  const UnifiedFirewallItem(this.json);

  final Map<String, dynamic> json;

  UnifiedFirewallRule get rule =>
      UnifiedFirewallRule(UnifiedFirewallRule._map(json['rule']));
  Map<String, dynamic> get desired => UnifiedFirewallRule._map(json['desired']);
  Map<String, dynamic> get observed =>
      UnifiedFirewallRule._map(json['observed']);
  String get state => '${json['state'] ?? ''}';
  String get match => '${json['match'] ?? ''}';
  String get uuid => '${desired['uuid'] ?? ''}';
  String get origin => '${desired['origin'] ?? ''}';
  bool get protected =>
      desired['protected'] == true ||
      observed['protected'] == true ||
      state == 'protected';
  bool get managed =>
      uuid.isNotEmpty &&
      (origin == 'created' || origin == 'adopted') &&
      desired['protected'] != true;
  bool get systemPreset =>
      (rule.provider == 'iptables' || rule.provider == 'nftables') &&
      (rule.scope['chain'] == '1PANEL_BASIC_BEFORE' ||
          rule.scope['chain'] == '1PANEL_BASIC_AFTER');
  bool get canEditDescription => managed;
  bool get canAdopt =>
      state == 'external' &&
      observed['parseStatus'] == 'supported' &&
      !systemPreset &&
      !protected &&
      (rule.provider == 'nftables'
          ? '${observed['instanceKey'] ?? ''}'.isNotEmpty
          : observed['rule'] is Map && (observed['rule'] as Map).isNotEmpty);
  bool get canEdit =>
      managed &&
      desired['expanded'] != true &&
      !systemPreset &&
      state != 'drifted' &&
      state != 'protected';
  bool get canDeleteManaged =>
      managed &&
      !systemPreset &&
      state != 'protected' &&
      (state != 'drifted' || (match == 'missing' && observed.isEmpty));
  bool get canDeleteBefore =>
      (rule.provider == 'iptables' || rule.provider == 'nftables') &&
      rule.scope['chain'] == '1PANEL_BASIC_BEFORE' &&
      desired.isEmpty &&
      state != 'protected' &&
      observed['parseStatus'] == 'supported' &&
      observed['protected'] != true &&
      '${observed['instanceKey'] ?? ''}'.isNotEmpty;
  bool get canDelete => canDeleteManaged || canDeleteBefore;
  Map<String, dynamic> get deleteTarget => canDeleteManaged
      ? {'uuid': uuid}
      : {'scope': rule.scope, 'instanceKey': observed['instanceKey']};
}

class UnifiedFirewallInventory {
  const UnifiedFirewallInventory({
    required this.items,
    required this.total,
    required this.notices,
  });

  final List<UnifiedFirewallItem> items;
  final int total;
  final List<String> notices;

  factory UnifiedFirewallInventory.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List? ?? const [];
    final notices = json['notices'] as List? ?? const [];
    return UnifiedFirewallInventory(
      items: raw
          .whereType<Map>()
          .map((e) => UnifiedFirewallItem(Map<String, dynamic>.from(e)))
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      notices: notices
          .whereType<Map>()
          .map((e) => '${e['code'] ?? ''}')
          .where((e) => e.isNotEmpty)
          .toList(),
    );
  }
}

class FirewallTaskSubmission {
  const FirewallTaskSubmission({required this.taskID, required this.queued});

  final String taskID;
  final bool queued;

  factory FirewallTaskSubmission.fromJson(Map<String, dynamic> json) =>
      FirewallTaskSubmission(
        taskID: '${json['taskID'] ?? ''}',
        queued: json['queued'] == true,
      );
}
