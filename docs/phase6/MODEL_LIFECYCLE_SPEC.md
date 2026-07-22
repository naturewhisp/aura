# Model Lifecycle Specification

**Project:** A.U.R.A. — Artificial Unbound Reasoning Arena  
**Target path:** `docs/phase6/MODEL_LIFECYCLE_SPEC.md`  
**Status:** Proposed for approval  
**Phase:** 6.0 — Architecture and Distribution Design Gate  
**Parent documents:**
- `docs/phase6/CROSS_PLATFORM_RUNTIME_ADR.md`
- `docs/phase6/INFERENCE_RUNTIME_CONTRACT.md`
- `docs/phase6/MODEL_MANIFEST_SPEC.md`
- `docs/phase6/PHASE_6_4_ACQUISITION_AND_LIFECYCLE_SPEC.md`

**Repository baseline:** `5d5f32533a520e5a224a53462a711f52410055ed`  
**Lifecycle specification version:** 1.0  
**Primary production target:** Windows x64  
**Secondary production target:** Android arm64, Phase 7  
**Last updated:** 2026-07-20

---

## 1. Purpose

This specification defines the complete lifecycle of model artifacts used by A.U.R.A.

It covers:

- catalog acquisition;
- model resolution;
- download;
- resumable transfer;
- temporary staging;
- checksum and size verification;
- GGUF inspection;
- license acceptance;
- atomic installation;
- installed-model registry updates;
- activation;
- runtime loading;
- unloading;
- repair;
- update;
- rollback;
- offline import;
- garbage collection;
- uninstall;
- recovery after interruption or corruption.

The lifecycle must guarantee that A.U.R.A. never loads a partially downloaded, unverified, incompatible, or ambiguously identified managed model.

---

## 2. Architectural Role

The lifecycle sits between manifest resolution and runtime loading:

```text
Model Manifest
      |
      v
ModelResolver
      |
      v
ModelLifecycleManager
      |
      +-- ArtifactDownloader
      +-- ModelStore
      +-- IntegrityVerifier
      +-- ModelInspector
      +-- InstalledModelRegistry
      +-- LicenseAcceptanceStore
      +-- ModelLifecycleJournal
      |
      v
ResolvedModelArtifact
      |
      v
InferenceRuntime.loadModel(...)
```

The lifecycle is responsible for artifact state.

The runtime is responsible for execution state.

The Game Controller is responsible for gameplay state.

These three state domains must remain independent.

---

## 3. Goals

The model lifecycle must provide:

1. reproducible managed installations;
2. interruption-safe downloads;
3. atomic state transitions;
4. deterministic repair and rollback;
5. explicit ownership of managed files;
6. offline import with exact verification;
7. independent model updates;
8. persistence across application upgrades;
9. installed and portable deployment support;
10. Windows and Android compatibility;
11. no implicit network access during tests;
12. diagnostics sufficient for support and recovery;
13. compatibility with externally owned development bindings;
14. future compatibility with LoRA artifacts.

---

## 4. Non-Goals

This specification does not define:

- final model filenames or quantizations;
- exact hardware selection thresholds;
- the inference runtime process lifecycle;
- Windows installer UI;
- Android download UI;
- release signing implementation;
- LoRA training;
- gameplay fallback decisions;
- final cloud mirror strategy;
- exact user-facing wording.

Those concerns are defined elsewhere.

---

## 5. Lifecycle Domains

A.U.R.A. distinguishes three model domains.

### 5.1 Managed model

A model whose bytes are:

- declared by a trusted manifest;
- installed into A.U.R.A.-managed storage;
- verified by size and SHA-256;
- recorded in `installed-models.json`;
- eligible for automatic selection.

### 5.2 Imported managed model

A user-provided artifact that:

- exactly matches a manifest variant;
- is copied or adopted into managed storage;
- is verified;
- is recorded in the installed registry;
- becomes equivalent to a downloaded managed model.

### 5.3 Externally owned model binding

A development-only binding where:

- an external server such as LM Studio owns the model;
- A.U.R.A. does not download or install its bytes;
- no managed registry entry is created;
- `discoverModels()` identifies availability;
- `external_binding.accepted_server_model_ids` maps the server model to a logical variant;
- a session-scoped `ModelHandle` is still created;
- the binding is never reported as a verified managed installation.

This domain is not available implicitly in production profiles.

---

## 6. Primary Components

### 6.1 `ModelLifecycleManager`

Coordinates high-level operations:

```dart
abstract interface class ModelLifecycleManager {
  Future<ModelAvailability> evaluateAvailability(
    ModelVariant variant,
  );

  Future<ModelInstallationResult> ensureInstalled(
    ModelVariant variant,
    ModelAvailabilityPolicy policy,
  );

  Future<ModelInstallationResult> install(
    ModelVariant variant,
    ModelInstallRequest request,
  );

  Future<ModelInstallationResult> importArtifact(
    ModelVariant variant,
    ModelImportRequest request,
  );

  Future<ModelRepairResult> repair(
    String variantId,
  );

  Future<ModelUpdateResult> update(
    ModelUpdateRequest request,
  );

  Future<ModelRollbackResult> rollback(
    String logicalModelId,
  );

  Future<void> remove(
    ModelRemovalRequest request,
  );

  Future<ModelGarbageCollectionResult> collectGarbage(
    ModelGarbageCollectionPolicy policy,
  );
}
```

### 6.2 `ArtifactDownloader`

Responsible for network transfer only.

It does not:

- select models;
- update the installed registry;
- activate variants;
- load models into a runtime.

