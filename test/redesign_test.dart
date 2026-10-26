import 'package:chairside/data/backend.dart';
import 'package:chairside/data/store.dart';
import 'package:chairside/screens/admin.dart';
import 'package:chairside/screens/app.dart';
import 'package:chairside/screens/business.dart';
import 'package:chairside/screens/common.dart';
import 'package:chairside/screens/discover.dart';
import 'package:chairside/screens/visits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'product_test.dart' as fixtures;

class RoleBackend extends fixtures.TestBackend {
  bool owner = false, admin = false, mfa = true, notificationFails = false;
  String status = 'pending';
  bool alreadyProcessed = false;
  int operatorCalls = 0, adminCalls = 0, applications = 0, notifications = 0;
  Json? application;
  @override
  Future<dynamic> rpc(String name, [Json params = const {}]) async {
    if (name == 'account_context')
      return {
        'is_admin': admin,
        'aal2': mfa,
        'business_id': owner ? 'p1' : null,
        'business_status': owner ? status : null,
        'business_review_note': status == 'rejected'
            ? 'Please provide ownership evidence.'
            : '',
      };
    if (name == 'operator_business') operatorCalls++;
    if (name == 'admin_email_overview')
      return {'pending': 0, 'accepted': 0, 'delivered': 0, 'failed': 0};
    if (name == 'admin_email_events') return <Json>[];
    if (name == 'admin_overview' || name == 'admin_health') {
      adminCalls++;
      return name == 'admin_overview'
          ? {'businesses': <Json>[], 'reports': <Json>[]}
          : {'failed_sms': 0, 'pending_sms': 0, 'pending_refunds': 0};
    }
    if (name == 'apply_business') {
      applications++;
      application = Json.from(params['p_data'] as Map);
      owner = true;
      status = 'pending';
      return 'p1';
    }
    return super.rpc(name, params);
  }

  @override
  Future<Json> invoke(String name, Json data) async {
    if (name == 'business-address') {
      if (data['action'] == 'suggest') {
        return {
          'suggestions': [
            {
              'place_id': 'test-address-123',
              'description': '12 Test Street, Auckland, New Zealand',
            },
          ],
        };
      }
      if (data['action'] == 'select') {
        return {
          'address': '12 Test Street, Auckland, New Zealand',
          'suburb': 'Auckland',
          'lat': -36.85,
          'lng': 174.76,
          'place_id': 'test-address-123',
        };
      }
    }
    if (name == 'business-application-notify') {
      notifications++;
      if (alreadyProcessed) return {'already_processed': true};
      if (notificationFails) throw Exception('Verified sender required');
      return {'email_queued': true};
    }
    return super.invoke(name, data);
  }
}

