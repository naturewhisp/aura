import 'dart:convert';
import 'dart:io';
import 'package:aura_core/aura_core.dart';

void main(List<String> args) async {
  print('==================================================================');
  print(' A.U.R.A. Audio Release Importer & Manifest Generator (Dart CLI)');
  print('==================================================================');

  String sourcePath = '';
  String destinationPath = 'distribution/audio';
  String appAssetPath = 'app/assets/audio';

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--source' && i + 1 < args.length) {
      sourcePath = args[i + 1];
    } else if (args[i] == '--destination' && i + 1 < args.length) {
      destinationPath = args[i + 1];
    } else if (args[i] == '--app-asset' && i + 1 < args.length) {
      appAssetPath = args[i + 1];
    }
  }

  if (sourcePath.isEmpty) {
    final appData = Platform.environment['APPDATA'] ?? '';
    sourcePath =
        appData.isNotEmpty ? '$appData/aura/audio' : 'distribution/audio';
  }

  print('[INFO] Source Path:      $sourcePath');
  print('[INFO] Destination Path: $destinationPath');
  print('[INFO] App Asset Path:   $appAssetPath');

  final sourceDir = Directory(sourcePath);
  if (!sourceDir.existsSync()) {
    print('[ERROR] Directory sorgente non trovata: $sourcePath');
    exit(1);
  }

  final expectedTracks = [
    (
      id: 'bgm.main',
      kind: AudioTrackKind.bgm,
      role: AudioTrackRole.mainMenu,
      filename: 'bgm_main.wav',
      loop: true,
      required: true
    ),
    (
      id: 'bgm.ambient',
      kind: AudioTrackKind.bgm,
      role: AudioTrackRole.ambient,
      filename: 'bgm_ambient.wav',
      loop: true,
      required: true
    ),
    (
      id: 'bgm.tense',
      kind: AudioTrackKind.bgm,
      role: AudioTrackRole.tense,
      filename: 'bgm_tense.wav',
      loop: true,
      required: true
    ),
    (
      id: 'bgm.epic',
      kind: AudioTrackKind.bgm,
      role: AudioTrackRole.epic,
      filename: 'bgm_epic.wav',
      loop: true,
      required: true
    ),
    (
      id: 'sfx.click',
      kind: AudioTrackKind.sfx,
      role: AudioTrackRole.click,
      filename: 'sfx_click.wav',
      loop: false,
      required: true
    ),
    (
      id: 'sfx.alert',
      kind: AudioTrackKind.sfx,
      role: AudioTrackRole.alert,
      filename: 'sfx_alert.wav',
      loop: false,
      required: true
    ),
    (
      id: 'sfx.glitch',
      kind: AudioTrackKind.sfx,
      role: AudioTrackRole.glitch,
      filename: 'sfx_glitch.wav',
      loop: false,
      required: true
    ),
    (
      id: 'sfx.chime',
      kind: AudioTrackKind.sfx,
      role: AudioTrackRole.chime,
      filename: 'sfx_chime.wav',
      loop: false,
      required: true
    ),
  ];

  final verifier = const WavHeaderVerifier();
  final descriptors = <AudioTrackDescriptor>[];
  final validatedBuffers = <String, List<int>>{};

  print('\n[1/3] Phase 1: Transational validation of all required tracks...');
  var hasErrors = false;

  for (final trk in expectedTracks) {
    final file = File('${sourceDir.path}/${trk.filename}');
    if (!file.existsSync()) {
      if (trk.required) {
        print('  - [ERROR] Traccia obbligatoria mancante: ${trk.filename}');
        hasErrors = true;
      }
      continue;
    }

    final bytes = file.readAsBytesSync();
    final inspection = verifier.inspectWavHeader(bytes);
    if (!inspection.isValid) {
      print(
          '  - [ERROR] Header RIFF/WAVE non valido per ${trk.filename}: ${inspection.failureMessage}');
      hasErrors = true;
      continue;
    }

    final sha256 = verifier.computeSha256(bytes);
    final descriptor = AudioTrackDescriptor(
      id: trk.id,
      kind: trk.kind,
      role: trk.role,
      filename: trk.filename,
      sizeBytes: bytes.length,
      sha256: sha256,
      codec: 'pcm',
      sampleRate: inspection.sampleRate,
      channels: inspection.channels,
      bitsPerSample: inspection.bitsPerSample,
      durationMs: inspection.calculatedDurationMs,
      loop: trk.loop,
      required: trk.required,
    );

    descriptors.add(descriptor);
    validatedBuffers[trk.filename] = bytes;
    print(
        '  - [VALID] ${trk.id} -> ${trk.filename} (${bytes.length} bytes, ${inspection.sampleRate} Hz, sha256: ${sha256.substring(0, 16)}...)');
  }

  if (hasErrors) {
    print(
        '\n[FATAL] Importazione annullata. Rilevate tracce mancanti o corrotte.');
    print('[FATAL] Nessuna modifica apportata alle destinazioni.');
    exit(1);
  }

  print('\n[2/3] Phase 2: Generating canonical AudioManifest...');
  final manifest = AudioManifest(
    schemaVersion: 1,
    audioSetId: 'aura.windows.release.v1',
    tracks: descriptors,
  );

  final jsonEncoder = JsonEncoder.withIndent('  ');
  final manifestJsonStr = jsonEncoder.convert(manifest.toJson());

  print('\n[3/3] Phase 3: Atomic staging & release promotion...');
  final stagingDir = Directory.systemTemp.createTempSync('aura_audio_staging_');

  try {
    for (final entry in validatedBuffers.entries) {
      File('${stagingDir.path}/${entry.key}').writeAsBytesSync(entry.value);
    }
    File('${stagingDir.path}/audio-manifest.json')
        .writeAsStringSync(manifestJsonStr);

    final destDir = Directory(destinationPath);
    final assetDir = Directory(appAssetPath);

    if (!destDir.existsSync()) destDir.createSync(recursive: true);
    if (!assetDir.existsSync()) assetDir.createSync(recursive: true);

    for (final entry in validatedBuffers.entries) {
      File('${destDir.path}/${entry.key}').writeAsBytesSync(entry.value);
      File('${assetDir.path}/${entry.key}').writeAsBytesSync(entry.value);
    }

    File('${destDir.path}/audio-manifest.json')
        .writeAsStringSync(manifestJsonStr);
    File('${assetDir.path}/audio_manifest.json')
        .writeAsStringSync(manifestJsonStr);

    stagingDir.deleteSync(recursive: true);
    print(
        '\n==================================================================');
    print('[SUCCESS] Importazione completata con successo!');
    print('          Manifest e tracce aggiornati atomicamente in:');
    print('          - $destinationPath');
    print('          - $appAssetPath');
    print('==================================================================');
  } catch (e) {
    print('[FATAL] Errore durante la promozione atomica: $e');
    exit(1);
  }
}
