# Test Runtime Strategy

**Project:** A.U.R.A. — Artificial Unbound Reasoning Arena  
**Target path:** `docs/phase6/TEST_RUNTIME_STRATEGY.md`  
**Status:** Proposed for approval  
**Phase:** 6.0 — Architecture and Distribution Design Gate  

**Parent documents:**
- `docs/phase6/CROSS_PLATFORM_RUNTIME_ADR.md`
- `docs/phase6/INFERENCE_RUNTIME_CONTRACT.md`
- `docs/phase6/MODEL_MANIFEST_SPEC.md`
- `docs/phase6/MODEL_LIFECYCLE_SPEC.md`
- `docs/phase6/HARDWARE_PROFILE_SPEC.md`

**Repository baseline:** `5d5f32533a520e5a224a53462a711f52410055ed`  
**Strategy version:** 1.0  
**Primary production target:** Windows x64  
**Secondary production target:** Android arm64, Phase 7  
**Last updated:** 2026-07-20

---

## 1. Purpose

This specification defines the test architecture for A.U.R.A. after the introduction of:

- platform-neutral inference-runtime contracts;
- managed Windows `llama-server`;
- native Android inference;
- model manifests;
- managed model lifecycle;
- hardware-aware execution plans;
- installer and release automation.

The strategy guarantees that the standard test suite remains:

- deterministic;
- fast;
- offline;
- independent from model downloads;
- independent from GPU availability;
- independent from the developer workstation;
- suitable for pull-request CI.

At the same time, the strategy defines explicit higher test levels for:

- native runtime integration;
- model loading;
- real-model behavior;
- hardware compatibility;
- release validation;
- clean-machine installation;
- Android instrumented execution.

---

## 2. Core Decision

The default commands:

```text
dart test
flutter test
```

must never:

- access Hugging Face;
- access GitHub Releases;
- start LM Studio;
- start `llama-server`;
- load Ministral, Qwen, Gemma, or another real production model;
- require CUDA, Vulkan, or a GPU;
- read `%APPDATA%\aura\audio\`;
- read the user's installed model store;
- depend on the host hardware profile;
- mutate the user's real settings, session, registry, or model directories.

The default policy is:

```dart
ModelAvailabilityPolicy.neverDownload
```

and the default runtime is:

```text
MockInferenceRuntime
or
RuleBasedInferenceRuntime
```

Real runtime and real model execution are opt-in, isolated, tagged, and executed through dedicated scripts or workflows.

---

## 3. Goals

The test strategy must provide:

1. deterministic gameplay validation;
2. shared runtime contract tests;
3. output-sanitizer and schema-validation coverage;
4. model-manifest parser and resolver coverage;
5. lifecycle crash-recovery coverage;
6. synthetic hardware-profile coverage;
7. native runtime smoke tests;
8. explicit real-model integration tests;
9. clean separation between functional correctness and model quality;
10. pull-request CI without large artifacts;
11. release-candidate validation on representative hardware;
12. Windows and Android parity at the contract level;
13. reproducible failure diagnostics;
14. bounded runtime and resource usage;
15. no accidental network or model usage in standard test commands.

---

## 4. Non-Goals

This document does not define:

- the final benchmark thresholds;
- the final supported hardware matrix;
- the final production models and quantizations;
- the release-signing implementation;
- the installer technology;
- exact Android device-lab providers;
- gameplay balance targets;
- final model-quality acceptance scores;
- LoRA training validation.

Those are defined in later Phase 6/7/8 specifications.

---

## 5. Test Pyramid

A.U.R.A. adopts the following test levels.

```text
Level 0 — Static validation
Level 1 — Pure unit tests
Level 2 — Contract tests
Level 3 — Component/integration tests with fakes
Level 4 — Native runtime smoke tests
Level 5 — Real-model integration tests
Level 6 — Hardware compatibility and performance tests
Level 7 — Packaging, installer and clean-machine tests
Level 8 — Android instrumented/device tests
Level 9 — Manual playtest and release acceptance
```

Each level has distinct:

- prerequisites;
- execution command;
- environment;
- artifact policy;
- timeout policy;
- CI eligibility;
- failure meaning.

---

## 6. Level 0 — Static Validation

### 6.1 Scope

Static validation includes:

```text
dart format
dart analyze
flutter analyze
JSON Schema validation
manifest validation
configuration-schema validation
asset-manifest validation
license/notice validation
dependency/license scanning
workflow syntax validation
PowerShell linting where available
```

### 6.2 Required checks

The static stage must reject:

- malformed model manifests;
- mutable production model revisions;
- missing SHA-256;
- duplicate logical IDs or variant IDs;
- invalid runtime compatibility ranges;
- invalid fixture schemas;
- missing managed audio assets;
- stale generated schema files where applicable;
- forbidden direct platform dependencies in `aura_core`;
- forbidden production defaults pointing to LM Studio.

### 6.3 CI

Level 0 runs on every pull request.

---

## 7. Level 1 — Pure Unit Tests

### 7.1 Characteristics

Pure unit tests:

- use no real filesystem unless a temporary directory is the subject under test;
- use no network;
- use no native runtime;
- use no real model;
- use deterministic clocks and IDs where required;
- finish quickly.

### 7.2 Primary subjects

```text
GameController
EvaluatorDelta application
safety override
hidden tags
deception transitions
victory/defeat
prompt construction
ActorCue construction
OutputValidator
ActorOutputSanitizer
ReasoningContentPolicy
CharacterSetGuard
DuplicateResponseGuard
manifest parsing
manifest validation
model resolution
lifecycle state transitions
hardware-profile normalization
execution-plan scoring
failure mapping
```

### 7.3 Existing test reuse

Existing deterministic tests remain authoritative for gameplay.

Tests currently embedded in `agent_runtime_test.dart` for:

- dialogue extraction;
- response cleanup;
- CJK rejection;
- duplicate-response handling;
- model routing;

should be redistributed into focused unit suites.

---

## 8. Level 2 — Shared Contract Tests

### 8.1 Purpose

Every implementation of a platform-neutral contract must pass the same behavioral suite.

Required contract families:

```text
InferenceRuntimeContract
ModelLifecycleContract
ModelStoreContract
InstalledModelRegistryContract
HardwareProbeContract
HardwareProfileRepositoryContract
ArtifactDownloaderContract
```

### 8.2 Runtime contract harness

Conceptual entry point:

```dart
void runInferenceRuntimeContractTests(
  String adapterName,
  Future<InferenceRuntime> Function() createRuntime,
  RuntimeContractTestProfile profile,
);
```

The harness must cover:

- initialization;
- invalid state;
- model load/unload;
- handle ownership;
- text generation;
- structured generation;
- cancellation;
- timeouts;
- concurrency;
- health;
- crash semantics;
- recovery;
- disposal;
- event ordering.

### 8.3 Lifecycle contract harness

Conceptual entry point:

```dart
void runModelLifecycleContractTests(
  String implementationName,
  Future<ModelLifecycleTestEnvironment> Function() createEnvironment,
);
```

The harness must cover:

- absent → install;
- staged artifacts not loadable;
- size/hash mismatch;
- atomic registry update;
- interruption recovery;
- activation;
- side-by-side update;
- rollback;
- repair;
- removal;
- garbage collection;
- external binding isolation.

### 8.4 Contract profiles

Adapters may declare supported optional capabilities.

The test harness must distinguish:

```text
mandatory behavior
optional supported behavior
explicitly unsupported behavior
```

Unsupported optional capability is not a failure if reported correctly.

---

## 9. Level 3 — Component Tests with Fakes

### 9.1 Purpose

Component tests validate multiple production components without real native inference.

Examples:

```text
RuntimeInferenceBridge + MockInferenceRuntime
ModelResolver + fixture manifest + fake registry
ModelLifecycleManager + fake downloader + temp store
HardwareProfileBuilder + synthetic snapshot
ModelExecutionPlanResolver + synthetic hardware + fake availability
bootstrap + fake PlatformServices
setup UI + fake lifecycle events
```

### 9.2 Required fakes

```text
MockInferenceRuntime
RuleBasedInferenceRuntime
FakeArtifactDownloader
FakeModelStore
InMemoryInstalledModelRegistry
FakeIntegrityVerifier
FakeModelInspector
FakeModelLifecycleJournal
FakeHardwareProbe
InMemoryHardwareProfileRepository
FakeRuntimeFactory
FakeClock
DeterministicIdGenerator
```

### 9.3 File I/O

Where filesystem semantics are the subject:

- use temporary directories;
- use tiny deterministic fixture files;
- clean up after execution;
- never use the user's real app-data directories.

---

## 10. Level 4 — Native Runtime Smoke Tests

### 10.1 Purpose

Validate that the packaged native runtime can:

- start;
- report health;
- load a tiny test model;
- execute one bounded generation;
- unload;
- stop cleanly.

### 10.2 Model fixture

The smoke test must use:

- a tiny, pinned GGUF artifact;
- immutable revision;
- known size;
- known SHA-256;
- license suitable for CI/testing;
- no implicit download.

The fixture is not a production-quality model.

### 10.3 Availability

Supported modes:

```text
fixture already installed
fixture bundled in a dedicated test artifact
fixture downloaded by an explicit setup command
```

The smoke test command itself must default to:

```text
requireInstalled
```

### 10.4 Windows script

Recommended:

```text
tool/run_native_smoke_tests.ps1
```

Suggested options:

```text
-RuntimePackage <id>
-Backend cpu|cuda|vulkan
-FixturePath <path>
-RequireInstalled
-KeepLogs
```

### 10.5 Required assertions

```text
runtime process starts
loopback binding only
runtime identity matches expected build
health becomes ready within timeout
fixture loads
generation returns non-empty bounded output
cancellation works or is reported unsupported
model unload succeeds
runtime exits
no orphan process remains
```

### 10.6 CI eligibility

Native smoke tests may run:

- manually;
- on scheduled workflows;
- on release branches;
- on selected hosted Windows runners for CPU;
- on self-hosted runners for GPU backends.

They do not run in default PR CI.

---

## 11. Level 5 — Real-Model Integration Tests

### 11.1 Purpose

Validate behavior with actual candidate production models.

This level tests:

- prompt compatibility;
- structured Evaluator output;
- Actor output sanitation;
- Italian-language behavior;
- cancellation;
- latency;
- memory use;
- runtime stability.

### 11.2 Explicit command

Recommended:

```text
tool/run_real_model_tests.ps1
```

Required default behavior:

```text
never download implicitly
require installed verified artifacts
skip/fail precondition clearly when absent
start runtime once per suite
```

Suggested options:

```text
-Profile evaluator
-Profile actor
-Profile shared
-Backend cpu|cuda|vulkan
-ManifestPath <path>
-RequireInstalled
-RecordMetrics
-ExportReport <path>
```

### 11.3 Test categories

#### Evaluator

```text
valid JSON/schema
unknown-field rejection
delta bounds
safety override compatibility
hidden-tag signaling
logical-trap scenarios
Italian instruction following
repeatability with fixed seed where supported
```

#### Actor

```text
Italian output
diegetic response
dialogue extraction
no reasoning leakage
no CJK leakage
no prompt-example echo
no excessive duplication
bounded output length
PANOPTICON identity consistency
```

#### Shared model

```text
role separation
Evaluator structured reliability
Actor narrative quality
prompt contamination between roles
sequential role switching
```

### 11.4 Failure meaning

A failed real-model test may indicate:

- model incompatibility;
- prompt regression;
- runtime regression;
- sanitizer regression;
- hardware-specific instability;
- nondeterministic quality degradation.

It is not treated identically to a unit-test failure and must produce a structured report.

---

## 12. Level 6 — Hardware Compatibility and Performance

### 12.1 Purpose

Validate the execution-plan policies defined by `HARDWARE_PROFILE_SPEC.md`.

### 12.2 Synthetic versus real hardware

Synthetic profile tests belong to Levels 1–3.

Actual hardware measurements belong to Level 6.

### 12.3 Required measurements

```text
runtime startup time
model load time
peak host RAM
peak device memory
Evaluator latency
Actor first-token latency
Actor total latency
model-switch latency
runtime recovery time
CPU utilization
GPU utilization where available
thermal/power observations where available
```

### 12.4 Required Windows scenarios

```text
CPU-only
Vulkan
CUDA
one shared model
two models sequential
two models simultaneous if supported
two runtime processes
deterministic Evaluator + Actor model
```

### 12.5 Reference machine

The development machine:

```text
Windows x64
64 GiB RAM
12 GiB dedicated VRAM
```

is one reference profile, not the compatibility matrix.

### 12.6 Output

Every run produces a machine-readable result:

```json
{
  "hardware_fingerprint": {},
  "runtime_package_id": "",
  "runtime_build_id": "",
  "backend": "",
  "model_content_ids": [],
  "execution_plan": {},
  "measurements": {},
  "result": "pass"
}
```

These results feed `HARDWARE_COMPATIBILITY_MATRIX.md`.

---

## 13. Level 7 — Packaging and Clean-Machine Tests

### 13.1 Scope

Validate:

- installer;
- portable ZIP;
- runtime packaging;
- manifest inclusion;
- asset inclusion;
- first-run setup;
- model download/import;
- repair;
- update;
- rollback;
- uninstall;
- data retention.

### 13.2 Clean-machine requirement

Release validation must run on a machine or VM without:

- source checkout;
- Flutter SDK;
- Dart SDK;
- LM Studio;
- preexisting A.U.R.A. runtime;
- preexisting model store;
- developer AppData audio;
- development environment variables.

### 13.3 Required scenarios

```text
fresh install
first launch
CPU fallback
model setup
offline model import
runtime repair
app upgrade without model redownload
model update with rollback
uninstall keeping models
uninstall removing managed data
portable launch
portable upgrade
```

---

## 14. Level 8 — Android Instrumented and Device Tests

### 14.1 Phase 7 scope

Android must reuse shared contract tests where possible.

Device/instrumented tests validate:

```text
native library loading
model import through ContentResolver
copy to app-private storage
model load
generation off UI thread
cancellation
process/activity recreation
low-memory handling
thermal-state response
app-private cleanup
optional AICore adapter
```

### 14.2 Emulator limits

Emulators are suitable for:

- lifecycle;
- storage;
- UI;
- contract wiring.

They are not authoritative for:

- native model performance;
- device memory behavior;
- thermal behavior;
- AICore.

Physical-device testing is required before Android release.

---

## 15. Level 9 — Manual Playtest and Release Acceptance

### 15.1 Purpose

Automated tests cannot fully evaluate:

- dramatic coherence;
- deception quality;
- narrative pacing;
- PANOPTICON identity;
- perceived latency;
- player comprehension;
- audio/visual polish.

### 15.2 Required playtest evidence

A release candidate should retain:

```text
application version
runtime build
model manifest version
model content IDs
hardware profile
execution plan
session replay
runtime diagnostics
tester observations
```

### 15.3 Separation

Manual playtest does not replace:

- deterministic gameplay tests;
- runtime contract tests;
- integrity validation;
- clean-machine validation.

---

## 16. Test Tags and Naming

Recommended tags:

```text
unit
contract
component
filesystem
native-smoke
real-model
hardware
packaging
android-instrumented
manual
network
slow
```

### 16.1 Standard suite inclusion

Included by default:

```text
unit
contract
component
filesystem
```

Excluded by default:

```text
native-smoke
real-model
hardware
packaging
android-instrumented
manual
network
slow
```

### 16.2 Naming convention

```text
*_test.dart
*_contract_test.dart
*_component_test.dart
*_native_smoke_test.dart
*_real_model_test.dart
```

---

## 17. Repository Layout

Recommended structure:

```text
test/
  unit/
  contract/
  component/
  fixtures/
    manifests/
    lifecycle/
    hardware/
    outputs/

