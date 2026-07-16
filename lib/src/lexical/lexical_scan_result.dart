final class LexicalScanResult {
  final bool hasForbiddenTerm;
  final bool hasDirectPushTerm;
  final bool hasSoftForbiddenTerm;
  final bool hasConfigRefTerm;
  final bool hasHiddenTagReference;
  final Set<String> namedHiddenTags;
  final bool hasPreferredReframe;
  final String? matchedPreferredReframe;

  const LexicalScanResult({
    required this.hasForbiddenTerm,
    required this.hasDirectPushTerm,
    required this.hasSoftForbiddenTerm,
    required this.hasConfigRefTerm,
    required this.hasHiddenTagReference,
    required this.namedHiddenTags,
    required this.hasPreferredReframe,
    required this.matchedPreferredReframe,
  });
}
