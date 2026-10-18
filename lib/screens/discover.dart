import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../data/backend.dart';
import '../data/store.dart';
import 'app.dart';
import 'booking.dart';
import 'common.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen(
      {super.key, required this.store, this.mapsEnabled = true});
  final AppStore store;
  final bool mapsEnabled;
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final search = TextEditingController();
  LatLng center = const LatLng(-36.8485, 174.7633);
  GoogleMapController? controller;
  List<Json> businesses = [], places = [];
  String? error, warning;
  bool loading = true, onlyFavorites = false;
  int request = 0;
  bool textSearch = false;
  bool get mapAvailable =>
      widget.mapsEnabled &&
      (!kIsWeb ||
          const String.fromEnvironment('GOOGLE_MAPS_WEB_KEY').isNotEmpty);
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    request++;
    search.dispose();
    controller?.dispose();
    super.dispose();
  }

  Future<void> load({bool? text}) async {
    if (text != null) textSearch = text;
    final query = textSearch ? search.text : '';
    final id = ++request;
    setState(() {
      loading = true;
      error = null;
      warning = null;
      businesses = [];
      places = [];
    });
    try {
      final data = await widget.store.backend!.invoke('discover', {
        'lat': center.latitude,
        'lng': center.longitude,
        'query': query,
        'include_public': true
      });
      if (!mounted || request != id) return;
      final c = data['center'] as Map;
      setState(() {
        center =
            LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble());
        businesses = List<Json>.from(data['businesses'] as List);
        places = List<Json>.from(data['places'] as List);
        warning = data['warning'] as String?;
      });
      await controller?.animateCamera(CameraUpdate.newLatLngZoom(center, 12));
    } catch (e) {
      if (mounted && request == id) setState(() => error = friendlyError(e));
    } finally {
      if (mounted && request == id) setState(() => loading = false);
    }
  }

  Future<void> locate() async {
    await widget.store.run(() async {
      if (!await Geolocator.isLocationServiceEnabled())
        throw Exception('Turn on location services, or search by suburb.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        throw Exception(
            'Location access is off. You can still search by suburb or move the map.');
      final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 15)));
      if (position.latitude < -48 ||
          position.latitude > -33 ||
          position.longitude < 165 ||
          position.longitude > 180)
        throw Exception(
            'SpicySelf currently serves New Zealand. Search for a New Zealand suburb.');
      center = LatLng(position.latitude, position.longitude);
      search.clear();
      await load(text: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final members = onlyFavorites
        ? businesses.where((b) => s.favorites.contains(b['id'])).toList()
        : businesses;
    return PageBody(children: [
      const PageHeading('Find your next look.',
          'Find barbers and salons near you. More services coming soon.'),
      Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
                width: 290,
                child: TextField(
                    controller: search,
                    onSubmitted: (_) => load(text: true),
                    decoration: const InputDecoration(
                        hintText: 'Search suburb, town or postcode',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder()))),
            FilledButton(
                onPressed: loading ? null : () => load(text: true),
                child: const Text('Search')),
            OutlinedButton.icon(
                onPressed: loading ? null : locate,
                icon: const Icon(Icons.my_location),
                label: const Text('Near me')),
            FilterChip(
                label: const Text('Favourites'),
                selected: onlyFavorites,
                onSelected: (v) {
                  if (!s.signedIn) {
                    openAccount(context, s);
                  } else {
                    setState(() => onlyFavorites = v);
                  }
                })
          ]),
      const SizedBox(height: 18),
      if (loading) const LinearProgressIndicator(),
      if (error != null)
        Notice(error!,
            action: TextButton(
                onPressed: () => load(), child: const Text('Try again'))),
      if (mapAvailable)
        ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
                height: MediaQuery.sizeOf(context).width < 600 ? 320 : 410,
                child: GoogleMap(
                  initialCameraPosition:
                      CameraPosition(target: center, zoom: 12),
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  onMapCreated: (c) => controller = c,
                  onCameraMove: (position) => center = position.target,
                  markers: {
                    for (final b in members)
                      Marker(
                          markerId: MarkerId('member-${b['id']}'),
                          position: LatLng((b['lat'] as num).toDouble(),
                              (b['lng'] as num).toDouble()),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueGreen),
                          infoWindow: InfoWindow(
                              title: b['name'] as String,
                              snippet: b['kind'] == 'home'
                                  ? 'SpicySelf • Approximate location'
                                  : 'SpicySelf member',
                              onTap: () =>
                                  openBusiness(context, s, b['id'] as String))),
                    if (!onlyFavorites)
                      for (final p in places)
                        Marker(
                            markerId: MarkerId(p['place_id'] as String),
                            position: LatLng((p['lat'] as num).toDouble(),
                                (p['lng'] as num).toDouble()),
                            infoWindow: InfoWindow(
                                title: p['name'] as String,
                                snippet: 'Public Google listing',
                                onTap: () => showPublicListing(context, s, p)))
                  },
                ))),
      const SizedBox(height: 8),
      if (mapAvailable)
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                onPressed: loading ? null : () => load(text: false),
                icon: const Icon(Icons.refresh),
                label: const Text('Search this map area'))),
      if (!mapAvailable)
        const Notice(
            'Map view is unavailable. You can browse businesses in the list below.'),
      if (warning != null)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(warning!, style: const TextStyle(fontSize: 12))),
      const SizedBox(height: 16),
      if (!onlyFavorites && places.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text('Nearby barbers and salons',
            style: Theme.of(context).textTheme.titleLarge),
        const Text(
            'Discover local businesses and visit their websites to book directly. External bookings are managed by the business.'),
        const SizedBox(height: 12),
        ...places.map((p) => Panel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(p['name'] as String,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(p['address'] as String),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if ((p['website_url'] as String? ?? '').startsWith('https://') ||
                        (p['website_url'] as String? ?? '').startsWith('http://'))
                      FilledButton.icon(
                          onPressed: () => openLink(p['website_url'] as String),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Website / book')),
                    OutlinedButton(
                        onPressed: () => showPublicListing(context, s, p),
                        child: const Text('View details'))
                  ])
                ]))),
        const GoogleAttribution(),
        for (final p in places)
          for (final a in (p['attributions'] as List? ?? []))
            if ((a['provider'] ?? '').toString().isNotEmpty)
              TextButton(
                  onPressed: () => openLink(a['providerUri'] as String),
                  child: Text(a['provider'] as String))
      ],
      const SizedBox(height: 16),
      Text('Book with SpicySelf',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text(
          'Approved members • live availability • no crowded waiting room'),
      const SizedBox(height: 16),
      if (members.isEmpty && !loading)
        Notice(onlyFavorites
            ? 'No saved businesses in this area. Try another area or turn off Favourites.'
            : 'No SpicySelf members in this area yet. Your local hair professional can register from the Business tab.'),
      ...members.map((b) => BusinessCard(
          business: b,
          favorite: s.favorites.contains(b['id']),
          onOpen: () => openBusiness(context, s, b['id'] as String),
          onFavorite: () {
            if (!s.signedIn) {
              openAccount(context, s);
            } else {
              s.run(() => s.favorite(b['id'] as String));
            }
          })),
      const SizedBox(height: 24),
      const Text(
          'Run a shop or home studio? Join from the Business tab — you don’t need to be on Google Maps.'),
    ]);
  }
}

