import 'dart:convert';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('RFC 8785 Appendix B & IEEE-754 Official JCS Canonicalization Suite',
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

    test('RFC 8785 Numeric Vectors: Zero and Negative Zero (-0.0 -> "0")', () {
      expect(Rfc8785JcsCanonicalizer.canonicalizeString({'val': 0}),
          equals('{"val":0}'));
      expect(Rfc8785JcsCanonicalizer.canonicalizeString({'val': -0.0}),
          equals('{"val":0}'));
    });

    test(
        'RFC 8785 Numeric Vectors: I-JSON / IEEE-754 Safe Integer Range Boundaries (2^53 - 1)',
        () {
      final maxSafe = 9007199254740991;
      final minSafe = -9007199254740991;

      expect(Rfc8785JcsCanonicalizer.canonicalizeString({'max': maxSafe}),
          equals('{"max":9007199254740991}'));
      expect(Rfc8785JcsCanonicalizer.canonicalizeString({'min': minSafe}),
          equals('{"min":-9007199254740991}'));

      // Reiezione di interi oltre il limite interoperabile I-JSON
      expect(
          () => Rfc8785JcsCanonicalizer.canonicalizeString(
              {'unsafe': 9007199254740992}),
          throwsArgumentError);
      expect(
          () => Rfc8785JcsCanonicalizer.canonicalizeString(
              {'unsafe': -9007199254740992}),
          throwsArgumentError);
    });

    test(
        'RFC 8785 Numeric Vectors: Floating Point, Subnormal and Exponential Notation Boundaries',
        () {
      // Minimum positive double in IEEE-754
      expect(Rfc8785JcsCanonicalizer.canonicalizeString({'subnormal': 5e-324}),
          equals('{"subnormal":5e-324}'));

      // Exponential thresholds [1e-6, 1e21)
      expect(Rfc8785JcsCanonicalizer.canonicalizeString({'num': 0.000001}),
          equals('{"num":0.000001}'));
      expect(Rfc8785JcsCanonicalizer.canonicalizeString({'num': 1e20}),
          equals('{"num":100000000000000000000}'));
      expect(Rfc8785JcsCanonicalizer.canonicalizeString({'small': 0.0000001}),
          equals('{"small":1e-7}'));
      expect(Rfc8785JcsCanonicalizer.canonicalizeString({'large': 1e21}),
          equals('{"large":1e+21}'));
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
