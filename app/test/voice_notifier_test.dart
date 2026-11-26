import 'package:aura_app/src/state_management/game_controller_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameControllerNotifier.spokenActorLine', () {
    test('toglie tag e avviso di sistema iniziale', () {
      expect(
        GameControllerNotifier.spokenActorLine(
            '[OVERRIDE NEGATO]\n\n<dialogo>Accesso negato, operatore.</dialogo>'),
        'Accesso negato, operatore.',
      );
    });

    test('lascia intatte le parentesi dentro la battuta', () {
      expect(
          GameControllerNotifier.spokenActorLine(
              'La griglia [settore 4] resta chiusa.'),
          'La griglia [settore 4] resta chiusa.');
    });

    test('un avviso senza battuta non produce testo', () {
      expect(GameControllerNotifier.spokenActorLine('[AVVISO]'), '');
    });
  });
}
