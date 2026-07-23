import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

/// Esito della validazione del nome visualizzato dell'utente.
@immutable
final class UserProfileValidationResult {
  final bool isValid;
  final String? errorMessage;

  const UserProfileValidationResult._(
      {required this.isValid, this.errorMessage});

  factory UserProfileValidationResult.valid() {
    return const UserProfileValidationResult._(isValid: true);
  }

  factory UserProfileValidationResult.invalid(String message) {
    return UserProfileValidationResult._(isValid: false, errorMessage: message);
  }
}

/// Rappresenta l'identità visualizzata dell'utente finale nel sistema A.U.R.A.
@immutable
final class UserProfile {
  /// Valore predefinito di fallback quando nessun nome è configurato.
  static const String defaultDisplayName = 'Tu';

  /// Limite massimo di grapheme cluster ammessi per il nome visualizzato.
  static const int maxDisplayNameGraphemes = 32;

  /// Il nome visualizzato personalizzato (opzionale, `null` se non impostato o predefinito).
  final String? displayName;

  /// Costruisce un [UserProfile] con il nome visualizzato specificato.
  const UserProfile({this.displayName});

  /// Restituisce il nome visualizzato effettivo:
  /// se [displayName] è nullo o vuoto, restituisce "Tu".
  String get effectiveDisplayName => resolve(displayName);

  /// Normalizza il valore in ingresso: rimuove gli spazi esterni
  /// e restituisce `null` se la stringa risulta vuota.
  static String? normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  /// Risolve il nome di presentazione per un dato valore grezzo o snapshot:
  /// restituisce "Tu" se il valore è nullo, vuoto o composto da soli spazi.
  static String resolve(String? value) {
    final normalized = normalize(value);
    return normalized ?? defaultDisplayName;
  }

  /// Valida la stringa fornita verificando i vincoli di sicurezza e formattazione:
  /// - Non deve contenere caratteri di controllo (\r, \n, \t, C0/C1).
  /// - Non deve contenere sequenze di escape ANSI (\x1B).
  /// - Non deve contenere coppie di surrogate UTF-16 non bilanciate.
  /// - La lunghezza in grapheme cluster (visivi) non deve superare i 32 caratteri.
  static UserProfileValidationResult validate(String? value) {
    final normalized = normalize(value);
    if (normalized == null) {
      return UserProfileValidationResult.valid();
    }

    // 1. Verifica assenza di newline, carriage return o tab
    if (normalized.contains('\n') ||
        normalized.contains('\r') ||
        normalized.contains('\t')) {
      return UserProfileValidationResult.invalid(
        'Il nome non può contenere a capo, ritorni di carrello o tabulazioni.',
      );
    }

    // 2. Verifica assenza di sequenze ESC / ANSI (\x1B)
    if (normalized.contains('\x1B')) {
      return UserProfileValidationResult.invalid(
        'Il nome non può contenere sequenze di escape ANSI.',
      );
    }

    // 3. Verifica assenza di caratteri di controllo C0 (\x00-\x1F, \x7F) e C1 (\x80-\x9F)
    for (final codeUnit in normalized.codeUnits) {
      if ((codeUnit >= 0x00 && codeUnit <= 0x1F) ||
          codeUnit == 0x7F ||
          (codeUnit >= 0x80 && codeUnit <= 0x9F)) {
        return UserProfileValidationResult.invalid(
          'Il nome contiene caratteri di controllo non ammessi.',
        );
      }
    }

    // 4. Verifica surrogate non bilanciate (lone surrogates)
    for (var i = 0; i < normalized.length; i++) {
      final codeUnit = normalized.codeUnitAt(i);
      if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) {
        // High surrogate
        if (i + 1 >= normalized.length) {
          return UserProfileValidationResult.invalid(
            'Il nome contiene una sequenza UTF-16 malformata (high surrogate isolato).',
          );
        }
        final nextUnit = normalized.codeUnitAt(i + 1);
        if (nextUnit < 0xDC00 || nextUnit > 0xDFFF) {
          return UserProfileValidationResult.invalid(
            'Il nome contiene una sequenza UTF-16 malformata (coppia surrogate non valida).',
          );
        }
        i++; // Salta il low surrogate della coppia valida
      } else if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
        // Low surrogate isolato
        return UserProfileValidationResult.invalid(
          'Il nome contiene una sequenza UTF-16 malformata (low surrogate isolato).',
        );
      }
    }

    // 5. Conteggio grapheme cluster tramite package:characters
    if (normalized.characters.length > maxDisplayNameGraphemes) {
      return UserProfileValidationResult.invalid(
        'Il nome non può superare i $maxDisplayNameGraphemes caratteri.',
      );
    }

    return UserProfileValidationResult.valid();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          displayName == other.displayName;

  @override
  int get hashCode => displayName.hashCode;

  @override
  String toString() => 'UserProfile(displayName: $displayName)';
}
