# Phase 6.4f — Runtime Dependency and Model Configuration

**Repository:** `naturewhisp/aura`  
**Target branch:** `fase6`  
**Status:** implementation-ready specification  
**Scope:** Windows application composition, `llama-server` discovery/validation, managed and external model bindings, installer integration, post-install settings and CLI-facing contracts.

---

## 1. Architectural decisions

### 1.1 `llama-server` is an external runtime dependency

`llama-server` is not an A.U.R.A. catalog artifact and does not participate in the model provisioning lifecycle introduced in Phase 6.4d/6.4e.

A.U.R.A. does not own, update, repair, roll back or purge the selected `llama-server` installation. It only:

- detects an existing executable;
- allows the user to select an executable manually;
- validates that the executable can be launched;
- stores the selected path and detected version;
- starts and supervises the process during gameplay;
- exposes actionable diagnostics when the dependency is absent or invalid.

The application must not:

- modify the system `PATH`;
- require administrator privileges solely for `llama-server`;
- install a permanent Windows service;
- silently download or replace an executable;
- treat the executable as a managed `InstalledArtifactDescriptor`;
- register it in `InstallationRecord` or `ActivationState`.

### 1.2 Models have two supported storage modes

A.U.R.A. supports:

1. **Managed models** — provisioned, imported, verified and stored through the Phase 6.4d/6.4e infrastructure.
2. **External unmanaged models** — GGUF files referenced directly from a user-controlled path.

External unmanaged files are never copied, modified, repaired, updated or physically deleted unless the user explicitly chooses to import them into the managed store.

### 1.3 Configuration is not installer-only

Runtime and model configuration must be available through the same application service from:

- the Windows installer or first-run setup;
- the post-install application settings;
- the CLI introduced in Phase 6.4f;
- application bootstrap and preflight diagnostics.

The installer and settings UI must not contain independent persistence or validation logic.

---

## 2. `llama-server` discovery and validation

### 2.1 Discovery order

The default discovery policy is deterministic:

1. persisted user-selected executable path;
2. application-local executable, when an optional portable bundle provides one;
3. executable discoverable through the current process `PATH`;
4. not found.

The implementation must not recursively scan arbitrary disks or user directories.

### 2.2 Assisted installation

When `llama-server` is missing, the installer and settings page expose:

- **Install with supported package manager**, only when a verified package identifier and package manager are available;
- **Open official download page**;
- **Select existing executable**;
- **Continue without configuring runtime**, when installation is allowed to complete without immediate gameplay readiness.

WinGet is an optional adapter, not a hard dependency. Package identifiers and command lines must be isolated in the Windows infrastructure layer and covered by tests. Failure of WinGet must fall back to manual guidance rather than fail the A.U.R.A. installation.

### 2.3 Validation contract

Validation checks are operational, not catalog-based:

- path is absolute;
- file exists and is readable;
- file is a regular executable candidate;
- process can be started without shell interpolation;
- `--version` is attempted first, then `--help` as a compatibility fallback;
- process exits or is terminated within a bounded timeout;
- stdout/stderr are captured and sanitized;
- detected version and capabilities are persisted when available.

A filename different from `llama-server.exe` may be accepted when the validation probe succeeds.

### 2.4 Runtime configuration model

```dart
final class LlamaServerConfiguration {
  final String executablePath;
  final String? detectedVersion;
  final DateTime? lastValidatedAtUtc;
  final LlamaServerValidationStatus validationStatus;
}
```

```dart
enum LlamaServerValidationStatus {
  unknown,
  valid,
  missing,
  notExecutable,
  probeFailed,
  incompatible,
}
```

### 2.5 Application service

```dart
abstract interface class LlamaServerDependencyService {
  Future<LlamaServerDetectionResult> detect();

  Future<LlamaServerValidationResult> validateExecutable({
    required String executablePath,
  });

  Future<LlamaServerConfiguration> configureExecutable({
    required String executablePath,
  });

  Future<void> clearConfiguration();

  Future<LlamaServerConfiguration?> readConfiguration();
}
```

