import 'package:flutter/material.dart';
import '../data/backend.dart';
import '../data/store.dart';
import 'app.dart';
import 'common.dart';

class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen> {
  String group = 'Upcoming';
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    if (!store.signedIn) return PageBody(children: [
      const PageHeading('My Bookings', 'Your next little moment of self-care.'),
      Notice('Sign in to view your appointments and queue place.',
        action: FilledButton(onPressed: () => openAccount(context, store), child: const Text('Sign in'))),
    ]);
    final own = store.visits.where((v) => v['customer_id'] == store.backend!.userId).toList();
    final matching = own.where((v) => bookingGroup(v['status'] as String) == group).toList()
      ..sort((a, b) => group == 'Upcoming'
          ? (a['starts_at'] as String).compareTo(b['starts_at'] as String)
          : (b['starts_at'] as String).compareTo(a['starts_at'] as String));
    return RefreshIndicator(onRefresh: store.refreshVisits,
      child: PageBody(children: [
        PageHeading('My Bookings', 'Appointments, queue places and past visits. All times are New Zealand time.',
          action: OutlinedButton.icon(onPressed: store.refreshVisits,
              icon: const Icon(Icons.refresh), label: const Text('Refresh'))),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final label in ['Upcoming', 'Completed', 'Cancelled']) ChoiceChip(
            label: Text(label), selected: group == label,
            onSelected: (_) => setState(() => group = label)),
        ]),
        const SizedBox(height: 24),
        if (matching.isEmpty) Panel(child: Column(children: [
          const Icon(Icons.calendar_month_outlined, size: 40, color: ink),
          const SizedBox(height: 16),
          Text(group == 'Upcoming' ? 'Your next look starts here.' : 'No ${group.toLowerCase()} bookings yet.',
              style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(group == 'Upcoming' ? 'Find a local professional in Explore and choose a real available time.'
              : 'Your booking history will appear here.', textAlign: TextAlign.center),
        ])),
        ...matching.map((v) => VisitCard(store: store, visit: v)),
        if (store.moreVisits) ActionButton(store, 'Load more visits', store.loadMoreVisits),
      ]));
  }
}

String bookingGroup(String status) => ['booked', 'waiting', 'serving'].contains(status)
    ? 'Upcoming' : status == 'completed' ? 'Completed' : 'Cancelled';

class VisitCard extends StatelessWidget {
  const VisitCard(
      {super.key,
      required this.store,
      required this.visit,
      this.operator = false,
      this.onlinePayments});
  final AppStore store;
  final Json visit;
  final bool operator;
  final bool? onlinePayments;
  @override
  Widget build(BuildContext context) {
    final v = visit;
    final upcoming = ['waiting', 'booked'].contains(v['status']);
    return Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!operator && v['business_name'] != null)
        Text(v['business_name'] as String,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      if (v['queue_position'] != null)
        Text('Queue position: ${v['queue_position']}'),
      Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(v['service_name'] as String,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Chip(label: Text((v['status'] as String).replaceAll('_', ' ')))
          ]),
      if (operator)
        Text(v['customer_name'] as String,
            style: const TextStyle(fontSize: 18)),
      Text(
          '${v['kind'] == 'queue' ? 'Estimated ' : ''}${nzTime(v['starts_at'])} • ${v['minutes']} min'),
      const SizedBox(height: 8),
      Text(
          '${money(v['price_cents'])} NZD • ${v['payment_status'] == 'unpaid' ? 'Online payment not recorded' : (v['payment_status'] as String).replaceAll('_', ' ')}'),
      if (v['status'] == 'waiting')
        const Text(
            'Keep an eye on this screen. The time is an estimate, and the business may be running late.',
            style: TextStyle(fontSize: 12)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (!operator && ['booked', 'waiting', 'serving'].contains(v['status']))
          OutlinedButton.icon(
              onPressed: store.busy
                  ? null
                  : () async {
                      Json? address;
                      final ok = await store.run(() async {
                        address = Json.from(await store.backend!.rpc(
                            'visit_location', {'p_visit': v['id']}) as Map);
                      });
                      if (!ok || !context.mounted) return;
                      final location = address!;
                      await showDialog<void>(
                          context: context,
                          builder: (c) => AlertDialog(
                                  title: const Text('Your visit address'),
                                  content: Text(location['address'] as String),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(c),
                                        child: const Text('Close')),
                                    FilledButton(
                                        onPressed: () => store.run(() => openLink(
                                            'https://www.google.com/maps/dir/?api=1&destination=${location['lat']},${location['lng']}')),
                                        child: const Text('Directions'))
                                  ]));
                    },
              icon: const Icon(Icons.directions_outlined),
              label: const Text('Address & directions')),
        if (!operator &&
            upcoming &&
            v['payment_status'] == 'unpaid' &&
            (onlinePayments ?? v['online_payments'] == true))
          OutlinedButton.icon(
              onPressed: store.busy
                  ? null
                  : () => store.run(() async {
                        final result = await store.backend!.invoke('payments',
                            {'action': 'checkout', 'visit_id': v['id']});
                        await openLink(result['url'] as String);
                      }),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Pay online')),
        if (operator && upcoming)
          ActionButton(store, 'Start',
              () => store.changeVisit(v['id'] as String, 'start'),
              icon: Icons.play_arrow),
        if (operator && v['status'] == 'serving')
          ActionButton(store, 'Finish',
              () => store.changeVisit(v['id'] as String, 'complete'),
              icon: Icons.check),
        if (upcoming)
          OutlinedButton(
              onPressed: store.busy
                  ? null
                  : () async {
                      if (await confirm(context, 'Cancel this visit?',
                          'Your place will be released. If prepaid, a full refund will be requested.',
                          action: 'Cancel visit'))
                        await store.run(() =>
                            store.changeVisit(v['id'] as String, 'cancel'));
                    },
              child: const Text('Cancel visit')),
        if (operator && upcoming)
          TextButton(
              onPressed: store.busy
                  ? null
                  : () async {
                      if (await confirm(context, 'Mark as absent?',
                          'Only use this when the customer has missed their time. Prepaid visits will be refunded.'))
                        await store.run(() =>
                            store.changeVisit(v['id'] as String, 'no_show'));
                    },
              child: const Text('No show')),
        if (operator && v['payment_status'] == 'paid')
          TextButton(
              onPressed: store.busy
                  ? null
                  : () async {
                      if (await confirm(context, 'Issue full refund?',
                          'This requests a full refund of ${money(v['price_cents'])}.',
                          action: 'Request refund'))
                        await store.run(() async {
                          await store.backend!
                              .rpc('request_refund', {'p_visit': v['id']});
                          await store.refreshVisits();
                        });
                    },
              child: const Text('Refund')),
      ]),
    ]));
  }
}
