import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/demo_store.dart';
import 'common.dart';

class BarberPage extends StatefulWidget {
  const BarberPage({required this.store, super.key});
  final DemoStore store;
  @override
  State<BarberPage> createState() => _BarberPageState();
}

class _BarberPageState extends State<BarberPage> {
  String providerId = 'p1';

  Future<void> addWalkIn(Provider provider) => showDialog<void>(
    context: context,
    builder: (_) => _WalkInDialog(store: widget.store, provider: provider),
  );

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final p = store.provider(providerId);
    final queue = store.queue(providerId);
    final appointments = store.appointments(providerId);
    final serving = store.activeFor(providerId).where((v) => v.status == VisitStatus.inService).toList();
    final completed = store.forProvider(providerId).where((v) => v.status == VisitStatus.completed).length;
    return ListView(padding: const EdgeInsets.all(20), children: [
      const SectionTitle('A calmer day behind the chair.', subtitle: 'One view for booked appointments and walk-ins.'),
      Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('PREVIEW A PROVIDER', style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.bold, color: green)),
        DropdownButtonHideUnderline(child: DropdownButton<String>(
          isExpanded: true, value: providerId,
          items: store.listed.map((provider) => DropdownMenuItem(value: provider.id, child: Text(provider.name))).toList(),
          onChanged: (value) => setState(() => providerId = value!),
        )),
        Text('${p.suburb} · One chair · Demo hours 9 am–6 pm', style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 20),
        Wrap(spacing: 12, runSpacing: 12, children: [
          Tag('${queue.length} in queue', icon: Icons.groups_outlined, color: lime),
          Tag('${appointments.length} active appointments', icon: Icons.event_outlined),
          Tag('$completed completed', icon: Icons.check_circle_outline),
        ]),
        const SizedBox(height: 20),
        if (!p.homeBased) Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(onPressed: () => addWalkIn(p), icon: const Icon(Icons.person_add_alt_1), label: const Text('Add walk-in')),
          OutlinedButton.icon(onPressed: () => store.toggleQueue(p),
            icon: Icon(p.queuePaused ? Icons.play_arrow : Icons.pause),
            label: Text(p.queuePaused ? 'Reopen queue' : 'Pause new queue entries')),
        ]),
        if (p.homeBased) const Text('This home studio accepts appointments only.'),
        if (p.queuePaused) const Padding(padding: EdgeInsets.only(top: 14), child: Text('New queue entries are paused. Existing visits stay in place.', style: TextStyle(color: green))),
      ])),
      const SizedBox(height: 24),
      const SectionTitle('In the chair'),
      if (serving.isEmpty) const EmptyMessage('Ready for your next customer', 'Start an eligible appointment or the first customer in the queue.', icon: Icons.content_cut),
      ...serving.map((v) => _VisitRow(visit: v, store: store)),
      const SizedBox(height: 24),
      const SectionTitle('Walk-in queue', subtitle: 'FIFO order. Due appointments reserve time in the schedule.'),
      if (queue.isEmpty) const Text('No one is waiting in the walk-in queue.'),
      ...queue.map((v) => _VisitRow(visit: v, store: store)),
      const SizedBox(height: 24),
      const SectionTitle('Appointments'),
      if (appointments.isEmpty) const Text('No active appointments. Try making one from the Customer view.'),
      ...appointments.where((v) => v.status == VisitStatus.waiting).map((v) => _VisitRow(visit: v, store: store)),
      const SizedBox(height: 24),
      const Text('Demo role switching is for trying the screens. Production access will require authentication and server-enforced permissions.',
        style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.6)),
    ]);
  }
}

class _VisitRow extends StatelessWidget {
  const _VisitRow({required this.visit, required this.store});
  final Visit visit;
  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    final v = visit;
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Surface(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          CircleAvatar(backgroundColor: const Color(0xFFE5EDD9), child: Icon(v.isQueue ? Icons.person_outline : Icons.event_outlined, color: ink)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v.customerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${v.service.name} · ${v.service.minutes} min · ${money(v.service.price)}'),
          ])),
        ]),
        const SizedBox(height: 14),
        Text(v.appointmentAt == null
          ? (v.status == VisitStatus.inService ? 'In progress' : '#${store.position(v)} · Estimated wait ${store.waitMinutes(v)}–${store.waitMinutes(v) + 10} min')
          : '${dayLabel(v.appointmentAt!)} · ${timeLabel(v.appointmentAt!)}'),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 8, children: [
          if (v.status == VisitStatus.waiting) FilledButton.icon(
            key: Key('start-${v.id}'), onPressed: () => perform(context, () => store.start(v)),
            icon: const Icon(Icons.play_arrow), label: const Text('Start haircut'),
          ),
          if (v.status == VisitStatus.inService) FilledButton.icon(
            key: Key('finish-${v.id}'), onPressed: () => perform(context, () => store.finish(v)),
            icon: const Icon(Icons.check), label: const Text('Finish haircut'),
          ),
          if (v.status == VisitStatus.waiting) TextButton(
            onPressed: () => perform(context, () => store.cancel(v)), child: const Text('Cancel visit'),
          ),
        ]),
      ],
    )));
  }
}

class _WalkInDialog extends StatefulWidget {
  const _WalkInDialog({required this.store, required this.provider});
  final DemoStore store;
  final Provider provider;
  @override
  State<_WalkInDialog> createState() => _WalkInDialogState();
}

class _WalkInDialogState extends State<_WalkInDialog> {
  final controller = TextEditingController();
  late HairService service = widget.provider.services.first;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    try {
      widget.store.join(widget.provider.id, service, name: controller.text, isDemoCustomer: false);
      Navigator.pop(context);
    } on DemoError catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a walk-in'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Use a fictional name. No account or app download needed in this demo.'),
      const SizedBox(height: 16),
      TextField(key: const Key('walkin-name'), controller: controller, maxLength: 50,
        decoration: const InputDecoration(labelText: 'Customer name')),
      const SizedBox(height: 12),
      ...widget.provider.services.map((s) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(service == s ? Icons.radio_button_checked : Icons.radio_button_off, color: green),
        title: Text(s.name), subtitle: Text('${s.minutes} min · ${money(s.price)}'),
        onTap: () => setState(() => service = s),
      )),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: submit, child: const Text('Add to queue')),
    ],
  );
}
