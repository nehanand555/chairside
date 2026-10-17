import 'dart:async';
import 'package:flutter/material.dart';
import '../data/store.dart';
import 'account.dart';
import 'admin.dart';
import 'business.dart';
import 'common.dart';
import 'discover.dart';
import 'visits.dart';

class ChairsideApp extends StatefulWidget {
  const ChairsideApp(
      {super.key,
      required this.store,
      this.startupError,
      this.mapsEnabled = true});
  final AppStore store;
  final String? startupError;
  final bool mapsEnabled;
  @override
  State<ChairsideApp> createState() => _ChairsideAppState();
}

class _ChairsideAppState extends State<ChairsideApp>
    with WidgetsBindingObserver {
  int index = 0;
  Timer? _poll;
  bool _active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_active && widget.store.signedIn && !widget.store.busy) unawaited(widget.store.refreshVisits());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed)
      unawaited(widget.store.refreshAccount());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Chairside',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
                seedColor: ink, primary: ink, secondary: lime, surface: cream),
            scaffoldBackgroundColor: cream,
            appBarTheme:
                const AppBarTheme(backgroundColor: cream, foregroundColor: ink),
            filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 17))),
            cardTheme: const CardThemeData(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(20))))),
        home: ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) {
              final s = widget.store;
              if (!s.configured)
                return Scaffold(
                    appBar: AppBar(title: const Text('Chairside')),
                    body: PageBody(children: [
                      const PageHeading('Your next great haircut.',
                          'Nearby professionals. A time that works for you.'),
                      Notice(widget.startupError ??
                          'Chairside is being connected to its live services. Please check back soon.'),
                      const Text(
                          'No personal information is collected on this screen.')
                    ]));
              final destinations = <(String, IconData)>[
                ('Explore', Icons.map_outlined),
                ('My visits', Icons.event_outlined),
                ('Business', Icons.storefront_outlined),
                ('Account', Icons.person_outline),
                if (s.isAdmin) ('Admin', Icons.admin_panel_settings_outlined)
              ];
              final selected = index < destinations.length ? index : 0;
              final pages = <Widget>[
                DiscoverScreen(store: s, mapsEnabled: widget.mapsEnabled),
                VisitsScreen(store: s),
                BusinessScreen(
                    key: ValueKey('${s.businessId}-${s.unlocked}'), store: s),
                AccountScreen(key: ValueKey(s.backend!.userId), store: s),
                if (s.isAdmin) AdminScreen(key: ValueKey(s.unlocked), store: s)
              ];
              return LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth >= 850;
                return Scaffold(
                  appBar: AppBar(
                      title:
                          const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.content_cut, size: 24),
                        SizedBox(width: 10),
                        Flexible(
                            child: Text('chairside',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1)))
                      ]),
                      actions: [
                        TextButton.icon(
                            onPressed: () => showLegal(context),
                            icon: const Icon(Icons.info_outline, size: 18),
                            label: const Text('About'))
                      ]),
                  body: Column(children: [
                    StoreFeedback(store: s),
                    Expanded(
                        child: Row(children: [
                      if (wide)
                        NavigationRail(
                            selectedIndex: selected,
                            onDestinationSelected: (v) =>
                                setState(() => index = v),
                            labelType: NavigationRailLabelType.all,
                            destinations: destinations
                                .map((d) => NavigationRailDestination(
                                    icon: Icon(d.$2), label: Text(d.$1)))
                                .toList()),
                      Expanded(
                          child: IndexedStack(index: selected, children: pages))
                    ]))
                  ]),
                  bottomNavigationBar: wide
                      ? null
                      : NavigationBar(
                          selectedIndex: selected,
                          onDestinationSelected: (v) =>
                              setState(() => index = v),
                          destinations: destinations
                              .map((d) => NavigationDestination(
                                  icon: Icon(d.$2), label: d.$1))
                              .toList()),
                );
              });
            }),
      );
}

class StoreFeedback extends StatelessWidget {
  const StoreFeedback({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        if (store.busy) const LinearProgressIndicator(minHeight: 3),
        if (store.error != null)
          Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                  child: Row(children: [
                    Expanded(child: Text(store.error!)),
                    IconButton(
                        onPressed: store.clearError,
                        icon: const Icon(Icons.close),
                        tooltip: 'Dismiss error')
                  ])))
      ]);
}

class DetailScaffold extends StatelessWidget {
  const DetailScaffold(
      {super.key,
      required this.store,
      required this.title,
      required this.child});
  final AppStore store;
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
          appBar: AppBar(
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
          body: Column(children: [
            StoreFeedback(store: store),
            Expanded(child: child)
          ])));
}

Future<void> openAccount(BuildContext context, AppStore store) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DetailScaffold(
            store: store,
            title: 'Your account',
            child: AccountScreen(store: store))));

Future<void> showLegal(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: PageBody(children: [
          const PageHeading('About Chairside',
              'Hair professionals across Aotearoa New Zealand.'),
          const Text(
              'Chairside connects customers with independent businesses. Public Google listings are directory results; those businesses have not necessarily joined Chairside. Booking and live queues are available only for approved Chairside members. Approval is a platform review and does not replace any required council permissions.'),
          const SizedBox(height: 20),
          const Text('Bookings & payments',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Text(
              'Prices are in NZD and shown before confirmation. Queue times are estimates and can change. You can cancel an upcoming visit in My visits. This release requests a full refund for prepaid visits cancelled before service or marked absent. Refund processing takes additional time. Businesses can also issue a full refund through Chairside. Your statutory rights continue to apply.'),
          const SizedBox(height: 20),
          const Text('Privacy', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text(
              'You can browse without an account. We use your Google account to sign you in and your name for bookings. We never receive your Google password. Location permission is optional; your device location is used for a nearby search and is not saved as your home address. Your business can see your booking name and service. Booking and queue updates are available in My visits. Optional SMS updates require a verified phone number, your consent and an enabled SMS service. Card details are handled by Stripe. Home studio addresses are shown only to confirmed upcoming customers and authorised operators. Public photos and listing details are visible to everyone.'),
          const Text(
              'Data is processed by our hosting, maps, authentication, payment and SMS providers, which may process data outside New Zealand. Delete your account from Account after visits and pending refunds are finished; minimal financial records may be retained. Contact support to request access or correction. Google Maps Platform terms and Google’s privacy policy apply to map services.'),
          const SizedBox(height: 12),
          TextButton(
              onPressed: () => openLink('https://policies.google.com/privacy'),
              child: const Text('Google privacy policy')),
          TextButton(
              onPressed: () =>
                  openLink('https://maps.google.com/help/terms_maps/'),
              child: const Text('Google Maps terms')),
          if (const String.fromEnvironment('SUPPORT_EMAIL').isNotEmpty)
            TextButton(
                onPressed: () => openLink(
                    'mailto:${const String.fromEnvironment('SUPPORT_EMAIL')}'),
                child: const Text('Contact Chairside support')),
          const SizedBox(height: 20),
        ])));
