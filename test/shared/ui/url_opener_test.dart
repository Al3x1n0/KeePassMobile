import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/ui/url_opener.dart';

void main() {
  group('entryUrl (GotoUrl di Keepass2Android, D14)', () {
    test('senza schema o con www.: https://', () {
      expect(
        entryUrl('example.org/login'),
        Uri.parse('https://example.org/login'),
      );
      expect(
        entryUrl('  www.example.org  '),
        Uri.parse('https://www.example.org'),
      );
      expect(entryUrl('WWW.Example.org'), Uri.parse('https://WWW.Example.org'));
    });

    test('http e https restano come sono', () {
      expect(entryUrl('http://example.org'), Uri.parse('http://example.org'));
      expect(
        entryUrl('https://example.org:8443/a?b=1'),
        Uri.parse('https://example.org:8443/a?b=1'),
      );
    });

    test('altri schemi e indirizzi non validi: rifiutati', () {
      for (final value in [
        '',
        '   ',
        'cmd://calc.exe',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'ftp://example.org',
        'mailto:a@example.org',
        'https://',
      ]) {
        expect(entryUrl(value), isNull, reason: value);
      }
    });
  });
}
