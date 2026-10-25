import 'dart:async';

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

Future<void> sendApplicationNotification(
  AppStore store,
  String businessId,
) async {
  final session = store.sessionRevision;
  final user = store.backend?.userId;
  store.applicationNotificationMessage =
      'Your application is saved. Sending the review notification…';
  store.changed();
  try {
    final result = await store.backend!.invoke('business-application-notify', {
      'business_id': businessId,
    });
    if (!store.isCurrentSession(session, user)) return;
    if (result['email_queued'] == true) {
      store.applicationNotificationMessage =
          'Your application is saved and emails are queued for delivery.';
    } else if (result['email_sent'] == true) {
      store.applicationNotificationMessage = 'Your application is saved and the review notification has been accepted. Delivery to the inbox is not guaranteed.';
    } else if (result['already_processed'] == true) {
      store.applicationNotificationMessage = 'Your application is saved. There is no outstanding review notification to queue.';
    } else if (result['configuration_required'] == true) {
      throw Exception(
        'Application saved. Review email needs a verified sender configured by the platform. You can retry without reapplying.',
      );
    } else {
      throw Exception(
        'Application saved. Review email was not accepted; please retry without reapplying.',
      );
    }
  } catch (e) {
    if (!store.isCurrentSession(session, user)) return;
    store.applicationNotificationMessage =
        'Application saved. Notification delivery needs attention. ${friendlyError(e)}';
    rethrow;
  } finally {
    if (store.isCurrentSession(session, user)) store.changed();
  }
}

// Email delivery must never prevent confirmation of a saved application.
Future<void> notifySavedApplication(AppStore store, String id) async {
  try {
    await sendApplicationNotification(store, id);
  } catch (_) {
    // The notification helper records a retryable delivery message in the store.
  }
}

class ApplicationDeliveryDetails extends StatelessWidget {
  const ApplicationDeliveryDetails({
    super.key,
    required this.store,
    required this.id,
  });
  final AppStore store;
  final String id;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('Email updates'),
    subtitle: const Text('Optional · your application is already saved'),
    childrenPadding: const EdgeInsets.only(bottom: 16),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        (store.applicationNotificationMessage ?? '').contains('needs attention')
            ? 'We could not send the review email. Your application is still saved and awaiting review.'
            : 'You can check your application status here at any time. Email delivery may take a little longer.',
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: store.busy
            ? null
            : () => store.run(() => sendApplicationNotification(store, id)),
        icon: const Icon(Icons.mail_outline, size: 18),
        label: const Text('Check notification'),
      ),
    ],
  );
}

class BusinessScreen extends StatelessWidget {
  const BusinessScreen({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => buildWorkspace(context),
  );

  Widget buildWorkspace(BuildContext context) {
    if (!store.signedIn) {
      return OperatorGate(store: store, child: const SizedBox.shrink());
    }
    if (store.businessId == null) {
      return BusinessApplication(
        key: ValueKey((store.backend!.userId, store.sessionRevision)),
        store: store,
      );
    }
    if (store.account['business_status'] != 'approved') {
      final status = store.account['business_status'] as String? ?? 'pending';
      final note = (store.account['business_review_note'] as String? ?? '')
          .trim();
      void editApplication() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Edit application')),
            body: PendingApplicationEditor(store: store),
          ),
        ),
      );
      return PageBody(
        width: 600,
        children: [
          const SizedBox(height: 16),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    child: Icon(
                      status == 'pending'
                          ? Icons.hourglass_top_rounded
                          : Icons.info_outline,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                PageHeading(
                  status == 'pending'
                      ? 'Application under review'
                      : status == 'rejected'
                      ? 'A few details need updating'
                      : 'Your business is paused',
                  status == 'pending'
                      ? 'You’re all set. We’ll review your details before your listing goes live.'
                      : status == 'rejected'
                      ? 'Read our feedback, update your application, and send it back for review.'
                      : 'Contact spicyself support to discuss your next steps.',
                ),
                if (note.isNotEmpty) ...[
                  Text(
                    'Feedback',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(note),
                  const SizedBox(height: 24),
                ],
                if (status == 'rejected')
                  FilledButton.icon(
                    onPressed: store.busy ? null : editApplication,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit and reapply'),
                  )
                else
                  ActionButton(
                    store,
                    'Check application status',
                    store.refreshAccount,
                    busyLabel: 'Checking status…',
                    icon: Icons.refresh,
                  ),
                if (status == 'pending') ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: store.busy ? null : editApplication,
                    child: const Text('View or edit application'),
                  ),
                ],
                if (status == 'rejected')
                  TextButton(
                    onPressed: store.busy
                        ? null
                        : () => store.run(store.refreshAccount),
                    child: const Text('Check application status'),
                  ),
              ],
            ),
          ),
          if (status == 'pending')
            ApplicationDeliveryDetails(store: store, id: store.businessId!),
        ],
      );
    }
    return OperatorGate(
      store: store,
      child: BusinessDashboard(
        key: ValueKey((
          store.backend!.userId,
          store.businessId,
          store.sessionRevision,
        )),
        store: store,
        id: store.businessId!,
      ),
    );
  }
}

