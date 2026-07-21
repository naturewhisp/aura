# Hardware Profile Specification

**Project:** A.U.R.A. — Artificial Unbound Reasoning Arena  
**Target path:** `docs/phase6/HARDWARE_PROFILE_SPEC.md`  
**Status:** Proposed for approval  
**Phase:** 6.0 — Architecture and Distribution Design Gate  
**Parent documents:**
- `docs/phase6/CROSS_PLATFORM_RUNTIME_ADR.md`
- `docs/phase6/INFERENCE_RUNTIME_CONTRACT.md`
- `docs/phase6/MODEL_MANIFEST_SPEC.md`
- `docs/phase6/MODEL_LIFECYCLE_SPEC.md`

**Repository baseline:** `5d5f32533a520e5a224a53462a711f52410055ed`  
**Hardware profile specification version:** 1.0  
**Primary production target:** Windows x64  
**Secondary production target:** Android arm64, Phase 7  
**Reference development machine:** Windows, 64 GiB system RAM, 12 GiB dedicated VRAM  
**Last updated:** 2026-07-20

---

## 1. Purpose

This specification defines how A.U.R.A. detects, represents, classifies, validates, and consumes device capabilities when selecting:

- inference runtime backend;
- runtime package;
- physical model variants;
- model residency policy;
- context size;
- GPU offload;
- CPU thread allocation;
- batch size;
- fallback strategy;
- update eligibility;
- runtime safety margins.

The hardware profile must support Windows desktop systems first and Android arm64 devices later without exposing platform-specific details to gameplay or agents.

The specification deliberately avoids treating a single RAM or VRAM threshold as sufficient. Model execution decisions must combine:

```text
detected hardware
runtime capabilities
model manifest requirements
installed-model availability
measured runtime behavior
application safety policy
user preference
```

---

## 2. Architectural Role

The hardware profile participates in the following resolution flow:

```text
HardwareProbe
      |
      v
RawHardwareSnapshot
      |
      v
HardwareProfileBuilder
      |
      +-- normalize capabilities
      +-- apply reliability/confidence
      +-- reserve safety margins
      +-- classify backend availability
      +-- derive resource budgets
      |
      v
HardwareProfile
      |
      +-----------------------------+
      |                             |
      v                             v
ModelResolver              RuntimeFactory
      |                             |
      v                             v
compatible variants        compatible runtime package
      |                             |
      +-------------+---------------+
                    |
                    v
       ModelExecutionPlanResolver
                    |
                    v
          ModelExecutionPlan
```

The hardware profile does not:

- select gameplay outcomes;
- identify the user;
- download models;
- load models;
- own runtime processes;
- contain provider model IDs;
- replace actual runtime capability discovery;
- guarantee benchmark performance.

---

## 3. Goals

The specification must provide:

1. platform-neutral hardware representation;
2. explicit confidence and data-source information;
3. conservative memory budgeting;
4. deterministic plan resolution;
5. Windows CPU/CUDA/Vulkan selection;
6. Android memory and lifecycle readiness;
7. support for simultaneous, sequential, shared-model, and deterministic-Evaluator plans;
8. graceful degradation;
9. stable diagnostics;
10. reproducible tests using synthetic profiles;
11. runtime feedback and profile refinement;
12. no accidental model download or load during probing.

---

## 4. Non-Goals

This document does not define:

- final production model variants;
- exact llama.cpp command lines;
- definitive benchmark results;
- download/install lifecycle;
- runtime process lifecycle;
- Android JNI/FFI implementation;
- user-facing setup screens;
- thermal APIs for every vendor;
- GPU driver installation;
- hardware warranty/support policy;
- cloud inference.

Those topics are handled by adjacent specifications or implementation phases.

---

## 5. Design Principles

### 5.1 Capability-based, not product-name-based

A.U.R.A. must not select behavior solely from strings such as:

```text
GeForce RTX 4070
Intel Core i7
Snapdragon 8 Gen 3
```

Product names are diagnostic metadata.

Selection uses normalized capabilities:

```text
system memory budget
device memory budget
backend availability
architecture
supported instruction sets
runtime-package compatibility
thermal/power constraints
storage availability
```

### 5.2 Conservative by default

When hardware data is unavailable, contradictory, or low confidence, the resolver selects the safer plan.

Examples:

- unknown VRAM does not imply zero VRAM, but prevents aggressive GPU-only selection;
- shared GPU memory is not treated as equivalent to dedicated VRAM;
- advertised total RAM is not treated as fully allocatable;
- model file size is not treated as runtime memory usage;
- benchmark success on one driver does not imply universal backend support.

### 5.3 Runtime facts override probe assumptions

`HardwareProbe` predicts capability.

`InferenceRuntime.initialize()` reports actual capability.

Effective capability is:

```text
hardware profile prediction
∩ installed runtime package capability
∩ runtime initialization result
```

If runtime initialization contradicts the profile, the runtime result wins and the plan is recalculated.

### 5.4 No hidden fallback

Fallback from CUDA to Vulkan or CPU must be:

- allowed by policy;
- recorded in diagnostics;
- surfaced to setup/status UI;
- reflected in the final execution plan.

### 5.5 Probe without side effects

Hardware probing must not:

- download models;
- launch a long-lived inference server;
- allocate multi-gigabyte buffers;
- modify drivers;
- alter system power settings;
- require administrator rights.

Optional benchmark probes are separate and explicit.

---

## 6. Hardware Profile Types

A.U.R.A. distinguishes:

### 6.1 Raw hardware snapshot

Platform-specific observations before normalization.

### 6.2 Normalized hardware profile

Stable platform-neutral representation used by model/runtime resolution.

### 6.3 Runtime capability snapshot

Capabilities reported by an initialized runtime.

### 6.4 Effective execution capability

Intersection used to build a `ModelExecutionPlan`.

---

## 7. Core Interface

Conceptual platform-neutral interface:

```dart
abstract interface class HardwareProbe {
  Future<RawHardwareSnapshot> inspect(
    HardwareProbeRequest request,
  );
}
```

