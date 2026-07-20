# ADR-006 — Cross-Platform Edge Runtime Foundation

**Project:** A.U.R.A. — Artificial Unbound Reasoning Arena  
**Target path:** `docs/phase6/CROSS_PLATFORM_RUNTIME_ADR.md`  
**Status:** Proposed for approval  
**Decision scope:** Phase 6 — Cross-Platform Edge Runtime Foundation  
**Baseline repository commit:** `5d5f32533a520e5a224a53462a711f52410055ed`  
**Related document:** `AURA_TGDD_v1_1_revised.md`, version 1.5  
**Primary production target:** Windows x64  
**Secondary production target:** Android arm64, Phase 7  
**Last updated:** 2026-07-20

---

## 1. Purpose

This Architecture Decision Record defines the foundation that allows A.U.R.A. to:

1. remove LM Studio as a production dependency;
2. own the lifecycle of the local inference runtime;
3. load and execute local GGUF models on Windows;
4. prepare Android integration without rewriting gameplay, agents, prompts, model management, or test infrastructure;
5. keep application, runtime, models, LoRA adapters, user data, and release assets independently versioned;
6. make standard development and CI test suites deterministic and independent from real models.

This ADR establishes architectural boundaries and irreversible or expensive decisions. It does **not** fully specify every API, manifest field, installer screen, hardware threshold, or model variant. Those details belong to the focused Phase 6 specifications listed in §18.

---

## 2. Context

A.U.R.A. currently has a stable deterministic gameplay core and a playable PANOPTICON vertical slice. The runtime architecture was intentionally developed using LM Studio because it offered a convenient OpenAI-compatible local endpoint and simplified early model experimentation.

The current implementation still reflects that development setup:

- `app/lib/main.dart` creates a local HTTP inference bridge directly;
- the default endpoint assumes `http://127.0.0.1:1234`;
- `LocalApiInferenceBridge` is described and implemented around the LM Studio-compatible API;
- model discovery assumes that models have already been loaded by an external runtime;
- `ModelRouter` resolves roles from models exposed by that runtime;
- the application does not own process startup, shutdown, crash recovery, runtime selection, model installation, or model integrity;
- the standard test suite already uses mock and deterministic bridges, which provides a good basis for decoupling tests from real inference.

This architecture was valid for prototyping but is insufficient for a distributable product.

A production user must not be required to:

- install LM Studio;
- manually download models;
- manually select or load models;
- start an API server;
- configure a port;
- understand GGUF quantizations;
- keep runtime and model versions mutually compatible;
- repair missing or corrupted artifacts manually.

At the same time, a Windows-only implementation must not leak process management, HTTP, paths, registry concepts, or sidecar assumptions into the gameplay core, because Android will use a different execution mechanism.

---

## 3. Decision Summary

A.U.R.A. adopts the following architecture:

```text
Flutter Application
        |
        v
GameController + Agents
        |
        v
RuntimeInferenceBridge
        |
        v
InferenceRuntime contract
        |
        +-- ManagedLlamaServerRuntime   [Windows production]
        +-- AndroidLlamaNativeRuntime   [Android production, Phase 7]
        +-- ExternalOpenAiRuntime       [development compatibility]
        +-- MockInferenceRuntime        [unit/contract tests]
        +-- RuleBasedInferenceRuntime   [deterministic fallback]
        |
        v
ModelExecutionPlan + ModelManager
        |
        +-- manifests
        +-- installed artifacts
        +-- integrity verification
        +-- hardware profile
        +-- runtime compatibility
```

The principal decisions are:

1. **Windows production inference uses a managed `llama-server` sidecar in the first implementation.**
2. **Android production inference uses an in-process native runtime adapter.**
3. **HTTP/OpenAI compatibility is an adapter detail, not the core inference contract.**
4. **The gameplay core and agents depend only on platform-neutral Dart contracts.**
5. **LM Studio remains available only through an optional external-runtime development adapter.**
6. **Models are addressed by logical IDs, not by provider repository names or physical filenames.**
7. **Application, runtime, models, LoRA adapters, configuration, and user content are separately versioned artifacts.**
8. **The model execution plan may use two models, one shared model, sequential residency, or deterministic fallback depending on hardware.**
9. **Standard test suites never download, load, or require real GGUF models.**
10. **All platform-specific construction occurs in the application composition root.**
11. **Runtime and model artifacts are pinned and integrity-checked.**
12. **LoRA specialization is not implemented in Phase 6 and must consume the same runtime/model contracts later.**

---

## 4. Architectural Principles

### 4.1 Deterministic core, probabilistic runtime

