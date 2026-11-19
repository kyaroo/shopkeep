/// ShopInfoClient: PATCH allowlist, header contract and readable error mapping.
/// A recording http.Client keeps every assertion off the network.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

import 'package:myhanout/services/shop_info_client.dart';

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

void main() {
  group('ShopInfoClient.patch allowlist', () {
    test('sends only the four editable contact fields', () async {
      final httpClient = _RecordingClient((_) => _json(200, {
            'shop_key': 'hanouti',
            'business_name': 'Hanouti',
            'provisioner_signer_id': 'founder-1',
          }));
      final client = ShopInfoClient(
          baseUrl: 'https://example.test', token: 'secret-token', client: httpClient);

      await client.patch(
        'hanouti',
        const ShopInfoPatch(
          address: '12 Rue Test',
          city: 'Casablanca',
          ownerName: 'Amina',
          phone: '0600000000',
        ),
      );

      final body = jsonDecode(httpClient.lastBody!) as Map<String, dynamic>;
      expect(body.keys.toSet(), {
        'address',
        'city',
        'owner_name',
        'phone',
      }, reason: 'PATCH body must contain ONLY the allowlisted fields');
      expect(body, isNot(containsPair('shop_key', anything)));
      expect(body, isNot(containsPair('catalog_version', anything)));
      expect(body, isNot(containsPair('provisioner_role', anything)));
      expect(httpClient.lastRequest!.url.path, '/v1/shops/hanouti/info');
      expect(httpClient.lastRequest!.headers['Authorization'],
          'Bearer secret-token');
      expect(httpClient.lastRequest!.headers['Content-Type'],
          'application/json');
    });

    test('omits untouched fields and rejects an empty patch locally', () async {
      final httpClient = _RecordingClient((_) => _json(200, {'shop_key': 'x'}));
      final client = ShopInfoClient(
          baseUrl: 'https://example.test', token: 't', client: httpClient);

      await client.patch('x', const ShopInfoPatch(city: 'Rabat'));
      expect(jsonDecode(httpClient.lastBody!), {'city': 'Rabat'});

      expect(
        () => client.patch('x', const ShopInfoPatch()),
        throwsA(isA<ShopInfoBadRequestException>()),
      );
    });
  });

  group('ShopInfoClient error mapping', () {
    ShopInfoClient clientFor(int status) => ShopInfoClient(
          baseUrl: 'https://example.test',
          token: 't',
          client: _RecordingClient((_) => _json(status, {'detail': 'bad field'})),
        );

    test('400 -> BadRequest with server detail', () async {
      expect(
        clientFor(400).fetch('x'),
        throwsA(isA<ShopInfoBadRequestException>()
            .having((e) => e.message, 'message', 'bad field')
            .having((e) => e.statusCode, 'status', 400)),
      );
    });

    test('404 -> NotFound', () async {
      expect(clientFor(404).fetch('x'),
          throwsA(isA<ShopInfoNotFoundException>()));
    });

    test('409 -> Conflict', () async {
      expect(
        clientFor(409).patch('x', const ShopInfoPatch(city: 'Rabat')),
        throwsA(isA<ShopInfoConflictException>()),
      );
    });

    test('401/403 -> Forbidden', () async {
      expect(clientFor(401).fetch('x'),
          throwsA(isA<ShopInfoForbiddenException>()));
      expect(clientFor(403).fetch('x'),
          throwsA(isA<ShopInfoForbiddenException>()));
    });
  });

  test('fetch parses provisioning fields read-only', () async {
    final httpClient = _RecordingClient((_) => _json(200, {
          'shop_key': 'hanouti',
          'business_name': 'Hanouti',
          'address': '1 A',
          'city': 'Casablanca',
          'owner_name': 'Amina',
          'phone': '0600',
          'provisioner_signer_id': 'salesman-7',
          'provisioner_name': 'Youssef',
          'provisioner_role': 'salesman',
          'catalog_version': 3,
        }));
    final client = ShopInfoClient(
        baseUrl: 'https://example.test', token: 't', client: httpClient);
    final info = await client.fetch('hanouti');
    expect(info.provisionerSignerId, 'salesman-7');
    expect(info.provisionerName, 'Youssef');
    expect(info.provisionerRole, 'salesman');
    expect(info.catalogVersion, 3);
  });
}
