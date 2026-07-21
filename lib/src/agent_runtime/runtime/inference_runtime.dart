import 'model_handle.dart';
import 'runtime_capabilities.dart';
import 'runtime_events.dart';
import 'runtime_health.dart';
import 'runtime_ids.dart';
import 'runtime_requests.dart';
import 'runtime_results.dart';
import 'runtime_state.dart';

/// Semantic contract version for the Inference Runtime interface.
const String runtimeContractVersion = '1.0.0';

/// Platform-neutral contract interface between A.U.R.A. agent layer and local inference backends.
abstract interface class InferenceRuntime {
  /// Current state of the runtime session.
  RuntimeState get state;

  /// Stream of state changes, lifecycle, and operational events.
  Stream<RuntimeEvent> get events;

  /// Initializes the runtime environment and verifies backend readiness.
  Future<RuntimeCapabilities> initialize(
    RuntimeInitializationRequest request,
  );

  /// Loads a resolved model artifact into the runtime session.
  Future<ModelHandle> loadModel(
    ModelLoadRequest request,
  );

  /// Unloads a model handle and releases native/process resources.
  Future<void> unloadModel(
    ModelHandle handle,
  );

  /// Executes plain text generation.
  Future<TextGenerationResult> generateText(
    TextGenerationRequest request,
  );

  /// Executes structured JSON generation constrained by schema.
  Future<StructuredGenerationResult> generateStructured(
    StructuredGenerationRequest request,
  );

  /// Requests cooperative cancellation of an active generation by request ID.
  Future<void> cancel(
    GenerationRequestId requestId,
  );

  /// Checks and returns detailed health metrics for the runtime session.
  Future<RuntimeHealth> health();

  /// Terminates the runtime session and releases all resources (idempotent).
  Future<void> dispose();
}
