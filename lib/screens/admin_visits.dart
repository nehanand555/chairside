import 'dart:async';

import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../data/store.dart';
import 'common.dart';
import 'visits.dart';

class AdminBusinessVisits extends StatefulWidget {
  const AdminBusinessVisits({
    super.key,
    required this.store,
    required this.business,
  });
  final AppStore store;
  final String business;
  @override
  State<AdminBusinessVisits> createState() => _AdminBusinessVisitsState();
}

class _AdminBusinessVisitsState extends State<AdminBusinessVisits> {
  Future<List<Json>>? data;
  String? dataUser;
  int request = 0;
  bool get permitted =>
      widget.store.signedIn && widget.store.isAdmin && widget.store.unlocked;
  Timer? debounce;
  int pages = 1;
  bool more = false;
  @override
  void initState() {
    super.initState();
    widget.store.addListener(changed);
  }

  Future<List<Json>> load() async {
    final user = widget.store.backend!.userId;
    final session = widget.store.sessionRevision;
    final current = ++request;
    final pageCount = pages;
    bool hasMore = false;
    final all = <Json>[];
    for (int page = 0; page < pageCount; page++) {
      if (!permitted || !widget.store.isCurrentSession(session, user))
        throw StateError('Admin access changed. Reopen the console.');
      final rows = List<Json>.from(
        await widget.store.backend!.rpc('my_visits', {
          'p_business': widget.business,
          'p_offset': page * 200,
        }) as List,
      );
      all.addAll(rows);
      hasMore = rows.length == 200;
      if (!hasMore) break;
    }
    if (!mounted ||
        !permitted ||
        !widget.store.isCurrentSession(session, user) ||
        current != request)
      throw StateError('Admin access changed. Reopen the console.');
    more = hasMore;
    return {for (final v in all) v['id']: v}.values.toList();
  }

  void changed() {
    if (!permitted || dataUser != widget.store.backend?.userId) {
      debounce?.cancel();
      request++;
      data = null;
      dataUser = null;
      pages = 1;
      more = false;
      return;
    }
    if (widget.store.busy || data == null) return;
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
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          if (!permitted)
            return const PageBody(
              children: [
                PageHeading(
                  'Restricted access',
                  'Visits and refunds require an authorised admin session and MFA.',
                ),
              ],
            );
          dataUser = widget.store.backend!.userId;
          data ??= load();
          return PageBody(
            children: [
              PageHeading(
                'Visits & refunds',
                'Only visits for this business are shown.',
                action: OutlinedButton.icon(
                  onPressed: () => setState(() => data = load()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ),
              AsyncPanel<List<Json>>(
                key: ValueKey((dataUser, widget.store.sessionRevision)),
                future: data!,
                retry: () => setState(() => data = load()),
                builder: (rows) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (rows.isEmpty)
                      const Notice('No visits for this business.'),
                    ...rows.map(
                      (v) => VisitCard(
                          store: widget.store, visit: v, operator: true),
                    ),
                    if (more)
                      OutlinedButton(
                        onPressed: () => setState(() {
                          pages++;
                          data = load();
                        }),
                        child: const Text('Load more visits'),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      );
}