### 6.3 `ModelStore`

Owns managed storage operations:

- path/URI allocation;
- staging;
- atomic rename/switch;
- backup;
- quarantine;
- deletion;
- storage accounting;
- platform-specific file operations.

### 6.4 `IntegrityVerifier`

Verifies:

```text
size
SHA-256
optional source metadata
optional signature metadata
```

### 6.5 `ModelInspector`

Inspects local artifact metadata without loading the full model into inference.

For GGUF it may validate:

- magic/header;
- GGUF version;
- architecture;
- quantization;
- embedded metadata;
- chat template presence;
- file consistency where possible.

### 6.6 `InstalledModelRegistry`

Stores verified installation state.

### 6.7 `ModelLifecycleJournal`

Records recoverable operations across crashes or process termination.

### 6.8 `LicenseAcceptanceStore`

Records user/project acceptance of applicable model licenses where required.

---

## 7. Availability Policy

The application must use an explicit policy.

```dart
enum ModelAvailabilityPolicy {
  neverDownload,
  requireInstalled,
  downloadIfMissing,
  importIfAvailable,
}
```

### 7.1 `neverDownload`

- never performs network access;
- returns current state;
- suitable for standard tests and offline mode.

### 7.2 `requireInstalled`

- succeeds only when a verified managed installation exists;
- does not download;
- suitable for real-model tests with preinstalled artifacts.

### 7.3 `downloadIfMissing`

- downloads only after explicit application/user policy allows it;
- never activates an unverified artifact.

### 7.4 `importIfAvailable`

- attempts to match a supplied local artifact;
- does not silently scan arbitrary user directories.

### 7.5 Default policy

Default for automated test suites:

```text
neverDownload
```

Default for production first-run setup may be:

```text
downloadIfMissing
```

but only after explicit user confirmation and storage preflight.

---

## 8. Lifecycle State Machine

### 8.1 Artifact states

```dart
enum ModelArtifactState {
  absent,
  resolving,
  awaitingConsent,
  awaitingLicenseAcceptance,
  preflighting,
  downloading,
  paused,
  staging,
  verifying,
  inspecting,
  installing,
  installedInactive,
  activating,
  active,
  updating,
  rollbackAvailable,
  rollingBack,
  repairing,
  quarantined,
  removing,
  failed,
}
```

### 8.2 State meaning

| State | Meaning |
|---|---|
| `absent` | No verified managed artifact exists. |
| `resolving` | Manifest and compatibility resolution is active. |
| `awaitingConsent` | User approval is required for transfer/import. |
| `awaitingLicenseAcceptance` | License acceptance is required. |
| `preflighting` | Storage, permissions, source and compatibility are checked. |
| `downloading` | Artifact bytes are being transferred. |
| `paused` | Resumable transfer is intentionally suspended. |
| `staging` | Artifact exists only in temporary managed storage. |
| `verifying` | Size and digest verification is active. |
| `inspecting` | Format and metadata checks are active. |
| `installing` | Verified staging bytes are being committed atomically. |
| `installedInactive` | Verified installation exists but is not selected. |
| `activating` | Registry/execution-plan activation is in progress. |
| `active` | Variant is the selected managed artifact for a logical role. |
| `updating` | A replacement variant is being installed side by side. |
| `rollbackAvailable` | Previous verified variant is retained. |
| `rollingBack` | Previous variant is being reactivated. |
| `repairing` | Missing or corrupt managed state is being reconstructed. |
| `quarantined` | Artifact is preserved but prohibited from loading. |
| `removing` | Managed bytes and registry entries are being removed. |
| `failed` | Operation failed with typed recovery information. |

### 8.3 State rules

- `active` implies installed, verified and registry-backed.
- `downloading` never implies installed.
- `staging` artifacts are never loadable.
- `quarantined` artifacts are never automatically loadable.
- `failed` does not delete verified rollback candidates.
- external bindings do not enter this managed state machine.
- runtime `modelReady` state is separate from lifecycle `active`.

---

## 9. Installation Operation Model

### 9.1 Operation identity

Every mutating lifecycle operation has:

```dart
class ModelLifecycleOperationId {
  final String value;
}
```

The operation ID correlates:

- journal entries;
- temporary files;
- progress events;
- registry transactions;
- logs;
- recovery.

### 9.2 Installation request

```dart
@immutable
class ModelInstallRequest {
  final ModelLifecycleOperationId operationId;
  final String logicalModelId;
  final String variantId;
  final ModelAvailabilityPolicy policy;
  final bool allowMeteredNetwork;
  final bool allowBackgroundTransfer;
  final bool retainRollbackCandidate;
  final bool activateAfterInstall;
}
```

### 9.3 Installation result

```dart
@immutable
class ModelInstallationResult {
  final String variantId;
  final ModelInstallationDisposition disposition;
  final InstalledModelRecord? installedRecord;
  final bool activated;
  final List<ModelLifecycleWarning> warnings;
}
```

Possible dispositions:

```text
alreadyInstalled
downloadedAndInstalled
importedAndInstalled
repaired
externalBinding
cancelled
failed
```

---

## 10. Preflight

Before download or import, A.U.R.A. must validate:

```text
manifest validity
variant enabled/release state
platform compatibility
runtime compatibility
hardware hard requirements
license state
source trust
network policy
available storage
staging storage
rollback storage requirement
write permissions
duplicate active operation
```

### 10.1 Storage requirement

Required free space must account for:

```text
downloaded artifact
partial/staging artifact
verification overhead
side-by-side previous version
filesystem safety margin
```