Future<AppStore> mount(
  WidgetTester tester,
  RoleBackend backend,
  Widget Function(AppStore) screen,
) async {
  final store = AppStore(backend);
  await store.refreshAccount();
  await tester.pumpWidget(
    MaterialApp(
      theme: spicyTheme(),
      home: Scaffold(body: screen(store)),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

Future<void> close(WidgetTester tester, AppStore store) async {
  await tester.pumpWidget(const SizedBox.shrink());
  store.dispose();
}

void main() {
  setUpAll(tz.initializeTimeZones);

  test(
    'no-pending notification response does not claim provider acceptance',
    () async {
      final backend = RoleBackend()..alreadyProcessed = true;
      final store = AppStore(backend);
      await store.refreshAccount();
      await sendApplicationNotification(store, 'p1');
      expect(store.applicationNotificationMessage, contains('no outstanding'));
      expect(store.applicationNotificationMessage, isNot(contains('queued')));
      store.dispose();
    },
  );

  testWidgets(
    'four customer tabs share discovery and keep admin outside navigation',
    (tester) async {
      final backend = RoleBackend()..admin = true;
      final store = AppStore(backend);
      await store.refreshAccount();
      await tester.pumpWidget(SpicySelfApp(store: store, mapsEnabled: false));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((d) => d.label),
        ['Explore', 'Map', 'My Bookings', 'Profile'],
      );
      final requests = backend.discoverRequests.length;
      await tester.tap(find.text('Map').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Map view is unavailable'), findsOneWidget);
      // Opening Map refreshes recently approved member listings.
      expect(backend.discoverRequests.length, requests + 1);
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      expect(find.text('spicyself for Business'), findsOneWidget);
      expect(find.text('Administration'), findsOneWidget);
      await close(tester, store);
    },
  );

  testWidgets('category and favourites filters use real member data', (
    tester,
  ) async {
    final backend = RoleBackend();
    final store = await mount(
      tester,
      backend,
      (s) => DiscoverScreen(store: s, mapsEnabled: false),
    );
    expect(find.text('Harbour Cuts'), findsOneWidget);
    await fixtures.tapVisible(tester, find.text('Home Studios'));
    expect(find.text('Harbour Cuts'), findsNothing);
    await fixtures.tapVisible(tester, find.text('All'));
    expect(find.text('Harbour Cuts'), findsOneWidget);
    await fixtures.tapVisible(tester, find.text('Favourites'));
    expect(find.text('Harbour Cuts'), findsNothing);
    expect(find.textContaining('No saved businesses'), findsOneWidget);
    await close(tester, store);
  });

  testWidgets(
    'public listing has no member badge, invented distance or in-app booking',
    (tester) async {
      final backend = RoleBackend();
      final store = await mount(
        tester,
        backend,
        (s) => PublicBusinessCard(
          store: s,
          place: {
            'name': 'Public Salon',
            'address': 'Wellington',
            'website_url': 'https://example.com/',
            'maps_url': 'https://maps.google.com/',
            'place_id': 'public',
          },
        ),
      );
      expect(find.text('Public Google listing'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);
      expect(find.text('Book externally'), findsNothing);
      expect(find.textContaining('Verified'), findsNothing);
      expect(find.text('Services & availability'), findsNothing);
      expect(find.textContaining('0.0 km'), findsNothing);
      await close(tester, store);
    },
  );

  testWidgets(
    'My Bookings separates upcoming, completed and cancelled visits',
    (tester) async {
      final backend = RoleBackend();
      for (final status in ['waiting', 'completed', 'cancelled']) {
        backend.visits.add({
          'id': status,
          'customer_id': 'customer',
          'business_id': 'p1',
          'business_name': 'Harbour Cuts',
          'service_name': 'Haircut',
          'kind': 'appointment',
          'starts_at': '2026-10-24T00:00:00Z',
          'minutes': 30,
          'price_cents': 3500,
          'status': status,
          'payment_status': 'unpaid',
        });
      }
      final store = await mount(tester, backend, (s) => VisitsScreen(store: s));
      expect(find.text('waiting'), findsOneWidget);
      expect(find.text('completed'), findsNothing);
      await fixtures.tapVisible(tester, find.text('Completed'));
      expect(find.text('completed'), findsOneWidget);
      expect(find.text('waiting'), findsNothing);
      await fixtures.tapVisible(tester, find.text('Cancelled'));
      expect(find.text('cancelled'), findsOneWidget);
      expect(find.text('completed'), findsNothing);
      await close(tester, store);
    },
  );

  testWidgets('admin data requires both server role and MFA', (tester) async {
    for (final flags in [(false, true), (true, false), (true, true)]) {
      final backend = RoleBackend()
        ..admin = flags.$1
        ..mfa = flags.$2;
      final store = await mount(tester, backend, (s) => AdminScreen(store: s));
      expect(backend.adminCalls, flags.$1 && flags.$2 ? 2 : 0);
      if (!flags.$1) expect(find.text('Restricted access'), findsOneWidget);
      if (flags.$1 && flags.$2) expect(find.text('Pending'), findsOneWidget);
      await close(tester, store);
    }
  });

  testWidgets('customer pages support narrow screens and large text', (
    tester,
  ) async {
    for (final width in [320.0, 390.0, 900.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      tester.platformDispatcher.textScaleFactorTestValue = width == 320
          ? 1.6
          : 1;
      final backend = RoleBackend();
      final store = AppStore(backend);
      await store.refreshAccount();
      await tester.pumpWidget(
        SpicySelfApp(key: ValueKey(width), store: store, mapsEnabled: false),
      );
      await tester.pumpAndSettle();
      for (final label in ['Map', 'My Bookings', 'Profile', 'Explore']) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await close(tester, store);
    }
    await tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('pending and rejected applications cannot load management data', (
    tester,
  ) async {
    for (final status in ['pending', 'rejected', 'suspended']) {
      final backend = RoleBackend()
        ..owner = true
        ..status = status;
      final store = await mount(
        tester,
        backend,
        (s) => BusinessScreen(store: s),
      );
      expect(backend.operatorCalls, 0);
      expect(find.text('Business settings'), findsNothing);
      if (status == 'pending')
        expect(find.text('Application under review'), findsOneWidget);
      if (status == 'rejected') {
        expect(find.textContaining('ownership evidence'), findsOneWidget);
        expect(find.text('Edit and reapply'), findsOneWidget);
      }
      if (status == 'suspended')
        expect(find.text('Edit and reapply'), findsNothing);
      await close(tester, store);
    }
  });

  testWidgets('business status stays focused and fits a narrow phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final status in ['pending', 'rejected']) {
      final backend = RoleBackend()
        ..owner = true
        ..status = status;
      final store = await mount(
        tester,
        backend,
        (s) => BusinessScreen(store: s),
      );
      store.applicationNotificationMessage =
          'Resend credentials configuration needs attention';
      store.changed();
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.textContaining('Resend credentials'), findsNothing);
      expect(find.text('Check notification').hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
      await close(tester, store);
    }
  });

  testWidgets('approved owners still need MFA before loading management data', (
    tester,
  ) async {
    final backend = RoleBackend()
      ..owner = true
      ..status = 'approved'
      ..mfa = false;
    final store = await mount(tester, backend, (s) => BusinessScreen(store: s));
    expect(find.text('Protect your business'), findsOneWidget);
    expect(backend.operatorCalls, 0);
    await close(tester, store);
  });

  testWidgets('approved MFA owners receive the business workspace', (
    tester,
  ) async {
    final backend = RoleBackend()
      ..owner = true
      ..status = 'approved';
    final store = await mount(tester, backend, (s) => BusinessScreen(store: s));
    expect(backend.operatorCalls, greaterThan(0));
    expect(find.text('Live queue'), findsOneWidget);
    await fixtures.tapVisible(tester, find.text('Calendar'));
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(find.text('No appointments on this date.'), findsOneWidget);
    await fixtures.tapVisible(tester, find.text('Business settings'));
    expect(find.text('Services & pricing'), findsOneWidget);
    await close(tester, store);
  });

  testWidgets(
    'application steps validate and notification retry never reapplies',
    (tester) async {
      final backend = RoleBackend()..notificationFails = true;
      final store = await mount(
        tester,
        backend,
        (s) => BusinessScreen(store: s),
      );
      await fixtures.tapVisible(tester, find.text('Continue'));
      expect(find.text('Step 1 of 4 · Business'), findsOneWidget);
      Future<void> fill(String label, String text) =>
          tester.enterText(find.byKey(ValueKey(label)), text);
      await fill('Registered business / trading name', 'Harbour Studio');
      await fill('NZBN or business registration number', 'Not applicable');
      await fixtures.tapVisible(tester, find.text('Continue'));
      expect(find.text('Step 2 of 4 · Contact'), findsOneWidget);
      await fill('Contact person full name', 'Sam Owner');
      await fill('Business contact email', 'owner@example.com');
      await fill('Business contact phone', '021 123 4567');
      await fixtures.tapVisible(tester, find.text('Continue'));
      expect(find.text('Suburb / town'), findsNothing);
      expect(find.text('Pin latitude'), findsNothing);
      expect(find.text('Pin longitude'), findsNothing);
      expect(find.text('Google Place ID (optional)'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business street address'),
        '12 Test Street',
      );
      await fixtures.tapVisible(tester, find.text('Continue'));
      expect(find.text('Step 3 of 4 · Location'), findsOneWidget);
      expect(
        find.text('Choose a suggestion or confirm the map pin'),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await fixtures.tapVisible(
        tester,
        find.text('12 Test Street, Auckland, New Zealand'),
      );
      await fixtures.tapVisible(tester, find.text('Continue'));
      expect(find.text('Step 4 of 4 · Review'), findsOneWidget);
      await fixtures.tapVisible(tester, find.byType(CheckboxListTile).first);
      await fixtures.tapVisible(tester, find.byType(CheckboxListTile).last);
      await fixtures.tapVisible(
        tester,
        find.text('Submit business application'),
      );
      expect(backend.applications, 1);
      expect(backend.application?['contact_email'], 'owner@example.com');
      expect(
        backend.application?['address'],
        '12 Test Street, Auckland, New Zealand',
      );
      expect(backend.application?['suburb'], 'Auckland');
      expect(backend.application?['lat'], -36.85);
      expect(backend.application?['lng'], 174.76);
      expect(backend.application?['place_id'], 'test-address-123');
      expect(find.text('Application under review'), findsOneWidget);
      expect(
        store.applicationNotificationMessage,
        contains('Application saved'),
      );
      expect(backend.operatorCalls, 0);
      backend.notificationFails = false;
      await fixtures.tapVisible(tester, find.text('Email updates'));
      await fixtures.tapVisible(tester, find.text('Check notification'));
      expect(backend.applications, 1);
      expect(backend.notifications, 2);
      expect(store.applicationNotificationMessage, contains('queued'));
      await close(tester, store);
    },
  );
}
