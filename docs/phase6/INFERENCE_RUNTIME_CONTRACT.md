# Inference Runtime Contract Specification

**Project:** A.U.R.A. — Artificial Unbound Reasoning Arena  
**Target path:** `docs/phase6/INFERENCE_RUNTIME_CONTRACT.md`  
**Status:** Revised after repository-aware review; proposed for approval  
**Phase:** 6.0 — Architecture and Distribution Design Gate  
**Parent decision:** `docs/phase6/CROSS_PLATFORM_RUNTIME_ADR.md`  
**Repository baseline:** `5d5f32533a520e5a224a53462a711f52410055ed`  
**Primary implementation target:** Windows x64  
**Secondary implementation target:** Android arm64, Phase 7  
**Document revision:** 1.1  
**Review basis:** repository-aware review performed after the first draft  
**Last updated:** 2026-07-20

---

## 1. Purpose

This specification defines the platform-neutral contract between the A.U.R.A. agent layer and any local inference backend.

The contract must support:

- Windows production inference through a managed `llama-server` sidecar;
- Android production inference through an in-process native adapter;
- LM Studio or another OpenAI-compatible endpoint as a development-only adapter;
- deterministic and mock implementations for tests;
- text generation for the Actor;
- structured generation for the Evaluator;
- model lifecycle, health, cancellation, timeouts, failures, and diagnostics;
- future streaming and LoRA extensions without redesigning the gameplay core.

The contract is intentionally independent from:

- HTTP;
- OpenAI request/response payloads;
- llama.cpp command-line options;
- native pointers;
- Kotlin/JNI types;
- Dart FFI types;
- operating-system paths;
- model-provider repository names.

---

## 2. Relationship to Existing Runtime Code

The current runtime exposes an `InferenceBridge` with operations comparable to:

```dart
generateText(...)
generateStructured(...)
discoverModels()
```

The current HTTP implementation also owns several responsibilities:

- transport to an OpenAI-compatible local endpoint;
- request formatting;
- model selection through physical model IDs;
- text cleanup;
- reasoning-content handling;
- duplicate-response detection;
- CJK filtering;
- structured JSON parsing and validation support.

Phase 6 separates these responsibilities.

Target direction:

```text
Agent
  |
  v
RuntimeInferenceBridge
  |
  +-- prompt/output policy
  +-- logical role resolution
  +-- local validation
  |
  v
InferenceRuntime
  |
  +-- runtime lifecycle
  +-- model lifecycle
  +-- generation
  +-- cancellation
  +-- health
  |
  v
Platform adapter
```

The existing behavior must be preserved during migration. The contract is introduced before the production backend is replaced.

---

## 3. Design Goals

The runtime contract must be:

### 3.1 Platform-neutral

No public type may depend on:

```text
dart:io Process
HTTP status codes
localhost ports
Windows paths
Android Context
JNI handles
Pointer<T>
llama.cpp native structs
```

### 3.2 Explicit about lifecycle

The contract must distinguish:

```text
runtime initialization
runtime readiness
model loading
model readiness
generation
model unloading
runtime disposal
runtime crash
```

### 3.3 Typed

Requests, results, capabilities, state, and failures must use explicit immutable Dart types.

Dynamic maps are allowed only at bounded serialization or schema boundaries.

### 3.4 Testable

Every implementation must be executable against a shared contract test suite.

### 3.5 Minimal but extensible

The first implementation must not require:

- token streaming;
- batching;
- embeddings;
- remote inference;
- LoRA hot swapping;
- multimodal inputs.

The contract must, however, avoid making those features impossible.

### 3.6 Independent from gameplay semantics

The runtime does not know:

- pillars;
- Alert;
- PANOPTICON traits;
- hidden tags;
- victory conditions;
- DeceptionState;
- objective rules.

It receives inference requests and returns model outputs plus runtime metadata.

---

## 4. Non-Goals

This specification does not define:

- model manifest JSON format;
- model download protocol;
- hardware tier thresholds;
- installer behavior;
- Windows executable packaging;
- Android plugin implementation;
- prompt content;
- Evaluator scoring rules;
- Actor tone validation rules;
- LoRA training or adapter distribution;
- final runtime file layout.

These are defined in separate Phase 6 documents.

---

## 5. Package and Dependency Boundary

Recommended logical placement:

```text
lib/src/agent_runtime/
  runtime/
    inference_runtime.dart
    runtime_factory.dart
    runtime_state.dart
    runtime_capabilities.dart
    runtime_health.dart
    runtime_failure.dart
    model_handle.dart
    requests/
    results/
    diagnostics/
    adapters/
```

Possible adapter placement:

```text
lib/src/agent_runtime/runtime/adapters/
  mock/
  rule_based/
  external_openai/
```

Platform-specific implementations should remain outside the platform-neutral core when they require OS APIs:

```text
app/lib/src/platform/windows/
  managed_llama_server_runtime.dart

app/lib/src/platform/android/
  android_llama_native_runtime.dart
```

The final package split may change, but the dependency direction must remain:

```text
platform adapter
      |
      v
platform-neutral runtime contracts
      |
      v
agents/gameplay consumers
```

The reverse dependency is forbidden.

---

## 6. Core Interface

The target contract is conceptually:

```dart
abstract interface class InferenceRuntime {
  RuntimeState get state;

  Stream<RuntimeEvent> get events;

  Future<RuntimeCapabilities> initialize(
    RuntimeInitializationRequest request,
  );

  Future<ModelHandle> loadModel(
    ModelLoadRequest request,
  );

  Future<void> unloadModel(
    ModelHandle handle,
  );

  Future<TextGenerationResult> generateText(
    TextGenerationRequest request,
  );

  Future<StructuredGenerationResult> generateStructured(
    StructuredGenerationRequest request,
  );

  Future<void> cancel(
    GenerationRequestId requestId,
  );

  Future<RuntimeHealth> health();

  Future<void> dispose();
}
```

