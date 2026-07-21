/// Advisory preference for selecting an inference execution backend.
enum RuntimeBackendPreference {
  automatic,
  cuda,
  vulkan,
  cpu,
  systemManaged,
}

/// Actual execution backend selected and reported by an [InferenceRuntime].
enum RuntimeBackend {
  cuda,
  vulkan,
  cpu,
  systemManaged,
  external,
  mock,
  deterministic,
}