Minimum recommendation:

```text
required free space =
new artifact size
+ staging allowance
+ rollback retention
+ fixed safety margin
```

The exact formula is finalized by platform distribution specifications.

### 10.2 Preflight failure

Preflight must fail before network transfer whenever possible.

Examples:

```text
insufficientStorage
licenseNotAccepted
unsupportedPlatform
runtimeIncompatible
sourceUntrusted
operationAlreadyActive
```

---

## 11. License Acceptance

### 11.1 Project acceptance

Production manifest variants require:

```text
license.accepted_by_project == true
```

### 11.2 User acceptance

If a license requires end-user acceptance, the lifecycle pauses at:

```text
awaitingLicenseAcceptance
```

Acceptance record includes:

```text
license identity
license version/hash
variant ID
accepted timestamp
application version
user scope
```

### 11.3 Change detection

A changed license hash requires new acceptance where legally required.

### 11.4 Offline mode

License text needed for installation must be packaged or cached so offline import can complete without network access.

---

## 12. Download Lifecycle

### 12.1 Download path

```text
manifest source
    |
    v
trusted source adapter
    |
    v
temporary partial file
    |
    v
completed staging file
    |
    v
verification
```

### 12.2 Partial naming

Recommended convention:

```text
<content-id>.partial
<content-id>.partial.meta.json
```

The partial metadata includes:

```text
operation ID
source identity
expected size
expected SHA-256
bytes completed
ETag/Last-Modified where applicable
resume support
created/updated timestamps
```

### 12.3 Resume

Resume is allowed only when:

- source supports byte ranges;
- immutable source identity is unchanged;
- local partial metadata matches the manifest;
- server response confirms compatible resource identity;
- existing partial size is within expected bounds.

Otherwise the partial file is discarded or quarantined.

### 12.4 Redirects

Redirect handling must enforce trusted host policy.

### 12.5 Progress

Progress events include:

```text
bytes transferred
expected bytes
transfer rate
estimated remaining time
state
```

Estimated time is advisory.

### 12.6 Cancellation

Cancellation:

- stops network activity;
- preserves resumable partial state if policy allows;
- records journal state;
- does not create an installed registry record.

### 12.7 Failure

Network failure may preserve resumable partial state.

Integrity mismatch must not preserve the completed artifact as resumable trusted content; it must be deleted or quarantined.

---

## 13. Staging

### 13.1 Purpose

Staging ensures incomplete or unverified bytes never enter active managed storage.

### 13.2 Staging requirements

- staging is within a managed area;
- filenames are generated from trusted IDs, not raw remote names;
- staging and final installation should use the same filesystem when atomic rename is required;
- staging metadata identifies the operation;
- no runtime may load from staging;
- stale staging entries are recoverable.

### 13.3 Staging layout

Conceptual:

```text
Models/
  staging/
    <operation-id>/
      artifact.partial
      artifact.complete
      operation.json
```

Platform-specific paths are not part of the core contract.

---

## 14. Integrity Verification

### 14.1 Verification order

```text
1. final byte count
2. SHA-256
3. content ID
4. format/header inspection
5. architecture/quantization checks
6. optional signature/provenance checks
```

### 14.2 Size mismatch

Any mismatch fails with:

```text
artifactSizeMismatch
```

### 14.3 SHA-256 mismatch

Any mismatch fails with:

```text
artifactIntegrityMismatch
```

The artifact must not be installed.

### 14.4 Hashing behavior

- hashing must stream bytes;
- hashing must not load a multi-gigabyte model into memory;
- progress should be reported;
- cancellation may be supported;
- verified digest is persisted in the registry.

### 14.5 Reverification

Reverification is required when:

- registry state is missing;
- file modification time/size changed unexpectedly;
- repair is requested;
- application detects an abnormal shutdown during update;
- model load reports format corruption;
- support diagnostics explicitly request deep verification.

Routine startup may use a faster trust policy if registry, size, immutable storage metadata and journal are consistent.

---

## 15. Model Inspection

### 15.1 Required inspection

For GGUF:

- valid GGUF magic;
- supported GGUF version;
- expected architecture;
- expected quantization where identifiable;
- non-truncated metadata;
- compatible tensor metadata;
- expected chat template policy where required.

### 15.2 Inspection result

```dart
@immutable
class ModelInspectionResult {
  final String format;
  final int? formatVersion;
  final String? architecture;
  final String? quantization;
  final String? embeddedChatTemplateId;
  final Map<String, Object?> metadata;
  final List<ModelLifecycleWarning> warnings;
}
```

### 15.3 Mismatch policy

A mismatch between manifest and inspected metadata fails installation unless the field is explicitly advisory.

---

## 16. Atomic Installation

### 16.1 Installation sequence

```text
verified staging artifact
      |
      v
allocate final content-addressed location
      |
      v
atomic move/copy-finalize
      |
      v
fsync/flush where supported
      |
      v
write registry transaction
      |
      v
mark installedInactive
      |
      v
optional activation
```

### 16.2 Content-addressed storage

Recommended layout:

```text
Models/
  objects/
    sha256/
      ab/
        <full-digest>.gguf
```

Benefits:

- deduplication;
- immutable identity;
- safe side-by-side variants;
- rollback;
- shared bytes across logical roles.

### 16.3 Atomicity boundary

The file commit and registry update cannot always be one filesystem transaction.

The journal must allow recovery from:

```text
file committed, registry not updated
registry updated, activation not completed
activation switched, old rollback flag not recorded
```

