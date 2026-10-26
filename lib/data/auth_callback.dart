import 'package:supabase_flutter/supabase_flutter.dart';

/// Callback failure must never fall through to a previously saved session.
class AuthCallbackResult {
  const AuthCallbackResult({this.userId, this.email});
  final String? userId;
  final String? email;
  bool get succeeded => userId != null;
}

bool isAuthCallback(Uri uri) {
  const keys = [
    'code',
    'error',
    'error_code',
    'error_description',
    'access_token',
  ];
  for (final part in [uri.query, uri.fragment]) {
    try {
      if (keys.any(Uri.splitQueryString(part).containsKey)) return true;
    } on FormatException {
      // A malformed callback still blocks fallback to an existing account.
      if (RegExp(
        r'(^|&)(code|error|error_code|error_description|access_token)(=|&|$)',
      ).hasMatch(part))
        return true;
    }
  }
  return false;
}

Future<AuthCallbackResult> resolveAuthCallback(
  Future<AuthSessionUrlResponse> Function() exchange,
) async {
  try {
    final result = await exchange();
    return AuthCallbackResult(
      userId: result.session.user.id,
      email: result.session.user.email,
    );
  } catch (_) {
    // Never expose callback codes, tokens or provider errors in the UI/logs.
    return const AuthCallbackResult();
  }
}

/// Do not restore another account while processing a new web sign-in callback.
/// Session persistence is separate from PKCE storage: keep the verifier intact.
class CallbackLocalStorage extends LocalStorage {
  CallbackLocalStorage(this.delegate);
  final LocalStorage delegate;
  @override
  Future<void> initialize() async {
    await delegate.initialize();
    await delegate.removePersistedSession();
  }

  @override
  Future<bool> hasAccessToken() async => false;
  @override
  Future<String?> accessToken() async => null;
  @override
  Future<void> persistSession(String value) => delegate.persistSession(value);
  @override
  Future<void> removePersistedSession() => delegate.removePersistedSession();
}
