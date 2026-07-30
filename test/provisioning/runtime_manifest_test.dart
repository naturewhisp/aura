import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('RuntimeManifest Domain Unit Tests', () {
    test('deserializza correttamente un manifest.json valido con backend CUDA',
        () {
      final json = {
        'runtimeId': 'llama.cpp-windows-x64-cuda',
        'llamaCppCommit': 'b3450',
        'buildType': 'Release',
        'backend': 'cuda',
        'cudaVersion': '12.2',
        'architecture': 'x86_64',
        'files': [
          {
            'path': 'llama-server.exe',
            'sha256':
                'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          },
          {
            'path': 'cudart64_12.dll',
            'sha256':
                '8f35248a313b2c6957790e71616c68e14674720616147614e21a2214d2417622',
          }
        ]
      };

      final manifest = RuntimeManifest.fromJson(json);

      expect(manifest.runtimeId, equals('llama.cpp-windows-x64-cuda'));
      expect(manifest.llamaCppCommit, equals('b3450'));
      expect(manifest.backend, equals(RuntimeAcceleration.cuda));
      expect(manifest.cudaVersion, equals('12.2'));
      expect(manifest.files.length, equals(2));
      expect(manifest.files.first.path, equals('llama-server.exe'));
    });

    test('lancia FormatException se runtimeId è mancante o vuoto', () {
      final json = {
        'runtimeId': '',
        'backend': 'cpu',
        'files': [],
      };

      expect(() => RuntimeManifest.fromJson(json), throwsFormatException);
    });
  });
}