The existing design rule remains authoritative:

```text
The LLM produces signals.
The Game Controller produces truth.
```

The runtime abstraction must not grant any inference backend authority over:

- metric application;
- safety overrides;
- hidden tags;
- deception transitions;
- victory or defeat;
- replay semantics;
- progression;
- persistence rules.

Runtime replacement must not alter gameplay behavior except where model quality, latency, or output characteristics are explicitly under test.

### 4.2 Platform neutrality

The following concepts must not appear in `aura_core` public or internal gameplay contracts:

```text
LM Studio
llama-server.exe
localhost ports
Windows Registry
%APPDATA%
%LOCALAPPDATA%
Process.start
Android Context
ContentResolver
WorkManager
JNI
FFI pointers
Kotlin Flow
CUDA DLL paths
Vulkan loader paths
```

Platform-specific code is allowed only behind adapters instantiated by the application layer.

### 4.3 Explicit ownership

A.U.R.A. must explicitly own or delegate each responsibility:

| Responsibility | Owner |
|---|---|
| Gameplay state and rules | `GameController` |
| Prompt construction | agent runtime |
| Runtime selection | `RuntimeFactory` |
| Runtime lifecycle | `InferenceRuntime` implementation |
| Model role selection | `ModelExecutionPlanResolver` |
| Model installation and integrity | `ModelManager` / `ModelStore` |
| Artifact download | `ArtifactDownloader` |
| Hardware detection | `HardwareProbe` |
| Runtime/model compatibility | manifest resolver |
| Platform paths | platform storage adapter |
| Window state | `WindowModeController` |
| Audio release assets | audio asset manager/resolver |
| Installer/update workflow | Windows distribution layer |
| UI state and progress | Flutter presentation layer |

No widget may directly start a process, resolve a GGUF path, or select a concrete inference backend.

### 4.4 Replaceable mechanisms

The architecture must allow the following replacements without modifying gameplay or agents:

- `llama-server` → native FFI runtime on Windows;
- one llama.cpp build → another pinned build;
- CUDA → Vulkan → CPU;
- two-model execution → shared single-model execution;
- local GGUF → AICore adapter where available;
- Ministral Evaluator → another compatible Evaluator;
- Gemma Actor → another compatible Actor;
- local HTTP adapter → in-process Android adapter.

---

## 5. Current-State Problems to Remove

### 5.1 Direct backend construction

`main.dart` currently instantiates the local API bridge directly. This creates a composition-root violation because application startup is tied to one development backend.

Required direction:

```text
Before:
main.dart
  -> LocalApiInferenceBridge(baseUrl: 127.0.0.1:1234)

After:
main.dart
  -> PlatformServices.bootstrap()
  -> RuntimeFactory.create(...)
  -> ModelExecutionPlanResolver.resolve(...)
  -> RuntimeInferenceBridge(...)
```

### 5.2 External process ownership

The current runtime assumes another application has already:

- installed the backend;
- started the server;
- selected the model;
- loaded the model;
- exposed the API.

In production, A.U.R.A. must manage these operations or provide a controlled fallback.

### 5.3 Physical model IDs in gameplay-facing configuration

Provider model IDs such as:

```text
mistralai/ministral-3-3b
google/gemma-4-12b
```

must not be treated as stable application contracts.

They describe a provider or development catalog entry, not the semantic role required by A.U.R.A.

The stable references must instead be:

```text
aura.evaluator.primary
aura.actor.primary
```

These logical IDs resolve to platform- and hardware-specific model variants.

### 5.4 Model discovery as routing

Discovering models already exposed by an external server is not sufficient model management.

Production routing must be based on:

- model manifests;
- installed artifacts;
- verified integrity;
- runtime compatibility;
- device capabilities;
- user-selected profile;
- fallback availability.

### 5.5 Test/runtime coupling risk

Real-model loading is expensive, nondeterministic, hardware-dependent, and unsuitable as an implicit requirement for `dart test` or `flutter test`.

The existing mock and rule-based infrastructure must be preserved and promoted into the formal runtime contract.

---

## 6. Target Component Boundaries

### 6.1 `aura_core`

`aura_core` contains:

- deterministic gameplay;
- game state;
- agents and their semantic contracts;
- prompt construction;
- output validation;
- replay domain models;
- platform-neutral runtime interfaces;
- platform-neutral model domain objects;
- mock and deterministic fallback implementations where appropriate.

It must not contain:

- process startup;
- OS-specific storage paths;
- installer logic;
- native library loading;
- Windows window APIs;
- Android platform APIs;
- concrete Hugging Face persistence behavior tied to one platform.