This is the normative responsibility set. Exact Dart syntax may be adjusted during implementation only if the semantic guarantees remain unchanged.

---

## 7. Runtime State Model

### 7.1 Runtime states

```dart
enum RuntimeState {
  uninitialized,
  initializing,
  ready,
  loadingModel,
  modelReady,
  generating,
  unloadingModel,
  recovering,
  failed,
  disposing,
  disposed,
}
```

### 7.2 State meaning

| State | Meaning |
|---|---|
| `uninitialized` | Runtime object exists but owns no active native/process resources. |
| `initializing` | Backend startup, validation, or native initialization is running. |
| `ready` | Runtime can accept model-load operations but no required model is currently ready. |
| `loadingModel` | At least one model-load operation is active. |
| `modelReady` | At least one valid model handle is available and no generation is active. |
| `generating` | At least one generation is active. |
| `unloadingModel` | A model is being released. |
| `recovering` | Adapter is recovering from a backend failure. |
| `failed` | Runtime cannot serve requests until recovery or reinitialization. |
| `disposing` | Cleanup is active and no new work is accepted. |
| `disposed` | Terminal state. |

### 7.3 State invariants

1. `initialize()` is valid only from `uninitialized` or from a recoverable `failed` state if explicitly supported.
2. `loadModel()` requires runtime state `ready` or `modelReady`.
3. `generate*()` requires a valid `ModelHandle`.
4. `unloadModel()` rejects an unknown or invalidated handle.
5. `dispose()` is idempotent.
6. No new generation is accepted while disposing.
7. A runtime crash invalidates every model handle created by that runtime session.
8. Cancellation does not automatically unload the model.
9. A failed request must not silently leave the runtime in `generating`.
10. State transitions must emit a `RuntimeEvent`.

### 7.4 Concurrent state representation

An implementation may internally support multiple simultaneous generations or model loads. The public state remains a summarized state.

Detailed active-operation counts belong to `RuntimeHealth` or diagnostics, not to gameplay code.

---

## 8. Runtime Initialization

### 8.1 Request

```dart
@immutable
class RuntimeInitializationRequest {
  final RuntimeInstanceId instanceId;
  final RuntimeBackendPreference backendPreference;
  final RuntimeResourceLimits resourceLimits;
  final Duration startupTimeout;
  final bool diagnosticsEnabled;
  final Map<String, String> adapterOptions;
}
```

### 8.2 Rules

- `instanceId` identifies one runtime session and must be unique for the application process.
- `backendPreference` is advisory; adapters may return the selected backend.
- `resourceLimits` expresses application policy, not native implementation details.
- `adapterOptions` is reserved for composition-root configuration and must not be populated by agents or widgets.
- Unknown adapter options must be rejected or explicitly reported, not silently ignored.
- Initialization must verify the backend before returning success.

### 8.3 Result

`initialize()` returns `RuntimeCapabilities`.

It must not return before the runtime can reliably answer `health()`.

For a Windows sidecar, successful initialization means:

```text
verified executable
process started
loopback endpoint established
runtime identity verified
health/readiness passed
```

For Android, it means:

```text
native library loaded
native context initialized
worker infrastructure ready
capabilities discovered
```

---

## 9. Runtime Capabilities

### 9.1 Type

```dart
@immutable
class RuntimeCapabilities {
  final RuntimeAdapterId adapterId;
  final String runtimeName;
  final String runtimeVersion;
  final String runtimeBuildId;
  final RuntimeBackend selectedBackend;
  final Set<GenerationCapability> generationCapabilities;
  final Set<ModelCapability> modelCapabilities;
  final int maxConcurrentGenerations;
  final int maxLoadedModels;
  final bool supportsCancellation;
  final bool supportsHealthCheck;
  final bool supportsTokenStreaming;
  final bool supportsGrammarConstraints;
  final bool supportsJsonSchema;
  final bool supportsLoRA;
  final Map<String, Object?> extensions;
}
```

### 9.2 Generation capabilities

```dart
enum GenerationCapability {
  text,
  structuredJson,
  tokenStreaming,
  cancellation,
  deterministicSeed,
  grammarConstraint,
  jsonSchemaConstraint,
  nativeReasoningField,
}
```

### 9.3 Model capabilities

```dart
enum ModelCapability {
  multipleLoadedModels,
  sequentialResidency,
  sharedModelAcrossRoles,
  gpuOffload,
  cpuExecution,
  contextResize,
  loRAAdapter,
  hotLoRASwap,
}
```

### 9.4 Capability rules

- Consumers must check capabilities rather than infer them from adapter names.
- An adapter name such as `managed_llama_server` must not be used as a feature flag.
- Optional capabilities must have defined fallback behavior.
- `supportsJsonSchema == true` does not remove local output validation.
- `supportsTokenStreaming == false` is valid for Phase 6.
- Extension keys must be namespaced, for example:

```text
llama_cpp.flash_attention
external_openai.reasoning_content
android.thermal_observer
```

Gameplay code must not depend on extension keys.

---

## 10. Backend Preference and Selection

### 10.1 Common enum

```dart
enum RuntimeBackendPreference {
  automatic,
  cuda,
  vulkan,
  cpu,
  systemManaged,
}
```

### 10.2 Selected backend

