import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Risultato del controllo di integrità di un'istanza `llama-server`.
class HealthProbeResult {
  final bool responsive;
  final int? statusCode;
  final bool modelVisible;
  final DateTime observedAt;
  final Duration? latency;
  final String? failureReason;
  final Map<String, dynamic> diagnostics;

  const HealthProbeResult({
    required this.responsive,
    this.statusCode,
    this.modelVisible = false,
    required this.observedAt,
    this.latency,
    this.failureReason,
    this.diagnostics = const {},
  });
}

/// Contratto per il probing dell'integrità HTTP del server locale.
abstract interface class HealthProbe {
  Future<HealthProbeResult> probe({
    required Uri baseUri,
    String? expectedModelAlias,
    Duration timeout = const Duration(seconds: 2),
  });
}

/// Implementazione concreta basata sul client HTTP standard.
class HttpLlamaServerHealthProbe implements HealthProbe {
  final http.Client _client;

  HttpLlamaServerHealthProbe({http.Client? client})
      : _client = client ?? http.Client();

  @override
  Future<HealthProbeResult> probe({
    required Uri baseUri,
    String? expectedModelAlias,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final stopwatch = Stopwatch()..start();
    final observedAt = DateTime.now();

    try {
      // 1. Prova l'endpoint /health se disponibile
      final healthUri = baseUri.replace(path: '/health');
      final healthRes = await _client.get(healthUri).timeout(timeout);
      stopwatch.stop();

      if (healthRes.statusCode == 200) {
        bool modelVisible = true;
        if (expectedModelAlias != null) {
          modelVisible =
              await _verifyModelAlias(baseUri, expectedModelAlias, timeout);
        }
        return HealthProbeResult(
          responsive: true,
          statusCode: healthRes.statusCode,
          modelVisible: modelVisible,
          observedAt: observedAt,
          latency: stopwatch.elapsed,
          diagnostics: {
            'endpoint': '/health',
            'statusCode': healthRes.statusCode
          },
        );
      }

      // 2. Fallback su /v1/models se /health restituisce non-200
      final modelsUri = baseUri.replace(path: '/v1/models');
      final modelsRes = await _client.get(modelsUri).timeout(timeout);

      if (modelsRes.statusCode == 200) {
        bool modelVisible = true;
        if (expectedModelAlias != null) {
          modelVisible =
              _checkModelInResponseBody(modelsRes.body, expectedModelAlias);
        }
        return HealthProbeResult(
          responsive: true,
          statusCode: modelsRes.statusCode,
          modelVisible: modelVisible,
          observedAt: observedAt,
          latency: stopwatch.elapsed,
          diagnostics: {
            'endpoint': '/v1/models',
            'statusCode': modelsRes.statusCode
          },
        );
      }

      return HealthProbeResult(
        responsive: false,
        statusCode: modelsRes.statusCode,
        observedAt: observedAt,
        failureReason:
            'Endpoint HTTP restituisce codice di stato non ok (${modelsRes.statusCode}).',
      );
    } catch (e) {
      stopwatch.stop();
      return HealthProbeResult(
        responsive: false,
        observedAt: observedAt,
        failureReason: 'Connessione al server non riuscita.',
        diagnostics: {'latencyMs': stopwatch.elapsedMilliseconds},
      );
    }
  }

  Future<bool> _verifyModelAlias(
      Uri baseUri, String alias, Duration timeout) async {
    try {
      final modelsUri = baseUri.replace(path: '/v1/models');
      final res = await _client.get(modelsUri).timeout(timeout);
      if (res.statusCode == 200) {
        return _checkModelInResponseBody(res.body, alias);
      }
    } catch (_) {}
    return false;
  }

  bool _checkModelInResponseBody(String body, String alias) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>?;
      if (data == null) return false;
      return data.any((item) =>
          item is Map<String, dynamic> &&
          (item['id'] == alias || item['id'].toString().contains(alias)));
    } catch (_) {
      return false;
    }
  }
}
