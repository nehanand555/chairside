import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/demo_store.dart';
import 'common.dart';

class CustomerPage extends StatelessWidget {
  const CustomerPage({required this.store, required this.tab, required this.onBooked, super.key});
  final DemoStore store;
  final int tab;
  final VoidCallback onBooked;
  @override
  Widget build(BuildContext context) => tab == 0
      ? _Discover(store: store, onBooked: onBooked)
      : _MyVisits(store: store);
}

class _Discover extends StatefulWidget {
  const _Discover({required this.store, required this.onBooked});
  final DemoStore store;
  final VoidCallback onBooked;
  @override
  State<_Discover> createState() => _DiscoverState();
}

class _DiscoverState extends State<_Discover> {
  String query = '';
  String filter = 'All';

  Future<void> openProvider(Provider provider) async {
    final booked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: paper,
      builder: (_) => _BookingSheet(store: widget.store, provider: provider),
    );
    if (!mounted) return;
    if (booked == true) widget.onBooked();
  }

  @override
  Widget build(BuildContext context) {
    final providers = widget.store.listed.where((p) {
      final matchesText = '${p.name} ${p.suburb} ${p.services.map((s) => s.name).join(' ')}'
          .toLowerCase().contains(query.toLowerCase().trim());
      return matchesText && (filter == 'All' || (filter == 'Home studios' ? p.homeBased : !p.homeBased));
    }).toList();
    return ListView(padding: const EdgeInsets.all(20), children: [
      Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(28)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Tag('LOCAL HAIR. LESS WAITING.', color: lime, icon: Icons.auto_awesome),
          const SizedBox(height: 22),
          const Text('Your next good\nhair day starts here.',
            style: TextStyle(fontSize: 35, height: 1.12, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1)),
          const SizedBox(height: 16),
          const Text('Find your local chair. Book a time or join the queue before you leave home.',
            style: TextStyle(fontSize: 15, color: Color(0xFFD1E0D6), height: 1.6)),
          const SizedBox(height: 20),
          Wrap(spacing: 8, runSpacing: 8, children: const [
            Tag('Wellington region', color: Color(0xFFE9EFE2), icon: Icons.location_on_outlined),
            Tag('Prices in NZD', color: Color(0xFFE9EFE2)),
          ]),
        ]),
      ),
      const SizedBox(height: 24),
      TextField(
        key: const Key('provider-search'),
        onChanged: (value) => setState(() => query = value),
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Suburb, provider or service'),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 4, children: ['All', 'Barbershops', 'Home studios'].map((label) => ChoiceChip(
        label: Text(label), selected: filter == label, onSelected: (_) => setState(() => filter = label),
      )).toList()),
      const SizedBox(height: 22),
      SectionTitle('Find your chair', subtitle: '${providers.length} sample providers · All profiles are fictional'),
      if (providers.isEmpty) const EmptyMessage('No matches yet', 'Try a different suburb, service or filter.', icon: Icons.search_off),
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(spacing: 16, runSpacing: 16, children: providers.map((p) => SizedBox(
          width: width,
          child: _ProviderCard(provider: p, store: widget.store, onTap: () => openProvider(p)),
        )).toList());
      }),
      const SizedBox(height: 24),
      const Text('Home studios are appointment-only in this prototype. No address or location permission is required to explore.',
        style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.6)),
    ]);
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.provider, required this.store, required this.onTap});
  final Provider provider;
  final DemoStore store;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = provider;
    final open = store.isOpen(store.now) && !p.queuePaused;
    final price = p.services.map((s) => s.price).reduce((a, b) => a < b ? a : b);
    return Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 58, height: 58,
          decoration: BoxDecoration(color: p.homeBased ? const Color(0xFFF0E5D7) : const Color(0xFFDFE8D8), borderRadius: BorderRadius.circular(18)),
          child: Icon(p.homeBased ? Icons.home_outlined : Icons.content_cut, color: ink, size: 28)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(p.suburb, style: const TextStyle(color: Colors.black54)),
        ])),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        Tag(p.homeBased ? 'Home studio' : 'Barbershop', icon: p.homeBased ? Icons.home_outlined : Icons.storefront_outlined),
        Tag(p.homeBased ? 'By appointment' : open ? 'Queue open' : 'Queue unavailable', color: p.homeBased || !open ? paper : lime),
      ]),
      const SizedBox(height: 14),
      Text(p.description, style: const TextStyle(color: Colors.black54, height: 1.5)),
      const SizedBox(height: 16),
      Text('From ${money(price)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      if (!p.homeBased && open) Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('Estimated queue wait: ${store.estimatedNewWait(p.id)}–${store.estimatedNewWait(p.id) + 10} min',
          style: const TextStyle(fontSize: 12, color: green)),
      ),
      const SizedBox(height: 18),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        key: Key('view-${p.id}'), onPressed: onTap, icon: const Icon(Icons.arrow_forward, size: 18), label: const Text('View services & times'),
      )),
    ]));
  }
}

class _BookingSheet extends StatefulWidget {
  const _BookingSheet({required this.store, required this.provider});
  final DemoStore store;
  final Provider provider;
  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  late HairService service = widget.provider.services.first;
  int day = 0;
  DateTime? selected;
  bool queueMode = false;
  bool sms = false;
  String? error;

