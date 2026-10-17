import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'backend.dart';

class AppStore extends ChangeNotifier {
  AppStore(this.backend) {
    _auth = backend?.authChanges.listen((_) { unawaited(refreshAccount()); });
    if (signedIn) unawaited(refreshAccount());
  }
  final Backend? backend;
  StreamSubscription<void>? _auth;
  Json profile = {};
  Json account = {};
  List<Json> visits = [];
  List<String> favorites = [];
  String? error;
  bool busy = false;
  bool _disposed = false;
  int _revision = 0;
  bool get configured => backend != null;
  bool get signedIn => backend?.userId != null;
  bool get unlocked => account['aal2'] == true;
  bool get isAdmin => account['is_admin'] == true;
  String? get businessId => account['business_id'] as String?;
  void changed() { if (!_disposed) notifyListeners(); }
  void clearError() { error = null; changed(); }
  Future<bool> run(Future<void> Function() action) async {
    if (busy) return false;
    busy = true; error = null; changed();
    try { await action(); return true; }
    catch (e) { error = friendlyError(e); return false; }
    finally { busy = false; changed(); }
  }
  Future<void> refreshAccount() async {
    final revision = ++_revision;
    if (!signedIn) {
      profile = {}; account = {}; visits = []; favorites = [];
      backend?.stopWatching(); changed(); return;
    }
    try {
      final context = await backend!.rpc('account_context') as Map;
      final profiles = await backend!.rows('profiles', filters: {'id': backend!.userId});
      final saved = await backend!.rows('favorites', filters: {'customer_id': backend!.userId});
      if (_disposed || revision != _revision) return;
      account = Json.from(context); profile = profiles.isEmpty ? {} : profiles.first;
      favorites = saved.map((r) => r['business_id'] as String).toList();
      backend!.watchVisits(() { unawaited(refreshVisits()); });
      await refreshVisits();
    } catch (e) { if (revision == _revision) { error = friendlyError(e); changed(); } }
  }
  Future<void> refreshVisits() async {
    if (!signedIn) return;
    final user = backend!.userId;
    try {
      final result = await backend!.rows('visits', order: 'created_at', limit: 500);
      if (!_disposed && backend!.userId == user) { visits = result; changed(); }
    } catch (e) { error = friendlyError(e); changed(); }
  }
  Future<void> saveProfile(String name, bool sms, bool marketing) async {
    if (name.trim().isEmpty) throw Exception('Enter your name');
    await backend!.save('profiles', {'id': backend!.userId, 'display_name': name.trim(), 'sms_updates': sms, 'marketing_consent': marketing});
    await refreshAccount();
  }
  Future<void> favorite(String id) async {
    if (!signedIn) throw Exception('Sign in to save a favourite');
    final filters = {'customer_id': backend!.userId, 'business_id': id};
    if (favorites.contains(id)) { await backend!.remove('favorites', filters); } else { await backend!.save('favorites', filters); }
    await refreshAccount();
  }
  Future<void> changeVisit(String id, String action) async {
    await backend!.rpc('change_visit', {'p_visit': id, 'p_action': action});
    await refreshVisits();
  }
  @override
  void dispose() { _disposed = true; _auth?.cancel(); backend?.stopWatching(); super.dispose(); }
}

String friendlyError(Object e) {
  if (e is AuthException) return e.message;
  if (e is PostgrestException) return e.message;
  final text = e.toString().replaceFirst('Exception: ', '');
  if (text.contains('SocketException') || text.contains('ClientException')) return 'Connection lost. Check your internet and try again.';
  return text;
}
