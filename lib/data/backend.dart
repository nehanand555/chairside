import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

typedef Json = Map<String, dynamic>;

/// Transport boundary: widgets can be exercised without live accounts or API keys.
abstract class Backend {
  String? get userId;
  String? get suggestedName => null;
  Stream<void> get authChanges;
  Future<dynamic> rpc(String name, [Json params = const {}]);
  Future<List<Json>> rows(String table, {Json filters = const {}, String? order, int limit = 100});
  Future<void> save(String table, Json values);
  Future<void> initializeProfile(String user, String displayName);
  Future<void> remove(String table, Json filters);
  Future<Json> invoke(String name, Json data);
  Future<void> signInWithGoogle();
  bool get hasVerifiedPhone => false;
  Future<void> signOut();
  Future<List<Json>> factors();
  Future<Json> enrollFactor();
  Future<void> verifyFactor(String id, String code);
  Future<void> discardFactor(String id);
  Future<List<String>> photos(String business);
  Future<void> uploadPhoto(String business, Uint8List bytes, String extension);
  Future<void> deletePhoto(String business, String url);
  void watchVisits(void Function() changed) {}
  void stopWatching() {}
}

class SupabaseBackend extends Backend {
  SupabaseBackend(this.client);
  final SupabaseClient client;
  RealtimeChannel? _channel;
  Timer? _changes;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  String? get suggestedName {
    final metadata = client.auth.currentUser?.userMetadata;
    for (final field in ['full_name', 'name']) {
      final value = metadata?[field];
      if (value is String && value.trim().isNotEmpty) {
        return String.fromCharCodes(value.trim().runes.take(80));
      }
    }
    return null;
  }
  @override
  Stream<void> get authChanges => client.auth.onAuthStateChange.map((_) {});
  @override
  Future<dynamic> rpc(String name, [Json params = const {}]) => client.rpc(name, params: params);
  @override
  Future<List<Json>> rows(String table, {Json filters = const {}, String? order, int limit = 100}) async {
    var query = client.from(table).select();
    for (final entry in filters.entries) { query = query.eq(entry.key, entry.value as Object); }
    final result = order == null ? await query.limit(limit) : await query.order(order, ascending: false).limit(limit);
    return List<Json>.from(result);
  }
  @override
  Future<void> save(String table, Json values) async { await client.from(table).upsert(values); }
  @override
  Future<void> initializeProfile(String user, String displayName) async {
    if (userId != user) return;
    // A simultaneous profile save wins. Never reset names or consent preferences.
    await client.from('profiles').upsert({'id': user, 'display_name': displayName}, onConflict: 'id', ignoreDuplicates: true);
    await client.from('profiles').update({'display_name': displayName}).eq('id', user).eq('display_name', '');
  }
  @override
  Future<void> remove(String table, Json filters) async {
    var query = client.from(table).delete();
    for (final e in filters.entries) { query = query.eq(e.key, e.value as Object); }
    await query;
  }
  @override
  Future<Json> invoke(String name, Json data) async {
    try {
      final result = await client.functions.invoke(name, body: data);
      return Map<String, dynamic>.from(result.data as Map);
    } on FunctionException catch (e) {
      final details = e.details;
      throw Exception(details is Map ? details['error'] ?? 'Service unavailable' : 'Service unavailable. Try again.');
    }
  }
  @override
  Future<void> signInWithGoogle() async {
    final launched = await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? '${Uri.base.origin}/' : 'nz.chairside.chairside://login-callback/',
      authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
    if (!launched) throw Exception('Could not open Google sign-in. Please try again.');
  }
  @override
  bool get hasVerifiedPhone => client.auth.currentUser?.phoneConfirmedAt != null && (client.auth.currentUser?.phone ?? '').isNotEmpty;
  @override
  Future<void> signOut() => client.auth.signOut();
  @override
  Future<List<Json>> factors() async {
    final result = await client.auth.mfa.listFactors();
    return result.all.where((f) => f.factorType == FactorType.totp).map((f) => <String, dynamic>{'id': f.id, 'status': f.status.name}).toList();
  }
  @override
  Future<Json> enrollFactor() async {
    final result = await client.auth.mfa.enroll(factorType: FactorType.totp, friendlyName: 'Chairside business');
    return {'id': result.id, 'secret': result.totp!.secret};
  }
  @override
  Future<void> verifyFactor(String id, String code) async { await client.auth.mfa.challengeAndVerify(factorId: id, code: code); }
  @override
  Future<void> discardFactor(String id) async { await client.auth.mfa.unenroll(id); }
  @override
  Future<List<String>> photos(String business) async {
    final bucket = client.storage.from('portfolios');
    final files = await bucket.list(path: business, searchOptions: const SearchOptions(limit: 20));
    return files.where((f) => f.id != null).map((f) => bucket.getPublicUrl('$business/${f.name}')).toList();
  }
  @override
  Future<void> uploadPhoto(String business, Uint8List bytes, String extension) async {
    if (bytes.length > 5 * 1024 * 1024) throw Exception('Choose an image smaller than 5 MB');
    if (!['jpg', 'jpeg', 'png', 'webp'].contains(extension)) throw Exception('Choose a JPG, PNG or WebP image');
    final type = extension == 'jpg' ? 'jpeg' : extension;
    await client.storage.from('portfolios').uploadBinary('$business/${DateTime.now().microsecondsSinceEpoch}.$extension', bytes, fileOptions: FileOptions(contentType: 'image/$type'));
  }
  @override
  Future<void> deletePhoto(String business, String url) async {
    final name = Uri.parse(url).pathSegments.last;
    await client.storage.from('portfolios').remove(['$business/$name']);
  }
  @override
  void watchVisits(void Function() changed) {
    stopWatching();
    if (userId == null) return;
    _channel = client.channel('my-visits').onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'visits', callback: (_) { _changes?.cancel(); _changes = Timer(const Duration(milliseconds: 200), changed); }).subscribe();
  }
  @override
  void stopWatching() { _changes?.cancel(); final channel = _channel; if (channel != null) { unawaited(client.removeChannel(channel)); } _channel = null; }
}
