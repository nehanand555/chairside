import 'dart:async';

import 'package:qr_flutter/qr_flutter.dart';
import 'package:chairside/data/backend.dart';
import 'package:chairside/data/store.dart';
import 'package:chairside/screens/account.dart';
import 'package:chairside/screens/admin.dart';
import 'package:chairside/screens/visits.dart';
import 'package:chairside/screens/admin_visits.dart';
import 'package:chairside/screens/booking.dart';
import 'package:chairside/screens/business.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'product_test.dart' as fixtures;
import 'redesign_test.dart' as redesign;

class RejectedApplicationBackend extends redesign.RoleBackend {
  int resubmissions = 0;
  bool saveFails = false;
  Completer<void>? delayedSave;
  Completer<Json>? delayedNotification;
  @override
  Future<Json> invoke(String name, Json data) {
    if (name == 'business-application-notify' && delayedNotification != null) {
      return delayedNotification!.future;
    }
    return super.invoke(name, data);
  }

  @override
  Future<dynamic> rpc(String name, [Json params = const {}]) async {
    if (name == 'my_pending_business_application') {
      return {
        'business_id': 'p1',
        'name': 'Test studio',
        'kind': 'salon',
        'suburb': 'Auckland',
        'registration_number': 'NZ123',
        'contact_name': 'Test Owner',
        'contact_email': 'owner@example.test',
        'contact_phone': '+64211234567',
      };
    }
    if (name == 'update_pending_business_application') {
      if (saveFails) throw Exception('Application could not be saved');
      if (delayedSave != null) await delayedSave!.future;
      expect(params['p_business'], 'p1');
      resubmissions++;
      status = 'pending';
      return null;
    }
    return super.rpc(name, params);
  }
}

class DelayedBackend extends fixtures.TestBackend {
  bool delayReads = false;
  final reads = <Completer<List<Json>>>[];
  Completer<List<Json>>? nextPage;
  final offsets = <int>[];
  @override
  Future<dynamic> rpc(String name, [Json params = const {}]) async {
    if (name == 'my_visits') {
      final offset = params['p_offset'] as int? ?? 0;
      offsets.add(offset);
      if (offset > 0 && nextPage != null) return nextPage!.future;
      if (delayReads) {
        final result = Completer<List<Json>>();
        reads.add(result);
        return result.future;
      }
    }
    return super.rpc(name, params);
  }
}

class WorkspaceBackend extends redesign.RoleBackend {
  String workspace = 'p1';
  int privateReads = 0, deletions = 0, reviewCalls = 0, refunds = 0;
  final visitActions = <String>[];
  bool reviewListing = false;
  bool failAccountAfterSave = false;
  @override
  Future<dynamic> rpc(String name, [Json params = const {}]) async {
    if (name == 'change_visit') visitActions.add(params['p_action'] as String);
    if (name == 'request_refund') {
      refunds++;
      visits.first['payment_status'] = 'refund_pending';
      return null;
    }
    if (name == 'visit_location')
      return {'address': 'Private home address', 'lat': -36.85, 'lng': 174.76};
    if (name == 'admin_review') {
      reviewCalls++;
      return null;
    }
    if (name == 'admin_overview' && reviewListing)
      return {
        'businesses': [
          {
            ...business,
            'status': 'pending',
            'location': {'address': 'Private application address'},
          },
        ],
        'reports': <Json>[],
      };
    if (name == 'account_context' && applications > 0 && failAccountAfterSave)
      throw Exception('Account refresh unavailable');
    if (name == 'account_context' && owner && status == 'approved')
      return {
        'is_admin': admin,
        'aal2': mfa,
        'business_id': workspace,
        'business_status': status,
      };
    if (name == 'operator_business')
      return {
        ...business,
        'id': workspace,
        'name': workspace == 'p1' ? 'First studio' : 'Second studio',
      };
    if (name == 'my_visits' && params['p_business'] != null) privateReads++;
    return super.rpc(name, params);
  }

  @override
  Future<Json> invoke(String name, Json data) async {
    if (name == 'delete-account') {
      deletions++;
      return {};
    }
    return super.invoke(name, data);
  }
}

class PendingEnrollmentBackend extends redesign.RoleBackend {
  final enrollment = Completer<Json>();
  @override
  Future<Json> enrollFactor() => enrollment.future;
}

