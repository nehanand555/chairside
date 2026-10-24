import 'dart:async';
import 'dart:typed_data';
import 'package:chairside/data/backend.dart';
import 'package:chairside/data/store.dart';
import 'package:chairside/screens/app.dart';
import 'package:chairside/screens/discover.dart';
import 'package:chairside/screens/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;

class TestBackend extends Backend {
  @override
  String? userId = 'customer';
  StreamController<void>? authEvents;
  @override
  Stream<void> get authChanges => authEvents?.stream ?? const Stream.empty();
  int googleSignIns = 0;
  Object? googleError;
  final Map<String, String> googleNames = {};
  @override
  String? get suggestedName => googleNames[userId];
  int initializedProfiles = 0;
  final Map<String, Json> profiles = {
    for (final user in ['customer', 'owner']) user: {
      'id': user, 'display_name': 'Customer', 'sms_updates': false, 'marketing_consent': false,
    },
  };
  Json? discoverFailure;
  final List<Json> discoverRequests = [];
  final List<Json> publicPlaces = [];
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
          'business_id': userId == 'owner' ? 'p1' : null,
          'business_status': userId == 'owner' ? 'approved' : null
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
    if (table == 'profiles') return profiles[filters['id']] == null ? [] : [Json.from(profiles[filters['id']]!)];
    if (table == 'visits') return visits.map(Json.from).toList();
    if (table == 'favorites') return [];
    throw StateError(table);
  }

  @override
  Future<Json> invoke(String name, Json data) async {
    discoverRequests.add(Json.from(data));
    if (discoverFailure != null && data['query'] == discoverFailure!['query']) throw Exception(discoverFailure!['message']);
    return {
        'center': {'lat': -36.85, 'lng': 174.76},
        'businesses': [business],
        'places': publicPlaces,
        'warning': null
      };
  }
  @override
  Future<List<String>> photos(String business) async => [];
  @override
  Future<List<Json>> factors() async => [];
  @override
  Future<void> save(String table, Json values) async {
    if (table == 'profiles') profiles[values['id'] as String] = {...?profiles[values['id']], ...values};
  }
  @override
  Future<void> initializeProfile(String user, String displayName) async {
    initializedProfiles++;
    profiles.putIfAbsent(user, () => {'id': user, 'display_name': displayName, 'sms_updates': false, 'marketing_consent': false});
    if (profiles[user]!['display_name'] == '') profiles[user]!['display_name'] = displayName;
  }
  @override
  Future<void> remove(String table, Json filters) async {}
  @override
  Future<void> signInWithGoogle() async {
    googleSignIns++;
    if (googleError != null) throw googleError!;
  }
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
  test('public listings show separate, safe booking and website links', () {
    final homepage = <String, dynamic>{
      'website_url': 'https://example.com/',
    };
    expect(publicWebsiteUrl(homepage), 'https://example.com/');
    expect(publicBookingUrl(homepage), isNull);

    final direct = <String, dynamic>{
      'website_url': 'https://example.com/book-now',
    };
    expect(publicBookingUrl(direct), 'https://example.com/book-now');
    expect(publicWebsiteUrl(direct), 'https://example.com/book-now');

    final external = <String, dynamic>{
      'website_url': 'https://example.com/',
      'booking_url': 'https://booksy.com/en-nz/12345',
    };
    expect(publicBookingUrl(external), 'https://booksy.com/en-nz/12345');

    final unsafe = <String, dynamic>{
      'website_url': 'javascript:alert(1)',
      'booking_url': 'http://insecure.example/book',
    };
    expect(publicWebsiteUrl(unsafe), isNull);
    expect(publicBookingUrl(unsafe), isNull);
  });

  test('NZ phone input and money use consistent formats', () {
    expect(normalizePhone('021 123 4567'), '+64211234567');
    expect(normalizePhone('+64 (21) 123-4567'), '+64211234567');
    expect(() => normalizePhone('abc'), throwsException);
    expect(money(3500), '\$35.00');
    expect(nzTime('2026-10-18T00:00:00Z'), contains('1:00 PM'));
  });
  testWidgets('Google login requires terms and receives the returned session without SMS', (tester) async {
    final backend = TestBackend()..userId = null;
    final events = StreamController<void>.broadcast();
    backend.authEvents = events;
    final store = AppStore(backend);
    await tester.pumpWidget(SpicySelfApp(store: store, mapsEnabled: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();
    expect(find.text('Phone number'), findsNothing);
    expect(find.text('Text me a code'), findsNothing);
    await tapVisible(tester, find.text('Continue with Google'));
    expect(backend.googleSignIns, 0);
    expect(find.textContaining('Please read and accept'), findsOneWidget);
    await tapVisible(tester, find.byType(CheckboxListTile));
    await tapVisible(tester, find.text('Continue with Google'));
    expect(backend.googleSignIns, 1);
    expect(store.signedIn, false); // Opening the browser does not create a session.
    backend.googleNames['google-customer'] = 'Nikita';
    backend.userId = 'google-customer';
    events.add(null); // Supabase emits this after exchanging the PKCE code.
    await tester.pumpAndSettle();
    expect(find.text('Your account'), findsOneWidget);
    expect(find.text('Hi, Nikita'), findsOneWidget);
    expect(backend.profiles['google-customer']!['display_name'], 'Nikita');
    final nameInput = find.descendant(of: find.byType(FormFieldBox).first, matching: find.byType(TextFormField));
    expect(tester.widget<TextFormField>(nameInput).controller!.text, 'Nikita');
    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Booking texts'), findsNothing);
    await tapVisible(tester, find.text('Sign out'));
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(store.visits, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    await events.close();
  });
  testWidgets('Google launch and callback failures leave sign-in available to retry', (tester) async {
    final backend = TestBackend()..userId = null;
    final events = StreamController<void>.broadcast();
    backend.authEvents = events;
    backend.googleError = Exception('Could not open Google sign-in. Please try again.');
    final store = AppStore(backend);
    await tester.pumpWidget(SpicySelfApp(store: store, mapsEnabled: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byType(CheckboxListTile));
    await tapVisible(tester, find.text('Continue with Google'));
    expect(find.textContaining('Could not open Google sign-in'), findsOneWidget);
    expect(store.busy, false);
    expect(store.signedIn, false);
    backend.googleError = null;
    await tapVisible(tester, find.text('Continue with Google'));
    expect(backend.googleSignIns, 2);
    events.addError(Exception('Google sign-in was cancelled. Please try again.'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Google sign-in was cancelled'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(store.signedIn, false);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    await events.close();
  });
  test('Google names initialize missing profiles without replacing saved names or consent', () async {
    final backend = TestBackend()..userId = 'fresh-google';
    backend.googleNames['fresh-google'] = 'Nikita';
    final store = AppStore(backend);
    await store.refreshAccount();
    expect(store.displayName, 'Nikita');
    expect(backend.profiles['fresh-google']!['display_name'], 'Nikita');
    await store.saveProfile('Niki', false, true);
    backend.googleNames['fresh-google'] = 'Different Google name';
    await store.refreshAccount();
    expect(store.displayName, 'Niki');
    expect(backend.profiles['fresh-google']!['marketing_consent'], true);
    final secondSession = AppStore(backend);
    await secondSession.refreshAccount();
    expect(secondSession.displayName, 'Niki');
    backend.userId = null;
    await store.refreshAccount();
    expect(store.displayName, '');
    store.dispose();
    secondSession.dispose();
  });
  test('an empty saved name can be initialized without opting into texts', () async {
    final backend = TestBackend();
    backend.profiles['customer']!['display_name'] = '';
    backend.profiles['customer']!['marketing_consent'] = true;
    backend.googleNames['customer'] = 'Google name';
    final store = AppStore(backend);
    await store.refreshAccount();
    expect(store.displayName, 'Google name');
    expect(store.profile['sms_updates'], false);
    expect(store.profile['marketing_consent'], true);
    store.dispose();
  });
  testWidgets('Google listings and postcode retries work when the map is unavailable', (tester) async {
    final backend = TestBackend();
    backend.publicPlaces.add({'place_id':'google-barber', 'name':'Google Barber', 'address':'Porirua 5014', 'lat':-41.1, 'lng':174.9, 'maps_url':'https://maps.google.com/', 'attributions': <Json>[]});
    final store = AppStore(backend);
    await store.refreshAccount();
    await tester.pumpWidget(SpicySelfApp(store: store, mapsEnabled: false));
    await tester.pumpAndSettle();
    expect(backend.discoverRequests.last['include_public'], true);
    await tester.ensureVisible(find.text('Google Barber'));
    await tester.pumpAndSettle();
    expect(find.text('Google Barber'), findsOneWidget);
    backend.discoverFailure = {'query':'5014', 'message':'Search temporarily unavailable'};
    final search = find.byType(TextField).first;
    await tester.ensureVisible(search);
    await tester.pumpAndSettle();
    await tester.enterText(search, '5014');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Search'));
    expect(backend.discoverRequests.last['query'], '5014');
    expect(find.text('Google Barber'), findsNothing);
    expect(find.text('Search temporarily unavailable'), findsOneWidget);
    backend.discoverFailure = null;
    await tapVisible(tester, find.text('Try again'));
    expect(backend.discoverRequests.last['query'], '5014');
    expect(find.text('Google Barber'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
  testWidgets(
      'customer joins queue, business serves them, customer sees completion',
      (tester) async {
    final backend = TestBackend();
    // One transport is shared by both roles, as the real database is.
    final app = AppStore(backend);
    await app.refreshAccount();
    await tester.pumpWidget(SpicySelfApp(store: app, mapsEnabled: false));
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
    await tapVisible(tester, find.text('Account').last);
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Open business'));
    await tester.pumpAndSettle();
    expect(app.businessId, 'p1');
    expect(app.visits.single['status'], 'waiting');
    expect(find.text('Harbour Cuts'), findsWidgets);
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
      final backend = TestBackend();
      backend.profiles['customer']!['display_name'] = List.filled(20, 'Long name').join(' ');
      final store = AppStore(backend);
      await store.refreshAccount();
      await tester.pumpWidget(
          SpicySelfApp(key: ValueKey(size), store: store, mapsEnabled: false));
      await tester.pumpAndSettle();
      expect(find.text('Find your next look.'), findsOneWidget);
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
    await tester.pumpWidget(SpicySelfApp(store: store));
    await tester.pumpAndSettle();
    expect(find.textContaining('being connected'), findsOneWidget);
    expect(find.text('Harbour Cuts'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
