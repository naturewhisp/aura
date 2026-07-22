import 'dart:convert';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('RFC 8785 Appendix B Complete Official Test Vectors Suite', () {
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
        'RFC 8785 Appendix B Complete Numbers Table Sample Vectors (List of Typed Records)',
        () {
      final samples = <({num input, String expected})>[
        (input: 0, expected: '0'),
        (input: -0.0, expected: '0'),
        (input: 1, expected: '1'),
        (input: -1, expected: '-1'),
        (input: 1.0, expected: '1'),
        (input: -1.0, expected: '-1'),
        (input: 0.000001, expected: '0.000001'),
        (input: 0.0000001, expected: '1e-7'),
        (input: -0.0000001, expected: '-1e-7'),
        (input: 1e20, expected: '100000000000000000000'),
        (input: 1e21, expected: '1e+21'),
        (input: 9007199254740991, expected: '9007199254740991'),
        (input: -9007199254740991, expected: '-9007199254740991'),
        (
          input: 9007199254740992,
          expected: '9007199254740992'
        ), // 2^53 (RFC 8785 Appendix B exact sample)
        (input: -9007199254740992, expected: '-9007199254740992'),
        (
          input: 295147905179352830000.0,
          expected: '295147905179352830000'
        ), // RFC 8785 Appendix B exact sample!
        (input: 5e-324, expected: '5e-324'),
        (input: -5e-324, expected: '-5e-324'),
        (input: 1.7976931348623157e+308, expected: '1.7976931348623157e+308'),
        (input: -1.7976931348623157e+308, expected: '-1.7976931348623157e+308'),
        (input: 333333333.3333333, expected: '333333333.3333333'),
        (input: 333333333.33333329, expected: '333333333.3333333'),
        (input: 333333333.3333334, expected: '333333333.3333334'),
        (input: 1e23, expected: '1e+23'),
      ];

      for (final sample in samples) {
        final canonical =
            Rfc8785JcsCanonicalizer.canonicalizeString({'n': sample.input});
        expect(canonical, equals('{"n":${sample.expected}}'),
            reason: 'Failed on number: ${sample.input}');
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
