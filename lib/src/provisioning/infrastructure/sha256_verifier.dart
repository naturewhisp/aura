import 'package:crypto/crypto.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_file_system.dart';

/// Helper per la verifica dell'hash SHA-256 di file ed archivi tramite I/O a chunk (streaming).
abstract class Sha256Verifier {
  /// Calcola in streaming l'hash SHA-256 in formato stringa esadecimale minuscola per il file indicato.
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

/// Implementazione concreta basata su `package:crypto` e streaming I/O.
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
      final stream = fileSystem.openRead(filePath);
      final digest = await sha256.bind(stream).first;
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
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.hashMismatch,
        message: 'Checksum SHA-256 dell\'artefatto non corrispondente.',
      );
    }
  }
}
