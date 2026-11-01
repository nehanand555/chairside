import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/backend.dart';
import '../data/store.dart';
import 'app.dart';
import 'common.dart';
import 'visits.dart';

DateTime nzDateOf(String value) {
  final local = tz.TZDateTime.from(
    DateTime.parse(value),
    tz.getLocation('Pacific/Auckland'),
  );
  return DateTime(local.year, local.month, local.day);
}

class BusinessSchedule extends StatefulWidget {
  const BusinessSchedule({
    super.key,
    required this.store,
    required this.business,
  });
  final AppStore store;
  final Json business;
  @override
  State<BusinessSchedule> createState() => _BusinessScheduleState();
}

class _BusinessScheduleState extends State<BusinessSchedule> {
  late DateTime day;
  bool week = false;
  String? professional;
  late Future<Json> page;
  int offset = 0;
  int loadedRevision = -1;
  final List<Json> loaded = [];
  @override
  void initState() {
    super.initState();
    final now = nzNow();
    day = DateTime(now.year, now.month, now.day);
    load();
  }

  void load({bool more = false}) {
    if (!more) {
      loaded.clear();
      offset = 0;
    }
    final start = week ? day.subtract(Duration(days: day.weekday - 1)) : day;
    loadedRevision = widget.store.visitRevision;
    page = widget.store.backend!
        .rpc('business_schedule', {
          'p_business': widget.business['id'],
          'p_day': dayKey(start),
          'p_days': week ? 7 : 1,
          'p_offset': offset,
        })
        .then((result) {
          final data = Json.from(result as Map);
          return data;
        });
  }

