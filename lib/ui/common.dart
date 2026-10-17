import 'package:flutter/material.dart';

import '../models/models.dart';

const ink = Color(0xFF193C32);
const green = Color(0xFF246E53);
const paper = Color(0xFFF5F5EF);
const lime = Color(0xFFD9F18A);

String money(int dollars) => 'NZ\$$dollars';
String timeLabel(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '$hour:${time.minute.toString().padLeft(2, '0')} ${time.hour < 12 ? 'am' : 'pm'}';
}
String dayLabel(DateTime date) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
}
String statusLabel(Visit v) => switch (v.status) {
  VisitStatus.waiting => v.isQueue ? 'In queue' : 'Booked',
  VisitStatus.inService => 'In the chair',
  VisitStatus.completed => 'Completed',
  VisitStatus.cancelled => 'Cancelled',
};

void perform(BuildContext context, VoidCallback action) {
  try {
    action();
  } on DemoError catch (error) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
  }
}

class Tag extends StatelessWidget {
  const Tag(this.label, {this.color = paper, this.icon, super.key});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 14, color: ink), const SizedBox(width: 5)],
      Flexible(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink))),
    ]),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {this.subtitle, super.key});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16, top: 6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -.6)),
      if (subtitle != null) ...[
        const SizedBox(height: 6),
        Text(subtitle!, style: const TextStyle(color: Colors.black54, height: 1.5)),
      ],
    ]),
  );
}

class Surface extends StatelessWidget {
  const Surface({required this.child, this.padding = const EdgeInsets.all(20), super.key});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE0E5DD))),
    child: child,
  );
}

class EmptyMessage extends StatelessWidget {
  const EmptyMessage(this.title, this.body, {this.icon = Icons.event_available_outlined, super.key});
  final String title;
  final String body;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Surface(child: Column(children: [
    const SizedBox(height: 16),
    Icon(icon, color: green, size: 40),
    const SizedBox(height: 16),
    Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, height: 1.5)),
    const SizedBox(height: 16),
  ]));
}
