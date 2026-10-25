import 'dart:convert';

/// Decode Supabase enrollment artwork locally. Never fetch or log this payload.
String? enrollmentQrSvg(String source) {
  try {
    var svg = source.trim();
    if (svg.toLowerCase().startsWith('data:')) {
      final comma = svg.indexOf(',');
      if (comma < 0) return null;
      final header = svg.substring(5, comma).toLowerCase();
      if (header.split(';').first != 'image/svg+xml') return null;
      final payload = svg.substring(comma + 1);
      if (header.split(';').contains('base64')) {
        svg = utf8.decode(base64Decode(payload));
      } else if (payload.trimLeft().startsWith('<')) {
        // Supabase's Dart SDK uses a bare `;utf-8` header and raw SVG.
        // Parsing it as a generic URI rejects that header; # colors and literal
        // percent signs must also remain artwork, not URI fragments/escapes.
        svg = payload;
      } else {
        svg = Uri.decodeComponent(payload);
      }
    }
    final markup = svg.trimLeft();
    return markup.startsWith('<svg') || markup.startsWith('<?xml') ? svg : null;
  } catch (_) {
    return null;
  }
}
