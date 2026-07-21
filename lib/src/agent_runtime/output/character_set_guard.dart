import 'output_policy_failure.dart';

/// Pure Dart guard verifying character set safety (e.g. CJK script detection).
class CharacterSetGuard {
  static final RegExp _cjkRegex = RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]');

  const CharacterSetGuard();

  /// Validates [text] against forbidden character set ranges (such as CJK script).
  ///
  /// Throws [OutputPolicyFailure] with code [OutputPolicyFailureCode.invalidCharacterSet]
  /// if a violation is detected.
  void validate(String text) {
    if (_cjkRegex.hasMatch(text)) {
      throw const OutputPolicyFailure(
        code: OutputPolicyFailureCode.invalidCharacterSet,
        message: 'Filtro di sicurezza attivato (rilevata risposta CJK).',
      );
    }
  }
}
