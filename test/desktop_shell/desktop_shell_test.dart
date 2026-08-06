import 'dart:io';
import 'package:test/test.dart';
import 'package:aura_core/aura_testing.dart';

void main() {
  group('Desktop Shell Contracts & Preferences Serialization', () {
    test('WindowGeometry serializes and deserializes correctly', () {
      const geometry = WindowGeometry(
        x: 150.0,
        y: 80.0,
        width: 1440.0,
        height: 900.0,
        monitorId: 'display-mon-1',
        displayScale: 1.25,
      );

      final jsonMap = geometry.toJson();
      final restored = WindowGeometry.fromJson(jsonMap);

      expect(restored, equals(geometry));
    });

    test('WindowPreferences serializes and deserializes correctly', () {
      const preferences = WindowPreferences(
        schemaVersion: 1,
        startupMode: WindowStartupMode.borderlessFullscreen,
        lastActiveMode: ActiveWindowMode.borderlessFullscreen,
        lastWindowedGeometry: WindowGeometry(
          x: 100,
          y: 200,
          width: 1280,
          height: 720,
        ),
        audioDuckingOnUnfocus: true,
        reduceAnimationsOnUnfocus: false,
        musicEnabled: false,
        sfxEnabled: true,
        reduceGraphicEffects: true,
      );

      final jsonMap = preferences.toJson();
      final restored = WindowPreferences.fromJson(jsonMap);

      expect(
          restored.startupMode, equals(WindowStartupMode.borderlessFullscreen));
      expect(restored.lastActiveMode,
          equals(ActiveWindowMode.borderlessFullscreen));
      expect(restored.lastWindowedGeometry, isNotNull);
      expect(restored.lastWindowedGeometry!.x, equals(100.0));
      expect(restored.reduceAnimationsOnUnfocus, isFalse);
      expect(restored.musicEnabled, isFalse);
      expect(restored.sfxEnabled, isTrue);
      expect(restored.reduceGraphicEffects, isTrue);
    });

    test('WindowPreferences falls back safely on corrupted or unknown enums',
        () {
      final badJson = {
        'schemaVersion': 'invalid',
        'startupMode': 'UNKNOWN_MODE_FUTURE',
        'lastActiveMode': 'NON_EXISTENT',
        'lastWindowedGeometry': {'x': 'not_a_number'},
      };

      final restored = WindowPreferences.fromJson(badJson);

      expect(restored.startupMode, equals(WindowStartupMode.restorePrevious));
      expect(restored.lastActiveMode, equals(ActiveWindowMode.windowed));
      expect(restored.lastWindowedGeometry, isNull);
    });
  });

  group('WindowPreferencesRepository', () {
    late Directory tempDir;
    late WindowPreferencesRepository repo;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('aura_window_prefs_test_');
      repo = WindowPreferencesRepository(storeDirectoryPath: tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('load returns defaults if file does not exist', () async {
      final prefs = await repo.load();
      expect(prefs.startupMode, equals(WindowStartupMode.restorePrevious));
      expect(prefs.lastActiveMode, equals(ActiveWindowMode.windowed));
    });

    test('load returns defaults if file is corrupted', () async {
      final file = File('${tempDir.path}/window_preferences.json');
      await file.writeAsString('{{{{INVALID_JSON');

      final prefs = await repo.load();
      expect(prefs.startupMode, equals(WindowStartupMode.restorePrevious));
    });

    test('save and load persist preferences atomically', () async {
      const prefs = WindowPreferences(
        startupMode: WindowStartupMode.maximized,
        lastActiveMode: ActiveWindowMode.maximized,
        lastWindowedGeometry: WindowGeometry(
          x: 50,
          y: 60,
          width: 1000,
          height: 700,
        ),
      );

      await repo.save(prefs);
      final loaded = await repo.load();

      expect(loaded.startupMode, equals(WindowStartupMode.maximized));
      expect(loaded.lastWindowedGeometry, isNotNull);
      expect(loaded.lastWindowedGeometry!.x, equals(50.0));
    });
  });

  group('WindowGeometryPersistenceCoordinator', () {
    late Directory tempDir;
    late WindowPreferencesRepository repo;
    late WindowGeometryPersistenceCoordinator coordinator;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('aura_window_coord_test_');
      repo = WindowPreferencesRepository(storeDirectoryPath: tempDir.path);
      coordinator = WindowGeometryPersistenceCoordinator(
        repository: repo,
        debounceDuration: const Duration(milliseconds: 50),
      );
    });

    tearDown(() async {
      coordinator.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('debounce aggregates multiple calls and flush writes final state',
        () async {
      coordinator.onGeometryChanged(
          const WindowGeometry(x: 10, y: 10, width: 800, height: 600));
      coordinator.onGeometryChanged(
          const WindowGeometry(x: 20, y: 20, width: 900, height: 650));
      coordinator.onGeometryChanged(
          const WindowGeometry(x: 30, y: 30, width: 1000, height: 700));

      await coordinator.flush();

      final saved = await repo.load();
      expect(saved.lastWindowedGeometry, isNotNull);
      expect(saved.lastWindowedGeometry!.x, equals(30.0));
      expect(saved.lastWindowedGeometry!.width, equals(1000.0));
    });
  });

  group('WindowGeometryValidator', () {
    const validator = WindowGeometryValidator();

    final displays = [
      const DisplayDescriptor(
        id: 'display-primary',
        name: 'Primary Display',
        x: 0,
        y: 0,
        width: 1920,
        height: 1080,
        visibleX: 0,
        visibleY: 0,
        visibleWidth: 1920,
        visibleHeight: 1040,
        scaleFactor: 1.0,
        isPrimary: true,
      ),
      const DisplayDescriptor(
        id: 'display-left',
        name: 'Left Secondary Display',
        x: -1920,
        y: 0,
        width: 1920,
        height: 1080,
        visibleX: -1920,
        visibleY: 0,
        visibleWidth: 1920,
        visibleHeight: 1040,
        scaleFactor: 1.0,
        isPrimary: false,
      ),
    ];

    test('fresh startup uses default size, not minimum size', () {
      final geometry =
          validator.validateAndAdjust(saved: null, displays: displays);

      expect(geometry.monitorId, equals('display-primary'));
      expect(
          geometry.width, equals(WindowGeometryValidator.defaultLogicalWidth));
      expect(geometry.height,
          equals(WindowGeometryValidator.defaultLogicalHeight));
      expect(geometry.x, greaterThanOrEqualTo(0));
    });

    test('preserves valid portrait geometries', () {
      const portrait1 = WindowGeometry(
        x: 100,
        y: 100,
        width: 450,
        height: 800,
        monitorId: 'display-primary',
      );

      final adjusted1 =
          validator.validateAndAdjust(saved: portrait1, displays: displays);
      expect(adjusted1.width, equals(450.0));
      expect(adjusted1.height, equals(800.0));

      const portrait2 = WindowGeometry(
        x: 100,
        y: 100,
        width: 600,
        height: 900,
        monitorId: 'display-primary',
      );

      final adjusted2 =
          validator.validateAndAdjust(saved: portrait2, displays: displays);
      expect(adjusted2.width, equals(600.0));
      expect(adjusted2.height, equals(900.0));
    });

    test('preserves portrait geometry on rotated 1080x1920 display', () {
      final rotatedDisplays = [
        const DisplayDescriptor(
          id: 'display-rotated',
          name: 'Rotated Portrait Display',
          x: 0,
          y: 0,
          width: 1080,
          height: 1920,
          visibleX: 0,
          visibleY: 0,
          visibleWidth: 1080,
          visibleHeight: 1880,
          scaleFactor: 1.0,
          isPrimary: true,
        ),
      ];

      const saved = WindowGeometry(
        x: 100,
        y: 100,
        width: 500,
        height: 1000,
        monitorId: 'display-rotated',
      );

      final adjusted =
          validator.validateAndAdjust(saved: saved, displays: rotatedDisplays);

      expect(adjusted.monitorId, equals('display-rotated'));
      expect(adjusted.width, equals(500.0));
      expect(adjusted.height, equals(1000.0));
    });

    test(
        'valid negative coordinates on left monitor in portrait mode are preserved',
        () {
      const saved = WindowGeometry(
        x: -1500,
        y: 100,
        width: 500,
        height: 850,
        monitorId: 'display-left',
      );

      final adjusted =
          validator.validateAndAdjust(saved: saved, displays: displays);

      expect(adjusted.monitorId, equals('display-left'));
      expect(adjusted.x, equals(-1500.0));
      expect(adjusted.y, equals(100.0));
      expect(adjusted.width, equals(500.0));
      expect(adjusted.height, equals(850.0));
    });

    test('off-screen geometry is safely re-centered on fallback display', () {
      const saved = WindowGeometry(
        x: 5000, // Way off screen
        y: 5000,
        width: 1280,
        height: 800,
        monitorId: 'disconnected-monitor',
      );

      final adjusted =
          validator.validateAndAdjust(saved: saved, displays: displays);

      expect(adjusted.x, lessThan(1920));
      expect(adjusted.y, lessThan(1080));
      expect(adjusted.width, equals(1280.0));
      expect(adjusted.height, equals(800.0));
    });

    test('clamps each axis independently', () {
      const savedWidthTooSmall = WindowGeometry(
        x: 100,
        y: 100,
        width: 400, // < 420
        height: 900,
      );

      final adjustedWidth = validator.validateAndAdjust(
          saved: savedWidthTooSmall, displays: displays);
      expect(adjustedWidth.width, equals(420.0));
      expect(adjustedWidth.height, equals(900.0));

      const savedBothTooSmall = WindowGeometry(
        x: 100,
        y: 100,
        width: 419,
        height: 499,
      );

      final adjustedBoth = validator.validateAndAdjust(
          saved: savedBothTooSmall, displays: displays);
      expect(adjustedBoth.width, equals(420.0));
      expect(adjustedBoth.height, equals(500.0));
    });

    test('adapts default size when display work area is smaller than 1280x800',
        () {
      final smallDisplays = [
        const DisplayDescriptor(
          id: 'display-small',
          name: 'Small Netbook Display',
          x: 0,
          y: 0,
          width: 1024,
          height: 600,
          visibleX: 0,
          visibleY: 0,
          visibleWidth: 1024,
          visibleHeight: 560,
          scaleFactor: 1.0,
          isPrimary: true,
        ),
      ];

      final adjusted =
          validator.validateAndAdjust(saved: null, displays: smallDisplays);

      expect(adjusted.width, equals(1024.0));
      expect(adjusted.height, equals(560.0));
    });
  });

  group('FakeDesktopWindowController Contract', () {
    test('simulates mode transitions and emits events', () async {
      final fakeController = FakeDesktopWindowController();
      final events = <DesktopWindowEvent>[];
      fakeController.events.listen(events.add);

      await fakeController.initialize();
      expect(fakeController.isInitialized, isTrue);

      await fakeController.maximize();
      expect(await fakeController.getActiveMode(),
          equals(ActiveWindowMode.maximized));

      await fakeController.enterBorderlessFullscreen();
      expect(await fakeController.getActiveMode(),
          equals(ActiveWindowMode.borderlessFullscreen));

      await fakeController.exitBorderlessFullscreen();
      expect(await fakeController.getActiveMode(),
          equals(ActiveWindowMode.windowed));

      expect(events.length, equals(3));
      expect(events[0], isA<DesktopWindowModeChanged>());
      expect((events[0] as DesktopWindowModeChanged).mode,
          equals(ActiveWindowMode.maximized));

      await fakeController.dispose();
      expect(fakeController.isDisposed, isTrue);
    });
  });
}