Process startup and supervision remain responsibilities of the Windows inference runtime adapter, which consumes the validated configuration.

---

## 3. Model binding contract

### 3.1 Binding targets

```dart
sealed class ConfiguredModelReference {
  const ConfiguredModelReference();
}

final class ManagedModelReference extends ConfiguredModelReference {
  final String installationId;

  const ManagedModelReference({required this.installationId});
}

final class ExternalModelReference extends ConfiguredModelReference {
  final String absolutePath;

  const ExternalModelReference({required this.absolutePath});
}
```

Bindings are maintained independently for actor and evaluator. The same target may be assigned to both roles.

```dart
final class ModelRoleConfiguration {
  final ConfiguredModelReference? actor;
  final ConfiguredModelReference? evaluator;
}
```

### 3.2 External model rules

External model selection bypasses trust and catalog checks, including:

- catalog membership;
- known SHA-256;
- catalog signature;
- declared license;
- known quantization;
- version/build metadata;
- automatic hardware suitability assessment;
- automatic update, repair and rollback.

The following minimum technical checks remain mandatory:

- absolute path;
- file exists;
- file is readable;
- file is not a directory;
- non-zero file size;
- no path traversal or malformed path;
- preflight load can be attempted through the configured runtime.

A lightweight GGUF header check may generate a warning, but the authoritative operational check is the bounded `llama-server` preflight load.

### 3.3 Informed consent

Before the first external unmanaged model is saved, the user must explicitly accept a concise disclaimer:

> Il modello selezionato non è verificato né gestito da A.U.R.A. Provenienza, integrità, licenza, compatibilità e requisiti hardware restano responsabilità dell'utente. A.U.R.A. non modificherà né eliminerà il file originale e non potrà garantirne aggiornamento, riparazione o rollback automatici.

Persisted consent is intentionally minimal:

```dart
final class ExternalModelConsent {
  final int consentVersion;
  final DateTime acceptedAtUtc;
}
```

Consent is requested again only when the disclaimer version changes or consent is explicitly revoked.

### 3.4 External model lifecycle

| Operation | External unmanaged model |
|---|---|
| Select and bind | Supported |
| Assign to actor/evaluator | Supported |
| Use same file for both roles | Supported |
| Runtime preflight | Supported |
| Remove binding | Supported |
| Import into managed store | Supported as an explicit separate action |
| Automatic update | Not supported |
| Repair | Not supported |
| Managed rollback | Not supported |
| Physical purge | Never permitted |

Removing an external model configuration removes only the reference. It must never delete the user's file.

---

## 4. Model configuration service

```dart
abstract interface class ModelConfigurationService {
  Future<ModelRoleConfiguration> readConfiguration();

  Future<ModelBindingValidationResult> validateReference({
    required ConfiguredModelReference reference,
    required ModelActivationRole role,
  });

  Future<ModelRoleConfiguration> configureRole({
    required ModelActivationRole role,
    required ConfiguredModelReference reference,
    ExternalModelConsent? consent,
  });

  Future<ModelRoleConfiguration> clearRole({
    required ModelActivationRole role,
  });

  Future<List<ExternalModelCandidate>> scanExternalDirectory({
    required String directoryPath,
  });
}
```

The directory scan is a user-initiated convenience operation. It:

- scans only the selected directory;
- does not recursively traverse by default;
- lists plausible `.gguf` files;
- does not import or hash complete multi-gigabyte files;
- does not persist a binding until a specific file is selected.

The selected binding always stores the absolute file path, not just the parent directory.

---

## 5. Installer and first-run setup

### 5.1 Runtime page

The installer or first-run setup shows:

- detected executable path;
- detected version or validation status;
- **Verify**;
- **Select executable**;
- **Install with WinGet**, only when supported;
- **Open official download page**;
- **Configure later**.

The installer may finish with an unconfigured runtime, but it must clearly report that local inference is not ready.

### 5.2 Models page

The user can independently configure actor and evaluator through:

- an installed managed model;
- a direct external GGUF file;
- a GGUF selected from a user-selected directory;
- no model yet, when deferred configuration is allowed.