Profile builder:

```dart
abstract interface class HardwareProfileBuilder {
  HardwareProfile build(
    RawHardwareSnapshot snapshot,
    HardwareProfilePolicy policy,
  );
}
```

Optional refresh:

```dart
abstract interface class HardwareProfileRepository {
  Future<HardwareProfile?> readCached();
  Future<void> writeCached(HardwareProfile profile);
  Future<void> invalidate();
}
```

---

## 8. Probe Request

```dart
@immutable
class HardwareProbeRequest {
  final bool includeGraphicsAdapters;
  final bool includeRuntimePackageCompatibility;
  final bool includeThermalSignals;
  final bool includePowerSignals;
  final bool includeStorage;
  final bool allowLightweightBenchmark;
  final Duration timeout;
}
```

### 8.1 Default startup request

Recommended:

```text
includeGraphicsAdapters: true
includeRuntimePackageCompatibility: true
includeThermalSignals: platform-dependent
includePowerSignals: true
includeStorage: true
allowLightweightBenchmark: false
```

### 8.2 Timeout

Probe timeout must be short and bounded.

Failure to collect optional information must not block application startup.

---

## 9. Raw Hardware Snapshot

Conceptual type:

```dart
@immutable
class RawHardwareSnapshot {
  final HardwareSnapshotId snapshotId;
  final DateTime observedAt;
  final PlatformDescriptor platform;
  final CpuDescriptor cpu;
  final MemoryDescriptor memory;
  final List<GraphicsAdapterDescriptor> graphicsAdapters;
  final StorageDescriptor? storage;
  final PowerDescriptor? power;
  final ThermalDescriptor? thermal;
  final List<ProbeObservation> observations;
  final List<HardwareProbeWarning> warnings;
}
```

---

## 10. Platform Descriptor

```dart
@immutable
class PlatformDescriptor {
  final OperatingSystemFamily operatingSystem;
  final String operatingSystemVersion;
  final CpuArchitecture architecture;
  final String? deviceClass;
  final bool isVirtualized;
  final bool isRemoteSession;
}
```

Initial operating systems:

```text
windows
android
```

Initial architectures:

```text
x64
arm64
```

`isVirtualized` and `isRemoteSession` are advisory. They may affect GPU availability and diagnostics but must not disable inference without evidence.

---

## 11. CPU Descriptor

```dart
@immutable
class CpuDescriptor {
  final String? vendor;
  final String? modelName;
  final int logicalProcessorCount;
  final int? physicalCoreCount;
  final Set<CpuInstructionSet> instructionSets;
  final CpuPerformanceClass performanceClass;
  final ProbeConfidence confidence;
}
```

Possible instruction sets:

```text
sse4_2
avx
avx2
avx512
fma
neon
dotprod
i8mm
sve
```

The exact set may expand.

### 11.1 CPU performance class

```text
unknown
low
balanced
high
workstation
mobileEfficiency
mobilePerformance
```

This is a derived class, not a marketing tier.

### 11.2 Thread budget

The default inference thread budget must reserve capacity for:

- Flutter UI;
- audio;
- file I/O;
- operating system;
- runtime coordination.

Recommended initial policy:

```text
available logical processors
minus reserved application processors
bounded by model/runtime recommendation
```

The application must not automatically use every logical processor.

---

## 12. System Memory Descriptor

```dart
@immutable
class MemoryDescriptor {
  final int totalPhysicalBytes;
  final int availablePhysicalBytes;
  final int? commitLimitBytes;
  final int? availableCommitBytes;
  final int reservedForSystemBytes;
  final int safeApplicationBudgetBytes;
  final ProbeConfidence confidence;
}
```

### 12.1 Total versus available memory

Both values are required when available.

Plan selection should use the lower safe budget derived from current availability and configured reservations.

### 12.2 Safety reserve

A.U.R.A. must reserve memory for:

- operating system;
- Flutter/UI;
- audio;
- file cache;
- runtime overhead;
- context/KV cache;
- temporary generation buffers;
- recovery margin.

A fixed percentage alone is insufficient across all devices.

Recommended conceptual formula:

```text
safe application budget =
min(
  available physical memory - fixed reserve,
  total physical memory × maximum application share
)
```

Values are finalized through benchmark data.

### 12.3 Swap/pagefile

Pagefile or swap availability may reduce immediate allocation failure but must not be treated as equivalent to physical RAM for acceptable inference performance.

---

## 13. Graphics Adapter Descriptor

```dart
@immutable
class GraphicsAdapterDescriptor {
  final GraphicsAdapterId id;
  final String? vendor;
  final String? name;
  final GraphicsAdapterType type;
  final int? dedicatedMemoryBytes;
  final int? sharedMemoryBytes;
  final Set<GraphicsBackend> supportedBackends;
  final DriverDescriptor? driver;
  final bool isPrimary;
  final bool isSoftwareAdapter;
  final ProbeConfidence confidence;
}
```

Adapter types:

```text
discrete
integrated
virtual
software
unknown
```

Backends:

```text
cuda
vulkan
cpu
systemManaged
```

### 13.1 Dedicated versus shared memory

Dedicated VRAM and shared system memory are represented separately.

Shared memory must not be added directly to dedicated memory to claim a larger GPU budget.

### 13.2 Multiple GPUs

The first Phase 6 implementation may select one graphics adapter per runtime instance.

Multi-GPU tensor distribution is deferred.

The profile must still represent multiple adapters so future support does not require schema replacement.

### 13.3 Software adapters

Software renderers must never be selected as inference accelerators.

---

## 14. Driver Descriptor

```dart
@immutable
class DriverDescriptor {
  final String? version;
  final String? provider;
  final DateTime? date;
  final Set<String> reportedCapabilities;
  final ProbeConfidence confidence;
}
```

Driver version is diagnostic and may participate in deny/allow rules when a verified incompatibility exists.

Broad assumptions such as “newer is always better” are prohibited.

---

## 15. Storage Descriptor