```dart
enum RuntimeBackend {
  cuda,
  vulkan,
  cpu,
  systemManaged,
  external,
  mock,
  deterministic,
}
```

### 10.3 Rules

- `automatic` delegates selection to the platform adapter and hardware profile.
- The runtime reports the actual selected backend.
- Unsupported explicit preferences return a typed failure unless policy permits fallback.
- Silent fallback from CUDA to CPU is not allowed unless the request explicitly enables fallback.
- Backend selection is outside the Game Controller.

---

## 11. Model Handle

### 11.1 Purpose

A `ModelHandle` represents a model loaded into one runtime session.

It replaces physical model identifiers in generation calls.

### 11.2 Type

```dart
@immutable
class ModelHandle {
  final ModelHandleId id;
  final RuntimeInstanceId runtimeInstanceId;
  final String logicalModelId;
  final String modelVariantId;
  final Set<ModelRole> roles;
  final DateTime loadedAt;
  final Map<String, Object?> runtimeMetadata;
}
```

### 11.3 Rules

- The handle is opaque to agents.
- Physical paths are not exposed.
- Native pointers are not exposed.
- A handle is valid only for its originating runtime instance.
- A handle becomes invalid after:
  - explicit unload;
  - runtime crash;
  - runtime disposal;
  - adapter-declared fatal model error.
- Handle equality is based on typed IDs, not object identity.
- `runtimeMetadata` is diagnostic and must not drive gameplay decisions.

### 11.4 Model roles

```dart
enum ModelRole {
  evaluator,
  actor,
  shared,
  memory,
  testing,
}
```

A shared model may support both Evaluator and Actor roles.

---

## 12. Model Loading

### 12.1 Request

```dart
@immutable
class ModelLoadRequest {
  final ModelLoadRequestId requestId;
  final ResolvedModelArtifact artifact;
  final String logicalModelId;
  final Set<ModelRole> roles;
  final ModelLoadOptions options;
  final Duration timeout;
}
```

### 12.2 Resolved artifact boundary

`ResolvedModelArtifact` is produced by the Model Manager after:

- manifest resolution;
- platform selection;
- installation check;
- integrity verification;
- runtime compatibility check.

The runtime must not download models.

Conceptually:

```dart
@immutable
class ResolvedModelArtifact {
  final String modelVariantId;
  final Uri localArtifactUri;
  final String sha256;
  final String format;
  final String quantization;
  final String architecture;
  final ModelRuntimeCompatibility compatibility;
}
```

`localArtifactUri` is interpreted by the platform adapter. Gameplay code must not inspect it.

### 12.3 Load options

```dart
@immutable
class ModelLoadOptions {
  final int? contextSize;
  final int? gpuLayerCount;
  final int? cpuThreadCount;
  final int? batchSize;
  final bool? memoryMap;
  final bool? memoryLock;
  final bool allowFallback;
  final Map<String, Object?> adapterOptions;
}
```

### 12.4 Rules

- Options are resolved from hardware and model profiles.
- Widgets must not construct low-level load options.
- Unsupported options return warnings or typed failures according to the contract.
- The runtime returns only after the model is usable.
- A load timeout must trigger cleanup of partial model state.
- Duplicate requests for the same artifact may:
  - reuse an existing handle;
  - return a new logical binding to the same native model;
  - fail as duplicate.

  The adapter must document its behavior and contract tests must verify it.
- Model integrity must be checked before calling `loadModel()`.
- The runtime may perform an additional format/header validation.

---

## 13. Model Unloading

### 13.1 Operation

```dart
Future<void> unloadModel(ModelHandle handle);
```

### 13.2 Rules

- Active generation behavior must be deterministic:
  - reject unload while in use; or
  - cancel active requests before unload if policy explicitly allows it.
- Silent forced cancellation is prohibited.
- Successful unload invalidates the handle.
- Repeated unload of the same handle returns an `invalidModelHandle` failure or an explicitly documented idempotent success.
- Native and sidecar resources must be released.
- Model unload must emit an event.
- Runtime disposal unloads all models.

---

## 14. Text Generation Request

### 14.1 Type

```dart
@immutable
class TextGenerationRequest {
  final GenerationRequestId requestId;
  final ModelHandle model;
  final List<InferenceMessage> messages;
  final GenerationParameters parameters;
  final Duration timeout;
  final InferenceTraceContext traceContext;
}
```

### 14.2 Messages

```dart
@immutable
class InferenceMessage {
  final InferenceRole role;
  final String content;
}

enum InferenceRole {
  system,
  user,
  assistant,
}
```

The first contract version supports text-only messages.

### 14.3 Parameters

```dart
@immutable
class GenerationParameters {
  final double temperature;
  final int maxOutputTokens;
  final double? topP;
  final int? topK;
  final double? repetitionPenalty;
  final int? seed;
  final ThinkingPolicy thinkingPolicy;
  final List<String> stopSequences;
  final Map<String, Object?> adapterOptions;
}
```

### 14.4 Thinking policy

```dart
enum ThinkingPolicy {
  runtimeDefault,
  disabled,
  enabled,
}
```

Rules:

- `thinkingPolicy` is a capability hint.
- An unsupported explicit `enabled` request returns a warning or typed unsupported-capability failure according to policy.
- Reasoning content must not be exposed to the player.
- The bridge/output policy decides whether a native reasoning field may be used for recovery.
- No contract type assumes OpenAI's `reasoning_content` field.

### 14.5 Request invariants

