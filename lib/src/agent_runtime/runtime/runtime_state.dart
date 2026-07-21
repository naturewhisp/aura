/// Lifecycle states for an [InferenceRuntime] session as defined in INFERENCE_RUNTIME_CONTRACT.md.
enum RuntimeState {
  /// Runtime object exists but owns no active native/process resources.
  uninitialized,

  /// Backend startup, validation, or native initialization is running.
  initializing,

  /// Runtime can accept model-load operations but no required model is currently ready.
  ready,

  /// At least one model-load operation is active.
  loadingModel,

  /// At least one valid model handle is available and no generation is active.
  modelReady,

  /// At least one generation operation is active.
  generating,

  /// A model is being released.
  unloadingModel,

  /// Adapter is recovering from a backend failure.
  recovering,

  /// Runtime cannot serve requests until recovery or reinitialization.
  failed,

  /// Cleanup is active and no new work is accepted.
  disposing,

  /// Terminal state.
  disposed,
}

extension RuntimeStateX on RuntimeState {
  /// Whether the runtime is in a terminal or disposed state.
  bool get isDisposed =>
      this == RuntimeState.disposing || this == RuntimeState.disposed;

  /// Whether the runtime is actively executing generation or model operations.
  bool get isBusy =>
      this == RuntimeState.initializing ||
      this == RuntimeState.loadingModel ||
      this == RuntimeState.generating ||
      this == RuntimeState.unloadingModel ||
      this == RuntimeState.recovering ||
      this == RuntimeState.disposing;
}
