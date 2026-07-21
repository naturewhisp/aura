/// Strategy selected by [ActorOutputSanitizer] to extract clean diegetic text from raw LLM output.
enum ActorOutputExtractionStrategy {
  /// Extracted from a fully closed XML tag (`<dialogo>...</dialogo>` or `<dialogue>...</dialogue>`).
  closedXmlTag,

  /// Extracted from an open/truncated XML tag (`<dialogo>...` or `<dialogue>...`).
  truncatedOpenXmlTag,

  /// Extracted from an end-of-text or last 400-char quote block (`"..."`).
  quotedText,

  /// Extracted following a standard response header (`Response:`, `Final Output:`, `Dialogue:`, `Attacco:`).
  responseHeader,

  /// Extracted from the last item of a numbered list (`3.`, `4.`).
  lastNumberedItem,

  /// Extracted from the last natural lines excluding markdown headers/lists.
  lastNaturalLines,

  /// Full cleaned text passed validation directly without needing structural extraction strategies.
  fullCleanedText,
}
