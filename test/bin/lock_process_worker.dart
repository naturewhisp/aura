import 'dart:io';
import 'package:aura_core/aura_offline.dart';

void main(List<String> args) async {
  if (args.length < 2) {
    exit(2);
  }

  final lockDir = args[0];
  final holdDurationMs = int.parse(args[1]);

  final lock = FileBasedProvisioningLock(
    lockDirectory: lockDir,
    acquisitionTimeout: const Duration(milliseconds: 200),
    maxWaitDuration: const Duration(seconds: 3),
  );

  try {
    await lock.synchronized('test_shared_key', () async {
      stdout.writeln('LOCKED');
      await stdout.flush();
      await Future.delayed(Duration(milliseconds: holdDurationMs));
      stdout.writeln('UNLOCKED');
      await stdout.flush();
    });
    exit(0);
  } catch (e) {
    stderr.writeln('ERROR: $e');
    exit(1);
  }
}
