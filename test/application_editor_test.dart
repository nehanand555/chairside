import 'dart:async';

import 'package:flutter/material.dart';
import 'package:chairside/data/store.dart';
import 'package:chairside/data/backend.dart';
import 'package:chairside/screens/business.dart';
import 'package:flutter_test/flutter_test.dart';

import 'redesign_test.dart' as fixtures;

class EditorBackend extends fixtures.RoleBackend {
  Completer<Json>? pending;
  int saves = 0;
  @override
  Future<dynamic> rpc(String name, [Json params = const {}]) async {
    if (name == 'my_pending_business_application') {
      return pending?.future ??
          {
            'business_id': 'p1',
            'name': 'Test studio',
            'kind': 'barber',
            'suburb': 'Auckland',
            'registration_number': 'Not applicable',
            'contact_name': 'Test owner',
            'contact_email': 'owner@example.com',
            'contact_phone': '+6491234567',
          };
    }
    if (name == 'update_pending_business_application') {
      saves++;
      return null;
    }
    return super.rpc(name, params);
  }
}

void main() {
  testWidgets('pending editor saves the existing application and notifies', (
    tester,
  ) async {
    final backend = EditorBackend()..owner = true;
    final store = await fixtures.mount(
      tester,
      backend,
      (store) => PendingApplicationEditor(store: store),
    );
    expect(find.text('Test studio'), findsOneWidget);
    final save = find.text('Save and resubmit for review');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(backend.saves, 1);
    expect(backend.applications, 0);
    expect(backend.notifications, 1);
    await fixtures.close(tester, store);
  });

  testWidgets(
    'pending editor discards late private data after session changes',
    (tester) async {
      final backend = EditorBackend()..owner = true;
      backend.pending = Completer<Json>();
      final store = AppStore(backend);
      await store.refreshAccount();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PendingApplicationEditor(store: store)),
        ),
      );
      await tester.pump();
      await backend.signOut();
      await tester.pump();
      backend.pending!.complete({
        'business_id': 'p1',
        'name': 'Private previous owner',
      });
      await tester.pumpAndSettle();
      expect(find.text('Private previous owner'), findsNothing);
      expect(find.textContaining('Session changed.'), findsOneWidget);
      expect(backend.saves, 0);
      await fixtures.close(tester, store);
    },
  );
}