### 6.2 Flutter application layer

The Flutter application contains:

- composition root;
- runtime setup screens;
- model download/setup UX;
- runtime progress and diagnostic UX;
- settings;
- window mode UX;
- audio settings;
- presentation of typed failures;
- platform service selection.

It may depend on platform packages but must consume them through application services rather than spreading platform calls through widgets.

### 6.3 Windows platform adapter

The Windows adapter contains:

- sidecar process management;
- backend executable selection;
- port allocation;
- loopback health checks;
- runtime log capture;
- GPU/backend probing;
- Windows storage layout;
- window mode implementation;
- installed/portable mode detection;
- shutdown and orphan cleanup;
- integration points required by installer and updater.

### 6.4 Android platform adapter

The Android adapter, implemented in Phase 7, contains:

- native llama.cpp integration;
- Kotlin/JNI or Dart FFI boundary;
- model loading from Android-compatible storage;
- inference worker threading;
- token streaming;
- cancellation;
- lifecycle handling;
- thermal and memory signals;
- optional AICore adapter.

The Android adapter must implement the same platform-neutral runtime contract.

### 6.5 Distribution layer

The distribution layer contains:

- installer definitions;
- portable package rules;
- update/repair/uninstall rules;
- runtime manifest;
- model manifest;
- audio manifest;
- checksums and signatures;
- GitHub Actions release workflows;
- staging and rollback logic.

Distribution logic must not become a dependency of `aura_core`.

---

## 7. Inference Runtime Contract Direction

The exact API is finalized in `INFERENCE_RUNTIME_CONTRACT.md`. This ADR fixes its responsibilities.

A conceptual contract is:

```dart
abstract interface class InferenceRuntime {
  Future<RuntimeCapabilities> initialize(
    RuntimeInitializationRequest request,
  );

  Future<ModelHandle> loadModel(
    ModelLoadRequest request,
  );

  Future<void> unloadModel(
    ModelHandle handle,
  );

  Future<GenerationResult> generateText(
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

### 7.1 Required characteristics

The contract must:

- use typed requests and responses;
- support text and structured generation;
- represent runtime and model capabilities;
- support cancellation;
- expose health without revealing transport details;
- distinguish initialization from model loading;
- distinguish runtime readiness from model readiness;
- allow one or more loaded model handles;
- return typed failures;
- avoid embedding HTTP payloads in public interfaces;
- avoid requiring streaming in the first implementation while leaving an extension path.

### 7.2 Model handles

Agents must not use physical paths or runtime-native pointers. They receive or resolve a `ModelHandle` owned by the runtime layer.

A handle must be:

- opaque to gameplay;
- associated with a logical model role;
- invalid after unload or runtime disposal;
- traceable in diagnostics without exposing sensitive paths unnecessarily.

### 7.3 Structured generation

Structured generation is a capability, not an assumption.

A runtime may implement it through:

- grammar-constrained decoding;
- JSON schema support;
- constrained prompt plus strict parser;
- deterministic fallback.

The `EvaluatorAgent` continues to validate every result locally even when the backend claims structured-output support.

---

## 8. Runtime Lifecycle

The shared lifecycle is:

```text
uninitialized
    |
    v
initializing
    |
    +----> failed
    |
    v
ready
    |
    v
loadingModel
    |
    +----> failed
    |
    v
modelReady
    |
    v
generating
    |
    +----> modelReady
    +----> failed
    |
    v
unloading
    |
    v
ready
    |
    v
disposing
    |
    v
disposed
```

### 8.1 Lifecycle rules

1. `initialize()` is idempotent or rejects invalid repeated calls with a typed state error.
2. `loadModel()` cannot run before runtime readiness.
3. `generate*()` cannot run without a valid model handle.
4. Cancellation must not corrupt the loaded model state.
5. `dispose()` must attempt graceful shutdown and then enforce cleanup.
6. A runtime crash invalidates all model handles.
7. Recovery requires a new runtime session and explicit model reload.
8. UI lifecycle changes must not directly dispose a runtime unless application policy requires it.
9. Application exit must not leave sidecar processes running.

### 8.2 Typed runtime failures

The common failure taxonomy must include at least:

```text
runtimeUnavailable
runtimeInitializationFailed
runtimeCrashed
runtimeIncompatible
unsupportedHardware
backendUnavailable
modelMissing
modelCorrupted
modelIncompatible
modelLoadFailed
insufficientMemory
insufficientStorage
generationFailed
structuredOutputUnavailable
timeout
cancelled
networkUnavailable
integrityCheckFailed
permissionDenied
invalidState
```

Platform adapters map native errors to these common categories.

---

## 9. Windows Runtime Decision

### 9.1 Selected approach

The first Windows production implementation uses a managed `llama-server` process.

```text
A.U.R.A. Flutter app
        |
        v
