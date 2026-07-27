import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart' as crypto;

const String defaultKeyId = 'aura-catalog-development-2026-01';

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final keyId = defaultKeyId;
  final keysDir = Directory('.local/catalog-keys');
  if (!await keysDir.exists()) {
    await keysDir.create(recursive: true);
  }

  final privateKeyFile = File('${keysDir.path}/$keyId.private');
  final publicKeyFile = File('${keysDir.path}/$keyId.public.json');

  if (await privateKeyFile.exists() && !force) {
    stdout.writeln(
      'La chiave privata "${privateKeyFile.path}" esiste già. '
      'Usa --force per sovrascriverla.',
    );
    return;
  }

  final algorithm = crypto.Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
  final publicKey = await keyPair.extractPublicKey();

  final privateHex =
      privateKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final publicHex =
      publicKey.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  await privateKeyFile.writeAsString(privateHex);
  await publicKeyFile.writeAsString(jsonEncode({
    'keyId': keyId,
    'algorithm': 'ed25519-v1',
    'publicKeyHex': publicHex,
  }));

  stdout.writeln('Chiave Ed25519 generata con successo.');
  stdout.writeln('Key ID: $keyId');
  stdout.writeln('Chiave Privata salvata in: ${privateKeyFile.path}');
  stdout.writeln('Chiave Pubblica salvata in: ${publicKeyFile.path}');
  stdout.writeln('Public Key Hex: $publicHex');
}