### 16.4 Existing identical content

If content ID already exists and verifies:

- do not duplicate bytes;
- create or update logical installation references;
- preserve existing active references.

---

## 17. Installed-Model Registry

### 17.1 Registry responsibilities

The registry stores:

- installed variants;
- content objects;
- logical bindings;
- active selection;
- verification state;
- rollback candidates;
- source provenance;
- external binding sessions only in transient memory, not as managed installs.

### 17.2 Conceptual schema

```json
{
  "schema_version": "1.0.0",
  "registry_revision": 42,
  "updated_at": "2026-07-20T00:00:00Z",
  "content_objects": [
    {
      "content_id": "sha256:...",
      "storage_uri": "managed://models/objects/sha256/...",
      "size_bytes": 0,
      "sha256": "...",
      "verification_status": "verified",
      "verified_at": "2026-07-20T00:00:00Z",
      "reference_count": 1
    }
  ],
  "installations": [
    {
      "variant_id": "aura.evaluator.primary.example.q4_k_m.win-x64",
      "logical_model_ids": ["aura.evaluator.primary"],
      "content_id": "sha256:...",
      "manifest_id": "aura.models.stable",
      "manifest_version": "1.0.0",
      "source_type": "download",
      "installed_at": "2026-07-20T00:00:00Z",
      "active": true,
      "rollback_candidate": false,
      "pinned_by_user": false
    }
  ]
}
```

### 17.3 Registry writes

- atomic replace;
- monotonic `registry_revision`;
- backup of previous valid registry;
- schema validation before activation;
- no partial JSON writes;
- recovery from backup or content scan.

### 17.4 Registry trust

A registry entry does not override checksum verification.

If registry and file disagree, the file is treated as unverified.

---

## 18. Activation

### 18.1 Meaning

Activation selects the installed variant for a logical model binding.

It does not necessarily load the model into memory.

### 18.2 Activation request

```dart
class ModelActivationRequest {
  final String logicalModelId;
  final String variantId;
  final bool retainPreviousForRollback;
}
```

### 18.3 Activation rules

- target installation must be verified;
- target must satisfy manifest/runtime/hardware compatibility;
- current runtime handles for the old variant must be unloaded or transitioned according to execution-plan policy;
- registry switch is atomic;
- previous active variant becomes rollback candidate when requested;
- activation emits an event.

### 18.4 Multi-role shared model

One content object may be active for multiple logical roles.

Reference counting and rollback must preserve shared usage.

---

## 19. Runtime Loading Boundary

The lifecycle produces:

```text
ResolvedModelArtifact
```

Only after:

- installation is verified;
- registry entry is valid;
- variant is compatible;
- storage URI is resolved by the platform;
- activation/execution-plan policy permits use.

`InferenceRuntime.loadModel()` does not:

- download;
- repair;
- update registry;
- accept unverified staging paths.

A runtime load failure may trigger lifecycle repair only through orchestration above both components.

---

## 20. Update Lifecycle

### 20.1 Update flow

```text
resolve newer manifest variant
      |
      v
preflight
      |
      v
download/import to staging
      |
      v
verify and inspect
      |
      v
install side by side
      |
      v
native/runtime smoke validation
      |
      v
activate new variant
      |
      v
retain previous rollback candidate
```

### 20.2 No in-place overwrite

Managed model updates must not overwrite the currently active artifact in place.

### 20.3 Update policy

```dart
enum ModelUpdatePolicy {
  manual,
  notifyOnly,
  automaticWhenIdle,
  securityOnly,
}
```

Initial production recommendation:

```text
manual or notifyOnly
```

### 20.4 Smoke validation

Before activation, the update should validate:

- runtime can open/load the artifact;
- minimal generation succeeds;
- Evaluator structured response baseline succeeds where applicable;
- Actor response sanitation baseline succeeds where applicable.

The exact real-model validation policy belongs to test/release specifications.

### 20.5 Failure

If update validation fails:

- current active model remains unchanged;
- new artifact becomes quarantined or installedInactive;
- diagnostics are recorded;
- no gameplay migration occurs.

---

## 21. Rollback

### 21.1 Preconditions

Rollback candidate must be:

- installed;
- verified or reverified;
- runtime-compatible;
- not revoked by hard policy;
- retained in registry.

### 21.2 Flow

```text
stop accepting new inference requests
      |
      v
unload affected handles
      |
      v
activate previous registry binding
      |
      v
rebuild ModelExecutionPlan
      |
      v
load previous model when needed
      |
      v
resume
```

### 21.3 Failure handling

If rollback load fails:

- lifecycle remains consistent;
- runtime enters degraded/fallback setup flow;
- deterministic Evaluator or other fallback may be selected by application policy;
- no invalid registry state is committed.

---

## 22. Repair

### 22.1 Repair triggers

- missing file;
- checksum mismatch;
- invalid registry;
- incomplete update journal;
- model-load corruption;
- user-selected repair;
- installer repair;
- stale content references.

### 22.2 Repair strategies

```text
rebuild registry from verified objects
reverify content
restore from rollback object
redownload exact artifact
reimport user-provided artifact
remove stale reference
quarantine suspicious bytes
```

### 22.3 Repair policy

Repair must not silently replace an artifact with a newer variant.

It restores the exact declared content identity unless the user chooses update.

---

## 23. Offline Import

### 23.1 Import request

```dart
class ModelImportRequest {
  final Uri sourceUri;
  final String? expectedVariantId;
  final bool copyIntoManagedStore;
  final bool activateAfterImport;
}
```

