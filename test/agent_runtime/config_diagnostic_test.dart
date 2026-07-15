import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

class ThrowingDiagnosticSink implements DiagnosticSink {
  @override
  void report(ConfigDiagnostic diagnostic) {
    throw Exception('Simulated sink crash');
  }
}

void main() {
  group('ConfigDiagnostic - Model & Sink', () {
    test('1. ConfigDiagnostic stores all fields correctly', () {
      final error = Exception('Some error');
      final stack = StackTrace.current;
      final diag = ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.error,
        code: ConfigDiagnosticCode.invalidJson,
        path: 'some/path.json',
        operation: 'loadSomething',
        message: 'Test message',
        error: error,
        stackTrace: stack,
        fallbackUsed: true,
      );

      expect(diag.severity, equals(ConfigDiagnosticSeverity.error));
      expect(diag.code, equals(ConfigDiagnosticCode.invalidJson));
      expect(diag.path, equals('some/path.json'));
      expect(diag.operation, equals('loadSomething'));
      expect(diag.message, equals('Test message'));
      expect(diag.error, same(error));
      expect(diag.stackTrace, same(stack));
      expect(diag.fallbackUsed, isTrue);
      expect(diag.toString(), contains('[ConfigDiagnosticSeverity.error]'));
      expect(diag.toString(), contains('Test message'));
      expect(diag.toString(), contains('Fallback Used'));
    });

    test('2. NullDiagnosticSink report does not throw', () {
      const sink = NullDiagnosticSink();
      final diag = ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.info,
        code: ConfigDiagnosticCode.preloadSucceeded,
        path: 'path',
        operation: 'op',
        message: 'msg',
      );

      expect(() => sink.report(diag), returnsNormally);
    });

    test('3. Faulty sink does not crash GameConfigLoader during preloadConfig',
        () async {
      GameConfigLoader.resetForTesting();
      GameConfigLoader.setDiagnosticSink(ThrowingDiagnosticSink());

      // Preload with non-existent path will trigger warning -> sourceReturnedNull
      // This should report to the sink, which throws, but GameConfigLoader should catch and swallow.
      await expectLater(
        GameConfigLoader.preloadConfig('non_existent.json'),
        completes,
      );

      GameConfigLoader.resetForTesting();
    });
  });
}
