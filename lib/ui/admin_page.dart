import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/demo_store.dart';
import 'common.dart';

class AdminPage extends StatelessWidget {
  const AdminPage({required this.store, super.key});
  final DemoStore store;
  @override
  Widget build(BuildContext context) {
    final pending = store.providers.where((p) => p.application == ApplicationStatus.pending).toList();
    return ListView(padding: const EdgeInsets.all(20), children: [
      const SectionTitle('Look after your local community.', subtitle: 'Review sample providers and see platform activity.'),
      const Surface(child: Text('ADMIN PREVIEW · This screen is publicly selectable only in the demo. An approval here is not a real identity, qualification or premises verification.',
        style: TextStyle(height: 1.6, color: ink))),
      const SizedBox(height: 20),
      LayoutBuilder(builder: (context, constraints) {
        final count = constraints.maxWidth >= 680 ? 3 : 1;
        final width = (constraints.maxWidth - (count - 1) * 12) / count;
        final stats = [
          ('Listed providers', '${store.listed.length}', Icons.storefront_outlined),
          ('Active visits', '${store.visits.where((v) => v.active).length}', Icons.event_available_outlined),
          ('Awaiting review', '${pending.length}', Icons.fact_check_outlined),
        ];
        return Wrap(spacing: 12, runSpacing: 12, children: stats.map((s) => SizedBox(width: width, child: Surface(
          child: Row(children: [Icon(s.$3, color: green, size: 28), const SizedBox(width: 18),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.$2, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)), Text(s.$1),
            ])),
          ]),
        ))).toList());
      }),
      const SizedBox(height: 24),
      const SectionTitle('Provider applications'),
      if (pending.isEmpty) const EmptyMessage('All caught up', 'There are no sample applications waiting for review.', icon: Icons.task_alt),
      ...pending.map((p) => Padding(padding: const EdgeInsets.only(bottom: 16), child: Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Tag('Awaiting demo review', color: Color(0xFFF5E9CB)),
          const SizedBox(height: 14),
          Text(p.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('${p.suburb} · ${p.homeBased ? 'Home studio' : 'Barbershop'}'),
          const SizedBox(height: 12),
          const Text('Sample application only. Approving adds this fictional business to Discover. No documents have been checked.', style: TextStyle(height: 1.6, color: Colors.black54)),
          const SizedBox(height: 18),
          Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton.icon(key: Key('approve-${p.id}'), onPressed: () => store.review(p, true),
              icon: const Icon(Icons.check), label: const Text('Approve demo listing')),
            OutlinedButton(onPressed: () => store.review(p, false), child: const Text('Decline')),
          ]),
        ]),
      ))),
      const SizedBox(height: 24),
      const SectionTitle('Provider directory'),
      ...store.providers.map((p) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        leading: Icon(p.homeBased ? Icons.home_outlined : Icons.storefront_outlined, color: green),
        title: Text(p.name), subtitle: Text('${p.suburb} · ${p.application.name}'),
      )),
      const SizedBox(height: 20),
      const Text('Next milestone: real sign-in, provider ownership, private documents and an audit trail enforced by the backend.',
        style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.6)),
    ]);
  }
}
