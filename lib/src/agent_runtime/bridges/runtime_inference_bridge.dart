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

/// Represents an execution plan binding a [ModelRole] to a [logicalModelId] and loaded [ModelHandle].
@immutable
class RuntimeModelExecutionPlan {
  final ModelRole role;
  final String logicalModelId;
  final ModelHandle handle;

  const RuntimeModelExecutionPlan({
    required this.role,
    required this.logicalModelId,
    required this.handle,
  });
}

/// Maps legacy model ID strings to [ModelRole]s without heuristic matching.
@immutable
class LegacyInferenceRouteResolver {
  final Map<String, ModelRole> routes;

  const LegacyInferenceRouteResolver({
    this.routes = const {
      'qwen/qwen3.5-9b': ModelRole.actor,
      'mistralai/ministral-3-3b': ModelRole.evaluator,
      'aura.actor.primary': ModelRole.actor,
      'aura.evaluator.primary': ModelRole.evaluator,
    },
  });

  ModelRole resolveRole(String legacyModelId) {
    final role = routes[legacyModelId];
    if (role == null) {
      throw RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.modelMissing,
          message:
              'Route non riconosciuta per il model ID legacy: "$legacyModelId".',
        ),
      );
    }
    return role;
  }
}

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

/// Scheduler interface managing generation execution timeouts.
abstract interface class TimeoutScheduler {
  Future<T> runWithTimeout<T>({
    required Future<T> Function() action,
    required Duration timeout,
    required Future<T> Function() onTimeout,
  });
}

/// Production implementation of [TimeoutScheduler] using [Future.timeout].
class AsyncTimeoutScheduler implements TimeoutScheduler {
  const AsyncTimeoutScheduler();

  @override
  Future<T> runWithTimeout<T>({
    required Future<T> Function() action,
    required Duration timeout,
    required Future<T> Function() onTimeout,
  }) async {
    try {
      return await action().timeout(timeout);
    } on TimeoutException {
      return await onTimeout();
    }
  }
}

/// Deterministic [TimeoutScheduler] for offline unit testing without real clock delays.
class FakeTimeoutScheduler implements TimeoutScheduler {
  final bool shouldTriggerTimeout;
  final bool shouldTriggerCancelTimeout;

  const FakeTimeoutScheduler({
    this.shouldTriggerTimeout = false,
    this.shouldTriggerCancelTimeout = false,
  });

  @override
  Future<T> runWithTimeout<T>({
    required Future<T> Function() action,
    required Duration timeout,
    required Future<T> Function() onTimeout,
  }) async {
    if (timeout < const Duration(seconds: 10) && shouldTriggerCancelTimeout) {
      return await onTimeout();
    }
    if (timeout >= const Duration(seconds: 10) && shouldTriggerTimeout) {
      return await onTimeout();
    }
    return await action();
  }
}

class _LateResultIgnoredException implements Exception {
  const _LateResultIgnoredException();
}

/// Compatibility bridge adapting the legacy [InferenceBridge] interface to the new [InferenceRuntime].
class RuntimeInferenceBridge implements InferenceBridge {
  final InferenceRuntime runtime;
  final RuntimeModelExecutionPlan Function(ModelRole role) planResolver;
  final LegacyInferenceRouteResolver routeResolver;
  final ActorOutputSanitizer sanitizer;
  final GenerationRequestIdFactory requestIdFactory;
  final RuntimeTraceIdFactory traceIdFactory;
  final RuntimeBridgeTimeoutPolicy timeoutPolicy;
  final TimeoutScheduler timeoutScheduler;

  RuntimeInferenceBridge({
    required this.runtime,
    required this.planResolver,
    LegacyInferenceRouteResolver? routeResolver,
    this.sanitizer = const ActorOutputSanitizer(),
    GenerationRequestIdFactory? requestIdFactory,
    RuntimeTraceIdFactory? traceIdFactory,
    this.timeoutPolicy = const RuntimeBridgeTimeoutPolicy(),
    this.timeoutScheduler = const AsyncTimeoutScheduler(),
  })  : routeResolver = routeResolver ?? const LegacyInferenceRouteResolver(),
        requestIdFactory =
            requestIdFactory ?? SequentialGenerationRequestIdFactory(),
        traceIdFactory = traceIdFactory ?? SequentialRuntimeTraceIdFactory();