```dart
@immutable
class StorageDescriptor {
  final int availableModelStoreBytes;
  final int availableStagingBytes;
  final bool stagingAndFinalOnSameVolume;
  final bool supportsAtomicRename;
  final bool isRemovable;
  final bool isNetworkBacked;
  final ProbeConfidence confidence;
}
```

The lifecycle performs authoritative storage preflight.

The hardware profile uses storage only to reject clearly impossible plans or warn the user.

---

## 16. Power Descriptor

```dart
@immutable
class PowerDescriptor {
  final PowerSource powerSource;
  final int? batteryPercent;
  final bool batterySaverEnabled;
  final bool lowPowerModeEnabled;
  final ProbeConfidence confidence;
}
```

Power sources:

```text
ac
battery
unknown
```

Power state may alter:

- optional background download;
- benchmark execution;
- preferred backend;
- context size;
- concurrency;
- automatic model update.

It must not alter deterministic gameplay rules.

---

## 17. Thermal Descriptor

```dart
@immutable
class ThermalDescriptor {
  final ThermalState state;
  final double? cpuTemperatureCelsius;
  final double? gpuTemperatureCelsius;
  final ProbeConfidence confidence;
}
```

Thermal states:

```text
nominal
fair
serious
critical
unknown
```

Thermal data is often unavailable on Windows without vendor-specific APIs.

Missing thermal data must not be interpreted as nominal.

Android thermal state becomes more important in Phase 7.

---

## 18. Probe Confidence

```dart
enum ProbeConfidence {
  unknown,
  inferred,
  reported,
  verified,
}
```

Meaning:

- `unknown`: no reliable observation;
- `inferred`: derived from indirect evidence;
- `reported`: provided by OS/driver API;
- `verified`: confirmed through a controlled capability probe.

The profile must retain confidence per critical observation.

---

## 19. Probe Observations

```dart
@immutable
class ProbeObservation {
  final String key;
  final Object? value;
  final String source;
  final ProbeConfidence confidence;
  final DateTime observedAt;
}
```

Examples:

```text
windows.memory.total
windows.gpu.adapter.0.dedicated_bytes
windows.cuda.runtime_available
windows.vulkan.device_available
android.memory_class
android.thermal.status
```

Observations are diagnostics; plan resolution consumes normalized fields.

---

## 20. Normalized Hardware Profile

```dart
@immutable
class HardwareProfile {
  final HardwareProfileId profileId;
  final DateTime createdAt;
  final PlatformDescriptor platform;
  final CpuCapabilityProfile cpu;
  final MemoryBudget memory;
  final List<AcceleratorProfile> accelerators;
  final StorageCapabilityProfile storage;
  final PowerCapabilityProfile power;
  final ThermalCapabilityProfile thermal;
  final Set<RuntimeBackend> candidateBackends;
  final HardwareTier tier;
  final Set<HardwareProfileTag> tags;
  final List<HardwareConstraint> constraints;
  final List<HardwareProfileWarning> warnings;
}
```

---

## 21. Memory Budget

```dart
@immutable
class MemoryBudget {
  final int systemBudgetBytes;
  final int runtimeReserveBytes;
  final int modelWeightsBudgetBytes;
  final int contextAndWorkingSetBudgetBytes;
  final int rollbackOrConcurrentLoadBudgetBytes;
  final int safetyReserveBytes;
}
```

### 21.1 Budget separation

The resolver must distinguish:

- model weights;
- KV/context memory;
- runtime overhead;
- temporary buffers;
- application reserve;
- concurrent model load;
- update/rollback disk needs.

### 21.2 Effective model budget

Conceptually:

```text
effective model memory budget =
safe application memory budget
- runtime reserve
- context reserve
- application safety reserve
```

For GPU execution, effective capacity is constrained by both device and system budgets.

---

## 22. Accelerator Profile

```dart
@immutable
class AcceleratorProfile {
  final GraphicsAdapterId adapterId;
  final GraphicsBackend backend;
  final int deviceBudgetBytes;
  final int hostBudgetBytes;
  final AcceleratorSuitability suitability;
  final ProbeConfidence confidence;
  final List<HardwareConstraint> constraints;
}
```

Suitability:

```text
unsupported
degraded
supported
recommended
```

### 22.1 Backend candidates

Candidate backend selection is ordered but not final.

Example:

```text
CUDA recommended
Vulkan supported
CPU supported
```

Runtime initialization confirms the final backend.

---

## 23. Hardware Tiers

Hardware tiers are coarse UX and diagnostics categories.

They must not replace detailed budget calculations.

```dart
enum HardwareTier {
  unsupported,
  minimal,
  constrained,
  balanced,
  performance,
  workstation,
  unknown,
}
```

### 23.1 Meaning

| Tier | Meaning |
|---|---|
| `unsupported` | No validated plan can satisfy hard requirements. |
| `minimal` | Only deterministic or very small shared-model plans are expected. |
| `constrained` | One small model, sequential loading, reduced context, or CPU-heavy execution. |
| `balanced` | Recommended single/shared model or two-model sequential plan. |
| `performance` | Two suitable models may run with substantial acceleration. |
| `workstation` | High resource margin, simultaneous residency and larger contexts may be viable. |
| `unknown` | Detection insufficient; safe probing or manual profile required. |

### 23.2 No universal fixed thresholds

Tier assignment must be policy-driven and benchmark-validated.

The specification may ship provisional threshold tables, but the final plan is always validated against variant-specific estimates.

---

## 24. Hardware Profile Tags

Examples:

```text
windows-x64
android-arm64
cuda-capable
vulkan-capable
cpu-only
integrated-gpu
discrete-gpu
low-memory
shared-model-preferred
sequential-residency-preferred
simultaneous-residency-candidate
battery-constrained
thermal-constrained
remote-session
virtualized
```

Tags improve diagnostics and policy matching.

They must not duplicate full capability logic.

---

## 25. Hardware Constraints

```dart
@immutable
class HardwareConstraint {
  final HardwareConstraintCode code;
  final HardwareConstraintSeverity severity;
  final String message;
  final Map<String, Object?> diagnostics;
}
```

