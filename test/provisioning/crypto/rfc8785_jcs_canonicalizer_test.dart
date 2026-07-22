import 'dart:convert';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group(
      'RFC 8785 Appendix B Official Test Vectors & IEEE-754 Canonicalization Suite',
      () {
    test(
        'RFC 8785 Property Sorting Vector: UTF-16 Code Unit Lexicographical Order',
        () {
      final input = {
        'b': 1,
        'a': 2,
        'A': 3,
        '1': 4,
        '\u00e9': 5, // e-acute
        '\u00e0': 6,
      };

      final canonical = Rfc8785JcsCanonicalizer.canonicalizeString(input);
      expect(
          canonical, equals('{"1":4,"A":3,"a":2,"b":1,"\u00e0":6,"\u00e9":5}'));
    });

    test(
        'RFC 8785 Appendix B Official Sample Vectors (Exact Output Verification)',
        () {
      final samples = <num, String>{
        0: '0',
        -0.0: '0',
        1: '1',
        -1: '-1',
        0.000001: '0.000001',
        0.0000001: '1e-7',
        -0.0000001: '-1e-7',
        1e20: '100000000000000000000',
        1e21: '1e+21',
        9007199254740991: '9007199254740991',
        -9007199254740991: '-9007199254740991',
        9007199254740992:
            '9007199254740992', // 2^53 (RFC 8785 Appendix B exact sample)
        -9007199254740992: '-9007199254740992',
        295147905179352830000.0:
            '295147905179352825856', // Shortest IEEE-754 double representation
        5e-324: '5e-324',
        -5e-324: '-5e-324',
        1.7976931348623157e+308: '1.7976931348623157e+308',
        -1.7976931348623157e+308: '-1.7976931348623157e+308',
      };

      for (final entry in samples.entries) {
        final canonical =
            Rfc8785JcsCanonicalizer.canonicalizeString({'n': entry.key});
        expect(canonical, equals('{"n":${entry.value}}'),
            reason: 'Failed on number: ${entry.key}');
      }
    });

    test(
        'RFC 8785 Integer Precision Rejection (Unrepresentable Ints in IEEE-754)',
        () {
      // 9007199254740993 is not representable as an exact IEEE-754 double (rounds to 9007199254740992)
      final unrepresentableInt = 9007199254740993;
      expect(
          () => Rfc8785JcsCanonicalizer.canonicalizeString(
              {'val': unrepresentableInt}),
          throwsArgumentError);
    });

    test(
        'RFC 8785 Unicode Vectors: Valid Surrogate Pairs and Lone Surrogates Rejection',
        () {
      // Valid UTF-16 surrogate pair (emoji 😀 U+1F600: \uD83D\uDE00)
      final validEmoji = {'emoji': '😀'};
      expect(Rfc8785JcsCanonicalizer.canonicalizeString(validEmoji),
          equals('{"emoji":"😀"}'));

      // High surrogate isolato (lone high surrogate)
      final loneHigh = {'invalid': '\uD83D'};
      expect(() => Rfc8785JcsCanonicalizer.canonicalizeString(loneHigh),
          throwsArgumentError);

      // Low surrogate isolato (lone low surrogate)
      final loneLow = {'invalid': '\uDE00'};
      expect(() => Rfc8785JcsCanonicalizer.canonicalizeString(loneLow),
          throwsArgumentError);

      // High surrogate seguito da carattere non-low surrogate
      final malformedPair = {'invalid': '\uD83DA'};
      expect(() => Rfc8785JcsCanonicalizer.canonicalizeString(malformedPair),
          throwsArgumentError);
    });

    test('RFC 8785 Rejection Vectors: NaN, Infinity, -Infinity', () {
      expect(
          () => Rfc8785JcsCanonicalizer.canonicalizeString({'v': double.nan}),
          throwsArgumentError);
      expect(
          () => Rfc8785JcsCanonicalizer.canonicalizeString(
              {'v': double.infinity}),
          throwsArgumentError);
      expect(
          () => Rfc8785JcsCanonicalizer.canonicalizeString(
              {'v': double.negativeInfinity}),
          throwsArgumentError);
    });

    test(
        'RFC 8785 String Escaping Vectors: Control Characters and Special Quotes',
        () {
      final input = {
        'str': 'Line1\nLine2\rLine3\tTab "Quote" \\ Backslash',
      };
      final canonical = Rfc8785JcsCanonicalizer.canonicalizeString(input);
      expect(
          canonical,
          equals(
              '{"str":"Line1\\nLine2\\rLine3\\tTab \\"Quote\\" \\\\ Backslash"}'));
    });

    test('RFC 8785 UTF-8 Output Representation', () {
      final input = {
        'catalogId': 'aura-official-catalog',
        'catalogRevision': 42,
        'schemaVersion': '1.0',
      };

      final bytes = Rfc8785JcsCanonicalizer.canonicalizeBytes(input);
      final expectedStr =
          '{"catalogId":"aura-official-catalog","catalogRevision":42,"schemaVersion":"1.0"}';
      expect(bytes, equals(utf8.encode(expectedStr)));
    });
  });
}
