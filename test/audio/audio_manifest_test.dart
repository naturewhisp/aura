import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('AudioManifest & AudioTrackDescriptor Unit Tests', () {
    test('carica correttamente un manifest valido da JSON', () {
      final json = {
        'schemaVersion': 1,
        'audioSetId': 'aura.windows.release.v1',
        'tracks': [
          {
            'id': 'bgm.main',
            'kind': 'bgm',
            'role': 'mainMenu',
            'filename': 'bgm_main.wav',
            'sizeBytes': 1024,
            'sha256':
                'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
            'codec': 'pcm',
            'sampleRate': 44100,
            'channels': 2,
            'bitsPerSample': 16,
            'durationMs': 12000,
            'loop': true,
            'required': true,
          }
        ]
      };

      final manifest = AudioManifest.fromJson(json);

      expect(manifest.schemaVersion, equals(1));
      expect(manifest.audioSetId, equals('aura.windows.release.v1'));
      expect(manifest.tracks.length, equals(1));

      final track = manifest.tracks.first;
      expect(track.id, equals('bgm.main'));
      expect(track.kind, equals(AudioTrackKind.bgm));
      expect(track.role, equals(AudioTrackRole.mainMenu));
      expect(track.filename, equals('bgm_main.wav'));
      expect(track.sizeBytes, equals(1024));
      expect(track.sampleRate, equals(44100));
      expect(track.channels, equals(2));
      expect(track.bitsPerSample, equals(16));
      expect(track.durationMs, equals(12000));
      expect(track.loop, isTrue);
      expect(track.required, isTrue);
      expect(manifest.toJson(), equals(json));
    });

    test('rigetta schemaVersion non supportata (!= 1)', () {
      final json = {
        'schemaVersion': 2,
        'audioSetId': 'aura.v2',
        'tracks': <Map<String, dynamic>>[]
      };

      expect(
        () => AudioManifest.fromJson(json),
        throwsA(
          isA<AudioManifestException>().having(
            (e) => e.code,
            'code',
            equals(AudioAssetFailureCode.unsupportedSchemaVersion),
          ),
        ),
      );
    });

    test('rigetta path traversal nel filename della traccia', () {
      final jsonTrack = {
        'id': 'sfx.hack',
        'kind': 'sfx',
        'role': 'click',
        'filename': '../etc/passwd',
        'sizeBytes': 1024,
        'sha256':
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'codec': 'pcm',
        'sampleRate': 22050,
        'channels': 1,
        'bitsPerSample': 16,
        'durationMs': 500,
        'loop': false,
        'required': true,
      };

      expect(
        () => AudioTrackDescriptor.fromJson(jsonTrack),
        throwsA(
          isA<AudioManifestException>().having(
            (e) => e.code,
            'code',
            equals(AudioAssetFailureCode.manifestMalformed),
          ),
        ),
      );
    });

    test(
        'rigetta hash SHA-256 non valido (lunghezza errata o caratteri invalidi)',
        () {
      final jsonTrack = {
        'id': 'sfx.badhash',
        'kind': 'sfx',
        'role': 'alert',
        'filename': 'sfx_alert.wav',
        'sizeBytes': 512,
        'sha256': 'INVALID_HASH_STRING',
        'codec': 'pcm',
        'sampleRate': 22050,
        'channels': 1,
        'bitsPerSample': 16,
        'durationMs': 500,
        'loop': false,
        'required': true,
      };

      expect(
        () => AudioTrackDescriptor.fromJson(jsonTrack),
        throwsA(
          isA<AudioManifestException>().having(
            (e) => e.code,
            'code',
            equals(AudioAssetFailureCode.checksumMismatch),
          ),
        ),
      );
    });

    test('rigetta manifest con ID tracce duplicati', () {
      final track1 = {
        'id': 'bgm.dup',
        'kind': 'bgm',
        'role': 'ambient',
        'filename': 'bgm1.wav',
        'sizeBytes': 1024,
        'sha256':
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'codec': 'pcm',
        'sampleRate': 44100,
        'channels': 2,
        'bitsPerSample': 16,
        'durationMs': 5000,
        'loop': true,
        'required': true,
      };
      final track2 = {
        'id': 'bgm.dup',
        'kind': 'bgm',
        'role': 'tense',
        'filename': 'bgm2.wav',
        'sizeBytes': 1024,
        'sha256':
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'codec': 'pcm',
        'sampleRate': 44100,
        'channels': 2,
        'bitsPerSample': 16,
        'durationMs': 5000,
        'loop': true,
        'required': true,
      };

      final json = {
        'schemaVersion': 1,
        'audioSetId': 'aura.dup',
        'tracks': [track1, track2],
      };

      expect(
        () => AudioManifest.fromJson(json),
        throwsA(
          isA<AudioManifestException>().having(
            (e) => e.code,
            'code',
            equals(AudioAssetFailureCode.manifestMalformed),
          ),
        ),
      );
    });
  });
}
