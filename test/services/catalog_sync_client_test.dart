/// CatalogSyncClient contract for the shop-provisioning / pill surfaces:
/// `POST /v1/shops` carries the optional contact fields, `GET
/// /v1/catalog/version` returns the RAW status (so the pill can tell a
/// rejected token from an unreachable server), and `GET /v1/sync/status`
/// yields the token role.
///
/// A recording http.Client keeps every assertion off the network.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

import 'package:myhanout/data/catalog_sync_client.dart';

class _RecordingClient extends http.BaseClient {
  final http.Response Function(http.BaseRequest request) responder;
  http.BaseRequest? lastRequest;
  String? lastBody;

  _RecordingClient(this.responder);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    if (request is http.Request) {
      lastBody = await request.finalize().bytesToString();
    }
    final response = responder(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
    );
  }

  @override
  void close() {}
}

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

CatalogSyncClient _client(_RecordingClient http) => CatalogSyncClient(
      baseUrl: 'https://catalog.example.test',
      token: 'secret-token',
      deviceId: 'mapper-owner-01',
      client: http,
    );

void main() {
  group('registerShop contact fields', () {
    test('sends the four contact fields when present', () async {
      final http = _RecordingClient((_) => _json(200, {'ok': true}));
      await _client(http).registerShop(
        'hanouti',
        'Hanouti',
        address: '12 Rue Omar',
        city: 'Casablanca',
        ownerName: 'Amina',
        phone: '0600000000',
      );

      final body = jsonDecode(http.lastBody!) as Map<String, dynamic>;
      expect(body, {
        'shop_key': 'hanouti',
        'business_name': 'Hanouti',
        'device_id': 'mapper-owner-01',
        'address': '12 Rue Omar',
        'city': 'Casablanca',
        'owner_name': 'Amina',
        'phone': '0600000000',
      });
      expect(http.lastRequest!.url.path, '/v1/shops');
      expect(http.lastRequest!.headers['Authorization'], 'Bearer secret-token');
    });

    test('omits empty contact fields (they are optional, never blocking)',
        () async {
      final http = _RecordingClient((_) => _json(200, {'ok': true}));
      await _client(http).registerShop('hanouti', 'Hanouti');

      final body = jsonDecode(http.lastBody!) as Map<String, dynamic>;
      expect(body.keys.toSet(), {'shop_key', 'business_name', 'device_id'},
          reason: 'an absent contact field must not be sent as an empty string');
    });
  });

  group('catalogVersionStatus', () {
    test('returns the raw status code, including 401/403', () async {
      for (final status in [200, 401, 403, 500]) {
        final http = _RecordingClient((_) => _json(status, {'detail': 'x'}));
        expect(await _client(http).catalogVersionStatus(), status,
            reason: 'the pill needs the raw code, not a thrown auth error');
      }
    });

    test('sends the auth header to the authenticated endpoint', () async {
      final http = _RecordingClient((_) => _json(200, {'version': 7}));
      await _client(http).catalogVersionStatus();
      expect(http.lastRequest!.url.path, '/v1/catalog/version');
      expect(http.lastRequest!.headers['Authorization'], 'Bearer secret-token');
    });

    test('lets a network error propagate', () async {
      final http = _RecordingClient((_) => throw Exception('socket closed'));
      expect(() => _client(http).catalogVersionStatus(),
          throwsA(isA<Exception>()));
    });
  });

  group('syncRole', () {
    test('decodes the role from GET /v1/sync/status', () async {
      final http = _RecordingClient(
          (_) => _json(200, {'count': 3, 'open': true, 'role': 'owner'}));
      expect(await _client(http).syncRole(), 'owner');
      expect(http.lastRequest!.url.path, '/v1/sync/status');
      expect(http.lastRequest!.headers['Authorization'], 'Bearer secret-token');
    });

    test('a salesman token reports salesman', () async {
      final http = _RecordingClient(
          (_) => _json(200, {'count': 1, 'open': false, 'role': 'salesman'}));
      expect(await _client(http).syncRole(), 'salesman');
    });

    test('a non-200 status throws SyncException', () async {
      final http = _RecordingClient((_) => _json(401, {'detail': 'no'}));
      expect(() => _client(http).syncRole(), throwsA(isA<SyncException>()));
    });
  });
}
