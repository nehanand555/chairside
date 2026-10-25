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

/// Only expose external HTTPS URLs. A homepage alone is not a booking link.
String? publicWebsiteUrl(Json place) {
  final value = place['website_url'];
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
      ? value
      : null;
}

/// Booking links are explicit URLs or clearly booking-specific website URLs.
/// This does not imply that a time slot is available.
String? publicBookingUrl(Json place) {
  final explicit = place['booking_url'];
  if (explicit is String) {
    final uri = Uri.tryParse(explicit);
    if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
      return explicit;
    }
  }
  final website = publicWebsiteUrl(place);
  if (website == null) return null;
  final uri = Uri.parse(website);
  final path = uri.path.toLowerCase();
  final host = uri.host.toLowerCase();
  final isBookingPath = RegExp(
    r'(^|/)(book|booking|book-now|book-online|appointments|appointment|schedule|reserve|reservations)(/|$|-)',
  ).hasMatch(path);
  // A booking-provider domain alone is insufficient: its pricing, support and
  // product pages are websites, not business booking destinations.
  final providerBooking =
      ((host == 'booksy.com' || host.endsWith('.booksy.com')) &&
              RegExp(r'^/[a-z]{2}(?:-[a-z]{2})?/\d+').hasMatch(path)) ||
          ((host == 'fresha.com' || host.endsWith('.fresha.com')) &&
              path.startsWith('/a/'));
  return isBookingPath || providerBooking ? website : null;
}

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.store,
    this.mapsEnabled = true,
    this.mapMode = false,
    this.onOpenMap,
  });
  final AppStore store;
  final bool mapsEnabled;
  final bool mapMode;
  final VoidCallback? onOpenMap;
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
  String? category;
  Json? selectedMember, selectedPlace;
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
  void didUpdateWidget(covariant DiscoverScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.mapMode || !mapAvailable) controller = null;
    // Returning to the map should show businesses approved since the last
    // discovery request, without requiring the visitor to press Refresh.
    if (widget.mapMode && !oldWidget.mapMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(load(text: textSearch));
      });
    }
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
      selectedMember = null;
      selectedPlace = null;
    });
    try {
      final data = await widget.store.backend!.invoke('discover', {
        'lat': center.latitude,
        'lng': center.longitude,
        'query': query,
        'include_public': true,
      });
      if (!mounted || request != id) return;
      final c = data['center'] as Map;
      setState(() {
        center = LatLng(
          (c['lat'] as num).toDouble(),
          (c['lng'] as num).toDouble(),
        );
        businesses = List<Json>.from(data['businesses'] as List);
        places = List<Json>.from(data['places'] as List);
        warning = data['warning'] as String?;
      });
      // Switching to Explore disposes the native map, not these shared results.
      try {
        await controller?.animateCamera(CameraUpdate.newLatLngZoom(center, 12));
      } catch (_) {
        /* Camera failure must not discard successful discovery. */
      }
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
          'Location access is off. You can still search by suburb or move the map.',
        );
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (position.latitude < -48 ||
          position.latitude > -33 ||
          position.longitude < 165 ||
          position.longitude > 180)
        throw Exception(
          'spicyself currently serves New Zealand. Search for a New Zealand suburb.',
        );
      center = LatLng(position.latitude, position.longitude);
      search.clear();
      await load(text: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final members = businesses
        .where(
          (b) =>
              (!onlyFavorites || s.favorites.contains(b['id'])) &&
              (category == null || b['kind'] == category),
        )
        .toList();
    final publicResults = onlyFavorites || category != null ? <Json>[] : places;
    return PageBody(
      children: [
        PageHeading(
          widget.mapMode
              ? 'A little closer to your next look.'
              : 'Find your next look.',
          widget.mapMode
              ? 'Explore the map. Find a place that feels like you.'
              : 'Good hair. Your kind of place. Discover local barbers, salons and home studios.',
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LocationSearchBar(
                controller: search,
                onSearch: () => load(text: true),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: loading ? null : () => load(text: true),
                    icon: const Icon(Icons.search),
                    label: const Text('Search'),
                  ),
                  OutlinedButton.icon(
                    onPressed: loading ? null : locate,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Near me'),
                  ),
                  if (!widget.mapMode && widget.onOpenMap != null)
                    TextButton.icon(
                      onPressed: widget.onOpenMap,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Open map'),
                    ),
                ],
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in const [
              (null, 'All'),
              ('barber', 'Barbers'),
              ('salon', 'Hair Salons'),
              ('home', 'Home Studios'),
            ])
              ChoiceChip(
                label: Text(item.$2),
                selected: category == item.$1,
                onSelected: (_) => setState(() {
                  category = item.$1;
                  selectedMember = null;
                  selectedPlace = null;
                }),
              ),
            FilterChip(
              label: const Text('Favourites'),
              avatar: const Icon(Icons.favorite_border, size: 18),
              selected: onlyFavorites,
              onSelected: (v) {
                if (!s.signedIn) {
                  openAccount(context, s);
                } else {
                  setState(() {
                    onlyFavorites = v;
                    selectedMember = null;
                    selectedPlace = null;
                  });
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (loading) const DiscoverySkeleton(),
        if (error != null)
          Notice(
            error!,
            action: TextButton(
              onPressed: () => load(),
              child: const Text('Try again'),
            ),
          ),
        if (widget.mapMode && mapAvailable) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).width < 600 ? 320 : 440,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: center, zoom: 12),
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                onMapCreated: (c) {
                  if (mounted && widget.mapMode && mapAvailable) controller = c;
                },
                onCameraMove: (position) => center = position.target,
                markers: {
                  for (final b in members)
                    Marker(
                      markerId: MarkerId('member-${b['id']}'),
                      position: LatLng(
                        (b['lat'] as num).toDouble(),
                        (b['lng'] as num).toDouble(),
                      ),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueGreen,
                      ),
                      onTap: () => setState(() {
                        selectedMember = b;
                        selectedPlace = null;
                      }),
                      infoWindow: InfoWindow(
                        title: b['name'] as String,
                        snippet: b['kind'] == 'home'
                            ? 'spicyself • Approximate location'
                            : 'spicyself member',
                      ),
                    ),
                  for (final p in publicResults)
                    Marker(
                      markerId: MarkerId(p['place_id'] as String),
                      position: LatLng(
                        (p['lat'] as num).toDouble(),
                        (p['lng'] as num).toDouble(),
                      ),
                      onTap: () => setState(() {
                        selectedPlace = p;
                        selectedMember = null;
                      }),
                      infoWindow: InfoWindow(
                        title: p['name'] as String,
                        snippet: 'Public Google listing',
                      ),
                    ),
                },
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: loading ? null : () => load(text: false),
                icon: const Icon(Icons.refresh),
                label: const Text('Search this map area'),
              ),
              TextButton.icon(
                onPressed: loading ? null : locate,
                icon: const Icon(Icons.my_location),
                label: const Text('Recenter'),
              ),
            ],
          ),
          if (selectedMember != null) memberCard(selectedMember!),
          if (selectedPlace != null)
            PublicBusinessCard(place: selectedPlace!, store: s),
        ],
        if (widget.mapMode && !mapAvailable)
          const Notice(
            'Map view is unavailable. You can browse businesses in the list below.',
          ),
        if (warning != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(warning!, style: Theme.of(context).textTheme.bodySmall),
          ),
        SectionHeader(
          onlyFavorites ? 'Your saved places' : 'Book with spicyself',
          subtitle: 'Local members. Real services. Your next appointment.',
        ),
        if (members.isEmpty && !loading && error == null)
          Notice(
            onlyFavorites
                ? 'No saved businesses in this area. Try another area or turn off Favourites.'
                : 'No members match this area and category yet. Try a nearby suburb or choose All.',
          ),
        ResponsiveCards(children: members.map(memberCard).toList()),
        if (publicResults.isNotEmpty) ...[
          const SectionHeader('Around the neighbourhood'),
          const Text(
            'Public Google listings are directory results. In-app bookings are available only with spicyself members.',
          ),
          const SizedBox(height: 16),
          ResponsiveCards(
            children: publicResults
                .map((p) => PublicBusinessCard(place: p, store: s))
                .toList(),
          ),
          const GoogleAttribution(),
          for (final p in publicResults)
            for (final a in (p['attributions'] as List? ?? []))
              if ((a['provider'] ?? '').toString().isNotEmpty)
                TextButton(
                  onPressed: () => openLink(a['providerUri'] as String),
                  child: Text(a['provider'] as String),
                ),
        ],
        if (category != null && !onlyFavorites)
          const Text(
            'Category filters show spicyself members. Choose All to also browse public Google listings.',
          ),
        const SizedBox(height: 24),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatusPill(
                'spicyself for Business',
                icon: Icons.storefront_outlined,
              ),
              const SizedBox(height: 16),
              Text(
                'Your craft. Your community.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Run a shop or home studio? Apply from Profile to get discovered. You don’t need a Google Maps listing.',
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => openBusinessWorkspace(context, s),
                child: const Text('Meet spicyself for Business'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget memberCard(Json b) => BusinessCard(
        business: b,
        favorite: widget.store.favorites.contains(b['id']),
        onOpen: () => openBusiness(context, widget.store, b['id'] as String),
        onFavorite: () {
          if (!widget.store.signedIn) {
            openAccount(context, widget.store);
          } else {
            widget.store.run(() => widget.store.favorite(b['id'] as String));
          }
        },
      );
}

class ResponsiveCards extends StatelessWidget {
  const ResponsiveCards({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 720 ? 2 : 1;
          final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
          return Wrap(
            spacing: 16,
            runSpacing: 0,
            children: [
              for (final child in children)
                SizedBox(width: width, child: child),
            ],
          );
        },
      );
}

class PublicBusinessCard extends StatelessWidget {
  const PublicBusinessCard({
    super.key,
    required this.place,
    required this.store,
  });
  final Json place;
  final AppStore store;
  @override
  Widget build(BuildContext context) => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StatusPill('Public Google listing', icon: Icons.public),
            const SizedBox(height: 16),
            Text(
              place['name'] as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(place['address'] as String),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (publicBookingUrl(place) != null)
                  OutlinedButton.icon(
                    onPressed: () => openLink(publicBookingUrl(place)!),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Book externally'),
                  ),
                if (publicWebsiteUrl(place) != null)
                  OutlinedButton.icon(
                    onPressed: () => openLink(publicWebsiteUrl(place)!),
                    icon: const Icon(Icons.language),
                    label: const Text('Website'),
                  ),
                TextButton(
                  onPressed: () => showPublicListing(context, store, place),
                  child: const Text('View details'),
                ),
              ],
            ),
          ],
        ),
      );
}

