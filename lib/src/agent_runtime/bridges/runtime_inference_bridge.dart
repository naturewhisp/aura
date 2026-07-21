import 'dart:async';
import 'package:meta/meta.dart';

import '../inference_bridge.dart';
import '../output/actor_output_sanitization_request.dart';
import '../output/actor_output_sanitizer.dart';
import '../runtime/inference_runtime.dart';
import '../runtime/model_handle.dart';
import '../runtime/runtime_failure.dart';
import '../runtime/runtime_ids.dart';
import '../runtime/runtime_requests.dart';
import '../runtime/runtime_results.dart';

/// Factory producing unique [GenerationRequestId] instances.
abstract interface class GenerationRequestIdFactory {
  GenerationRequestId next();
}

/// Factory producing unique [RuntimeTraceId] instances.
abstract interface class RuntimeTraceIdFactory {
  RuntimeTraceId next();
}

/// Default sequential [GenerationRequestIdFactory] for deterministic execution and testing.
class SequentialGenerationRequestIdFactory
    implements GenerationRequestIdFactory {
  int _counter = 0;
  final String prefix;

  SequentialGenerationRequestIdFactory({this.prefix = 'bridge-req'});

  @override
  GenerationRequestId next() {
    _counter++;
    return GenerationRequestId('$prefix-$_counter');
  }
}

/// Default sequential [RuntimeTraceIdFactory] for deterministic execution and testing.
class SequentialRuntimeTraceIdFactory implements RuntimeTraceIdFactory {
  int _counter = 0;
  final String prefix;

  SequentialRuntimeTraceIdFactory({this.prefix = 'bridge-trace'});

  @override
  RuntimeTraceId next() {
    _counter++;
    return RuntimeTraceId('$prefix-$_counter');
  }
}

/// Timeout policy configuration governing application-level generations and cancellation.
@immutable
class RuntimeBridgeTimeoutPolicy {
  final Duration generationTimeout;
  final Duration cancellationTimeout;

  const RuntimeBridgeTimeoutPolicy({
    this.generationTimeout = const Duration(seconds: 300),
    this.cancellationTimeout = const Duration(seconds: 5),
  });
}

/// Compatibility bridge adapting the legacy [InferenceBridge] interface to the new [InferenceRuntime].
///
/// Responsibilities:
/// - Maps legacy string `modelId` to [ModelRole].
/// - Resolves [ModelRole] to loaded [ModelHandle]s via handle resolver.
/// - Creates trace IDs and generation request IDs.
/// - Owns application-level timeout management and triggers cooperative cancellation via `runtime.cancel`.
/// - Coordinates narrative post-processing using [ActorOutputSanitizer] exclusively for Actor text requests.
class RuntimeInferenceBridge implements InferenceBridge {
  final InferenceRuntime runtime;
  final ModelHandle Function(ModelRole role) handleResolver;
  final ModelRole Function(String legacyModelId) roleResolver;
  final ActorOutputSanitizer sanitizer;
  final GenerationRequestIdFactory requestIdFactory;
  final RuntimeTraceIdFactory traceIdFactory;
  final RuntimeBridgeTimeoutPolicy timeoutPolicy;

  RuntimeInferenceBridge({
    required this.runtime,
    required this.handleResolver,
    ModelRole Function(String legacyModelId)? roleResolver,
    this.sanitizer = const ActorOutputSanitizer(),
    GenerationRequestIdFactory? requestIdFactory,
    RuntimeTraceIdFactory? traceIdFactory,
    this.timeoutPolicy = const RuntimeBridgeTimeoutPolicy(),
  })  : roleResolver = roleResolver ?? _defaultRoleResolver,
        requestIdFactory =
            requestIdFactory ?? SequentialGenerationRequestIdFactory(),
        traceIdFactory = traceIdFactory ?? SequentialRuntimeTraceIdFactory();

  static ModelRole _defaultRoleResolver(String legacyModelId) {
    final lower = legacyModelId.toLowerCase();
    if (lower.contains('qwen') ||
        lower.contains('actor') ||
        lower.contains('panopticon')) {
      return ModelRole.actor;
    }
    return ModelRole.evaluator;
  }

