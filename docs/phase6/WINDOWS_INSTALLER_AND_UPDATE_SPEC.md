# Windows Installer, Provisioning Wizard and Update Specification

**Project:** A.U.R.A. — Artificial Unbound Reasoning Arena  
**Target path:** `docs/phase6/WINDOWS_INSTALLER_AND_UPDATE_SPEC.md`  
**Status:** Normative Specification  
**Phase:** 6.0 — Architecture and Distribution Design Gate  
**Parent documents:**
- `docs/phase6/CROSS_PLATFORM_RUNTIME_ADR.md`
- `docs/phase6/MODEL_LIFECYCLE_SPEC.md`
- `docs/phase6/HARDWARE_PROFILE_SPEC.md`
- `docs/phase6/MODEL_MANIFEST_SPEC.md`

**Primary target:** Windows x64 Installer & Application Setup  
**Document revision:** 1.0  
**Last updated:** 2026-07-21

---

## 1. Purpose

This specification defines the normative behavior for the Windows installation wizard, initial hardware-aware provisioning, application updates, repair procedures, and uninstallation.

---

## 2. Core Architectural Principle

> **"The installer performs initial hardware-aware provisioning; the application maintains permanent control over model store, performance profiles, models, compatible imports, updates, repair, and rollback."**

To prevent duplicate logic, **the installer and the desktop application share the exact same application service boundary** (`ModelProvisioningService`) and `ModelLifecycleManager`. The installer does not contain a secondary, independent implementation of model lifecycle, integrity checking, or hardware recommendation logic.

---

## 3. Initial Provisioning Wizard Flow

The initial setup wizard (executed during installation or on first desktop application boot) follows 15 explicit normative steps:

```text
1. Hardware Probe
       │
       ▼
2. Recommendation Profile Generation
       │
       ▼
3. Proposal Presentation (Backend, Models, Space, Rationale)
       │
       ▼
4. Model Store Directory Confirmation / Custom Selection
       │
       ▼
5. Optional Local GGUF Directory Scanning
       │
       ▼
6. Local Model Inspection & Classification (6 Levels)
       │
       ▼
7. User Action Selection (Adopt / Import / Download / Defer)
       │
       ▼
8. Model License Terms Acceptance
       │
       ▼
9. Disk Space Preflight Check
       │
       ▼
10. Resumable Download Execution (Missing Approved Artifacts)
       │
       ▼
11. Integrity & Format Verification (SHA-256 / GGUF Headers)
       │
       ▼
12. Atomic Managed Store Registration
       │
       ▼
13. Model Execution Plan Activation
       │
       ▼
14. Runtime Smoke Test
       │
       ▼
15. Provisioning Summary & Final Report
```

### 3.1 Step Details & Normative Requirements

1. **Hardware Probe:** `HardwareProbe` queries system RAM, dedicated VRAM, CPU architecture, instruction set extensions (AVX2/AVX512), and GPU backends (CUDA/Vulkan).
2. **Recommendation Generation:** `HardwareProfileBuilder` generates a `HardwareProvisioningProposal` containing recommended backend, variants, quantizations, and context sizes.
3. **Proposal Presentation:** UI displays hardware detected, recommended plan, estimated RAM/VRAM usage, required download space, and clear explainable rationale.
4. **Model Store Directory Selection:** User confirms default path (`%LOCALAPPDATA%\AURA\models`) or selects a custom directory path.
5. **Optional Directory Scanning:** User may point the wizard to existing local folders containing `.gguf` files.
6. **Local Model Inspection:** `ModelInspector` inspects headers and `IntegrityVerifier` computes hashes to classify local files into 6 normative levels (`exactVerifiedMatch`, `compatibleKnownVariant`, `compatibleUnverifiedImport`, `externallyOwnedBinding`, `incompatible`, `unknownReviewRequired`).
7. **User Action Selection:** User chooses whether to adopt/import compatible local files, download missing variants, or defer model acquisition to later.
8. **License Agreement:** User reviews and accepts applicable license terms for model variants requiring agreement.
9. **Space Preflight:** `ModelStore` verifies target disk free space (download size $+ 15\%$ safety margin).
10. **Resumable Download:** Missing approved artifacts are transferred via HTTP Range requests writing to `.partial` files under `/staging/`.
11. **Verification:** `IntegrityVerifier` checks SHA-256 and GGUF header consistency.
12. **Atomic Registration:** Files are committed to `/models/` and registered in `InstalledModelRegistry`.
13. **Plan Activation:** `ModelExecutionPlanResolver` binds installed handles to logical roles (`aura.evaluator.primary`, `aura.actor.primary`).
14. **Runtime Smoke Test:** Executes a 1-token non-gameplay generation test to verify backend readiness.
15. **Final Report:** Displays summary, active backend, and launch options.

---

## 4. Shared Application Service Boundary

```text
┌──────────────────────────────────────┐     ┌──────────────────────────────────────┐
│     Windows Installer Wizard         │     │     App Settings / Setup Wizard      │
└──────────────────┬───────────────────┘     └──────────────────┬───────────────────┘
                   │                                            │
                   └─────────────────────┬──────────────────────┘
                                         │
                                         ▼
                     ┌──────────────────────────────────────┐
                     │       ModelProvisioningService       │
                     └──────────────────┬───────────────────┘
                                         │
                   ┌─────────────────────┴─────────────────────┐
                   ▼                                           ▼
       ┌──────────────────────┐                    ┌──────────────────────┐
       │ HardwareProfiler     │                    │ ModelLifecycleManager│
       └──────────────────────┘                    └──────────────────────┘
```

The `ModelProvisioningService` contract orchestrates:
- Hardware probe evaluation and proposal generation;
- Model store migration and validation;
- Local artifact scanning and classification;
- Download execution with user consent;
- Plan activation and smoke testing.

---

## 5. Offline & Zero-Download Setup Modes

1. **Zero-Download Mode:** The installer permits installation without downloading any model files. The app boots in offline deterministic mode or prompts for model configuration upon launch.
2. **Offline Local Setup:** The installer can consume pre-downloaded model artifacts or local GGUF directories provided on installation media or local drives without network access.
3. **No Implicit Network Access:** The installer **never initiates network requests** without explicit user consent.

---

## 6. Application Upgrade, Repair, and Uninstall

### 6.1 Application Upgrade
- Upgrading the A.U.R.A. executable or Flutter shell **preserves all existing managed model store contents**, custom store paths, configuration, audio packs, and replay logs.
- Existing verified models do not need to be re-downloaded upon app update.

### 6.2 Application Repair
- Repair mode verifies app binaries, runtime sidecars, and model store integrity.
- Corrupted model files are quarantined and re-downloaded or re-imported; intact models are left untouched.

### 6.3 Selective Uninstallation
- Uninstaller prompts the user with explicit checkboxes:
  - `[ ] Remove Application Executable and Runtime` (Checked by default)
  - `[ ] Remove Managed Model Store (%LOCALAPPDATA%\AURA\models)` (Unchecked by default)
  - `[ ] Remove Audio Assets and User Replays` (Unchecked by default)
- User models are never deleted during uninstallation unless explicitly checked by the user.
