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
  final phone = TextEditingController(), code = TextEditingController(), name = TextEditingController();
  bool sent = false, sms = false, marketing = false, accepted = false;
  String? sentPhone, loadedUser;
  @override
  void dispose() { phone.dispose(); code.dispose(); name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    if (!s.signedIn) return PageBody(width: 520, children: [
      const PageHeading('Welcome to Chairside', 'Use your phone number. No email or password needed.'),
      Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FormFieldBox(phone, 'Phone number', hint: '021 123 4567', keyboard: TextInputType.phone),
        CheckboxListTile(contentPadding: EdgeInsets.zero, value: accepted, onChanged: sent ? null : (v) => setState(() => accepted = v!), title: const Text('I agree to the booking terms and privacy notice.')),
        TextButton(onPressed: () => showLegal(context), child: const Text('Read terms and privacy')),
        if (!sent) ActionButton(s, 'Text me a code', () async { if (!accepted) throw Exception('Please read and accept the terms first'); final number = normalizePhone(phone.text); await s.backend!.sendCode(number); if (mounted) setState(() { sent = true; sentPhone = number; }); }, icon: Icons.sms_outlined),
        if (sent) ...[Text('Enter the code sent to $sentPhone'), const SizedBox(height: 16), FormFieldBox(code, 'Verification code', keyboard: TextInputType.number), ActionButton(s, 'Verify & continue', () async { await s.backend!.verifyCode(sentPhone!, code.text.trim()); await s.refreshAccount(); }, icon: Icons.verified_outlined), TextButton(onPressed: s.busy ? null : () => setState(() { sent = false; code.clear(); }), child: const Text('Change number or request another code'))],
      ])),
      const Text('We only send sign-in codes unless you choose booking updates. Standard carrier charges may apply.'),
    ]);
    if (loadedUser != s.backend!.userId && s.profile.isNotEmpty) { loadedUser = s.backend!.userId; name.text = s.profile['display_name'] ?? ''; sms = s.profile['sms_updates'] == true; marketing = s.profile['marketing_consent'] == true; }
    return PageBody(width: 650, children: [
      const PageHeading('Your account', 'A few details, and you’re ready to book.'),
      Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [FormFieldBox(name, 'Your name'), SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Booking texts'), subtitle: const Text('Confirmations, reminders and queue updates.'), value: sms, onChanged: (v) => setState(() => sms = v)), SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Offers & news'), subtitle: const Text('Optional. Separate from booking updates.'), value: marketing, onChanged: (v) => setState(() => marketing = v)), ActionButton(s, 'Save preferences', () async { await s.saveProfile(name.text, sms, marketing); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved'))); }, icon: Icons.check)])),
      if (s.businessId != null || s.isAdmin) MfaPanel(store: s),
      OutlinedButton(onPressed: s.busy ? null : () => s.run(() async { await s.backend!.signOut(); await s.refreshAccount(); if (mounted) setState(() { sent = false; loadedUser = null; }); }), child: const Text('Sign out')),
      const SizedBox(height: 16), TextButton(onPressed: s.busy ? null : () async {
        if (await confirm(context, 'Delete your account?', 'This removes your profile and signs you out. Finish or cancel active visits first. Business owners must close their business. Financial records may be retained.', action: 'Delete account')) {
          await s.run(() async { await s.backend!.invoke('delete-account', {}); await s.backend!.signOut(); await s.refreshAccount(); });
        }
      }, child: const Text('Delete account')),
    ]);
  }
}

class OperatorGate extends StatelessWidget {
  const OperatorGate({super.key, required this.store, required this.child});
  final AppStore store;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!store.signedIn) return PageBody(children: [const PageHeading('Your business, in your pocket.', 'Manage appointments and a calmer queue from your phone or tablet.'), Notice('Sign in with your phone to register or manage a business.', action: FilledButton(onPressed: () => openAccount(context, store), child: const Text('Sign in')))]);
    if (!store.unlocked) return PageBody(width: 620, children: [const PageHeading('Protect your business', 'Business and admin access requires an authenticator code.'), MfaPanel(store: store)]);
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
  late Future<List<Json>> factors;
  Json? enrollment;
  @override
  void initState() { super.initState(); factors = widget.store.backend!.factors(); }
  @override
  void dispose() { code.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    if (s.unlocked) return const Notice('Business access is unlocked for this session. Keep your authenticator app available for future sign-ins.');
    return AsyncPanel<List<Json>>(future: factors, retry: () => setState(() => factors = s.backend!.factors()), builder: (items) {
      final verified = items.where((f) => f['status'] == 'verified').toList();
      return Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Text('Authenticator protection', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 12),
        if (verified.isEmpty && enrollment == null) ...[const Text('Add Chairside to an authenticator such as Google Authenticator or Microsoft Authenticator. Store the setup key securely; you’ll need the app to access business tools.'), const SizedBox(height: 12), ActionButton(s, 'Set up authenticator', () async { for (final f in items.where((f) => f['status'] != 'verified')) { await s.backend!.discardFactor(f['id'] as String); } final result = await s.backend!.enrollFactor(); if (mounted) setState(() => enrollment = result); }, icon: Icons.shield_outlined)],
        if (enrollment != null) ...[const Text('In your authenticator choose “Enter setup key”, name it Chairside, and choose time-based codes. Keep this key private.'), const SizedBox(height: 12), SelectableText(enrollment!['secret'] as String), const SizedBox(height: 12)],
        if (verified.isNotEmpty || enrollment != null) ...[FormFieldBox(code, 'Authenticator code', keyboard: TextInputType.number), ActionButton(s, 'Unlock business access', () async { await s.backend!.verifyFactor((enrollment ?? verified.first)['id'] as String, code.text.trim()); code.clear(); enrollment = null; await s.refreshAccount(); }, icon: Icons.lock_open)],
      ]));
    });
  }
}
