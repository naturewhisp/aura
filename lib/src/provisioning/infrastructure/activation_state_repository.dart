import 'dart:convert';
import 'dart:io';
import '../domain/activation_state.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_path_resolver.dart';

/// Contratto astratto I/O per la lettura e scrittura dell'ActivationState.
abstract class ActivationStateRepository {
  /// Legge l'ActivationState memorizzato sul filesystem.
  /// Se il file non esiste ancora, restituisce un [ActivationState.empty].
  Future<ActivationState> readState();

  /// Scrive atomicamente l'ActivationState sul filesystem.
  Future<void> writeState(ActivationState state);
}

/// Implementazione concreta basata su file JSON atomico.
final class JsonActivationStateRepository implements ActivationStateRepository {
  final ProvisioningPathResolver _pathResolver;

  JsonActivationStateRepository({
    required ProvisioningPathResolver pathResolver,
  }) : _pathResolver = pathResolver;

  @override
  Future<ActivationState> readState() async {
    final file = File(_pathResolver.activeStatePath);
    if (!await file.exists()) {
      return ActivationState.empty();
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return ActivationState.empty();
      }
      final jsonMap = jsonDecode(content);
      if (jsonMap is! Map<String, dynamic>) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.activationStateReadFailed,
          message: 'Il contenuto di active_state.json non è un oggetto JSON.',
        );
      }
      return ActivationState.fromJson(jsonMap);
    } on ProvisioningException {
      rethrow;
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.activationStateReadFailed,
        message:
            'Impossibile leggere o decodificare il file active_state.json.',
      );
    }
  }

  @override
  Future<void> writeState(ActivationState state) async {
    final targetFile = File(_pathResolver.activeStatePath);
    final tempFile = File(
        '${_pathResolver.activeStatePath}.tmp_${DateTime.now().microsecondsSinceEpoch}');

    try {
      final parentDir = targetFile.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      final jsonStr =
          const JsonEncoder.withIndent('  ').convert(state.toJson());
      await tempFile.writeAsString(jsonStr, flush: true);

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);
    } catch (_) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.activationStateWriteFailed,
        message: 'Scrittura atomica di active_state.json fallita.',
      );
    }
  }
}