  Future<void> addAppointment() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailScaffold(
          store: widget.store,
          title: 'New appointment',
          child: AppointmentEditor(
            store: widget.store,
            business: widget.business,
          ),
        ),
      ),
    );
    if (mounted) setState(() => load());
  }

  @override
  Widget build(BuildContext context) {
    if (loadedRevision != widget.store.visitRevision) load();
    final resources = List<Json>.from(widget.business['resources'] as List);
    if (professional != null &&
        professional != '' &&
        !resources.any((r) => r['id'] == professional))
      professional = null;
    final start = week ? day.subtract(Duration(days: day.weekday - 1)) : day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Your appointment calendar',
          subtitle:
              'Pacific/Auckland · confirmed appointments, not availability',
          action: OutlinedButton.icon(
            onPressed: addAppointment,
            icon: const Icon(Icons.add),
            label: const Text('New appointment'),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('Day'),
              selected: !week,
              onSelected: (_) => setState(() {
                week = false;
                load();
              }),
            ),
            ChoiceChip(
              label: const Text('Week'),
              selected: week,
              onSelected: (_) => setState(() {
                week = true;
                load();
              }),
            ),
            IconButton(
              tooltip: 'Previous period',
              onPressed: () => setState(() {
                day = day.subtract(Duration(days: week ? 7 : 1));
                load();
              }),
              icon: const Icon(Icons.chevron_left),
            ),
            OutlinedButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: day,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2040),
                );
                if (picked != null && mounted)
                  setState(() {
                    day = picked;
                    load();
                  });
              },
              child: Text(dayKey(start)),
            ),
            IconButton(
              tooltip: 'Next period',
              onPressed: () => setState(() {
                day = day.add(Duration(days: week ? 7 : 1));
                load();
              }),
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(
              onPressed: () => setState(() {
                final now = nzNow();
                day = DateTime(now.year, now.month, now.day);
                load();
              }),
              child: const Text('Today'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: professional ?? '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Professional / chair'),
          items: [
            const DropdownMenuItem(value: '', child: Text('All professionals')),
            for (final resource in resources)
              DropdownMenuItem(
                value: resource['id'] as String,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProfessionalAvatar(
                      backend: widget.store.backend!,
                      resource: resource,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: Text(resource['name'] as String)),
                  ],
                ),
              ),
          ],
          onChanged: (value) => setState(() => professional = value),
        ),
        const SizedBox(height: 20),
        AsyncPanel<Json>(
          future: page,
          retry: () => setState(() => load()),
          builder: (data) {
            final items = [
              ...loaded,
              ...List<Json>.from(data['items'] as List),
            ];
            final filtered = items
                .where(
                  (v) =>
                      professional == null ||
                      professional == '' ||
                      v['resource_id'] == professional,
                )
                .toList();
            if (week)
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < 7; i++)
                          SizedBox(
                            width: 230,
                            child: Panel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    dayKey(start.add(Duration(days: i))),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 12),
                                  if (!filtered.any(
                                    (v) =>
                                        nzDateOf(v['starts_at']) ==
                                        start.add(Duration(days: i)),
                                  ))
                                    const Text('No appointments loaded'),
                                  for (final visit in filtered.where(
                                    (v) =>
                                        nzDateOf(v['starts_at']) ==
                                        start.add(Duration(days: i)),
                                  ))
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(visit['customer_name']),
                                      subtitle: Text(
                                        '${nzTime(visit['starts_at'])}\n${visit['resource_name']} · ${visit['status']}',
                                      ),
                                      onTap: () => setState(() {
                                        day = start.add(Duration(days: i));
                                        week = false;
                                        load();
                                      }),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (data['has_more'] == true)
                    TextButton(
                      onPressed: () => setState(() {
                        loaded.addAll(List<Json>.from(data['items']));
                        offset += 100;
                        load(more: true);
                      }),
                      child: const Text('Load more appointments'),
                    ),
                ],
              );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (filtered.isEmpty)
                  const Notice('No appointments on this date.'),
                for (final resource in resources.where(
                  (r) =>
                      professional == null ||
                      professional == '' ||
                      r['id'] == professional,
                )) ...[
                  SectionHeader(resource['name'] as String),
                  for (final visit in filtered.where(
                    (v) => v['resource_id'] == resource['id'],
                  ))
                    VisitCard(
                      store: widget.store,
                      visit: visit,
                      operator: true,
                    ),
                ],
                if (data['has_more'] == true)
                  TextButton(
                    onPressed: () => setState(() {
                      loaded.addAll(List<Json>.from(data['items']));
                      offset += 100;
                      load(more: true);
                    }),
                    child: const Text('Load more appointments'),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class AppointmentEditor extends StatefulWidget {
  const AppointmentEditor({
    super.key,
    required this.store,
    required this.business,
    this.visit,
    this.client,
  });
  final AppStore store;
  final Json business;
  final Json? visit, client;
  @override
  State<AppointmentEditor> createState() => _AppointmentEditorState();
}

class _AppointmentEditorState extends State<AppointmentEditor> {
  final name = TextEditingController();
  late DateTime day;
  String? service;
  Json? slot;
  Future<List<Json>>? slots;
  bool saved = false, confirming = false;
  @override
  void initState() {
    super.initState();
    final now = nzNow();
    day = DateTime(now.year, now.month, now.day);
    name.text = widget.client?['name'] ?? widget.visit?['customer_name'] ?? '';
    service = widget.visit?['service_id'];
    if (service != null) load();
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void load() {
    slot = null;
    slots = widget.store.backend!
        .rpc('available_slots', {
          'p_business': widget.business['id'],
          'p_service': service,
          'p_day': dayKey(day),
        })
        .then((value) => List<Json>.from(value as List));
  }

  Future<void> requestSave() async {
    if (confirming || widget.store.busy) return;
    final rescheduling = widget.visit != null;
    if (slot == null || (!rescheduling && name.text.trim().length < 2)) {
      await widget.store.run(() async {
        throw Exception('Enter a client name and choose an available time');
      });
      return;
    }
    setState(() => confirming = true);
    bool accepted = false;
    try {
      accepted = await confirm(
        context,
        rescheduling ? 'Move this appointment?' : 'Book this appointment?',
        '${name.text.trim()} · ${nzTime(slot!['starts_at'])}',
        store: widget.store,
        requireMfa:
            !rescheduling ||
            widget.visit!['customer_id'] != widget.store.backend?.userId,
        action: rescheduling ? 'Reschedule' : 'Book appointment',
      );
    } finally {
      if (mounted) setState(() => confirming = false);
    }
    if (accepted && mounted) await widget.store.run(save);
  }

  Future<void> save() async {
    final rescheduling = widget.visit != null;
    final revision = widget.store.sessionRevision,
        user = widget.store.backend?.userId;
    await widget.store.backend!.rpc(
      rescheduling ? 'reschedule_visit' : 'operator_book_appointment',
      rescheduling
          ? {
              'p_visit': widget.visit!['id'],
              'p_start': slot!['starts_at'],
              'p_resource': slot!['resource_id'],
            }
          : {
              'p_business': widget.business['id'],
              'p_service': service,
              'p_resource': slot!['resource_id'],
              'p_start': slot!['starts_at'],
              'p_name': name.text.trim(),
              'p_customer': widget.client?['customer_id'],
            },
    );
    if (!mounted || !widget.store.isCurrentSession(revision, user)) return;
    setState(() => saved = true);
    await widget.store.refreshVisits();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final services = List<Json>.from(widget.business['services'] as List);
      return PageBody(
        width: 660,
        children: [
          PageHeading(
            saved
                ? 'Appointment saved'
                : widget.visit == null
                ? 'Book for a client'
                : 'Choose a new time',
            saved
                ? 'Your calendar has been updated. No payment has been taken.'
                : 'Times are checked by the server again when you confirm. All times are New Zealand time.',
          ),
          if (saved)
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to calendar'),
            )
          else
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.visit == null) FormFieldBox(name, 'Client name'),
                  if (widget.visit == null)
                    DropdownButtonFormField<String>(
                      initialValue: service,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Service'),
                      items: [
                        for (final s in services.where(
                          (s) => s['active'] == true,
                        ))
                          DropdownMenuItem(
                            value: s['id'] as String,
                            child: Text(
                              '${s['name']} · ${money(s['price_cents'])}',
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        service = v;
                        load();
                      }),
                    ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(dayKey(day)),
                    onPressed: () async {
                      final now = nzNow();
                      final first = DateTime(now.year, now.month, now.day);
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: day,
                        firstDate: first,
                        lastDate: first.add(const Duration(days: 89)),
                      );
                      if (picked != null && mounted)
                        setState(() {
                          day = picked;
                          if (service != null) load();
                        });
                    },
                  ),
                  const SizedBox(height: 16),
                  if (slots != null)
                    AsyncPanel<List<Json>>(
                      future: slots!,
                      retry: () => setState(load),
                      builder: (items) => items.isEmpty
                          ? const Notice(
                              'No times available. Try another date.',
                            )
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final time in items)
                                  ChoiceChip(
                                    label: Text(
                                      '${nzTime(time['starts_at'])}\n${time['resource_name']}',
                                    ),
                                    selected:
                                        slot?['starts_at'] ==
                                            time['starts_at'] &&
                                        slot?['resource_id'] ==
                                            time['resource_id'],
                                    onSelected: widget.store.busy
                                        ? null
                                        : (_) => setState(() => slot = time),
                                  ),
                              ],
                            ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: widget.store.busy || confirming
                        ? null
                        : requestSave,
                    icon: widget.store.busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      widget.store.busy
                          ? 'Saving appointment…'
                          : widget.visit == null
                          ? 'Book appointment'
                          : 'Save new time',
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
