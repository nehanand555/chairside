import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../data/store.dart';
import 'app.dart';
import 'common.dart';
import 'scheduling.dart';

class BusinessClients extends StatefulWidget {
  const BusinessClients({
    super.key,
    required this.store,
    required this.business,
  });
  final AppStore store;
  final Json business;
  @override
  State<BusinessClients> createState() => _BusinessClientsState();
}

class _BusinessClientsState extends State<BusinessClients> {
  final search = TextEditingController();
  late Future<Json> page;
  int offset = 0;
  final List<Json> previous = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void load({bool more = false}) {
    if (!more) {
      offset = 0;
      previous.clear();
    }
    page = widget.store.backend!
        .rpc('business_clients', {
          'p_business': widget.business['id'],
          'p_search': search.text.trim(),
          'p_offset': offset,
        })
        .then((value) => Json.from(value as Map));
  }

  Future<void> note(Json client) async {
    final controller = TextEditingController(
      text: client['note'] as String? ?? '',
    );
    final value = await showSessionDialog<String>(
      context,
      widget.store,
      requireMfa: true,
      builder: (context) => AlertDialog(
        title: Text('Notes · ${client['name']}'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 8,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Private business note',
              helperText: 'Avoid sensitive health or payment information.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save note'),
          ),
        ],
      ),
    );
    if (value != null)
      await widget.store.run(() async {
        await widget.store.backend!.rpc('save_client_note', {
          'p_business': widget.business['id'],
          'p_customer': client['customer_id'],
          'p_note': value,
        });
        if (mounted) setState(() => load());
      });
    // Dialog exit animation may still hold the controller; dispose after a frame.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionHeader(
        'Clients',
        subtitle: 'People who have booked with your business. Notes stay private to this workspace.',
      ),
      TextField(
        controller: search,
        maxLength: 100,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => setState(() => load()),
        decoration: InputDecoration(
          labelText: 'Find a client',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: 'Search clients',
            onPressed: () => setState(() => load()),
            icon: const Icon(Icons.arrow_forward),
          ),
        ),
      ),
      const SizedBox(height: 16),
      AsyncPanel<Json>(
        future: page,
        retry: () => setState(() => load()),
        builder: (data) {
          final clients = [
            ...previous,
            ...List<Json>.from(data['items'] as List),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (clients.isEmpty)
                const Notice(
                  'No matching clients yet. Clients appear after they book with your business.',
                ),
              for (final client in clients)
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        client['name'],
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '${client['visit_count']} visits · Latest booking ${nzTime(client['last_visit'])}',
                      ),
                      if ((client['note'] as String? ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(client['note']),
                        ),
                      ClientHistory(
                        store: widget.store,
                        business: widget.business['id'],
                        customer: client['customer_id'],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () => note(client),
                            icon: const Icon(Icons.edit_note),
                            label: const Text('Private notes'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => DetailScaffold(
                                  store: widget.store,
                                  title: 'Repeat booking',
                                  child: AppointmentEditor(
                                    store: widget.store,
                                    business: widget.business,
                                    client: client,
                                  ),
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.event_repeat),
                            label: const Text('Book again'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (data['has_more'] == true)
                TextButton(
                  onPressed: () => setState(() {
                    previous.addAll(List<Json>.from(data['items']));
                    offset += 50;
                    load(more: true);
                  }),
                  child: const Text('Load more clients'),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class ClientHistory extends StatefulWidget {
  const ClientHistory({
    super.key,
    required this.store,
    required this.business,
    required this.customer,
  });
  final AppStore store;
  final String business, customer;
  @override
  State<ClientHistory> createState() => _ClientHistoryState();
}

class _ClientHistoryState extends State<ClientHistory> {
  Future<List<Json>>? history;
  int offset = 0;
  void load() {
    history = widget.store.backend!
        .rpc('business_client_history', {
          'p_business': widget.business,
          'p_customer': widget.customer,
          'p_offset': offset,
        })
        .then((value) => List<Json>.from(value as List));
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Visit history'),
    onExpansionChanged: (expanded) {
      if (expanded && history == null) setState(load);
    },
    children: [
      if (history != null)
        AsyncPanel<List<Json>>(
          future: history!,
          retry: () => setState(load),
          builder: (items) => Column(
            children: [
              for (final item in items)
                ListTile(
                  title: Text(item['service_name']),
                  subtitle: Text(
                    '${nzTime(item['starts_at'])} · ${item['status']}',
                  ),
                  trailing: Text(money(item['price_cents'])),
                ),
              if (items.isEmpty) const Text('No visits on this page.'),
              Wrap(
                children: [
                  TextButton(
                    onPressed: offset == 0
                        ? null
                        : () => setState(() {
                            offset -= 25;
                            load();
                          }),
                    child: const Text('Previous visits'),
                  ),
                  TextButton(
                    onPressed: items.length < 25
                        ? null
                        : () => setState(() {
                            offset += 25;
                            load();
                          }),
                    child: const Text('More visits'),
                  ),
                ],
              ),
            ],
          ),
        ),
    ],
  );
}
