import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/src/platform/desktop_host_platform.dart';
import 'package:aura_app/src/platform/desktop_window_bindings.dart';
import 'package:aura_app/src/platform/desktop_window_controller_factory.dart';
import 'package:aura_app/src/platform/macos/macos_desktop_window_controller.dart';
import 'package:aura_app/src/platform/noop_desktop_window_controller.dart';
import 'package:aura_app/src/platform/windows/windows_desktop_window_controller.dart';
import 'package:aura_core/aura_core.dart';
import 'package:screen_retriever/screen_retriever.dart' as sr;
import 'package:window_manager/window_manager.dart' as wm;

/// Fake in-memory di [DesktopWindowBindings] per testare [MacOSDesktopWindowController]
/// su qualsiasi piattaforma host (incluso Windows CI) senza invocare plugin nativi.
final class FakeDesktopWindowBindings implements DesktopWindowBindings {
  bool ensureInitializedCalled = false;
  final List<wm.WindowListener> listeners = [];
  bool? isPreventCloseValue;
  Size? minimumSize;
  bool isFullScreenValue = false;
  bool isMaximizedValue = false;
  Offset position = const Offset(120, 140);
  Size size = const Size(1280, 800);
  Rect? bounds;
  bool isDestroyed = false;

  List<sr.Display> displays = const [
    sr.Display(
      id: '1',
      name: 'Mac Display 1',
      size: Size(2560, 1440),
      visiblePosition: Offset(0, 0),
      visibleSize: Size(2560, 1415),
      scaleFactor: 2.0,
    ),
  ];

  sr.Display? primaryDisplay;

  @override
  Future<void> ensureInitialized() async {
    ensureInitializedCalled = true;
  }

  @override
  void addListener(wm.WindowListener listener) {
    listeners.add(listener);
  }

  @override
  void removeListener(wm.WindowListener listener) {
    listeners.remove(listener);
  }

  @override
  Future<void> setPreventClose(bool isPreventClose) async {
    isPreventCloseValue = isPreventClose;
  }

  @override
  Future<void> setMinimumSize(Size size) async {
    minimumSize = size;
  }

  @override
  Future<bool> isFullScreen() async => isFullScreenValue;

  @override
  Future<bool> isMaximized() async => isMaximizedValue;

  @override
  Future<Offset> getPosition() async => position;

  @override
  Future<Size> getSize() async => size;

  @override
  Future<void> setFullScreen(bool isFullScreen) async {
    isFullScreenValue = isFullScreen;
  }

  @override
  Future<void> maximize() async {
    isMaximizedValue = true;
  }

  @override
  Future<void> unmaximize() async {
    isMaximizedValue = false;
  }

  @override
  Future<void> setBounds(Rect bounds) async {
    this.bounds = bounds;
    position = Offset(bounds.left, bounds.top);
    size = Size(bounds.width, bounds.height);
  }

  @override
  Future<void> destroy() async {
    isDestroyed = true;
  }

  @override
  Future<List<sr.Display>> getAllDisplays() async => displays;

  @override
  Future<sr.Display> getPrimaryDisplay() async =>
      primaryDisplay ?? displays.first;
}