ManagedLlamaServerRuntime
        |
        +-- select pinned executable/backend
        +-- allocate loopback endpoint
        +-- spawn child process
        +-- capture stdout/stderr
        +-- wait for readiness
        +-- submit inference requests
        +-- detect crash
        +-- terminate on shutdown
```

### 9.2 Why this approach

This choice:

- removes the end-user dependency on LM Studio;
- retains a stable process isolation boundary;
- reuses the existing OpenAI-compatible request path internally;
- reduces the first migration cost;
- avoids immediate ownership of unstable C APIs and memory management through FFI;
- allows backend-specific binaries;
- supports independent runtime crash handling;
- keeps Android free to use an in-process implementation.

### 9.3 Sidecar security requirements

The managed server must:

- bind only to loopback;
- never listen on all interfaces;
- use an automatically selected or reserved local port;
- prevent accidental attachment to an unrelated process;
- validate readiness against the expected runtime session;
- avoid accepting remote network traffic;
- not expose unrestricted filesystem paths;
- sanitize command-line logging when it contains user paths;
- use a pinned executable verified by checksum before launch.

A per-session local token or equivalent handshake should be used if supported by the chosen runtime integration. If not supported, process ownership, loopback binding, random port allocation, and session-specific readiness validation are mandatory compensating controls.

### 9.4 Process ownership rules

- The runtime process is a child owned by A.U.R.A.
- A process identifier alone is not sufficient identity; the executable path and session metadata must be validated.
- Startup creates a session marker.
- Normal exit requests graceful shutdown first.
- Forced termination is allowed after a bounded timeout.
- Startup must detect and clean only verified stale A.U.R.A.-owned processes.
- The application must never kill arbitrary `llama-server` processes started by the user or another application.

### 9.5 FFI decision

Direct Windows FFI is **deferred**.

It may be reconsidered only after production profiling identifies a material limitation that cannot be solved through the managed sidecar, such as:

- unacceptable latency caused specifically by IPC;
- memory duplication that materially blocks supported hardware;
- missing runtime features;
- inability to coordinate LoRA or model residency;
- packaging constraints.

A future FFI adapter must implement the same `InferenceRuntime` contract and must not require gameplay refactoring.

---

## 10. Android Runtime Direction

### 10.1 Selected architectural direction

Android uses an in-process native inference runtime behind the same Dart contract.

Candidate implementation mechanisms:

```text
Flutter plugin + Kotlin/JNI + llama.cpp
or
Dart FFI + packaged native libraries
```

The exact mechanism is deferred to the Phase 7 spike.

### 10.2 Android constraints prepared in Phase 6

Phase 6 contracts must not assume:

- a child process;
- a local port;
- OpenAI-compatible endpoints;
- desktop filesystem paths;
- unlimited background execution;
- simultaneous residency of two large models;
- discrete GPU semantics;
- persistent application process lifetime.

The shared model and runtime contracts must support:

- one model serving multiple roles;
- sequential model residency;
- explicit unload;
- low-memory failure;
- thermal degradation signals;
- user-approved multi-gigabyte downloads;
- app-specific storage;
- imported model artifacts;
- cancellation and teardown.

### 10.3 AICore position

AICore is an optional adapter, not the baseline dependency.

AICore may be selected only when:

- the required API is available;
- the device exposes a compatible model;
- required capabilities are present;
- quality and latency satisfy A.U.R.A. validation;
- structured evaluation can be made reliable.

AICore availability must not determine gameplay architecture.

---

## 11. Model Identity and Execution Plans

### 11.1 Logical model IDs

Stable application references:

```text
aura.evaluator.primary
aura.actor.primary
```

Optional future IDs:

```text
aura.evaluator.fallback
aura.actor.fallback
aura.shared.primary
aura.memory.optional
```

A logical ID resolves through a model manifest to one or more variants.

### 11.2 Physical variants

A physical variant contains information such as:

- provider;
- repository;
- pinned revision;
- filename;
- SHA-256;
- format;
- quantization;
- architecture;
- compatible platforms;
- compatible runtime range;
- minimum memory class;
- recommended backend;
- role suitability;
- chat template or prompt-format metadata;
- structured-output capability.

The definitive schema belongs to `MODEL_MANIFEST_SPEC.md`.

### 11.3 Execution plans

The application must not require exactly two simultaneously loaded models.

Supported policies:

```dart
enum ModelResidencyPolicy {
  simultaneous,
  sequential,
  sharedSingleModel,
  evaluatorDeterministic,
}
```

A conceptual plan:

```dart
class ModelExecutionPlan {
  final ResolvedModel evaluator;
  final ResolvedModel actor;
  final ModelResidencyPolicy residencyPolicy;
  final RuntimeBackendPreference backendPreference;
}
```

The resolver uses:

- platform;
- RAM;
- VRAM or equivalent capacity;
- available backends;
- runtime compatibility;
- installed model variants;
- user profile;
- power/thermal state where relevant.

### 11.4 Initial Windows expectations

The Phase 6 benchmark compares at least:

1. Evaluator and Actor both resident;
2. two managed runtime processes;
3. one runtime with sequential loading;
4. one shared model for both roles;
5. deterministic Evaluator plus local Actor.

No strategy is declared universally optimal before measurement.

---

## 12. Artifact and Version Boundaries

The following are independent artifacts:

```text
A.U.R.A. application
llama.cpp runtime package
model artifacts
model manifest
LoRA adapters
audio pack
branding assets
configuration schema
saved sessions and replay logs
```

### 12.1 Versioning rules

- Application updates must not force model redownload.
- Runtime updates require compatibility validation.
- Model updates require hash verification and rollback support.
- LoRA adapters must identify the exact compatible base model.
- Audio pack updates must be independently identifiable.
- User replay/configuration data must survive normal application upgrades.
- Portable and installed layouts may differ but consume the same logical manifests.

### 12.2 Integrity

Every managed binary or model artifact must be verified against declared metadata before use.

Minimum integrity mechanism:

```text
pinned source/revision
expected filename
expected size
SHA-256
atomic finalization after verification
```

Partial downloads must never be treated as installed artifacts.

### 12.3 Trust boundary

Remote manifests must not be accepted blindly.

The release design must define:

- trusted manifest source;
- release channel;
- signature or authenticated transport policy;
- rollback prevention policy where appropriate;
- behavior when verification fails.

The exact signing approach is deferred to `RELEASE_PIPELINE_SPEC.md`.

---

## 13. Storage Boundary

Storage paths are resolved by platform adapters.

Conceptual categories:

```text
application binaries
runtime binaries
managed models
managed audio
configuration
logs
replays
temporary downloads
staging/rollback
user-imported artifacts
```

The core refers to typed storage locations, not raw platform paths.

Example:

```dart
enum StorageArea {
  runtime,
  models,
  managedAudio,
  configuration,
  logs,
  replays,
  temporary,
  staging,
  userImports,
}
```

### 13.1 Windows installed mode

The intended layout remains conceptually:

```text
%LOCALAPPDATA%\AURA\App\
%LOCALAPPDATA%\AURA\Runtime\
%LOCALAPPDATA%\AURA\Models\
%LOCALAPPDATA%\AURA\Config\
%LOCALAPPDATA%\AURA\Logs\
%APPDATA%\aura\audio\
```

Final paths and capitalization are specified later.

### 13.2 Portable mode

Portable mode must not be assumed to write all managed data to AppData.

The packaging specification must decide which categories remain beside the executable and which remain in the user profile. At minimum, portable mode must be detectable and its storage behavior explicit.

### 13.3 Android mode

Android uses app-compatible storage and import mechanisms. The model store contract must not require Windows-style path semantics.

---

## 14. Composition Root and Dependency Injection

All concrete services are selected at application startup.

Conceptual bootstrap:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final platformServices = await PlatformServices.bootstrap();
  final hardwareProfile =
      await platformServices.hardwareProbe.inspect();

  final runtime = await platformServices.runtimeFactory.create(
    hardwareProfile: hardwareProfile,
  );

  final executionPlan =
      await platformServices.modelExecutionPlanResolver.resolve(
    hardwareProfile: hardwareProfile,
    installedModels: await platformServices.modelStore.listInstalled(),
  );

  final inferenceBridge = RuntimeInferenceBridge(
    runtime: runtime,
    executionPlan: executionPlan,
  );

  final notifier = GameControllerNotifier(
    bridge: inferenceBridge,
    initialState: createInitialState(),
  );

  runApp(AuraApp(
    notifier: notifier,
    platformServices: platformServices,
  ));
}
```

