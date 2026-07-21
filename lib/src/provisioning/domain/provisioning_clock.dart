import 'package:meta/meta.dart';

/// Abilitatore deterministico per l'interrogazione dell'ora UTC nel sistema di provisioning.
@immutable
abstract interface class ProvisioningClock {
  /// Restituisce la data e l'ora correnti in UTC.
  DateTime nowUtc();
}

/// Implementazione predefinita del clock basata sull'orologio di sistema.
final class SystemProvisioningClock implements ProvisioningClock {
  const SystemProvisioningClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// Clock deterministico finto da utilizzare nei test unitari.
final class TestProvisioningClock implements ProvisioningClock {
  final DateTime _fixedUtcTime;

  TestProvisioningClock(DateTime utcTime) : _fixedUtcTime = utcTime.toUtc();

  @override
  DateTime nowUtc() => _fixedUtcTime;
}
