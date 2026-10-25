import 'dart:convert';
import 'package:chairside/data/mfa_qr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const svg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="100%" viewBox="0 0 40 40"><path fill="#000" d="M0 0h10v10H0z"/></svg>';

  test('raw SVG remains unchanged', () {
    expect(enrollmentQrSvg(svg), svg);
  });
  test('Supabase SDK data URL preserves colors and literal percentages', () {
    expect(enrollmentQrSvg('data:image/svg+xml;utf-8,$svg'), svg);
  });
  test('percent-encoded SVG data URL is decoded without changing artwork', () {
    expect(
        enrollmentQrSvg(
            'data:image/svg+xml;charset=utf-8,${Uri.encodeComponent(svg)}'),
        svg);
  });
  test('base64 SVG data URL is decoded locally', () {
    expect(
        enrollmentQrSvg(
            'data:image/svg+xml;base64,${base64Encode(utf8.encode(svg))}'),
        svg);
  });
  test('XML declaration from the Supabase SVG generator is retained', () {
    const xml = '<?xml version="1.0"?>\n$svg';
    expect(enrollmentQrSvg('data:image/svg+xml;utf-8,$xml'), xml);
  });
  test('remote URLs and malformed payloads use the safe manual fallback', () {
    for (final source in [
      '',
      'https://example.invalid/private-qr',
      'data:image/png;base64,AAAA',
      'data:image/svg+xml;base64,not-base64!',
      'data:image/svg+xml;utf-8,%ZZ',
      'data:image/svg+xml;utf-8'
    ]) {
      expect(enrollmentQrSvg(source), isNull);
    }
  });
}
