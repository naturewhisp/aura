import 'catalog_acquisition_models.dart';

/// Stato di compatibilità dell'applicazione rispetto ad un catalogo.
enum CatalogCompatibilityStatus {
  compatible,
  unsupportedSchema,
  applicationTooOld,
  applicationTooNew,
  constraintsUnavailable,
}

/// DTO contenente l'esito della valutazione di compatibilità applicativa.
final class CatalogCompatibilityResult {
  final CatalogCompatibilityStatus status;
  final String? message;

  const CatalogCompatibilityResult({
    required this.status,
    this.message,
  });

  bool get isCompatible =>
      status == CatalogCompatibilityStatus.compatible ||
      status == CatalogCompatibilityStatus.constraintsUnavailable;

  @override
  String toString() =>
      'CatalogCompatibilityResult(status: $status, message: $message)';
}

/// Contratto ed implementazione per la valutazione della compatibilità applicativa di un catalogo.
abstract interface class CatalogCompatibilityEvaluator {
  CatalogCompatibilityResult evaluate({
    required CatalogSignedPayload payload,
    required String applicationVersion,
  });
}

/// Implementazione predefinita di [CatalogCompatibilityEvaluator].
final class DefaultCatalogCompatibilityEvaluator
    implements CatalogCompatibilityEvaluator {
  const DefaultCatalogCompatibilityEvaluator();

  @override
  CatalogCompatibilityResult evaluate({
    required CatalogSignedPayload payload,
    required String applicationVersion,
  }) {
    // 1. Verifica della versione dello schema del catalogo
    if (payload.schemaVersion != '1.0') {
      return CatalogCompatibilityResult(
        status: CatalogCompatibilityStatus.unsupportedSchema,
        message: 'Versione di schema non supportata: ${payload.schemaVersion}',
      );
    }

    // Se il manifest non specifica vincoli min/max nei DTO 6.3, si restituisce constraintsUnavailable
    return const CatalogCompatibilityResult(
      status: CatalogCompatibilityStatus.constraintsUnavailable,
      message:
          'Nessun vincolo di versione applicativa specificato nel manifest.',
    );
  }
}
