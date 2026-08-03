import 'package:aura_core/aura_core.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

class FakeBundleSource implements AudioAssetSource {
  final Map<String, List<int>> files = {};

  @override
  Future<List<int>?> read(String filename) async => files[filename];
}

class FakeManagedStore implements ManagedAudioStore {
  final Map<String, List<int>> files = {};
  final List<String> deletedFiles = [];

  @override
  Future<List<int>?> read(String filename) async => files[filename];

  @override
  Future<void> writeAtomically(String filename, List<int> bytes) async {
    files[filename] = bytes;
  }

  @override
  Future<void> delete(String filename) async {
    files.remove(filename);
    deletedFiles.add(filename);
  }
}

class FakeProceduralFallback implements ProceduralAudioFallback {
  @override
  Future<List<int>> generate(AudioTrackDescriptor descriptor) async {
    return [0x52, 0x49, 0x46, 0x46]; // Mock procedural bytes
  }
}

List<int> createValidWavBytes({int numSamples = 100}) {
  final builder = <int>[];
  builder.addAll('RIFF'.codeUnits);
  final dataSize = numSamples * 2;
  final chunkSize = 36 + dataSize;
  builder.addAll([
    chunkSize & 0xFF,
    (chunkSize >> 8) & 0xFF,
    (chunkSize >> 16) & 0xFF,
    (chunkSize >> 24) & 0xFF,
  ]);
  builder.addAll('WAVEfmt '.codeUnits);
  builder.addAll([16, 0, 0, 0]); // fmt chunk size
  builder.addAll([1, 0]); // PCM
  builder.addAll([1, 0]); // 1 channel
  builder.addAll([0x22, 0x56, 0, 0]); // 22050 Hz
  builder.addAll([0x44, 0xAC, 0, 0]); // byte rate
  builder.addAll([2, 0]); // block align
  builder.addAll([16, 0]); // 16 bits
  builder.addAll('data'.codeUnits);
  builder.addAll([
    dataSize & 0xFF,
    (dataSize >> 8) & 0xFF,
    (dataSize >> 16) & 0xFF,
    (dataSize >> 24) & 0xFF,
  ]);
  for (var i = 0; i < numSamples; i++) {
    builder.addAll([0, 0]);
  }
  return builder;
}

void main() {
  group('AudioImportEngine Unit & Integration Tests', () {
    late FakeBundleSource bundledSource;
    late FakeManagedStore managedStore;
    late FakeProceduralFallback proceduralFallback;
    late AudioImportEngine engine;

    setUp(() {
      bundledSource = FakeBundleSource();
      managedStore = FakeManagedStore();
      proceduralFallback = FakeProceduralFallback();
      engine = AudioImportEngine(
        bundledSource: bundledSource,
        managedStore: managedStore,
        proceduralFallback: proceduralFallback,
      );
    });

    test('1. Usa prima lo store gestito se il file è presente e valido',
        () async {
      final wavBytes = createValidWavBytes();
      final hash = sha256.convert(wavBytes).toString().toLowerCase();

      final track = AudioTrackDescriptor(
        id: 'bgm.main',
        kind: AudioTrackKind.bgm,
        role: AudioTrackRole.mainMenu,
        filename: 'bgm_main.wav',
        sizeBytes: wavBytes.length,
        sha256: hash,
        codec: 'pcm',
        sampleRate: 22050,
        channels: 1,
        bitsPerSample: 16,
        durationMs: 100,
        loop: true,
        required: true,
      );

      managedStore.files['bgm_main.wav'] = wavBytes;

      final resolved = await engine.resolveTrack(track);

      expect(resolved.isProceduralFallback, isFalse);
      expect(resolved.sourcePath, equals('managedStore:bgm_main.wav'));
      expect(resolved.bytes, equals(wavBytes));
    });

    test(
        '2. Ripristina dal bundle nel managed store se lo store è corrotto o mancante',
        () async {
      final wavBytes = createValidWavBytes();
      final hash = sha256.convert(wavBytes).toString().toLowerCase();

      final track = AudioTrackDescriptor(
        id: 'sfx.click',
        kind: AudioTrackKind.sfx,
        role: AudioTrackRole.click,
        filename: 'sfx_click.wav',
        sizeBytes: wavBytes.length,
        sha256: hash,
        codec: 'pcm',
        sampleRate: 22050,
        channels: 1,
        bitsPerSample: 16,
        durationMs: 100,
        loop: false,
        required: true,
      );

      // Store gestito corrotto
      managedStore.files['sfx_click.wav'] = [0x00, 0x00, 0x00];
      // Bundle valido
      bundledSource.files['sfx_click.wav'] = wavBytes;

      final resolved = await engine.resolveTrack(track);

      expect(resolved.isProceduralFallback, isFalse);
      expect(resolved.sourcePath, equals('bundledStore:sfx_click.wav'));
      expect(resolved.bytes, equals(wavBytes));
      // Verifica che il file sia stato cancellato e poi sovrascritto atomicamente nello store gestito
      expect(managedStore.deletedFiles, contains('sfx_click.wav'));
      expect(managedStore.files['sfx_click.wav'], equals(wavBytes));
    });

    test(
        '3. Utilizza la modalità degradata proceduralFallback se store e bundle non sono validi',
        () async {
      final wavBytes = createValidWavBytes();
      final hash = sha256.convert(wavBytes).toString().toLowerCase();

      final track = AudioTrackDescriptor(
        id: 'sfx.alert',
        kind: AudioTrackKind.sfx,
        role: AudioTrackRole.alert,
        filename: 'sfx_alert.wav',
        sizeBytes: wavBytes.length,
        sha256: hash,
        codec: 'pcm',
        sampleRate: 22050,
        channels: 1,
        bitsPerSample: 16,
        durationMs: 100,
        loop: false,
        required: true,
      );

      // Entrambi non disponibili o corrotti
      managedStore.files['sfx_alert.wav'] = [1, 2, 3];
      bundledSource.files['sfx_alert.wav'] = [4, 5, 6];

      final resolved = await engine.resolveTrack(track);

      expect(resolved.isProceduralFallback, isTrue);
      expect(resolved.sourcePath, equals('proceduralFallback:sfx_alert.wav'));
      expect(resolved.failureCode,
          equals(AudioAssetFailureCode.proceduralFallbackUsed));
      // Il file nello store non viene sovrascritto dalla modalità degradata
      expect(managedStore.files.containsKey('sfx_alert.wav'), isFalse);
    });
  });
}