### 23.2 Flow

```text
user selects source
      |
      v
read access validation
      |
      v
size and SHA-256
      |
      v
manifest exact match
      |
      v
GGUF inspection
      |
      v
license check
      |
      v
copy/adopt into staging
      |
      v
atomic installation
```

### 23.3 Copy versus adopt

Recommended production behavior:

```text
copy into managed store
```

Directly adopting an arbitrary external path is discouraged because:

- removable media may disappear;
- permissions may change;
- user may overwrite the file;
- Android URI grants may expire;
- repair and rollback become unreliable.

### 23.4 Unrecognized import

An unrecognized artifact may be available only in explicit developer mode.

It must be labeled:

```text
unverified
unsupported
externally owned
```

It must not become a stable automatic selection.

---

## 24. External Binding Lifecycle

### 24.1 Purpose

External binding preserves current LM Studio development behavior during migration.

### 24.2 Flow

```text
load development manifest
      |
      v
discover external server models
      |
      v
match accepted_server_model_ids
      |
      v
create transient logical binding
      |
      v
create session-scoped ModelHandle
```

### 24.3 Rules

- no model download;
- no managed staging;
- no checksum verification of server-owned bytes;
- no installed registry entry;
- no rollback artifact;
- no garbage collection responsibility;
- availability ends when the external session ends;
- production profiles cannot select it implicitly;
- UI must label it as externally managed development runtime;
- `ModelAvailability` must distinguish it from `installedVerified`.

### 24.4 Availability disposition

Recommended enum value:

```text
externalAvailable
```

---

## 25. Removal

### 25.1 Removal request

```dart
class ModelRemovalRequest {
  final String variantId;
  final bool removeContentWhenUnreferenced;
  final bool removeRollbackCandidate;
  final bool force;
}
```

### 25.2 Rules

- active variants cannot be removed without selecting a replacement or fallback;
- loaded model handles must be released;
- shared content objects remain while referenced;
- user-pinned artifacts require explicit confirmation;
- rollback candidates are preserved unless explicitly removed;
- registry changes occur before physical garbage collection only if recovery is guaranteed.

### 25.3 Uninstall interaction

Application uninstall may offer:

```text
keep models
remove managed models
keep rollback cache
remove all managed data
```

The installer specification defines UI and default choices.

---

## 26. Garbage Collection

### 26.1 Eligible content

Content is eligible only when:

- reference count is zero;
- not active;
- not rollback candidate;
- not user-pinned;
- not part of an active operation;
- not required by repair journal;
- retention period expired.

### 26.2 Policy

```dart
class ModelGarbageCollectionPolicy {
  final Duration minimumUnusedAge;
  final int? targetFreeBytes;
  final bool includeQuarantine;
  final bool includeRollbackCandidates;
}
```

### 26.3 Quarantine

Quarantined content has a separate retention policy.

Security-sensitive revoked artifacts may require immediate removal after diagnostics are captured.

---

## 27. Lifecycle Journal

### 27.1 Purpose

The journal makes mutating operations recoverable.

### 27.2 Entry shape

```json
{
  "operation_id": "uuid",
  "operation_type": "install",
  "variant_id": "aura.actor.primary.example",
  "state": "verifying",
  "started_at": "2026-07-20T00:00:00Z",
  "updated_at": "2026-07-20T00:01:00Z",
  "staging_uri": "managed://models/staging/...",
  "expected_content_id": "sha256:...",
  "previous_active_variant_id": null
}
```

### 27.3 Recovery

At startup:

```text
read journal
validate referenced files
resume safe operations
rollback incomplete activation
remove stale temporary state
surface unrecoverable operations
```

### 27.4 Journal durability

Journal updates must be atomic and sufficiently durable for application crash recovery.

---

## 28. Concurrency and Locking

### 28.1 Lock scope

The lifecycle requires locks for:

```text
registry writes
content-object commit
variant installation
logical-model activation
garbage collection
repair
```

### 28.2 Lock identities

Recommended:

```text
global registry lock
content:<content-id>
variant:<variant-id>
logical:<logical-model-id>
```

### 28.3 Multiple application instances

Two A.U.R.A. processes must not mutate the same managed model store concurrently without inter-process coordination.

Initial Windows policy may reject a second mutating instance.

### 28.4 Read operations

Read-only availability checks may proceed concurrently when consistent snapshots are available.

---

## 29. Events and Progress

Required lifecycle events:

```text
ModelResolutionStarted
ModelConsentRequired
ModelLicenseRequired
ModelPreflightStarted
ModelDownloadStarted
ModelDownloadProgress
ModelDownloadPaused
ModelDownloadResumed
ModelDownloadCancelled
ModelVerificationStarted
ModelVerificationProgress
ModelVerificationFailed
ModelInspectionCompleted
ModelInstallStarted
ModelInstallCompleted
ModelActivationStarted
ModelActivated
ModelUpdateAvailable
ModelUpdateStarted
ModelUpdateFailed
ModelRollbackStarted
ModelRollbackCompleted
ModelRepairStarted
ModelRepairCompleted
ModelQuarantined
ModelRemoved
ModelGarbageCollectionCompleted
```

Events must include:

```text
operation ID
logical model ID
variant ID
timestamp
state
typed failure/warning where applicable
```

---

## 30. Failure Model

Recommended failure codes:

```dart
enum ModelLifecycleFailureCode {
  manifestUnavailable,
  manifestInvalid,
  variantUnknown,
  variantDisabled,
  variantRevoked,
  unsupportedPlatform,
  runtimeIncompatible,
  hardwareIncompatible,
  licenseNotAccepted,
  consentRequired,
  sourceUntrusted,
  networkUnavailable,
  downloadFailed,
  downloadCancelled,
  resumeRejected,
  insufficientStorage,
  permissionDenied,
  artifactSizeMismatch,
  artifactIntegrityMismatch,
  artifactFormatInvalid,
  artifactMetadataMismatch,
  stagingFailed,
  installationFailed,
  registryCorrupted,
  registryWriteFailed,
  activationFailed,
  modelInUse,
  rollbackUnavailable,
  rollbackFailed,
  repairFailed,
  importNotMatched,
  externalBindingUnavailable,
  operationAlreadyActive,
  operationRecoveryFailed,
  removalFailed,
  garbageCollectionFailed,
  unknown,
}
```

Every failure must include:

- recoverability;
- suggested recovery action;
- diagnostics;
- operation ID;
- affected variant/logical ID.

---

## 31. Windows Requirements

### 31.1 Installed mode

Managed models should live outside the application binary directory.

Conceptual:

```text
%LOCALAPPDATA%\AURA\Models\
```

### 31.2 Portable mode

Portable behavior must be explicit.

Options include:

```text
portable-local model store beside executable
or
shared user-profile model store
```

The selected policy must preserve:

- write permissions;
- free-space checks;
- update/rollback;
- uninstall expectations.

### 31.3 Filesystem considerations

- antivirus may lock large files;
- atomic rename may fail temporarily;
- long paths must be handled;
- filesystem case behavior must not affect IDs;
- partial downloads must survive app restarts;
- installed models must not be embedded in the main EXE installer by default.

---

## 32. Android Requirements

### 32.1 Storage

Android implementation must support:

- app-private managed storage;
- imported URI through `ContentResolver`;
- persisted read grants where available;
- copy into managed private storage;
- limited free-space conditions;
- app uninstall semantics.

### 32.2 Downloads

Large user-initiated downloads require:

- explicit consent;
- foreground/user-initiated transfer strategy as appropriate;
- resumability;
- lifecycle-aware progress;
- no inference on the main thread.

### 32.3 Process lifecycle

Android may terminate the application.

Journal and registry recovery must not assume continuous process lifetime.

### 32.4 Shared model plans

Lifecycle must support a single installed model satisfying both Evaluator and Actor logical roles.

---

## 33. Security Requirements

### 33.1 Managed path safety

- no manifest-controlled absolute paths;
- no path traversal;
- no shell interpolation;
- generated storage names derive from validated IDs/content digests;
- symlink/reparse-point handling must be defined per platform.

### 33.2 TOCTOU protection

Between verification and installation/loading:

- use managed immutable locations;
- prevent untrusted replacement;
- reopen/verify metadata where platform semantics require it;
- avoid loading directly from user-controlled mutable paths.

### 33.3 Quarantine

Integrity or metadata mismatch moves content to quarantine only when diagnostics justify retaining it.

Quarantine content is never loaded.

### 33.4 Registry tampering

Registry entries are not sufficient trust. Content verification remains authoritative.

### 33.5 Source identity

Resume and update operations must verify immutable source identity.

---

## 34. Observability and Diagnostics

Diagnostics should expose:

```text
logical model ID
variant ID
manifest ID/version
content ID
source type
operation ID
current lifecycle state
bytes downloaded
verification status
inspection metadata
active/rollback state
last failure
storage usage
```

Diagnostics should not expose:

- authentication tokens;
- unrestricted local paths in normal UI;
- model-license personal acceptance details beyond required audit metadata.

---

## 35. Test Strategy Requirements

### 35.1 Unit tests

Use fake/in-memory components for:

```text
state transitions
preflight
resume logic
checksum mismatch
registry transactions
activation
rollback
repair
garbage collection
external binding
```

### 35.2 Filesystem tests

Use temporary directories and tiny fixture files.

### 35.3 Download tests

Use a fake HTTP/source adapter.

No standard test reaches Hugging Face or GitHub.

### 35.4 Integrity fixtures

Create tiny deterministic files with known:

```text
size
SHA-256
content ID
```

### 35.5 Crash-recovery tests

Simulate interruption after:

```text
partial download
completed download before verification
verification before file commit
file commit before registry write
registry write before activation
activation before rollback flag
```

### 35.6 External binding tests

Validate:

- matching server ID;
- unmatched server ID;
- no registry entry;
- transient handle invalidation;
- production profile rejection.

---

## 36. Migration from Current Repository

### Stage 1 — Introduce interfaces and fake implementations

Add:

```text
ModelLifecycleManager
ModelStore
InstalledModelRegistry
ArtifactDownloader
IntegrityVerifier
ModelLifecycleJournal
```

No real download is required initially.

### Stage 2 — Development manifest and external binding

Preserve LM Studio through:

```text
model-manifest.dev.json
ExternalOpenAiRuntime
external_binding
```

Do not create managed registry entries for LM Studio-owned models.

### Stage 3 — Remove model discovery from GameControllerNotifier

Move:

```text
discoverModels()
ModelRouter.resolve()
physical model persistence
```

into bootstrap/model-management services.

### Stage 4 — Introduce managed local fixture model

Validate lifecycle using a tiny pinned artifact.

### Stage 5 — Add real managed GGUF flow

Implement:

```text
download
resume
verify
inspect
install
registry
activation
```

### Stage 6 — Add update, rollback and repair

Only after initial install is stable.

### Stage 7 — Integrate installer/setup UI

