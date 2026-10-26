// Automated SpicySelf persona/UX audit.
// Run with: flutter test test/agent_audit_test.dart
// This uses an isolated fake backend; it does not alter production bookings.
import 'package:chairside/data/store.dart';
import 'package:chairside/screens/admin.dart';
import 'package:chairside/screens/app.dart';
import 'package:chairside/screens/common.dart';
import 'package:chairside/screens/business.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'redesign_test.dart' as roles;

Future<AppStore> launch(WidgetTester tester, roles.RoleBackend backend) async {
  final store = AppStore(backend);
  await store.refreshAccount();
  await tester.pumpWidget(SpicySelfApp(store: store, mapsEnabled: false));
  await tester.pumpAndSettle();
  return store;
}

Future<void> unload(WidgetTester tester, AppStore store) async {
  await tester.pumpWidget(const SizedBox.shrink());
  store.dispose();
}

void assertInteractiveControlsHaveSize(WidgetTester tester) {
  // Fail on buttons accidentally rendered at zero/tiny dimensions.
  // IconButtons use a 40px minimum in Flutter; text controls have
  // minimum dimensions set by the SpicySelf theme.
  for (final finder in <Finder>[
    find.byType(FilledButton),
    find.byType(OutlinedButton),
    find.byType(ElevatedButton),
    find.byType(IconButton),
  ]) {
    for (final element in finder.evaluate()) {
      final render = element.renderObject;
      if (render is! RenderBox || !render.hasSize) continue;
      expect(
        render.size.width,
        greaterThanOrEqualTo(40),
        reason: 'A button is too narrow to use comfortably',
      );
      expect(
        render.size.height,
        greaterThanOrEqualTo(40),
        reason: 'A button is too short to use comfortably',
      );
    }
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);

  testWidgets(
    'customer: every primary destination renders and has usable controls',
    (tester) async {
      final backend = roles.RoleBackend();
      final store = await launch(tester, backend);
      for (final tab in ['Explore', 'Map', 'My Bookings', 'Profile']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$tab must not throw on navigation',
        );
        assertInteractiveControlsHaveSize(tester);
      }
      expect(
        find.text('Administration'),
        findsNothing,
        reason: 'Customer must not receive the admin entry point',
      );
      await unload(tester, store);
    },
  );

  testWidgets('guest: sign-in actions are visible but admin is hidden', (
    tester,
  ) async {
    final backend = roles.RoleBackend()..userId = null;
    final store = await launch(tester, backend);
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.text('Choose Google account'), findsOneWidget);
    expect(find.text('Send sign-in link'), findsOneWidget);
    expect(find.text('Administration'), findsNothing);
    assertInteractiveControlsHaveSize(tester);
    expect(tester.takeException(), isNull);
    await unload(tester, store);
  });

  testWidgets('business: unapproved and suspended accounts cannot open tools', (
    tester,
  ) async {
    for (final status in ['pending', 'rejected', 'suspended']) {
      final backend = roles.RoleBackend()
        ..owner = true
        ..status = status;
      final store = AppStore(backend);
      await store.refreshAccount();
      await tester.pumpWidget(
        MaterialApp(
          theme: spicyThemeForAudit(),
          home: Scaffold(body: BusinessScreen(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        backend.operatorCalls,
        0,
        reason: '$status must not load owner-only RPCs',
      );
      expect(find.text('Business settings'), findsNothing);
      assertInteractiveControlsHaveSize(tester);
      expect(tester.takeException(), isNull);
      await unload(tester, store);
    }
  });

  testWidgets('business: approved owner without MFA cannot load tools', (
    tester,
  ) async {
    final backend = roles.RoleBackend()
      ..owner = true
      ..status = 'approved'
      ..mfa = false;
    final store = AppStore(backend);
    await store.refreshAccount();
    await tester.pumpWidget(
      MaterialApp(
        theme: spicyThemeForAudit(),
        home: Scaffold(body: BusinessScreen(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Protect your business'), findsOneWidget);
    expect(backend.operatorCalls, 0);
    expect(tester.takeException(), isNull);
    await unload(tester, store);
  });

  testWidgets('business: approved MFA owner can navigate management views', (
    tester,
  ) async {
    final backend = roles.RoleBackend()
      ..owner = true
      ..status = 'approved';
    final store = AppStore(backend);
    await store.refreshAccount();
    await tester.pumpWidget(
      MaterialApp(
        theme: spicyThemeForAudit(),
        home: Scaffold(body: BusinessScreen(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Live queue'), findsOneWidget);
    expect(backend.operatorCalls, greaterThan(0));
    assertInteractiveControlsHaveSize(tester);
    expect(tester.takeException(), isNull);
    await unload(tester, store);
  });

  testWidgets('admin: both admin claim and MFA are required', (tester) async {
    for (final flags in [(false, true), (true, false), (true, true)]) {
      final backend = roles.RoleBackend()
        ..admin = flags.$1
        ..mfa = flags.$2;
      final store = AppStore(backend);
      await store.refreshAccount();
      await tester.pumpWidget(
        MaterialApp(
          theme: spicyThemeForAudit(),
          home: Scaffold(body: AdminScreen(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      expect(backend.adminCalls, flags.$1 && flags.$2 ? 2 : 0);
      expect(tester.takeException(), isNull);
      assertInteractiveControlsHaveSize(tester);
      await unload(tester, store);
    }
  });

  testWidgets(
    'roles: account changes do not retain previous admin permissions',
    (tester) async {
      final backend = roles.RoleBackend()
        ..admin = true
        ..mfa = true;
      final store = await launch(tester, backend);
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      expect(find.text('Administration'), findsOneWidget);

      backend.userId = 'other-customer';
      backend.admin = false;
      backend.owner = false;
      await store.refreshAccount();
      await tester.pumpAndSettle();
      expect(store.isAdmin, isFalse);
      expect(store.businessId, isNull);
      expect(find.text('Administration'), findsNothing);
      expect(tester.takeException(), isNull);
      await unload(tester, store);
    },
  );

  testWidgets(
    'layout: core journeys survive common mobile and desktop widths',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [320.0, 375.0, 430.0, 1024.0]) {
        await tester.binding.setSurfaceSize(Size(width, 850));
        final backend = roles.RoleBackend();
        final store = await launch(tester, backend);
        for (final tab in ['Explore', 'Map', 'My Bookings', 'Profile']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$tab must render at width $width',
          );
        }
        await unload(tester, store);
      }
    },
  );
}

// Imports theme from the shared app code rather than reproducing the design.
ThemeData spicyThemeForAudit() => spicyTheme();