Possible codes:

```text
insufficientSystemMemory
insufficientDeviceMemory
unknownDeviceMemory
backendUnavailable
driverIncompatible
storageInsufficient
thermalLimited
batteryLimited
cpuInstructionUnavailable
runtimePackageUnavailable
remoteSessionAccelerationUnavailable
virtualizationLimitation
```

Severity:

```text
info
warning
hard
```

Hard constraints remove a plan from consideration.

---

## 26. Model Memory Estimation

### 26.1 Inputs

The estimator consumes:

- artifact size;
- manifest `memory_estimation`;
- model architecture;
- quantization;
- context size;
- batch size;
- GPU offload configuration;
- runtime package;
- backend;
- runtime empirical coefficients.

### 26.2 Estimate result

```dart
@immutable
class ModelMemoryEstimate {
  final int weightsHostBytes;
  final int weightsDeviceBytes;
  final int contextHostBytes;
  final int contextDeviceBytes;
  final int runtimeOverheadBytes;
  final int temporaryPeakBytes;
  final int totalHostPeakBytes;
  final int totalDevicePeakBytes;
  final double confidence;
  final List<String> assumptions;
}
```

### 26.3 Conservative estimate

When exact information is absent, the estimator must use a conservative upper bound.

### 26.4 Empirical refinement

After successful load, the runtime may report observed memory.

Observed data may refine future estimates for:

```text
same runtime build
same model content ID
same backend
same context/load profile
same platform family
```

It must not globally overwrite manifest requirements.

---

## 27. Context Budget

Context size materially affects memory use.

The resolver must treat it as a plan variable, not a fixed constant.

Selection order:

```text
required gameplay minimum
    |
    v
model minimum
    |
    v
hardware-safe context
    |
    v
model default/recommended
    |
    v
optional larger context
```

A context reduction is permitted only when it remains above the gameplay minimum.

The final context size must be recorded in the execution plan.

---

## 28. Runtime Backend Selection

### 28.1 Windows order

Initial preference policy:

```text
1. CUDA when verified compatible and sufficiently beneficial
2. Vulkan when verified compatible
3. CPU
```

This is a default policy, not a guarantee.

### 28.2 Backend selection factors

- runtime package installed;
- adapter compatibility;
- driver compatibility;
- device memory;
- host memory;
- model architecture;
- model size;
- context size;
- measured startup/load success;
- user preference;
- deny/allow rules;
- current power/thermal condition.

### 28.3 CPU fallback

CPU fallback remains valid when:

- model fits system budget;
- expected latency is acceptable for the selected profile;
- user accepts degraded performance;
- no acceleration backend is reliable.

### 28.4 Backend-specific runtime package

The selected backend must map to a compatible pinned runtime package.

Hardware profile does not construct executable paths.

---

## 29. Model Residency Policies

```dart
enum ModelResidencyPolicy {
  simultaneous,
  sequential,
  sharedSingleModel,
  evaluatorDeterministic,
}
```

### 29.1 Simultaneous

Evaluator and Actor models are resident concurrently.

Requires:

- sufficient peak host/device memory;
- compatible runtime topology;
- acceptable process/runtime overhead;
- validated stability.

### 29.2 Sequential

Only the required model is resident.

Trade-offs:

- lower memory;
- model-switch latency;
- lifecycle/runtime coordination;
- possible cache loss.

### 29.3 Shared single model

One model satisfies both roles.

Requires:

- manifest role compatibility;
- prompt/structured-output validation;
- acceptable Actor quality;
- acceptable Evaluator reliability.

### 29.4 Deterministic Evaluator

The Evaluator uses rule-based logic while the Actor uses a local model.

This is a valid production fallback profile, not a test-only failure state.

---

## 30. Execution Plan

Conceptual type:

```dart
@immutable
class ModelExecutionPlan {
  final ModelExecutionPlanId planId;
  final HardwareProfileId hardwareProfileId;
  final String evaluatorLogicalModelId;
  final String actorLogicalModelId;
  final ModelResolution evaluatorResolution;
  final ModelResolution actorResolution;
  final ModelResidencyPolicy residencyPolicy;
  final RuntimeTopology runtimeTopology;
  final RuntimeBackend backend;
  final String runtimePackageId;
  final ModelLoadOptions evaluatorLoadOptions;
  final ModelLoadOptions actorLoadOptions;
  final int evaluatorContextSize;
  final int actorContextSize;
  final List<ModelExecutionPlanDecision> decisions;
  final List<ModelExecutionPlanWarning> warnings;
}
```

### 30.1 Runtime topology

```dart
enum RuntimeTopology {
  singleRuntimeSingleModel,
  singleRuntimeSequentialModels,
  singleRuntimeMultipleModels,
  dualRuntimeProcesses,
  nativeSharedContext,
  deterministicPlusRuntime,
}
```

The topology is explicit and testable.

---

## 31. Plan Resolution Algorithm

The resolver evaluates plans in a deterministic order.

### 31.1 Inputs

```text
HardwareProfile
Runtime package catalog
RuntimeCapabilities, when already initialized
Model manifest
InstalledModelRegistry
Model availability
User policy
Application safety policy
Benchmark/compatibility cache
```

### 31.2 Candidate generation

Generate candidate combinations for:

```text
runtime backend
runtime package
Evaluator variant
Actor variant
residency policy
context sizes
load options
runtime topology
```

### 31.3 Hard filtering

Reject candidates that fail:

```text
platform compatibility
runtime contract compatibility
runtime package compatibility
model role compatibility
verified availability policy
minimum memory
minimum storage
required instruction sets
backend support
license/revocation rules
gameplay minimum context
```

### 31.4 Scoring

Remaining candidates may be scored by:

```text
quality tier
installed availability
expected latency
memory margin
backend reliability
power efficiency
update/download requirement
user preference
fallback distance
```

### 31.5 Tie-breaking

Tie-breaking must be stable.

