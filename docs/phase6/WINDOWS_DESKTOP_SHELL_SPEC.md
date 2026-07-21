# Windows Desktop Shell and App Settings Specification

**Project:** A.U.R.A. — Artificial Unbound Reasoning Arena  
**Target path:** `docs/phase6/WINDOWS_DESKTOP_SHELL_SPEC.md`  
**Status:** Normative Specification  
**Phase:** 6.0 — Architecture and Distribution Design Gate  
**Parent documents:**
- `docs/phase6/CROSS_PLATFORM_RUNTIME_ADR.md`
- `docs/phase6/INFERENCE_RUNTIME_CONTRACT.md`
- `docs/phase6/MODEL_LIFECYCLE_SPEC.md`
- `docs/phase6/HARDWARE_PROFILE_SPEC.md`

**Primary target:** Windows x64 Desktop Shell & App Settings UI  
**Document revision:** 1.0  
**Last updated:** 2026-07-21

---

## 1. Purpose

This specification defines the normative requirements for the Windows Desktop Shell window management, branding, and the persistent **Runtime & Models Settings** interface within the application.

---

## 2. Desktop Shell & Window Modes

The Windows application shell manages window state via a platform-neutral controller (`WindowModeController`):

### 2.1 Window States
- **Windowed (`windowed`):** Standard resizable window with native titlebar or custom CRT frame.
- **Maximized (`maximized`):** Maximized to active monitor bounds.
- **Borderless Fullscreen (`borderlessFullscreen`):** Exclusive borderless window matching active monitor resolution.
- **Restored Previous (`restorePrevious`):** Persisted window position, size, and monitor index loaded at startup.

### 2.2 Hotkeys & Focus Behavior
- **F11 / Alt+Enter:** Toggles borderless fullscreen mode.
- **Escape:** Exits borderless fullscreen to windowed mode when in non-gameplay screens.
- **Focus Loss:** When the application window loses focus, audio gain attenuates and frame rate throttles to conserve GPU/CPU resources.

---

## 3. Runtime & Models Settings UI Specification

The App Settings screen includes a dedicated **Runtime & Models** section allowing persistent management of local inference configuration.

### 3.1 Views and Capabilities

The UI exposes the following controls:

1. **Active Runtime & Backend Display:** Shows current runtime engine (`ManagedLlamaServerRuntime`, `ExternalOpenAiRuntime`, `RuleBasedInferenceRuntime`) and active backend (`CUDA`, `Vulkan`, `Metal`, `CPU`).
2. **Managed Model Store Location:**
   - Displays current model store folder path.
   - Provides a "Change Store Location..." button invoking the transactional migration procedure (`ModelProvisioningService.migrateModelStore`).
3. **Performance Profile Selector:**
   - Dropdown options: `Automatic / Recommended`, `Memory Saver`, `Quality`, `Manual / Advanced`.
   - Persists preference mode (`automatic`, `recommendedPinned`, `manual`).
4. **Model Role Assignments:**
   - Displays assigned models for `aura.evaluator.primary` and `aura.actor.primary`.
   - Allows selecting installed variants or external bindings.
5. **Model Inventory & Verification Status:**
   - Lists all installed managed models and external local bindings.
   - Displays verification status (SHA-256 verified, GGUF format, quantization, file size).
   - Distinguishes managed store models from `externalLocal` bindings with visual indicators.
6. **Action Operations:**
   - **Download Missing Models:** Prompts for consent and initiates download of manifest variants.
   - **Import Local GGUF File:** Opens file picker, inspects GGUF headers, and presents import/bind options.
   - **Re-run Hardware Benchmark:** Re-probes system hardware and updates explainable recommendation proposal.
   - **Reset to Recommended:** Restores settings to the profiler recommendation proposal.
   - **Delete Unused Models:** Removes non-active managed models to free storage space.

### 3.2 Architectural Isolation of Settings UI

```text
┌──────────────────────────────────────┐
│       App Settings Screen UI         │
└──────────────────┬───────────────────┘
                   │
                   │ (Delegates all actions)
                   ▼
┌──────────────────────────────────────┐
│       ModelProvisioningService       │
└──────────────────┬───────────────────┘
                   │
         ┌─────────┴─────────┐
         ▼                   ▼
┌─────────────────┐ ┌──────────────────┐
│ ModelStore      │ │ ModelLifecycle   │
└─────────────────┘ └──────────────────┘
```

#### Strict Separation Rules:
- The UI layer **never** modifies `installed-models.json` or preferences directly.
- The UI layer **never** executes raw filesystem operations (copy, move, delete).
- The UI layer **never** directly contacts Hugging Face URIs or constructs raw HTTP download requests.
- All mutating operations are passed to `ModelProvisioningService` and `ModelLifecycleManager`, which emit progress events consumed by UI state notifiers.

---

## 4. Portable Mode Behavior

When running in Portable Mode (e.g. `AURA-Portable-x.y.z.zip` unpacked on external drive):
1. **Relative Model Store Default:** Model store defaults to relative path `.\data\models\`.
2. **Isolated Preferences:** Configuration and registry files remain inside `.\data\config\` rather than AppData.
3. **External Model Linking:** Portable mode permits linking external GGUF files without forcing copies onto the portable drive.
4. **Storage Preservation:** Portable store contents are preserved upon app termination.
