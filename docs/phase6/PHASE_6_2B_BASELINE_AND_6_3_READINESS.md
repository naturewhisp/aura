# Phase 6.2b Baseline & Phase 6.3 Readiness Specification

**Project:** A.U.R.A. — Artificial Unbound Reasoning Arena  
**Target path:** `docs/phase6/PHASE_6_2B_BASELINE_AND_6_3_READINESS.md`  
**Status:** APPROVED  
**Phase:** 6.2c — Runtime Baseline Consolidation & Provisioning Readiness  
**Implementation Baseline:** `a57379fdb092db1fa76d6a0b1c17ce999d67b4ad`  
**Documentation Consolidation Baseline:** `24edc84f88511bf6dca057be37057fcdb0d3ab96`  
**Primary Platform Target:** Windows x64 (managed out-of-process `llama-server.exe`)  
**Secondary Platform Target:** Android arm64 (Phase 7, native in-process)  
**Last Updated:** 2026-07-21  

---

## 1. Executive Summary & Purpose

This document serves as the formal **Consolidation Record** for **Phase 6.2b** and the **Readiness Gate** for **Phase 6.3**.

The primary purpose of Phase 6.2c is to consolidate the implemented runtime architecture, freeze verified contracts, establish strict operational boundaries, and resolve design decisions for model/runtime provisioning before writing code for Phase 6.3.

```text
+-----------------------------------------------------------------------------------+
|                           PHASE 6 BOUNDARY SEPARATION                             |
+-----------------------------------------------------------------------------------+
|                                                                                   |
|  [PHASE 6.2b (COMPLETED & VERIFIED)]                                              |
|  - Managed Out-of-Process Execution (`llama-server.exe`)                          |
|  - Process Ownership, Monitoring, Failure Detection & Cleanup                     |
|  - Dynamic Loopback Port Allocation (`8080` fallback range)                        |
|  - Single Physical Model Loading with Dual Logical Handles (`actor` & `evaluator`) |
|  - Health Probing, Retries, Single-Flight Stop/Dispose & Safety Sanitization      |
|                                                                                   |
|  [PHASE 6.3 (PROVISIONING, MANIFESTS & LIFECYCLE)]                                 |
|  - Artifact Acquisition & Source URI Resolution                                   |
|  - Remote Catalog Manifest Validation & Immutable SHA-256 Hashing                 |
|  - Atomic Staging, Directory Layout Installation & Rollback                       |
|  - Local Installation Records & Active Session State Resolution                    |
|  - Path Resolution (`executablePath`, `modelPath`) for Bootstrap                  |
|                                                                                   |
|  [DEFERRED TO FUTURE PHASE]                                                       |
|  - Automated Hardware Capability Profiling & Recommendation Engine                |
|                                                                                   |
+-----------------------------------------------------------------------------------+
```

---

## 2. Phase 6.2b Implemented Baseline & Architectural Invariants

The implementation baseline (`a57379fdb092db1fa76d6a0b1c17ce999d67b4ad`) introduces the production managed runtime adapter for Windows x64.

### 2.1 Concrete Implemented Components
The concrete implementation resides under `lib/src/agent_runtime/runtime/adapters/managed_llama_server/`:

1. **`ManagedLlamaServerRuntime`**: Implements `InferenceRuntime` for out-of-process `llama-server.exe` sidecars. Manages initialization, logical handle bindings (`aura.actor.primary`, `aura.evaluator.primary`), health status reporting, generation forwarding, and single-flight disposal.
2. **`LlamaServerProcessSupervisor`**: Encapsulates OS process execution, state transitions (`stopped` -> `starting` -> `probing` -> `ready` | `failed`), bounded log tailing, ANSI sanitization, and graceful/forced process termination (`SIGTERM` / `SIGKILL`).
3. **`HttpLlamaServerHealthProbe`**: Performs HTTP `/health` polling to verify sidecar responsiveness and model slot availability.
4. **`LoopbackPortAllocator`**: Dynamically binds available loopback TCP ports (default target `8080`).
5. **`LlamaServerCommandBuilder`**: Constructs CLI flags for `llama-server.exe` (`--model`, `--port`, `--ctx-size`, `--n-gpu-layers`, `--alias`, `--jinja`).
6. **`ManagedFileSystem` / `LocalFileSystem`**: Abstraction layer isolating direct File/Directory I/O for unit testing.
7. **`FakeManagedProcess` & Test Fixtures**: Deterministic mocks enabling offline test suites without launching native processes or binding OS sockets.