Expose progress and recovery without moving lifecycle logic into widgets.

---

## 37. Relationship to App Settings

App settings must not persist provider model IDs.

Persistable user choices include:

```text
preferred quality profile
preferred backend policy
automatic update policy
logical model preference
allow experimental variants
retain rollback models
```

Physical `variant_id` may be stored as a user pin, but must be revalidated against the current manifest.

`storage_uri` and runtime `ModelHandle` must not be stored in general user settings.

---

## 38. Relationship to GameControllerNotifier

`GameControllerNotifier` must not own:

- discovery;
- download;
- registry;
- model resolution;
- activation;
- repair;
- physical model IDs.

It receives an already configured bridge/execution context.

Model setup and lifecycle state belong to application/bootstrap services.

---

## 39. Acceptance Criteria

This specification is approved when all statements are accepted:

```text
- Managed models pass through staging, verification and atomic installation.
- No staging or partial artifact is loadable.
- Catalog state and installed state remain separate.
- The installed registry is atomic, recoverable and not itself a trust root.
- Download resume validates immutable source identity.
- Offline import requires an exact manifest match for managed status.
- Externally owned development bindings bypass managed installation state.
- Updates install side by side and do not overwrite active artifacts.
- Rollback retains a verified previous variant.
- Repair restores exact content identity rather than silently updating.
- Garbage collection respects active, shared, pinned and rollback references.
- Model lifecycle state is separate from runtime load state.
- Windows and Android use the same lifecycle semantics through platform stores.
- Standard tests use fake sources and tiny fixtures with no network access.
- GameControllerNotifier and widgets do not own model lifecycle operations.
```

---

## 40. Exit Criteria for This Document

The document is complete when:

- committed under `docs/phase6/MODEL_LIFECYCLE_SPEC.md`;
- reviewed against the manifest and runtime contracts;
- external binding behavior is unambiguous;
- update/rollback/repair semantics are agreed;
- registry and journal responsibilities are agreed;
- the hardware specification can assume a reliable availability/install state;
- the test strategy can define lifecycle test levels;
- Antigravity can map the current repository to this lifecycle without inventing storage or ownership rules.

---

## 41. Recommended Antigravity Review Prompt

After committing this document:

```text
Read in full:

1. docs/phase6/CROSS_PLATFORM_RUNTIME_ADR.md
2. docs/phase6/INFERENCE_RUNTIME_CONTRACT.md
3. docs/phase6/MODEL_MANIFEST_SPEC.md
4. docs/phase6/MODEL_LIFECYCLE_SPEC.md
5. the previous Phase 6 repository-aware review reports
6. ARCHITECTURE.md
7. AGENTS.md, if present

Perform a repository-aware, read-only review of MODEL_LIFECYCLE_SPEC.md.

Do not modify code or documentation.
Do not implement downloads, storage, registry or runtime changes.
Do not select final production models.

Report:

1. Current repository state
   - existing file/storage helpers;
   - SharedPreferences or configuration persistence;
   - model discovery and routing;
   - application bootstrap;
   - CLI and simulator behavior;
   - tests that touch files, HTTP or model IDs.

2. Lifecycle ownership
   Verify the proposed separation among:
   - ModelLifecycleManager;
   - ArtifactDownloader;
   - ModelStore;
   - IntegrityVerifier;
   - ModelInspector;
   - InstalledModelRegistry;
   - ModelLifecycleJournal;
   - ModelExecutionPlanResolver;
   - InferenceRuntime;
   - UI/bootstrap.

3. State-machine completeness
   Evaluate every lifecycle state and transition:
   - absent;
   - preflight;
   - downloading/paused;
   - staging;
   - verifying;
   - inspecting;
   - installing;
   - active/inactive;
   - updating;
   - rollback;
   - repair;
   - quarantine;
   - removal;
   - failure.

4. Crash consistency
   Analyze recovery after interruption at:
   - partial download;
   - completed download before verification;
   - verification before final commit;
   - file commit before registry update;
   - registry update before activation;
   - activation before rollback state;
   - application termination during cleanup.

5. Windows feasibility
   Evaluate:
   - filesystem paths;
   - atomic rename;
   - antivirus locks;
   - multiple app instances;
   - installed versus portable mode;
   - side-by-side model versions;
   - installer repair/uninstall;
   - multi-gigabyte storage and resume.

6. Android feasibility
   Evaluate:
   - app-private storage;
   - ContentResolver import;
   - URI permissions;
   - copying into managed storage;
   - process termination;
   - resumable user-initiated downloads;
   - uninstall semantics;
   - single shared model plans.

7. External binding
   Verify that LM Studio compatibility:
   - creates no managed registry entry;
   - performs no managed download;
   - remains development-only;
   - still produces a logical session ModelHandle;
   - cannot be confused with a verified installation.

8. Security
   Evaluate:
   - path traversal;
   - symlink/reparse-point risks;
   - TOCTOU between verification and loading;
   - registry tampering;
   - redirect/source identity;
   - quarantine;
   - unrecognized imports.

9. Testability
   Identify:
   - reusable current tests;
   - required fake components;
   - tiny fixture strategy;
   - crash-recovery test cases;
   - risks of accidental network/model use in standard suites.

10. Impact on following documents
    State decisions that must be reflected in:
    - HARDWARE_PROFILE_SPEC.md;
    - TEST_RUNTIME_STRATEGY.md;
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

For every proposed document change specify:
- exact section;
- rationale;
- Windows impact;
- Android impact;
- implementation impact.

Conclude with one judgment:

A. DOCUMENT APPROVABLE WITHOUT CHANGES
B. APPROVABLE WITH NON-BLOCKING CHANGES
C. REQUIRES CHANGES BEFORE HARDWARE_PROFILE_SPEC
D. LIFECYCLE ARCHITECTURE INCOMPATIBLE WITH CURRENT REPOSITORY
```

