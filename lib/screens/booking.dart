import 'package:flutter/material.dart';
import '../data/backend.dart';
import '../data/store.dart';
import 'app.dart';
import 'common.dart';
import 'visits.dart';

Future<void> openBusiness(BuildContext context, AppStore store, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DetailScaffold(
            store: store,
            title: 'Services & booking',
            child: BookingScreen(store: store, businessId: id))));

class BookingScreen extends StatefulWidget {
  const BookingScreen(
      {super.key, required this.store, required this.businessId});
  final AppStore store;
  final String businessId;
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  late Future<Json> details;
  late Future<List<String>> photos;
  Future<List<Json>>? slots;
  Future<List<Json>>? estimates;
  String? service, resource, created;
  Json? selected;
  bool queue = false;
  late DateTime day;
  @override
  void initState() {
    super.initState();
    final n = nzNow();
    day = DateTime(n.year, n.month, n.day);
    reload();
  }

  void reload() {
    details = widget.store.backend!.rpc('business_detail',
        {'p_business': widget.businessId}).then((v) => Json.from(v as Map));
    photos = widget.store.backend!.photos(widget.businessId).catchError((_) => <String>[]);
  }

  void loadEstimates() {
    if (service != null) estimates = widget.store.backend!.rpc('queue_estimates', {'p_business': widget.businessId, 'p_service': service}).then((v) => List<Json>.from(v as List));
  }

  void loadSlots() {
    selected = null;
    if (service != null)
      slots = widget.store.backend!.rpc('available_slots', {
        'p_business': widget.businessId,
        'p_service': service,
        'p_day': dayKey(day)
      }).then((v) => List<Json>.from(v as List));
  }

  Future<void> book(Json business) async {
    final s = widget.store;
    if (!s.signedIn ||
        (s.profile['display_name'] ?? '').toString().trim().isEmpty) {
      await openAccount(context, s);
      return;
    }
    if (service == null || (queue ? resource == null : selected == null)) {
      await s.run(() async {
        throw Exception('Choose a service and ${queue ? 'chair' : 'time'}');
      });
      return;
    }
    final services = List<Json>.from(business['services'] as List);
    final choice = services.firstWhere((v) => v['id'] == service);
    final accepted = await confirm(
        context,
        queue ? 'Join this queue?' : 'Confirm appointment?',
        '${choice['name']} • ${money(choice['price_cents'])} NZD\n${queue ? 'Queue times are estimates. You’ll see your expected time in My Bookings.' : nzTime(selected!['starts_at'])}\nPay at the business, or online if enabled. Cancel upcoming visits in My Bookings. Prepaid cancellations request a full refund.',
        action: queue ? 'Join queue' : 'Confirm booking');
    if (!accepted) return;
    await s.run(() async {
      final id = await s.backend!.rpc('create_visit', {
        'p_business': widget.businessId,
        'p_service': service,
        'p_resource': queue ? resource : selected!['resource_id'],
        'p_kind': queue ? 'queue' : 'appointment',
        'p_start': queue ? null : selected!['starts_at']
      });
      await s.refreshVisits();
      if (mounted)
        setState(() {
          created = id as String;
        });
    });
  }