void main() {
  group('DesktopHostPlatform & Factory', () {
    test('detectHostPlatform riconosce la piattaforma corrente', () {
      final detected = DesktopWindowControllerFactory.detectHostPlatform();
      if (Platform.isWindows) {
        expect(detected, equals(DesktopHostPlatform.windows));
      } else if (Platform.isMacOS) {
        expect(detected, equals(DesktopHostPlatform.macos));
      } else {
        expect(detected, equals(DesktopHostPlatform.other));
      }
    });

    test('createFor istanzia WindowsDesktopWindowController per windows', () {
      final controller = DesktopWindowControllerFactory.createFor(
        DesktopHostPlatform.windows,
      );
      expect(controller, isA<WindowsDesktopWindowController>());
    });

    test('createFor istanzia MacOSDesktopWindowController per macos', () {
      final fakeBindings = FakeDesktopWindowBindings();
      final controller = DesktopWindowControllerFactory.createFor(
        DesktopHostPlatform.macos,
        customBindings: fakeBindings,
      );
      expect(controller, isA<MacOSDesktopWindowController>());
    });

    test('createFor istanzia NoOpDesktopWindowController per other', () {
      final controller = DesktopWindowControllerFactory.createFor(
        DesktopHostPlatform.other,
      );
      expect(controller, isA<NoOpDesktopWindowController>());
    });
  });

  group('NoOpDesktopWindowController', () {
    const controller = NoOpDesktopWindowController();

    test('fornisce valori neutri di fallback e non lancia eccezioni', () async {
      await controller.initialize();
      expect(
          await controller.getActiveMode(), equals(ActiveWindowMode.windowed));
      expect(await controller.getGeometry(), isNull);

      final displays = await controller.getDisplays();
      expect(displays.length, equals(1));
      expect(displays.first.id, equals('noop-default'));

      await controller.setWindowed();
      await controller.maximize();
      await controller.enterBorderlessFullscreen();
      await controller.exitBorderlessFullscreen();
      await controller.setGeometry(const WindowGeometry(
        x: 0,
        y: 0,
        width: 1280,
        height: 720,
        monitorId: 'noop-default',
        displayScale: 1.0,
      ));
      await controller.closeWindow();
      await controller.dispose();

      expect(controller.events, isA<Stream<DesktopWindowEvent>>());
    });
  });

  group('MacOSDesktopWindowController', () {
    late FakeDesktopWindowBindings fakeBindings;
    late MacOSDesktopWindowController controller;

    setUp(() {
      fakeBindings = FakeDesktopWindowBindings();
      controller = MacOSDesktopWindowController(bindings: fakeBindings);
    });

    tearDown(() async {
      await controller.dispose();
    });

    test('initialize configura bindings e prevenzione chiusura', () async {
      await controller.initialize();
      expect(fakeBindings.ensureInitializedCalled, isTrue);
      expect(fakeBindings.listeners, contains(controller));
      expect(fakeBindings.isPreventCloseValue, isTrue);
      expect(
        fakeBindings.minimumSize,
        equals(const Size(
          WindowGeometryValidator.minLogicalWidth,
          WindowGeometryValidator.minLogicalHeight,
        )),
      );
    });

    test('getActiveMode valuta fullscreen, maximize e windowed', () async {
      fakeBindings.isFullScreenValue = true;
      fakeBindings.isMaximizedValue = false;
      expect(
        await controller.getActiveMode(),
        equals(ActiveWindowMode.borderlessFullscreen),
      );

      fakeBindings.isFullScreenValue = false;
      fakeBindings.isMaximizedValue = true;
      expect(
        await controller.getActiveMode(),
        equals(ActiveWindowMode.maximized),
      );

      fakeBindings.isFullScreenValue = false;
      fakeBindings.isMaximizedValue = false;
      expect(
        await controller.getActiveMode(),
        equals(ActiveWindowMode.windowed),
      );
    });

    test('enterBorderlessFullscreen e exitBorderlessFullscreen', () async {
      final events = <DesktopWindowEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.enterBorderlessFullscreen();
      expect(fakeBindings.isFullScreenValue, isTrue);

      await controller.exitBorderlessFullscreen();
      expect(fakeBindings.isFullScreenValue, isFalse);

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(events.length, equals(2));
      expect(
        events[0],
        equals(const DesktopWindowModeChanged(
            ActiveWindowMode.borderlessFullscreen)),
      );
      expect(
        events[1],
        equals(const DesktopWindowModeChanged(ActiveWindowMode.windowed)),
      );
    });

    test('setWindowed resetta sia fullscreen sia maximized', () async {
      fakeBindings.isFullScreenValue = true;
      fakeBindings.isMaximizedValue = true;

      final events = <DesktopWindowEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.setWindowed();
      expect(fakeBindings.isFullScreenValue, isFalse);
      expect(fakeBindings.isMaximizedValue, isFalse);

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(
        events.single,
        equals(const DesktopWindowModeChanged(ActiveWindowMode.windowed)),
      );
    });

    test('maximize disattiva fullscreen e attiva maximize', () async {
      fakeBindings.isFullScreenValue = true;

      final events = <DesktopWindowEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.maximize();
      expect(fakeBindings.isFullScreenValue, isFalse);
      expect(fakeBindings.isMaximizedValue, isTrue);

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(
        events.single,
        equals(const DesktopWindowModeChanged(ActiveWindowMode.maximized)),
      );
    });

    test('setGeometry e getGeometry mappano correttamente le coordinate',
        () async {
      const geometryToSet = WindowGeometry(
        x: 150,
        y: 200,
        width: 1400,
        height: 900,
        monitorId: '1',
        displayScale: 2.0,
      );

      final events = <DesktopWindowEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.setGeometry(geometryToSet);
      expect(fakeBindings.bounds,
          equals(const Rect.fromLTWH(150, 200, 1400, 900)));

      final retrieved = await controller.getGeometry();
      expect(retrieved, isNotNull);
      expect(retrieved!.x, equals(150));
      expect(retrieved.y, equals(200));
      expect(retrieved.width, equals(1400));
      expect(retrieved.height, equals(900));
      expect(retrieved.monitorId, equals('1'));
      expect(retrieved.displayScale, equals(2.0));

      await sub.cancel();
      expect(events.single, isA<DesktopWindowMovedResized>());
    });

    test('getDisplays converte i display nativi con scala e posizione',
        () async {
      final displays = await controller.getDisplays();
      expect(displays.length, equals(1));
      final primary = displays.first;
      expect(primary.id, equals('1'));
      expect(primary.name, equals('Mac Display 1'));
      expect(primary.width, equals(2560));
      expect(primary.height, equals(1440));
      expect(primary.scaleFactor, equals(2.0));
      expect(primary.isPrimary, isTrue);
    });

    test('closeWindow disabilita preventClose e distrugge la finestra',
        () async {
      fakeBindings.isPreventCloseValue = true;
      await controller.closeWindow();
      expect(fakeBindings.isPreventCloseValue, isFalse);
      expect(fakeBindings.isDestroyed, isTrue);
    });

    test('WindowListener propaga gli eventi alla stream DesktopWindowEvent',
        () async {
      final events = <DesktopWindowEvent>[];
      final sub = controller.events.listen(events.add);

      controller.onWindowFocus();
      controller.onWindowBlur();
      controller.onWindowMaximize();
      controller.onWindowUnmaximize();
      controller.onWindowMinimize();
      controller.onWindowRestore();
      controller.onWindowEnterFullScreen();
      controller.onWindowLeaveFullScreen();
      controller.onWindowClose();

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events, contains(const DesktopWindowFocusChanged(true)));
      expect(events, contains(const DesktopWindowFocusChanged(false)));
      expect(
        events,
        contains(const DesktopWindowModeChanged(ActiveWindowMode.maximized)),
      );
      expect(
        events,
        contains(const DesktopWindowModeChanged(ActiveWindowMode.windowed)),
      );
      expect(events, contains(const DesktopWindowMinimizeChanged(true)));
      expect(events, contains(const DesktopWindowMinimizeChanged(false)));
      expect(
        events,
        contains(const DesktopWindowModeChanged(
            ActiveWindowMode.borderlessFullscreen)),
      );
      expect(events, contains(const DesktopWindowCloseRequested()));
    });
  });
}
