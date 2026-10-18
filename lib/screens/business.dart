import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:timezone/timezone.dart' as tz;
import '../data/backend.dart';
import '../data/store.dart';
import 'account.dart';
import 'common.dart';
import 'visits.dart';

class BusinessScreen extends StatelessWidget {
  const BusinessScreen({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) {
    if (!store.signedIn) {
      return OperatorGate(store: store, child: const SizedBox.shrink());
    }
    if (store.businessId == null) {
      return BusinessApplication(store: store);
    }
    if (store.account['business_status'] != 'approved') {
      final status = store.account['business_status'] as String? ?? 'pending';
      final note = (store.account['business_review_note'] as String? ?? '').trim();
      return PageBody(width: 700, children: [
        PageHeading(
          status == 'pending' ? 'Application under review' : 'Business application: $status',
          'Your business will appear as a verified SpicySelf listing only after approval.',
        ),
        Notice(status == 'pending'
            ? 'Your application has been submitted. Our team will review your registration and contact details.'
            : 'Your business is not currently approved. Contact SpicySelf support if you need a review.'),
        if (note.isNotEmpty) Panel(child: Text('Review note: $note')),
        OutlinedButton.icon(
          onPressed: store.busy ? null : () => store.run(store.refreshAccount),
          icon: const Icon(Icons.refresh),
          label: const Text('Check application status'),
        ),
      ]);
    }
    return OperatorGate(
      store: store,
      child: BusinessDashboard(store: store, id: store.businessId!),
    );
  }
}

class BusinessApplication extends StatefulWidget {
  const BusinessApplication({super.key, required this.store});
  final AppStore store;
  @override
  State<BusinessApplication> createState() => _BusinessApplicationState();
}

class _BusinessApplicationState extends State<BusinessApplication> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      registrationNumber = TextEditingController(),
      contactName = TextEditingController(),
      contactEmail = TextEditingController(),
      contactPhone = TextEditingController(),
      description = TextEditingController(),
      address = TextEditingController(),
      suburb = TextEditingController(),
      placeId = TextEditingController(),
      lat = TextEditingController(),
      lng = TextEditingController();
  String kind = 'barber';
  bool consent = false, declaration = false;
  LatLng pin = const LatLng(-36.8485, 174.7633);
  @override
  void dispose() {
    for (final c in [name, registrationNumber, contactName, contactEmail, contactPhone, description, address, suburb, placeId, lat, lng]) {
      c.dispose();
    }
    super.dispose();
  }

