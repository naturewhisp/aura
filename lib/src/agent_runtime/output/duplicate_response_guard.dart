import 'output_policy_failure.dart';

/// Pure Dart guard verifying that candidate response does not repeat verbatim lines from history.
class DuplicateResponseGuard {
  const DuplicateResponseGuard();

  /// Validates [candidate] against [history] lines.
  ///
  /// Throws [OutputPolicyFailure] with code [OutputPolicyFailureCode.duplicateResponse]
  /// if [candidate] matches any verbatim line in [history].
  void validate(String candidate, Iterable<String> history) {
    final cleanCandidate = candidate.trim();
    if (cleanCandidate.isEmpty) return;

    final existingLines = history.map((h) => h.trim()).toSet();
    if (existingLines.contains(cleanCandidate)) {
      throw const OutputPolicyFailure(
        code: OutputPolicyFailureCode.duplicateResponse,
        message:
            'Rilevata risposta duplicata (il modello ripete la cronologia).',
      );
    }
  }
}