### 2.2 Implemented Architectural Invariants
- **Out-of-Process Isolation**: `llama-server.exe` runs as an independent OS child process managed by A.U.R.A. Crash or failure in `llama-server` is trapped by the supervisor exit-code listener without corrupting the host Dart VM state.
- **Shared Physical Model, Dual Logical Bindings**: The managed sidecar loads **one physical GGUF model** into VRAM/RAM under a single alias. The runtime registers multiple logical handles (`aura.actor.primary`, `aura.evaluator.primary`) pointing to that physical alias, permitting both agents to issue requests concurrently without triggering invalid multi-model reload errors.
- **Diagnostic Information Hiding**: Public status objects (`ApplicationRuntimeStatus`) and exception messages omit OS process IDs (PIDs), internal port allocations, and raw stack traces to prevent sensitive information leakage.
- **Idempotent Single-Flight Lifecycle**: Concurrent calls to `stop()` or `dispose()` return identical `Future` instances. If process cleanup fails, state transitions to `failed` and internal completers reset, allowing retry calls.
- **Deterministic Test Synchronization**: Test suites prohibit `Future.delayed` calls. All async flows are driven deterministically via `expectLater`, `pumpEventQueue()`, and `Completer` controls.

---

## 3. Decision Matrix: Status, Scope & Ownership

The following matrix records all design decisions for Phase 6, categorizing each with a formal status (`APPROVED`, `DEFERRED`, `OPEN`, `SUPERSEDED`) and referencing the canonical document that owns the specification.

| Decision ID | Area / Subject | Status | Summary & Resolution | Owning Canonical Spec |
| :--- | :--- | :--- | :--- | :--- |
| **DEC-6.1** | Execution Topology | `APPROVED` | Windows x64 sidecar runs **managed out-of-process** (`llama-server.exe`). Android runs **native in-process** (Phase 7). | [CROSS_PLATFORM_RUNTIME_ADR.md](CROSS_PLATFORM_RUNTIME_ADR.md) |
| **DEC-6.2** | Physical Model Sharing | `APPROVED` | Single physical GGUF loaded per sidecar instance; logical handles map to the shared alias. | [INFERENCE_RUNTIME_CONTRACT.md](INFERENCE_RUNTIME_CONTRACT.md) |
| **DEC-6.3** | Hardware Profiling & Recommendation | `DEFERRED` | Hardware auto-detection & recommendation engine is deferred to a dedicated post-6.3 phase. Phase 6.3 consumes explicit configuration. | [HARDWARE_PROFILE_SPEC.md](HARDWARE_PROFILE_SPEC.md) |
| **DEC-6.4** | Manifest Tripartition | `APPROVED` | Separate **Catalog Manifest** (remote/immutable), **Installation Record** (local state), and **Activation State** (current session). | [MODEL_MANIFEST_SPEC.md](MODEL_MANIFEST_SPEC.md) |
| **DEC-6.5** | Directory Layout Ownership | `APPROVED` | `Program Files` owns installer-packaged assets; `%LOCALAPPDATA%\AURA\` owns app-acquired runtimes, models, staging, cache, and state. | [WINDOWS_INSTALLER_AND_UPDATE_SPEC.md](WINDOWS_INSTALLER_AND_UPDATE_SPEC.md) |
| **DEC-6.6** | Runtime Precedence Policy | `APPROVED` | App-acquired runtime in `LocalAppData` overrides installer-provided runtime in `Program Files` if valid and version-compatible. | [WINDOWS_INSTALLER_AND_UPDATE_SPEC.md](WINDOWS_INSTALLER_AND_UPDATE_SPEC.md) |
| **DEC-6.7** | Artifact Retention & Uninstall Policy | `APPROVED` | Uninstaller prompts user whether to preserve or remove user models/data under `LocalAppData`. Staging files are cleaned automatically. | [WINDOWS_INSTALLER_AND_UPDATE_SPEC.md](WINDOWS_INSTALLER_AND_UPDATE_SPEC.md) |
| **DEC-6.8** | Atomic Staging & Rollback | `APPROVED` | Downloads extract to `%LOCALAPPDATA%\AURA\staging\<uuid>\`, SHA-256 verified, then atomically renamed to target directory. | [MODEL_LIFECYCLE_SPEC.md](MODEL_LIFECYCLE_SPEC.md) |
| **DEC-6.9** | Bootstrap Contract Mapping | `APPROVED` | Provisioning resolves paths and outputs `ManagedLlamaServerConfiguration` consumed directly by `DefaultApplicationBootstrap`. | [MODEL_LIFECYCLE_SPEC.md](MODEL_LIFECYCLE_SPEC.md) |
| **DEC-6.10** | Relative Link Constraint | `APPROVED` | All versioned documentation files MUST use relative repository links. Absolute `file:///` and Windows local paths are prohibited in repo files. | [AGENTS.md](../../AGENTS.md) |