class QrEnrollmentBackend extends redesign.RoleBackend {
  @override
  Future<Json> enrollFactor() async => {
    'id': 'new-factor',
    'secret': 'private-test-secret',
    'uri': 'otpauth://totp/spicyself:test?secret=JBSWY3DPEHPK3PXP&issuer=spicyself',
    'qr_code': '', // Rendering must work without Supabase SVG artwork.
  };
}

class PendingNotificationBackend extends redesign.RoleBackend {
  final notification = Completer<Json>();
  @override
  Future<Json> invoke(String name, Json data) =>
      name == 'business-application-notify'
      ? notification.future
      : super.invoke(name, data);
}

Json visit(String id, String status) => {
  'id': id,
  'business_id': 'p1',
  'customer_id': 'customer',
  'customer_name': 'Private customer',
  'service_name': 'Haircut',
  'kind': 'appointment',
  'status': status,
  'starts_at': '2026-10-24T00:00:00Z',
  'minutes': 30,
  'price_cents': 3500,
  'payment_status': 'unpaid',
};

Future<void> tick() => Future<void>.delayed(Duration.zero);

Future<void> selectQueue(WidgetTester tester) async {
  await fixtures.tapVisible(
    tester,
    find.byKey(const ValueKey('service-picker')),
  );
  await tester.tap(find.text('Haircut • 30 min • \$35.00').last);
  await tester.pumpAndSettle();
  await fixtures.tapVisible(tester, find.text('Join live queue'));
}

