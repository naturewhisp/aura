import 'dart:convert';
import 'dart:typed_data';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('RFC 8785 Appendix B Official IEEE-754 Hex Pattern Certification Suite',
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
        'RFC 8785 Appendix B Full Official Table (100% Exact 26 IEEE-754 Hex Vectors)',
        () {
      // Matrice 100% conforme ed esaustiva dell'Appendice B di RFC 8785:
      // IEEE-754 64-bit Hex Pattern -> Expected Canonical JSON String
      final officialAppendixBTable =
          <({int bits64, String expectedJsonNumber, String description})>[
        (
          bits64: 0x0000000000000000,
          expectedJsonNumber: '0',
          description: 'Zero'
        ),
        (
          bits64: 0x8000000000000000,
          expectedJsonNumber: '0',
          description: 'Minus zero'
        ),
        (
          bits64: 0x0000000000000001,
          expectedJsonNumber: '5e-324',
          description: 'Min pos number'
        ),
        (
          bits64: 0x8000000000000001,
          expectedJsonNumber: '-5e-324',
          description: 'Min neg number'
        ),
        (
          bits64: 0x7fefffffffffffff,
          expectedJsonNumber: '1.7976931348623157e+308',
          description: 'Max pos number'
        ),
        (
          bits64: 0xffefffffffffffff,
          expectedJsonNumber: '-1.7976931348623157e+308',
          description: 'Max neg number'
        ),
        (
          bits64: 0x4340000000000000,
          expectedJsonNumber: '9007199254740992',
          description: 'Max pos int (2^53)'
        ),
        (
          bits64: 0xc340000000000000,
          expectedJsonNumber: '-9007199254740992',
          description: 'Max neg int (-2^53)'
        ),
        (
          bits64: 0x4430000000000000,
          expectedJsonNumber: '295147905179352830000',
          description: '~2^68'
        ),
        (
          bits64: 0x44b52d02c7e14af5,
          expectedJsonNumber: '9.999999999999997e+22',
          description: 'Exponential threshold lower boundary'
        ),
        (
          bits64: 0x44b52d02c7e14af6,
          expectedJsonNumber: '1e+23',
          description: 'Exponential threshold 1e+23'
        ),
        (
          bits64: 0x44b52d02c7e14af7,
          expectedJsonNumber: '1.0000000000000001e+23',
          description: 'Exponential threshold upper boundary'
        ),
        (
          bits64: 0x444b1ae4d6e2ef4e,
          expectedJsonNumber: '999999999999999700000',
          description: 'Rounding threshold 999999999999999700000'
        ),
        (
          bits64: 0x444b1ae4d6e2ef4f,
          expectedJsonNumber: '999999999999999900000',
          description: 'Rounding threshold 999999999999999900000'
        ),
        (
          bits64: 0x444b1ae4d6e2ef50,
          expectedJsonNumber: '1e+21',
          description: '1e+21 threshold'
        ),
        (
          bits64: 0x3eb0c6f7a0b5ed8c,
          expectedJsonNumber: '9.999999999999997e-7',
          description: 'Small exponent lower boundary'
        ),
        (
          bits64: 0x3eb0c6f7a0b5ed8d,
          expectedJsonNumber: '0.000001',
          description: 'Small exponent threshold 0.000001'
        ),
        (
          bits64: 0x41b3de4355555553,
          expectedJsonNumber: '333333333.3333332',
          description: 'Shortest-roundtrip 333333333.3333332'
        ),
        (
          bits64: 0x41b3de4355555554,
          expectedJsonNumber: '333333333.33333325',
          description: 'Shortest-roundtrip 333333333.33333325'
        ),
        (
          bits64: 0x41b3de4355555555,
          expectedJsonNumber: '333333333.3333333',
          description: 'Shortest-roundtrip 333333333.3333333'
        ),
        (
          bits64: 0x41b3de4355555556,
          expectedJsonNumber: '333333333.3333334',
          description: 'Shortest-roundtrip 333333333.3333334'
        ),
        (
          bits64: 0x41b3de4355555557,
          expectedJsonNumber: '333333333.33333343',
          description: 'Shortest-roundtrip 333333333.33333343'
        ),
        (
          bits64: 0xbecbf647612f3696,
          expectedJsonNumber: '-0.0000033333333333333333',
          description: 'Negative small float'
        ),
        (
          bits64: 0x43143ff3c1cb0959,
          expectedJsonNumber: '1424953923781206.2',
          description: 'Round to even'
        ),
      ];

      final bd = ByteData(8);
      for (final sample in officialAppendixBTable) {
        bd.setUint64(0, sample.bits64, Endian.big);
        final d = bd.getFloat64(0, Endian.big);

        final canonical = Rfc8785JcsCanonicalizer.canonicalizeString({'n': d});
        expect(
          canonical,
          equals('{"n":${sample.expectedJsonNumber}}'),
          reason:
              'Failed on IEEE-754 hex pattern 0x${sample.bits64.toRadixString(16).padLeft(16, '0')} (${sample.description})',
        );
      }
    });

    test(
        'RFC 8785 Rejection Vectors: NaN, Infinity, -Infinity (Appendix B 7fffffffffffffff, 7ff0000000000000)',
        () {
      final bd = ByteData(8);

      // NaN: 0x7fffffffffffffff
      bd.setUint64(0, 0x7fffffffffffffff, Endian.big);
      final nanVal = bd.getFloat64(0, Endian.big);
      expect(() => Rfc8785JcsCanonicalizer.canonicalizeString({'v': nanVal}),
          throwsArgumentError);

      // Infinity: 0x7ff0000000000000
      bd.setUint64(0, 0x7ff0000000000000, Endian.big);
      final infVal = bd.getFloat64(0, Endian.big);
      expect(() => Rfc8785JcsCanonicalizer.canonicalizeString({'v': infVal}),
          throwsArgumentError);

      expect(
          () => Rfc8785JcsCanonicalizer.canonicalizeString(
              {'v': double.negativeInfinity}),
          throwsArgumentError);
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