  void setPin(LatLng value) {
    setState(() {
      pin = value;
      lat.text = value.latitude.toStringAsFixed(6);
      lng.text = value.longitude.toStringAsFixed(6);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return PageBody(width: 760, children: [
      const PageHeading('Put your business on the map.',
          'Shop, salon or home studio — you can join even if you’re not on Google Maps.'),
      Form(
          key: form,
          child: Panel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                FormFieldBox(name, 'Registered business / trading name'),
                FormFieldBox(registrationNumber, 'NZBN or business registration number'),
                FormFieldBox(contactName, 'Contact person full name'),
                FormFieldBox(contactEmail, 'Business contact email',
                    keyboard: TextInputType.emailAddress),
                FormFieldBox(contactPhone, 'Business contact phone',
                    keyboard: TextInputType.phone),
                const Text('Your registration number and contact details are used for verification and are not shown on your public listing.'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: const InputDecoration(
                        labelText: 'Business type',
                        border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(
                          value: 'barber', child: Text('Barber shop')),
                      DropdownMenuItem(
                          value: 'salon', child: Text('Hair salon')),
                      DropdownMenuItem(
                          value: 'home', child: Text('Home studio'))
                    ],
                    onChanged: (v) => setState(() => kind = v!)),
                const SizedBox(height: 16),
                FormFieldBox(description, 'About your business',
                    lines: 3, required: false),
                FormFieldBox(address, 'Full business address'),
                FormFieldBox(suburb, 'Suburb / town'),
                const Text(
                    'Set the pin at your actual entrance. For home studios, only an approximate pin and suburb are public.'),
                const SizedBox(height: 12),
                if ((!kIsWeb && const bool.fromEnvironment('MAPS_ENABLED')) ||
                    (kIsWeb &&
                        const String.fromEnvironment('GOOGLE_MAPS_WEB_KEY')
                            .isNotEmpty))
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SizedBox(
                          height: 260,
                          child: GoogleMap(
                              initialCameraPosition:
                                  CameraPosition(target: pin, zoom: 12),
                              onTap: setPin,
                              markers: {
                                Marker(
                                    markerId: const MarkerId('business'),
                                    position: pin,
                                    draggable: true,
                                    onDragEnd: setPin)
                              },
                              zoomControlsEnabled: false,
                              myLocationButtonEnabled: false))),
                OutlinedButton.icon(
                    onPressed: s.busy
                        ? null
                        : () => s.run(() async {
                              var p = await Geolocator.checkPermission();
                              if (p == LocationPermission.denied)
                                p = await Geolocator.requestPermission();
                              if (p == LocationPermission.denied ||
                                  p == LocationPermission.deniedForever)
                                throw Exception(
                                    'Location permission is off. Tap the map or enter the coordinates.');
                              final value = await Geolocator.getCurrentPosition(
                                  locationSettings: const LocationSettings(
                                      timeLimit: Duration(seconds: 15)));
                              if (mounted)
                                setPin(LatLng(value.latitude, value.longitude));
                            }),
                    icon: const Icon(Icons.my_location),
                    label: const Text('Use my current business location')),
                const SizedBox(height: 16),
                FormFieldBox(lat, 'Pin latitude',
                    hint: '-36.848500',
                    keyboard: const TextInputType.numberWithOptions(
                        decimal: true, signed: true)),
                FormFieldBox(lng, 'Pin longitude',
                    hint: '174.763300',
                    keyboard: const TextInputType.numberWithOptions(
                        decimal: true, signed: true)),
                FormFieldBox(placeId, 'Google Place ID (optional)',
                    required: false,
                    hint: 'Copy from your public listing to claim it'),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: declaration,
                    onChanged: (v) => setState(() => declaration = v!),
                    title: const Text(
                        'I own or am authorised to manage this business, and have the permissions required to operate at this address.')),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: consent,
                    onChanged: (v) => setState(() => consent = v!),
                    title: const Text(
                        'Publish my business name, services, photos and public map location after approval.')),
                const SizedBox(height: 12),
                const Text(
                    'Our team reviews your registration and ownership details before your business becomes a verified listing. After approval you can set up services, opening hours and bookings. Applying does not register your business with Google.'),
                const SizedBox(height: 16),
                ActionButton(s, 'Submit business application', () async {
                  if (!form.currentState!.validate()) return;
                  if (!consent || !declaration)
                    throw Exception(
                        'Please confirm business authority and publication consent');
                  if (contactEmail.text.trim().isEmpty ||
                      !contactEmail.text.contains('@') ||
                      contactPhone.text.trim().length < 7 ||
                      registrationNumber.text.trim().length < 2) {
                    throw Exception('Enter valid registration and contact details.');
                  }
                  final applicationId = await s.backend!.rpc('apply_business', {
                    'p_data': {
                      'name': name.text.trim(),
                      'registration_number': registrationNumber.text.trim(),
                      'contact_name': contactName.text.trim(),
                      'contact_email': contactEmail.text.trim(),
                      'contact_phone': contactPhone.text.trim(),
                      'description': description.text.trim(),
                      'kind': kind,
                      'address': address.text.trim(),
                      'suburb': suburb.text.trim(),
                      'lat': double.parse(lat.text),
                      'lng': double.parse(lng.text),
                      'place_id': placeId.text.trim(),
                      'publish_consent': consent,
                      'operating_declaration': declaration
                    }
                  });
                  await s.refreshAccount();
                  // Email is a best-effort notification; the application is
                  // already stored for review even if email delivery fails.
                  try {
                    await s.backend!.invoke('business-application-notify', {
                      'business_id': applicationId
                    });
                  } catch (_) {
                    // The admin review queue remains the source of truth.
                  }
                }, icon: Icons.storefront_outlined),
              ]))),
    ]);
  }
}

