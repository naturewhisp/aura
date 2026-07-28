import 'package:meta/meta.dart';

import 'configured_model_reference.dart';

/// Versione corrente dello schema del disclaimer di consenso informato per modelli esterni.
const int kCurrentExternalModelConsentVersion = 1;

/// Testo canonico del disclaimer di consenso informato per modelli esterni.
const String kExternalModelConsentDisclaimerText =
    'Il modello selezionato non è verificato né gestito da A.U.R.A. '
    'Provenienza, integrità, licenza, compatibilità e requisiti hardware restano responsabilità dell\'utente. '
    'A.U.R.A. non modificherà né eliminerà il file originale e non potrà garantirne aggiornamento, '
    'riparazione o rollback automatici.';

/// DTO che definisce l'assegnazione dei ruoli di inferenza Actor ed Evaluator a riferimenti di modelli gestiti o esterni.
@immutable
final class ModelRoleConfiguration {
  final ConfiguredModelReference? actor;
  final ConfiguredModelReference? evaluator;

  const ModelRoleConfiguration({
    this.actor,
    this.evaluator,
  });

  factory ModelRoleConfiguration.fromJson(Map<String, dynamic> json) {
    final actorMap = json['actor'] as Map<String, dynamic>?;
    final evaluatorMap = json['evaluator'] as Map<String, dynamic>?;

    return ModelRoleConfiguration(
      actor:
          actorMap != null ? ConfiguredModelReference.fromJson(actorMap) : null,
      evaluator: evaluatorMap != null
          ? ConfiguredModelReference.fromJson(evaluatorMap)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (actor != null) 'actor': actor!.toJson(),
      if (evaluator != null) 'evaluator': evaluator!.toJson(),
    };
  }

  ModelRoleConfiguration copyWith({
    Object? actor = _unset,
    Object? evaluator = _unset,
  }) {
    return ModelRoleConfiguration(
      actor: identical(actor, _unset)
          ? this.actor
          : actor as ConfiguredModelReference?,
      evaluator: identical(evaluator, _unset)
          ? this.evaluator
          : evaluator as ConfiguredModelReference?,
    );
  }

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelRoleConfiguration &&
          runtimeType == other.runtimeType &&
          actor == other.actor &&
          evaluator == other.evaluator;

  @override
  int get hashCode => Object.hash(actor, evaluator);

  @override
  String toString() =>
      'ModelRoleConfiguration(actor: $actor, evaluator: $evaluator)';
}

/// DTO immutabile che attesta l'accettazione del consenso informato per modelli esterni non gestiti.
@immutable
final class ExternalModelConsent {
  final int consentVersion;
  final DateTime acceptedAtUtc;

  const ExternalModelConsent({
    required this.consentVersion,
    required this.acceptedAtUtc,
  });

  factory ExternalModelConsent.now({
    int consentVersion = kCurrentExternalModelConsentVersion,
  }) {
    return ExternalModelConsent(
      consentVersion: consentVersion,
      acceptedAtUtc: DateTime.now().toUtc(),
    );
  }

  factory ExternalModelConsent.fromJson(Map<String, dynamic> json) {
    final version = json['consentVersion'] as int?;
    final acceptedStr = json['acceptedAtUtc'] as String?;

    if (version == null || acceptedStr == null) {
      throw const FormatException(
        'Campi "consentVersion" o "acceptedAtUtc" mancanti in ExternalModelConsent.',
      );
    }

    final acceptedAt = DateTime.tryParse(acceptedStr)?.toUtc();
    if (acceptedAt == null) {
      throw const FormatException(
        'Timestamp "acceptedAtUtc" non valido in ExternalModelConsent.',
      );
    }

    return ExternalModelConsent(
      consentVersion: version,
      acceptedAtUtc: acceptedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'consentVersion': consentVersion,
      'acceptedAtUtc': acceptedAtUtc.toUtc().toIso8601String(),
    };
  }

  bool get isValidCurrent =>
      consentVersion == kCurrentExternalModelConsentVersion;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExternalModelConsent &&
          runtimeType == other.runtimeType &&
          consentVersion == other.consentVersion &&
          acceptedAtUtc == other.acceptedAtUtc;

  @override
  int get hashCode => Object.hash(consentVersion, acceptedAtUtc);

  @override
  String toString() =>
      'ExternalModelConsent(version: $consentVersion, acceptedAt: $acceptedAtUtc)';
}

/// DTO che descrive un candidato file GGUF esterno individuato durante uno scan non ricorsivo.
@immutable
final class ExternalModelCandidate {
  final String absolutePath;
  final String fileName;
  final int sizeBytes;
  final DateTime modifiedAtUtc;

  const ExternalModelCandidate({
    required this.absolutePath,
    required this.fileName,
    required this.sizeBytes,
    required this.modifiedAtUtc,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExternalModelCandidate &&
          runtimeType == other.runtimeType &&
          absolutePath == other.absolutePath &&
          fileName == other.fileName &&
          sizeBytes == other.sizeBytes &&
          modifiedAtUtc == other.modifiedAtUtc;

  @override
  int get hashCode => Object.hash(
        absolutePath,
        fileName,
        sizeBytes,
        modifiedAtUtc,
      );

  @override
  String toString() =>
      'ExternalModelCandidate(file: $fileName, size: $sizeBytes)';
}

/// Esito della validazione di un binding di modello per un ruolo specifico.
@immutable
final class ModelBindingValidationResult {
  final bool isValid;
  final ConfiguredModelReference reference;
  final String? errorMessage;

  const ModelBindingValidationResult({
    required this.isValid,
    required this.reference,
    this.errorMessage,
  });

  const ModelBindingValidationResult.valid(this.reference)
      : isValid = true,
        errorMessage = null;

  const ModelBindingValidationResult.invalid(
    this.reference,
    this.errorMessage,
  ) : isValid = false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelBindingValidationResult &&
          runtimeType == other.runtimeType &&
          isValid == other.isValid &&
          reference == other.reference &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(isValid, reference, errorMessage);

  @override
  String toString() =>
      'ModelBindingValidationResult(valid: $isValid, ref: $reference, err: $errorMessage)';
}