  @override
  Widget build(BuildContext context) => PageBody(children: [
        AsyncPanel<Json>(
            future: details,
            retry: () => setState(reload),
            builder: (b) {
              final services = List<Json>.from(b['services'] as List);
              final resources = List<Json>.from(b['resources'] as List);
              resource ??=
                  resources.isEmpty ? null : resources.first['id'] as String;
              final visit = widget.store.visits
                  .where((v) => v['id'] == created)
                  .firstOrNull;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageHeading(b['name'] as String,
                        '${b['suburb']} • ${b['kind'] == 'home' ? 'Home studio' : 'SpicySelf member'}'),
                    if (b['status'] == 'approved')
                      const Padding(padding: EdgeInsets.only(bottom: 16),
                        child: StatusPill('Verified SpicySelf business', icon: Icons.verified_outlined)),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final s = widget.store;
                        if (!s.signedIn) { await openAccount(context, s); return; }
                        await s.run(() => s.favorite(widget.businessId));
                        if (mounted) setState(() {});
                      },
                      icon: Icon(widget.store.favorites.contains(widget.businessId) ? Icons.favorite : Icons.favorite_border),
                      label: Text(widget.store.favorites.contains(widget.businessId) ? 'Remove favourite' : 'Save favourite')),
                    if ((b['description'] as String).isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(b['description'] as String)),
                    if (b['kind'] == 'home')
                      const Notice(
                          'This map pin is approximate. The exact address is available after you confirm an upcoming visit.'),
                    AsyncPanel<List<String>>(
                        future: photos,
                        builder: (urls) => urls.isEmpty
                            ? BrandPlaceholder(home: b['kind'] == 'home', height: 180)
                            : Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: SizedBox(
                                    height: 180,
                                    child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: urls.length,
                                        separatorBuilder: (_, i) =>
                                            const SizedBox(width: 12),
                                        itemBuilder: (_, i) => ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            child: Image.network(urls[i],
                                                width: 240,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, e, st) =>
                                                    const SizedBox(
                                                        width: 240,
                                                        child: Center(
                                                            child:
                                                                Icon(Icons.broken_image_outlined))))))))),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final h in b['hours'] as List)
                        Chip(
                            label: Text('${const [
                          'Mon',
                          'Tue',
                          'Wed',
                          'Thu',
                          'Fri',
                          'Sat',
                          'Sun'
                        ][(h['weekday'] as int) - 1]} ${(h['opens'] as String).substring(0, 5)}–${(h['closes'] as String).substring(0, 5)}'))
                    ]),
                    const SizedBox(height: 20),
                    if (visit != null) ...[
                      const PageHeading('You’re booked in.',
                          'Your place is saved. Keep My Bookings open for updates.'),
                      VisitCard(
                          store: widget.store,
                          visit: visit,
                          onlinePayments: b['online_payments'] == true)
                    ],
                    if (created != null && visit == null) const Notice('Your place was saved. Open My Bookings and refresh for the latest details.'),
                    if (b['status'] != 'approved')
                      const Notice('This listing is not currently accepting bookings.'),
                    if (created == null && b['status'] == 'approved')
                      Panel(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            Text('Make time for yourself',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 16),
                            if (services.isEmpty)
                              const Text('Services are not available yet.')
                            else
                              DropdownButtonFormField<String>(
                                  key: const ValueKey('service-picker'),
                                  initialValue: service,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                      labelText: 'Service',
                                      border: OutlineInputBorder()),
                                  items: services
                                      .map((v) => DropdownMenuItem(
                                          value: v['id'] as String,
                                          child: Text(
                                              '${v['name']} • ${v['minutes']} min • ${money(v['price_cents'])}',
                                              overflow: TextOverflow.ellipsis)))
                                      .toList(),
                                  onChanged: (value) => setState(() {
                                        service = value;
                                        loadSlots();
                                        if (queue) loadEstimates();
                                      })),
                            const SizedBox(height: 16),
                            if (b['kind'] != 'home' && b['queue_open'] == true)
                              Wrap(spacing: 8, children: [
                                ChoiceChip(
                                    label: const Text('Book a time'),
                                    selected: !queue,
                                    onSelected: (_) =>
                                        setState(() => queue = false)),
                                ChoiceChip(
                                    label: const Text('Join live queue'),
                                    selected: queue,
                                    onSelected: (_) => setState(() { queue = true; loadEstimates(); }))
                              ]),
                            const SizedBox(height: 16),
                            if (queue) ...[
                              if (estimates != null) AsyncPanel<List<Json>>(future: estimates!, retry: () => setState(loadEstimates), builder: (items) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final e in items) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(e['wait_minutes'] == null ? '${e['name']}: no more queue space today' : '${e['name']}: about ${e['wait_minutes']} min • ${e['waiting']} waiting', style: const TextStyle(fontWeight: FontWeight.bold)))])),
                              const Text(
                                  'We’ll reserve your place behind the people already waiting. Estimates move as the barber works. Come back to My Bookings to see updates.'),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                  initialValue: resource,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                      labelText: 'Chair / professional',
                                      border: OutlineInputBorder()),
                                  items: resources
                                      .map((r) => DropdownMenuItem(
                                          value: r['id'] as String,
                                          child: Text(r['name'] as String)))
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => resource = v))
                            ],
                            if (!queue) ...[
                              OutlinedButton.icon(
                                  onPressed: () async {
                                    final n = nzNow();
                                    final first =
                                        DateTime(n.year, n.month, n.day);
                                    final chosen = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            day.isBefore(first) ? first : day,
                                        firstDate: first,
                                        lastDate: first
                                            .add(const Duration(days: 89)));
                                    if (chosen != null && mounted)
                                      setState(() {
                                        day = chosen;
                                        loadSlots();
                                      });
                                  },
                                  icon:
                                      const Icon(Icons.calendar_today_outlined),
                                  label: Text(dayKey(day))),
                              const SizedBox(height: 12),
                              if (slots != null)
                                AsyncPanel<List<Json>>(
                                    future: slots!,
                                    retry: () => setState(loadSlots),
                                    builder: (items) => items.isEmpty
                                        ? const Text(
                                            'No times available. Try another day.')
                                        : Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: items
                                                .map((v) => ChoiceChip(
                                                    key: ValueKey(
                                                        '${v['resource_id']}-${v['starts_at']}'),
                                                    label: Text(
                                                        '${nzTime(v['starts_at'])}\n${v['resource_name']}'),
                                                    selected: selected?[
                                                                'resource_id'] ==
                                                            v['resource_id'] &&
                                                        selected?['starts_at'] ==
                                                            v['starts_at'],
                                                    onSelected: (_) => setState(
                                                        () => selected = v)))
                                                .toList()))
                              else
                                const Text('Choose a service to see available times.'),
                            ],
                            const SizedBox(height: 20),
                            FilledButton.icon(
                                key: const ValueKey('confirm-visit'),
                                onPressed: widget.store.busy || services.isEmpty
                                    ? null
                                    : () => book(b),
                                icon: Icon(queue
                                    ? Icons.groups_outlined
                                    : Icons.event_available),
                                label: Text(queue
                                    ? 'Join queue'
                                    : 'Confirm appointment')),
                            const SizedBox(height: 12),
                            const Text(
                                'Prices in NZD. Online payment is optional when the business has enabled it. Apple Pay, Google Pay and other methods appear only when supported by your device and payment provider.',
                                style: TextStyle(fontSize: 12)),
                          ])),
                    TextButton.icon(
                        onPressed: () async {
                          if (!widget.store.signedIn) {
                            await openAccount(context, widget.store);
                            return;
                          }
                          if (!context.mounted) return;
                          final controller = TextEditingController();
                          final message = await showDialog<String>(
                              context: context,
                              builder: (c) => AlertDialog(
                                      title: const Text('Report a concern'),
                                      content: TextField(
                                          controller: controller,
                                          maxLength: 2000,
                                          maxLines: 4,
                                          decoration: const InputDecoration(
                                              hintText:
                                                  'Please describe what happened (at least 10 characters)')),
                                      actions: [
                                        TextButton(
                                            onPressed: () => Navigator.pop(c),
                                            child: const Text('Cancel')),
                                        FilledButton(
                                            onPressed: () => Navigator.pop(
                                                c, controller.text),
                                            child: const Text('Send report'))
                                      ]));
                          controller.dispose();
                          if (message != null)
                            await widget.store.run(
                                () => widget.store.backend!.save('reports', {
                                      'user_id': widget.store.backend!.userId,
                                      'business_id': widget.businessId,
                                      'message': message
                                    }));
                        },
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Report a concern')),
                  ]);
            })
      ]);
}
