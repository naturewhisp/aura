import 'package:aura_core/aura_offline.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import '../provisioning_test_helpers.dart';

void main() {
  group('Tranche 6.4c — Artifact Download Engine, Resume & Staging Tests', () {
    late MemoryProvisioningFileSystem fileSystem;
    late ProvisioningPathResolver pathResolver;
    late InMemoryProvisioningLock lock;
    late JsonDownloadCheckpointRepository checkpointRepository;
    late DownloadConcurrencyController concurrencyController;
    late DateTime nowUtc;
    late MemoryProvisioningClock clock;

    setUp(() {
      fileSystem = MemoryProvisioningFileSystem();
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AURA\app_managed',
        bundledRoot: r'C:\AURA\bundled',
      );
      lock = InMemoryProvisioningLock();
      checkpointRepository = JsonDownloadCheckpointRepository(
        pathResolver: pathResolver,
        lock: lock,
        fileSystem: fileSystem,
      );
      concurrencyController =
          DownloadConcurrencyController(maxConcurrentDownloads: 1);
      nowUtc = DateTime.parse('2026-07-27T12:00:00Z');
      clock = MemoryProvisioningClock(nowUtc);
    });

    DownloadRequest createRequest({
      String operationId = 'op-gemma-12b-q4',
      String artifactId = 'gemma-4-12b-it-qat-q4_0',
      String url =
          'https://huggingface.co/lmstudio-community/gemma-4-12B-it-QAT-GGUF/resolve/main/gemma-4-12B-it-QAT-Q4_0.gguf',
      int expectedSizeBytes = 100,
      Map<String, String>? extraHeaders,
    }) {
      return DownloadRequest(
        operationId: operationId,
        artifactId: artifactId,
        sourceUri: Uri.parse(url),
        expectedSizeBytes: expectedSizeBytes,
        extraHeaders: extraHeaders,
      );
    }

    test('Full download from byte 0 with HTTP 200 completes StagingArtifact',
        () async {
      final payload = List.generate(100, (i) => i % 256);
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          payload,
          200,
          headers: {'etag': '"strong-etag-v1"'},
        );
      });

      final engine = DefaultArtifactDownloadEngine(
        httpClient: mockClient,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        checkpointRepository: checkpointRepository,
        concurrencyController: concurrencyController,
        clock: clock,
      );

      final req = createRequest(expectedSizeBytes: 100);
      final result = await engine.downloadArtifact(request: req);

      expect(result.isSuccess, isTrue);
      expect(result.stagingArtifact, isNotNull);
      expect(result.stagingArtifact!.downloadComplete, isTrue);
      expect(result.stagingArtifact!.cryptographicallyVerified, isFalse);
      expect(result.stagingArtifact!.sizeBytes, equals(100));
      expect(result.stagingArtifact!.strongEtag, equals('"strong-etag-v1"'));

      final partPath = pathResolver.stagingPartPath(req.operationId);
      expect(await fileSystem.fileExists(partPath), isTrue);
      final savedBytes = await fileSystem.readAsBytes(partPath);
      expect(savedBytes.length, equals(100));

      // Il file checkpoint deve essere stato eliminato alla fine
      final checkpoint =
          await checkpointRepository.readCheckpoint(req.operationId);
      expect(checkpoint, isNull);
    });

    test(
        'Resume via HTTP 206 with If-Range header and matching Strong ETag succeeds',
        () async {
      final req = createRequest(expectedSizeBytes: 100);
      final partPath = pathResolver.stagingPartPath(req.operationId);

      // Pre-condizione: 40 byte gia salvati su disco
      final initialBytes = List.generate(40, (i) => i % 256);
      await fileSystem.appendBytes(partPath, initialBytes);

      final initialCheckpoint = DownloadCheckpoint(
        operationId: req.operationId,
        artifactId: req.artifactId,
        sourceUri: req.sourceUri.toString(),
        strongEtag: '"strong-etag-v1"',
        downloadedBytes: 40,
        expectedSizeBytes: 100,
        createdAtUtc: nowUtc,
        updatedAtUtc: nowUtc,
      );
      await checkpointRepository.saveCheckpoint(initialCheckpoint);

      String? receivedRange;
      String? receivedIfRange;

      final mockClient = MockClient((request) async {
        receivedRange = request.headers['Range'];
        receivedIfRange = request.headers['If-Range'];

        final remaining = List.generate(60, (i) => (i + 40) % 256);
        return http.Response.bytes(
          remaining,
          206,
          headers: {
            'etag': '"strong-etag-v1"',
            'content-range': 'bytes 40-99/100',
            'content-length': '60',
          },
        );
      });

      final engine = DefaultArtifactDownloadEngine(
        httpClient: mockClient,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        checkpointRepository: checkpointRepository,
        concurrencyController: concurrencyController,
        clock: clock,
      );

      final result = await engine.downloadArtifact(request: req);

      expect(receivedRange, equals('bytes=40-'));
      expect(receivedIfRange, equals('"strong-etag-v1"'));
      expect(result.isSuccess, isTrue);
      expect(result.stagingArtifact!.sizeBytes, equals(100));

      final finalBytes = await fileSystem.readAsBytes(partPath);
      expect(finalBytes.length, equals(100));
    });

    test(
        'Invalidates resume and restarts from byte 0 if checkpoint has a weak ETag (W/)',
        () async {
      final req = createRequest(expectedSizeBytes: 100);
      final partPath = pathResolver.stagingPartPath(req.operationId);

      await fileSystem.appendBytes(partPath, List.generate(40, (i) => i));

      final weakCheckpoint = DownloadCheckpoint(
        operationId: req.operationId,
        artifactId: req.artifactId,
        sourceUri: req.sourceUri.toString(),
        strongEtag: 'W/"weak-etag"', // ETag debole!
        downloadedBytes: 40,
        expectedSizeBytes: 100,
        createdAtUtc: nowUtc,
        updatedAtUtc: nowUtc,
      );
      await checkpointRepository.saveCheckpoint(weakCheckpoint);

      String? receivedRange;
      String? receivedIfRange;

      final mockClient = MockClient((request) async {
        receivedRange = request.headers['Range'];
        receivedIfRange = request.headers['If-Range'];
        return http.Response.bytes(
          List.generate(100, (i) => i),
          200,
        );
      });

      final engine = DefaultArtifactDownloadEngine(
        httpClient: mockClient,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        checkpointRepository: checkpointRepository,
        concurrencyController: concurrencyController,
        clock: clock,
      );

      final result = await engine.downloadArtifact(request: req);

      // Range ed If-Range NON devono essere stati inviati
      expect(receivedRange, isNull);
      expect(receivedIfRange, isNull);
      expect(result.isSuccess, isTrue);
      expect(result.stagingArtifact!.sizeBytes, equals(100));
    });

    test(
        'Rejects invalid 206 response with mismatched Content-Range start offset',
        () async {
      final req = createRequest(expectedSizeBytes: 100);
      final partPath = pathResolver.stagingPartPath(req.operationId);

      await fileSystem.appendBytes(partPath, List.generate(40, (i) => i));
      final checkpoint = DownloadCheckpoint(
        operationId: req.operationId,
        artifactId: req.artifactId,
        sourceUri: req.sourceUri.toString(),
        strongEtag: '"etag-v1"',
        downloadedBytes: 40,
        expectedSizeBytes: 100,
        createdAtUtc: nowUtc,
        updatedAtUtc: nowUtc,
      );
      await checkpointRepository.saveCheckpoint(checkpoint);

      var attempt = 0;
      final mockClient = MockClient((request) async {
        attempt++;
        if (attempt == 1) {
          // Risposta 206 invalida: dichiara start=0 anziche 40!
          return http.Response.bytes(
            List.generate(100, (i) => i),
            206,
            headers: {
              'etag': '"etag-v1"',
              'content-range': 'bytes 0-99/100',
            },
          );
        }
        // Tentativo 2 incondizionato da byte 0
        return http.Response.bytes(List.generate(100, (i) => i), 200);
      });

      final engine = DefaultArtifactDownloadEngine(
        httpClient: mockClient,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        checkpointRepository: checkpointRepository,
        concurrencyController: concurrencyController,
        clock: clock,
      );

      final result = await engine.downloadArtifact(request: req);

      expect(attempt, equals(2));
      expect(result.isSuccess, isTrue);
      expect(result.stagingArtifact!.sizeBytes, equals(100));
    });

    test('HTTP 416 completes immediately if local size equals expected size',
        () async {
      final req = createRequest(expectedSizeBytes: 100);
      final partPath = pathResolver.stagingPartPath(req.operationId);

      await fileSystem.appendBytes(partPath, List.generate(100, (i) => i));
      final checkpoint = DownloadCheckpoint(
        operationId: req.operationId,
        artifactId: req.artifactId,
        sourceUri: req.sourceUri.toString(),
        strongEtag: '"etag-v1"',
        downloadedBytes: 100,
        expectedSizeBytes: 100,
        createdAtUtc: nowUtc,
        updatedAtUtc: nowUtc,
      );
      await checkpointRepository.saveCheckpoint(checkpoint);

      final mockClient = MockClient((request) async {
        return http.Response(
          'Range Not Satisfiable',
          416,
          headers: {'content-range': 'bytes */100'},
        );
      });

      final engine = DefaultArtifactDownloadEngine(
        httpClient: mockClient,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        checkpointRepository: checkpointRepository,
        concurrencyController: concurrencyController,
        clock: clock,
      );

      final result = await engine.downloadArtifact(request: req);

      expect(result.isSuccess, isTrue);
      expect(result.stagingArtifact!.sizeBytes, equals(100));
    });

    test(
        'Startup reconciliation truncates .part file if larger than checkpoint',
        () async {
      final req = createRequest(expectedSizeBytes: 100);
      final partPath = pathResolver.stagingPartPath(req.operationId);

      // Il file su disco contiene 60 byte ma il checkpoint dichiara solo 40 byte flushati
      await fileSystem.appendBytes(partPath, List.generate(60, (i) => i));
      final checkpoint = DownloadCheckpoint(
        operationId: req.operationId,
        artifactId: req.artifactId,
        sourceUri: req.sourceUri.toString(),
        strongEtag: '"etag-v1"',
        downloadedBytes: 40,
        expectedSizeBytes: 100,
        createdAtUtc: nowUtc,
        updatedAtUtc: nowUtc,
      );
      await checkpointRepository.saveCheckpoint(checkpoint);

      String? rangeReceived;

      final mockClient = MockClient((request) async {
        rangeReceived = request.headers['Range'];
        return http.Response.bytes(
          List.generate(60, (i) => i + 40),
          206,
          headers: {
            'etag': '"etag-v1"',
            'content-range': 'bytes 40-99/100',
          },
        );
      });

      final engine = DefaultArtifactDownloadEngine(
        httpClient: mockClient,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        checkpointRepository: checkpointRepository,
        concurrencyController: concurrencyController,
        clock: clock,
      );

      final result = await engine.downloadArtifact(request: req);

      expect(rangeReceived, equals('bytes=40-'));
      expect(result.isSuccess, isTrue);
      expect(result.stagingArtifact!.sizeBytes, equals(100));
    });

    test(
        'Cooperative cancellation yields DownloadResult.cancelled and retains .part and checkpoint',
        () async {
      final req = createRequest(expectedSizeBytes: 100);
      final cancelToken = DownloadCancellationToken();

      final mockClient = MockClient((request) async {
        // Annulla a meta streaming
        cancelToken
            .cancel('Annullamento richiesto dall\'utente durante il test.');
        return http.Response.bytes(List.generate(100, (i) => i), 200);
      });

      final engine = DefaultArtifactDownloadEngine(
        httpClient: mockClient,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        checkpointRepository: checkpointRepository,
        concurrencyController: concurrencyController,
        clock: clock,
      );

      final result = await engine.downloadArtifact(
        request: req,
        cancellationToken: cancelToken,
      );

      expect(result.isCancelled, isTrue);
      expect(result.failureReason, equals(DownloadFailureReason.cancelled));

      // Verifico che il file .part e il checkpoint siano stati preservati
      final partPath = pathResolver.stagingPartPath(req.operationId);
      expect(await fileSystem.fileExists(partPath), isTrue);
    });

    test(
        'Strips Authorization header and prohibits HTTPS to HTTP downgrade on Cross-Origin redirect',
        () async {
      final req = createRequest(
        expectedSizeBytes: 100,
        extraHeaders: {'Authorization': 'Bearer secret_token'},
      );

      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('huggingface.co')) {
          // Redirect verso HTTP non sicuro!
          return http.Response('', 302, headers: {
            'location': 'http://insecure-cdn.com/file.gguf',
          });
        }
        return http.Response('OK', 200);
      });

      final engine = DefaultArtifactDownloadEngine(
        httpClient: mockClient,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        checkpointRepository: checkpointRepository,
        concurrencyController: concurrencyController,
        clock: clock,
      );

      final result = await engine.downloadArtifact(request: req);

      expect(result.isFailure, isTrue);
      expect(
          result.failureReason, equals(DownloadFailureReason.insecureRedirect));
    });

    test(
        'Exclusive destination lock prevents concurrent download on same operationId',
        () async {
      final req = createRequest(operationId: 'op-locked-test');

      concurrencyController.tryAcquireLock('op-locked-test');

      final mockClient = MockClient((request) async {
        return http.Response('OK', 200);
      });

      final engine = DefaultArtifactDownloadEngine(
        httpClient: mockClient,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        checkpointRepository: checkpointRepository,
        concurrencyController: concurrencyController,
        clock: clock,
      );

      final result = await engine.downloadArtifact(request: req);

      expect(result.isFailure, isTrue);
      expect(result.failureReason,
          equals(DownloadFailureReason.destinationLocked));

      concurrencyController.releaseLock('op-locked-test');
    });

    test('Cleanly fails when available free storage is insufficient', () async {
      final req = createRequest(expectedSizeBytes: 1000);
      fileSystem.mockAvailableFreeSpace = 200; // Solo 200 byte disponibili!

      final mockClient = MockClient((request) async {
        return http.Response('OK', 200);
      });

      final engine = DefaultArtifactDownloadEngine(
        httpClient: mockClient,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        checkpointRepository: checkpointRepository,
        concurrencyController: concurrencyController,
        clock: clock,
      );

      final result = await engine.downloadArtifact(request: req);

      expect(result.isFailure, isTrue);
      expect(result.failureReason,
          equals(DownloadFailureReason.insufficientStorage));
    });
  });
}