This is illustrative, not the final API.

### 14.1 Required injection points

The application must be able to inject:

- runtime;
- model manager/store;
- downloader;
- hardware probe;
- storage resolver;
- window mode controller;
- audio asset resolver;
- preferences store;
- clock and process abstractions where required for tests.

### 14.2 Prohibited construction

The following must not occur inside gameplay agents or widgets:

```dart
Process.start(...);
File('C:\\...');
LocalApiInferenceBridge(baseUrl: ...);
HttpClient();
loadDynamicLibrary(...);
```

---

## 15. Legacy Compatibility

### 15.1 LM Studio

LM Studio support is retained temporarily through:

```text
ExternalOpenAiRuntime
```

Use cases:

- developer comparison;
- manual model experimentation;
- regression comparison during migration;
- emergency compatibility during Phase 6 implementation.

It is not:

- the production default;
- an installer prerequisite;
- a required test dependency;
- a supported end-user setup path after Phase 6 exit.

### 15.2 Existing bridge migration

`LocalApiInferenceBridge` should be refactored rather than immediately deleted.

Recommended migration:

```text
LocalApiInferenceBridge
    |
    +--> extract protocol-cleaning behavior
    +--> rename/generalize HTTP transport adapter
    +--> place behind RuntimeInferenceBridge
    +--> retain ExternalOpenAiRuntime configuration
```

