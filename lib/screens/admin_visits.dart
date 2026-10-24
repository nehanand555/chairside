import 'dart:async';
import 'package:flutter/material.dart';
import '../data/backend.dart';
import '../data/store.dart';
import 'common.dart';
import 'visits.dart';

class AdminBusinessVisits extends StatefulWidget {
  const AdminBusinessVisits(
      {super.key, required this.store, required this.business});
  final AppStore store;
  final String business;
  @override
  State<AdminBusinessVisits> createState() => _AdminBusinessVisitsState();
}

class _AdminBusinessVisitsState extends State<AdminBusinessVisits> {
  late Future<List<Json>> data;
  Timer? debounce;
  int pages = 1;
  bool more = false;
  @override
  void initState() {
    super.initState();
    data = load();
    widget.store.addListener(changed);
  }

  Future<List<Json>> load() async {
    final all = <Json>[];
    for (int page = 0; page < pages; page++) {
      final rows = List<Json>.from(await widget.store.backend!.rpc('my_visits',
          {'p_business': widget.business, 'p_offset': page * 200}) as List);
      all.addAll(rows);
      more = rows.length == 200;
      if (!more) break;
    }
    return {for (final v in all) v['id']: v}.values.toList();
  }

  void changed() {
    if (widget.store.busy) return;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => data = load());
    });
  }

  @override
  void dispose() {
    debounce?.cancel();
    widget.store.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageBody(children: [
        PageHeading(
            'Visits & refunds', 'Only visits for this business are shown.',
            action: OutlinedButton.icon(
                onPressed: () => setState(() => data = load()),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'))),
        AsyncPanel<List<Json>>(
            future: data,
            retry: () => setState(() => data = load()),
            builder: (rows) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (rows.isEmpty)
                        const Notice('No visits for this business.'),
                      ...rows.map((v) => VisitCard(
                          store: widget.store, visit: v, operator: true)),
                      if (more)
                        OutlinedButton(
                            onPressed: () => setState(() {
                                  pages++;
                                  data = load();
                                }),
                            child: const Text('Load more visits')),
                    ])),
      ]);
}