class BusinessDashboard extends StatefulWidget {
  const BusinessDashboard({super.key, required this.store, required this.id});
  final AppStore store;
  final String id;
  @override
  State<BusinessDashboard> createState() => _BusinessDashboardState();
}

class _BusinessDashboardState extends State<BusinessDashboard> {
  late Future<Json> business;
  late Future<List<String>> photos;
  int section = 0;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    business = widget.store.backend!.rpc('operator_business',
        {'p_business': widget.id}).then((v) => Json.from(v as Map));
    photos = widget.store.backend!.photos(widget.id).catchError((_) => <String>[]);
  }

  Future<void> configure(String action, Json data) async {
    await widget.store.backend!.rpc('configure_business',
        {'p_business': widget.id, 'p_action': action, 'p_data': data});
    if (mounted) setState(reload);
    await widget.store.refreshVisits();
  }

  @override
  Widget build(BuildContext context) => PageBody(children: [
        AsyncPanel<Json>(
            future: business,
            retry: () => setState(reload),
            builder: (b) {
              final s = widget.store;
              final services = List<Json>.from(b['services'] as List),
                  resources = List<Json>.from(b['resources'] as List);
              final visits = s.visits
                  .where((v) => v['business_id'] == widget.id)
                  .toList()
                ..sort((a, b) => (a['starts_at'] as String)
                    .compareTo(b['starts_at'] as String));
              final active = visits
                  .where((v) =>
                      ['waiting', 'booked', 'serving'].contains(v['status']))
                  .toList();
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageHeading(b['name'] as String,
                        'Your shop floor, wherever you are.',
                        action: OutlinedButton.icon(
                            onPressed: () {
                              setState(reload);
                              s.refreshVisits();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh'))),
                    if (b['status'] != 'approved')
                      Notice(
                          'Listing status: ${b['status']}. ${b['review_note'] ?? ''} ${b['status'] == 'pending' ? 'Add services and hours below so an admin can review your application.' : ''}'),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      ChoiceChip(
                          label: Text('Today & upcoming (${active.length})'),
                          selected: section == 0,
                          onSelected: (_) => setState(() => section = 0)),
                      ChoiceChip(
                          label: const Text('Business settings'),
                          selected: section == 1,
                          onSelected: (_) => setState(() => section = 1)),
                      ChoiceChip(
                          label: const Text('History'),
                          selected: section == 2,
                          onSelected: (_) => setState(() => section = 2))
                    ]),
                    const SizedBox(height: 20),
                    if (section == 0) ...[
                      if (b['kind'] != 'home')
                        Panel(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: b['queue_open'] == true,
                                  onChanged: s.busy || b['status'] != 'approved'
                                      ? null
                                      : (v) => s.run(() =>
                                          configure('queue', {'open': v})),
                                  title:
                                      const Text('Accept new queue arrivals'),
                                  subtitle: const Text(
                                      'Pausing keeps everyone already waiting.')),
                              OutlinedButton.icon(
                                  onPressed: s.busy || b['status'] != 'approved'
                                      ? null
                                      : () => addWalkIn(context, b),
                                  icon: const Icon(Icons.person_add_alt_1),
                                  label: const Text('Add walk-in'))
                            ])),
                      if (active.isEmpty)
                        const Notice(
                            'No active visits. Your next customer will appear here.'),
                      for (final r
                          in resources.where((r) => r['active'] == true)) ...[
                        Text(r['name'] as String,
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        ...active.where((v) => v['resource_id'] == r['id']).map(
                            (v) =>
                                VisitCard(store: s, visit: v, operator: true))
                      ],
                    ],
                    if (section == 2)
                      ...visits
                          .where((v) => !['waiting', 'booked', 'serving']
                              .contains(v['status']))
                          .toList()
                          .reversed
                          .map((v) =>
                              VisitCard(store: s, visit: v, operator: true)),
                    if ((section == 0 || section == 2) && s.moreVisits) ActionButton(s, 'Load more visits', s.loadMoreVisits),
                    if (section == 1) ...[
                      Panel(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Services',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 12),
                            for (final v in services)
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(v['name'] as String),
                                  subtitle: Text(
                                      '${v['minutes']} min • ${money(v['price_cents'])} • ${v['active'] == true ? 'active' : 'hidden'}'),
                                  trailing: IconButton(
                                      onPressed: () => editService(context, v),
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: 'Edit service')),
                            OutlinedButton.icon(
                                onPressed: () => editService(context, null),
                                icon: const Icon(Icons.add),
                                label: const Text('Add service'))
                          ])),
                      Panel(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Opening hours',
                                style: Theme.of(context).textTheme.titleLarge),
                            const Text(
                                'New Zealand time. To change hours, finish or cancel active visits first.'),
                            const SizedBox(height: 12),
                            for (final h in b['hours'] as List)
                              Text('${const [
                                'Mon',
                                'Tue',
                                'Wed',
                                'Thu',
                                'Fri',
                                'Sat',
                                'Sun'
                              ][(h['weekday'] as int) - 1]} ${(h['opens'] as String).substring(0, 5)}–${(h['closes'] as String).substring(0, 5)}'),
                            const SizedBox(height: 12),
                            OutlinedButton(
                                onPressed: () => editHours(context,
                                    List<Json>.from(b['hours'] as List)),
                                child: const Text('Edit weekly hours'))
                          ])),
                      Panel(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Chairs / professionals',
                                style: Theme.of(context).textTheme.titleLarge),
                            const Text(
                                'Each chair has its own appointments and queue. Everyone uses the business opening hours.'),
                            for (final r in resources)
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(r['name'] as String),
                                  subtitle: Text(r['active'] == true
                                      ? 'Active'
                                      : 'Hidden'),
                                  trailing: IconButton(
                                      onPressed: () => editResource(context, r),
                                      icon: const Icon(Icons.edit_outlined))),
                            OutlinedButton.icon(
                                onPressed: () => editResource(context, null),
                                icon: const Icon(Icons.add),
                                label: const Text('Add chair')),
                            const SizedBox(height: 12),
                            OutlinedButton(
                                onPressed: () => addBreak(context, resources),
                                child: const Text('Schedule a break')),
                            for (final r in b['breaks'] as List? ?? [])
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title:
                                      Text('Break: ${nzTime(r['starts_at'])}'),
                                  subtitle:
                                      Text('Until ${nzTime(r['ends_at'])}'),
                                  trailing: IconButton(
                                      onPressed: () => s.run(() => configure(
                                          'remove_break', {'id': r['id']})),
                                      icon: const Icon(Icons.delete_outline)))
                          ])),
                      Panel(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Portfolio photos',
                                style: Theme.of(context).textTheme.titleLarge),
                            const Text(
                                'Public images. Upload only photos you have permission to publish. Maximum 5 MB each.'),
                            const SizedBox(height: 12),
                            AsyncPanel<List<String>>(
                                future: photos,
                                builder: (urls) => Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: urls
                                        .map((url) => SizedBox(
                                            width: 160,
                                            child: Column(children: [
                                              Image.network(url,
                                                  width: 160,
                                                  height: 120,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, e, st) =>
                                                      const Icon(Icons
                                                          .broken_image_outlined)),
                                              TextButton(
                                                  onPressed: () =>
                                                      s.run(() async {
                                                        await s.backend!
                                                            .deletePhoto(
                                                                widget.id, url);
                                                        if (mounted)
                                                          setState(reload);
                                                      }),
                                                  child: const Text('Remove'))
                                            ])))
                                        .toList())),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                                onPressed: s.busy
                                    ? null
                                    : () => s.run(() async {
                                          final image = await ImagePicker()
                                              .pickImage(
                                                  source: ImageSource.gallery,
                                                  maxWidth: 1800,
                                                  imageQuality: 85);
                                          if (image == null) return;
                                          await s.backend!.uploadPhoto(
                                              widget.id,
                                              await image.readAsBytes(),
                                              image.name
                                                  .split('.')
                                                  .last
                                                  .toLowerCase());
                                          if (mounted) setState(reload);
                                        }),
                                icon: const Icon(
                                    Icons.add_photo_alternate_outlined),
                                label: const Text('Add photo'))
                          ])),
                      Panel(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Payments & payouts',
                                style: Theme.of(context).textTheme.titleLarge),
                            Text(b['online_payments'] == true
                                ? 'Online payments are enabled.'
                                : 'Complete Stripe verification to accept online payments. Customers can still pay at your business.'),
                            const SizedBox(height: 12),
                            ActionButton(s, 'Set up / update Stripe account',
                                () async {
                              final result = await s.backend!.invoke(
                                  'payments', {
                                'action': 'connect',
                                'business_id': widget.id
                              });
                              await openLink(result['url'] as String);
                            }, icon: Icons.account_balance_outlined),
                            const SizedBox(height: 12),
                            OutlinedButton(
                                onPressed: s.busy
                                    ? null
                                    : () => s.run(() async {
                                          await s.backend!.invoke('payments', {
                                            'action': 'sync',
                                            'business_id': widget.id
                                          });
                                          if (mounted) setState(reload);
                                        }),
                                child: const Text('Refresh payment status')),
                            const Text(
                                'Stripe processing fees apply. Available wallets depend on the customer’s device. Afterpay requires separate activation and eligibility.',
                                style: TextStyle(fontSize: 12))
                          ])),
                      TextButton(
                          onPressed: s.busy
                              ? null
                              : () async {
                                  if (await confirm(
                                      context,
                                      'Close your Chairside listing?',
                                      'Finish or cancel all visits first. This removes your listing from search. Historical financial records are retained.',
                                      action: 'Close listing'))
                                    await s.run(() async {
                                      await configure('close', {});
                                      await s.refreshAccount();
                                    });
                                },
                          child: const Text('Close business listing')),
                    ],
                  ]);
            })
      ]);
  Future<void> editService(BuildContext context, Json? current) async {
    final name = TextEditingController(text: current?['name'] as String? ?? ''),
        minutes = TextEditingController(text: '${current?['minutes'] ?? 30}'),
        price = TextEditingController(
            text: ((current?['price_cents'] as num? ?? 3000) / 100)
                .toStringAsFixed(2));
    bool active = current?['active'] != false;
    final result = await showDialog<Json>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, set) => AlertDialog(
                    title:
                        Text(current == null ? 'Add service' : 'Edit service'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      FormFieldBox(name, 'Service name'),
                      FormFieldBox(minutes, 'Duration in minutes',
                          keyboard: TextInputType.number),
                      FormFieldBox(price, 'Price in NZD',
                          keyboard: const TextInputType.numberWithOptions(
                              decimal: true)),
                      if (current != null)
                        SwitchListTile(
                            value: active,
                            title: const Text('Available for new bookings'),
                            onChanged: (v) => set(() => active = v))
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () {
                            final m = int.tryParse(minutes.text),
                                p = double.tryParse(price.text);
                            if (name.text.trim().length < 2 ||
                                m == null ||
                                m < 10 ||
                                m > 240 ||
                                p == null ||
                                !p.isFinite ||
                                p < 1 ||
                                p > 2000) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Enter a name, 10–240 minutes, and a price of \$1–\$2,000.')));
                              return;
                            }
                            Navigator.pop(context, {
                              'id': current?['id'],
                              'name': name.text.trim(),
                              'minutes': m,
                              'price_cents': (p * 100).round(),
                              'active': active
                            });
                          },
                          child: const Text('Save'))
                    ])));
    name.dispose();
    minutes.dispose();
    price.dispose();
    if (result != null)
      await widget.store.run(() => configure('service', result));
  }

  Future<void> editResource(BuildContext context, Json? current) async {
    final name = TextEditingController(text: current?['name'] as String? ?? '');
    bool active = current?['active'] != false;
    final result = await showDialog<Json>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, set) => AlertDialog(
                    title: const Text('Chair / professional'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      FormFieldBox(name, 'Name'),
                      if (current != null)
                        SwitchListTile(
                            title: const Text('Active'),
                            value: active,
                            onChanged: (v) => set(() => active = v))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () {
                            if (name.text.trim().isNotEmpty)
                              Navigator.pop(context, {
                                'id': current?['id'],
                                'name': name.text.trim(),
                                'active': active
                              });
                          },
                          child: const Text('Save'))
                    ])));
    name.dispose();
    if (result != null)
      await widget.store.run(() => configure('resource', result));
  }

  Future<void> editHours(BuildContext context, List<Json> current) async {
    final enabled =
        List.generate(7, (i) => current.any((h) => h['weekday'] == i + 1));
    final opens = List.generate(
        7,
        (i) => TextEditingController(
            text: (current
                        .where((h) => h['weekday'] == i + 1)
                        .firstOrNull?['opens'] as String? ??
                    '09:00')
                .substring(0, 5)));
    final closes = List.generate(
        7,
        (i) => TextEditingController(
            text: (current
                        .where((h) => h['weekday'] == i + 1)
                        .firstOrNull?['closes'] as String? ??
                    '17:00')
                .substring(0, 5)));
    final result = await showDialog<List<Json>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, set) => AlertDialog(
                    title: const Text('Weekly hours'),
                    content: SizedBox(
                        width: 440,
                        child: SingleChildScrollView(
                            child: Column(children: [
                          const Text(
                              '24-hour times, e.g. 09:00 and 17:00. Overnight hours are not supported.'),
                          for (int i = 0; i < 7; i++)
                            Column(children: [
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(const [
                                    'Monday',
                                    'Tuesday',
                                    'Wednesday',
                                    'Thursday',
                                    'Friday',
                                    'Saturday',
                                    'Sunday'
                                  ][i]),
                                  value: enabled[i],
                                  onChanged: (v) => set(() => enabled[i] = v!)),
                              if (enabled[i])
                                Row(children: [
                                  Expanded(
                                      child: FormFieldBox(opens[i], 'Opens')),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: FormFieldBox(closes[i], 'Closes'))
                                ])
                            ])
                        ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () {
                            final hours = <Json>[];
                            for (int i = 0; i < 7; i++) {
                              if (!enabled[i]) continue;
                              if (!RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$')
                                      .hasMatch(opens[i].text) ||
                                  !RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$')
                                      .hasMatch(closes[i].text) ||
                                  opens[i].text.compareTo(closes[i].text) >=
                                      0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Use valid opening and closing times. Closing must be after opening.')));
                                return;
                              }
                              hours.add({
                                'weekday': i + 1,
                                'opens': opens[i].text,
                                'closes': closes[i].text
                              });
                            }
                            Navigator.pop(context, hours);
                          },
                          child: const Text('Save hours'))
                    ])));
    for (final c in [...opens, ...closes]) {
      c.dispose();
    }
    if (result != null)
      await widget.store.run(() => configure('hours', {'hours': result}));
  }

  Future<void> addWalkIn(BuildContext context, Json b) async {
    final name = TextEditingController(), phone = TextEditingController();
    final services = List<Json>.from(b['services'] as List)
            .where((v) => v['active'] == true)
            .toList(),
        resources = List<Json>.from(b['resources'] as List)
            .where((v) => v['active'] == true)
            .toList();
    if (services.isEmpty || resources.isEmpty) {
      await widget.store.run(() async {
        throw Exception('Add an active service and chair first');
      });
      return;
    }
    String service = services.first['id'] as String,
        resource = resources.first['id'] as String;
    bool consent = false;
    final result = await showDialog<Json>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, set) => AlertDialog(
                    title: const Text('Add walk-in'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      FormFieldBox(name, 'Customer name'),
                      FormFieldBox(phone, 'Phone (optional)',
                          keyboard: TextInputType.phone, required: false),
                      CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Customer agrees to booking texts'),
                          value: consent,
                          onChanged: (v) => set(() => consent = v!)),
                      DropdownButtonFormField<String>(
                          initialValue: service,
                          isExpanded: true,
                          items: services
                              .map((v) => DropdownMenuItem(
                                  value: v['id'] as String,
                                  child: Text(v['name'] as String,
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) => service = v!),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                          initialValue: resource,
                          isExpanded: true,
                          items: resources
                              .map((v) => DropdownMenuItem(
                                  value: v['id'] as String,
                                  child: Text(v['name'] as String)))
                              .toList(),
                          onChanged: (v) => resource = v!)
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () {
                            if (name.text.trim().isNotEmpty)
                              Navigator.pop(context, {
                                'p_business': widget.id,
                                'p_service': service,
                                'p_resource': resource,
                                'p_kind': 'queue',
                                'p_walk_in': {
                                  'name': name.text.trim(),
                                  'phone': phone.text.trim(),
                                  'sms_consent': consent
                                }
                              });
                          },
                          child: const Text('Add to queue'))
                    ])));
    name.dispose();
    phone.dispose();
    if (result != null)
      await widget.store.run(() async {
        final walk = result['p_walk_in'] as Json;
        if ((walk['phone'] as String).isNotEmpty)
          walk['phone'] = normalizePhone(walk['phone'] as String);
        await widget.store.backend!.rpc('create_visit', result);
        await widget.store.refreshVisits();
      });
  }

  Future<void> addBreak(BuildContext context, List<Json> resources) async {
    final active = resources.where((v) => v['active'] == true).toList();
    if (active.isEmpty) return;
    String resource = active.first['id'] as String;
    final start = TextEditingController(
            text:
                '${nzNow().hour.toString().padLeft(2, '0')}:${nzNow().minute.toString().padLeft(2, '0')}'),
        minutes = TextEditingController(text: '30');
    final result = await showDialog<Json>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Break today'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                      initialValue: resource,
                      isExpanded: true,
                      items: active
                          .map((v) => DropdownMenuItem(
                              value: v['id'] as String,
                              child: Text(v['name'] as String)))
                          .toList(),
                      onChanged: (v) => resource = v!),
                  const SizedBox(height: 16),
                  FormFieldBox(start, 'Start (HH:mm NZ time)'),
                  FormFieldBox(minutes, 'Minutes',
                      keyboard: TextInputType.number)
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, {
                            'resource_id': resource,
                            'time': start.text,
                            'minutes': minutes.text
                          }),
                      child: const Text('Add break'))
                ]));
    start.dispose();
    minutes.dispose();
    if (result != null)
      await widget.store.run(() async {
        if (!RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$')
            .hasMatch(result['time'] as String))
          throw Exception('Use a 24-hour time such as 13:30');
        final parts =
            (result['time'] as String).split(':').map(int.parse).toList();
        final n = nzNow();
        final date = tz.TZDateTime(tz.getLocation('Pacific/Auckland'), n.year,
            n.month, n.day, parts[0], parts[1]);
        await configure('break', {
          'resource_id': result['resource_id'],
          'starts_at': date.toUtc().toIso8601String(),
          'minutes': int.parse(result['minutes'] as String)
        });
      });
  }
}
