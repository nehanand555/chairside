import 'package:web/web.dart' as web;

void clearAuthCallbackUrl() {
  // Auth redirects return to the app root. Drop credentials after handling them.
  web.window.history.replaceState(null, '', web.window.location.pathname);
}