class BusinessCard extends StatelessWidget {
  const BusinessCard({
    super.key,
    required this.business,
    required this.favorite,
    required this.onOpen,
    required this.onFavorite,
  });
  final Json business;
  final bool favorite;
  final VoidCallback onOpen, onFavorite;
  @override
  Widget build(BuildContext context) => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrandPlaceholder(home: business['kind'] == 'home'),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: lime,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    business['kind'] == 'home'
                        ? Icons.home_outlined
                        : Icons.content_cut,
                    color: ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        business['name'] as String,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${business['suburb']}${business['distance_km'] is num ? ' • ${(business['distance_km'] as num).toStringAsFixed(1)} km' : ''}',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onFavorite,
                  icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
                  tooltip: favorite ? 'Remove favourite' : 'Save favourite',
                ),
              ],
            ),
            const SizedBox(height: 12),
            // The discover endpoint returns approved members only; older responses
            // omit status. An explicit non-approved status never gets a badge.
            if (business['status'] == null || business['status'] == 'approved')
              const StatusPill(
                'Verified spicyself business',
                icon: Icons.verified_outlined,
              ),
            const SizedBox(height: 8),
            Text(
              business['kind'] == 'home'
                  ? 'Home studio • approximate map pin'
                  : business['queue_open'] == true
                      ? 'Live queue enabled • check services'
                      : 'Explore services and available times',
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: ValueKey('view-${business['id']}'),
              onPressed: onOpen,
              child: const Text('Services & availability'),
            ),
          ],
        ),
      );
}

