import 'package:flutter/material.dart';

import '../state/demo_store.dart';
import 'admin_page.dart';
import 'barber_page.dart';
import 'common.dart';
import 'customer_page.dart';

class ChairsideApp extends StatelessWidget {
  const ChairsideApp({required this.store, super.key});
  final DemoStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chairside · Your next good hair day',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: green, primary: green, surface: paper),
      scaffoldBackgroundColor: paper,
      fontFamily: 'sans-serif',
      appBarTheme: const AppBarTheme(backgroundColor: paper, foregroundColor: ink, elevation: 0),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      )),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDBE2D9))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDBE2D9))),
      ),
    ),
    home: _Shell(store: store),
  );
}

class _Shell extends StatefulWidget {
  const _Shell({required this.store});
  final DemoStore store;
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  String role = 'Customer';
  int tab = 0;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final wide = MediaQuery.sizeOf(context).width >= 850;
      final content = switch (role) {
        'Barber' => BarberPage(store: store),
        'Admin' => AdminPage(store: store),
        _ => CustomerPage(store: store, tab: tab, onBooked: () => setState(() => tab = 1)),
      };
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 76,
          title: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.content_cut, color: green, size: 23), SizedBox(width: 10),
            Text('chairside', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -1)),
          ]),
          actions: [
            DropdownButtonHideUnderline(child: DropdownButton<String>(
              key: const Key('role-switch'),
              value: role,
              items: ['Customer', 'Barber', 'Admin'].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (value) => setState(() { role = value!; tab = 0; }),
            )),
            const SizedBox(width: 16),
          ],
        ),
        body: Column(children: [
          Container(
            width: double.infinity,
            color: const Color(0xFFE5EDD9),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: const Text('INTERACTIVE DEMO · Fictional providers. Data resets on restart. No payments or texts are sent.',
              style: TextStyle(fontSize: 12, color: ink, height: 1.4)),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4), child: Row(children: [
            const Icon(Icons.schedule, size: 15, color: green), const SizedBox(width: 6),
            Expanded(child: Text('Demo clock: ${timeLabel(store.now)}', style: const TextStyle(fontSize: 12))),
            TextButton(onPressed: store.advanceTime, child: const Text('+15 min')),
          ])),
          Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (wide && role == 'Customer') NavigationRail(
              backgroundColor: paper,
              selectedIndex: tab,
              onDestinationSelected: (value) => setState(() => tab = value),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: Text('Discover')),
                NavigationRailDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: Text('My visits')),
              ],
            ),
            Expanded(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120), child: content,
            ))),
          ])),
        ]),
        bottomNavigationBar: !wide && role == 'Customer' ? NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (value) => setState(() => tab = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Discover'),
            NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: 'My visits'),
          ],
        ) : null,
      );
    },
  );
}