---

## 4. Phase 6.3 Target Architecture & Manifest Architecture

Phase 6.3 introduces the **Model & Runtime Provisioning Subsystem**. It is responsible for acquiring, verifying, staging, installing, and resolving paths for binaries and GGUF model files.

```text
+-----------------------------------------------------------------------------------+
|                        PROVISIONING TO BOOTSTRAP PIPELINE                         |
+-----------------------------------------------------------------------------------+
|                                                                                   |
|  [Remote Sources / Bundled Media]                                                 |
|         |                                                                         |
|         v                                                                         |
|  1. Catalog Manifest Validation (SHA-256, Min Runtime Build, Arch)                |
|         |                                                                         |
|         v                                                                         |
|  2. Atomic Download & Extraction to `%LOCALAPPDATA%\AURA\staging\<id>\`           |
|         |                                                                         |
|         v                                                                         |
|  3. Integrity Verification & Atomic Move to `%LOCALAPPDATA%\AURA\models\<id>\`     |
|         |                                                                         |
|         v                                                                         |
|  4. Update `installation_record.json` & Set `active_state.json`                   |
|         |                                                                         |
|         v                                                                         |
|  5. Resolve `executablePath` & `modelPath` -> `ManagedLlamaServerConfiguration`   |
|         |                                                                         |
|         v                                                                         |
|  6. Pass to `DefaultApplicationBootstrap` -> Initialize `ManagedLlamaServerRuntime`|
|                                                                                   |
+-----------------------------------------------------------------------------------+
```

### 4.1 Manifest Architecture Tripartition
To prevent mutating remote catalog files or polluting installation records with runtime session state, Phase 6.3 enforces a three-tier data model detailed in [MODEL_MANIFEST_SPEC.md](MODEL_MANIFEST_SPEC.md):

1. **Catalog Manifest (`catalog_manifest.json`)**: Immutable, remote or bundled document signed or hashed. Defines available models, GGUF variants, quantization levels, file size, SHA-256 hash, minimum required `llama.cpp` build number, and hardware compatibility tags.
2. **Installation Record (`installation_record.json`)**: Local file maintained in `%LOCALAPPDATA%\AURA\installation_record.json`. Tracks all downloaded and extracted runtimes and models present on the local machine, their local relative paths, verification timestamp, and disk space usage.
3. **Activation State (`active_state.json`)**: Local file maintained in `%LOCALAPPDATA%\AURA\active_state.json`. Stores the currently selected active runtime build ID, active model ID, user override settings, and fallback preferences for immediate resolution by `ApplicationBootstrap`.

---

## 5. Windows Directory Layout & Ownership Specification

The Windows directory structure separates immutable installer-managed files from mutable app-managed user data, detailed in [WINDOWS_INSTALLER_AND_UPDATE_SPEC.md](WINDOWS_INSTALLER_AND_UPDATE_SPEC.md):

