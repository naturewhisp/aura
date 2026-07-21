import 'package:meta/meta.dart';

/// Eccezione infrastrutturale interna per fallimenti I/O del filesystem di provisioning.
/// Non espone mai path locali assoluti o dettagli sensibili di sistema.
@immutable
final class ProvisioningIoException implements Exception {
  final String operation;

  const ProvisioningIoException({
    required this.operation,
  });

  @override
  String toString() => 'ProvisioningIoException[$operation]';
}
