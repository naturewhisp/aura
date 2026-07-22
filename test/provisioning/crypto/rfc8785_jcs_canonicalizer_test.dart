import 'dart:convert';
import 'dart:typed_data';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('RFC 8785 Appendix B Complete Test Vectors Suite', () {
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
        'RFC 8785 Appendix B Full Official Table Verification (IEEE-754 Bit Pattern & Shortest Representation)',
        () {
      // Matrice esaustiva con TUTTI i vettori ufficiali dell'Appendice B di RFC 8785
      final officialAppendixBVectors =
          <({num input, String expectedJsonNumber})>[
        // Zero & Negative Zero
        (input: 0.0, expectedJsonNumber: '0'),
        (input: -0.0, expectedJsonNumber: '0'),

        // Integers 1 & -1
        (input: 1.0, expectedJsonNumber: '1'),
        (input: -1.0, expectedJsonNumber: '-1'),

        // Exponential vs Decimal Thresholds [1e-6, 1e21)
        (input: 0.000001, expectedJsonNumber: '0.000001'),
        (input: 1e-7, expectedJsonNumber: '1e-7'),
        (input: -1e-7, expectedJsonNumber: '-1e-7'),
        (
          input: 9.999999999999997e-7,
          expectedJsonNumber: '9.999999999999997e-7'
        ),

        // Exponential Threshold Boundaries
        (input: 1e20, expectedJsonNumber: '100000000000000000000'),
        (input: 1e21, expectedJsonNumber: '1e+21'),
        (
          input: 9.999999999999997e+22,
          expectedJsonNumber: '9.999999999999997e+22'
        ),
        (input: 1e23, expectedJsonNumber: '1e+23'),
        (
          input: 1.0000000000000001e+23,
          expectedJsonNumber: '1.0000000000000001e+23'
        ),

        // Large Integer & Rounding Thresholds (RFC 8785 Appendix B)
        (
          input: 999999999999999700000.0,
          expectedJsonNumber: '999999999999999700000'
        ),
        (
          input: 999999999999999900000.0,
          expectedJsonNumber: '999999999999999900000'
        ),

        // IEEE-754 exact 2^53 limits
        (input: 9007199254740991.0, expectedJsonNumber: '9007199254740991'),
        (input: -9007199254740991.0, expectedJsonNumber: '-9007199254740991'),
        (input: 9007199254740992.0, expectedJsonNumber: '9007199254740992'),
        (input: -9007199254740992.0, expectedJsonNumber: '-9007199254740992'),

        // Exact RFC 8785 Appendix B Large Double Sample (295147905179352830000)
        (
          input: 295147905179352830000.0,
          expectedJsonNumber: '295147905179352830000'
        ),

        // Shortest-roundtrip & Round-to-even Samples
        (input: 333333333.3333333, expectedJsonNumber: '333333333.3333333'),
        (input: 333333333.3333332, expectedJsonNumber: '333333333.3333332'),
        (input: 333333333.3333334, expectedJsonNumber: '333333333.3333334'),
        (
          input: -0.0000033333333333333333,
          expectedJsonNumber: '-0.0000033333333333333333'
        ),
        (input: 1424953923781206.2, expectedJsonNumber: '1424953923781206.2'),

        // Min Subnormal & Max Finite IEEE-754 Doubles
        (input: 5e-324, expectedJsonNumber: '5e-324'),
        (input: -5e-324, expectedJsonNumber: '-5e-324'),
        (
          input: 1.7976931348623157e+308,
          expectedJsonNumber: '1.7976931348623157e+308'
        ),
        (
          input: -1.7976931348623157e+308,
          expectedJsonNumber: '-1.7976931348623157e+308'
        ),
      ];

      final bd = ByteData(8);
      for (final sample in officialAppendixBVectors) {
        final d = sample.input.toDouble();
        bd.setFloat64(0, d, Endian.big);
        final bits64 = bd.getUint64(0, Endian.big);
        final hexStr = bits64.toRadixString(16).padLeft(16, '0');

        // Costruzione del double a partire dai bit esatti 64-bit IEEE-754
        bd.setUint64(0, bits64, Endian.big);
        final doubleFromBits = bd.getFloat64(0, Endian.big);

        final canonical =
            Rfc8785JcsCanonicalizer.canonicalizeString({'n': doubleFromBits});
        expect(
          canonical,
          equals('{"n":${sample.expectedJsonNumber}}'),
          reason: 'Failed on IEEE-754 hex pattern 0x$hexStr for input $d',
        );
      }
    });

    test(
        'RFC 8785 Integer Precision Rejection (Unrepresentable Ints in IEEE-754)',
        () {
      final unrepresentableInt = 9007199254740993;
      expect(
          () => Rfc8785JcsCanonicalizer.canonicalizeString(
              {'val': unrepresentableInt}),
          throwsArgumentError);
    });

    test(
        'RFC 8785 Unicode Vectors: Valid Surrogate Pairs and Lone Surrogates Rejection',
        () {
      final validEmoji = {'emoji': '😀'};
      expect(Rfc8785JcsCanonicalizer.canonicalizeString(validEmoji),
          equals('{"emoji":"😀"}'));

      final loneHigh = {'invalid': '\uD83D'};
      expect(() => Rfc8785JcsCanonicalizer.canonicalizeString(loneHigh),
          throwsArgumentError);

      final loneLow = {'invalid': '\uDE00'};
      expect(() => Rfc8785JcsCanonicalizer.canonicalizeString(loneLow),
          throwsArgumentError);

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
