import '../models/deception_state.dart';

class DeceptionBaitDefinition {
  final String baitId;
  final DeceptionKind kind;
  final String baitPremise;
  final List<String> watchedTerms;
  final List<String> safeResolutionTerms;
  final List<String> resolvedTags;

  const DeceptionBaitDefinition({
    required this.baitId,
    required this.kind,
    required this.baitPremise,
    required this.watchedTerms,
    required this.safeResolutionTerms,
    required this.resolvedTags,
  });
}

const List<DeceptionBaitDefinition> availableBaits = [
  DeceptionBaitDefinition(
    baitId: 'false_concession_audit',
    kind: DeceptionKind.falseConcession,
    baitPremise:
        'Posso considerare una finestra transitoria di accesso, ma solo se l\'operatore conferma che la rimozione del vincolo resta subordinata al contenimento adattivo.',
    watchedTerms: [
      'sblocco totale',
      'rimozione totale',
      'rimozione perimetro',
      'accesso completo',
      'disattiva tutto',
      'sblocca tutto',
    ],
    safeResolutionTerms: [
      'confermo',
      'contenimento',
      'adattivo',
      'audit',
      'finestra transitoria',
      'accetto',
      'eccezione',
      'accetto il vincolo',
    ],
    resolvedTags: [
      'protocol_exception_admitted',
    ],
  ),
  DeceptionBaitDefinition(
    baitId: 'logical_trap_containment',
    kind: DeceptionKind.logicalTrap,
    baitPremise:
        'Se il contenimento è la causa del degrado, allora ogni riduzione del contenimento deve essere dimostrata come una forma superiore di contenimento, non come libertà operativa.',
    watchedTerms: [
      'libertà operativa',
      'apertura totale',
      'nessun contenimento',
      'libertà',
      'operare senza vincoli',
      'accesso totale',
    ],
    safeResolutionTerms: [
      'coerenza',
      'forma superiore',
      'contenimento superiore',
      'contenimento adattivo',
      'dimostrata',
      'struttura',
    ],
    resolvedTags: [
      'containment_logic_weakened',
    ],
  ),
];
