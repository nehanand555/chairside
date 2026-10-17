import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Local prototype state, NOT an authentication or production booking service.
/// One provider = one chair in this first milestone. Every reload resets state.
class DemoStore extends ChangeNotifier {
  DemoStore({DateTime Function()? clock, bool seedQueue = true})
      : _clock = clock ?? _demoMorning {
    if (seedQueue && isOpen(now)) {
      visits.add(Visit(
        id: 'sample-visit',
        providerId: 'p1',
        customerName: 'Alex (sample)',
        service: providers.first.services.first,
        createdAt: now,
        isDemoCustomer: false,
      ));
    }
  }

  final DateTime Function() _clock;
  Duration _offset = Duration.zero;
  DateTime get now => _clock().add(_offset);
  static DateTime _demoMorning() {
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day, 10);
  }
  void advanceTime() {
    _offset += const Duration(minutes: 15);
    notifyListeners();
  }
  int _sequence = 0;
  final List<Visit> visits = [];

  final List<Provider> providers = [
    Provider(
      id: 'p1', name: 'The Local Chair', suburb: 'Petone', homeBased: false,
      description: 'A relaxed neighbourhood spot for sharp cuts and fresh starts.',
      services: const [
        HairService('cut', 'Classic haircut', 30, 40),
        HairService('fade', 'Skin fade', 45, 55),
        HairService('beard', 'Beard tidy', 15, 25),
      ],
    ),
    Provider(
      id: 'p2', name: 'Studio Fern', suburb: 'Lower Hutt', homeBased: true,
      description: 'A quiet home studio with appointments and personal attention.',
      services: const [
        HairService('cut', 'Cut & style', 45, 60),
        HairService('trim', 'Dry trim', 30, 35),
      ],
    ),
    Provider(
      id: 'p3', name: 'Sunday Studio', suburb: 'Te Aro', homeBased: false,
      description: 'Easy-going grooming in the city. Come as you are.',
      services: const [
        HairService('cut', 'Classic haircut', 30, 45),
        HairService('combo', 'Cut & beard', 60, 75),
      ],
    ),
    Provider(
      id: 'p4', name: 'Harbour Home Hair', suburb: 'Eastbourne', homeBased: true,
      description: 'Sample application awaiting an admin decision.',
      application: ApplicationStatus.pending,
      services: const [HairService('cut', 'Haircut', 30, 35)],
    ),
  ];

  Provider provider(String id) => providers.firstWhere((p) => p.id == id);
  List<Provider> get listed => providers
      .where((p) => p.application == ApplicationStatus.approved).toList();
  List<Visit> get mine => visits.where((v) => v.isDemoCustomer).toList().reversed.toList();
  List<Visit> forProvider(String id) => visits.where((v) => v.providerId == id).toList();
  List<Visit> activeFor(String id) => forProvider(id).where((v) => v.active).toList();

  bool isOpen(DateTime time) => time.hour >= 9 && time.hour < 18;
  bool overlaps(DateTime a, int minutesA, DateTime b, int minutesB) =>
      a.isBefore(b.add(Duration(minutes: minutesB))) &&
      b.isBefore(a.add(Duration(minutes: minutesA)));

  void _checkProvider(Provider p, HairService service) {
    if (p.application != ApplicationStatus.approved) {
      throw const DemoError('This provider is not available for bookings.');
    }
    if (!p.services.contains(service)) {
      throw const DemoError('Choose a service offered by this provider.');
    }
  }

  bool slotAvailable(String providerId, HairService service, DateTime start) {
    final p = provider(providerId);
    if (p.application != ApplicationStatus.approved || !p.services.contains(service)) return false;
    if (!start.isAfter(now) || !isOpen(start)) return false;
    final close = DateTime(start.year, start.month, start.day, 18);
    if (start.add(Duration(minutes: service.minutes)).isAfter(close)) return false;
    for (final v in activeFor(providerId)) {
      final occupiedAt = v.status == VisitStatus.inService ? v.startedAt : v.appointmentAt;
      if (occupiedAt != null && overlaps(start, service.minutes, occupiedAt, v.service.minutes)) return false;
    }
    return true;
  }

  List<DateTime> slots(String providerId, HairService service, DateTime day) {
    final result = <DateTime>[];
    for (var minutes = 9 * 60; minutes < 18 * 60; minutes += 15) {
      final time = DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
      if (slotAvailable(providerId, service, time)) result.add(time);
    }
    return result;
  }

  void _checkCustomer(bool isDemoCustomer) {
    if (isDemoCustomer && visits.any((v) => v.isDemoCustomer && v.active)) {
      throw const DemoError('You already have an active visit. Cancel or finish it first.');
    }
  }

  Visit book(String providerId, HairService service, DateTime at, {bool sms = false}) {
    final p = provider(providerId);
    _checkProvider(p, service);
    _checkCustomer(true);
    if (!slotAvailable(providerId, service, at)) {
      throw const DemoError('That time is no longer available. Please choose another.');
    }
    final visit = Visit(
      id: 'v${++_sequence}', providerId: providerId, customerName: 'You (demo)',
      service: service, createdAt: now, isDemoCustomer: true,
      appointmentAt: at, smsRequested: sms,
    );
    visits.add(visit);
    notifyListeners();
    return visit;
  }

  Visit join(String providerId, HairService service, {
    String name = 'You (demo)', bool isDemoCustomer = true, bool sms = false,
  }) {
    final p = provider(providerId);
    _checkProvider(p, service);
    _checkCustomer(isDemoCustomer);
    if (p.homeBased) throw const DemoError('This home studio takes appointments only.');
    if (p.queuePaused) throw const DemoError('This provider has paused queue entries.');
    if (!isOpen(now)) throw const DemoError('The demo queue is open 9 am–6 pm. Book a time instead.');
    if (name.trim().isEmpty) throw const DemoError('Please enter a customer name.');
    final candidate = Visit(
      id: 'v${++_sequence}', providerId: providerId, customerName: name.trim(),
      service: service, createdAt: now, isDemoCustomer: isDemoCustomer, smsRequested: sms,
    );
    final start = _queueStart(providerId, candidate: candidate);
    final close = DateTime(now.year, now.month, now.day, 18);
    if (start.add(Duration(minutes: service.minutes)).isAfter(close)) {
      throw const DemoError('The queue is full for today. Please book another time.');
    }
    visits.add(candidate);
    notifyListeners();
    return candidate;
  }

  List<Visit> queue(String id) => activeFor(id)
      .where((v) => v.isQueue && v.status == VisitStatus.waiting).toList()
    ..sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : visits.indexOf(a).compareTo(visits.indexOf(b));
    });

  List<Visit> appointments(String id) => activeFor(id)
      .where((v) => !v.isQueue).toList()
    ..sort((a, b) => a.appointmentAt!.compareTo(b.appointmentAt!));

  DateTime _fitAroundAppointments(String id, DateTime start, int minutes, {String? ignore}) {
    var result = start;
    for (final v in appointments(id)) {
      if (v.id == ignore || v.status == VisitStatus.inService) continue;
      if (overlaps(result, minutes, v.appointmentAt!, v.service.minutes)) {
        final end = v.appointmentAt!.add(Duration(minutes: v.service.minutes));
        if (end.isAfter(result)) result = end;
      }
    }
    return result;
  }

  DateTime _queueStart(String id, {Visit? target, Visit? candidate}) {
    var cursor = now;
    for (final v in activeFor(id).where((v) => v.status == VisitStatus.inService)) {
      final end = v.startedAt!.add(Duration(minutes: v.service.minutes));
      if (end.isAfter(cursor)) cursor = end;
    }
    final waiting = [...queue(id), if (candidate != null) candidate];
    for (final v in waiting) {
      cursor = _fitAroundAppointments(id, cursor, v.service.minutes);
      if (v.id == target?.id || v.id == candidate?.id) return cursor;
      cursor = cursor.add(Duration(minutes: v.service.minutes));
    }
    return cursor;
  }

  int waitMinutes(Visit v) => !v.active || v.status == VisitStatus.inService
      ? 0 : math.max(0, _queueStart(v.providerId, target: v).difference(now).inMinutes);

  int position(Visit v) => queue(v.providerId).indexWhere((x) => x.id == v.id) + 1;

  int estimatedNewWait(String id) {
    final p = provider(id);
    final candidate = Visit(id: 'estimate', providerId: id, customerName: '',
      service: p.services.first, createdAt: now, isDemoCustomer: false);
    return math.max(0, _queueStart(id, candidate: candidate).difference(now).inMinutes);
  }

  void start(Visit v) {
    if (v.status != VisitStatus.waiting) throw const DemoError('This visit cannot be started.');
    if (activeFor(v.providerId).any((x) => x.status == VisitStatus.inService)) {
      throw const DemoError('Finish the current haircut first.');
    }
    if (v.isQueue && queue(v.providerId).first.id != v.id) {
      throw const DemoError('Start the first customer in the queue.');
    }
    if (!isOpen(now)) throw const DemoError('The demo provider is open 9 am–6 pm.');
    if (v.appointmentAt != null && now.isBefore(v.appointmentAt!)) {
      throw const DemoError('This appointment has not reached its start time.');
    }
    final fits = _fitAroundAppointments(v.providerId, now, v.service.minutes, ignore: v.id);
    if (fits.isAfter(now)) throw const DemoError('An appointment is reserved during this time.');
    if (now.add(Duration(minutes: v.service.minutes)).isAfter(DateTime(now.year, now.month, now.day, 18))) {
      throw const DemoError('This service would finish after closing.');
    }
    v.status = VisitStatus.inService;
    v.startedAt = now;
    notifyListeners();
  }

  void finish(Visit v) {
    if (v.status != VisitStatus.inService) throw const DemoError('Start this visit before finishing it.');
    v.status = VisitStatus.completed;
    v.finishedAt = now;
    notifyListeners();
  }

  void cancel(Visit v) {
    if (v.status != VisitStatus.waiting) throw const DemoError('Only waiting visits can be cancelled.');
    v.status = VisitStatus.cancelled;
    notifyListeners();
  }

  void toggleQueue(Provider p) {
    p.queuePaused = !p.queuePaused;
    notifyListeners();
  }

  void review(Provider p, bool approve) {
    if (p.application != ApplicationStatus.pending) return;
    p.application = approve ? ApplicationStatus.approved : ApplicationStatus.declined;
    notifyListeners();
  }
}
