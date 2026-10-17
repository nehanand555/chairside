import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chairside/state/demo_store.dart';
import 'package:chairside/ui/app.dart';

void main() {
  testWidgets('customer joins a queue, barber serves them, customer sees completion', (tester) async {
    final store = DemoStore(clock: () => DateTime(2026, 10, 19, 10), seedQueue: false);
    addTearDown(store.dispose);
    await tester.pumpWidget(ChairsideApp(store: store));
    await tester.scrollUntilVisible(find.byKey(const Key('view-p1')), 220, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('view-p1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('queue-choice')));
    await tester.tap(find.byKey(const Key('queue-choice')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('confirm-visit')));
    await tester.tap(find.byKey(const Key('confirm-visit')));
    await tester.pumpAndSettle();
    expect(find.text('You are #1 in the queue'), findsOneWidget);

    await tester.tap(find.byKey(const Key('role-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Barber').last);
    await tester.pumpAndSettle();
    final id = store.mine.single.id;
    await tester.scrollUntilVisible(find.byKey(Key('start-$id')), 220, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(Key('start-$id')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(Key('finish-$id')));
    await tester.tap(find.byKey(Key('finish-$id')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('role-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customer').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('My visits').last);
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discovery renders on a small phone and a desktop', (tester) async {
    final store = DemoStore(clock: () => DateTime(2026, 10, 19, 10));
    addTearDown(store.dispose);
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    tester.view.devicePixelRatio = 1;
    for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(ChairsideApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Find your chair'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
