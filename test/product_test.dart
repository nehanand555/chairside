import 'dart:typed_data';
import 'package:chairside/data/backend.dart';
import 'package:chairside/data/store.dart';
import 'package:chairside/screens/app.dart';
import 'package:chairside/screens/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;

class TestBackend extends Backend {
  @override
  String? userId = 'customer';
  @override
  Stream<void> get authChanges => const Stream.empty();
  final List<Json> visits = [];
  final Json business = {
    'id': 'p1',
    'name': 'Harbour Cuts',
    'kind': 'barber',
    'description': 'Local hair professionals',
    'suburb': 'Auckland',
    'lat': -36.85,
    'lng': 174.76,
    'distance_km': 1.2,
    'queue_open': true,
    'status': 'approved',
    'review_note': '',
    'online_payments': false,
    'services': [
      {
        'id': 's1',
        'name': 'Haircut',
        'minutes': 30,
        'price_cents': 3500,
        'active': true
      }
    ],
    'resources': [
      {'id': 'r1', 'name': 'Chair 1', 'active': true}
    ],
    'hours': <Json>[]
  };
  @override
  Future<dynamic> rpc(String name, [Json params = const {}]) async {
    switch (name) {
      case 'account_context':
        return {
          'is_admin': false,
          'aal2': userId == 'owner',
          'business_id': userId == 'owner' ? 'p1' : null
        };
      case 'business_detail':
      case 'operator_business':
        return business;
      case 'queue_estimates': return <Json>[{'resource_id':'r1','name':'Chair 1','waiting':0,'wait_minutes':1}];
      case 'available_slots':
        return <Json>[];
      case 'refresh_queues':
        return null;
      case 'my_visits':
        return visits.skip(params['p_offset'] as int? ?? 0).take(200).map(Json.from).toList();
      case 'create_visit':
        expect(params['p_kind'], 'queue');
        visits.add({
          'id': 'v1',
          'business_id': 'p1',
          'resource_id': 'r1',
          'customer_id': 'customer',
          'customer_name': 'Customer',
          'service_name': 'Haircut',
          'minutes': 30,
          'price_cents': 3500,
          'kind': 'queue',
          'status': 'waiting',
          'starts_at': '2026-10-18T00:00:00Z',
          'payment_status': 'unpaid',
          'created_at': '2026-10-17T23:00:00Z'
        });
        return 'v1';
      case 'change_visit':
        visits.first['status'] =
            params['p_action'] == 'start' ? 'serving' : 'completed';
        return null;
    }
    throw StateError('Unexpected RPC: $name');
  }

  @override
  Future<List<Json>> rows(String table,
      {Json filters = const {}, String? order, int limit = 100}) async {
    if (table == 'profiles')
      return [
        {
          'id': userId,
          'display_name': 'Customer',
          'sms_updates': false,
          'marketing_consent': false
        }
      ];
    if (table == 'visits') return visits.map(Json.from).toList();
    if (table == 'favorites') return [];
    throw StateError(table);
  }

  @override
  Future<Json> invoke(String name, Json data) async => {
        'center': {'lat': -36.85, 'lng': 174.76},
        'businesses': [business],
        'places': <Json>[],
        'warning': null
      };
  @override
  Future<List<String>> photos(String business) async => [];
  @override
  Future<List<Json>> factors() async => [];
  @override
  Future<void> save(String table, Json values) async {}
  @override
  Future<void> remove(String table, Json filters) async {}
  @override
  Future<void> sendCode(String phone) async {}
  @override
  Future<void> verifyCode(String phone, String code) async {}
  @override
  Future<void> signOut() async {
    userId = null;
  }

  @override
  Future<Json> enrollFactor() async => {'id': 'factor', 'secret': 'secret'};
  @override
  Future<void> verifyFactor(String id, String code) async {}
  @override
  Future<void> discardFactor(String id) async {}
  @override
  Future<void> uploadPhoto(
      String business, Uint8List bytes, String extension) async {}
  @override
  Future<void> deletePhoto(String business, String url) async {}
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(tz.initializeTimeZones);
  test('NZ phone input and money use consistent formats', () {
    expect(normalizePhone('021 123 4567'), '+64211234567');
    expect(normalizePhone('+64 (21) 123-4567'), '+64211234567');
    expect(() => normalizePhone('abc'), throwsException);
    expect(money(3500), '\$35.00');
    expect(nzTime('2026-10-18T00:00:00Z'), contains('1:00 PM'));
  });
  testWidgets(
      'customer joins queue, business serves them, customer sees completion',
      (tester) async {
    final backend = TestBackend();
    // One transport is shared by both roles, as the real database is.
    final app = AppStore(backend);
    await app.refreshAccount();
    await tester.pumpWidget(ChairsideApp(store: app, mapsEnabled: false));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const ValueKey('view-p1')));
    final picker = find.byKey(const ValueKey('service-picker'));
    await tapVisible(tester, picker);
    await tester.tap(find.text('Haircut • 30 min • \$35.00').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Join live queue'));
    await tapVisible(tester, find.byKey(const ValueKey('confirm-visit')));
    await tester.tap(find.widgetWithText(FilledButton, 'Join queue').last);
    await tester.pumpAndSettle();
    expect(backend.visits.single['status'], 'waiting');
    await tester.pageBack();
    await tester.pumpAndSettle();
    backend.userId = 'owner';
    await app.refreshAccount();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Business').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Start'));
    expect(backend.visits.single['status'], 'serving');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Finish'));
    backend.userId = 'customer';
    await app.refreshAccount();
    await tester.pumpAndSettle();
    await tester.tap(find.text('My visits').last);
    await tester.pumpAndSettle();
    expect(find.text('completed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
  testWidgets('discovery and navigation fit small phones and desktop',
      (tester) async {
    for (final size in [
      const Size(320, 700),
      const Size(390, 844),
      const Size(1200, 900)
    ]) {
      await tester.binding.setSurfaceSize(size);
      final store = AppStore(TestBackend());
      await store.refreshAccount();
      await tester.pumpWidget(
          ChairsideApp(key: ValueKey(size), store: store, mapsEnabled: false));
      await tester.pumpAndSettle();
      expect(find.text('Find your next chair.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    }
    await tester.binding.setSurfaceSize(null);
  });
  test('loaded history survives live refreshes', () async {
    final backend = TestBackend();
    backend.visits.addAll(List.generate(205, (i) => <String, dynamic>{'id': 'v$i', 'status': 'completed'}));
    final store = AppStore(backend);
    await store.refreshAccount();
    expect(store.visits.length, 200);
    await store.loadMoreVisits();
    expect(store.visits.length, 205);
    await store.refreshVisits();
    expect(store.visits.length, 205);
    expect(store.moreVisits, false);
    store.dispose();
  });
  testWidgets('missing service configuration never shows fake listings',
      (tester) async {
    final store = AppStore(null);
    await tester.pumpWidget(ChairsideApp(store: store));
    await tester.pumpAndSettle();
    expect(find.textContaining('being connected'), findsOneWidget);
    expect(find.text('Harbour Cuts'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