Recommended final tie-breaker:

```text
runtimePackageId
then evaluator variant_id
then actor variant_id
then residencyPolicy enum order
```

### 31.6 Explanation

The selected plan must include human-readable and machine-readable decisions.

---

## 32. Plan Safety Margins

### 32.1 Memory headroom

A plan must not target 100% of reported memory.

Separate safety margins apply to:

- system RAM;
- device memory;
- storage;
- runtime process count;
- context growth.

### 32.2 Peak versus steady-state

Plan validation must use estimated peak memory, not only steady-state memory.

Peak events include:

- model loading;
- context allocation;
- simultaneous old/new model during switch;
- dual runtime startup;
- update smoke validation.

### 32.3 Unknown data

Unknown critical capacity increases required safety margin or removes aggressive plans.

---

## 33. Provisional Profile Policy

Until benchmarks are available, Phase 6 may use conservative provisional policies.

Example policy classes:

```text
minimal:
  deterministic Evaluator
  small Actor model
  CPU or low-memory backend
  reduced context

constrained:
  shared model or sequential two-model plan
  conservative context
  no simultaneous dual runtime by default

balanced:
  shared recommended model or sequential specialized models
  acceleration preferred
  moderate context

performance:
  simultaneous specialized models may be evaluated
  acceleration required for recommended plan

workstation:
  simultaneous specialized models
  larger context candidate
  additional diagnostic/benchmark margin
```

These are policy descriptions, not final byte thresholds.

---

## 34. Reference Development Profile

The reference development machine is:

```text
Windows x64
64 GiB system RAM
12 GiB dedicated VRAM
single workstation
```

This profile is used to:

- validate managed Windows runtime integration;
- test CUDA/Vulkan/CPU fallbacks where available;
- benchmark simultaneous and sequential residency;
- validate two-runtime-process topology;
- test realistic development models.

It is not:

- the minimum supported configuration;
- the only target;
- proof that every 12 GiB GPU behaves identically;
- permission to hardcode 12 GiB assumptions.

---

## 35. Windows Hardware Probe

### 35.1 Required observations

Windows implementation should collect:

```text
OS version/build
x64 architecture
logical and physical CPU count
instruction sets where practical
total and available physical RAM
graphics adapters
dedicated/shared GPU memory
driver identity/version
CUDA runtime/package availability
Vulkan device/runtime availability
model-store storage availability
remote session state
power source
```

### 35.2 Data sources

Implementation may use:

- Win32 APIs;
- WMI/CIM;
- DXGI;
- Vulkan enumeration;
- runtime-package self-probe;
- controlled helper executable.

No single source is assumed authoritative for every field.

### 35.3 Remote Desktop

Remote sessions may expose reduced or different graphics capabilities.

A cached local GPU profile must not be reused blindly during a remote session.

### 35.4 Driver/runtime mismatch

The hardware probe may predict CUDA support while runtime initialization fails.

The failure must:

- mark the combination unreliable;
- permit Vulkan/CPU fallback if policy allows;
- not mark the GPU universally unsupported without appropriate scope.

---

## 36. Android Hardware Probe

### 36.1 Required observations

Phase 7 should collect:

```text
Android API level
arm64 ABI
total and available memory
memory class / large memory class
CPU core topology
relevant instruction sets
available private storage
thermal state
power/battery state
supported native runtime libraries
optional AICore availability and capabilities
```

### 36.2 Android memory

Android process memory constraints may be lower than total physical RAM.

The profile must distinguish:

```text
device total memory
currently available memory
application/process class limits
safe native allocation budget
```

### 36.3 Process recreation

Hardware profile caching must survive process recreation but be invalidated when:

- application version changes materially;
- runtime package changes;
- OS updates;
- device thermal/power context requires refresh;
- prior initialization contradicts the cache.

### 36.4 AICore

AICore capability is represented as an optional `systemManaged` backend.

Availability alone does not imply model-role suitability.

---

## 37. Runtime Feedback Loop

After runtime initialization or model load, the system may record:

```text
backend initialization success/failure
model load success/failure
observed load time
observed memory
generation latency
runtime crash
thermal degradation
```

### 37.1 Compatibility cache

Conceptual record:

```dart
class HardwareRuntimeCompatibilityRecord {
  final HardwareFingerprint hardware;
  final String runtimePackageId;
  final String modelContentId;
  final RuntimeBackend backend;
  final bool succeeded;
  final DateTime observedAt;
  final RuntimeFailureCode? failureCode;
  final RuntimeResourceSnapshot? observedResources;
}
```

### 37.2 Scope

Compatibility records are local hints.

They must be invalidated when relevant versions or hardware fingerprints change.

### 37.3 Failure memory

Repeated known failures may lower candidate priority.

A single transient failure must not permanently blacklist a backend.

---

## 38. Hardware Fingerprint

A privacy-conscious fingerprint may include:

```text
OS family and relevant build
CPU architecture and instruction class
normalized RAM bucket
GPU vendor/device identifier where available
dedicated memory bucket
driver version
runtime package ID
```

It must not include:

- user name;
- machine name;
- serial number;
- MAC address;
- unrelated unique identifiers.

The fingerprint is local unless explicit diagnostic export occurs.

---

## 39. User Policy

```dart
@immutable
class HardwareExecutionPolicy {
  final RuntimeBackendPreference backendPreference;
  final PerformancePreference performancePreference;
  final bool allowBackendFallback;
  final bool allowSequentialResidency;
  final bool allowSharedModel;
  final bool allowDeterministicEvaluator;
  final bool allowExperimentalVariants;
  final int? maximumSystemMemoryBytes;
  final int? maximumDeviceMemoryBytes;
  final int? maximumCpuThreads;
}
```

Performance preferences:

```text
automatic
quality
balanced
efficiency
minimumMemory
```

### 39.1 User policy limits

User settings may constrain resource use.

They may not bypass:

- hard memory requirements;
- compatibility;
- integrity;
- revocation;
- runtime safety constraints.

---

## 40. Dynamic Conditions