```text
C:\Program Files\AURA\                               [READ-ONLY / INSTALLER OWNED]
├── aura.exe                                         # Primary application binary
├── unins000.exe                                     # Inno Setup uninstaller
└── bundled_runtime\                                 # Optional fallback llama-server
    └── llama-server.exe                             # Baseline sidecar executable

C:\Users\<User>\AppData\Local\AURA\                  [READ-WRITE / APP OWNED]
├── installation_record.json                         # Local inventory of installed assets
├── active_state.json                                # Active runtime & model selection
├── runtimes\                                        # App-acquired llama-server builds
│   └── build-b3500-win-x64\
│       └── llama-server.exe
├── models\                                          # App-acquired GGUF model files
│   └── ministral-3b-instruct-q4_k_m\
│       ├── model.gguf
│       └── model_manifest.json
├── staging\                                         # Transient atomic download workspace
│   └── tmp-staging-4f8a\
├── cache\                                           # HTTP & download chunk cache
└── logs\                                            # Sidecar & application runtime logs
```

### 5.1 Runtime Resolution & Precedence Policy
When `DefaultApplicationBootstrap` resolves `executablePath`:
1. Check `active_state.json` for an active custom or app-acquired runtime build in `%LOCALAPPDATA%\AURA\runtimes\<build_id>\llama-server.exe`. If present, valid, and executable, select it (**Precedence 1**).
2. Fall back to bundled sidecar executable in `C:\Program Files\AURA\bundled_runtime\llama-server.exe` (**Precedence 2**).
3. If neither exists or is executable, fail bootstrap with `ApplicationBootstrapFailure.executableNotFound`.

---

## 6. Phase 6.3 Readiness Checklist & Exit Criteria

Before beginning implementation work for Phase 6.3, the following readiness criteria MUST be met:

- [x] **Zero Code Changes in 6.2c**: Code behavior, Dart classes, and unit tests are unchanged.
- [x] **Implementation Baseline Frozen**: Baseline commit `a57379fdb092db1fa76d6a0b1c17ce999d67b4ad` verified.
- [x] **Canonical Specification Alignment**: `ARCHITECTURE.md`, `CROSS_PLATFORM_RUNTIME_ADR.md`, `INFERENCE_RUNTIME_CONTRACT.md`, `MODEL_LIFECYCLE_SPEC.md`, `MODEL_MANIFEST_SPEC.md`, `TEST_RUNTIME_STRATEGY.md`, `WINDOWS_INSTALLER_AND_UPDATE_SPEC.md`, and `AGENTS.md` updated without contradictions.
- [x] **Single Canonical Source**: No duplicate JSON schemas or conflicting definitions across documents.
- [x] **Relative Link Invariant**: Zero `file:///` links, absolute Windows paths, or local developer paths in repository documentation files.
- [x] **Consistent Terminology**: "Managed out-of-process" used strictly for Windows `llama-server.exe` sidecars; "Native in-process" reserved for Android FFI.
- [x] **Manifest Tripartition Approved**: Catalog Manifest, Installation Record, and Activation State cleanly separated.
- [x] **Windows Directory Ownership Approved**: `Program Files` vs `LocalAppData` ownership, precedence, and uninstall policies formalized.
- [x] **CI Verification Clean**: `tool/run_ci_tests.ps1` executes cleanly without warnings or test failures.

---

## 7. Document References

- [ARCHITECTURE.md](../../ARCHITECTURE.md) — Main Architecture & Phase Overview
- [CROSS_PLATFORM_RUNTIME_ADR.md](CROSS_PLATFORM_RUNTIME_ADR.md) — Cross-Platform Runtime Strategy ADR
- [INFERENCE_RUNTIME_CONTRACT.md](INFERENCE_RUNTIME_CONTRACT.md) — Inference Runtime Contract Specification
- [MODEL_LIFECYCLE_SPEC.md](MODEL_LIFECYCLE_SPEC.md) — Model Lifecycle & Provisioning Specification
- [MODEL_MANIFEST_SPEC.md](MODEL_MANIFEST_SPEC.md) — Model & Runtime Manifest Specification
- [TEST_RUNTIME_STRATEGY.md](TEST_RUNTIME_STRATEGY.md) — Test Runtime & Mocking Strategy
- [WINDOWS_INSTALLER_AND_UPDATE_SPEC.md](WINDOWS_INSTALLER_AND_UPDATE_SPEC.md) — Windows Shell, Installer & Directory Spec
- [AGENTS.md](../../AGENTS.md) — Agent Architecture & Repository Guidelines