- `requestId` must be unique among active requests.
- `messages` must not be empty.
- `maxOutputTokens` must be positive and bounded by application policy.
- `temperature` must be finite and in the accepted application range.
- The model handle must be valid and support the requested role.
- Timeout must be positive.
- Adapter options must be provided only by trusted application configuration.

---

## 15. Text Generation Result

### 15.1 Type

```dart
@immutable
class TextGenerationResult {
  final GenerationRequestId requestId;
  final ModelHandle model;
  final String content;
  final GenerationFinishReason finishReason;
  final GenerationUsage usage;
  final Duration latency;
  final List<RuntimeWarning> warnings;
  final Map<String, Object?> adapterMetadata;
}
```

### 15.2 Finish reasons

```dart
enum GenerationFinishReason {
  completed,
  stopSequence,
  maxTokens,
  cancelled,
  timeout,
  contentRejected,
  backendError,
}
```

### 15.3 Usage

```dart
@immutable
class GenerationUsage {
  final int? inputTokens;
  final int? outputTokens;
  final int? reasoningTokens;
  final int? cachedInputTokens;
}
```

Token usage may be unavailable.

### 15.4 Content rules

The runtime result contains backend-produced text.

It is not guaranteed to be:

- diegetically valid;
- free from reasoning;
- free from duplicates;
- free from CJK output;
- enclosed in `<dialogo>`;
- safe to render.

Those guarantees remain in the bridge/output-validation layer.

---

## 16. Structured Generation Request

### 16.1 Type

```dart
@immutable
class StructuredGenerationRequest {
  final GenerationRequestId requestId;
  final ModelHandle model;
  final List<InferenceMessage> messages;
  final JsonSchemaDocument schema;
  final StructuredGenerationParameters parameters;
  final Duration timeout;
  final InferenceTraceContext traceContext;
}
```

### 16.2 Schema type

```dart
@immutable
class JsonSchemaDocument {
  final String schemaId;
  final Map<String, Object?> document;
  final bool rejectUnknownProperties;
}
```

### 16.3 Parameters

```dart
@immutable
class StructuredGenerationParameters {
  final double temperature;
  final int maxOutputTokens;
  final int? seed;
  final StructuredOutputMode mode;
  final Map<String, Object?> adapterOptions;
}
```

### 16.4 Output modes

```dart
enum StructuredOutputMode {
  automatic,
  jsonSchema,
  grammar,
  promptConstrained,
}
```

Rules:

- `automatic` selects the strongest supported mode.
- `jsonSchema` requires native schema support.
- `grammar` requires grammar support.
- `promptConstrained` allows plain generation followed by strict local parsing.
- Unsupported explicit modes return `structuredOutputUnavailable`.
- The runtime does not apply gameplay clamps.
- The Evaluator's `OutputValidator` remains authoritative.

---

## 17. Structured Generation Result

### 17.1 Type

```dart
@immutable
class StructuredGenerationResult {
  final GenerationRequestId requestId;
  final ModelHandle model;
  final String rawContent;
  final Map<String, Object?>? parsedObject;
  final StructuredOutputMode appliedMode;
  final GenerationFinishReason finishReason;
  final GenerationUsage usage;
  final Duration latency;
  final List<RuntimeWarning> warnings;
  final Map<String, Object?> adapterMetadata;
}
```

### 17.2 Rules

- `rawContent` is retained for diagnostics and local validation.
- `parsedObject` may be null when parsing is delegated to `OutputValidator`.
- A non-null `parsedObject` is not automatically trusted.
- Unknown fields remain subject to application schema policy.
- Malformed JSON returns a generation result only if the adapter completed successfully and parsing is intentionally delegated; otherwise it returns a typed generation failure.
- Adapter behavior must be consistent and documented.

Recommended Phase 6 behavior:

```text
runtime returns rawContent
RuntimeInferenceBridge invokes existing OutputValidator
EvaluatorAgent receives validated EvaluatorDelta
```

This preserves current validation logic.

---

## 18. RuntimeInferenceBridge

### 18.1 Purpose

`RuntimeInferenceBridge` adapts the new runtime contract to the agent-facing interface.

Responsibilities:

- receive the logical model role required by the calling agent;
- resolve that role through the active `ModelExecutionPlan`;
- obtain the corresponding valid `ModelHandle`;
- generate a unique `GenerationRequestId` for every runtime request;
- retain the association between the agent invocation, trace context and runtime request;
- build runtime requests from agent messages;
- apply application timeout policy;
- call `generateText()` or `generateStructured()`;
- invoke `cancel(requestId)` when the application-level timeout expires;
- preserve existing output cleanup;
- apply local structured parsing;
- map runtime failures to agent fallback policy;
- record runtime trace metadata.

It does not:

- expose physical model IDs or `ModelHandle` objects to `EvaluatorAgent` or `ActorAgent`;
- require agents to generate request IDs;
- start platform processes directly;
- download models;
- choose physical model files;
- inspect hardware;
- update gameplay state.

Normative rule:

```text
EvaluatorAgent and ActorAgent request a ModelRole.
RuntimeInferenceBridge resolves the ModelRole to a ModelHandle.
Agents never receive or transmit provider model IDs, physical filenames,
local model paths or runtime-native handles.
```

### 18.2 Migration compatibility

During migration, `InferenceBridge` may remain the agent-facing interface while its implementation changes:

```text
EvaluatorAgent / ActorAgent
        |
        v
InferenceBridge
        |
        v
RuntimeInferenceBridge
        |
        v
InferenceRuntime
```

A later cleanup may merge or rename these layers, but Phase 6 must avoid simultaneous agent and runtime rewrites unless necessary.

### 18.3 Output policy extraction

