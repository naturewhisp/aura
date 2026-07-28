import 'package:meta/meta.dart';

/// Riferimento configurato ad un modello utilizzabile per un ruolo di inferenza (Actor o Evaluator).
///
/// Può consistere in una installazione gestita dal provisioning ([ManagedModelReference])
/// oppure in un file GGUF esterno gestito dall'utente ([ExternalModelReference]).
@immutable
sealed class ConfiguredModelReference {
  const ConfiguredModelReference();

  Map<String, dynamic> toJson();

  factory ConfiguredModelReference.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String?;
    switch (kind) {
      case 'managed':
        return ManagedModelReference.fromJson(json);
      case 'external':
        return ExternalModelReference.fromJson(json);
      default:
        throw FormatException(
            'Tipo di riferimento modello non valido o sconosciuto: "$kind"');
    }
  }
}

/// Riferimento ad un'installazione gestita dal sistema di provisioning di A.U.R.A.
@immutable
final class ManagedModelReference extends ConfiguredModelReference {
  final String installationId;

  ManagedModelReference({required this.installationId}) {
    if (installationId.trim().isEmpty) {
      throw ArgumentError.value(
        installationId,
        'installationId',
        'L\'installationId non può essere vuoto.',
      );
    }
  }

  factory ManagedModelReference.fromJson(Map<String, dynamic> json) {
    final instId = json['installationId'] as String?;
    if (instId == null || instId.trim().isEmpty) {
      throw const FormatException(
        'Campo "installationId" mancante o non valido in ManagedModelReference.',
      );
    }
    return ManagedModelReference(installationId: instId.trim());
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'kind': 'managed',
      'installationId': installationId,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManagedModelReference &&
          runtimeType == other.runtimeType &&
          installationId == other.installationId;

  @override
  int get hashCode => installationId.hashCode;

  @override
  String toString() => 'ManagedModelReference(installationId: $installationId)';
}

/// Riferimento ad un file GGUF esterno gestito dall'utente.
@immutable
final class ExternalModelReference extends ConfiguredModelReference {
  final String absolutePath;

  ExternalModelReference({required this.absolutePath}) {
    if (absolutePath.trim().isEmpty) {
      throw ArgumentError.value(
        absolutePath,
        'absolutePath',
        'Il percorso assoluto non può essere vuoto.',
      );
    }
  }

  factory ExternalModelReference.fromJson(Map<String, dynamic> json) {
    final path = json['absolutePath'] as String?;
    if (path == null || path.trim().isEmpty) {
      throw const FormatException(
        'Campo "absolutePath" mancante o non valido in ExternalModelReference.',
      );
    }
    return ExternalModelReference(absolutePath: path.trim());
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'kind': 'external',
      'absolutePath': absolutePath,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExternalModelReference &&
          runtimeType == other.runtimeType &&
          absolutePath == other.absolutePath;

  @override
  int get hashCode => absolutePath.hashCode;

  @override
  String toString() => 'ExternalModelReference(absolutePath: $absolutePath)';
}
