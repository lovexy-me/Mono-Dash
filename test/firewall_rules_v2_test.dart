import 'package:flutter_test/flutter_test.dart';
import 'package:mono_dash/data/api/firewall_rules_v2.dart';

V2RuleItem _item({
  String source = '',
  String port = '',
  String protocol = 'all',
  String action = 'accept',
  String? uuid,
}) {
  return V2RuleItem({
    'state': uuid == null ? 'external' : 'managed',
    'rule': {
      'scope': {'provider': 'iptables', 'family': 'ipv4', 'chain': '1PANEL_BASIC'},
      'protocol': protocol,
      'sourceAddress': source,
      'destinationPort': port,
      'action': action,
    },
    if (uuid != null) 'desired': {'uuid': uuid},
  });
}

void main() {
  test('IP body expands per address with protocol all', () {
    final rules = rulesFromLegacyBody({
      'operation': 'add',
      'address': '1.2.3.4, 10.0.0.0/8',
      'strategy': 'drop',
    }, isPort: false);
    expect(rules.length, 2);
    expect(rules.first['protocol'], 'all');
    expect(rules.first['action'], 'drop');
    expect(rules.first.containsKey('destinationPort'), isFalse);
  });

  test('port body expands tcp/udp and ports', () {
    final rules = rulesFromLegacyBody({
      'port': '80,443',
      'protocol': 'tcp/udp',
      'strategy': 'accept',
      'address': '',
    }, isPort: true);
    expect(rules.length, 4);
    expect(rules.every((r) => !r.containsKey('sourceAddress')), isTrue);
  });

  test('classification and paging', () {
    final items = [
      _item(source: '1.2.3.4', action: 'drop', uuid: 'a'),
      _item(port: '22', protocol: 'tcp', uuid: 'b'),
      _item(source: '5.6.7.8', port: '80', protocol: 'tcp'),
    ];
    final ips = legacyPage(items, type: 'address', page: 1, pageSize: 50);
    expect(ips.total, 1);
    expect(ips.items.first['strategy'], 'drop');
    final ports = legacyPage(items, type: 'port', page: 1, pageSize: 50);
    expect(ports.total, 2);
  });

  test('matching a legacy remove body', () {
    final item = _item(source: '1.2.3.4', action: 'drop', uuid: 'a');
    expect(
      itemMatchesLegacyBody(item, {
        'address': '1.2.3.4',
        'strategy': 'drop',
      }, isPort: false),
      isTrue,
    );
    expect(
      itemMatchesLegacyBody(item, {
        'address': '1.2.3.4',
        'strategy': 'accept',
      }, isPort: false),
      isFalse,
    );
    expect(item.uuid, 'a');
  });
}
