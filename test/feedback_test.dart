import 'package:chairside/data/backend.dart';
import 'package:chairside/data/store.dart';
import 'package:chairside/screens/common.dart';
import 'package:chairside/screens/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'product_test.dart' as fixtures;
import 'redesign_test.dart' as roles;

import 'package:timezone/data/latest.dart' as tz;

import 'package:chairside/screens/admin.dart';

class FeedbackBackend extends fixtures.TestBackend {
  int sends = 0;
  bool fails = false;
  String? saved;
  @override
  Future<dynamic> rpc(String name, [Json params = const {}]) async {
    if (name == 'submit_feedback') {
      if (fails) throw Exception('Unavailable');
      sends++;
      saved = params['p_message'] as String;
      return 'feedback-id';
    }
    return super.rpc(name, params);
  }
}

class FeedbackAdminBackend extends roles.RoleBackend {
  bool resolved = false;
  @override
  Future<dynamic> rpc(String name, [Json params = const {}]) async {
    if (name == 'admin_feedback')
      return resolved
          ? []
          : [
              {
                'id': 'feedback-1',
                'message': 'Please add more search filters.',
                'created_at': '2026-10-30T00:00:00Z',
              },
            ];
    if (name == 'resolve_feedback') {
      resolved = true;
      return null;
    }
    return super.rpc(name, params);
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  testWidgets('authorised admin can read and resolve submitted feedback', (
    tester,
  ) async {
    final backend = FeedbackAdminBackend()..admin = true;
    final store = await roles.mount(
      tester,
      backend,
      (s) => AdminScreen(store: s),
    );
    await fixtures.tapVisible(tester, find.text('User feedback'));
    expect(find.text('Please add more search filters.'), findsOneWidget);
    await fixtures.tapVisible(tester, find.text('Mark as read'));
    expect(backend.resolved, isTrue);
    expect(find.text('No new feedback. You’re all caught up.'), findsOneWidget);
    await roles.close(tester, store);
  });

  testWidgets('feedback validates, saves and only then confirms delivery', (
    tester,
  ) async {
    final backend = FeedbackBackend();
    final store = AppStore(backend);
    await store.refreshAccount();
    await tester.pumpWidget(
      MaterialApp(
        theme: spicyTheme(),
        home: Scaffold(body: FeedbackScreen(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    await fixtures.tapVisible(tester, find.text('Send feedback'));
    expect(backend.sends, 0);
    await tester.enterText(
      find.byType(TextFormField),
      'Please add more search filters.',
    );
    backend.fails = true;
    await fixtures.tapVisible(tester, find.text('Send feedback'));
    expect(find.textContaining('couldn’t be sent'), findsOneWidget);
    expect(find.text('Thank you for helping us improve!'), findsNothing);
    backend.fails = false;
    await fixtures.tapVisible(tester, find.text('Send feedback'));
    expect(backend.sends, 1);
    expect(backend.saved, 'Please add more search filters.');
    expect(find.text('Thank you for helping us improve!'), findsOneWidget);
    backend.userId = 'another-user';
    await store.refreshAccount();
    await tester.pumpAndSettle();
    expect(find.text('Thank you for helping us improve!'), findsNothing);
    expect(find.text('Please add more search filters.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
  testWidgets('guest feedback asks for sign in without sending', (
    tester,
  ) async {
    final backend = FeedbackBackend()..userId = null;
    final store = AppStore(backend);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FeedbackScreen(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Send feedback'), findsNothing);
    expect(backend.sends, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
