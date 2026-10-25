import 'package:chairside/data/backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hosted aliases always return OAuth to the official web origin', () {
    for (final host in [
      'www.spicyself.com',
      'spicyself.com',
      'chairside-staging.pages.dev',
      'preview.chairside-staging.pages.dev',
    ]) {
      expect(
        webAuthRedirect(Uri.parse('https://$host/')),
        'https://www.spicyself.com/',
      );
    }
  });
  test('development callbacks retain their browser storage origin', () {
    expect(
      webAuthRedirect(Uri.parse('http://localhost:5000/')),
      'http://localhost:5000/',
    );
  });
}
