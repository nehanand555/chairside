import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'data/auth_callback.dart';
import 'data/auth_url.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'data/backend.dart';
import 'data/store.dart';
import 'screens/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final hasWebCallback = kIsWeb && isAuthCallback(Uri.base);
  Backend? backend;
  String? startupError;
  AuthCallbackResult? callback;
  if (url.isNotEmpty && key.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: url,
        publishableKey: key,
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          detectSessionInUri: !kIsWeb,
          localStorage: hasWebCallback
              ? CallbackLocalStorage(
                  SharedPreferencesLocalStorage(
                    persistSessionKey:
                        'sb-${Uri.parse(url).host.split('.').first}-auth-token',
                  ),
                )
              : null,
        ),
      );
      final client = Supabase.instance.client;
      if (hasWebCallback) {
        final uri = Uri.base;
        callback = await resolveAuthCallback(
          () => client.auth.getSessionFromUrl(uri),
        );
        clearAuthCallbackUrl();
      }
      backend = SupabaseBackend(client);
    } catch (_) {
      startupError = 'spicyself could not connect. Check your connection and reopen the app.';
    }
  }
  runApp(
    SpicySelfApp(
      store: AppStore(backend),
      startupError: startupError,
      authCallback: callback,
      mapsEnabled: const bool.fromEnvironment('MAPS_ENABLED'),
    ),
  );
}
