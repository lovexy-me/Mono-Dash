import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mono_dash/core/network/dio_client.dart';
import 'package:mono_dash/core/network/network_exceptions.dart';
import 'package:mono_dash/data/api/firewall_api.dart';
import 'package:mono_dash/data/api/unified_firewall_api.dart';
import 'package:mono_dash/data/dto/firewall/unified_firewall_dto.dart';

void main() {
  group('unified firewall capability probe', () {
    late HttpServer server;
    late DioClient client;
    late UnifiedFirewallApi api;
    late Future<void> listener;
    final requests = <String>[];
    Map<String, dynamic>? adoptPayload;
    var probeStatus = 200;
    var probeCode = 200;

    setUp(() async {
      requests.clear();
      adoptPayload = null;
      probeStatus = 200;
      probeCode = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      listener = () async {
        await for (final request in server) {
          requests.add('${request.method} ${request.uri.path}');
          request.response.headers.contentType = ContentType.json;
          if (request.uri.path == '/api/v2/hosts/firewall/settings') {
            request.response.statusCode = probeStatus;
            request.response.write(
              jsonEncode({
                'code': probeCode,
                'errorCode': probeCode == 200 ? null : 'FW_SCOPE_UNSUPPORTED',
                'message': 'probe failed',
                'data': probeCode == 200 ? <String, dynamic>{} : null,
              }),
            );
          } else if (request.uri.path == '/api/v2/hosts/firewall/rules') {
            request.response.write(
              jsonEncode({
                'code': 200,
                'data': {'taskID': 'task-1', 'queued': true},
              }),
            );
          } else if (request.uri.path == '/api/v2/hosts/firewall/rules/adopt') {
            adoptPayload =
                jsonDecode(await utf8.decoder.bind(request).join())
                    as Map<String, dynamic>;
            request.response.write(jsonEncode({'code': 200, 'data': null}));
          } else {
            request.response.statusCode = 404;
          }
          await request.response.close();
        }
      }();
      client = DioClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'test-key',
        userAgent: 'MonoDash-Test',
      );
      api = UnifiedFirewallApi(client);
    });

    tearDown(() async {
      client.dispose();
      await server.close(force: true);
      await listener;
    });

    test('uses only an actual HTTP 404 to select the legacy API', () async {
      probeStatus = 404;
      expect(await api.detectVersion(), FirewallApiVersion.legacy);
      await expectLater(
        api.create([
          {
            'scope': {'provider': 'ufw'},
          },
        ]),
        throwsA(isA<StateError>()),
      );
      expect(requests, everyElement(contains('/firewall/settings')));
    });

    test('business errors keep the version unknown and block writes', () async {
      probeCode = 404;
      await expectLater(
        api.detectVersion(),
        throwsA(
          isA<ApiBusinessException>().having(
            (e) => e.errorCode,
            'errorCode',
            'FW_SCOPE_UNSUPPORTED',
          ),
        ),
      );
      await expectLater(
        api.create([
          {
            'scope': {'provider': 'ufw'},
          },
        ]),
        throwsA(isA<ApiBusinessException>()),
      );
      expect(requests, everyElement(contains('/firewall/settings')));
    });

    test('new rule mutation is sent only after successful probe', () async {
      final task = await api.create([
        {
          'scope': UnifiedFirewallApi.scopeFor('ufw', 'ipv4'),
          'protocol': 'tcp',
          'destinationPort': '443',
          'action': 'accept',
        },
      ]);
      expect(task.taskID, 'task-1');
      expect(requests, [
        'GET /api/v2/hosts/firewall/settings',
        'POST /api/v2/hosts/firewall/rules',
      ]);
    });

    test('adopts a supported external rule with observed position', () async {
      const item = UnifiedFirewallItem({
        'rule': {
          'scope': {
            'provider': 'iptables',
            'family': 'ipv4',
            'table': 'filter',
            'chain': '1PANEL_BASIC',
            'direction': 'input',
          },
        },
        'state': 'external',
        'observed': {
          'parseStatus': 'supported',
          'instanceKey': 'rule-1',
          'marker': 'marker-1',
          'locator': {'position': 3},
          'rule': {
            'scope': {
              'provider': 'iptables',
              'family': 'ipv4',
              'table': 'filter',
              'chain': '1PANEL_BASIC',
              'direction': 'input',
            },
            'protocol': 'tcp',
            'destinationPort': '443',
            'action': 'accept',
          },
        },
      });
      expect(item.canAdopt, isTrue);
      await api.adopt(item);
      expect(adoptPayload?['instanceKey'], 'rule-1');
      expect(adoptPayload?['marker'], 'marker-1');
      expect((adoptPayload?['rule'] as Map)['orderIndex'], 3);
      expect(requests.last, 'POST /api/v2/hosts/firewall/rules/adopt');
    });

    test('legacy port mutation is blocked after a backend upgrade', () async {
      await expectLater(
        FirewallApi(
          client,
        ).operatePortRule({'operation': 'add', 'port': '443'}),
        throwsA(isA<StateError>()),
      );
      expect(requests, ['GET /api/v2/hosts/firewall/settings']);
    });
  });

  test('protected and external rules cannot be edited or deleted', () {
    const protected = UnifiedFirewallItem({
      'rule': {
        'scope': {'provider': 'ufw', 'family': 'inet'},
      },
      'state': 'protected',
      'desired': {'uuid': 'a', 'origin': 'created', 'protected': true},
    });
    const external = UnifiedFirewallItem({
      'rule': {
        'scope': {'provider': 'ufw', 'family': 'inet'},
      },
      'state': 'external',
    });
    expect(protected.canEdit, isFalse);
    expect(protected.canDelete, isFalse);
    expect(protected.canAdopt, isFalse);
    expect(external.canEdit, isFalse);
    expect(external.canDelete, isFalse);
    expect(external.canAdopt, isFalse);
  });
}
