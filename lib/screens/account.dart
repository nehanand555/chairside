import 'package:flutter/material.dart';
import '../data/backend.dart';
import '../data/store.dart';
import 'app.dart';
import 'admin.dart';
import 'common.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.store, this.onBusinessTap});
  final AppStore store;
  final VoidCallback? onBusinessTap;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final name = TextEditingController();
  final signInEmail = TextEditingController();
  bool emailSent = false;
  bool sms = false, marketing = false, accepted = false;
  String? loadedUser, formUser;
  int? formSession;
  @override
  void dispose() {
    name.dispose();
    signInEmail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.store, builder: (context, _) => buildAccount(context));

  Widget buildAccount(BuildContext context) {
    final s = widget.store;
    if (formUser != s.backend?.userId || formSession != s.sessionRevision) {
      formSession = s.sessionRevision;
      formUser = s.backend?.userId;
      loadedUser = null;
      name.clear();
      sms = false;
      marketing = false;
      accepted = false;
      signInEmail.clear();
      emailSent = false;
    }
    if (!s.signedIn)
      return PageBody(width: 520, children: [
        const PageHeading('Welcome to SpicySelf',
            'Sign in with Google or receive a secure email sign-in link.'),
        Panel(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: accepted,
                  onChanged:
                      s.busy ? null : (v) => setState(() => accepted = v!),
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
              const SizedBox(height: 18),
              const Text('Or sign in with email',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: signInEmail,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                    labelText: 'Email address',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              ActionButton(s, 'Send sign-in link', () async {
                if (!accepted)
                  throw Exception('Please read and accept the terms first');
                final email = signInEmail.text.trim();
                if (!RegExp(r'^[^@\\s]+@[^@\\s]+\\.[^@\\s]+
            ])),
        const Text(
            'Google lets you choose an account each time. Email sign-in uses a one-time link, without a password. You can browse without signing in.'),
      ]);
    if (loadedUser != s.backend!.userId && s.profile.isNotEmpty) {
      loadedUser = s.backend!.userId;
      if (name.text.isEmpty) name.text = s.displayName;
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
          child: Text(
              'Check My Bookings for booking confirmations and live queue updates.'),
        ),
        if (s.backend!.hasVerifiedPhone)
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Booking texts'),
              subtitle:
                  const Text('Confirmations, reminders and queue updates.'),
              value: sms,
              onChanged: (v) => setState(() => sms = v)),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Offers & news'),
            subtitle: const Text('Optional. Separate from booking updates.'),
            value: marketing,
            onChanged: (v) => setState(() => marketing = v)),
        ActionButton(s, 'Save preferences', () async {
          final session = s.sessionRevision;
          final user = s.backend!.userId;
          await s.saveProfile(
              name.text, s.backend!.hasVerifiedPhone && sms, marketing);
          if (context.mounted && s.isCurrentSession(session, user))
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Saved')));
        }, icon: Icons.check)
      ])),
      Panel(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('SpicySelf for Business',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(s.businessId == null
              ? 'Get discovered by local customers. Claim or register your barber shop, salon or home studio for free.'
              : s.account['business_status'] == 'approved'
                  ? 'Manage your services, opening hours, bookings and live queue in one place.'
                  : 'Track your application while our team reviews your business details.'),
          if (s.businessId == null) ...[
            const SizedBox(height: 12),
            const Text('Free listing includes:',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(
                '• A business profile customers can discover\n• Services, prices and opening hours\n• Booking and queue tools after approval and setup'),
            const SizedBox(height: 8),
            const Text(
                'Applications are reviewed before your business becomes publicly bookable.'),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed:
                widget.onBusinessTap ?? () => openBusinessWorkspace(context, s),
            icon: const Icon(Icons.storefront_outlined),
            label: Text(
                s.businessId == null ? 'List your business' : 'Open business'),
          ),
        ],
      )),
      if (s.isAdmin)
        Panel(
            child: ListTile(
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: const Text('Administration'),
          subtitle: const Text('Protected review and operations console'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => DetailScaffold(
                  store: s,
                  title: 'Administration',
                  child: ListenableBuilder(
                      listenable: s,
                      builder: (context, child) => AdminScreen(store: s))))),
        )),
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
                      store: s, action: 'Delete account')) {
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
        Notice('Sign in with Google or email to register or manage a business.',
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
  String? factorUser;
  int? factorSession;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    if (factorUser != s.backend?.userId || factorSession != s.sessionRevision) {
      factorSession = s.sessionRevision;
      factorUser = s.backend?.userId;
      factors = null;
      enrollment = null;
      code.clear();
    }
    if (!s.signedIn) return const SizedBox.shrink();
    if (s.unlocked)
      return const Notice(
          'Business access is unlocked for this session. Keep your authenticator app available for future sign-ins.');
    return AsyncPanel<List<Json>>(
        key: ValueKey((factorUser, s.sessionRevision)),
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
                      'Add SpicySelf to an authenticator such as Google Authenticator or Microsoft Authenticator. Store the setup key securely; you’ll need the app to access business tools.'),
                  const SizedBox(height: 12),
                  ActionButton(s, 'Set up authenticator', () async {
                    final session = s.sessionRevision;
                    final user = s.backend!.userId;
                    for (final f
                        in items.where((f) => f['status'] != 'verified')) {
                      if (!s.isCurrentSession(session, user)) return;
                      await s.backend!.discardFactor(f['id'] as String);
                    }
                    if (!s.isCurrentSession(session, user)) return;
                    final result = await s.backend!.enrollFactor();
                    if (mounted && s.isCurrentSession(session, user))
                      setState(() => enrollment = result);
                  }, icon: Icons.shield_outlined)
                ],
                if (enrollment != null) ...[
                  const Text(
                      'In your authenticator choose “Enter setup key”, name it SpicySelf, and choose time-based codes. Keep this key private.'),
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
)
                    .hasMatch(email)) {
                  throw Exception('Enter a valid email address');
                }
                await s.backend!.signInWithEmail(email);
                if (mounted) setState(() => emailSent = true);
              }, icon: Icons.mail_outline),
              if (emailSent)
                const Notice('Check your inbox for a SpicySelf sign-in link. It may take a moment to arrive.'),
            ])),
        const Text(
            'Google handles your sign-in. We never receive your Google password. You can browse nearby businesses without signing in.'),
      ]);
    if (loadedUser != s.backend!.userId && s.profile.isNotEmpty) {
      loadedUser = s.backend!.userId;
      if (name.text.isEmpty) name.text = s.displayName;
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
          child: Text(
              'Check My Bookings for booking confirmations and live queue updates.'),
        ),
        if (s.backend!.hasVerifiedPhone)
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Booking texts'),
              subtitle:
                  const Text('Confirmations, reminders and queue updates.'),
              value: sms,
              onChanged: (v) => setState(() => sms = v)),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Offers & news'),
            subtitle: const Text('Optional. Separate from booking updates.'),
            value: marketing,
            onChanged: (v) => setState(() => marketing = v)),
        ActionButton(s, 'Save preferences', () async {
          final session = s.sessionRevision;
          final user = s.backend!.userId;
          await s.saveProfile(
              name.text, s.backend!.hasVerifiedPhone && sms, marketing);
          if (context.mounted && s.isCurrentSession(session, user))
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Saved')));
        }, icon: Icons.check)
      ])),
      Panel(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('SpicySelf for Business',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(s.businessId == null
              ? 'Get discovered by local customers. Claim or register your barber shop, salon or home studio for free.'
              : s.account['business_status'] == 'approved'
                  ? 'Manage your services, opening hours, bookings and live queue in one place.'
                  : 'Track your application while our team reviews your business details.'),
          if (s.businessId == null) ...[
            const SizedBox(height: 12),
            const Text('Free listing includes:',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(
                '• A business profile customers can discover\n• Services, prices and opening hours\n• Booking and queue tools after approval and setup'),
            const SizedBox(height: 8),
            const Text(
                'Applications are reviewed before your business becomes publicly bookable.'),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed:
                widget.onBusinessTap ?? () => openBusinessWorkspace(context, s),
            icon: const Icon(Icons.storefront_outlined),
            label: Text(
                s.businessId == null ? 'List your business' : 'Open business'),
          ),
        ],
      )),
      if (s.isAdmin)
        Panel(
            child: ListTile(
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: const Text('Administration'),
          subtitle: const Text('Protected review and operations console'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => DetailScaffold(
                  store: s,
                  title: 'Administration',
                  child: ListenableBuilder(
                      listenable: s,
                      builder: (context, child) => AdminScreen(store: s))))),
        )),
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
                      store: s, action: 'Delete account')) {
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
  String? factorUser;
  int? factorSession;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    if (factorUser != s.backend?.userId || factorSession != s.sessionRevision) {
      factorSession = s.sessionRevision;
      factorUser = s.backend?.userId;
      factors = null;
      enrollment = null;
      code.clear();
    }
    if (!s.signedIn) return const SizedBox.shrink();
    if (s.unlocked)
      return const Notice(
          'Business access is unlocked for this session. Keep your authenticator app available for future sign-ins.');
    return AsyncPanel<List<Json>>(
        key: ValueKey((factorUser, s.sessionRevision)),
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
                      'Add SpicySelf to an authenticator such as Google Authenticator or Microsoft Authenticator. Store the setup key securely; you’ll need the app to access business tools.'),
                  const SizedBox(height: 12),
                  ActionButton(s, 'Set up authenticator', () async {
                    final session = s.sessionRevision;
                    final user = s.backend!.userId;
                    for (final f
                        in items.where((f) => f['status'] != 'verified')) {
                      if (!s.isCurrentSession(session, user)) return;
                      await s.backend!.discardFactor(f['id'] as String);
                    }
                    if (!s.isCurrentSession(session, user)) return;
                    final result = await s.backend!.enrollFactor();
                    if (mounted && s.isCurrentSession(session, user))
                      setState(() => enrollment = result);
                  }, icon: Icons.shield_outlined)
                ],
                if (enrollment != null) ...[
                  const Text(
                      'In your authenticator choose “Enter setup key”, name it SpicySelf, and choose time-based codes. Keep this key private.'),
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