  void submit() {
    try {
      if (queueMode) {
        widget.store.join(widget.provider.id, service, sms: sms);
      } else {
        if (selected == null) {
          setState(() => error = 'Please choose an appointment time.');
          return;
        }
        widget.store.book(widget.provider.id, service, selected!, sms: sms);
      }
      Navigator.of(context).pop(true);
    } on DemoError catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final now = widget.store.now;
      final date = DateTime(now.year, now.month, now.day + day);
      final slots = widget.store.slots(widget.provider.id, service, date);
      return FractionallySizedBox(heightFactor: .94, child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(widget.provider.name, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800))),
            IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
          Text('${widget.provider.suburb} · ${widget.provider.homeBased ? 'Home studio' : 'Barbershop'}'),
          const SizedBox(height: 24),
          const Text('1. Choose a service', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...widget.provider.services.map((s) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(s == service ? Icons.radio_button_checked : Icons.radio_button_off, color: green),
            title: Text(s.name), subtitle: Text('${s.minutes} min · ${money(s.price)}'),
            selected: service == s,
            onTap: () => setState(() { service = s; selected = null; error = null; }),
          )),
          const SizedBox(height: 16),
          const Text('2. Choose how to visit', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 8, children: [
            ChoiceChip(label: const Text('Book a time'), selected: !queueMode,
              onSelected: (_) => setState(() { queueMode = false; error = null; })),
            if (!widget.provider.homeBased) ChoiceChip(
              key: const Key('queue-choice'), label: const Text('Join live queue'), selected: queueMode,
              onSelected: (_) => setState(() { queueMode = true; error = null; }),
            ),
          ]),
          const SizedBox(height: 16),
          if (queueMode) Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Keep your day moving.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Your queue position and estimated wait appear in My visits. Booked appointments take priority when their time is due.', style: TextStyle(height: 1.6)),
            const SizedBox(height: 8),
            Text(widget.provider.queuePaused ? 'Queue paused. Try booking a time.' : 'Demo opening hours: 9 am–6 pm', style: const TextStyle(color: green)),
          ])) else ...[
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: List.generate(7, (index) {
              final d = DateTime(now.year, now.month, now.day + index);
              return Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
                label: Text(index == 0 ? 'Today' : dayLabel(d)), selected: day == index,
                onSelected: (_) => setState(() { day = index; selected = null; error = null; }),
              ));
            }))),
            const SizedBox(height: 14),
            if (slots.isEmpty) const Text('No times left on this day. Choose another day.'),
            Wrap(spacing: 8, runSpacing: 8, children: slots.map((slot) => ChoiceChip(
              key: Key('slot-${slot.toIso8601String()}'),
              label: Text(timeLabel(slot)), selected: selected == slot,
              onSelected: (_) => setState(() { selected = slot; error = null; }),
            )).toList()),
          ],
          const SizedBox(height: 20),
          SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
            title: const Text('Prefer SMS updates'),
            subtitle: const Text('Demo preference only. No mobile number is collected and no message is sent.'),
            value: sms, onChanged: (value) => setState(() => sms = value)),
          const SizedBox(height: 12),
          Text('${money(service.price)} · Pay at your visit', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('This creates a fictional visit on this device only. No payment is taken.', style: TextStyle(fontSize: 12, color: Colors.black54)),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: FilledButton(
            key: const Key('confirm-visit'), onPressed: submit,
            child: Text(queueMode ? 'Join demo queue' : 'Create demo booking'),
          )),
        ]),
      ));
    },
  );
}

class _MyVisits extends StatelessWidget {
  const _MyVisits({required this.store});
  final DemoStore store;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    const SectionTitle('Your chair is waiting.', subtitle: 'Appointments and queue updates, all in one place.'),
    if (store.mine.isEmpty) const EmptyMessage('Your next visit starts here', 'Find a provider in Discover, then book a time or join a queue.'),
    ...store.mine.map((v) {
      final p = store.provider(v.providerId);
      final wait = store.waitMinutes(v);
      return Padding(padding: const EdgeInsets.only(bottom: 16), child: Surface(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tag(statusLabel(v), color: v.active ? lime : paper),
          const SizedBox(height: 16),
          Text(p.name, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text('${v.service.name} · ${money(v.service.price)} · ${p.suburb}'),
          const SizedBox(height: 18),
          if (v.appointmentAt != null) Text('${dayLabel(v.appointmentAt!)} at ${timeLabel(v.appointmentAt!)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (v.isQueue && v.status == VisitStatus.waiting) ...[
            Text('You are #${store.position(v)} in the queue', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: green)),
            const SizedBox(height: 8),
            Text('Estimated wait: $wait–${wait + 10} min. Times can change.'),
          ],
          if (v.status == VisitStatus.inService) const Text('Your visit is in progress. Enjoy your fresh start!'),
          if (v.smsRequested) const Padding(padding: EdgeInsets.only(top: 12), child: Text('SMS preference saved for this demo. No texts are sent.', style: TextStyle(fontSize: 12, color: Colors.black54))),
          if (v.status == VisitStatus.waiting) Padding(padding: const EdgeInsets.only(top: 14), child: OutlinedButton.icon(
            onPressed: () => perform(context, () => store.cancel(v)), icon: const Icon(Icons.close, size: 17),
            label: Text(v.isQueue ? 'Leave queue' : 'Cancel demo booking'),
          )),
        ],
      )));
    }),
  ]);
}
