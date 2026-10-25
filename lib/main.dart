import 'package:flutter/material.dart';

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
  Backend? backend;
  String? startupError;
  if (url.isNotEmpty && key.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: url,
        publishableKey: key,
        authOptions:
            const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
      );
      backend = SupabaseBackend(Supabase.instance.client);
    } catch (_) {
      startupError =
          'spicyself could not connect. Check your connection and reopen the app.';
    }
  }
  runApp(SpicySelfApp(
      store: AppStore(backend),
      startupError: startupError,
      mapsEnabled: const bool.fromEnvironment('MAPS_ENABLED')));
}
