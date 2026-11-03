import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../data/store.dart';
import 'account.dart';
import 'app.dart';
import 'common.dart';
import 'workspace.dart';
import 'admin_visits.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Future<Json>? data;
  Future<Json>? insights;
  final search = TextEditingController();
  int section = 0, offset = 0;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<List<dynamic>>? feedback;
  Future<Json>? health;
  Future<Json>? emailHealth;
  Future<List<dynamic>>? emailEvents;
  String filter = 'pending';
  String? loadedUser;
  int? loadedSession;
  void reload() {
    insights = widget.store.backend!
        .rpc('admin_workspace_insights')
        .then((v) => Json.from(v as Map));
    feedback = widget.store.backend!
        .rpc('admin_feedback')
        .then((v) => List<dynamic>.from(v as List));
    data = widget.store.backend!
        .rpc('admin_business_page', {
          'p_status': filter,
          'p_search': search.text.trim(),
          'p_offset': offset,
        })
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
    listenable: widget.store,
    builder: (context, _) => buildConsole(context),
  );

  Widget buildConsole(BuildContext context) {
    final s = widget.store;
    if (loadedUser != s.backend?.userId || loadedSession != s.sessionRevision) {
      loadedSession = s.sessionRevision;
      loadedUser = s.backend?.userId;
      data = null;
      insights = null;
      feedback = null;
      health = null;
      emailHealth = null;
      emailEvents = null;
    }
    if (!s.isAdmin)
      return const PageBody(
        children: [
          PageHeading(
            'Restricted access',
            'This console is available to authorised administrators only.',
          ),
        ],
      );
    if (s.unlocked && data == null) reload();
    return OperatorGate(
      store: s,
      child: PageBody(
        children: [
          WorkspaceNavigation(
            selected: section,
            onSelected: (value) => setState(() {
              section = value;
              offset = 0;
              filter = value == 2 ? 'all' : 'pending';
              reload();
            }),
            destinations: const [
              WorkspaceDestination('Overview', Icons.dashboard_outlined),
              WorkspaceDestination('Applications', Icons.fact_check_outlined),
              WorkspaceDestination('Businesses', Icons.storefront_outlined),
              WorkspaceDestination('Billing history', Icons.receipt_long_outlined),
              WorkspaceDestination('Notifications', Icons.mail_outline),
              WorkspaceDestination('Support', Icons.support_agent),
              WorkspaceDestination('Security', Icons.shield_outlined),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageHeading(
                  'Platform administration',
                  'Review businesses, investigate reports and help customers.',
                ),
                if (section == 4 && emailHealth != null)
                  AsyncPanel<Json>(
                    future: emailHealth!,
                    builder: (h) => Notice(
                      'Email queue: ${h['pending']} pending • ${h['accepted']} accepted • ${h['delivered']} delivered • ${h['failed']} requiring review',
                    ),
                  ),
                if (section == 4 && emailEvents != null)
                  AsyncPanel<List<dynamic>>(
                    future: emailEvents!,
                    builder: (events) => Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recent email notifications',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          if (events.isEmpty)
                            const Text('No notification events yet.'),
                          WorkspaceTable(
                            columns: const ['Business', 'Event', 'Status', 'Attempts', 'Action'],
                            rows: [
                              for (final raw in events)
                                [
                                  Builder(builder: (_) {
                                    final e = Json.from(raw as Map);
                                    return Text('${e['business'] ?? '—'}', maxLines: 2, overflow: TextOverflow.ellipsis);
                                  }),
                                  Builder(builder: (_) {
                                    final e = Json.from(raw as Map);
                                    return Text('${e['event'] ?? '—'}', maxLines: 2, overflow: TextOverflow.ellipsis);
                                  }),
                                  Builder(builder: (_) {
                                    final e = Json.from(raw as Map);
                                    final error = e['error'] as String?;
                                    return Tooltip(
                                      message: error ?? 'No error reported',
                                      child: Text('${e['state'] ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                    );
                                  }),
                                  Builder(builder: (_) {
                                    final e = Json.from(raw as Map);
                                    return Text('${e['attempts'] ?? 0}');
                                  }),
                                  Builder(builder: (_) {
                                    final e = Json.from(raw as Map);
                                    final error = e['error'] as String?;
                                    final retryable = error != null && error.startsWith('http_') &&
                                        (e['state'] == 'failed' || e['state'] == 'dead');
                                    return retryable
                                        ? TextButton(
                                            onPressed: s.busy ? null : () => s.run(() async {
                                              await s.backend!.rpc('admin_retry_email', {'p_id': e['id']});
                                              if (mounted) setState(reload);
                                            }),
                                            child: const Text('Retry'),
                                          )
                                        : const Text('—');
                                  }),
                                ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if ((section == 0 || section == 4) && health != null)
                  AsyncPanel<Json>(
                    future: health!,
                    builder: (h) => Notice(
                      'SMS needing review: ${h['failed_sms']} • Overdue texts: ${h['pending_sms']} • Pending refunds: ${h['pending_refunds']}',
                    ),
                  ),
                if (insights != null && [0, 3, 6].contains(section))
                  AsyncPanel<Json>(
                    future: insights!,
                    retry: () => setState(reload),
                    builder: (summary) {
                      final counts = Json.from(
                        summary['business_counts'] as Map,
                      );
                      final memberships = List<Json>.from(
                        summary['memberships'] as List,
                      );
                      final events = List<Json>.from(summary['audit'] as List);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (section == 0) ...[
                            const SectionHeader(
                              'Platform overview',
                              subtitle: 'Business approvals, platform activity and operational health.',
                            ),
                            Wrap(
                              spacing: 12,
                              children: [
                                WorkspaceMetric(
                                  label: 'Awaiting review',
                                  value: '${counts['pending'] ?? 0}',
                                  detail: 'Submitted business applications',
                                  icon: Icons.fact_check_outlined,
                                ),
                                WorkspaceMetric(
                                  label: 'Approved businesses',
                                  value: '${counts['approved'] ?? 0}',
                                  detail: 'Approved businesses with free management access',
                                  icon: Icons.verified_outlined,
                                ),
                                WorkspaceMetric(
                                  label: 'Suspended businesses',
                                  value: '${counts['suspended'] ?? 0}',
                                  detail: 'Listings paused by an administrator',
                                  icon: Icons.pause_circle_outline,
                                ),
                              ],
                            ),
                            FilledButton(
                              onPressed: () => setState(() {
                                section = 1;
                                filter = 'pending';
                                offset = 0;
                                reload();
                              }),
                              child: const Text('Review applications'),
                            ),
                          ],
                          if (section == 3) ...[
                            const SectionHeader(
                              'Legacy subscription records',
                              subtitle: 'Historical subscription records only. New businesses use free access with 6% commission on completed bookings.',
                            ),
                            if (memberships.isEmpty)
                              const Notice(
                                'No subscription records yet. No membership revenue is assumed.',
                              ),
                            WorkspaceTable(
                              columns: const [
                                'Business',
                                'Status',
                                'Current period ends',
                                'Billing',
                              ],
                              rows: [
                                for (final member in memberships)
                                  [
                                    Text(member['name']),
                                    Text(member['status']),
                                    Text(
                                      member['current_period_end'] == null
                                          ? 'Not recorded'
                                          : nzTime(
                                              member['current_period_end'],
                                            ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (member['cancel_at_period_end'] ==
                                            true)
                                          const Text('Cancels at period end'),
                                        if (member['stripe_subscription_id']
                                                is String &&
                                            RegExp(
                                              r'^sub_[A-Za-z0-9]+$',
                                            ).hasMatch(
                                              member['stripe_subscription_id'],
                                            )) ...[
                                          SelectableText(
                                            member['stripe_subscription_id'],
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                          TextButton(
                                            onPressed: () => openLink(
                                              'https://dashboard.stripe.com/subscriptions/${member['stripe_subscription_id']}',
                                            ),
                                            child: const Text('View in Stripe'),
                                          ),
                                        ] else
                                          const Text(
                                            'No subscription identifier',
                                          ),
                                      ],
                                    ),
                                  ],
                              ],
                            ),
                          ],
                          if (section == 6) ...[
                            const SectionHeader(
                              'Security & activity',
                              subtitle: 'Admin access is verified by the backend and requires MFA. Latest 50 recorded actions.',
                            ),
                            if (events.isEmpty)
                              const Notice('No audit records available.'),
                            WorkspaceTable(
                              columns: const ['Action', 'Date', 'Actor'],
                              rows: [
                                for (final event in events)
                                  [
                                    Text('${event['action'] ?? '—'}'.replaceAll('_', ' ')),
                                    Text(nzTime(event['created_at'])),
                                    SelectableText('${event['actor_id'] ?? 'system'}'),
                                  ],
                              ],
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                if (data != null && [1, 2, 5].contains(section))
                  AsyncPanel<Json>(
                    future: data!,
                    retry: () => setState(reload),
                    builder: (overview) {
                      final businesses = List<Json>.from(
                            overview['businesses'] as List,
                          ),
                          reports = List<Json>.from(
                            overview['reports'] as List,
                          );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (section == 1 || section == 2) ...[
                            TextField(
                              controller: search,
                              maxLength: 100,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => setState(() {
                                offset = 0;
                                reload();
                              }),
                              decoration: InputDecoration(
                                labelText: 'Search businesses',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: IconButton(
                                  tooltip: 'Search businesses',
                                  onPressed: () => setState(() {
                                    offset = 0;
                                    reload();
                                  }),
                                  icon: const Icon(Icons.arrow_forward),
                                ),
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final status in [
                                  'pending',
                                  'approved',
                                  'rejected',
                                  'suspended',
                                  'all',
                                ])
                                  ChoiceChip(
                                    label: Text(
                                      status == 'all'
                                          ? 'All businesses'
                                          : '${status[0].toUpperCase()}${status.substring(1)}',
                                    ),
                                    selected: filter == status,
                                    onSelected: (_) => setState(() {
                                      filter = status;
                                      offset = 0;
                                      reload();
                                    }),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: () => setState(reload),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Refresh'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ...businesses
                                .where(
                                  (b) =>
                                      filter == 'all' || b['status'] == filter,
                                )
                                .map(
                                  (b) => Panel(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${b['name']} • ${b['status']}',
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text('${b['kind']} • ${b['suburb']}'),
                                        Text(
                                          (b['location'] as Map)['address']
                                              as String,
                                        ),
                                        Text(
                                          'Owner phone: ${b['owner_phone'] ?? 'Not available'}',
                                        ),
                                        Text(
                                          'Owner email: ${b['owner_email'] ?? 'Not available'}',
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Registration number: ${b['registration_number'] ?? 'Not provided'}',
                                        ),
                                        Text(
                                          'Contact person: ${b['contact_name'] ?? 'Not provided'}',
                                        ),
                                        Text(
                                          'Contact email: ${b['contact_email'] ?? 'Not provided'}',
                                        ),
                                        Text(
                                          'Contact phone: ${b['contact_phone'] ?? 'Not provided'}',
                                        ),
                                        if (b['place_id'] != null)
                                          SelectableText(
                                            'Google claim: ${b['place_id']}',
                                          ),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            for (final status in [
                                              'approved',
                                              'rejected',
                                              'suspended',
                                            ])
                                              OutlinedButton(
                                                onPressed: s.busy
                                                    ? null
                                                    : () => review(
                                                        context,
                                                        b,
                                                        status,
                                                      ),
                                                child: Text(
                                                  status == 'approved'
                                                      ? 'Approve'
                                                      : status == 'rejected'
                                                      ? 'Reject'
                                                      : 'Suspend',
                                                ),
                                              ),
                                            TextButton(
                                              onPressed: () => Navigator.push(
                                                context,
                                                MaterialPageRoute<void>(
                                                  builder: (_) =>
                                                      DetailScaffold(
                                                        store: s,
                                                        title:
                                                            b['name'] as String,
                                                        child:
                                                            AdminBusinessVisits(
                                                              store: s,
                                                              business:
                                                                  b['id']
                                                                      as String,
                                                            ),
                                                      ),
                                                ),
                                              ),
                                              child: const Text(
                                                'Visits & refunds',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            if (businesses
                                .where(
                                  (b) =>
                                      filter == 'all' || b['status'] == filter,
                                )
                                .isEmpty)
                              Notice(
                                filter == 'pending'
                                    ? 'No applications waiting for review.'
                                    : 'No businesses in this status.',
                              ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: offset == 0
                                      ? null
                                      : () => setState(() {
                                          offset -= 50;
                                          reload();
                                        }),
                                  child: const Text('Previous page'),
                                ),
                                Text('Page ${offset ~/ 50 + 1}'),
                                TextButton(
                                  onPressed: overview['has_more'] == true
                                      ? () => setState(() {
                                          offset += 50;
                                          reload();
                                        })
                                      : null,
                                  child: const Text('Next page'),
                                ),
                              ],
                            ),
                          ],
                          if (section == 5) ...[
                            Text(
                              'User feedback',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            AsyncPanel<List<dynamic>>(
                              future: feedback!,
                              retry: () => setState(reload),
                              builder: (items) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (items.isEmpty)
                                    const Text(
                                      'No new feedback. You’re all caught up.',
                                    ),
                                  ...items.map(
                                    (item) => Panel(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(item['message'] as String),
                                          const SizedBox(height: 8),
                                          Text(nzTime(item['created_at'])),
                                          TextButton(
                                            onPressed: s.busy
                                                ? null
                                                : () => s.run(() async {
                                                    await s.backend!.rpc(
                                                      'resolve_feedback',
                                                      {
                                                        'p_feedback':
                                                            item['id'],
                                                      },
                                                    );
                                                    if (mounted)
                                                      setState(reload);
                                                  }),
                                            child: const Text('Mark as read'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Open reports (${reports.length})',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            ...reports.map(
                              (r) => Panel(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r['message'] as String),
                                    Text(
                                      'Business: ${businesses.where((b) => b['id'] == r['business_id']).firstOrNull?['name'] ?? r['business_name'] ?? r['business_id']}',
                                    ),
                                    Text(nzTime(r['created_at'])),
                                    const SizedBox(height: 12),
                                    ActionButton(s, 'Mark resolved', () async {
                                      await s.backend!.rpc('resolve_report', {
                                        'p_report': r['id'],
                                      });
                                      if (mounted) setState(reload);
                                    }, icon: Icons.check),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (section == 1 || section == 2)
                            const Notice(
                              'Verify the registration number against the appropriate business register, confirm the contact and operating address, and review Google listing claims before approving. Only approved businesses can use business tools. Decisions are audited.',
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> review(
    BuildContext context,
    Json business,
    String status,
  ) async {
    final note = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showSessionDialog<String>(
      context,
      widget.store,
      requireAdmin: true,
      requireMfa: true,
      builder: (context) => AlertDialog(
        title: Text('$status: ${business['name']}'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Record the evidence checked or the reason for this decision. The owner can see this note.',
                ),
                const SizedBox(height: 16),
                FormFieldBox(
                  note,
                  'Review note',
                  lines: 4,
                  validator: (v) =>
                      (v ?? '').trim().length < 10 || (v ?? '').length > 2000
                      ? 'Use 10–2000 characters to explain the decision'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate())
                Navigator.pop(context, note.text.trim());
            },
            child: const Text('Save decision'),
          ),
        ],
      ),
    );
    note.dispose();
    if (result != null && mounted)
      await widget.store.run(() async {
        await widget.store.backend!.rpc('admin_review', {
          'p_business': business['id'],
          'p_status': status,
          'p_note': result,
        });
        if (context.mounted) {
          setState(() {
            filter = status;
            reload();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "${business['name']} ${status == 'approved'
                    ? 'approved'
                    : status == 'rejected'
                    ? 'rejected'
                    : 'suspended'} successfully. The owner will be notified by email when delivery completes.",
              ),
            ),
          );
        }
      });
  }
}