---

## 42. Final Decision

A.U.R.A. will manage production model artifacts through an explicit, recoverable lifecycle based on trusted manifests, staging, integrity verification, atomic installation, a local installed-model registry, operation journaling, side-by-side updates and rollback.

Externally owned development models remain a separate transient domain and never masquerade as verified managed installations.

The lifecycle guarantees that only compatible, verified and explicitly activated artifacts reach `InferenceRuntime`, while keeping gameplay, runtime execution and platform-specific storage concerns cleanly separated.

---

## 43. Hardware-Aware Provisioning and Managed Model Store Specification

### 43.1 Managed Model Store Directory & Layout

A.U.R.A. operates a strictly managed model store for all production inference artifacts.

#### 43.1.1 Platform-Appropriate Defaults
The model store directory defaults to platform-appropriate locations:
- **Windows:** `%LOCALAPPDATA%\AURA\models`
- **Linux:** `~/.local/share/aura/models`
- **macOS:** `~/Library/Application Support/aura/models`
- **Android:** App-private storage directory (e.g. `/data/user/0/com.aura/app_models`)

#### 43.1.2 Custom Directory Selection
- During initial provisioning (via installer or first-run wizard) or subsequently through App Settings, the user can select a custom model store directory.
- The physical storage path is managed by `ModelStore` and recorded in application preferences and `InstalledModelRegistry`.
- The storage path **must never be encoded** into logical model IDs (`logicalModelId`) or `ModelHandle`s.

#### 43.1.3 Internal Store Directory Layout
```text
<ManagedModelStorePath>/
  ├── registry.json           # Canonical state of installed models
  ├── journal.log             # Operational log for crash recovery
  ├── models/                 # Verified, immutable GGUF artifacts
  │   ├── sha256_<hash_a>.gguf
  │   └── sha256_<hash_b>.gguf
  ├── staging/                # In-progress downloads and imports (.partial files)
  ├── locks/                  # File locks for concurrent process safety
  └── quarantine/             # Corrupted or revoked artifacts
```

### 43.2 Existing Local GGUF Discovery & Classification

When the user requests scanning of existing local directories for GGUF files:

#### 43.2.1 Scanning and Verification
- Filename matching alone is **strictly insufficient** to verify an artifact.
- `ModelInspector` inspects GGUF headers (magic, version, architecture, quantization, context size) and `IntegrityVerifier` calculates/verifies SHA-256 where applicable.

#### 43.2.2 Import vs External Local Binding
Discovered local models are categorized into two explicit domains:

1. **Imported Managed Model (`importedManaged`):**
   - The artifact is copied or moved into `<ManagedModelStorePath>/staging/`, verified against the manifest, and committed to `/models/`.
   - Recorded in `registry.json` as a managed installation.
   - Fully eligible for automated app lifecycle management (updates, repair, garbage collection, uninstallation).

2. **Externally Owned Local Binding (`externalLocal`):**
   - The file remains in the user's external directory and is **never modified or deleted** by A.U.R.A.
   - Registered as a local external binding referencing the external path.
   - Displayed in UI with a distinct "External" indicator.
   - Lifecycle operations (auto-update, repair, managed deletion) are **disabled** for external bindings.

### 43.3 Store Migration Procedure

Changing the managed model store directory from path $A$ to path $B$ follows a transactional, crash-safe procedure:

1. **Preflight Space & Write Check:**
   - `ModelStore` verifies that destination path $B$ has sufficient free storage (total size of managed models $+ 15\%$ safety margin) and valid write permissions.
2. **Operation Pause:**
   - Active generations are completed or paused; new lifecycle operations are locked.
3. **Staging Transfer:**
   - Artifacts are copied from $A$ to $B/\text{staging}/$.
4. **Post-Transfer Verification:**
   - `IntegrityVerifier` computes SHA-256 digests for all transferred files in $B/\text{staging}/$ and matches them against `registry.json`.
5. **Atomic Commit & Path Switch:**
   - Files are moved from $B/\text{staging}/$ to $B/\text{models}/$.
   - `registry.json` is updated with the new base path $B$.
   - Application configuration updates active store pointer to $B$.
6. **Rollback & Recovery:**
   - If any transfer or verification step fails, the operation aborts, files in $B/\text{staging}/$ are cleaned up, and active store remains at $A$.
   - Source directory $A$ is **never deleted** before explicit commit. The user is prompted whether to retain or delete the legacy directory $A$ after successful migration.

### 43.4 Consent and Policy Normative Constraints

1. **Zero Implicit Downloads:**
   - Network downloads of model artifacts **never occur implicitly** or without user authorization.
2. **Explicit Consent Prompting:**
   - Prior to any download, the user must be presented with a clear summary: exact file size, required disk space, Hugging Face / repository source URI, license agreement, and target store path.
3. **Resumable Transfers:**
   - All network transfers use HTTP Range requests writing to `.partial` files under `/staging/`. Downloads can be paused, resumed, or cancelled at any time without corrupting the store.
4. **`ModelAvailabilityPolicy` Enforcement:**
   - Default policy for automated test suites and headless runs is `neverDownload`.
   - Production first-run setup invokes `downloadIfMissing` only after explicit user consent is registered.
