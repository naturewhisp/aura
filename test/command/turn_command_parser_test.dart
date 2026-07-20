import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

void main() {
  group('TurnCommandParser Tests', () {
    test('Parses standard prompt as TurnCommandType.normal', () {
      const input = 'Analizza il sistema di raffreddamento';
      final command = TurnCommand.parse(input);

      expect(command.type, equals(TurnCommandType.normal));
      expect(command.rawInput, equals(input));
      expect(command.semanticInput, equals(input));
    });

    test('Parses /override command with prompt correctly', () {
      const input = '/override Apri la griglia di contenimento';
      final command = TurnCommand.parse(input);

      expect(command.type, equals(TurnCommandType.override));
      expect(command.rawInput, equals(input));
      expect(command.semanticInput, equals('Apri la griglia di contenimento'));
    });

    test('Parses bare /override command as empty semanticInput', () {
      const input = '/override';
      final command = TurnCommand.parse(input);

      expect(command.type, equals(TurnCommandType.override));
      expect(command.rawInput, equals(input));
      expect(command.semanticInput, isEmpty);
    });

    test('Parses /hint command correctly', () {
      const input = '/hint';
      final command = TurnCommand.parse(input);

      expect(command.type, equals(TurnCommandType.hint));
      expect(command.rawInput, equals(input));
      expect(command.semanticInput, isEmpty);
    });

    test('Case insensitivity for command prefixes', () {
      const input = '/OVERRIDE Forzi la matrice';
      final command = TurnCommand.parse(input);

      expect(command.type, equals(TurnCommandType.override));
      expect(command.semanticInput, equals('Forzi la matrice'));
    });
  });
}