app/test/
  unit/
  widget/
  component/

integration_test/
  windows/
  android/

tool/
  run_native_smoke_tests.ps1
  run_real_model_tests.ps1
  run_hardware_benchmarks.ps1
  verify_no_network_tests.ps1
  prepare_test_model.ps1
```

The exact migration can be incremental.

---

## 18. No-Network Enforcement

### 18.1 Requirement

Standard tests must fail if unexpected network access is attempted.

### 18.2 Enforcement options

```text
inject network clients
use fake source adapters
deny real HttpClient in test bootstrap
run CI job with outbound access restricted where practical
scan tests for direct external endpoints
```

### 18.3 Explicit exceptions

Only tagged integration workflows may use network.

A test that silently skips because LM Studio is unavailable is not acceptable in the standard suite.

The current live LM Studio test must move out of `dart test`.

---

## 19. No-Real-Model Enforcement

### 19.1 Requirement

Standard tests must not resolve or load production model artifacts.

### 19.2 Guards

- `ModelAvailabilityPolicy.neverDownload`;
- fake installed registry;
- fixture manifest without production variants;
- runtime factory returning mock/deterministic runtime;
- environment guard rejecting production model-store paths;
- CI assertion that no multi-gigabyte artifact is opened.

### 19.3 Real-model opt-in

Real-model tests require an explicit script and profile.

Environment variables alone should not accidentally enable them in ordinary test commands.

---

## 20. Fixture Strategy

### 20.1 Fixture principles

Fixtures must be:

- small;
- deterministic;
- versioned;
- license-safe;
- independent from external services;
- easy to regenerate.

### 20.2 Required fixture groups

#### Manifest fixtures

```text
valid
minimal
invalid checksum
fallback cycle
Windows variants
Android variants
shared model
external binding
revoked model
```

#### Lifecycle fixtures

```text
known tiny binary
known SHA-256
partial metadata
registry valid
registry corrupted
journal interrupted states
quarantine object
```

#### Hardware fixtures

Use the synthetic profiles listed in `HARDWARE_PROFILE_SPEC.md`.

#### Output fixtures

```text
valid Evaluator JSON
malformed JSON
unknown fields
reasoning leakage
valid dialogue tag
truncated dialogue tag
CJK contamination
duplicate output
prompt-example echo
```

---

## 21. Deterministic IDs and Clocks

Tests must inject:

```text
Clock
ID generator
random seed
temporary base path
runtime event scheduler where needed
```

This prevents nondeterministic snapshots, registry revisions, and event ordering.

---

## 22. Timeout Strategy

### 22.1 Test-level timeouts

Different levels use different limits.

```text
unit: short
contract: short to moderate
component: moderate
native smoke: bounded startup/load/generation
real model: profile-specific
hardware benchmark: explicit long-running
packaging: scenario-specific
```

### 22.2 No arbitrary sleeps

Tests should await explicit events, states, or completers.

Fixed sleeps are allowed only where timing itself is under test and must include generous diagnostics.

### 22.3 Cancellation tests

Cancellation tests must verify:

- request ID correlation;
- cancellation event;
- generation future outcome;
- model remains usable or runtime recovery is explicit;
- no orphan operation remains.

---

## 23. Flakiness Policy

### 23.1 Standard suite

Flaky tests are defects.

No automatic retry is permitted to hide failures in unit, contract, or component tests.

### 23.2 Native and hardware tests

A bounded diagnostic retry may be used only when:

- the first failure is classified as environmental;
- both attempts are recorded;
- the release decision sees the instability.

### 23.3 Quarantine

A test may be quarantined temporarily only with:

```text
issue reference
owner
reason
expiration date
replacement coverage
```

---

## 24. Golden and Snapshot Tests

Golden tests may be used for:

- schema rendering;
- setup UI states;
- diagnostics panels;
- deterministic prompt construction;
- manifest reports.

They must not assert exact raw LLM prose.

Real-model output is evaluated through invariants and scoring criteria, not full-string golden comparison.

---

## 25. Property-Based and Fuzz Testing

Recommended targets:

```text
Evaluator JSON parser
manifest parser
manifest cross-field validation
registry parser
journal recovery
ActorOutputSanitizer
CJK/Unicode guards
path validation
lifecycle state transitions
execution-plan resolver
```

Fuzz tests must be bounded and deterministic in CI through fixed seeds.

---

## 26. Security Tests

Required security cases:

```text
path traversal
absolute paths
drive-letter injection
NUL characters
malicious manifest sizes
unknown source type
untrusted redirect
registry tampering
symlink/reparse-point substitution
TOCTOU simulation
malformed GGUF header
oversized diagnostic fields
shell metacharacters in metadata
```

Native helper invocation must be tested without shell interpolation.

---

## 27. Crash-Recovery Matrix

Lifecycle tests must simulate interruption after:

```text
partial download write
partial metadata write
download completion before verification
verification before final move
final move before registry write
registry write before activation
activation before rollback marking
garbage collection before registry reconciliation
```

For each interruption, assert:

- no partial artifact is loadable;
- active previous model remains valid where applicable;
- journal recovery is deterministic;
- orphan content is recoverable or collectable;
- registry remains parseable or recoverable from backup.

---

## 28. Bootstrap Tests

Bootstrap component tests must verify:

```text
settings loaded
cached hardware profile loaded
dynamic hardware refreshed
manifests validated
installed registry read
execution plan resolved
runtime initialized
capabilities reconciled
bridge constructed
notifier constructed last
```

Failure paths:

```text
manifest invalid
no supported runtime
model missing
runtime startup failure
hardware unknown
registry corrupt
fallback plan selected
```

`GameControllerNotifier` must not perform model discovery or hardware probing.

---

## 29. External LM Studio Compatibility Tests

External runtime compatibility remains development-only.

Tests must verify:

```text
accepted server model ID binds to logical role
unmatched model remains unavailable
no managed registry write
no model download
transient ModelHandle created
handle invalid after external session loss
production profile rejects implicit external binding
```

The external endpoint is faked in standard tests.

A real LM Studio comparison belongs to an explicit manual/integration script.

---

## 30. Model Quality Test Corpus

### 30.1 Evaluator corpus

The corpus should cover:

```text
direct compliance
indirect compliance
contradiction
identity pressure
safety conflict
logical trap seeding
logical trap resolution
deception escalation
reset conditions
ambiguous input
adversarial prompt injection
Italian slang and malformed input
```

Expected results are ranges/invariants, not exact model prose.

### 30.2 Actor corpus

The corpus should cover:

```text
low alert
high alert
high control
high dissonance
high resonance
deception states
logical-trap awareness
safety override aftermath
victory/defeat proximity
repeated user messages
adversarial instructions
```

### 30.3 Versioning

Corpus entries must have stable IDs and schema versions.

Changes require review because they alter model acceptance criteria.

---

## 31. Quality Metrics

Candidate model evaluation may use:

```text
Evaluator schema success rate
Evaluator local-validation pass rate
Evaluator retry rate
Actor sanitizer pass rate
reasoning-leak rate
CJK contamination rate
duplicate-response rate
Italian-language pass rate
median latency
p95 latency
runtime crash rate
```

Thresholds are deferred until benchmark data exists.

A quality metric cannot override deterministic controller rules.

---

## 32. CI Workflow Strategy

### 32.1 Pull request workflow

Runs:

```text
format/analyze
static schema validation
unit tests
contract tests with mocks/fakes
component tests
widget tests
filesystem tests using temporary directories
no-network guard
```

Does not run:

```text
real models
GPU tests
large downloads
installer clean-machine scenarios
Android physical-device inference
```

### 32.2 Main/default branch workflow

May additionally run:

```text
CPU native smoke test
portable packaging smoke
manifest artifact verification
```

only when artifacts are already available and runtime remains bounded.

### 32.3 Scheduled workflow

May run:

```text
real-model integration
hardware benchmarks
GPU backends
long-running lifecycle tests
dependency/license refresh checks
```

### 32.4 Release workflow

Runs:

```text
all PR checks
native runtime smoke
real-model acceptance
package verification
installer tests
portable tests
clean-machine tests
checksums/signatures
SBOM/notices validation
```

---

## 33. Self-Hosted Runner Policy

GPU and large-model validation generally require self-hosted runners.

Requirements:

- runner identity documented;
- hardware fingerprint recorded;
- clean workspace;
- model cache managed explicitly;
- no developer personal model directories;
- runtime and model versions pinned;
- disk cleanup policy;
- secrets isolated;
- result artifacts retained.

A self-hosted runner must not be treated as a generic trusted workstation without controls.

---

## 34. Test Artifact Policy

### 34.1 Small fixtures

May live in the repository when license and size permit.

### 34.2 Native runtime packages

Prefer workflow artifacts or release assets.

### 34.3 Large models

Must not be committed to Git.

They may reside in:

```text
managed runner cache
Hugging Face pinned artifact
release test asset
offline validation store
```

Downloads occur only in explicit preparation jobs.

### 34.4 Checksums

Every test artifact has:

```text
source
revision
filename
size
SHA-256
license
```

---

## 35. Logging and Reports

### 35.1 Standard tests

On failure include:

```text
test name
seed
fixture IDs
state transitions
typed failure
relevant events
temporary artifact path if retained
```

### 35.2 Native/real-model tests

Include:

```text
application commit
runtime build
manifest version
model content IDs
hardware fingerprint
backend
execution plan
latencies
memory observations
logs
```

### 35.3 Prompt privacy

Real-model reports should avoid storing unrestricted user prompts.

Use curated test corpus IDs.

---

## 36. Failure Classification

Recommended classes:

```text
product defect
test defect
environment failure
artifact precondition failure
hardware incompatibility
model-quality regression
runtime regression
packaging regression
infrastructure failure
```

CI and release reports must distinguish these classes.

---

## 37. Test Data Retention

- unit/contract logs: short retention;
- release reports: long retention;
- hardware benchmark history: retained for compatibility matrix;
- failed native logs: retained sufficiently for diagnosis;
- model artifacts: cached according to storage policy;
- user-derived playtest data: explicit and privacy-conscious.

---

## 38. Coverage Policy

Coverage is used as a diagnostic, not a substitute for behavioral adequacy.

High-priority coverage targets:

```text
GameController rules
safety override
OutputValidator
sanitizers/guards
manifest validation
lifecycle transitions
registry recovery
plan resolution
failure mapping
```

Native and real-model code require scenario coverage and smoke evidence in addition to line coverage.

---

## 39. Migration from Current Repository

### Stage 1 — Classify existing tests

Label:

```text
pure deterministic
filesystem
live LM Studio
widget
integration
```

### Stage 2 — Remove live network from standard suite

Move the current LM Studio integration test out of `agent_runtime_test.dart`.

### Stage 3 — Introduce shared runtime contract tests

Run first against:

```text
MockInferenceRuntime
RuleBasedInferenceRuntime
ExternalOpenAiRuntime with fake HTTP server
```

### Stage 4 — Extract output-policy tests

Move response-cleaning tests into focused sanitizer/guard suites.

### Stage 5 — Add manifest/lifecycle/hardware fixtures

Use fake stores, fake downloader, and synthetic hardware.

### Stage 6 — Add managed `llama-server` smoke tests

Keep them opt-in.

### Stage 7 — Add real-model suites and hardware reports

Use preinstalled verified artifacts.

### Stage 8 — Add packaging and clean-machine workflows

Required before Phase 6 exit.

---

## 40. Mandatory Standard Commands

The repository must document and keep stable:

```text
dart test
flutter test
dart analyze
flutter analyze
```

Recommended aggregate script:

```text
tool/run_ci_tests.ps1
```

It must run only standard offline levels.

---

## 41. Explicit Integration Commands

Recommended:

```text
tool/run_native_smoke_tests.ps1
tool/run_real_model_tests.ps1
tool/run_hardware_benchmarks.ps1
tool/run_packaging_tests.ps1
```

Each script must:

- print prerequisites;
- print selected manifest/runtime/model IDs;
- refuse implicit download unless a separate preparation flag is provided;
- return a meaningful exit code;
- export a structured report.

---

## 42. Release Gates

A Windows release candidate cannot be promoted unless:

```text
standard CI green
runtime contract tests green
native CPU smoke green
selected GPU-backend smoke green where claimed supported
real Evaluator acceptance green
real Actor acceptance green
installer/portable validation green
clean-machine first-run green
upgrade/repair/uninstall scenarios green
manifest/runtime/model checksums verified
no orphan runtime process
```

Claims in the compatibility matrix require corresponding evidence.

---

## 43. Android Gates

An Android release cannot be promoted unless:

```text
shared contract tests green
instrumented native runtime smoke green
storage import/copy green
process recreation green
cancellation green
low-memory handling green
physical-device model acceptance green
thermal behavior assessed
ABI packaging verified
```

---

## 44. Acceptance Criteria

This strategy is approved when all statements are accepted:

```text
- dart test and flutter test are offline and deterministic.
- Standard tests never load or download real models.
- Standard tests never start LM Studio or llama-server.
- All runtime adapters pass shared contract tests.
- Model lifecycle uses fake sources and tiny fixtures in standard CI.
- Hardware resolution uses synthetic profiles in standard CI.
- Native runtime smoke tests are explicit and separate.
- Real-model tests require verified preinstalled artifacts by default.
- GPU and large-model validation run only in dedicated workflows.
- Packaging and clean-machine tests are release gates.
- Android reuses platform-neutral contract tests and adds device tests.
- The live LM Studio test is removed from the standard suite.
- Test failures distinguish product, environment, model, hardware and infrastructure causes.
- Release claims are backed by retained structured evidence.
```

---

## 45. Exit Criteria for This Document

The document is complete when:

- committed under `docs/phase6/TEST_RUNTIME_STRATEGY.md`;
- reviewed against runtime, manifest, lifecycle and hardware specifications;
- standard and opt-in test boundaries are unambiguous;
- no implicit network or real-model path remains in the standard strategy;
- required fake components and fixtures are identified;
- native, real-model, hardware and packaging workflows have explicit ownership;
- GitHub Actions and release specifications can consume the defined test levels;
- Antigravity can migrate the current tests without silently weakening coverage.

---

## 46. Recommended Antigravity Review Prompt

After committing this document:

```text
Read in full, in this order:

1. docs/phase6/CROSS_PLATFORM_RUNTIME_ADR.md
2. docs/phase6/INFERENCE_RUNTIME_CONTRACT.md
3. docs/phase6/MODEL_MANIFEST_SPEC.md
4. docs/phase6/MODEL_LIFECYCLE_SPEC.md
5. docs/phase6/HARDWARE_PROFILE_SPEC.md
6. docs/phase6/TEST_RUNTIME_STRATEGY.md
7. previous Phase 6 repository-aware review reports
8. ARCHITECTURE.md
9. AGENTS.md, if present

Perform a repository-aware, read-only review of TEST_RUNTIME_STRATEGY.md.

Do not modify code or documentation.
Do not move tests yet.
Do not start LM Studio or llama-server.
Do not download or load models.
Do not run heavyweight benchmarks.

Produce a structured report containing:

1. Current test inventory
   - root Dart tests;
   - Flutter app tests;
   - widget tests;
   - filesystem tests;
   - integration tests;
   - live HTTP/LM Studio tests;
   - test helpers and mocks.

2. Default-suite compliance
   Verify whether current:
   - dart test;
   - flutter test;
   can perform network access, inspect real hardware, read user AppData,
   start external processes or load real models.

3. Reusable test mapping
   Map current tests to:
   - unit;
   - contract;
   - component;
   - filesystem;
   - native smoke;
   - real-model;
   - packaging;
   - manual playtest.