The following existing behaviors must be extracted into reusable policies rather than tied to the external HTTP adapter:

```text
dialogue-tag extraction
truncated-dialogue recovery
reasoning-text exclusion
native-reasoning-field recovery
duplicate-response rejection
CJK safety rejection
character-prefix cleanup
example-prompt rejection
empty-response rejection
```

Suggested components:

```text
ActorOutputSanitizer
ReasoningContentPolicy
DuplicateResponseGuard
CharacterSetGuard
StructuredOutputParser
```

### 18.4 Request identity and cancellation ownership

`GenerationRequestId` is an infrastructure concern owned by `RuntimeInferenceBridge`.

The agents must not generate, persist or interpret runtime request IDs.

Required flow:

```text
EvaluatorAgent / ActorAgent
        |
        | ModelRole + messages + agent timeout policy
        v
RuntimeInferenceBridge
        |
        +-- generate GenerationRequestId
        +-- resolve ModelRole to ModelHandle
        +-- create runtime request
        +-- retain request correlation
        +-- await runtime result
        |
        +-- on application timeout:
                call InferenceRuntime.cancel(requestId)
                await bounded cancellation completion
                map result to agent fallback policy
```

Rules:

1. Every active runtime generation has exactly one `GenerationRequestId`.
2. The bridge stores the association between:
   - agent invocation;
   - `GenerationRequestId`;
   - `RuntimeTraceId`;
   - `ModelRole`;
   - resolved `ModelHandle`.
3. An application-level timeout must request runtime cancellation before the bridge returns the timeout outcome to the agent layer.
4. Cancellation has a short, separate timeout and must not reuse the generation timeout.
5. If cancellation succeeds, the model remains loaded unless the adapter declares the model state invalid.
6. If cancellation fails or the backend state becomes uncertain, the adapter applies its recovery policy and reports the resulting runtime state.
7. `Future.timeout` without a corresponding `cancel(requestId)` call is non-compliant for production adapters.
8. Mock and deterministic runtimes must implement the same observable cancellation semantics.

### 18.5 Agent-facing model selection

The current agents receive model ID strings. This is a migration artifact and not the target contract.

Target agent invocation:

```dart
context.inferenceBridge.generateText(
  role: ModelRole.actor,
  messages: messages,
  parameters: parameters,
);
```

or an equivalent typed agent-facing request.

The bridge resolves:

```text
ModelRole
   ↓
active ModelExecutionPlan
   ↓
logical model binding
   ↓
valid ModelHandle
```

The implementation may retain the current `InferenceBridge` signature temporarily, but any model ID parameter used during migration must represent a logical role or logical model ID, never a provider ID such as a Hugging Face repository name.

Physical identifiers remain confined to:

```text
ModelManifest
ResolvedModelArtifact
ModelManager
platform runtime adapter
diagnostics
```

---

## 19. Cancellation

### 19.1 Contract

```dart
Future<void> cancel(GenerationRequestId requestId);
```

### 19.2 Rules

- Cancellation is cooperative when the backend supports it.
- `cancel()` must be safe to call from another async control flow.
- Unknown request IDs return an explicit `requestNotFound` or documented idempotent success.
- Successful cancellation completes the generation future with a typed cancellation outcome.
- Application-level timeout handling must invoke cancellation through `RuntimeInferenceBridge`.
- The bridge waits for cancellation only within a dedicated bounded timeout.
- Cancellation must not corrupt model state.
- Cancellation must not implicitly dispose the runtime.
- If the backend cannot cancel natively, the adapter may:
  - abandon the response;
  - terminate and recover the runtime;
  - return `cancellationUnsupported`.

The chosen behavior must be reported in capabilities and tested.

### 19.3 Windows sidecar

Cancellation may use:

- backend-specific cancellation support;
- request disconnection where reliable;
- process restart as a last-resort recovery policy.

Killing the entire sidecar for every cancellation is not acceptable as the default without measured justification.

### 19.4 Android

The Android adapter must provide a native cancellation flag or equivalent mechanism and must not block the Flutter main thread.

---

## 20. Timeout Policy

### 20.1 Layers

Timeouts exist at multiple levels:

```text
agent/application timeout
runtime request timeout
transport/native timeout
startup timeout
model-load timeout
shutdown timeout
```

They must not be conflated.

### 20.2 Rules

- The caller supplies the effective generation timeout.
- The adapter may enforce a stricter safety maximum.
- Timeout produces a typed failure distinct from cancellation.
- Timeout cleanup must leave the runtime in a known state.
- If backend state is uncertain after timeout, the adapter enters `recovering` or `failed`.
- HTTP transport timeout must not be the only timeout mechanism.
- Existing gameplay hard limits remain application policy and may be revised by hardware profile.

---

## 21. Concurrency and Serialization

### 21.1 Baseline policy

The contract supports concurrency conceptually, but the first production adapter may serialize requests.

Capabilities report:

```dart
maxConcurrentGenerations
maxLoadedModels
```

### 21.2 Rules

- The runtime must reject unsupported concurrency explicitly or queue requests deterministically.
- Queue behavior must be observable.
- Evaluator and Actor ordering remains controlled by the application.
- A queued request's timeout semantics must specify whether queue time is included.
- The recommended policy includes queue time in the request timeout.
- Model unload cannot race silently with generation.
- Contract tests must cover simultaneous requests even if the expected result is a typed rejection.

### 21.3 Multiple runtime instances

The application may create multiple runtime instances, for example one Evaluator sidecar and one Actor sidecar.

Each instance has:

- unique `RuntimeInstanceId`;
- independent state;
- independent handles;
- independent events;
- independent disposal.