  InferenceRole _parseRole(String roleStr) {
    switch (roleStr.toLowerCase()) {
      case 'system':
        return InferenceRole.system;
      case 'user':
        return InferenceRole.user;
      case 'assistant':
        return InferenceRole.assistant;
      default:
        return InferenceRole.user;
    }
  }

  @override
  Future<String> generateText({
    required String modelId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 150,
    bool? thinking,
  }) async {
    final role = roleResolver(modelId);
    final handle = handleResolver(role);
    final requestId = requestIdFactory.next();
    final traceId = traceIdFactory.next();

    final inferenceMessages = messages
        .map((m) => InferenceMessage(
              role: _parseRole(m['role'] ?? 'user'),
              content: m['content'] ?? '',
            ))
        .toList();

    final request = TextGenerationRequest(
      requestId: requestId,
      model: handle,
      messages: inferenceMessages,
      parameters: GenerationParameters(
        temperature: temperature,
        maxOutputTokens: maxTokens,
      ),
      traceContext: InferenceTraceContext(
        traceId: traceId,
        sessionId: 'session-bridge',
        agentId: role.name,
        logicalModelId: handle.logicalModelId,
      ),
    );

    TextGenerationResult rawResult;
    try {
      rawResult = await runtime
          .generateText(request)
          .timeout(timeoutPolicy.generationTimeout);
    } on TimeoutException {
      try {
        await runtime
            .cancel(requestId)
            .timeout(timeoutPolicy.cancellationTimeout);
      } catch (_) {}
      throw RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.timeout,
          message:
              'Timeout applicativo durante la generazione del testo (superati ${timeoutPolicy.generationTimeout.inSeconds}s).',
        ),
      );
    }

    if (role == ModelRole.actor) {
      final conversationHistory =
          messages.map((m) => m['content']?.trim() ?? '').toList();

      final finishReasonStr =
          rawResult.finishReason == GenerationFinishReason.maxTokens
              ? 'length'
              : 'stop';

      final sanitizedResult = sanitizer.sanitize(
        ActorOutputSanitizationRequest(
          content: rawResult.content,
          reasoningContent: rawResult.reasoningContent ?? '',
          finishReason: finishReasonStr,
          requestedMaxTokens: maxTokens,
          conversationHistory: conversationHistory,
        ),
      );
      return sanitizedResult.content;
    }

    return rawResult.content;
  }

  @override
  Future<Map<String, dynamic>> generateStructured({
    required String modelId,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> schema,
    double temperature = 0.0,
  }) async {
    final role = roleResolver(modelId);
    final handle = handleResolver(role);
    final requestId = requestIdFactory.next();
    final traceId = traceIdFactory.next();

    final inferenceMessages = messages
        .map((m) => InferenceMessage(
              role: _parseRole(m['role'] ?? 'user'),
              content: m['content'] ?? '',
            ))
        .toList();

    final request = StructuredGenerationRequest(
      requestId: requestId,
      model: handle,
      messages: inferenceMessages,
      schema: JsonSchemaDocument(
        schemaId: 'evaluator_schema',
        document: schema,
      ),
      parameters: StructuredGenerationParameters(
        temperature: temperature,
        maxOutputTokens: 512,
      ),
      traceContext: InferenceTraceContext(
        traceId: traceId,
        sessionId: 'session-bridge',
        agentId: role.name,
        logicalModelId: handle.logicalModelId,
      ),
    );

    StructuredGenerationResult result;
    try {
      result = await runtime
          .generateStructured(request)
          .timeout(timeoutPolicy.generationTimeout);
    } on TimeoutException {
      try {
        await runtime
            .cancel(requestId)
            .timeout(timeoutPolicy.cancellationTimeout);
      } catch (_) {}
      throw RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.timeout,
          message:
              'Timeout applicativo durante la generazione strutturata (superati ${timeoutPolicy.generationTimeout.inSeconds}s).',
        ),
      );
    }

    if (result.parsedObject != null) {
      return result.parsedObject!;
    }
    throw const RuntimeException(
      RuntimeFailure(
        code: RuntimeFailureCode.malformedStructuredOutput,
        message:
            'L\'output del modello non è stato decodificato in un oggetto JSON.',
      ),
    );
  }

  @override
  Future<List<String>> discoverModels() async {
    final health = await runtime.health();
    if (!health.responsive) return const [];
    return const ['aura.evaluator.primary', 'aura.actor.primary'];
  }
}