class PendingApplicationEditor extends StatefulWidget {
  const PendingApplicationEditor({super.key, required this.store});
  final AppStore store;
  @override
  State<PendingApplicationEditor> createState() =>
      _PendingApplicationEditorState();
}

class _PendingApplicationEditorState extends State<PendingApplicationEditor> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final description = TextEditingController();
  final registration = TextEditingController();
  final contact = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  late Future<Json> application;
  String? businessId;
  late final int session;
  late final String? user;
  bool get current => mounted && widget.store.isCurrentSession(session, user);
  @override
  void initState() {
    super.initState();
    session = widget.store.sessionRevision;
    user = widget.store.backend!.userId;
    application = load();
  }

  Future<Json> load() async {
    final value = await widget.store.backend!.rpc(
      'my_pending_business_application',
    );
    if (!current) throw Exception('Session changed. Reopen your application.');
    if (value == null) throw Exception('No editable application was found.');
    final data = Json.from(value as Map);
    businessId = data['business_id'] as String;
    name.text = data['name'] as String? ?? '';
    description.text = data['description'] as String? ?? '';
    registration.text = data['registration_number'] as String? ?? '';
    contact.text = data['contact_name'] as String? ?? '';
    email.text = data['contact_email'] as String? ?? '';
    phone.text = data['contact_phone'] as String? ?? '';
    return data;
  }

  @override
  void dispose() {
    for (final controller in [
      name,
      description,
      registration,
      contact,
      email,
      phone,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool submitted = false;

  Future<void> resubmit() async {
    if (submitted) return;
    if (!current || form.currentState?.validate() != true || businessId == null)
      return;
    final id = businessId!;
    await widget.store.backend!.rpc('update_pending_business_application', {
      'p_business': id,
      'p_data': {
        'name': name.text.trim(),
        'description': description.text.trim(),
        'registration_number': registration.text.trim(),
        'contact_name': contact.text.trim(),
        'contact_email': email.text.trim(),
        'contact_phone': phone.text.trim(),
      },
    });
    if (!mounted || !current) return;
    setState(() => submitted = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Application sent for review.')),
    );
    unawaited(notifySavedApplication(widget.store, id));
    await widget.store.refreshAccount();
    if (mounted &&
        current &&
        widget.store.account['business_status'] == 'pending') {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => current
        ? buildEditor(context)
        : const PageBody(
            children: [
              Notice(
                'Session changed. Close this page and reopen your application.',
              ),
            ],
          ),
  );

  Widget buildEditor(BuildContext context) => submitted
      ? PageBody(
          width: 700,
          children: [
            const PageHeading(
              'Application sent for review',
              'Your updated application has been saved. You do not need to submit it again.',
            ),
            if (businessId != null)
              ApplicationDeliveryDetails(store: widget.store, id: businessId!),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to business'),
            ),
          ],
        )
      : PageBody(
          width: 700,
          children: [
            const PageHeading(
              'Review your application',
              'Correct your contact and business details, then resubmit for review.',
            ),
            AsyncPanel<Json>(
              future: application,
              retry: () => setState(() => application = load()),
              builder: (data) => Form(
                key: form,
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Business type: ${data['kind']} · ${data['suburb']}',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'To change your business type or location, contact the review team.',
                      ),
                      const SizedBox(height: 16),
                      FormFieldBox(
                        name,
                        'Business name',
                        validator: (v) => (v ?? '').trim().length < 2
                            ? 'Enter a business name'
                            : null,
                      ),
                      FormFieldBox(
                        description,
                        'About your business',
                        lines: 3,
                        required: false,
                      ),
                      FormFieldBox(
                        registration,
                        'NZBN or registration number',
                        validator: (v) => (v ?? '').trim().length < 2
                            ? 'Enter your registration number or Not applicable'
                            : null,
                      ),
                      FormFieldBox(
                        contact,
                        'Contact person',
                        validator: (v) => (v ?? '').trim().length < 2
                            ? 'Enter a contact name'
                            : null,
                      ),
                      FormFieldBox(
                        email,
                        'Contact email',
                        keyboard: TextInputType.emailAddress,
                        validator: (v) =>
                            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch((v ?? '').trim())
                            ? null
                            : 'Enter a valid email',
                      ),
                      FormFieldBox(
                        phone,
                        'Contact phone',
                        keyboard: TextInputType.phone,
                        validator: (v) =>
                            RegExp(r'^[+0-9 ()-]{7,30}$')
                                .hasMatch((v ?? '').trim())
                            ? null
                            : 'Enter a valid phone number',
                      ),
                      const SizedBox(height: 12),
                      const Notice(
                        'Your changes will be sent to our team for review.',
                      ),
                      if (widget.store.error != null)
                        Notice(widget.store.error!),
                      ActionButton(
                        widget.store,
                        'Save and resubmit for review',
                        resubmit,
                        busyLabel: 'Submitting application…',
                        icon: Icons.send_outlined,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
}

class BusinessApplication extends StatefulWidget {
  const BusinessApplication({super.key, required this.store});
  final AppStore store;
  @override
  State<BusinessApplication> createState() => _BusinessApplicationState();
}

class _BusinessApplicationState extends State<BusinessApplication> {
  final form = GlobalKey<FormState>();
  int step = 0;
  String? submittedApplication;
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
  Timer? addressDebounce;
  List<Json> suggestions = [];
  String? locationError;
  bool locationConfirmed = false, searching = false;
  int searchRevision = 0;
  String sessionToken = DateTime.now().microsecondsSinceEpoch.toString();

  void addressEdited(String value) {
    addressDebounce?.cancel();
    final revision = ++searchRevision;
    setState(() {
      locationConfirmed = false;
      searching = value.trim().length >= 3;
      suggestions = [];
      locationError = null;
      placeId.clear();
    });
    if (value.trim().length < 3) return;
    addressDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final result = await widget.store.backend!.invoke('business-address', {
          'action': 'suggest',
          'query': value.trim(),
          'session_token': sessionToken,
        });
        if (!mounted || revision != searchRevision) return;
        setState(() {
          searching = false;
          suggestions = List<Json>.from(result['suggestions'] as List);
          if (suggestions.isEmpty)
            locationError =
                'No matching address. Try adding your street number and town.';
        });
      } catch (_) {
        if (!mounted || revision != searchRevision) return;
        setState(() {
          searching = false;
          locationError = 'Address suggestions are unavailable. Try again or use the map pin.';
        });
      }
    });
  }

  Future<void> selectAddress(Json suggestion) async {
    addressDebounce?.cancel();
    final revision = ++searchRevision;
    setState(() {
      searching = true;
      suggestions = [];
      locationError = null;
    });
    try {
      final data = await widget.store.backend!.invoke('business-address', {
        'action': 'select',
        'place_id': suggestion['place_id'],
        'session_token': sessionToken,
      });
      if (!mounted || revision != searchRevision) return;
      final value = LatLng(
        (data['lat'] as num).toDouble(),
        (data['lng'] as num).toDouble(),
      );
      setState(() {
        address.text = data['address'] as String;
        suburb.text = data['suburb'] as String;
        placeId.text = data['place_id'] as String;
        pin = value;
        lat.text = value.latitude.toStringAsFixed(6);
        lng.text = value.longitude.toStringAsFixed(6);
        locationConfirmed = true;
        searching = false;
        sessionToken = DateTime.now().microsecondsSinceEpoch.toString();
      });
    } catch (_) {
      if (!mounted || revision != searchRevision) return;
      setState(() {
        searching = false;
        locationError =
            'That location could not be confirmed. Select another suggestion.';
      });
    }
  }

  @override
  void dispose() {
    addressDebounce?.cancel();
    for (final c in [
      name,
      registrationNumber,
      contactName,
      contactEmail,
      contactPhone,
      description,
      address,
      suburb,
      placeId,
      lat,
      lng,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void setPin(LatLng value) {
    setState(() {
      pin = value;
      lat.text = value.latitude.toStringAsFixed(6);
      lng.text = value.longitude.toStringAsFixed(6);
      locationConfirmed = address.text.trim().length >= 5;
      placeId.clear();
      if (suburb.text.isEmpty) suburb.text = 'New Zealand';
    });
  }

  Future<void> submit() async {
    final s = widget.store;
    if (!consent || !declaration)
      throw Exception('Confirm business authority and publication consent.');
    if (submittedApplication != null) return;
    if (!locationConfirmed)
      throw Exception('Choose a suggested address or set the map pin.');
    final session = s.sessionRevision;
    final user = s.backend!.userId;
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
        'lat': double.parse(lat.text.trim()),
        'lng': double.parse(lng.text.trim()),
        'place_id': placeId.text.trim(),
        'publish_consent': consent,
        'operating_declaration': declaration,
      },
    });
    if (!mounted || !s.isCurrentSession(session, user)) return;
    setState(() => submittedApplication = applicationId as String);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Application sent for review.')),
    );
    unawaited(notifySavedApplication(s, applicationId));
    await s.refreshAccount();
  }

  void next() {
    if (!form.currentState!.validate()) return;
    setState(() => step++);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    if (submittedApplication != null)
      return PageBody(
        width: 600,
        children: [
          const PageHeading(
            'Application saved',
            'Application sent for review. There is no need to apply again.',
          ),
          ActionButton(s, 'Check application status', s.refreshAccount),
          ApplicationDeliveryDetails(store: s, id: submittedApplication!),
        ],
      );
    const labels = ['Business', 'Contact', 'Location', 'Review'];
    return PageBody(
      width: 760,
      children: [
        const PageHeading(
          'List your business',
          'Tell us a little about your business. We’ll guide you through four short steps.',
        ),
        const SizedBox(height: 8),
        Text(
          'Step ${step + 1} of 4 · ${labels[step]}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (step + 1) / 4,
          semanticsLabel: 'Application progress',
        ),
        const SizedBox(height: 24),
        Form(
          key: form,
          child: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (step == 0) ...[
                  const SectionHeader('Tell us about your business'),
                  FormFieldBox(
                    name,
                    'Registered business / trading name',
                    validator: (v) => (v ?? '').trim().length < 2
                        ? 'Enter a name of at least 2 characters'
                        : null,
                  ),
                  FormFieldBox(
                    registrationNumber,
                    'NZBN or business registration number',
                    hint: 'Use Not applicable if you do not have a registration number',
                    validator: (v) =>
                        (v ?? '').trim().length < 2 || (v ?? '').length > 80
                        ? 'Enter your registration number or Not applicable'
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Business type',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'barber',
                        child: Text('Barber shop'),
                      ),
                      DropdownMenuItem(
                        value: 'salon',
                        child: Text('Hair salon'),
                      ),
                      DropdownMenuItem(
                        value: 'home',
                        child: Text('Home studio'),
                      ),
                    ],
                    onChanged: (v) => setState(() => kind = v!),
                  ),
                  const SizedBox(height: 16),
                  FormFieldBox(
                    description,
                    'About your business',
                    lines: 3,
                    required: false,
                  ),
                ],
                if (step == 1) ...[
                  const SectionHeader('A person we can reach'),
                  FormFieldBox(
                    contactName,
                    'Contact person full name',
                    validator: (v) => (v ?? '').trim().length < 2
                        ? 'Enter the contact person’s name'
                        : null,
                  ),
                  FormFieldBox(
                    contactEmail,
                    'Business contact email',
                    keyboard: TextInputType.emailAddress,
                    validator: (v) =>
                        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch((v ?? '').trim())
                        ? null
                        : 'Enter a valid email address',
                  ),
                  FormFieldBox(
                    contactPhone,
                    'Business contact phone',
                    keyboard: TextInputType.phone,
                    validator: (v) =>
                        RegExp(r'^[+0-9 ()-]{7,30}$').hasMatch((v ?? '').trim())
                        ? null
                        : 'Enter a valid contact phone',
                  ),
                  const Notice(
                    'Registration and contact details are private. Only authorised reviewers can see them.',
                  ),
                ],
                if (step == 2) ...[
                  const SectionHeader('Where the good hair happens'),
                  TextFormField(
                    controller: address,
                    onChanged: addressEdited,
                    decoration: const InputDecoration(
                      labelText: 'Business street address',
                      hintText: 'Start typing your street address',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    validator: (v) => (v ?? '').trim().length < 5
                        ? 'Enter a street address'
                        : !locationConfirmed
                        ? 'Choose a suggestion or confirm the map pin'
                        : null,
                  ),
                  if (searching) const LinearProgressIndicator(),
                  if (locationError != null) Notice(locationError!),
                  for (final suggestion in suggestions)
                    ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(suggestion['description'] as String),
                      onTap: () => selectAddress(suggestion),
                    ),
                  const Text(
                    'Choose an NZ address to automatically place the map pin. '
                    'You can move the pin if necessary. Home studio addresses remain private.',
                  ),
                  const SizedBox(height: 16),
                  if ((!kIsWeb && const bool.fromEnvironment('MAPS_ENABLED')) ||
                      (kIsWeb &&
                          const String.fromEnvironment('GOOGLE_MAPS_WEB_KEY')
                              .isNotEmpty))
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 240,
                        child: GoogleMap(
                          key: ValueKey('${pin.latitude}:${pin.longitude}'),
                          initialCameraPosition: CameraPosition(
                            target: pin,
                            zoom: 12,
                          ),
                          onTap: setPin,
                          markers: {
                            Marker(
                              markerId: const MarkerId('business'),
                              position: pin,
                              draggable: true,
                              onDragEnd: setPin,
                            ),
                          },
                          zoomControlsEnabled: false,
                          myLocationButtonEnabled: false,
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: s.busy
                        ? null
                        : () => s.run(() async {
                            if (!await Geolocator.isLocationServiceEnabled())
                              throw Exception(
                                'Turn on location services or choose an address.',
                              );
                            var permission = await Geolocator.checkPermission();
                            if (permission == LocationPermission.denied)
                              permission = await Geolocator.requestPermission();
                            if (permission == LocationPermission.denied ||
                                permission == LocationPermission.deniedForever)
                              throw Exception(
                                'Location permission is off. Choose an address or tap the map.',
                              );
                            final value = await Geolocator.getCurrentPosition(
                              locationSettings: const LocationSettings(
                                timeLimit: Duration(seconds: 15),
                              ),
                            );
                            if (mounted)
                              setPin(LatLng(value.latitude, value.longitude));
                          }),
                    icon: const Icon(Icons.my_location),
                    label: const Text('Use my current business location'),
                  ),
                  const SizedBox(height: 16),
                  if (locationConfirmed)
                    const Notice(
                      'Location confirmed. Map coordinates have been saved automatically.',
                    ),
                ],
                if (step == 3) ...[
                  const SectionHeader('One last look'),
                  Text(
                    name.text,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${kind == 'home'
                        ? 'Home studio'
                        : kind == 'salon'
                        ? 'Hair salon'
                        : 'Barber shop'} · ${address.text}',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Review contact: ${contactName.text} · ${contactEmail.text}',
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: declaration,
                    onChanged: s.busy
                        ? null
                        : (v) => setState(() => declaration = v!),
                    title: const Text(
                      'I own or am authorised to manage this business, and have the permissions required to operate at this address.',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: consent,
                    onChanged: s.busy
                        ? null
                        : (v) => setState(() => consent = v!),
                    title: const Text(
                      'Publish my business name, services, photos and public map location after approval.',
                    ),
                  ),
                  const Notice(
                    'We’ll review your application before your listing goes live.',
                  ),
                  if (s.error != null) Notice(s.error!),
                  ActionButton(
                    s,
                    'Submit business application',
                    submit,
                    busyLabel: 'Submitting application…',
                    icon: Icons.storefront_outlined,
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (step > 0)
                      OutlinedButton(
                        onPressed: s.busy ? null : () => setState(() => step--),
                        child: const Text('Back'),
                      ),
                    if (step < 3)
                      FilledButton(
                        onPressed: s.busy ? null : next,
                        child: const Text('Continue'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
  DateTime calendarDay = DateTime.now();
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    business = widget.store.backend!
        .rpc('operator_business', {'p_business': widget.id})
        .then((v) => Json.from(v as Map));
    photos = widget.store.backend!
        .photos(widget.id)
        .catchError((_) => <String>[]);
  }

  Future<void> configure(String action, Json data) async {
    await widget.store.backend!.rpc('configure_business', {
      'p_business': widget.id,
      'p_action': action,
      'p_data': data,
    });
    if (mounted) setState(reload);
    await widget.store.refreshVisits();
  }

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      AsyncPanel<Json>(
        future: business,
        retry: () => setState(reload),
        builder: (b) {
          final s = widget.store;
          final services = List<Json>.from(b['services'] as List),
              resources = List<Json>.from(b['resources'] as List);
          final visits =
              s.visits.where((v) => v['business_id'] == widget.id).toList()
                ..sort(
                  (a, b) => (a['starts_at'] as String).compareTo(
                    b['starts_at'] as String,
                  ),
                );
          final activeServices = services
              .where((v) => v['active'] == true)
              .length;
          final activeChairs = resources
              .where((v) => v['active'] == true)
              .length;
          final hasHours = (b['hours'] as List).isNotEmpty;
          final setupSteps = <(String, bool)>[
            (
              'Add at least one active service with a price',
              activeServices > 0,
            ),
            ('Set your weekly opening hours', hasHours),
            ('Add an active chair or professional', activeChairs > 0),
          ];
          final setupComplete = setupSteps.where((step) => step.$2).length;
          final completedVisits = visits
              .where((v) => v['status'] == 'completed')
              .length;
          final cancelledVisits = visits
              .where((v) => v['status'] == 'cancelled')
              .length;
          final active = visits
              .where(
                (v) =>
                    ['waiting', 'booked', 'serving'].contains(v['status']) &&
                    (section != 3 || v['kind'] == 'queue'),
              )
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeading(
                b['name'] as String,
                'Your shop floor, wherever you are.',
                action: OutlinedButton.icon(
                  onPressed: () {
                    setState(reload);
                    s.refreshVisits();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ),
              if (b['status'] != 'approved')
                Notice(
                  'Listing status: ${b['status']}. ${b['review_note'] ?? ''} ${b['status'] == 'pending' ? 'Add services and hours below so an admin can review your application.' : ''}',
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(
                    '${visits.where((v) => v['kind'] == 'queue' && v['status'] == 'waiting').length} waiting',
                    icon: Icons.groups_outlined,
                  ),
                  StatusPill(
                    '${visits.where((v) => v['status'] == 'serving').length} in the chair',
                    icon: Icons.content_cut,
                  ),
                  StatusPill(
                    '${visits.where((v) => v['kind'] == 'appointment' && ['booked', 'serving'].contains(v['status']) && dayKey(tz.TZDateTime.from(DateTime.parse(v['starts_at'] as String), tz.getLocation('Pacific/Auckland'))) == dayKey(nzNow())).length} appointments today',
                    icon: Icons.today_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (setupComplete < setupSteps.length)
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Finish setting up your business ($setupComplete/${setupSteps.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Complete these steps so customers can see accurate services and availability.',
                      ),
                      const SizedBox(height: 8),
                      for (final step in setupSteps)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            step.$2
                                ? Icons.check_circle_outline
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text(step.$1),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => section = 1),
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Complete business setup'),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(
                    '$completedVisits completed visits',
                    icon: Icons.check_circle_outline,
                  ),
                  StatusPill(
                    '$cancelledVisits cancelled visits',
                    icon: Icons.event_busy_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Live queue'),
                    selected: section == 3,
                    onSelected: (_) => setState(() => section = 3),
                  ),
                  ChoiceChip(
                    label: Text('Today & upcoming (${active.length})'),
                    selected: section == 0,
                    onSelected: (_) => setState(() => section = 0),
                  ),
                  ChoiceChip(
                    label: const Text('Business settings'),
                    selected: section == 1,
                    onSelected: (_) => setState(() => section = 1),
                  ),
                  ChoiceChip(
                    label: const Text('Calendar'),
                    selected: section == 4,
                    onSelected: (_) => setState(() => section = 4),
                  ),
                  ChoiceChip(
                    label: const Text('History'),
                    selected: section == 2,
                    onSelected: (_) => setState(() => section = 2),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (section == 4) ...[
                Panel(
                  child: CalendarDatePicker(
                    initialDate: calendarDay,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                    onDateChanged: (day) => setState(() => calendarDay = day),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Appointments for ${calendarDay.day}/${calendarDay.month}/${calendarDay.year}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (!visits.any(
                  (v) =>
                      v['kind'] == 'appointment' &&
                      dayKey(
                            tz.TZDateTime.from(
                              DateTime.parse(v['starts_at'] as String),
                              tz.getLocation('Pacific/Auckland'),
                            ),
                          ) ==
                          dayKey(
                            tz.TZDateTime(
                              tz.getLocation('Pacific/Auckland'),
                              calendarDay.year,
                              calendarDay.month,
                              calendarDay.day,
                            ),
                          ),
                ))
                  const Notice('No appointments on this date.'),
                for (final v in visits.where(
                  (v) =>
                      v['kind'] == 'appointment' &&
                      dayKey(
                            tz.TZDateTime.from(
                              DateTime.parse(v['starts_at'] as String),
                              tz.getLocation('Pacific/Auckland'),
                            ),
                          ) ==
                          dayKey(
                            tz.TZDateTime(
                              tz.getLocation('Pacific/Auckland'),
                              calendarDay.year,
                              calendarDay.month,
                              calendarDay.day,
                            ),
                          ),
                ))
                  VisitCard(store: s, visit: v, operator: true),
              ],
              if (section == 0 || section == 3) ...[
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
                              : (v) => s.run(
                                  () => configure('queue', {'open': v}),
                                ),
                          title: const Text('Accept new queue arrivals'),
                          subtitle: const Text(
                            'Pausing keeps everyone already waiting.',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: s.busy || b['status'] != 'approved'
                              ? null
                              : () => addWalkIn(context, b),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Add walk-in'),
                        ),
                      ],
                    ),
                  ),
                if (active.isEmpty)
                  const Notice(
                    'No active visits. Your next customer will appear here.',
                  ),
                for (final r in resources.where(
                  (r) => r['active'] == true,
                )) ...[
                  Text(
                    r['name'] as String,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  ...active
                      .where((v) => v['resource_id'] == r['id'])
                      .map(
                        (v) => VisitCard(store: s, visit: v, operator: true),
                      ),
                ],
              ],
              if (section == 2)
                ...visits
                    .where(
                      (v) => ![
                        'waiting',
                        'booked',
                        'serving',
                      ].contains(v['status']),
                    )
                    .toList()
                    .reversed
                    .map((v) => VisitCard(store: s, visit: v, operator: true)),
              if ((section == 0 || section == 2 || section == 3) &&
                  s.moreVisits)
                ActionButton(s, 'Load more visits', s.loadMoreVisits),
              if (section == 1) ...[
                WorkspaceGroup(
                  title: 'Business profile',
                  icon: Icons.storefront_outlined,
                  children: [
                    Text(
                      b['name'] as String,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text('${b['suburb']} · ${b['kind']}'),
                    const SizedBox(height: 8),
                    Text(b['description'] as String),
                    const SizedBox(height: 16),
                    const Notice(
                      'Name, address and ownership changes require review. Finish active visits before requesting a replacement listing. Home studio addresses remain private.',
                    ),
                  ],
                ),
                WorkspaceGroup(
                  title: 'Services & pricing',
                  icon: Icons.content_cut,
                  children: [
                    Text(
                      'Services',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    for (final v in services)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(v['name'] as String),
                        subtitle: Text(
                          '${v['minutes']} min • ${money(v['price_cents'])} • ${v['active'] == true ? 'active' : 'hidden'}',
                        ),
                        trailing: IconButton(
                          onPressed: () => editService(context, v),
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit service',
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => editService(context, null),
                      icon: const Icon(Icons.add),
                      label: const Text('Add service'),
                    ),
                  ],
                ),
                WorkspaceGroup(
                  title: 'Working hours',
                  icon: Icons.schedule,
                  children: [
                    Text(
                      'Opening hours',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'New Zealand time. To change hours, finish or cancel active visits first.',
                    ),
                    const SizedBox(height: 12),
                    for (final h in b['hours'] as List)
                      Text(
                        '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][(h['weekday'] as int) - 1]} ${(h['opens'] as String).substring(0, 5)}–${(h['closes'] as String).substring(0, 5)}',
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => editHours(
                        context,
                        List<Json>.from(b['hours'] as List),
                      ),
                      child: const Text('Edit weekly hours'),
                    ),
                  ],
                ),
                WorkspaceGroup(
                  title: 'Chairs & breaks',
                  icon: Icons.chair_outlined,
                  children: [
                    Text(
                      'Chairs / professionals',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Each chair has its own appointments and queue. Everyone uses the business opening hours.',
                    ),
                    for (final r in resources)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(r['name'] as String),
                        subtitle: Text(
                          r['active'] == true ? 'Active' : 'Hidden',
                        ),
                        trailing: IconButton(
                          onPressed: () => editResource(context, r),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => editResource(context, null),
                      icon: const Icon(Icons.add),
                      label: const Text('Add chair'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => addBreak(context, resources),
                      child: const Text('Schedule a break'),
                    ),
                    for (final r in b['breaks'] as List? ?? [])
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Break: ${nzTime(r['starts_at'])}'),
                        subtitle: Text('Until ${nzTime(r['ends_at'])}'),
                        trailing: IconButton(
                          onPressed: () => s.run(
                            () => configure('remove_break', {'id': r['id']}),
                          ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                  ],
                ),
                WorkspaceGroup(
                  title: 'Portfolio',
                  icon: Icons.photo_library_outlined,
                  children: [
                    Text(
                      'Portfolio photos',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Public images. Upload only photos you have permission to publish. Maximum 5 MB each.',
                    ),
                    const SizedBox(height: 12),
                    AsyncPanel<List<String>>(
                      future: photos,
                      builder: (urls) => Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: urls
                            .map(
                              (url) => SizedBox(
                                width: 160,
                                child: Column(
                                  children: [
                                    Image.network(
                                      url,
                                      width: 160,
                                      height: 120,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, e, st) => const Icon(
                                        Icons.broken_image_outlined,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => s.run(() async {
                                        await s.backend!.deletePhoto(
                                          widget.id,
                                          url,
                                        );
                                        if (mounted) setState(reload);
                                      }),
                                      child: const Text('Remove'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: s.busy
                          ? null
                          : () => s.run(() async {
                              final image = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1800,
                                imageQuality: 85,
                              );
                              if (image == null) return;
                              await s.backend!.uploadPhoto(
                                widget.id,
                                await image.readAsBytes(),
                                image.name.split('.').last.toLowerCase(),
                              );
                              if (mounted) setState(reload);
                            }),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Add photo'),
                    ),
                  ],
                ),
                WorkspaceGroup(
                  title: 'Payments & payouts',
                  icon: Icons.payments_outlined,
                  children: [
                    Text(
                      'Payments & payouts',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      b['online_payments'] == true
                          ? 'Online payments are enabled.'
                          : 'Complete Stripe verification to accept online payments. Customers can still pay at your business.',
                    ),
                    const SizedBox(height: 12),
                    ActionButton(s, 'Set up / update Stripe account', () async {
                      final result = await s.backend!.invoke('payments', {
                        'action': 'connect',
                        'business_id': widget.id,
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
                                'business_id': widget.id,
                              });
                              if (mounted) setState(reload);
                            }),
                      child: const Text('Refresh payment status'),
                    ),
                    const Text(
                      'Stripe processing fees apply. Available wallets depend on the customer’s device. Afterpay requires separate activation and eligibility.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: s.busy
                      ? null
                      : () async {
                          if (await confirm(
                            context,
                            'Close your spicyself listing?',
                            'Finish or cancel all visits first. This removes your listing from search. Historical financial records are retained.',
                            store: s,
                            requireMfa: true,
                            action: 'Close listing',
                          ))
                            await s.run(() async {
                              await configure('close', {});
                              await s.refreshAccount();
                            });
                        },
                  child: const Text('Close business listing'),
                ),
              ],
            ],
          );
        },
      ),
    ],
  );
  Future<void> editService(BuildContext context, Json? current) async {
    final name = TextEditingController(text: current?['name'] as String? ?? ''),
        minutes = TextEditingController(text: '${current?['minutes'] ?? 30}'),
        price = TextEditingController(
          text: ((current?['price_cents'] as num? ?? 3000) / 100)
              .toStringAsFixed(2),
        );
    bool active = current?['active'] != false;
    final result = await showSessionDialog<Json>(
      context,
      widget.store,
      requireMfa: true,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(current == null ? 'Add service' : 'Edit service'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FormFieldBox(name, 'Service name'),
                FormFieldBox(
                  minutes,
                  'Duration in minutes',
                  keyboard: TextInputType.number,
                ),
                FormFieldBox(
                  price,
                  'Price in NZD',
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                if (current != null)
                  SwitchListTile(
                    value: active,
                    title: const Text('Available for new bookings'),
                    onChanged: (v) => set(() => active = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
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
                        'Enter a name, 10–240 minutes, and a price of \$1–\$2,000.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'id': current?['id'],
                  'name': name.text.trim(),
                  'minutes': m,
                  'price_cents': (p * 100).round(),
                  'active': active,
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    minutes.dispose();
    price.dispose();
    if (result != null && mounted)
      await widget.store.run(() => configure('service', result));
  }

  Future<void> editResource(BuildContext context, Json? current) async {
    final name = TextEditingController(text: current?['name'] as String? ?? '');
    bool active = current?['active'] != false;
    final result = await showSessionDialog<Json>(
      context,
      widget.store,
      requireMfa: true,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Chair / professional'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FormFieldBox(name, 'Name'),
              if (current != null)
                SwitchListTile(
                  title: const Text('Active'),
                  value: active,
                  onChanged: (v) => set(() => active = v),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isNotEmpty)
                  Navigator.pop(context, {
                    'id': current?['id'],
                    'name': name.text.trim(),
                    'active': active,
                  });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (result != null && mounted)
      await widget.store.run(() => configure('resource', result));
  }

  Future<void> editHours(BuildContext context, List<Json> current) async {
    final enabled = List.generate(
      7,
      (i) => current.any((h) => h['weekday'] == i + 1),
    );
    final opens = List.generate(
      7,
      (i) => TextEditingController(
        text:
            (current.where((h) => h['weekday'] == i + 1).firstOrNull?['opens']
                        as String? ??
                    '09:00')
                .substring(0, 5),
      ),
    );
    final closes = List.generate(
      7,
      (i) => TextEditingController(
        text:
            (current.where((h) => h['weekday'] == i + 1).firstOrNull?['closes']
                        as String? ??
                    '17:00')
                .substring(0, 5),
      ),
    );
    final result = await showSessionDialog<List<Json>>(
      context,
      widget.store,
      requireMfa: true,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Weekly hours'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const Text(
                    '24-hour times, e.g. 09:00 and 17:00. Overnight hours are not supported.',
                  ),
                  for (int i = 0; i < 7; i++)
                    Column(
                      children: [
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            const [
                              'Monday',
                              'Tuesday',
                              'Wednesday',
                              'Thursday',
                              'Friday',
                              'Saturday',
                              'Sunday',
                            ][i],
                          ),
                          value: enabled[i],
                          onChanged: (v) => set(() => enabled[i] = v!),
                        ),
                        if (enabled[i])
                          Row(
                            children: [
                              Expanded(child: FormFieldBox(opens[i], 'Opens')),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FormFieldBox(closes[i], 'Closes'),
                              ),
                            ],
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final hours = <Json>[];
                for (int i = 0; i < 7; i++) {
                  if (!enabled[i]) continue;
                  if (!RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$')
                          .hasMatch(opens[i].text) ||
                      !RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$')
                          .hasMatch(closes[i].text) ||
                      opens[i].text.compareTo(closes[i].text) >= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Use valid opening and closing times. Closing must be after opening.',
                        ),
                      ),
                    );
                    return;
                  }
                  hours.add({
                    'weekday': i + 1,
                    'opens': opens[i].text,
                    'closes': closes[i].text,
                  });
                }
                Navigator.pop(context, hours);
              },
              child: const Text('Save hours'),
            ),
          ],
        ),
      ),
    );
    for (final c in [...opens, ...closes]) {
      c.dispose();
    }
    if (result != null && mounted)
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
    final result = await showSessionDialog<Json>(
      context,
      widget.store,
      requireMfa: true,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Add walk-in'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FormFieldBox(name, 'Customer name'),
                FormFieldBox(
                  phone,
                  'Phone (optional)',
                  keyboard: TextInputType.phone,
                  required: false,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Customer agrees to booking texts'),
                  value: consent,
                  onChanged: (v) => set(() => consent = v!),
                ),
                DropdownButtonFormField<String>(
                  initialValue: service,
                  isExpanded: true,
                  items: services
                      .map(
                        (v) => DropdownMenuItem(
                          value: v['id'] as String,
                          child: Text(
                            v['name'] as String,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => service = v!,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: resource,
                  isExpanded: true,
                  items: resources
                      .map(
                        (v) => DropdownMenuItem(
                          value: v['id'] as String,
                          child: Text(v['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => resource = v!,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
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
                      'sms_consent': consent,
                    },
                  });
              },
              child: const Text('Add to queue'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    phone.dispose();
    if (result != null && mounted)
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
              '${nzNow().hour.toString().padLeft(2, '0')}:${nzNow().minute.toString().padLeft(2, '0')}',
        ),
        minutes = TextEditingController(text: '30');
    final result = await showSessionDialog<Json>(
      context,
      widget.store,
      requireMfa: true,
      builder: (context) => AlertDialog(
        title: const Text('Break today'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: resource,
                isExpanded: true,
                items: active
                    .map(
                      (v) => DropdownMenuItem(
                        value: v['id'] as String,
                        child: Text(v['name'] as String),
                      ),
                    )
                    .toList(),
                onChanged: (v) => resource = v!,
              ),
              const SizedBox(height: 16),
              FormFieldBox(start, 'Start (HH:mm NZ time)'),
              FormFieldBox(minutes, 'Minutes', keyboard: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'resource_id': resource,
              'time': start.text,
              'minutes': minutes.text,
            }),
            child: const Text('Add break'),
          ),
        ],
      ),
    );
    start.dispose();
    minutes.dispose();
    if (result != null && mounted)
      await widget.store.run(() async {
        if (!RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$')
            .hasMatch(result['time'] as String))
          throw Exception('Use a 24-hour time such as 13:30');
        final parts = (result['time'] as String)
            .split(':')
            .map(int.parse)
            .toList();
        final n = nzNow();
        final date = tz.TZDateTime(
          tz.getLocation('Pacific/Auckland'),
          n.year,
          n.month,
          n.day,
          parts[0],
          parts[1],
        );
        await configure('break', {
          'resource_id': result['resource_id'],
          'starts_at': date.toUtc().toIso8601String(),
          'minutes': int.parse(result['minutes'] as String),
        });
      });
  }
}
