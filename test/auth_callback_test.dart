import 'package:chairside/data/auth_callback.dart';
import 'package:chairside/data/store.dart';
import 'package:chairside/screens/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'product_test.dart' as fixtures;

class MemoryStorage extends LocalStorage {
  String? value = 'previous-session';
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => value != null;
  @override
  Future<String?> accessToken() async => value;
  @override
  Future<void> persistSession(String session) async {
    value = session;
  }

  @override
  Future<void> removePersistedSession() async {
    value = null;
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  test(
    'auth callback detection includes errors but ignores ordinary navigation',
    () {
      for (final suffix in [
        '?code=synthetic',
        '?code=synthetic#bad=%ZZ',
        '?code=%ZZ',
        '?error=denied',
        '#error_description=expired',
        '#access_token=synthetic',
      ]) {
        expect(
          isAuthCallback(Uri.parse('https://www.spicyself.com/$suffix')),
          isTrue,
        );
      }
      expect(
        isAuthCallback(Uri.parse('https://www.spicyself.com/?business=1')),
        isFalse,
      );
    },
  );
  test('callback storage discards old account without restoring it and persists new sessions', () async {
    final memory = MemoryStorage();
    final storage = CallbackLocalStorage(memory);
    await storage.initialize();
    expect(memory.value, isNull);
    expect(await storage.hasAccessToken(), isFalse);
    expect(await storage.accessToken(), isNull);
    await storage.persistSession('verified-new-session');
    expect(memory.value, 'verified-new-session');
    expect(await storage.hasAccessToken(), isFalse);
  });
  test(
    'failed callback returns no identity and no raw provider error',
    () async {
      final result = await resolveAuthCallback(
        () async => throw const AuthException('private-provider-details'),
      );
      expect(result.succeeded, isFalse);
      expect(result.email, isNull);
    },
  );
  testWidgets(
    'failed callback blocks existing session until explicit sign-out',
    (tester) async {
      final backend = fixtures.TestBackend();
      final store = AppStore(backend);
      await store.refreshAccount();
      await tester.pumpWidget(
        SpicySelfApp(
          store: store,
          mapsEnabled: false,
          authCallback: const AuthCallbackResult(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('This sign-in link did not finish'), findsOneWidget);
      expect(find.text('My Bookings'), findsNothing);
      expect(find.text('Continue with this account'), findsNothing);
      await fixtures.tapVisible(tester, find.text('Back to sign in'));
      expect(backend.userId, isNull);
      expect(store.account, isEmpty);
      expect(find.text('Choose Google account'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );
  testWidgets(
    'successful callback requires confirmation of the returned identity',
    (tester) async {
      final backend = fixtures.TestBackend();
      final store = AppStore(backend);
      await store.refreshAccount();
      await tester.pumpWidget(
        SpicySelfApp(
          store: store,
          mapsEnabled: false,
          authCallback: const AuthCallbackResult(
            userId: 'customer',
            email: 'correct@example.test',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('correct@example.test'), findsOneWidget);
      expect(find.text('My Bookings'), findsNothing);
      await fixtures.tapVisible(
        tester,
        find.text('Continue with this account'),
      );
      expect(find.text('Your account'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );
  testWidgets(
    'mismatched browser session cannot confirm a different callback identity',
    (tester) async {
      final store = AppStore(fixtures.TestBackend());
      await store.refreshAccount();
      await tester.pumpWidget(
        SpicySelfApp(
          store: store,
          mapsEnabled: false,
          authCallback: const AuthCallbackResult(
            userId: 'other',
            email: 'other@example.test',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue with this account'), findsNothing);
      expect(find.text('This sign-in link did not finish'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );
}
