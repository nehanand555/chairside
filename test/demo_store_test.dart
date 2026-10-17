import 'package:flutter_test/flutter_test.dart';
import 'package:chairside/models/models.dart';
import 'package:chairside/state/demo_store.dart';

void main() {
  late DateTime clock;
  late DemoStore store;

  setUp(() {
    clock = DateTime(2026, 10, 19, 10);
    store = DemoStore(clock: () => clock, seedQueue: false);
  });

  tearDown(() => store.dispose());

  test('an overlapping appointment is unavailable, but adjacent time is free', () {
    final service = store.provider('p1').services.first;
    final start = clock.add(const Duration(hours: 1));
    store.book('p1', service, start);
    expect(store.slotAvailable('p1', service, start.add(const Duration(minutes: 15))), isFalse);
    expect(store.slotAvailable('p1', service, start.add(const Duration(minutes: 30))), isTrue);
    expect(store.slotAvailable('p2', store.provider('p2').services.first, start), isTrue);
  });

  test('a customer cannot create a second active visit', () {
    final service = store.provider('p1').services.first;
    store.join('p1', service);
    expect(() => store.book('p1', service, clock.add(const Duration(hours: 1))), throwsA(isA<DemoError>()));
    expect(store.mine.length, 1);
  });

  test('cancelling releases a slot and lets the customer book again', () {
    final service = store.provider('p1').services.first;
    final start = clock.add(const Duration(hours: 1));
    final first = store.book('p1', service, start);
    store.cancel(first);
    expect(store.slotAvailable('p1', service, start), isTrue);
    expect(store.book('p1', service, start).status, VisitStatus.waiting);
  });

  test('queue stays FIFO and only one customer can be served at once', () {
    final service = store.provider('p1').services.first;
    final first = store.join('p1', service, name: 'Walk-in', isDemoCustomer: false);
    clock = clock.add(const Duration(seconds: 1));
    final second = store.join('p1', service);
    expect(store.position(second), 2);
    expect(() => store.start(second), throwsA(isA<DemoError>()));
    store.start(first);
    expect(store.position(second), 1);
    expect(store.waitMinutes(second), 30);
    expect(() => store.start(second), throwsA(isA<DemoError>()));
    store.finish(first);
    expect(store.waitMinutes(second), 0);
    store.start(second);
    store.finish(second);
    expect(store.queue('p1'), isEmpty);
    expect(second.status, VisitStatus.completed);
  });

  test('queue estimates reserve time for appointments', () {
    final service = store.provider('p1').services.first;
    store.book('p1', service, clock.add(const Duration(minutes: 15)));
    final walkIn = store.join('p1', service, name: 'Walk-in', isDemoCustomer: false);
    expect(store.waitMinutes(walkIn), 45);
    expect(() => store.start(walkIn), throwsA(isA<DemoError>()));
  });

  test('paused queues reject arrivals but keep existing visits', () {
    final p = store.provider('p1');
    store.join(p.id, p.services.first, isDemoCustomer: false);
    store.toggleQueue(p);
    expect(() => store.join(p.id, p.services.first), throwsA(isA<DemoError>()));
    expect(store.queue(p.id).length, 1);
    expect(store.slotAvailable(p.id, p.services.first, clock.add(const Duration(hours: 1))), isTrue);
  });

  test('home studios use appointments only; pending providers cannot book', () {
    final home = store.provider('p2');
    expect(() => store.join(home.id, home.services.first), throwsA(isA<DemoError>()));
    final pending = store.provider('p4');
    expect(() => store.book(pending.id, pending.services.first, clock.add(const Duration(hours: 1))), throwsA(isA<DemoError>()));
    store.review(pending, true);
    expect(store.listed.contains(pending), isTrue);
    expect(store.book(pending.id, pending.services.first, clock.add(const Duration(hours: 1))).active, isTrue);
  });

  test('past times, closing-time overruns and early starts are rejected', () {
    final service = store.provider('p1').services.first;
    expect(store.slotAvailable('p1', service, clock.subtract(const Duration(minutes: 15))), isFalse);
    expect(store.slotAvailable('p1', service, DateTime(2026, 10, 19, 17, 45)), isFalse);
    final visit = store.book('p1', service, clock.add(const Duration(minutes: 30)));
    expect(() => store.start(visit), throwsA(isA<DemoError>()));
    clock = clock.add(const Duration(minutes: 30));
    store.start(visit);
    expect(visit.status, VisitStatus.inService);
  });

  test('a queue cannot take a visit that finishes after closing', () {
    clock = DateTime(2026, 10, 19, 17, 45);
    final p = store.provider('p1');
    expect(() => store.join(p.id, p.services.first), throwsA(isA<DemoError>()));
    expect(store.visits, isEmpty);
  });

  test('finishing before starting and cancelling during service are rejected', () {
    final p = store.provider('p1');
    final visit = store.join(p.id, p.services.first);
    expect(() => store.finish(visit), throwsA(isA<DemoError>()));
    store.start(visit);
    expect(() => store.cancel(visit), throwsA(isA<DemoError>()));
  });

  test('demo clock updates queue waits without an external service', () {
    final p = store.provider('p1');
    final current = store.join(p.id, p.services.first, isDemoCustomer: false);
    store.start(current);
    final next = store.join(p.id, p.services.first);
    store.advanceTime();
    expect(store.waitMinutes(next), 15);
  });

  test('arrivals in the same second retain their insertion order', () {
    final p = store.provider('p1');
    final entries = List.generate(4, (i) => store.join(
      p.id, p.services.first, name: 'Walk-in $i', isDemoCustomer: false,
    ));
    expect(store.queue(p.id).map((v) => v.id), entries.map((v) => v.id));
  });

  test('a late-started appointment blocks the actual service interval', () {
    final p = store.provider('p1');
    final visit = store.book(p.id, p.services.first, clock.add(const Duration(minutes: 15)));
    clock = clock.add(const Duration(minutes: 30));
    store.start(visit);
    expect(store.slotAvailable(p.id, p.services.first, clock.add(const Duration(minutes: 15))), isFalse);
  });
}
