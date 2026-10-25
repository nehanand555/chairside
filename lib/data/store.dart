import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'backend.dart';

class AppStore extends ChangeNotifier {
  AppStore(this.backend) {
    _auth = backend?.authChanges.listen((_) {
      unawaited(refreshAccount());
    }, onError: (Object e) {
      error = friendlyError(e);
      changed();
    });
    if (signedIn) unawaited(refreshAccount());
  }
  final Backend? backend;
  StreamSubscription<void>? _auth;
  Json profile = {};
  Json account = {};
  List<Json> visits = [];
  List<String> favorites = [];
  bool moreVisits = false;
  String? error;
  String? applicationNotificationMessage;
  bool busy = false;
  bool _disposed = false;
  int _revision = 0;
  int _visitPages = 1;
  int _visitRevision = 0;
  int _sessionRevision = 0;
  int get sessionRevision => _sessionRevision;
  bool isCurrentSession(int revision, String? user) =>
      !_disposed && revision == _sessionRevision && backend?.userId == user;
  String? _lastUser;
  bool get configured => backend != null;
  bool get signedIn => backend?.userId != null;
  String get displayName {
    if (!signedIn) return '';
    if (!_accountMatchesUser) return backend?.suggestedName ?? '';
    final saved = (profile['display_name'] as String? ?? '').trim();
    return saved.isNotEmpty ? saved : backend?.suggestedName ?? '';
  }

  // Never reuse privileged UI state across sign-out or an account switch.
  // The server independently enforces role and MFA on every admin RPC.
  bool get _accountMatchesUser => signedIn && _lastUser == backend?.userId;
  bool get hasCurrentAccount => _accountMatchesUser;
  bool get unlocked => _accountMatchesUser && account['aal2'] == true;
  bool get isAdmin => _accountMatchesUser && account['is_admin'] == true;
  String? get businessId =>
      _accountMatchesUser ? account['business_id'] as String? : null;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  void clearError() {
    error = null;
    changed();
  }

  Future<bool> run(Future<void> Function() action) async {
    if (busy) return false;
    final session = _sessionRevision;
    final user = backend?.userId;
    busy = true;
    error = null;
    changed();
    try {
      await action();
      return isCurrentSession(session, user);
    } catch (e) {
      if (isCurrentSession(session, user)) error = friendlyError(e);
      return false;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> refreshAccount() async {
    final revision = ++_revision;
    if (_lastUser != backend?.userId) {
      _lastUser = backend?.userId;
      _sessionRevision++;
      _visitRevision++;
      backend?.stopWatching();
      error = null;
      applicationNotificationMessage = null;
      _visitPages = 1;
      profile = {};
      account = {};
      visits = [];
      favorites = [];
      moreVisits = false;
      changed();
    }
    if (!signedIn) {
      profile = {};
      account = {};
      visits = [];
      favorites = [];
      moreVisits = false;
      backend?.stopWatching();
      changed();
      return;
    }
    try {
      final user = backend!.userId!;
      final suggestedName = backend!.suggestedName;
      final context = await backend!.rpc('account_context') as Map;
      var profiles = await backend!.rows('profiles', filters: {'id': user});
      if (_disposed || revision != _revision || backend!.userId != user) return;
      if ((profiles.isEmpty ||
              (profiles.first['display_name'] as String? ?? '').isEmpty) &&
          suggestedName != null &&
          suggestedName.isNotEmpty) {
        await backend!.initializeProfile(user, suggestedName);
        profiles = await backend!.rows('profiles', filters: {'id': user});
      }
      final saved =
          await backend!.rows('favorites', filters: {'customer_id': user});
      if (_disposed || revision != _revision || backend!.userId != user) return;
      account = Json.from(context);
      profile = profiles.isEmpty ? {} : profiles.first;
      favorites = saved.map((r) => r['business_id'] as String).toList();
      changed();
      backend!.watchVisits(() {
        unawaited(refreshVisits());
      });
      await refreshVisits();
    } catch (e) {
      if (revision == _revision) {
        error = friendlyError(e);
        changed();
      }
    }
  }

  Future<void> refreshVisits() async {
    if (!signedIn) return;
    final user = backend!.userId;
    final session = _sessionRevision;
    final revision = ++_visitRevision;
    final pages = _visitPages;
    try {
      await backend!.rpc('refresh_queues');
      final result = <Json>[];
      int count = 0;
      for (var page = 0; page < pages; page++) {
        if (!isCurrentSession(session, user) || revision != _visitRevision)
          return;
        final rows = List<Json>.from(
            await backend!.rpc('my_visits', {'p_offset': page * 200}) as List);
        result.addAll(rows);
        count = rows.length;
        if (count < 200) break;
      }
      if (isCurrentSession(session, user) && revision == _visitRevision) {
        visits = {for (final v in result) v['id']: v}.values.toList();
        moreVisits = count == 200;
        changed();
      }
    } catch (e) {
      if (isCurrentSession(session, user) && revision == _visitRevision) {
        error = friendlyError(e);
        changed();
      }
    }
  }

  Future<void> loadMoreVisits() async {
    if (!signedIn || !moreVisits) return;
    final user = backend!.userId;
    final session = _sessionRevision;
    final revision = _visitRevision;
    final page = _visitPages;
    final result = List<Json>.from(
        await backend!.rpc('my_visits', {'p_offset': page * 200}) as List);
    if (!isCurrentSession(session, user) ||
        revision != _visitRevision ||
        page != _visitPages) return;
    _visitPages++;
    final known = visits.map((v) => v['id']).toSet();
    visits.addAll(result.where((v) => !known.contains(v['id'])));
    moreVisits = result.length == 200;
    changed();
  }

  Future<void> saveProfile(String name, bool sms, bool marketing) async {
    if (name.trim().isEmpty) throw Exception('Enter your name');
    await backend!.save('profiles', {
      'id': backend!.userId,
      'display_name': name.trim(),
      'sms_updates': sms,
      'marketing_consent': marketing
    });
    await refreshAccount();
  }

  Future<void> favorite(String id) async {
    if (!signedIn) throw Exception('Sign in to save a favourite');
    final filters = {'customer_id': backend!.userId, 'business_id': id};
    if (favorites.contains(id)) {
      await backend!.remove('favorites', filters);
    } else {
      await backend!.save('favorites', filters);
    }
    await refreshAccount();
  }

  Future<void> changeVisit(String id, String action) async {
    await backend!.rpc('change_visit', {'p_visit': id, 'p_action': action});
    await refreshVisits();
  }

  @override
  void dispose() {
    _disposed = true;
    _auth?.cancel();
    backend?.stopWatching();
    super.dispose();
  }
}

String friendlyError(Object e) {
  if (e is AuthException) return e.message;
  if (e is PostgrestException) return e.message;
  final text = e.toString().replaceFirst('Exception: ', '');
  if (text.contains('SocketException') || text.contains('ClientException'))
    return 'Connection lost. Check your internet and try again.';
  return text;
}