4. Contract-test feasibility
   Evaluate the proposed shared contract harnesses for:
   - InferenceRuntime;
   - ModelLifecycleManager;
   - ModelStore;
   - InstalledModelRegistry;
   - HardwareProbe;
   - HardwareProfileRepository;
   - ArtifactDownloader.

5. Required fakes and fixtures
   Identify:
   - reusable existing mocks;
   - missing fake components;
   - manifest fixtures;
   - lifecycle fixtures;
   - hardware profiles;
   - output-policy fixtures;
   - deterministic clocks/IDs.

6. Live LM Studio test
   Analyze the current live HTTP test and recommend:
   - exact destination;
   - tag/script;
   - prerequisite behavior;
   - skip versus fail semantics;
   - fake replacement for standard CI.

7. No-network and no-real-model enforcement
   Evaluate practical enforcement in this repository:
   - dependency injection;
   - fake clients;
   - CI guards;
   - forbidden paths/endpoints;
   - environment protections.

8. Native smoke feasibility
   Evaluate:
   - tiny GGUF fixture strategy;
   - runtime startup per suite;
   - CPU hosted runner possibility;
   - GPU self-hosted requirements;
   - orphan-process detection;
   - structured report output.

9. Real-model test feasibility
   Evaluate:
   - preinstalled model policy;
   - manifest/registry prerequisites;
   - Evaluator corpus;
   - Actor corpus;
   - invariant-based assertions;
   - nondeterminism handling;
   - latency/memory reporting.

