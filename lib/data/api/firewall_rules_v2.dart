/// Adapter between Mono-Dash's legacy firewall rule bodies and the unified
/// firewall rule API that newer 1Panel v2 builds expose
/// (`/hosts/firewall/rules/*`), which replaced `/hosts/firewall/search`,
/// `/ip`, `/update/*`, `/batch` and `/update/description`.
///
/// Pure Dart on purpose: no Dio or Flutter imports, so it can be unit tested.
library;

/// A rule row from `/hosts/firewall/rules/search`, flattened.
class V2RuleItem {
  V2RuleItem(this.raw);

  final Map<String, dynamic> raw;

  Map<String, dynamic> get rule =>
      (raw['rule'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic>? get observed =>
      (raw['observed'] as Map?)?.cast<String, dynamic>();
  Map<String, dynamic>? get desired =>
      (raw['desired'] as Map?)?.cast<String, dynamic>();
  Map<String, dynamic> get scope =>
      (rule['scope'] as Map?)?.cast<String, dynamic>() ?? const {};

  String get state => (raw['state'] ?? '').toString();
  String get sourceAddress => (rule['sourceAddress'] ?? '').toString();
  String get sourcePort => (rule['sourcePort'] ?? '').toString();
  String get destinationPort => (rule['destinationPort'] ?? '').toString();
  String get protocol =>
      (rule['protocol'] ?? '').toString().toLowerCase().trim();
  String get action => (rule['action'] ?? '').toString().toLowerCase();
  String get description => (rule['description'] ?? '').toString();
  String get family => (scope['family'] ?? '').toString();
  String get chain => (scope['chain'] ?? scope['zone'] ?? '').toString();

  /// UUID of the panel-managed rule, when the panel owns it.
  String? get uuid {
    final d = desired;
    final value = d?['uuid'] ?? (d?['rule'] as Map?)?['uuid'];
    final text = value?.toString() ?? '';
    return text.isEmpty ? null : text;
  }

  String? get instanceKey {
    final key = observed?['instanceKey']?.toString() ?? '';
    return key.isEmpty ? null : key;
  }

  bool get isProtected =>
      state == 'protected' || observed?['protected'] == true;

  bool get isParsed =>
      observed == null || observed!['parseStatus'] == 'supported';

  /// Deletable directly by scope + instance key (iptables/nftables BEFORE chain).
  bool get isDeletableBeforeRule {
    final provider = scope['provider'];
    return (provider == 'iptables' || provider == 'nftables') &&
        scope['chain'] == '1PANEL_BASIC_BEFORE' &&
        desired == null &&
        !isProtected &&
        isParsed &&
        instanceKey != null;
  }

  /// Payload for `/hosts/firewall/rules/adopt`, turning an external rule into
  /// a panel-managed one so it can be edited or deleted.
  Map<String, dynamic>? get adoptRequest {
    final obs = observed;
    if (obs == null || isProtected || !isParsed) return null;
    final obsRule = (obs['rule'] as Map?)?.cast<String, dynamic>() ?? rule;
    final locator = (obs['locator'] as Map?)?.cast<String, dynamic>();
    return {
      'scope': scope,
      if (instanceKey != null) 'instanceKey': instanceKey,
      'rule': {
        ...obsRule,
        if (locator?['position'] != null) 'orderIndex': locator!['position'],
      },
      if ((obs['marker'] ?? '').toString().isNotEmpty) 'marker': obs['marker'],
    };
  }

  /// An "IP rule" in the old UI: whole-host allow/deny for a source address.
  bool get isAddressRule =>
      sourceAddress.isNotEmpty &&
      destinationPort.isEmpty &&
      sourcePort.isEmpty &&
      (protocol.isEmpty || protocol == 'all' || protocol == 'any');

  String get legacyStrategy => action == 'accept' ? 'accept' : 'drop';

  /// The legacy `RuleInfo` JSON shape the screens already understand.
  Map<String, dynamic> toLegacyJson() => {
    'chain': chain,
    'family': family,
    'address': sourceAddress,
    'port': destinationPort,
    'protocol': protocol == 'all' ? '' : protocol,
    'strategy': legacyStrategy,
    'description': description,
  };
}

const anyAddresses = {'', 'anywhere', '0.0.0.0/0', '::/0', 'any', 'all'};

String normalizeAddress(String value) {
  final v = value.trim().toLowerCase();
  if (anyAddresses.contains(v)) return '';
  if (v.endsWith('/32') && !v.contains(':')) return v.substring(0, v.length - 3);
  if (v.endsWith('/128') && v.contains(':')) return v.substring(0, v.length - 4);
  return v;
}

List<String> splitValues(String value) => value
    .split(RegExp(r'[\s,]+'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

List<String> expandProtocol(String protocol) {
  final p = protocol.trim().toLowerCase();
  if (p == 'tcp/udp' || p == 'tcp,udp') return const ['tcp', 'udp'];
  if (p.isEmpty || p == 'any') return const ['all'];
  return [p];
}

String actionFor(String strategy) =>
    strategy.trim().toLowerCase() == 'accept' ||
            strategy.trim().toLowerCase() == 'allow'
        ? 'accept'
        : 'drop';

/// Turns one legacy body (`/firewall/ip` or `/firewall/port`) into atomic
/// rules for `/firewall/rules`. The scope is left empty so the server fills
/// in the provider, family, table/zone and chain it manages.
List<Map<String, dynamic>> rulesFromLegacyBody(
  Map<String, dynamic> body, {
  required bool isPort,
}) {
  final addresses = splitValues((body['address'] ?? '').toString())
      .where((a) => normalizeAddress(a).isNotEmpty)
      .toList();
  final ports = isPort
      ? splitValues((body['port'] ?? '').toString())
      : const <String>[];
  final protocols = isPort
      ? expandProtocol((body['protocol'] ?? 'tcp').toString())
      : const ['all'];
  final action = actionFor((body['strategy'] ?? 'accept').toString());
  final description = (body['description'] ?? '').toString();

  final rules = <Map<String, dynamic>>[];
  for (final address in addresses.isEmpty ? [''] : addresses) {
    for (final port in ports.isEmpty ? [''] : ports) {
      for (final protocol in protocols) {
        rules.add({
          'scope': <String, dynamic>{},
          'protocol': protocol,
          if (address.isNotEmpty) 'sourceAddress': address,
          if (port.isNotEmpty) 'destinationPort': port,
          'action': action,
          if (description.isNotEmpty) 'description': description,
        });
      }
    }
  }
  return rules;
}

/// Whether a server rule is one of the rules a legacy body describes.
bool itemMatchesLegacyBody(
  V2RuleItem item,
  Map<String, dynamic> body, {
  required bool isPort,
}) {
  final addresses = splitValues((body['address'] ?? '').toString())
      .map(normalizeAddress)
      .toSet();
  if (addresses.isEmpty) addresses.add('');
  if (!addresses.contains(normalizeAddress(item.sourceAddress))) return false;
  if (item.legacyStrategy != actionFor((body['strategy'] ?? '').toString())) {
    return false;
  }
  if (!isPort) return item.isAddressRule;
  final ports = splitValues((body['port'] ?? '').toString()).toSet();
  if (ports.isEmpty) ports.add('');
  if (!ports.contains(item.destinationPort)) return false;
  final protocols = expandProtocol((body['protocol'] ?? '').toString());
  final itemProtocol = item.protocol.isEmpty ? 'all' : item.protocol;
  return protocols.contains(itemProtocol) || protocols.contains('all');
}

/// Applies the legacy `type`/`strategy` filters and paging locally.
({int total, List<Map<String, dynamic>> items}) legacyPage(
  List<V2RuleItem> all, {
  required String type,
  required int page,
  required int pageSize,
  String strategy = '',
}) {
  final wantAddress = type == 'address';
  final filtered = all.where((item) {
    if (item.raw['incompatible'] == true) return false;
    if (item.isAddressRule != wantAddress) return false;
    if (strategy.isNotEmpty && item.legacyStrategy != actionFor(strategy)) {
      return false;
    }
    return true;
  }).toList();
  final start = (page - 1) * pageSize;
  final items = start >= filtered.length
      ? <Map<String, dynamic>>[]
      : filtered
            .skip(start)
            .take(pageSize)
            .map((e) => e.toLegacyJson())
            .toList();
  return (total: filtered.length, items: items);
}