void main() {
  testWidgets('rejected owner edits and resubmits the existing application', (
    tester,
  ) async {
    final backend = RejectedApplicationBackend()
      ..owner = true
      ..status = 'rejected';
    final store = await redesign.mount(
      tester,
      backend,
      (s) => BusinessScreen(store: s),
    );
    await fixtures.tapVisible(tester, find.text('Edit and reapply'));
    await tester.pumpAndSettle();
    expect(find.text('Test studio'), findsOneWidget);
    await fixtures.tapVisible(
      tester,
      find.text('Save and resubmit for review'),
    );
    await tester.pumpAndSettle();
    expect(backend.resubmissions, 1);
    expect(backend.applications, 0);
    expect(backend.operatorCalls, 0);
    expect(find.text('Application under review'), findsOneWidget);
    await redesign.close(tester, store);
  });

  testWidgets(
    'resubmission confirms and closes while review email is still pending',
    (tester) async {
      final backend = RejectedApplicationBackend()
        ..owner = true
        ..status = 'rejected'
        ..delayedNotification = Completer<Json>();
      final store = await redesign.mount(
        tester,
        backend,
        (s) => BusinessScreen(store: s),
      );
      await fixtures.tapVisible(tester, find.text('Edit and reapply'));
      await tester.pumpAndSettle();
      await fixtures.tapVisible(
        tester,
        find.text('Save and resubmit for review'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Application under review'), findsOneWidget);
      expect(find.text('Application sent for review.'), findsOneWidget);
      expect(find.text('Save and resubmit for review'), findsNothing);
      expect(backend.resubmissions, 1);
      backend.delayedNotification!.completeError(
        Exception('Email unavailable'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Application under review'), findsOneWidget);
      expect(
        store.applicationNotificationMessage,
        contains('Notification delivery needs attention'),
      );
      expect(tester.takeException(), isNull);
      await redesign.close(tester, store);
    },
  );

  testWidgets('resubmission shows progress and prevents duplicate clicks', (
    tester,
  ) async {
    final backend = RejectedApplicationBackend()
      ..owner = true
      ..status = 'rejected'
      ..delayedSave = Completer<void>();
    final store = await redesign.mount(
      tester,
      backend,
      (s) => BusinessScreen(store: s),
    );
    await fixtures.tapVisible(tester, find.text('Edit and reapply'));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(
      FilledButton,
      'Save and resubmit for review',
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    expect(find.text('Submitting application…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Submitting application…'),
          )
          .onPressed,
      isNull,
    );
    backend.delayedSave!.complete();
    await tester.pumpAndSettle();
    expect(backend.resubmissions, 1);
    expect(find.text('Application under review'), findsOneWidget);
    await redesign.close(tester, store);
  });

  testWidgets(
    'failed resubmission stays editable and shows the error beside submit',
    (tester) async {
      final backend = RejectedApplicationBackend()
        ..owner = true
        ..status = 'rejected'
        ..saveFails = true;
      final store = await redesign.mount(
        tester,
        backend,
        (s) => BusinessScreen(store: s),
      );
      await fixtures.tapVisible(tester, find.text('Edit and reapply'));
      await tester.pumpAndSettle();
      await fixtures.tapVisible(
        tester,
        find.text('Save and resubmit for review'),
      );
      expect(find.text('Application could not be saved'), findsOneWidget);
      expect(find.text('Application sent for review.'), findsNothing);
      expect(find.text('Save and resubmit for review'), findsOneWidget);
      backend.saveFails = false;
      await fixtures.tapVisible(
        tester,
        find.text('Save and resubmit for review'),
      );
      expect(find.text('Application under review'), findsOneWidget);
      await redesign.close(tester, store);
    },
  );

  test(
    'cached profile identity is hidden before a new account finishes loading',
    () async {
      final backend = fixtures.TestBackend();
      final store = AppStore(backend);
      await store.refreshAccount();
      expect(store.displayName, 'Customer');
      backend.userId = 'second-account';
      backend.googleNames['second-account'] = 'New account';
      expect(store.hasCurrentAccount, false);
      expect(store.displayName, 'New account');
      await store.refreshAccount();
      expect(store.profile['id'], 'second-account');
      store.dispose();
    },
  );

  setUpAll(tz.initializeTimeZones);

  test('new login cannot inherit cached admin rights', () async {
    final backend = redesign.RoleBackend()..admin = true;
    final store = AppStore(backend);
    await store.refreshAccount();
    expect(store.isAdmin, true);
    backend.userId = 'another-user';
    expect(store.isAdmin, false);
    expect(store.unlocked, false);
    backend.admin = false;
    await store.refreshAccount();
    expect(store.isAdmin, false);
    store.dispose();
  });

  test('older visit refresh cannot overwrite a newer status', () async {
    final backend = DelayedBackend();
    final store = AppStore(backend);
    await store.refreshAccount();
    backend.delayReads = true;
    final older = store.refreshVisits();
    await tick();
    final newer = store.refreshVisits();
    await tick();
    backend.reads[1].complete([visit('v1', 'serving')]);
    await newer;
    backend.reads[0].complete([visit('v1', 'waiting')]);
    await older;
    expect(store.visits.single['status'], 'serving');
    store.dispose();
  });

  test('pagination cannot append a previous account’s visits', () async {
    final backend = DelayedBackend();
    final store = AppStore(backend);
    await store.refreshAccount();
    store.moreVisits = true;
    backend.nextPage = Completer<List<Json>>();
    final more = store.loadMoreVisits();
    await tick();
    backend.userId = 'owner';
    await store.refreshAccount();
    backend.nextPage!.complete([visit('old-private', 'completed')]);
    await more;
    expect(store.visits, isEmpty);
    expect(store.moreVisits, false);
    store.dispose();
  });

  test('overlapping pagination requests advance only one page', () async {
    final backend = DelayedBackend();
    final store = AppStore(backend);
    await store.refreshAccount();
    store.moreVisits = true;
    backend.nextPage = Completer<List<Json>>();
    final first = store.loadMoreVisits();
    final second = store.loadMoreVisits();
    await tick();
    backend.nextPage!.complete(
      List.generate(200, (i) => visit('v$i', 'completed')),
    );
    await Future.wait([first, second]);
    expect(store.visits.length, 200);
    backend.nextPage = null;
    await store.loadMoreVisits();
    expect(backend.offsets.last, 400);
    store.dispose();
  });

  test(
    'old-session refresh errors do not appear after signing in again',
    () async {
      final backend = DelayedBackend();
      final store = AppStore(backend);
      await store.refreshAccount();
      backend.delayReads = true;
      final older = store.refreshVisits();
      await tick();
      backend.userId = null;
      await store.refreshAccount();
      backend.delayReads = false;
      backend.userId = 'customer';
      await store.refreshAccount();
      backend.reads.single.completeError(Exception('Previous session detail'));
      await older;
      expect(store.error, isNull);
      store.dispose();
    },
  );

  test('old-session action failures do not affect the new account', () async {
    final backend = DelayedBackend();
    final store = AppStore(backend);
    await store.refreshAccount();
    final pending = Completer<void>();
    final action = store.run(() => pending.future);
    backend.userId = 'owner';
    await store.refreshAccount();
    pending.completeError(Exception('Previous session detail'));
    expect(await action, false);
    expect(store.error, isNull);
    expect(store.busy, false);
    store.dispose();
  });

  test(
    'late notification outcomes do not overwrite another account’s state',
    () async {
      final backend = PendingNotificationBackend();
      final store = AppStore(backend);
      await store.refreshAccount();
      final pending = sendApplicationNotification(store, 'p1');
      backend.userId = 'owner';
      await store.refreshAccount();
      backend.notification.complete({'email_sent': true});
      await pending;
      expect(store.applicationNotificationMessage, isNull);
      store.dispose();
    },
  );

  testWidgets('new MFA enrolment displays QR and hides manual key by default', (
    tester,
  ) async {
    final backend = QrEnrollmentBackend()
      ..owner = true
      ..status = 'approved'
      ..mfa = false;
    final store = await redesign.mount(
      tester,
      backend,
      (s) => BusinessScreen(store: s),
    );
    await fixtures.tapVisible(tester, find.text('Set up authenticator'));
    expect(find.text('Cannot scan? Show manual setup key'), findsOneWidget);
    expect(find.text('private-test-secret'), findsNothing);
    expect(
      find.text('QR unavailable. Use the manual setup key below.'),
      findsNothing,
    );
    expect(find.textContaining('QR could not be displayed'), findsNothing);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(
      tester.widget<QrImageView>(find.byType(QrImageView)).semanticsLabel,
      'Private authenticator setup QR',
    );
    // The QR must be a compact scannable square, not an expanding grey panel.
    expect(
      find.byType(SizedBox).evaluate().any((element) {
        final widget = element.widget as SizedBox;
        return widget.width == 252 && widget.height == 252;
      }),
      isTrue,
    );
    await fixtures.tapVisible(
      tester,
      find.text('Cannot scan? Show manual setup key'),
    );
    expect(find.text('private-test-secret'), findsOneWidget);
    await redesign.close(tester, store);
  });

  testWidgets(
    'late MFA enrolment does not show the previous account’s secret',
    (tester) async {
      final backend = PendingEnrollmentBackend()
        ..owner = true
        ..status = 'approved'
        ..mfa = false;
      final store = await redesign.mount(
        tester,
        backend,
        (s) => BusinessScreen(store: s),
      );
      await fixtures.tapVisible(tester, find.text('Set up authenticator'));
      backend.userId = 'owner';
      await store.refreshAccount();
      await tester.pumpAndSettle();
      backend.enrollment.complete({
        'id': 'old-factor',
        'secret': 'old-account-test-secret',
      });
      await tester.pumpAndSettle();
      expect(find.text('old-account-test-secret'), findsNothing);
      expect(find.text('Set up authenticator'), findsOneWidget);
      await redesign.close(tester, store);
    },
  );

  testWidgets('an open profile resets unsaved details when accounts change', (
    tester,
  ) async {
    final backend = redesign.RoleBackend();
    backend.profiles['owner']!['display_name'] = 'New account';
    final store = await redesign.mount(
      tester,
      backend,
      (s) => AccountScreen(store: s),
    );
    await tester.enterText(
      find.byKey(const ValueKey('Your name')),
      'Previous private draft',
    );
    backend.userId = 'owner';
    await store.refreshAccount();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('Your name')))
          .controller!
          .text,
      'New account',
    );
    expect(find.text('Previous private draft'), findsNothing);
    await redesign.close(tester, store);
  });

  testWidgets('unfinished business application does not cross accounts', (
    tester,
  ) async {
    final backend = redesign.RoleBackend();
    final store = await redesign.mount(
      tester,
      backend,
      (s) => BusinessScreen(store: s),
    );
    final field = find.byKey(
      const ValueKey('Registered business / trading name'),
    );
    await tester.enterText(field, 'Previous private draft');
    backend.userId = 'owner';
    await store.refreshAccount();
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(field).controller!.text, isEmpty);
    await redesign.close(tester, store);
  });

  testWidgets(
    'an open owner workspace reloads for a different account and business',
    (tester) async {
      final backend = WorkspaceBackend()
        ..owner = true
        ..status = 'approved';
      final store = await redesign.mount(
        tester,
        backend,
        (s) => BusinessScreen(store: s),
      );
      expect(find.text('First studio'), findsOneWidget);
      backend.userId = 'owner';
      backend.workspace = 'p2';
      await store.refreshAccount();
      await tester.pumpAndSettle();
      expect(find.text('Second studio'), findsOneWidget);
      expect(find.text('First studio'), findsNothing);
      await redesign.close(tester, store);
    },
  );

  testWidgets(
    'open admin visits hide private data immediately when privileges are lost',
    (tester) async {
      final backend = WorkspaceBackend()..admin = true;
      backend.visits.add(visit('v1', 'completed'));
      final store = await redesign.mount(
        tester,
        backend,
        (s) => AdminBusinessVisits(store: s, business: 'p1'),
      );
      expect(find.text('Private customer'), findsOneWidget);
      final reads = backend.privateReads;
      backend.admin = false;
      await store.refreshAccount();
      await tester.pump();
      expect(find.text('Private customer'), findsNothing);
      expect(find.text('Restricted access'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(backend.privateReads, reads);
      await redesign.close(tester, store);
    },
  );

  testWidgets('direct admin visits never load without role and MFA', (
    tester,
  ) async {
    for (final flags in [(false, true), (true, false)]) {
      final backend = WorkspaceBackend()
        ..admin = flags.$1
        ..mfa = flags.$2;
      final store = await redesign.mount(
        tester,
        backend,
        (s) => AdminBusinessVisits(store: s, business: 'p1'),
      );
      expect(backend.privateReads, 0);
      expect(find.text('Restricted access'), findsOneWidget);
      await redesign.close(tester, store);
    }
  });

  testWidgets(
    'rapid booking taps create one confirmation and reset on account switch',
    (tester) async {
      final backend = redesign.RoleBackend();
      final store = await redesign.mount(
        tester,
        backend,
        (s) => BookingScreen(store: s, businessId: 'p1'),
      );
      await selectQueue(tester);
      final confirm = tester
          .widget<FilledButton>(find.byKey(const ValueKey('confirm-visit')))
          .onPressed!;
      confirm();
      confirm();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Join queue').last);
      await tester.pumpAndSettle();
      expect(
        backend.visits.length,
        1,
        reason:
            'error=${store.error}; busy=${store.busy}; session=${store.sessionRevision}',
      );
      expect(find.text('You’re booked in.'), findsOneWidget);
      backend.userId = 'owner';
      await store.refreshAccount();
      await tester.pumpAndSettle();
      expect(find.text('You’re booked in.'), findsNothing);
      expect(find.byKey(const ValueKey('confirm-visit')), findsOneWidget);
      await redesign.close(tester, store);
    },
  );

  testWidgets('booking confirmation cannot be reused by another account', (
    tester,
  ) async {
    final backend = redesign.RoleBackend();
    final store = await redesign.mount(
      tester,
      backend,
      (s) => BookingScreen(store: s, businessId: 'p1'),
    );
    await selectQueue(tester);
    await fixtures.tapVisible(
      tester,
      find.byKey(const ValueKey('confirm-visit')),
    );
    backend.userId = 'owner';
    await store.refreshAccount();
    await tester.pumpAndSettle();
    expect(find.text('Session changed'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Join queue'),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(backend.visits, isEmpty);
    await redesign.close(tester, store);
  });

  testWidgets('account deletion confirmation expires when the user changes', (
    tester,
  ) async {
    final backend = WorkspaceBackend();
    final store = await redesign.mount(
      tester,
      backend,
      (s) => AccountScreen(store: s),
    );
    await fixtures.tapVisible(tester, find.text('Delete account'));
    backend.userId = 'owner';
    await store.refreshAccount();
    await tester.pumpAndSettle();
    expect(find.text('Session changed'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete account'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(backend.deletions, 0);
    await redesign.close(tester, store);
  });

  testWidgets('private address dialog hides its contents on account switch', (
    tester,
  ) async {
    final backend = WorkspaceBackend();
    final store = await redesign.mount(
      tester,
      backend,
      (s) => VisitCard(store: s, visit: visit('v1', 'waiting')),
    );
    await fixtures.tapVisible(tester, find.text('Address & directions'));
    expect(find.text('Private home address'), findsOneWidget);
    backend.userId = 'owner';
    await store.refreshAccount();
    await tester.pumpAndSettle();
    expect(find.text('Private home address'), findsNothing);
    expect(find.text('Session changed'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await redesign.close(tester, store);
  });

  testWidgets('admin review dialog expires when MFA is lost', (tester) async {
    final backend = WorkspaceBackend()
      ..admin = true
      ..reviewListing = true;
    final store = await redesign.mount(
      tester,
      backend,
      (s) => AdminScreen(store: s),
    );
    await fixtures.tapVisible(tester, find.text('Approve'));
    await tester.enterText(
      find.byKey(const ValueKey('Review note')),
      'Verified application details',
    );
    backend.mfa = false;
    await store.refreshAccount();
    await tester.pumpAndSettle();
    expect(find.text('Session changed'), findsOneWidget);
    expect(find.text('Save decision'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(backend.reviewCalls, 0);
    expect(find.text('Private application address'), findsNothing);
    await redesign.close(tester, store);
  });

  testWidgets(
    'cancellation requires confirmation and refreshes the booking status',
    (tester) async {
      final backend = WorkspaceBackend();
      backend.visits.add(visit('v1', 'booked'));
      final store = await redesign.mount(
        tester,
        backend,
        (s) => ListenableBuilder(
          listenable: s,
          builder: (context, _) => VisitCard(store: s, visit: s.visits.single),
        ),
      );
      await fixtures.tapVisible(tester, find.text('Cancel visit'));
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(backend.visitActions, isEmpty);
      await fixtures.tapVisible(tester, find.text('Cancel visit'));
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel visit'));
      await tester.pumpAndSettle();
      expect(backend.visitActions, ['cancel']);
      expect(find.text('cancelled'), findsOneWidget);
      expect(find.text('Cancel visit'), findsNothing);
      await redesign.close(tester, store);
    },
  );

  testWidgets(
    'refund requests stay behind confirmation and the protected RPC',
    (tester) async {
      final backend = WorkspaceBackend()
        ..owner = true
        ..status = 'approved';
      backend.visits.add({
        ...visit('v1', 'completed'),
        'payment_status': 'paid',
      });
      final store = await redesign.mount(
        tester,
        backend,
        (s) => ListenableBuilder(
          listenable: s,
          builder: (context, _) =>
              VisitCard(store: s, visit: s.visits.single, operator: true),
        ),
      );
      await fixtures.tapVisible(tester, find.text('Refund'));
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(backend.refunds, 0);
      await fixtures.tapVisible(tester, find.text('Refund'));
      backend.mfa = false;
      await store.refreshAccount();
      await tester.pumpAndSettle();
      expect(find.text('Session changed'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(backend.refunds, 0);
      backend.mfa = true;
      await store.refreshAccount();
      await tester.pumpAndSettle();
      await fixtures.tapVisible(tester, find.text('Refund'));
      await tester.tap(find.text('Request refund'));
      await tester.pumpAndSettle();
      expect(backend.refunds, 1);
      expect(find.textContaining('refund pending'), findsOneWidget);
      expect(find.text('Refund'), findsNothing);
      await redesign.close(tester, store);
    },
  );

  testWidgets(
    'saved application survives failed account refresh without resubmission',
    (tester) async {
      final backend = WorkspaceBackend()
        ..failAccountAfterSave = true
        ..notificationFails = true;
      final store = await redesign.mount(
        tester,
        backend,
        (s) => BusinessScreen(store: s),
      );
      Future<void> fill(String label, String value) =>
          tester.enterText(find.byKey(ValueKey(label)), value);
      await fill('Registered business / trading name', 'Studio');
      await fill('NZBN or business registration number', 'Not applicable');
      await fixtures.tapVisible(tester, find.text('Continue'));
      await fill('Contact person full name', 'Sam Owner');
      await fill('Business contact email', 'owner@example.com');
      await fill('Business contact phone', '021 123 4567');
      await fixtures.tapVisible(tester, find.text('Continue'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business street address'),
        '12 Test Street',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await fixtures.tapVisible(
        tester,
        find.text('12 Test Street, Auckland, New Zealand'),
      );
      await fixtures.tapVisible(tester, find.text('Continue'));
      await fixtures.tapVisible(tester, find.byType(CheckboxListTile).first);
      await fixtures.tapVisible(tester, find.byType(CheckboxListTile).last);
      await fixtures.tapVisible(
        tester,
        find.text('Submit business application'),
      );
      expect(find.text('Application saved'), findsOneWidget);
      expect(find.text('Application sent for review.'), findsOneWidget);
      expect(
        store.applicationNotificationMessage,
        contains('Notification delivery needs attention'),
      );
      expect(find.text('Submit business application'), findsNothing);
      expect(backend.applications, 1);
      backend.failAccountAfterSave = false;
      await fixtures.tapVisible(tester, find.text('Check application status'));
      expect(find.text('Application under review'), findsOneWidget);
      expect(backend.applications, 1);
      await redesign.close(tester, store);
    },
  );
}