The hardware profile has stable and dynamic parts.

Stable:

```text
architecture
CPU instruction sets
total RAM
GPU identity
driver version
runtime packages
```

Dynamic:

```text
available memory
available storage
power state
thermal state
remote session
```

Plan resolution may refresh dynamic fields before expensive operations.

---

## 41. Plan Re-evaluation

Re-evaluate when:

```text
runtime initialization contradicts profile
model installation changes
runtime package changes
model manifest changes
user policy changes
available memory falls below safety margin
device thermal state becomes serious/critical
power policy changes materially
application resumes on Android
driver/OS update detected
```

Gameplay must not be interrupted mid-generation without an explicit runtime recovery policy.

---

## 42. Degradation Strategy

Recommended ordered degradation:

```text
1. reduce optional context toward gameplay minimum
2. reduce batch/load aggressiveness
3. reduce GPU offload if host memory permits
4. switch simultaneous to sequential residency
5. switch specialized models to shared model
6. switch Evaluator to deterministic fallback
7. select smaller compatible model variant
8. switch acceleration backend
9. CPU fallback
10. declare no supported plan
```

The exact order may vary by user policy and measured performance.

Every degradation must be recorded.

---

## 43. Unsupported Hardware

A.U.R.A. declares hardware unsupported only when no candidate plan satisfies hard constraints.

The result must explain:

```text
missing capability
required resource
detected resource
possible remediation
available fallback, if any
```

Examples of remediation:

- free memory;
- free storage;
- install compatible runtime package;
- select smaller model profile;
- use deterministic Evaluator;
- switch backend;
- update a known-incompatible driver;
- use another device.

---

## 44. Diagnostics

Technical diagnostics should include:

```text
profile ID
timestamp
platform/architecture
CPU core and instruction summary
system memory total/available/budget
graphics adapters
dedicated/shared memory
candidate backends
selected backend
hardware tier
constraints
warnings
selected execution plan
rejected plans and reasons
compatibility-cache observations
```

Normal UI should show a simplified summary.

Raw hardware data must not be uploaded automatically.

---

## 45. Persistence and Cache

### 45.1 Cached profile

A cached profile may accelerate startup.

It must contain:

```text
schema version
application version
probe version
hardware fingerprint
stable observations
last dynamic observations
created/updated timestamps
```

### 45.2 Cache invalidation

Invalidate on:

- schema major change;
- application migration;
- runtime package change;
- driver/OS change;
- hardware fingerprint mismatch;
- explicit rescan;
- repeated runtime contradiction.

### 45.3 Atomic writes

Profile cache and compatibility records must use atomic persistence.

They are recoverable caches, not authoritative trust roots.

---

## 46. Security and Privacy

### 46.1 Least privilege

Hardware probe must not require administrator privileges for standard operation.

### 46.2 Helper processes

Any helper executable must be:

- pinned;
- verified;
- invoked with bounded arguments;
- parsed defensively;
- terminated after probing.

### 46.3 Command injection

Hardware names and driver strings must never be inserted into shell commands.

### 46.4 Privacy

Hardware diagnostics remain local by default.

Export requires explicit user action.

### 46.5 Denial-of-service resistance

Probe and benchmark operations must have:

- timeouts;
- bounded output;
- bounded allocations;
- cancellation.

---

## 47. Testing Strategy

### 47.1 Synthetic profiles

Required synthetic fixtures:

```text
windows_cpu_only_minimal
windows_integrated_vulkan_constrained
windows_8gb_ram_cpu
windows_16gb_ram_8gb_vram
windows_64gb_ram_12gb_vram_reference
windows_multi_gpu
windows_remote_session
windows_unknown_vram
android_arm64_low_memory
android_arm64_shared_model
android_arm64_aicore_available
android_thermal_critical
```

These are logical fixture names, not final thresholds.

### 47.2 Probe tests

Use fake platform probes.

Standard tests must not depend on the developer’s actual hardware.

### 47.3 Resolver tests

Cover:

```text
deterministic selection
hard constraint rejection
unknown memory handling
CUDA-to-Vulkan fallback
Vulkan-to-CPU fallback
simultaneous-to-sequential degradation
shared-model selection
deterministic-Evaluator selection
context reduction
user memory cap
thermal/power restriction
runtime contradiction
```

### 47.4 Boundary tests

Test exact behavior just below, at, and above policy thresholds once thresholds are defined.

### 47.5 Real hardware tests

Real-hardware validation is separate and explicit.

It must capture:

```text
hardware fingerprint
runtime package
model content IDs
execution plan
observed memory
latency
result
```

---

## 48. Benchmark Strategy

### 48.1 Purpose

Benchmarks validate plan policy, not gameplay correctness.

### 48.2 Required measurements

```text
runtime initialization time
model load time
peak system memory
peak device memory
Evaluator latency
Actor first-token latency
Actor total latency
model-switch latency
runtime recovery time
thermal behavior where available
```

### 48.3 Reference scenarios

Windows Phase 6 must compare at least:

```text
one shared model
two models sequential
two models simultaneous in one runtime, if supported
two runtime processes
deterministic Evaluator + Actor model
CUDA
Vulkan
CPU
```

### 48.4 No automatic destructive benchmark

A benchmark that may allocate substantial memory or trigger thermal load requires explicit invocation.

---

## 49. Relationship to Model Manifest

The hardware profile consumes:

```text
hardware_requirements
memory_estimation
supported_backends
platform compatibility
inference_profile
quality tier
capabilities
```

The manifest must not contain device-specific local measurements.

The profile must not modify the manifest.

---

## 50. Relationship to Model Lifecycle

The execution-plan resolver consumes availability dispositions:

```text
installedVerified
downloadRequired
offlineImportRequired
builtinFallback
externalAvailable
unresolvable
```

Hardware suitability does not imply installation.

Installation does not imply hardware suitability.

The resolver combines both.

---

## 51. Relationship to Inference Runtime

`RuntimeFactory` uses the hardware profile to propose a runtime package/backend.

