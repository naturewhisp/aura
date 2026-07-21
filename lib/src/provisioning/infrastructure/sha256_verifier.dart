import 'package:crypto/crypto.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_file_system.dart';

/// Helper per la verifica dell'hash SHA-256 di file ed archivi.
abstract class Sha256Verifier {
  /// Calcola l'hash SHA-256 in formato stringa esadecimale minuscola per il file indicato.
  Future<String> calculateSha256(
    String filePath,
    ProvisioningFileSystem fileSystem,
  );

  /// Verifica che il checksum SHA-256 del file corrisponda all'hash atteso.
  /// Lancia [ProvisioningException] con ragione [ProvisioningFailureReason.hashMismatch] se non corrisponde.
  Future<void> verifySha256({
    required String filePath,
    required String expectedSha256,
    required ProvisioningFileSystem fileSystem,
  });
}

/// Implementazione concreta basata su [ProvisioningFileSystem] ed isolata da I/O diretto.
final class DefaultSha256Verifier implements Sha256Verifier {
  const DefaultSha256Verifier();

  @override
  Future<String> calculateSha256(
    String filePath,
    ProvisioningFileSystem fileSystem,
  ) async {
    if (!await fileSystem.fileExists(filePath)) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.hashMismatch,
        message: 'File introvabile per il calcolo del checksum SHA-256.',
      );
    }

    try {
      final bytes = await fileSystem.readAsBytes(filePath);
      final digest = sha256.convert(bytes);
      return digest.toString().toLowerCase();
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.hashMismatch,
        message:
            'Impossibile leggere il file durante il calcolo dell\'hash SHA-256.',
      );
    }
  }

  @override
  Future<void> verifySha256({
    required String filePath,
    required String expectedSha256,
    required ProvisioningFileSystem fileSystem,
  }) async {
    final cleanExpected = expectedSha256.trim().toLowerCase();
    if (cleanExpected.isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.hashMismatch,
        message: 'L\'hash SHA-256 atteso non può essere vuoto.',
      );
    }

    final calculated = await calculateSha256(filePath, fileSystem);
    if (calculated != cleanExpected) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.hashMismatch,
        message:
            'Checksum SHA-256 non corrispondente. Atteso: "$cleanExpected", Calcolato: "$calculated".',
      );
    }
  }
}
