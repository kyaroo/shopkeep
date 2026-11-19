// Phase 3 — « Publish changes »: push local changes, then adopt the server's
// new global generation. The local generation must not move on a failure.
//
// Run: flutter test test/services/catalog_publish_service_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:myhanout/services/catalog_publish_service.dart';

import '../helpers/fake_settings.dart';

class _FakeClient extends CatalogSyncClient {
  final int version;
  final Object? failWith;

  _FakeClient(this.version, {this.failWith})
      : super(baseUrl: '', token: '', deviceId: 'test');

  @override
  Future<int> catalogVersion() async {
    if (failWith != null) throw failWith!;
    return version;
  }

  @override
  void close() {}
}

void main() {
  late FakeSettingsService settings;

  setUp(() {
    settings = FakeSettingsService()..catalogVersion = 1;
  });

  CatalogPublishService service(CatalogSyncClient client) =>
      CatalogPublishService(
        settings: settings,
        clientFactory: () async => client,
      );

  test('adopts the server version after a successful push', () async {
    final result = await service(_FakeClient(5)).publish(push: () async => true);

    expect(result.ok, isTrue);
    expect(result.oldVersion, 1);
    expect(result.newVersion, 5);
    expect(result.changed, isTrue);
    expect(settings.catalogVersion, 5);
  });

  test('a rejected push leaves the local version untouched', () async {
    final result =
        await service(_FakeClient(5)).publish(push: () async => false);

    expect(result.ok, isFalse);
    expect(settings.catalogVersion, 1);
  });

  test('a version lookup failure leaves the local version untouched', () async {
    final result = await service(_FakeClient(5, failWith: StateError('down')))
        .publish(push: () async => true);

    expect(result.ok, isFalse);
    expect(result.error, contains('down'));
    expect(settings.catalogVersion, 1);
  });

  test('an unchanged server version reports ok without moving', () async {
    settings.catalogVersion = 5;
    final result = await service(_FakeClient(5)).publish(push: () async => true);

    expect(result.ok, isTrue);
    expect(result.changed, isFalse);
    expect(settings.catalogVersion, 5);
  });
}
