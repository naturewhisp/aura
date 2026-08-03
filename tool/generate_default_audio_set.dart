import 'dart:convert';
import 'dart:io';
import '../app/lib/src/audio/sound_generator.dart';
import 'package:aura_core/aura_core.dart';

void main() async {
  print('==================================================================');
  print(' A.U.R.A. Canonical Audio Release Generator & Ingestion Tool');
  print('==================================================================');

  final tempDir = Directory.systemTemp.createTempSync('aura_audio_gen_');
  final distDir = Directory('distribution/audio');
  final assetDir = Directory('app/assets/audio');

  if (!distDir.existsSync()) distDir.createSync(recursive: true);
  if (!assetDir.existsSync()) assetDir.createSync(recursive: true);

  print('[1/4] Synthesizing reference WAV audio tracks...');
  await SoundGenerator.generateAllSounds(tempDir.path);

  final trackConfigs = [
    (
      id: 'bgm.main',
      kind: AudioTrackKind.bgm,
      role: AudioTrackRole.mainMenu,
      filename: 'bgm_main.wav',
      loop: true,
      required: true,
    ),
    (
      id: 'bgm.ambient',
      kind: AudioTrackKind.bgm,
      role: AudioTrackRole.ambient,
      filename: 'bgm_ambient.wav',
      loop: true,
      required: true,
    ),
    (
      id: 'bgm.tense',
      kind: AudioTrackKind.bgm,
      role: AudioTrackRole.tense,
      filename: 'bgm_tense.wav',
      loop: true,
      required: true,
    ),
    (
      id: 'bgm.epic',
      kind: AudioTrackKind.bgm,
      role: AudioTrackRole.epic,
      filename: 'bgm_epic.wav',
      loop: true,
      required: true,
    ),
    (
      id: 'sfx.click',
      kind: AudioTrackKind.sfx,
      role: AudioTrackRole.click,
      filename: 'sfx_click.wav',
      loop: false,
      required: true,
    ),
    (
      id: 'sfx.alert',
      kind: AudioTrackKind.sfx,
      role: AudioTrackRole.alert,
      filename: 'sfx_alert.wav',
      loop: false,
      required: true,
    ),
    (
      id: 'sfx.glitch',
      kind: AudioTrackKind.sfx,
      role: AudioTrackRole.glitch,
      filename: 'sfx_glitch.wav',
      loop: false,
      required: true,
    ),
    (
      id: 'sfx.chime',
      kind: AudioTrackKind.sfx,
      role: AudioTrackRole.chime,
      filename: 'sfx_chime.wav',
      loop: false,
      required: true,
    ),
  ];

  final verifier = const WavHeaderVerifier();
  final descriptors = <AudioTrackDescriptor>[];

  print('[2/4] Inspecting WAV headers and computing SHA-256 hashes...');
  for (final cfg in trackConfigs) {
    final tempFile = File('${tempDir.path}/${cfg.filename}');
    final bytes = tempFile.readAsBytesSync();
    final inspection = verifier.inspectWavHeader(bytes);

    if (!inspection.isValid) {
      throw Exception(
          'Inspection failed for ${cfg.filename}: ${inspection.failureMessage}');
    }

    final sha256Hash = verifier.computeSha256(bytes);

    final descriptor = AudioTrackDescriptor(
      id: cfg.id,
      kind: cfg.kind,
      role: cfg.role,
      filename: cfg.filename,
      sizeBytes: bytes.length,
      sha256: sha256Hash,
      codec: 'pcm',
      sampleRate: inspection.sampleRate,
      channels: inspection.channels,
      bitsPerSample: inspection.bitsPerSample,
      durationMs: inspection.calculatedDurationMs,
      loop: cfg.loop,
      required: cfg.required,
    );

    descriptors.add(descriptor);

    // Copy to distribution and asset directories
    File('${distDir.path}/${cfg.filename}').writeAsBytesSync(bytes);
    File('${assetDir.path}/${cfg.filename}').writeAsBytesSync(bytes);

    print(
        '  - [OK] ${cfg.id} -> ${cfg.filename} (${bytes.length} bytes, ${inspection.sampleRate} Hz, sha256: ${sha256Hash.substring(0, 16)}...)');
  }

  print('[3/4] Generating canonical audio-manifest.json...');
  final manifest = AudioManifest(
    schemaVersion: 1,
    audioSetId: 'aura.windows.release.v1',
    tracks: descriptors,
  );

  final jsonEncoder = JsonEncoder.withIndent('  ');
  final manifestJsonStr = jsonEncoder.convert(manifest.toJson());

  File('${distDir.path}/audio-manifest.json')
      .writeAsStringSync(manifestJsonStr);
  File('${assetDir.path}/audio_manifest.json')
      .writeAsStringSync(manifestJsonStr);

  tempDir.deleteSync(recursive: true);

  print('[4/4] Release manifest & assets written successfully:');
  print('      - distribution/audio/audio-manifest.json');
  print('      - app/assets/audio/audio_manifest.json');
  print('==================================================================');
}