After initialization, `RuntimeCapabilities` refine the plan.

The runtime may reject load options.

The application must then:

```text
record contradiction
recalculate plan
select safe fallback
```

It must not repeatedly retry the same known-invalid configuration without bounds.

---

## 52. Relationship to Application Bootstrap

Recommended bootstrap order:

```text
load settings/policy
      |
      v
load cached hardware profile
      |
      v
refresh required observations
      |
      v
load trusted model/runtime manifests
      |
      v
read installed model registry
      |
      v
generate candidate execution plan
      |
      v
initialize selected runtime
      |
      v
reconcile actual capabilities
      |
      v
finalize execution plan
      |
      v
construct RuntimeInferenceBridge
      |
      v
construct GameControllerNotifier
```

`GameControllerNotifier` is not responsible for probing or plan resolution.

---

## 53. Migration from Current Repository

### Stage 1 — Introduce platform-neutral types

Add:

```text
HardwareProbe
RawHardwareSnapshot
HardwareProfile
MemoryBudget
AcceleratorProfile
HardwareExecutionPolicy
```

Use synthetic profiles in tests.

### Stage 2 — Introduce plan resolver against development manifest

Preserve LM Studio through `externalAvailable`.

No native probing is required to preserve existing behavior initially.

### Stage 3 — Windows probe implementation

Collect CPU, RAM, GPU, backend and storage observations.

### Stage 4 — Runtime package compatibility

Connect probe results to pinned CPU/CUDA/Vulkan runtime packages.

### Stage 5 — Hardware-aware managed model resolution

Use manifest requirements and installed registry.

### Stage 6 — Benchmark and calibrate provisional policies

Use the reference development machine and additional supported profiles.

### Stage 7 — Android implementation

Reuse normalized types and resolver with an Android-specific probe.

---

## 54. Decisions Deferred

The following remain open until implementation/benchmark data exists:

1. final byte thresholds for hardware tiers;
2. exact fixed and percentage memory reserves;
3. minimum gameplay context size;
4. default CPU thread reserve;
5. backend preference exceptions;
6. driver denylist/allowlist;
7. exact runtime package matrix;
8. final model memory coefficients;
9. simultaneous versus dual-process default on 12 GiB VRAM;
10. Android minimum memory/device support matrix;
11. AICore eligibility criteria;
12. automatic benchmark eligibility.

These decisions must be resolved in the hardware compatibility matrix and production hardening stages.

---

## 55. Acceptance Criteria

This specification is approved when all statements are accepted:

```text
- Hardware probing is platform-specific but produces a platform-neutral profile.
- Model and runtime selection use capabilities and budgets, not product names.
- Dedicated and shared GPU memory remain distinct.
- Total memory is not treated as fully allocatable memory.
- Model memory estimation includes weights, context, runtime and peak overhead.
- Hardware tiers are explanatory categories, not the final selection mechanism.
- Runtime capabilities override probe predictions.
- Backend fallback is explicit and observable.
- Execution plans include backend, topology, residency, variants, context and load options.
- Simultaneous, sequential, shared-model and deterministic-Evaluator plans are supported.
- Unknown or low-confidence data selects conservative behavior.
- Windows and Android consume the same normalized profile and resolver contracts.
- Standard tests use synthetic profiles, never the developer’s actual hardware.
- Real-hardware benchmarks are explicit and separate.
- The 64 GiB RAM / 12 GiB VRAM development machine is a validation profile, not a minimum requirement.
```

---

## 56. Exit Criteria for This Document

The document is complete when:

- committed under `docs/phase6/HARDWARE_PROFILE_SPEC.md`;
- reviewed against runtime, manifest and lifecycle specifications;
- ownership between probe, profile builder, runtime factory and plan resolver is agreed;
- provisional policy is clearly separated from benchmark-calibrated values;
- Windows and Android assumptions are explicit;
- the test strategy can define synthetic hardware fixtures;
- the compatibility matrix can later provide measured support results;
- Antigravity can map the specification to repository changes without hardcoding the developer workstation.

---

## 57. Recommended Antigravity Review Prompt

After committing this document:

```text
Read in full, in this order:

1. docs/phase6/CROSS_PLATFORM_RUNTIME_ADR.md
2. docs/phase6/INFERENCE_RUNTIME_CONTRACT.md
3. docs/phase6/MODEL_MANIFEST_SPEC.md
4. docs/phase6/MODEL_LIFECYCLE_SPEC.md
5. docs/phase6/HARDWARE_PROFILE_SPEC.md
6. previous Phase 6 repository-aware review reports
7. ARCHITECTURE.md
8. AGENTS.md, if present

Perform a repository-aware, read-only review of HARDWARE_PROFILE_SPEC.md.

Do not modify code or documentation.
Do not implement hardware probing.
Do not select final production models, quantizations or hardware thresholds.
Do not run heavyweight benchmarks.

Produce a structured report containing:

1. Current hardware assumptions
   - hardcoded model choices;
   - timeouts and context limits;
   - CPU/GPU assumptions;
   - LM Studio assumptions;
   - current settings and bootstrap behavior;
   - any existing platform detection.

2. Ownership review
   Verify the separation among:
   - HardwareProbe;
   - HardwareProfileBuilder;
   - HardwareProfileRepository;
   - RuntimeFactory;
   - ModelResolver;
   - ModelExecutionPlanResolver;
   - ModelLifecycleManager;
   - InferenceRuntime;
   - application bootstrap and UI.

3. Data-model completeness
   Evaluate:
   - CPU descriptor;
   - memory descriptor and budgets;
   - graphics adapter descriptor;
   - dedicated versus shared memory;
   - storage;
   - power;
   - thermal state;
   - confidence;
   - constraints;
   - hardware fingerprint;
   - compatibility cache.

4. Execution-plan completeness
   Evaluate:
   - backend selection;
   - runtime package selection;
   - model variants;
   - context size;
   - load options;
   - simultaneous residency;
   - sequential residency;
   - shared single model;
   - deterministic Evaluator;
   - one versus two runtime processes.

5. Windows feasibility
   Analyze:
   - reliable RAM/available-memory detection;
   - GPU enumeration;
   - dedicated/shared VRAM detection;
   - CUDA availability;
   - Vulkan availability;
   - remote desktop behavior;
   - multiple GPUs;
   - driver/runtime mismatch;
   - CPU fallback;
   - storage probing;
   - non-admin operation.

6. Android feasibility
   Analyze:
   - total versus process-safe memory;
   - memory class;
   - app-private storage;
   - thermal state;
   - battery/power state;
   - arm64 instruction capability;
   - process recreation;
   - native runtime packages;
   - optional AICore backend;
   - shared-model plans.

7. Memory-estimation review
   Verify that the proposed model can represent:
   - weights;
   - KV/context memory;
   - runtime overhead;
   - temporary peak;
   - host/device split;
   - simultaneous loads;
   - dual runtime processes;
   - context reduction.

8. Determinism and fallback
   Verify:
   - deterministic candidate ordering;
   - hard filtering;
   - stable tie-breaking;
   - explicit fallback;
   - handling of unknown/low-confidence data;
   - repeated runtime contradiction.

9. Privacy and security
   Evaluate:
   - hardware fingerprint contents;
   - diagnostics;
   - helper-process trust;
   - command injection risks;
   - local-only behavior;
   - bounded probes and benchmarks.

10. Testability
    Identify:
    - required fake probes;
    - synthetic profile fixtures;
    - resolver boundary tests;
    - current tests reusable as a base;
    - separation of real-hardware benchmarks from standard CI.

11. Impact on following documents
    State decisions that must be reflected in:
    - TEST_RUNTIME_STRATEGY.md;
    - HARDWARE_COMPATIBILITY_MATRIX.md;
    - WINDOWS_INSTALLER_AND_UPDATE_SPEC.md;
    - ANDROID_READINESS_SPEC.md;
    - RELEASE_PIPELINE_SPEC.md.

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

For every proposed document modification specify:
- exact section;
- rationale;
- Windows impact;
- Android impact;
- implementation impact;
- test impact.

Conclude with one judgment:

A. DOCUMENT APPROVABLE WITHOUT CHANGES
B. APPROVABLE WITH NON-BLOCKING CHANGES
C. REQUIRES CHANGES BEFORE TEST_RUNTIME_STRATEGY
D. HARDWARE PROFILE ARCHITECTURE INCOMPATIBLE WITH CURRENT REPOSITORY
```

---

## 58. Final Decision

A.U.R.A. will use a platform-neutral, confidence-aware hardware profile to select local inference runtimes, model variants, memory budgets, context sizes, execution topologies and fallback strategies.

Hardware selection will be conservative, deterministic and explainable. Runtime-reported facts override probe assumptions, and no plan will rely solely on marketed product names or raw RAM/VRAM totals.

The Windows development workstation with 64 GiB RAM and 12 GiB VRAM will be used as a reference validation profile, while the architecture remains capable of supporting lower-resource Windows systems and Android arm64 devices through sequential, shared-model and deterministic fallback plans.

---

## 59. Explainable Recommendation & User Profile Specification

### 59.1 Explainable Provisioning Recommendation Engine

The hardware profiler and `HardwareProfileBuilder` generate an **explainable recommendation proposal** for application provisioning and installer setup.

#### 59.1.1 Proposal Data Payload
The recommendation proposal includes:
- **Recommended Backend:** Selected inference runtime backend (e.g. `cuda`, `vulkan`, `metal`, `cpu`).
- **Recommended Variants:** Model variant IDs for `aura.evaluator.primary` and `aura.actor.primary`.
- **Quantization & Topology:** Target quantization (e.g. `Q4_K_M`), context size (e.g. 2048 / 4096 tokens), and model residence strategy (separate side-by-side models vs single shared model).
- **Resource Footprint Estimates:** Expected RAM, VRAM, and disk storage requirements.
- **Confidence & Rationale:** Numerical confidence score (0–100%) and human-readable explanation (e.g. *"Dedicated GPU VRAM (12 GiB) detected; dual-model CUDA residency recommended"*).
- **Warnings & Alternatives:** Potential performance bottlenecks and compatible fallback plans.

### 59.2 User-Facing Performance Profiles

A.U.R.A. exposes four user-facing profile presets:

1. **Automatic / Recommended (`automatic`):**
   - Automatically selects the optimal execution plan based on hardware detection and safety margins.
2. **Memory Saver (`memorySaver`):**
   - Minimizes VRAM and RAM footprint by selecting lightweight quantizations (e.g. `Q4_K_M`), smaller context sizes, or single-model shared residency.
3. **Quality (`quality`):**
   - Maximizes model fidelity and parameters up to the maximum safe hardware ceiling.
4. **Manual / Advanced (`manual`):**
   - Allows fine-grained user override of runtime backend, GPU layers, CPU threads, context size, and model variants.

### 59.3 Persistent Preference Modes

The active provisioning mode is persisted in application settings:
- **`automatic`:** Re-evaluates hardware on hardware changes and applies dynamic recommendations.
- **`recommendedPinned`:** Locks the initial recommended plan confirmed during installer setup until the user manually re-runs benchmarks.
- **`manual`:** Preserves user-defined manual overrides.

### 59.4 Validation Rules & Profiler Boundaries

1. **User Override Authority:**
   - The user is never forced to accept the recommendation proposal.
2. **Compatibility Enforcement:**
   - Manual configurations that violate physical system limits (e.g. allocation exceeding total VRAM + RAM leading to fatal process crash) are **hard-blocked** with explanatory diagnostic messages.
   - Suboptimal but compatible configurations (e.g. running on CPU when CUDA GPU is available) generate **warnings** but are permitted.
3. **Read-Only Profiler Boundary:**
   - The hardware profiler is strictly read-only. It **never initiates downloads, model store modifications, or process execution**. It produces structured inputs exclusively for `ModelExecutionPlanResolver` and provisioning UI wizards.