Response cleanup, structured-output parsing, CJK filtering, duplicate detection, and other model-output safeguards must remain reusable regardless of transport.

---

## 16. Testing Decision

### 16.1 Standard suites

These commands must remain offline and deterministic:

```text
dart test
flutter test
```

They must not:

- download a runtime;
- download a model;
- load Ministral;
- start `llama-server`;
- require GPU access;
- depend on Hugging Face;
- read developer AppData content.

They use:

- `MockInferenceRuntime`;
- `RuleBasedInferenceRuntime`;
- fake process/runtime adapters;
- fixture manifests;
- temporary storage.

### 16.2 Contract tests

Every runtime implementation must pass a shared behavioral contract covering:

- initialization;
- model load/unload;
- generation;
- structured generation;
- invalid state;
- timeout;
- cancellation;
- failure mapping;
- runtime disposal;
- handle invalidation;
- recovery after crash where supported.

### 16.3 Native smoke tests

Native smoke tests are explicit and separate:

```text
tool/run_native_smoke_tests.ps1
```

They may use:

- a pinned small GGUF fixture;
- a preinstalled test artifact;
- a separately downloaded fixture after explicit consent.

### 16.4 Real-model integration tests

Real-model tests are opt-in:

```text
tool/run_real_model_tests.ps1 -RequireInstalled
```

Default policy:

```text
require installed artifact
never download implicitly
fail with a clear skip/precondition message if absent
```

The real runtime should start once per suite, not once per test.

### 16.5 CI policy

Pull-request CI runs no real-model inference.

Real-model validation belongs to:

- manual workflow dispatch;
- scheduled/nightly validation;
- dedicated or self-hosted Windows runner;
- release candidate validation.

The full policy is specified in `TEST_RUNTIME_STRATEGY.md`.

---

## 17. Observability and Diagnostics

The runtime layer must produce structured events without leaking transport details into gameplay.

Required event families:

```text
runtime.initializing
runtime.ready
runtime.failed
runtime.crashed
model.resolving
model.loading
model.ready
model.unloading
generation.started
generation.completed
generation.cancelled
generation.failed
artifact.verifying
artifact.corrupted
fallback.activated
```

Diagnostic metadata may include:

- runtime build ID;
- backend;
- logical model ID;
- model variant ID;
- load duration;
- generation latency;
- token counts where available;
- exit code;
- typed failure;
- recovery action.

Diagnostic logs must avoid:

- full prompt content by default;
- secrets;
- unrestricted personal paths;
- raw user input unless explicitly part of an exported replay;
- remote transmission without opt-in.

Replay semantics remain distinct from runtime diagnostic logs.

---

## 18. Dependent Phase 6 Specifications

This ADR is the parent decision for:

```text
docs/phase6/INFERENCE_RUNTIME_CONTRACT.md
docs/phase6/MODEL_MANIFEST_SPEC.md
docs/phase6/MODEL_LIFECYCLE_SPEC.md
docs/phase6/HARDWARE_PROFILE_SPEC.md
docs/phase6/TEST_RUNTIME_STRATEGY.md
docs/phase6/WINDOWS_DESKTOP_SHELL_SPEC.md
docs/phase6/BRANDING_ASSET_SPEC.md
docs/phase6/AUDIO_ASSET_PACKAGING_SPEC.md
docs/phase6/WINDOWS_INSTALLER_AND_UPDATE_SPEC.md
docs/phase6/ANDROID_READINESS_SPEC.md
docs/phase6/RELEASE_PIPELINE_SPEC.md
docs/phase6/HARDWARE_COMPATIBILITY_MATRIX.md
```