A handle from one instance must be rejected by another.

---

## 22. Runtime Health

### 22.1 Type

```dart
@immutable
class RuntimeHealth {
  final RuntimeInstanceId instanceId;
  final RuntimeState state;
  final bool responsive;
  final DateTime observedAt;
  final Duration? uptime;
  final int activeGenerations;
  final int loadedModelCount;
  final RuntimeBackend backend;
  final RuntimeResourceSnapshot? resources;
  final List<RuntimeWarning> warnings;
  final RuntimeFailure? lastFailure;
}
```

### 22.2 Resource snapshot

```dart
@immutable
class RuntimeResourceSnapshot {
  final int? residentMemoryBytes;
  final int? deviceMemoryBytes;
  final double? cpuUtilization;
  final double? deviceUtilization;
  final double? temperatureCelsius;
}
```

Metrics are optional and platform-dependent.

### 22.3 Rules

- Health checks must be bounded by a short timeout.
- A health check cannot mutate gameplay.
- Health checks may trigger adapter recovery only according to explicit policy.
- Missing resource metrics do not imply an unhealthy runtime.
- UI may display diagnostics but must not interpret backend-specific details directly.

---

## 23. Runtime Events

### 23.1 Type family

```dart
sealed class RuntimeEvent {
  final RuntimeInstanceId instanceId;
  final DateTime timestamp;
  final RuntimeTraceId traceId;
}
```

Required event categories:

```text
RuntimeStateChanged
RuntimeInitialized
RuntimeInitializationFailed
RuntimeCrashed
RuntimeRecoveryStarted
RuntimeRecoveryCompleted
ModelLoadStarted
ModelLoadCompleted
ModelLoadFailed
ModelUnloadStarted
ModelUnloadCompleted
GenerationQueued
GenerationStarted
GenerationCompleted
GenerationCancelled
GenerationTimedOut
GenerationFailed
RuntimeWarningEmitted
RuntimeDisposing
RuntimeDisposed
```

### 23.2 Event rules

- Events are diagnostics and orchestration signals.
- Gameplay rules must not depend on event timing.
- Events must not include raw prompts by default.
- Events may include logical model ID and variant ID.
- Events must include correlation IDs sufficient for logs.
- Event streams close after disposal.

---

## 24. Trace Context

### 24.1 Type

```dart
@immutable
class InferenceTraceContext {
  final RuntimeTraceId traceId;
  final String sessionId;
  final int? gameplayTurnId;
  final String agentId;
  final String logicalModelId;
  final Map<String, String> tags;
}
```

### 24.2 Rules

- Trace context supports correlation across replay and runtime logs.
- Raw user content is not a trace tag.
- Tags must not include secrets.
- Runtime logs and replay logs remain distinct stores.
- A trace ID may be recorded in replay metadata without embedding backend logs.

---

## 25. Failure Model

### 25.1 Exception type

```dart
class RuntimeException implements Exception {
  final RuntimeFailure failure;
  final Object? cause;
  final StackTrace? stackTrace;
}
```

### 25.2 Failure type

```dart
@immutable
class RuntimeFailure {
  final RuntimeFailureCode code;
  final String message;
  final bool recoverable;
  final RuntimeRecoveryAction suggestedAction;
  final Map<String, Object?> diagnostics;
}
```

### 25.3 Failure codes

```dart
enum RuntimeFailureCode {
  invalidState,
  alreadyInitialized,
  disposed,
  runtimeUnavailable,
  runtimeInitializationFailed,
  runtimeIncompatible,
  runtimeCrashed,
  backendUnavailable,
  unsupportedBackend,
  unsupportedCapability,
  modelMissing,
  modelCorrupted,
  modelIncompatible,
  modelLoadFailed,
  invalidModelHandle,
  modelInUse,
  insufficientMemory,
  insufficientStorage,
  invalidRequest,
  duplicateRequestId,
  requestNotFound,
  generationFailed,
  structuredOutputUnavailable,
  malformedStructuredOutput,
  timeout,
  cancelled,
  cancellationUnsupported,
  networkUnavailable,
  permissionDenied,
  integrityCheckFailed,
  recoveryFailed,
  unknown,
}
```

### 25.4 Recovery actions

```dart
enum RuntimeRecoveryAction {
  none,
  retryRequest,
  reloadModel,
  restartRuntime,
  selectFallbackBackend,
  selectFallbackModel,
  freeStorage,
  closeOtherApplications,
  repairInstallation,
  reinstallRuntime,
  useDeterministicFallback,
  contactSupport,
}
```

### 25.5 Rules

- User-facing localization must not depend on parsing `message`.
- Recovery behavior depends on `code`, `recoverable`, and application policy.
- Native stack traces must not be shown directly to users.
- Diagnostics may include process exit code or native error code.
- Unknown errors must be wrapped as `unknown` while preserving cause for logs.
- The runtime does not decide whether a gameplay turn is retried or cancelled.

---

## 26. Warnings

Warnings represent degraded but successful behavior.

```dart
@immutable
class RuntimeWarning {
  final RuntimeWarningCode code;
  final String message;
  final Map<String, Object?> diagnostics;
}
```

Examples:

```text
requestedBackendUnavailableFallbackUsed
requestedContextReduced
tokenUsageUnavailable
thinkingPolicyIgnored
nativeStructuredOutputUnavailablePromptFallbackUsed
resourceMetricsUnavailable
modelAlreadyLoadedReused
```

Warnings must be recorded in diagnostics and may be surfaced in a technical UI, but must not alter gameplay directly.

---

## 27. Adapter Requirements

