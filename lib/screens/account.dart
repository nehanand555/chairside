import 'package:flutter/material.dart';
import '../data/backend.dart';
import '../data/store.dart';
import 'app.dart';
import 'common.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final name = TextEditingController();
  bool sms = false, marketing = false, accepted = false;
  String? loadedUser;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    if (!s.signedIn)
      return PageBody(width: 520, children: [
        const PageHeading('Welcome to Chairside',
            'Continue with your Google account. No SMS code needed.'),
        Panel(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: accepted,
                  onChanged: s.busy ? null : (v) => setState(() => accepted = v!),
                  title: const Text(
                      'I agree to the booking terms and privacy notice.')),
              TextButton(
                  onPressed: () => showLegal(context),
                  child: const Text('Read terms and privacy')),
              ActionButton(s, 'Continue with Google', () async {
                if (!accepted)
                  throw Exception('Please read and accept the terms first');
                await s.backend!.signInWithGoogle();
              }, icon: Icons.login),
            ])),
        const Text(
            'Google handles your sign-in. We never receive your Google password. You can browse nearby businesses without signing in.'),
      ]);
    if (loadedUser != s.backend!.userId && s.profile.isNotEmpty) {
      loadedUser = s.backend!.userId;
      name.text = s.profile['display_name'] ?? '';
      sms = s.profile['sms_updates'] == true;
      marketing = s.profile['marketing_consent'] == true;
    }
    return PageBody(width: 650, children: [
      const PageHeading(
          'Your account', 'A few details, and you’re ready to book.'),
      Panel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FormFieldBox(name, 'Your name'),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Check My visits for booking confirmations and live queue updates.'),
        ),
        if (s.backend!.hasVerifiedPhone) SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Booking texts'),
            subtitle: const Text('Confirmations, reminders and queue updates.'),
            value: sms,
            onChanged: (v) => setState(() => sms = v)),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Offers & news'),
            subtitle: const Text('Optional. Separate from booking updates.'),
            value: marketing,
            onChanged: (v) => setState(() => marketing = v)),
        ActionButton(s, 'Save preferences', () async {
          await s.saveProfile(name.text, s.backend!.hasVerifiedPhone && sms, marketing);
          if (context.mounted)
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Saved')));
        }, icon: Icons.check)
      ])),
      if (s.businessId != null || s.isAdmin) MfaPanel(store: s),
      OutlinedButton(
          onPressed: s.busy
              ? null
              : () => s.run(() async {
                    await s.backend!.signOut();
                    await s.refreshAccount();
                    if (mounted)
                      setState(() {
                        loadedUser = null;
                      });
                  }),
          child: const Text('Sign out')),
      const SizedBox(height: 16),
      TextButton(
          onPressed: s.busy
              ? null
              : () async {
                  if (await confirm(context, 'Delete your account?',
                      'This removes your profile and signs you out. Finish or cancel active visits first. Business owners must close their business. Financial records may be retained.',
                      action: 'Delete account')) {
                    await s.run(() async {
                      await s.backend!.invoke('delete-account', {});
                      await s.backend!.signOut();
                      await s.refreshAccount();
                    });
                  }
                },
          child: const Text('Delete account')),
    ]);
  }
}

class OperatorGate extends StatelessWidget {
  const OperatorGate({super.key, required this.store, required this.child});
  final AppStore store;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!store.signedIn)
      return PageBody(children: [
        const PageHeading('Your business, in your pocket.',
            'Manage appointments and a calmer queue from your phone or tablet.'),
        Notice('Sign in with Google to register or manage a business.',
            action: FilledButton(
                onPressed: () => openAccount(context, store),
                child: const Text('Sign in')))
      ]);
    if (!store.unlocked)
      return PageBody(width: 620, children: [
        const PageHeading('Protect your business',
            'Business and admin access requires an authenticator code.'),
        MfaPanel(store: store)
      ]);
    return child;
  }
}

class MfaPanel extends StatefulWidget {
  const MfaPanel({super.key, required this.store});
  final AppStore store;
  @override
  State<MfaPanel> createState() => _MfaPanelState();
}

class _MfaPanelState extends State<MfaPanel> {
  final code = TextEditingController();
  Future<List<Json>>? factors;
  Json? enrollment;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    if (s.unlocked)
      return const Notice(
          'Business access is unlocked for this session. Keep your authenticator app available for future sign-ins.');
    return AsyncPanel<List<Json>>(
        future: factors ??= s.backend!.factors(),
        retry: () => setState(() => factors = s.backend!.factors()),
        builder: (items) {
          final verified =
              items.where((f) => f['status'] == 'verified').toList();
          return Panel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                const Text('Authenticator protection',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (verified.isEmpty && enrollment == null) ...[
                  const Text(
                      'Add Chairside to an authenticator such as Google Authenticator or Microsoft Authenticator. Store the setup key securely; you’ll need the app to access business tools.'),
                  const SizedBox(height: 12),
                  ActionButton(s, 'Set up authenticator', () async {
                    for (final f
                        in items.where((f) => f['status'] != 'verified')) {
                      await s.backend!.discardFactor(f['id'] as String);
                    }
                    final result = await s.backend!.enrollFactor();
                    if (mounted) setState(() => enrollment = result);
                  }, icon: Icons.shield_outlined)
                ],
                if (enrollment != null) ...[
                  const Text(
                      'In your authenticator choose “Enter setup key”, name it Chairside, and choose time-based codes. Keep this key private.'),
                  const SizedBox(height: 12),
                  SelectableText(enrollment!['secret'] as String),
                  const SizedBox(height: 12)
                ],
                if (verified.isNotEmpty || enrollment != null) ...[
                  FormFieldBox(code, 'Authenticator code',
                      keyboard: TextInputType.number),
                  ActionButton(s, 'Unlock business access', () async {
                    await s.backend!.verifyFactor(
                        (enrollment ?? verified.first)['id'] as String,
                        code.text.trim());
                    code.clear();
                    enrollment = null;
                    await s.refreshAccount();
                  }, icon: Icons.lock_open)
                ],
              ]));
        });
  }
}
