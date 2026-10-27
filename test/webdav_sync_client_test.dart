import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mono_dash/core/storage/webdav_sync_client.dart';

void main() {
  test('creates the configured collection and writes the sync file', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final requests = <String>[];
    var collectionExists = false;
    final handler = () async {
      await for (final request in server) {
        requests.add('${request.method} ${request.uri.path}');
        if (request.method == 'MKCOL' && request.uri.path == '/dav/') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
        } else if (request.method == 'MKCOL' &&
            request.uri.path == '/dav/mono-dash/') {
          collectionExists = true;
          request.response.statusCode = HttpStatus.created;
        } else if (request.method == 'PUT' &&
            request.uri.path == '/dav/mono-dash/data.json') {
          request.response.statusCode = collectionExists
              ? HttpStatus.created
              : HttpStatus.conflict;
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      }
    }();

    final client = WebDavSyncClient(
      url: 'http://${server.address.host}:${server.port}/dav/',
      path: WebDavSyncClient.defaultPath,
      username: '',
      password: '',
    );
    expect(await client.readPayload(), isNull);
    await client.writePayload('{}');

    expect(requests, [
      'GET /dav/mono-dash/data.json',
      'PUT /dav/mono-dash/data.json',
      'MKCOL /dav/',
      'MKCOL /dav/mono-dash/',
      'PUT /dav/mono-dash/data.json',
    ]);
    await server.close(force: true);
    await handler;
  });
}
