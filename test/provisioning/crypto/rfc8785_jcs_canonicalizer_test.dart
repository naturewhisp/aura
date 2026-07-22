import 'dart:convert';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('RFC 8785 JCS Canonicalizer Tests', () {
    test(
        'Sorts map properties strictly by UTF-16 code unit lexicographical order',
        () {
      final input = {
        'b': 1,
        'a': 2,
        'A': 3,
        '1': 4,
      };

      final canonicalString = Rfc8785JcsCanonicalizer.canonicalizeString(input);
      expect(canonicalString, equals('{"1":4,"A":3,"a":2,"b":1}'));
    });

    test('Strips whitespace and escapes control characters and quotes', () {
      final input = {
        'text': 'Line1\nLine2\t"Quote" \\ Slash',
        'boolVal': true,
        'nullVal': null,
      };

      final canonicalString = Rfc8785JcsCanonicalizer.canonicalizeString(input);
      expect(
        canonicalString,
        equals(
            '{"boolVal":true,"nullVal":null,"text":"Line1\\nLine2\\t\\"Quote\\" \\\\ Slash"}'),
      );
    });

    test(
        'Serializes numbers deterministically per RFC 8785 (converting -0.0 to 0)',
        () {
      final input = {
        'zero': 0,
        'negZero': -0.0,
        'integer': 42,
        'doubleVal': 3.14,
      };

      final canonicalString = Rfc8785JcsCanonicalizer.canonicalizeString(input);
      expect(canonicalString,
          equals('{"doubleVal":3.14,"integer":42,"negZero":0,"zero":0}'));
    });

    test('Rejects non-finite numbers (NaN, Infinity, -Infinity)', () {
      expect(
        () => Rfc8785JcsCanonicalizer.canonicalizeString({'nan': double.nan}),
        throwsArgumentError,
      );
      expect(
        () => Rfc8785JcsCanonicalizer.canonicalizeString(
            {'inf': double.infinity}),
        throwsArgumentError,
      );
    });

    test('Rejects non-JSON-safe objects or non-string map keys', () {
      expect(
        () => Rfc8785JcsCanonicalizer.canonicalizeString(Object()),
        throwsArgumentError,
      );
      expect(
        () => Rfc8785JcsCanonicalizer.canonicalizeString({123: 'invalidKey'}),
        throwsArgumentError,
      );
    });

    test('Produces deterministic byte-for-byte UTF-8 output', () {
      final payload = {
        'schemaVersion': '1.0',
        'catalogId': 'aura-official-catalog',
        'catalogRevision': 42,
      };

      final bytes = Rfc8785JcsCanonicalizer.canonicalizeBytes(payload);
      final expectedStr =
          '{"catalogId":"aura-official-catalog","catalogRevision":42,"schemaVersion":"1.0"}';
      expect(bytes, equals(utf8.encode(expectedStr)));
    });
  });
}