Future<void> showPublicListing(
  BuildContext context,
  AppStore store,
  Json place,
) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: 400,
        child: PageBody(
          children: [
            PageHeading(
                place['name'] as String, 'Public listing from Google Maps'),
            Text(place['address'] as String),
            const SizedBox(height: 16),
            const Text(
              'This business has not joined spicyself. We do not have verified booking availability, prices or queue times.',
            ),
            const SizedBox(height: 16),
            if (publicBookingUrl(place) != null) ...[
              FilledButton.icon(
                onPressed: () => openLink(publicBookingUrl(place)!),
                icon: const Icon(Icons.event_available),
                label: const Text('Book externally'),
              ),
              const SizedBox(height: 8),
            ],
            if (publicWebsiteUrl(place) != null) ...[
              OutlinedButton.icon(
                onPressed: () => openLink(publicWebsiteUrl(place)!),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Website'),
              ),
              const SizedBox(height: 8),
              const Text(
                'External links open the business website or booking provider. Bookings are handled outside spicyself; availability is not verified.',
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton(
              onPressed: () => openLink(place['maps_url'] as String),
              child: const Text('View on Google Maps'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Own this business? From Profile, include this Google Place ID when applying. Ownership is reviewed before booking is enabled.',
            ),
            SelectableText(place['place_id'] as String),
            const GoogleAttribution(),
            for (final a in (place['attributions'] as List? ?? []))
              if ((a['provider'] ?? '').toString().isNotEmpty)
                TextButton(
                  onPressed: () => openLink(a['providerUri'] as String),
                  child: Text(a['provider'] as String),
                ),
          ],
        ),
      ),
    );

/// Compact source attribution for Google result cards and listing sheets.
class GoogleAttribution extends StatelessWidget {
  const GoogleAttribution({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(10, 10, 10, 5),
        child: Text(
          'Google Maps',
          maxLines: 1,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            fontStyle: FontStyle.normal,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
            color: Color(0xff5e5e5e),
          ),
        ),
      );
}
