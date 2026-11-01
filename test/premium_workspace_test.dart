import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:chairside/data/backend.dart';
import 'package:chairside/screens/admin.dart';
import 'package:chairside/screens/booking.dart';
import 'package:chairside/screens/business.dart';
import 'package:chairside/screens/common.dart';
import 'package:chairside/screens/clients.dart';
import 'package:chairside/screens/scheduling.dart';
import 'package:chairside/screens/workspace.dart';

import 'product_test.dart' as fixtures;
import 'redesign_test.dart' as roles;

class PremiumBackend extends roles.RoleBackend {
  final requests = <String, Json>{};
  String note = 'Prefers a quiet appointment';
  int manualBookings = 0, reschedules = 0;
  Completer<void>? savePending;
  final slots = <Json>[
    {
      'resource_id': 'r1',
      'resource_name': 'Professional A',
      'starts_at': '2026-11-02T21:00:00Z',
    },
    {
      'resource_id': 'r2',
      'resource_name': 'Professional B',
      'starts_at': '2026-11-02T21:00:00Z',
    },
  ];
  PremiumBackend() {
    business['resources'] = [
      {'id': 'r1', 'name': 'Professional A', 'active': true},
      {'id': 'r2', 'name': 'Professional B', 'active': true},
    ];
  }
  @override
  Future<dynamic> rpc(String name, [Json params = const {}]) async {
    requests[name] = Json.from(params);
    if (name == 'available_slots') return slots;
    if (name == 'business_clients')
      return {
        'items': [
          {
            'customer_id': 'client-1',
            'name': 'Alex',
            'visit_count': 2,
            'last_visit': '2026-11-02T21:00:00Z',
            'note': note,
          },
        ],
        'has_more': false,
      };
    if (name == 'business_client_history')
      return [
        {
          'service_name': 'Haircut',
          'starts_at': '2026-11-02T21:00:00Z',
          'status': 'completed',
          'price_cents': 3500,
        },
      ];
    if (name == 'save_client_note') {
      note = params['p_note'] as String;
      return null;
    }
    if (name == 'operator_book_appointment') {
      if (savePending != null) await savePending!.future;
      manualBookings++;
      return 'new-visit';
    }
    if (name == 'reschedule_visit') {
      reschedules++;
      return null;
    }
    return super.rpc(name, params);
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  testWidgets(
    'workspace changes never show stale results while the new query loads',
    (tester) async {
      final first = Future.value('Previous workspace');
      final next = Completer<String>();
      Widget screen(Future<String> value) => MaterialApp(
        home: Scaffold(
          body: AsyncPanel<String>(future: value, builder: (s) => Text(s)),
        ),
      );
      await tester.pumpWidget(screen(first));
      await tester.pumpAndSettle();
      expect(find.text('Previous workspace'), findsOneWidget);
      await tester.pumpWidget(screen(next.future));
      await tester.pump();
      expect(find.text('Previous workspace'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      next.complete('New workspace');
      await tester.pumpAndSettle();
      expect(find.text('New workspace'), findsOneWidget);
    },
  );
  test('calendar dates use NZ DST boundaries, rather than UTC dates', () {
    expect(nzDateOf('2026-09-26T12:30:00Z'), DateTime(2026, 9, 27));
    expect(nzDateOf('2026-09-27T10:30:00Z'), DateTime(2026, 9, 27));
    expect(nzDateOf('2026-09-27T11:30:00Z'), DateTime(2026, 9, 28));
  });
  testWidgets(
    'merchant navigation supports phone, tablet and desktop with large text',
    (tester) async {
      for (final width in [360.0, 768.0, 1440.0]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        final backend = PremiumBackend()
          ..owner = true
          ..status = 'approved';
        final store = await roles.mount(
          tester,
          backend,
          (s) => BusinessScreen(store: s),
        );
        expect(find.text('Booked value today'), findsOneWidget);
        expect(find.textContaining('not revenue'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Overview fits $width');
        if (width < 1000) {
          await fixtures.selectWorkspace(tester, 'Calendar');
        } else {
          await fixtures.tapVisible(tester, find.text('Calendar'));
        }
        expect(find.text('Your appointment calendar'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Calendar fits $width');
        await roles.close(tester, store);
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets('calendar switches from day to a bounded server week query', (
    tester,
  ) async {
    final backend = PremiumBackend()..owner = true;
    final store = await roles.mount(
      tester,
      backend,
      (s) => BusinessSchedule(store: s, business: backend.business),
    );
    expect(backend.requests['business_schedule']?['p_days'], 1);
    await fixtures.tapVisible(tester, find.text('Week'));
    expect(backend.requests['business_schedule']?['p_days'], 7);
    final monday = DateTime.parse(
      backend.requests['business_schedule']!['p_day'],
    );
    expect(monday.weekday, DateTime.monday);
    expect(find.text('No appointments loaded'), findsNWidgets(7));
    await roles.close(tester, store);
  });
  testWidgets(
    'client notes are saved through the protected API and history is paged',
    (tester) async {
      final backend = PremiumBackend()..owner = true;
      final store = await roles.mount(
        tester,
        backend,
        (s) => BusinessClients(store: s, business: backend.business),
      );
      expect(find.text('Alex'), findsOneWidget);
      await fixtures.tapVisible(tester, find.text('Visit history'));
      expect(
        backend.requests['business_client_history']?['p_customer'],
        'client-1',
      );
      await fixtures.tapVisible(tester, find.text('Private notes'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Private business note'),
        'Prefers a short consultation',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save note'));
      await tester.pumpAndSettle();
      expect(backend.requests['save_client_note']?['p_business'], 'p1');
      expect(backend.note, 'Prefers a short consultation');
      expect(find.text('Prefers a short consultation'), findsOneWidget);
      await roles.close(tester, store);
    },
  );
  testWidgets(
    'booking professional preference filters only real server slots',
    (tester) async {
      final backend = PremiumBackend();
      final store = await roles.mount(
        tester,
        backend,
        (s) => BookingScreen(store: s, businessId: 'p1'),
      );
      await fixtures.tapVisible(
        tester,
        find.byKey(const ValueKey('service-picker')),
      );
      await tester.tap(find.text('Haircut • 30 min • \$35.00').last);
      await tester.pumpAndSettle();
      expect(find.text('Any available'), findsOneWidget);
      await fixtures.tapVisible(
        tester,
        find.widgetWithText(
          DropdownButtonFormField<String>,
          'Preferred professional',
        ),
      );
      await tester.tap(find.text('Professional B').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('r1-2026-11-02T21:00:00Z')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('r2-2026-11-02T21:00:00Z')),
        findsOneWidget,
      );
      expect(find.text('3 · Review & confirm'), findsOneWidget);
      await roles.close(tester, store);
    },
  );
  testWidgets(
    'manual bookings use server slots and do not confirm before save completes',
    (tester) async {
      final backend = PremiumBackend()
        ..owner = true
        ..savePending = Completer<void>();
      final store = await roles.mount(
        tester,
        backend,
        (s) => AppointmentEditor(store: s, business: backend.business),
      );
      await tester.enterText(find.byKey(const ValueKey('Client name')), 'Alex');
      await fixtures.tapVisible(
        tester,
        find.widgetWithText(DropdownButtonFormField<String>, 'Service'),
      );
      await tester.tap(find.text('Haircut · \$35.00').last);
      await tester.pumpAndSettle();
      await fixtures.tapVisible(tester, find.byType(ChoiceChip).first);
      await fixtures.tapVisible(tester, find.text('Book appointment'));
      await tester.tap(
        find.widgetWithText(FilledButton, 'Book appointment').last,
      );
      await tester.pump();
      expect(find.text('Appointment saved'), findsNothing);
      backend.savePending!.complete();
      await tester.pumpAndSettle();
      expect(backend.manualBookings, 1);
      expect(find.text('Appointment saved'), findsOneWidget);
      expect(backend.requests['operator_book_appointment']?['p_name'], 'Alex');
      await roles.close(tester, store);
    },
  );
  testWidgets(
    'admin search uses server filters and keeps memberships separate',
    (tester) async {
      final backend = PremiumBackend()..admin = true;
      final store = await roles.mount(
        tester,
        backend,
        (s) => AdminScreen(store: s),
      );
      await fixtures.selectWorkspace(tester, 'Businesses');
      await tester.enterText(
        find.widgetWithText(TextField, 'Search businesses'),
        'Harbour',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(backend.requests['admin_business_page']?['p_search'], 'Harbour');
      expect(backend.requests['admin_business_page']?['p_status'], 'all');
      await fixtures.selectWorkspace(tester, 'Memberships');
      expect(find.text('Business memberships'), findsOneWidget);
      expect(
        find.text(
          'No subscription records yet. No membership revenue is assumed.',
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await roles.close(tester, store);
    },
  );
  testWidgets('record tables adapt to labelled cards on small screens', (
    tester,
  ) async {
    for (final width in [360.0, 1200.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        MaterialApp(
          theme: spicyTheme(),
          home: Scaffold(
            body: WorkspaceTable(
              columns: const ['Business', 'Status'],
              rows: [
                [const Text('Sample studio'), const Text('active')],
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sample studio'), findsOneWidget);
      expect(
        find.byType(DataTable),
        width < 700 ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });
}