  /// Backwards-compatible constructor converting [handleResolver] to a execution plan resolver.
  factory RuntimeInferenceBridge.fromHandleResolver({
    required InferenceRuntime runtime,
    required ModelHandle Function(ModelRole role) handleResolver,
    LegacyInferenceRouteResolver? routeResolver,
    ActorOutputSanitizer sanitizer = const ActorOutputSanitizer(),
    GenerationRequestIdFactory? requestIdFactory,
    RuntimeTraceIdFactory? traceIdFactory,
    RuntimeBridgeTimeoutPolicy timeoutPolicy =
        const RuntimeBridgeTimeoutPolicy(),
    TimeoutScheduler timeoutScheduler = const AsyncTimeoutScheduler(),
  }) {
    return RuntimeInferenceBridge(
      runtime: runtime,
      planResolver: (role) {
        final handle = handleResolver(role);
        return RuntimeModelExecutionPlan(
          role: role,
          logicalModelId: handle.logicalModelId,
          handle: handle,
        );
      },
      routeResolver: routeResolver,
      sanitizer: sanitizer,
      requestIdFactory: requestIdFactory,
      traceIdFactory: traceIdFactory,
      timeoutPolicy: timeoutPolicy,
      timeoutScheduler: timeoutScheduler,
    );
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

  Future<T> _executeWithTimeoutAndCancellation<T>({
    required GenerationRequestId requestId,
    required Future<T> Function() generateAction,
  }) async {
    bool timedOut = false;

    return await timeoutScheduler.runWithTimeout<T>(
      action: () async {
        final res = await generateAction();
        if (timedOut) {
          throw const _LateResultIgnoredException();
        }
        return res;
      },
      timeout: timeoutPolicy.generationTimeout,
      onTimeout: () async {
        timedOut = true;
        String cancellationDisposition = 'confirmed';
        Object? cancelCause;

        try {
          await timeoutScheduler.runWithTimeout<void>(
            action: () => runtime.cancel(requestId),
            timeout: timeoutPolicy.cancellationTimeout,
            onTimeout: () async {
              cancellationDisposition = 'cancellationTimedOut';
            },
          );
        } on RuntimeException catch (e) {
          if (e.failure.code == RuntimeFailureCode.cancellationUnsupported) {
            cancellationDisposition = 'cancellationUnsupported';
          } else {
            cancellationDisposition = 'cancellationFailed';
          }
          cancelCause = e.failure;
        } catch (e) {
          cancellationDisposition = 'cancellationFailed';
          cancelCause = e;
        }

        throw RuntimeException(
          RuntimeFailure(
            code: RuntimeFailureCode.timeout,
            message:
                'Timeout applicativo durante la generazione (superati ${timeoutPolicy.generationTimeout.inSeconds}s). Status cancellazione: $cancellationDisposition.',
            diagnostics: {
              'cancellationDisposition': cancellationDisposition,
              'requestId': requestId.value,
            },
          ),
          cause: cancelCause,
        );
      },
    );
  }

  @override
  Future<String> generateText({
    required String modelId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 150,
    bool? thinking,
  }) async {
    final role = routeResolver.resolveRole(modelId);
    final plan = planResolver(role);
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
      model: plan.handle,
      messages: inferenceMessages,
      parameters: GenerationParameters(
        temperature: temperature,
        maxOutputTokens: maxTokens,
      ),
      traceContext: InferenceTraceContext(
        traceId: traceId,
        sessionId: 'session-bridge',
        agentId: role.name,
        logicalModelId: plan.logicalModelId,
      ),
    );

    final rawResult =
        await _executeWithTimeoutAndCancellation<TextGenerationResult>(
      requestId: requestId,
      generateAction: () => runtime.generateText(request),
    );

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
    final role = routeResolver.resolveRole(modelId);
    final plan = planResolver(role);
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
      model: plan.handle,
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
        logicalModelId: plan.logicalModelId,
      ),
    );

    final result =
        await _executeWithTimeoutAndCancellation<StructuredGenerationResult>(
      requestId: requestId,
      generateAction: () => runtime.generateStructured(request),
    );

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
    return routeResolver.routes.keys.toList();
  }
}