Every adapter must document:

```text
adapter ID
supported platforms
runtime/version discovery
supported backends
initialization behavior
model loading behavior
duplicate-load behavior
maximum loaded models
concurrency policy
cancellation behavior
timeout behavior
structured-output modes
health implementation
crash semantics
recovery behavior
disposal guarantees
diagnostic fields
security considerations
```

Every adapter must pass the common contract tests.

---

## 28. ManagedLlamaServerRuntime Requirements

The Windows production adapter must:

- launch only a verified pinned executable;
- bind to loopback only;
- use a session-specific runtime identity;
- select or allocate a safe local endpoint;
- capture stdout and stderr;
- wait for readiness;
- translate generic requests into server requests;
- map server failures to `RuntimeFailureCode`;
- validate the expected model/runtime state;
- terminate gracefully on dispose;
- enforce cleanup after timeout;
- avoid killing unrelated llama.cpp processes;
- invalidate handles after crash or restart;
- expose the actual llama.cpp build ID;
- keep HTTP details private to the adapter.

Its public type must implement `InferenceRuntime` without adding required Windows-specific methods.

---

## 29. ExternalOpenAiRuntime Requirements

The development compatibility adapter must:

- connect to an explicitly configured endpoint;
- never be selected silently in production;
- support LM Studio and compatible local servers where practical;
- treat remote or non-loopback endpoints as a separate explicit security mode;
- report `RuntimeBackend.external`;
- discover capabilities conservatively;
- avoid claiming model lifecycle ownership where the external server owns it;
- map external model identifiers to logical handles through configuration;
- preserve output cleanup and validation above the transport layer.

Because an external server may already own model loading, this adapter may implement `loadModel()` as logical binding rather than physical load. This deviation must be explicit in capabilities and diagnostics.

---

## 30. AndroidLlamaNativeRuntime Requirements

The Phase 7 adapter must:

- run inference outside the Flutter UI thread;
- load models through Android-compatible storage references;
- implement explicit teardown;
- support cancellation;
- surface low-memory failures;
- respond to application lifecycle;
- avoid assuming persistent process lifetime;
- expose thermal/resource degradation where available;
- use the same request/result/failure types;
- pass the same contract tests through Android instrumented tests.

It must not require changes to EvaluatorAgent, ActorAgent, GameController, PromptBuilder, or OutputValidator.

---

## 31. MockInferenceRuntime Requirements

The mock runtime is the default unit-test implementation.

It must support:

- configurable capabilities;
- configurable text results;
- configurable structured results;
- configurable delays;
- configurable failures;
- cancellation;
- state transitions;
- deterministic event emission;
- model-handle creation;
- invalid-handle checks;
- call recording.

It must not:

- use network;
- use files outside temporary fixtures;
- start processes;
- depend on native libraries.

---

## 32. RuleBasedInferenceRuntime Requirements

The deterministic runtime supports offline gameplay fallback.

It may:

- return heuristic structured Evaluator outputs;
- return hardcoded or rule-based Actor responses where configured;
- advertise only capabilities it actually implements.

It must not pretend to be a loaded language model.

Recommended capabilities:

```text
structuredJson
cancellation: optional/immediate
deterministicSeed: true
```

Model handles may be synthetic logical handles.

---

## 33. Security Requirements

### 33.1 Untrusted content

Prompts and model responses are untrusted content.

The runtime contract must not:

- execute model output;
- interpret model output as adapter options;
- allow prompts to alter runtime paths;
- allow prompts to select binaries;
- allow prompts to select model files.

### 33.2 Adapter options

`adapterOptions` are privileged configuration.

They may originate only from:

- versioned configuration;
- trusted composition-root setup;
- tests.

They must not originate from user chat input or LLM output.

### 33.3 Paths and URIs

Model artifacts must come from a verified `ResolvedModelArtifact`.

The runtime must not accept arbitrary paths from agents.

### 33.4 Local server

The Windows sidecar must not expose an externally reachable inference endpoint.

### 33.5 Logs

Default logs must not include:

- full prompts;
- full raw responses;
- authentication tokens;
- private filesystem paths where avoidable;
- user-identifying OS data.

Debug logging of content must be opt-in and clearly marked.

---

## 34. Versioning and Compatibility

### 34.1 Contract version

The runtime contract must expose a semantic contract version:

```dart
const runtimeContractVersion = '1.0.0';
```

Adapters declare the supported range.

### 34.2 Compatibility rules

- Breaking changes increment the major version.
- New optional fields increment the minor version.
- Documentation or non-semantic fixes increment the patch version.
- Serialized diagnostic data must include its schema version.
- Model manifests declare compatible runtime contract and runtime build ranges.
- A runtime incompatibility fails before model loading.

### 34.3 Extension fields

Extensions permit adapter evolution but cannot substitute for common fields.

A feature required by multiple production adapters must be promoted into the common contract.

---

## 35. Migration Plan from Current InferenceBridge

### Stage 1 — Add contract types

Introduce:

```text
InferenceRuntime
RuntimeState
RuntimeCapabilities
ModelHandle
request/result types
failure types
MockInferenceRuntime
```

No production behavior changes.

### Stage 2 — Implement bridge adapter

Create:

```text
RuntimeInferenceBridge
```

Allow agents to continue using the existing `InferenceBridge` interface temporarily.

During this stage:

- introduce `ModelRole`-based resolution inside the bridge;
- stop propagating provider model IDs beyond the model-management boundary;
- generate `GenerationRequestId` inside the bridge;
- connect application timeout handling to runtime cancellation;
- preserve existing LM Studio behavior through the external adapter.

