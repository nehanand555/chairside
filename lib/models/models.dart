enum VisitStatus { waiting, inService, completed, cancelled }

enum ApplicationStatus { pending, approved, declined }

class HairService {
  const HairService(this.id, this.name, this.minutes, this.price);
  final String id;
  final String name;
  final int minutes;
  final int price;
}

class Provider {
  Provider({
    required this.id,
    required this.name,
    required this.suburb,
    required this.description,
    required this.homeBased,
    required this.services,
    this.application = ApplicationStatus.approved,
  });

  final String id;
  final String name;
  final String suburb;
  final String description;
  final bool homeBased;
  final List<HairService> services;
  ApplicationStatus application;
  bool queuePaused = false;
}

class Visit {
  Visit({
    required this.id,
    required this.providerId,
    required this.customerName,
    required this.service,
    required this.createdAt,
    required this.isDemoCustomer,
    this.appointmentAt,
    this.smsRequested = false,
    this.status = VisitStatus.waiting,
  });

  final String id;
  final String providerId;
  final String customerName;
  final HairService service;
  final DateTime createdAt;
  final bool isDemoCustomer;
  final DateTime? appointmentAt;
  final bool smsRequested;
  VisitStatus status;
  DateTime? startedAt;
  DateTime? finishedAt;

  bool get active => status == VisitStatus.waiting || status == VisitStatus.inService;
  bool get isQueue => appointmentAt == null;
}

class DemoError implements Exception {
  const DemoError(this.message);
  final String message;
  @override
  String toString() => message;
}
