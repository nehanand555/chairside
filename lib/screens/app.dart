import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../data/auth_callback.dart';
import 'account.dart';
import 'feedback.dart';
import 'business.dart';
import 'common.dart';
import 'discover.dart';
import 'visits.dart';

class SpicySelfApp extends StatefulWidget {
  const SpicySelfApp({
    super.key,
    required this.store,
    this.startupError,
    this.authCallback,
    this.mapsEnabled = true,
  });
  final AppStore store;
  final String? startupError;
  final AuthCallbackResult? authCallback;
  final bool mapsEnabled;
  @override
  State<SpicySelfApp> createState() => _SpicySelfAppState();
}

class _SpicySelfAppState extends State<SpicySelfApp>
    with WidgetsBindingObserver {
  int index = 0;
  bool callbackConfirmed = false;
  Timer? _poll;
  bool _active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_active &&
          (widget.authCallback == null || callbackConfirmed) &&
          widget.store.signedIn &&
          !widget.store.busy)
        unawaited(widget.store.refreshVisits());
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
    title: 'spicyself',
    debugShowCheckedModeBanner: false,
    theme: spicyTheme(),
    home: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final s = widget.store;
        if (!s.configured)
          return Scaffold(
            appBar: AppBar(title: const SpicySelfBrand()),
            body: PageBody(
              children: [
                const PageHeading(
                  'Find your next look.',
                  'Discover local hair, nails, tattoos and beauty professionals.',
                ),
                Notice(
                  widget.startupError ?? 'spicyself is being connected to its live services. Please check back soon.',
                ),
                const Text(
                  'No personal information is collected on this screen.',
                ),
              ],
            ),
          );
        if (widget.authCallback != null && !callbackConfirmed) {
          final callback = widget.authCallback!;
          final matches =
              callback.succeeded && callback.userId == s.backend?.userId;
          return Scaffold(
            appBar: AppBar(title: const SpicySelfBrand()),
            body: PageBody(
              width: 520,
              children: [
                PageHeading(
                  matches
                      ? 'Confirm your account'
                      : 'This sign-in link did not finish',
                  matches
                      ? 'You’re signing in to spicyself with the account below.'
                      : 'We haven’t continued with an account already saved in this browser. Request a new link in the same browser where you’ll open it.',
                ),
                if (matches) ...[
                  Panel(child: Text(callback.email ?? 'Your verified account')),
                  ActionButton(s, 'Continue with this account', () async {
                    if (s.backend?.userId != callback.userId) return;
                    await s.refreshAccount();
                    if (mounted && s.backend?.userId == callback.userId) {
                      setState(() {
                        callbackConfirmed = true;
                        index = 3;
                      });
                    }
                  }),
                ],
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: s.busy
                      ? null
                      : () => s.run(() async {
                          await s.backend!.signOut();
                          await s.refreshAccount();
                          if (mounted && !s.signedIn) {
                            setState(() {
                              callbackConfirmed = true;
                              index = 3;
                            });
                          }
                        }),
                  child: Text(
                    matches ? 'Use a different account' : 'Back to sign in',
                  ),
                ),
                if (s.error != null)
                  Notice('Could not complete the request. Please try again.'),
              ],
            ),
          );
        }
        const destinations = <(String, IconData)>[
          ('Explore', Icons.explore_outlined),
          ('Map', Icons.map_outlined),
          ('My Bookings', Icons.calendar_month_outlined),
          ('Profile', Icons.person_outline),
          ('Feedback', Icons.chat_bubble_outline),
        ];
        final selected = index;
        final pages = <Widget>[
          DiscoverScreen(
            store: s,
            mapsEnabled: widget.mapsEnabled,
            mapMode: index == 1,
            onOpenMap: () => setState(() => index = 1),
          ),
          VisitsScreen(store: s),
          AccountScreen(key: ValueKey(s.backend!.userId), store: s),
          FeedbackScreen(
            key: ValueKey(('feedback', s.backend!.userId, s.sessionRevision)),
            store: s,
          ),
        ];
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 850;
            return Scaffold(
              appBar: AppBar(
                title: Tooltip(
                  message: 'Back to Explore',
                  child: InkWell(
                    key: const ValueKey('home-logo'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => index = 0),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: SpicySelfBrand(),
                    ),
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12, bottom: 8),
                      child: OutlinedButton.icon(
                        key: const ValueKey('business-entry'),
                        onPressed: () => openBusinessWorkspace(context, s),
                        icon: const Icon(Icons.storefront_outlined, size: 18),
                        label: const Text('For business'),
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton.icon(
                    onPressed: () => showLegal(context),
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: const Text('About'),
                  ),
                ],
              ),
              body: Column(
                children: [
                  if (s.signedIn)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            key: const ValueKey('account-greeting'),
                            onPressed: () => setState(() => index = 3),
                            child: Row(
                              children: [
                                const Icon(Icons.person_outline),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    s.displayName.isEmpty
                                        ? 'Complete your account'
                                        : 'Hi, ${s.displayName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  StoreFeedback(store: s),
                  Expanded(
                    child: Row(
                      children: [
                        if (wide)
                          NavigationRail(
                            selectedIndex: selected,
                            onDestinationSelected: (v) =>
                                setState(() => index = v),
                            labelType: NavigationRailLabelType.all,
                            destinations: destinations
                                .map(
                                  (d) => NavigationRailDestination(
                                    icon: Icon(d.$2),
                                    label: Text(d.$1),
                                  ),
                                )
                                .toList(),
                          ),
                        Expanded(
                          child: IndexedStack(
                            index: selected < 2 ? 0 : selected - 1,
                            children: pages,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: wide
                  ? null
                  : SafeArea(
                      top: false,
                      child: NavigationBar(
                        selectedIndex: selected,
                        onDestinationSelected: (v) => setState(() => index = v),
                        destinations: destinations
                            .map(
                              (d) => NavigationDestination(
                                icon: Icon(d.$2),
                                label: d.$1,
                              ),
                            )
                            .toList(),
                      ),
                    ),
            );
          },
        );
      },
    ),
  );
}

class StoreFeedback extends StatelessWidget {
  const StoreFeedback({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (store.busy) const LinearProgressIndicator(minHeight: 3),
      if (store.error != null)
        Material(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Row(
              children: [
                Expanded(child: Text(store.error!)),
                IconButton(
                  onPressed: store.clearError,
                  icon: const Icon(Icons.close),
                  tooltip: 'Dismiss error',
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class DetailScaffold extends StatelessWidget {
  const DetailScaffold({
    super.key,
    required this.store,
    required this.title,
    required this.child,
  });
  final AppStore store;
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          StoreFeedback(store: store),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

Future<void> openBusinessWorkspace(BuildContext context, AppStore store) async {
  // Recheck the server-side decision before choosing application vs dashboard.
  // Approval emails can arrive while the owner still has the app open.
  if (store.signedIn) await store.refreshAccount();
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DetailScaffold(
        store: store,
        title: 'spicyself for business',
        child: BusinessScreen(store: store),
      ),
    ),
  );
}

Future<void> openAccount(BuildContext context, AppStore store) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailScaffold(
          store: store,
          title: 'Your account',
          child: AccountScreen(store: store),
        ),
      ),
    );

Future<void> showLegal(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .8,
    child: PageBody(
      children: [
        const PageHeading(
          'About spicyself',
          'Hair professionals across Aotearoa New Zealand.',
        ),
        const Text(
          'spicyself connects customers with independent businesses. Public Google listings are directory results; those businesses have not necessarily joined spicyself. Booking and live queues are available only for approved spicyself members. Approval is a platform review and does not replace any required council permissions.',
        ),
        const SizedBox(height: 20),
        const Text(
          'Bookings & payments',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          'Prices are in NZD and shown before confirmation. Queue times are estimates and can change. You can cancel an upcoming visit in My Bookings. This release requests a full refund for prepaid visits cancelled before service or marked absent. Refund processing takes additional time. Businesses can also issue a full refund through spicyself. Your statutory rights continue to apply.',
        ),
        const SizedBox(height: 20),
        const Text('Privacy', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text(
          'You can browse without an account. You can sign in using Google or an email sign-in link. We never receive your Google password. We use your name for bookings. Location permission is optional; your device location is used for a nearby search and is not saved as your home address. Your business can see your booking name and service. Booking and queue updates are available in My Bookings. Optional SMS updates require a verified phone number, your consent and an enabled SMS service. Card details are handled by Stripe. Home studio addresses are shown only to confirmed upcoming customers and authorised operators. Public photos and listing details are visible to everyone.',
        ),
        const Text(
          'Data is processed by our hosting, maps, authentication, payment and SMS providers, which may process data outside New Zealand. Delete your account from Profile after visits and pending refunds are finished; minimal financial records may be retained. Contact support to request access or correction. Google Maps Platform terms and Google’s privacy policy apply to map services.',
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => openLink('https://policies.google.com/privacy'),
          child: const Text('Google privacy policy'),
        ),
        TextButton(
          onPressed: () => openLink('https://maps.google.com/help/terms_maps/'),
          child: const Text('Google Maps terms'),
        ),
        if (const String.fromEnvironment('SUPPORT_EMAIL').isNotEmpty)
          TextButton(
            onPressed: () => openLink(
              'mailto:${const String.fromEnvironment('SUPPORT_EMAIL')}',
            ),
            child: const Text('Contact spicyself support'),
          ),
        const SizedBox(height: 20),
      ],
    ),
  ),
);