### Stage 3 — Wrap current HTTP implementation

Refactor current HTTP behavior into:

```text
ExternalOpenAiRuntime
ActorOutputSanitizer
StructuredOutputParser
```

Keep LM Studio working.

### Stage 4 — Move construction

Replace direct backend creation in `main.dart` with injected platform services.

### Stage 5 — Implement managed Windows runtime

Add `ManagedLlamaServerRuntime` and native smoke tests.

### Stage 6 — Retire legacy names

After functional parity:

- deprecate `LocalApiInferenceBridge`;
- remove LM Studio terminology from production defaults;
- retain explicit development compatibility configuration.

---

## 36. Shared Contract Test Suite

Recommended test entry point:

```dart
void runInferenceRuntimeContractTests(
  String adapterName,
  Future<InferenceRuntime> Function() createRuntime,
  RuntimeContractTestProfile profile,
);
```

### 36.1 Mandatory tests

#### Lifecycle

```text
starts uninitialized
initializes successfully
rejects generation before initialization
rejects generation before model load
dispose is idempotent
rejects work after dispose
emits state events in valid order
```

#### Model handles

```text
loads a model and returns a valid handle
rejects handle from another runtime
invalidates handle after unload
invalidates all handles after crash/dispose
handles duplicate load according to declared policy
```

#### Text generation

```text
returns content and finish reason
returns trace-correlated request ID
enforces invalid request checks
maps timeout
maps backend failure
records warnings
```

#### Structured generation

```text
uses strongest supported mode for automatic
rejects unsupported explicit mode
retains raw content
does not bypass local validation expectations
```

#### Cancellation

```text
cancels an active request
does not corrupt model state
handles unknown request ID
reports unsupported cancellation correctly
```

#### Concurrency

```text
serializes, queues, or rejects according to capabilities
does not race unload with generation
includes queue time in timeout according to policy
```

#### Health and recovery

```text
health reflects current state
crash changes state and invalidates handles
recovery emits events
failed recovery returns typed error
```

### 36.2 Adapter-specific tests

Adapter-specific tests are additional and must not replace common contract tests.

---

## 37. Acceptance Criteria

This specification is approved when all statements below are accepted:

```text
- InferenceRuntime is the platform-neutral lifecycle boundary.
- Agents do not depend directly on HTTP, sidecar, FFI, or JNI.
- ModelHandle replaces physical model IDs in runtime generation calls.
- EvaluatorAgent and ActorAgent request only a logical `ModelRole`.
- RuntimeInferenceBridge owns ModelRole-to-ModelHandle resolution.
- RuntimeInferenceBridge owns `GenerationRequestId` creation and timeout-triggered cancellation.
- Provider model IDs never cross into agent-facing APIs.
- The runtime does not download or resolve models.
- RuntimeInitialization, ModelLoad, Generation, Health, and Disposal are distinct operations.
- Text and structured generation use typed requests and results.
- Existing output cleanup and validation remain above the transport adapter.
- Cancellation, timeout, state, capabilities, events, and failures are explicit.
- The first contract version may be non-streaming.
- Windows, external HTTP, Android, mock, and deterministic adapters implement the same semantics.
- Standard tests use mock or deterministic runtime implementations.
- Every adapter must pass shared contract tests.
```

---

## 38. Exit Criteria for This Document

The document is complete when:

- committed under `docs/phase6/INFERENCE_RUNTIME_CONTRACT.md`;
- reviewed against `CROSS_PLATFORM_RUNTIME_ADR.md`;
- reviewed against the current `InferenceBridge` and agent usage;
- no public API requires Windows or Android implementation details;
- contract tests can be designed without a real model;
- the Model Manifest and Model Lifecycle specifications can reference the types defined here;
- the repository-review findings on logical-role resolution and request-ID ownership are incorporated;
- Antigravity can identify migration impact without inventing a competing runtime contract.

---

## 39. Recommended Antigravity Review Prompt

After committing this document:

```text
Read these documents in full:

- docs/phase6/CROSS_PLATFORM_RUNTIME_ADR.md
- docs/phase6/INFERENCE_RUNTIME_CONTRACT.md

Analyze the repository against the proposed runtime contract.
Do not modify code or documentation.

Produce a report with:

1. current InferenceBridge implementations and consumers;
2. every file affected by introducing InferenceRuntime;
3. responsibilities currently mixed inside LocalApiInferenceBridge;
4. output-cleaning logic that must be extracted and preserved;
5. lifecycle or concurrency assumptions in the current code;
6. tests that can become shared contract tests;
7. incompatibilities between this specification and the current implementation;
8. minimal migration steps that preserve LM Studio behavior temporarily;
9. risks of dependency cycles between aura_core and the Flutter app;
10. suggested changes to the contract, each clearly marked as a proposed deviation.

Do not implement Phase 6.1 yet.
Do not silently redefine the contract.
```

---

## 40. Final Contract Decision

A.U.R.A. will use a typed, platform-neutral `InferenceRuntime` contract as the sole lifecycle boundary for local model execution.

The Windows managed sidecar, Android native runtime, external OpenAI-compatible development adapter, mock runtime, and deterministic fallback will implement the same model-loading, generation, cancellation, health, failure, and disposal semantics.

Transport-specific behavior remains private to adapters. Agent-facing calls use logical model roles; `RuntimeInferenceBridge` resolves those roles to valid runtime handles, creates request IDs and coordinates timeout-driven cancellation. Output validation and gameplay authority remain outside the runtime. This preserves the existing deterministic architecture while enabling Windows production packaging and Android integration without complex refactoring.