The documents should be produced incrementally. The minimum set required before implementation of Phase 6.1 and 6.2 is:

```text
CROSS_PLATFORM_RUNTIME_ADR.md
INFERENCE_RUNTIME_CONTRACT.md
MODEL_MANIFEST_SPEC.md
MODEL_LIFECYCLE_SPEC.md
HARDWARE_PROFILE_SPEC.md
TEST_RUNTIME_STRATEGY.md
```

---

## 19. Implementation Sequence Enabled by This ADR

### Step 1 — Introduce contracts without changing behavior

- add platform-neutral runtime and model interfaces;
- implement adapters over existing mocks and rule-based fallback;
- keep current LM Studio path functional;
- add contract tests.

### Step 2 — Move construction to the composition root

- remove direct `LocalApiInferenceBridge` construction from `main.dart`;
- introduce `PlatformServices`;
- inject runtime and model services;
- preserve current user-visible behavior.

### Step 3 — Generalize the existing HTTP bridge

- separate transport from output cleanup;
- implement `ExternalOpenAiRuntime`;
- keep LM Studio as a development option;
- prepare the same adapter for managed `llama-server`.

### Step 4 — Implement Windows managed runtime

- package a pinned llama.cpp build;
- implement process lifecycle;
- implement readiness and crash recovery;
- map failures;
- add native smoke tests.

### Step 5 — Implement model lifecycle

- logical IDs;
- manifests;
- artifact verification;
- download/import;
- execution plan;
- hardware profiles.

### Step 6 — Complete Windows product integration

- shell/window modes;
- definitive audio packaging;
- installer/update/repair;
- release pipeline;
- clean-machine validation.

### Step 7 — Validate Android readiness

- verify that no public contract assumes HTTP, sidecars, or Windows paths;
- verify shared contract tests can be reused by a native Android runtime;
- record remaining Phase 7 risks.

---

## 20. Alternatives Considered

### 20.1 Keep LM Studio as production prerequisite

**Rejected.**

Reasons:

- external manual dependency;
- poor installer experience;
- runtime and model lifecycle not owned by A.U.R.A.;
- unsuitable for Android;
- difficult repair and support;
- weak reproducibility.

### 20.2 Direct Windows FFI immediately

**Deferred.**

Advantages:

- no sidecar process;
- potentially tighter memory and lifecycle control;
- direct access to native features.

Reasons for deferral:

- higher implementation and maintenance cost;
- ABI/API churn risk;
- threading and memory ownership complexity;
- harder crash isolation;
- unnecessary before profiling proves a need.

### 20.3 Use HTTP/OpenAI compatibility as the universal core contract

**Rejected.**

Reasons:

- leaks transport into architecture;
- forces Android toward an unnatural local-server model;
- makes model lifecycle and handles ambiguous;
- limits native capability expression;
- couples agents to one protocol shape.

HTTP remains valid inside specific adapters.

### 20.4 Bundle all GGUF models inside the Windows installer

**Rejected as the default.**

Reasons:

- excessive installer size;
- slow updates;
- application updates would redistribute unchanged models;
- difficult hardware-specific variant selection;
- poor rollback granularity.

The installer may optionally bootstrap downloads or support offline bundles later.

### 20.5 Require two fixed models on every platform

**Rejected.**

Reasons:

- incompatible with many Android and low-memory devices;
- blocks shared-model and deterministic-Evaluator profiles;
- turns current model choices into architecture.

### 20.6 Make AICore the Android-only architecture

**Rejected.**

Reasons:

- capability and device availability may vary;
- model behavior may not satisfy the Evaluator contract;
- creates dependency on a system-managed model;
- weakens portability.

AICore remains an optional adapter.

### 20.7 Put models under the application installation directory

**Rejected.**

Reasons:

- upgrade coupling;
- permission issues;
- duplicated downloads;
- difficult persistence across repair/uninstall;
- incompatible with portable and Android storage models.

### 20.8 Let widgets manage runtime setup directly

**Rejected.**

Reasons:

- platform leakage;
- untestable lifecycle;
- duplicated logic;
- difficult Android reuse;
- UI becomes owner of critical resources.

---

## 21. Consequences

### 21.1 Positive consequences

- LM Studio can be removed from the end-user path.
- Windows can ship before direct native FFI is justified.
- Android can use an in-process runtime without core refactoring.
- Models become replaceable and versioned independently.
- Standard tests remain fast and deterministic.
- Installer, repair, and release behavior can be specified cleanly.
- Future LoRA adapters can reuse model and runtime contracts.
- Hardware-specific execution strategies become possible.
- Runtime failures can be handled through typed, user-readable states.
- Process and model ownership become observable and supportable.