The installer must support the same file for actor and evaluator.

External files require informed consent but do not require catalog matching or import.

### 5.3 Idempotency

Re-running setup must preserve existing valid choices unless the user changes them. Upgrade and repair operations must not silently reset:

- the selected `llama-server` path;
- actor/evaluator bindings;
- external model directories;
- external-model consent.

---

## 6. Post-install settings

A dedicated **Runtime e modelli** settings page exposes the same capabilities after installation.

### 6.1 Runtime section

- current executable path;
- detected version;
- last validation timestamp;
- current validation status;
- verify again;
- choose another executable;
- open official download page;
- clear configuration.

### 6.2 Actor and evaluator sections

Each role supports:

- list/select managed installations;
- select an external GGUF;
- scan a selected directory;
- switch between managed and external reference;
- test model loading;
- remove binding;
- import the selected external file into the managed store as a separate action.

Configuration changes that affect a running session are either rejected with a typed conflict or applied only after the current runtime session is stopped.

---

## 7. Preflight and startup

Before starting a local inference session, the application performs:

1. valid `llama-server` configuration;
2. actor binding present and resolvable;
3. evaluator binding present when the selected execution plan requires one;
4. managed installation still verified, or external file still readable;
5. selected port available;
6. bounded process startup and health probe;
7. model load result mapped to typed diagnostics.

Preflight must not modify external files.

Suggested result taxonomy:

```dart
enum LocalInferencePreflightFailure {
  runtimeNotConfigured,
  runtimeMissing,
  runtimeInvalid,
  actorNotConfigured,
  evaluatorNotConfigured,
  managedInstallationUnavailable,
  externalModelMissing,
  externalModelUnreadable,
  portUnavailable,
  runtimeStartupFailed,
  modelLoadFailed,
}
```

---

## 8. Phase 6.4f implementation scope

Phase 6.4f must deliver:

- `LlamaServerDependencyService` and Windows implementation;
- persisted runtime dependency configuration;
- safe process probe with timeout and sanitized diagnostics;
- `ConfiguredModelReference` sealed model;
- persisted actor/evaluator role configuration;
- external directory scan and direct file selection contracts;
- informed-consent persistence;
- preflight service;
- installer/first-run-facing facade;
- settings-facing facade using the same services;
- CLI commands for detection, validation and role binding;
- public exports limited to application-facing DTOs and services;
- unit and integration tests without mandatory real-model downloads.

Phase 6.4f does not implement:

- WinGet package ownership or upgrade management;
- automatic updates of `llama-server`;
- physical deletion of external models;
- catalog registration of external models;
- repair or rollback of external models;
- recursive whole-disk model discovery;
- Android runtime installation.

---

## 9. Required tests

At minimum:

- persisted runtime path has discovery precedence;
- invalid persisted path falls through to other detection strategies;
- manual executable validation success/failure/timeout;
- package-manager absence does not block manual configuration;
- actor and evaluator can use different bindings;
- actor and evaluator can use the same binding;
- managed and external bindings can coexist;
- external model requires current consent version;
- external binding rejects missing/unreadable files;
- clearing an external binding does not delete the source file;
- directory scan is non-recursive by default;
- installer and settings use the same persistence service;
- upgrade preserves existing configuration;
- preflight maps runtime and model failures to typed diagnostics;
- no standard test downloads or loads a production GGUF;
- optional on-demand smoke test validates a real `llama-server` executable and GGUF.

---

## 10. Acceptance criteria

Phase 6.4f is complete when:

- A.U.R.A. can detect, validate and persist an external `llama-server` executable;
- absence of `llama-server` produces guided, recoverable setup options;
- actor/evaluator can be bound independently to managed or external models;
- the same external model can serve both roles;
- external model use is possible without catalog/trust verification after informed consent;
- external user files are never modified or deleted by lifecycle operations;
- all configuration remains editable after installation;
- installer, settings and CLI share the same application services;
- startup preflight prevents opaque runtime failures;
- standard CI remains network-free and model-free.