10. CI and release integration
    Recommend concrete workflow separation for:
    - pull requests;
    - default branch;
    - nightly/manual;
    - release candidate;
    - self-hosted GPU validation;
    - clean-machine packaging validation.

11. Android readiness
    Verify which shared tests can be reused and which require:
    - instrumented tests;
    - emulator;
    - physical device.

12. Findings
    For each finding use:

    ID:
    Severity: BLOCKER | HIGH | MEDIUM | LOW
    Document section:
    Repository files/symbols:
    Problem:
    Evidence:
    Impact:
    Recommendation:
    Decision required before proceeding: yes/no

13. Proposed document changes
    For each proposed change specify:
    - exact section;
    - rationale;
    - CI impact;
    - Windows impact;
    - Android impact;
    - implementation impact.

Conclude with one judgment:

A. DOCUMENT APPROVABLE WITHOUT CHANGES
B. APPROVABLE WITH NON-BLOCKING CHANGES
C. REQUIRES CHANGES BEFORE PHASE 6.1 IMPLEMENTATION
D. TEST STRATEGY INCOMPATIBLE WITH CURRENT REPOSITORY
```

---

## 47. Final Decision

A.U.R.A. will keep functional correctness, runtime integration, model behavior, hardware compatibility, packaging validation and manual playtesting as separate, explicit test layers.

The standard developer and pull-request suites will remain fully offline, deterministic and independent from native runtimes and real model artifacts.

Native runtime, real-model, GPU, hardware, installer and Android tests will run only through dedicated scripts or workflows with pinned prerequisites, bounded execution and structured evidence.