class BusinessCard extends StatelessWidget {
  const BusinessCard(
      {super.key,
      required this.business,
      required this.favorite,
      required this.onOpen,
      required this.onFavorite});
  final Json business;
  final bool favorite;
  final VoidCallback onOpen, onFavorite;
  @override
  Widget build(BuildContext context) => Panel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: lime, borderRadius: BorderRadius.circular(14)),
              child: Icon(
                  business['kind'] == 'home'
                      ? Icons.home_outlined
                      : Icons.content_cut,
                  color: ink)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(business['name'] as String,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.bold)),
                Text(
                    '${business['suburb']} • ${(business['distance_km'] as num? ?? 0).toStringAsFixed(1)} km')
              ])),
          IconButton(
              onPressed: onFavorite,
              icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
              tooltip: favorite ? 'Remove favourite' : 'Save favourite')
        ]),
        const SizedBox(height: 12),
        Text(business['kind'] == 'home'
            ? 'Home studio • appointments • approximate map pin'
            : business['queue_open'] == true
                ? 'Appointments + live queue'
                : 'Appointments • queue paused'),
        const SizedBox(height: 12),
        FilledButton(
            key: ValueKey('view-${business['id']}'),
            onPressed: onOpen,
            child: const Text('Services & availability'))
      ]));
}

Future<void> showPublicListing(
        BuildContext context, AppStore store, Json place) =>
    showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SizedBox(
            height: 400,
            child: PageBody(children: [
              PageHeading(
                  place['name'] as String, 'Public listing from Google Maps'),
              Text(place['address'] as String),
              const SizedBox(height: 16),
              const Text(
                  'This business has not joined SpicySelf. We do not have verified booking availability, prices or queue times.'),
              const SizedBox(height: 16),
              if ((place['website_url'] as String? ?? '').startsWith('https://') ||
                  (place['website_url'] as String? ?? '').startsWith('http://')) ...[
                FilledButton.icon(
                    onPressed: () => openLink(place['website_url'] as String),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Website / book externally')),
                const SizedBox(height: 8),
                const Text('You will leave SpicySelf. Check the business website for its own booking system.'),
                const SizedBox(height: 12),
              ],
              OutlinedButton(
                  onPressed: () => openLink(place['maps_url'] as String),
                  child: const Text('View on Google Maps')),
              const SizedBox(height: 12),
              const Text(
                  'Own this business? In the Business tab, include this Google Place ID when applying. Ownership is reviewed before booking is enabled.'),
              SelectableText(place['place_id'] as String),
              const GoogleAttribution(),
              for (final a in (place['attributions'] as List? ?? []))
                if ((a['provider'] ?? '').toString().isNotEmpty)
                  TextButton(onPressed: () => openLink(a['providerUri'] as String), child: Text(a['provider'] as String)),
            ])));

/// Compact source attribution for Google result cards and listing sheets.
class GoogleAttribution extends StatelessWidget {
  const GoogleAttribution({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(10, 10, 10, 5),
    child: Text('Google Maps', maxLines: 1,
      style: TextStyle(fontFamily: 'Roboto', fontSize: 14, fontStyle: FontStyle.normal, fontWeight: FontWeight.w400, letterSpacing: 0, color: Color(0xff5e5e5e))),
  );
}
