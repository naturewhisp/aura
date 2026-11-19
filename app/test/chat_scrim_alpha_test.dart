import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/src/screens/terminal_screen.dart';

double composite(double background, double scrim) =>
    1 - (1 - background) * (1 - scrim);

void main() {
  group('chatScrimAlpha - leggibilità vicino alla vittoria', () {
    test('con sfondo già opaco (pilastri bassi) non aggiunge alcun velo', () {
      expect(chatScrimAlpha(0.92), 0.0);
    });

    test('con sfondo quasi trasparente garantisce l\'opacità minima', () {
      for (final background in [0.15, 0.4, 0.6, 0.84]) {
        expect(
          composite(background, chatScrimAlpha(background)),
          closeTo(kChatMinimumBackdropOpacity, 1e-9),
        );
      }
    });
  });
}
