import 'package:flutter/material.dart';
import '../data/backend.dart';
import '../data/store.dart';
import 'account.dart';
import 'app.dart';
import 'common.dart';
import 'admin_visits.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Future<Json>? data;
  Future<Json>? health;
  Future<Json>? emailHealth;
  Future<List<dynamic>>? emailEvents;
  String filter = 'pending';
  String? loadedUser;
  int? loadedSession;
  void reload() {
    data = widget.store.backend!
        .rpc('admin_overview')
        .then((v) => Json.from(v as Map));
    emailEvents = widget.store.backend!
        .rpc('admin_email_events')
        .then((v) => List<dynamic>.from(v as List));
    emailHealth = widget.store.backend!
        .rpc('admin_email_overview')
        .then((v) => Json.from(v as Map));
    health = widget.store.backend!
        .rpc('admin_health')
        .then((v) => Json.from(v as Map));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.store, builder: (context, _) => buildConsole(context));

  Widget buildConsole(BuildContext context) {
    final s = widget.store;
    if (loadedUser != s.backend?.userId || loadedSession != s.sessionRevision) {
      loadedSession = s.sessionRevision;
      loadedUser = s.backend?.userId;
      data = null;
      health = null;
      emailHealth = null;
      emailEvents = null;
    }
    if (!s.isAdmin)
      return const PageBody(children: [
        PageHeading('Restricted access',
            'This console is available to authorised administrators only.'),
      ]);
    if (s.unlocked && data == null) reload();
    return OperatorGate(
        store: s,
        child: PageBody(children: [
          const PageHeading('Platform administration',
              'Review businesses, investigate reports and help customers.'),
          if (emailHealth != null)
            AsyncPanel<Json>(
                future: emailHealth!,
                builder: (h) => Notice(
                    'Email queue: ${h['pending']} pending • ${h['accepted']} accepted • ${h['delivered']} delivered • ${h['failed']} requiring review')),
          if (emailEvents != null)
            AsyncPanel<List<dynamic>>(
              future: emailEvents!,
              builder: (events) => Panel(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recent email notifications',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (events.isEmpty) const Text('No notification events yet.'),
                  for (final raw in events)
                    Builder(builder: (context) {
                      final event = Json.from(raw as Map);
                      final error = event['error'] as String?;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text("${event['business']} · ${event['event']}"),
                        subtitle: Text(
                            "State: ${event['state']} · Attempts: ${event['attempts']}${error == null ? '' : ' · ' + error}"),
                        trailing: error != null &&
                                error.startsWith('http_') &&
                                (event['state'] == 'failed' ||
                                    event['state'] == 'dead')
                            ? TextButton(
                                onPressed: s.busy
                                    ? null
                                    : () => s.run(() async {
                                          await s.backend!.rpc(
                                              'admin_retry_email',
                                              {'p_id': event['id']});
                                          if (mounted) setState(reload);
                                        }),
                                child: const Text('Retry'))
                            : null,
                      );
                    }),
                ],
              )),
            ),
          if (health != null)
            AsyncPanel<Json>(
                future: health!,
                builder: (h) => Notice(
                    'SMS needing review: ${h['failed_sms']} • Overdue texts: ${h['pending_sms']} • Pending refunds: ${h['pending_refunds']}')),
          if (data != null)
            AsyncPanel<Json>(
                future: data!,
                retry: () => setState(reload),
                builder: (overview) {
                  final businesses =
                          List<Json>.from(overview['businesses'] as List),
                      reports = List<Json>.from(overview['reports'] as List);
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final status in [
                            'pending',
                            'approved',
                            'rejected',
                            'suspended',
                            'all'
                          ])
                            ChoiceChip(
                                label: Text(status == 'all'
                                    ? 'All businesses'
                                    : '${status[0].toUpperCase()}${status.substring(1)}'),
                                selected: filter == status,
                                onSelected: (_) =>
                                    setState(() => filter = status)),
                          OutlinedButton.icon(
                              onPressed: () => setState(reload),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh'))
                        ]),
                        const SizedBox(height: 16),
                        ...businesses
                            .where(
                                (b) => filter == 'all' || b['status'] == filter)
                            .map((b) => Panel(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text('${b['name']} • ${b['status']}',
                                          style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold)),
                                      Text('${b['kind']} • ${b['suburb']}'),
                                      Text((b['location'] as Map)['address']
                                          as String),
                                      Text(
                                          'Owner phone: ${b['owner_phone'] ?? 'Not available'}'),
                                      Text(
                                          'Owner email: ${b['owner_email'] ?? 'Not available'}'),
                                      const SizedBox(height: 8),
                                      Text(
                                          'Registration number: ${b['registration_number'] ?? 'Not provided'}'),
                                      Text(
                                          'Contact person: ${b['contact_name'] ?? 'Not provided'}'),
                                      Text(
                                          'Contact email: ${b['contact_email'] ?? 'Not provided'}'),
                                      Text(
                                          'Contact phone: ${b['contact_phone'] ?? 'Not provided'}'),
                                      if (b['place_id'] != null)
                                        SelectableText(
                                            'Google claim: ${b['place_id']}'),
                                      const SizedBox(height: 12),
                                      Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            for (final status in [
                                              'approved',
                                              'rejected',
                                              'suspended'
                                            ])
                                              OutlinedButton(
                                                  onPressed: s.busy
                                                      ? null
                                                      : () => review(
                                                          context, b, status),
                                                  child:
                                                      Text(status == 'approved'
                                                          ? 'Approve'
                                                          : status == 'rejected'
                                                              ? 'Reject'
                                                              : 'Suspend')),
                                            TextButton(
                                                onPressed: () => Navigator.push(
                                                    context,
                                                    MaterialPageRoute<void>(
                                                        builder: (_) => DetailScaffold(
                                                            store: s,
                                                            title: b['name']
                                                                as String,
                                                            child: AdminBusinessVisits(
                                                                store: s,
                                                                business: b[
                                                                        'id']
                                                                    as String)))),
                                                child: const Text(
                                                    'Visits & refunds'))
                                          ])
                                    ]))),
                        if (businesses
                            .where(
                                (b) => filter == 'all' || b['status'] == filter)
                            .isEmpty)
                          Notice(filter == 'pending'
                              ? 'No applications waiting for review.'
                              : 'No businesses in this status.'),
                        const SizedBox(height: 20),
                        Text('Open reports (${reports.length})',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        ...reports.map((r) => Panel(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(r['message'] as String),
                                  Text(
                                      'Business: ${businesses.where((b) => b['id'] == r['business_id']).firstOrNull?['name'] ?? r['business_id']}'),
                                  Text(nzTime(r['created_at'])),
                                  const SizedBox(height: 12),
                                  ActionButton(s, 'Mark resolved', () async {
                                    await s.backend!.rpc('resolve_report',
                                        {'p_report': r['id']});
                                    if (mounted) setState(reload);
                                  }, icon: Icons.check)
                                ]))),
                        const Notice(
                            'Verify the registration number against the appropriate business register, confirm the contact and operating address, and review Google listing claims before approving. Only approved businesses can use business tools. Decisions are audited.'),
                      ]);
                })
        ]));
  }

  Future<void> review(
      BuildContext context, Json business, String status) async {
    final note = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showSessionDialog<String>(context, widget.store,
        requireAdmin: true,
        requireMfa: true,
        builder: (context) => AlertDialog(
              title: Text('$status: ${business['name']}'),
              content: Form(
                  key: form,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        'Record the evidence checked or the reason for this decision. The owner can see this note.'),
                    const SizedBox(height: 16),
                    FormFieldBox(note, 'Review note',
                        lines: 4,
                        validator: (v) => (v ?? '').trim().length < 10 ||
                                (v ?? '').length > 2000
                            ? 'Use 10–2000 characters to explain the decision'
                            : null),
                  ]))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () {
                      if (form.currentState!.validate())
                        Navigator.pop(context, note.text.trim());
                    },
                    child: const Text('Save decision'))
              ],
            ));
    note.dispose();
    if (result != null && mounted)
      await widget.store.run(() async {
        await widget.store.backend!.rpc('admin_review', {
          'p_business': business['id'],
          'p_status': status,
          'p_note': result
        });
        if (context.mounted) {
          setState(() {
            filter = status;
            reload();
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "${business['name']} ${status == 'approved' ? 'approved' : status == 'rejected' ? 'rejected' : 'suspended'} successfully. The owner will be notified by email when delivery completes."),
          ));
        }
      });
  }
}