### 21.2 Costs

- More interfaces and adapters must be maintained.
- A formal model manifest and compatibility policy are required.
- The application must implement runtime setup UX.
- The Windows sidecar needs robust process management.
- Shared contract tests become mandatory.
- Release automation must package and verify native artifacts.
- Migration must preserve current playability while replacing construction and routing.

### 21.3 Risks

- Over-abstraction before actual Android implementation.
- Contract design that is too close to HTTP despite neutral naming.
- Runtime API that is too narrow for native token streaming or LoRA.
- Process cleanup bugs.
- Runtime/model version drift.
- Incorrect hardware profiling.
- Duplicated logic between bridge and runtime layers.
- Accidental real-model execution in standard CI.

Mitigations:

- keep contracts minimal;
- validate each contract through mock, external HTTP, and managed sidecar adapters;
- review every public API against the future Android adapter;
- add lifecycle and crash tests early;
- use pinned manifests;
- fail closed on integrity mismatch;
- enforce test scripts and CI guards.

---

## 22. Deferred Decisions

The following are intentionally not fixed by this ADR:

1. exact llama.cpp build number;
2. exact Windows runtime asset matrix;
3. exact CUDA/Vulkan/CPU selection thresholds;
4. exact Ministral and Actor quantization files;
5. one sidecar versus two sidecars as production default;
6. final streaming API shape;
7. Kotlin/JNI versus Dart FFI for Android;
8. Inno Setup versus WiX/Burn;
9. Authenticode and manifest signing implementation;
10. installed versus portable audio/config placement details;
11. exact model download UI;
12. LoRA training, conversion, and hot-swap behavior;
13. exact hardware support tiers;
14. whether the physical executable is renamed during desktop-shell work or packaging.

Each deferred decision has a designated specification or benchmark phase.

---

## 23. Acceptance Criteria

This ADR is accepted when the maintainer confirms all of the following:

```text
- Windows production uses a managed llama-server sidecar for the first implementation.
- Android is prepared for an in-process runtime implementing the same Dart contract.
- HTTP is not the public core inference boundary.
- LM Studio is development-only compatibility.
- aura_core contains no platform-specific runtime implementation.
- model roles use logical IDs.
- application, runtime, models, LoRA, audio, and user data are separate artifacts.
- model residency is selected by an execution plan rather than hardcoded.
- standard tests never use real models or network downloads.
- runtime and model artifacts are pinned and integrity-checked.
- composition and platform selection occur in the application bootstrap layer.
- direct Windows FFI and LoRA are deferred without blocking future adapters.
```

---

## 24. Phase 6.0 Exit Criteria Related to This ADR

The ADR portion of the design gate is complete when:

- this file is committed under `docs/phase6/`;
- alternatives and consequences have been reviewed;
- no unresolved contradiction exists with TGDD v1.5;
- the next specifications can reference stable component boundaries;
- Antigravity can analyze the repository against this ADR without being asked to invent the architecture;
- no production implementation begins before the minimum dependent specification set in §18 is approved.

---

## 25. Recommended Review Request for Antigravity

After this document is committed, Antigravity should be asked to perform a repository-aware review without modifying code:

```text
Read docs/phase6/CROSS_PLATFORM_RUNTIME_ADR.md in full.

Analyze the current repository against the ADR. Do not modify files.

Produce a report containing:
1. current classes and files affected;
2. violations of the proposed boundaries;
3. migration risks;
4. potential dependency cycles;
5. test infrastructure that can be reused;
6. missing abstractions;
7. assumptions in the ADR that are incompatible with the current code;
8. a proposed implementation sequence for Phase 6.1 and 6.2;
9. explicit deviations you recommend, with technical justification.

Do not redesign the architecture silently. Treat the ADR as the proposed canonical decision and identify conflicts for review.
```

---

## 26. Final Decision

A.U.R.A. will migrate from an externally managed LM Studio development runtime to a product-owned, cross-platform runtime architecture.

Windows will initially execute GGUF models through a managed, pinned, loopback-only `llama-server` sidecar. Android will later execute through an in-process native adapter. Both implementations will satisfy the same platform-neutral Dart contracts and consume logical model IDs resolved through versioned manifests and hardware-aware execution plans.

This decision allows Phase 6 to deliver a distributable Windows product while preserving a clean path to Android and future LoRA specialization without complex gameplay or agent refactoring.
