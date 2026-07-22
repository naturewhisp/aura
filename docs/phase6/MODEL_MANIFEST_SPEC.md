# Model Manifest Specification

**Project:** A.U.R.A. — Artificial Unbound Reasoning Arena  
**Target path:** `docs/phase6/MODEL_MANIFEST_SPEC.md`  
**Status:** Revised after repository-aware review; proposed for approval  
**Phase:** 6.0 — Architecture and Distribution Design Gate  
**Parent documents:**
- `docs/phase6/CROSS_PLATFORM_RUNTIME_ADR.md`
- `docs/phase6/INFERENCE_RUNTIME_CONTRACT.md`
- `docs/phase6/PHASE_6_4_ACQUISITION_AND_LIFECYCLE_SPEC.md`

**Repository baseline:** `5d5f32533a520e5a224a53462a711f52410055ed`  
**Manifest specification version:** 1.1  
**Primary production target:** Windows x64  
**Secondary production target:** Android arm64, Phase 7  
**Review basis:** repository-aware review performed after the first draft  
**Last updated:** 2026-07-20

---

## 1. Purpose

This specification defines the canonical model manifest used by A.U.R.A. to describe, resolve, install, verify, update, and load local inference models.

The manifest separates stable application semantics from provider-specific model artifacts.

Agents and gameplay use logical identities such as:

```text
aura.evaluator.primary
aura.actor.primary
```

The model-management layer resolves those identities to concrete variants such as:

```text
provider repository
pinned revision
GGUF filename
quantization
checksum
runtime compatibility
platform compatibility
hardware requirements
prompt format
structured-output capabilities
```

The manifest is the authoritative declaration of what A.U.R.A. may install and execute. A model file found on disk is not trusted or considered installed merely because its filename looks correct.

---

## 2. Architectural Role

The manifest participates in this flow:

```text
Agent requests ModelRole
        |
        v
RuntimeInferenceBridge
        |
        v
ModelExecutionPlan
        |
        v
Logical Model ID
        |
        v
Model Manifest Resolver
        |
        +-- platform compatibility
        +-- runtime compatibility
        +-- hardware compatibility
        +-- installed artifact state
        +-- user profile
        |
        v
ResolvedModelArtifact
        |
        v
InferenceRuntime.loadModel(...)
```

The manifest is consumed by:

- `ModelManifestRepository`;
- `ModelManifestValidator`;
- `ModelResolver`;
- `ModelManager`;
- `ModelStore`;
- `ModelExecutionPlanResolver`;
- installer and setup wizard;
- release pipeline;
- diagnostics and support tools;
- test fixtures.

The manifest is not consumed directly by:

- `EvaluatorAgent`;
- `ActorAgent`;
- `GameController`;
- gameplay rules;
- Flutter widgets.

---

## 3. Goals

The specification must guarantee:

1. stable logical model identities;
2. exact artifact reproducibility;
3. platform- and hardware-aware variant selection;
4. runtime/model compatibility validation;
5. integrity verification before installation and loading;
6. deterministic update and rollback behavior;
7. explicit licenses and provenance;
8. offline import support;
9. compatibility with Windows and Android;
10. separation between catalog metadata and local installation state;
11. testability without network access or real models;
12. a future extension path for LoRA adapters.

---

## 4. Non-Goals

This document does not define:

- download scheduling or progress UX;
- exact storage directories;
- atomic installation implementation;
- runtime process lifecycle;
- hardware tier thresholds;
- final model choices or quantizations;
- release signing implementation;
- installer screens;
- LoRA training;
- prompt contents for PANOPTICON;
- model benchmarking methodology.

Those concerns are handled by:

```text
MODEL_LIFECYCLE_SPEC.md
HARDWARE_PROFILE_SPEC.md
TEST_RUNTIME_STRATEGY.md
WINDOWS_INSTALLER_AND_UPDATE_SPEC.md
RELEASE_PIPELINE_SPEC.md
```

---

## 5. Core Principles

### 5.1 Logical identity is stable

Application code refers only to logical IDs.

Required initial logical IDs:

```text
aura.evaluator.primary
aura.actor.primary
```

Possible future logical IDs:

```text
aura.shared.primary
aura.evaluator.fallback
aura.actor.fallback
aura.memory.optional
aura.testing.tiny
```

Provider IDs and physical filenames must never become agent-facing contracts.

### 5.2 Every production artifact is pinned

A production artifact must identify an immutable source.

For a Hugging Face artifact, the manifest must include:

```text
repository
exact commit revision
filename
expected size
SHA-256
```

The following are forbidden in production manifests:

```text
revision: main
revision: master
revision: latest
unversioned direct URL
missing checksum
wildcard filename
```

### 5.3 Catalog state and installed state are separate

The manifest declares available models.

A separate installation registry records:

- what is installed;
- where it is installed;
- when it was verified;
- which manifest version installed it;
- whether it is active;
- rollback state;
- local import provenance.

The manifest must not be modified to record local paths or download progress.

### 5.4 Resolution is capability-based

A variant is selected by evaluating explicit requirements, not by matching arbitrary model names returned by an external server.

### 5.5 Fail closed

If identity, compatibility, size, or checksum cannot be verified, the artifact must not be loaded as a managed production model.

---

## 6. Manifest Types

A.U.R.A. defines three related manifest types.

### 6.1 Catalog manifest

Describes logical models and all supported physical variants.

Suggested filename:

```text
model-manifest.json
```

### 6.2 Runtime manifest

Describes supported inference-runtime builds and native packages.

Suggested filename:

```text
runtime-manifest.json
```

The runtime manifest is specified separately, but model variants reference compatible runtime constraints.

### 6.3 Installed-model registry

Records local installation state.

Suggested filename:

```text
installed-models.json
```

It is generated locally and is not a release catalog.

This specification primarily defines the catalog manifest and its interaction with the installed-model registry.

---

## 7. Manifest Location and Distribution

Canonical repository location:

```text
distribution/models/model-manifest.json
```

Optional environment-specific manifests:

```text
distribution/models/model-manifest.dev.json
distribution/models/model-manifest.beta.json
distribution/models/model-manifest.stable.json
```

Recommended policy:

- one canonical schema;
- one manifest per release channel;
- release artifacts include the exact manifest used to build the release;
- the application stores a verified local copy;
- updates are downloaded only through the configured release channel;
- test fixtures live separately under `test/fixtures/`.

Production code must not silently merge arbitrary manifests from the filesystem.

---

## 8. Top-Level Schema

Conceptual top-level shape:

```json
{
  "schema_version": "1.0.0",
  "manifest_id": "aura.models.stable",
  "manifest_version": "1.0.0",
  "channel": "stable",
  "generated_at": "2026-07-20T00:00:00Z",
  "minimum_app_version": "0.2.0",
  "minimum_runtime_contract_version": "1.0.0",
  "models": [],
  "resolution_policies": {},
  "metadata": {}
}
```

### 8.1 Required top-level fields

| Field | Type | Required | Meaning |
|---|---:|---:|---|
| `schema_version` | semantic version string | yes | Schema format implemented by the parser. |
| `manifest_id` | string | yes | Stable identity of the manifest family. |
| `manifest_version` | semantic version string | yes | Version of this catalog content. |
| `channel` | enum | yes | `stable`, `beta`, `dev`, or `test`. |
| `generated_at` | ISO-8601 UTC string | yes | Build timestamp for diagnostics. |
| `minimum_app_version` | semantic version string | yes | Oldest application allowed to consume it. |
| `minimum_runtime_contract_version` | semantic version string | yes | Oldest runtime-contract version allowed. |
| `models` | array | yes | Logical model declarations. |
| `resolution_policies` | object | yes | Global deterministic resolution rules. |
| `metadata` | object | no | Non-normative release metadata. |

### 8.2 Optional top-level fields

```text
maximum_app_version
expires_at
supersedes_manifest_version
release_notes_id
signature_metadata
default_locale
```

`expires_at` must not automatically disable an already-installed working model while offline. Expiration controls catalog refresh policy, not gameplay availability.

---

## 9. Logical Model Declaration

Conceptual shape:

```json
{
  "logical_model_id": "aura.evaluator.primary",
  "display_name": "A.U.R.A. Evaluator",
  "roles": ["evaluator"],
  "required": true,
  "selection_priority": 100,
  "fallback_logical_model_ids": [
    "aura.evaluator.fallback"
  ],
  "variants": []
}
```

### 9.1 Required fields

| Field | Type | Meaning |
|---|---|---|
| `logical_model_id` | string | Stable application identity. |
| `display_name` | string | Technical/user-facing label, not a provider identifier. |
| `roles` | enum array | Supported A.U.R.A. roles. |
| `required` | boolean | Whether setup must resolve this model for the selected profile. |
| `selection_priority` | integer | Priority among logical alternatives. |
| `fallback_logical_model_ids` | string array | Ordered fallback logical identities. |
| `variants` | array | Concrete physical model variants. |

### 9.2 Logical ID format

Logical IDs must use lowercase dot-separated segments:

```regex
^aura\.[a-z0-9]+(?:\.[a-z0-9]+)+$
```

Valid:

```text
aura.evaluator.primary
aura.actor.primary
aura.shared.primary
aura.testing.tiny
```

Invalid:

```text
mistralai/ministral-3-3b
ActorModel
aura_actor_primary
aura.actor.latest
```

The segment `latest` is forbidden because it introduces mutable semantics.

### 9.3 Role values

```text
evaluator
actor
shared
memory
testing
```

A model declared with role `shared` must explicitly declare which operational roles it may satisfy:

```json
"shared_role_bindings": ["evaluator", "actor"]
```

---

## 10. Model Variant Declaration

Conceptual shape:

```json
{
  "variant_id": "aura.evaluator.primary.ministral3-3b.q4_k_m.win-x64",
  "model_family": "ministral",
  "model_version": "3-3b-instruct-2512",
  "provider": "mistralai",
  "artifact": {},
  "license": {},
  "compatibility": {},
  "hardware_requirements": {},
  "inference_profile": {},
  "prompt_format": {},
  "capabilities": {},
  "quality_tier": "recommended",
  "priority": 100,
  "enabled": true
}
```

### 10.1 Variant ID

The variant ID is stable inside the A.U.R.A. catalog.

Recommended pattern:

```text
aura.<role>.<model-family>.<quantization>.<platform-profile>
```

It must not be derived at runtime from a filename.

### 10.2 Required variant fields

| Field | Required |
|---|---:|
| `variant_id` | yes |
| `model_family` | yes |
| `model_version` | yes |
| `provider` | yes |
| `artifact` | yes |
| `license` | yes |
| `compatibility` | yes |
| `hardware_requirements` | yes |
| `inference_profile` | yes |
| `prompt_format` | yes |
| `capabilities` | yes |
| `quality_tier` | yes |
| `priority` | yes |
| `enabled` | yes |

---

## 11. Artifact Declaration

### 11.1 Shape

```json
{
  "artifact": {
    "format": "gguf",
    "source": {
      "type": "huggingface",
      "repository": "organization/repository",
      "revision": "40-character-commit-sha",
      "filename": "model-file.gguf"
    },
    "size_bytes": 0,
    "sha256": "64-lowercase-hex-characters",
    "content_id": "sha256:<digest>",
    "compression": "none",
    "download": {
      "supports_range": true,
      "mirrors": []
    }
  }
}
```

### 11.2 Supported source types

Initial source types:

```text
huggingface
github_release
aura_release
offline_only
```

A source adapter may support additional types later, but production manifests must use a type understood by the current application.

### 11.3 Hugging Face source

Required fields:

```text
repository
revision
filename
```

`revision` must be an exact immutable commit hash.

The resolver may construct a download request from these fields, but the manifest must not rely on branch names or dynamic repository state.

### 11.4 Direct URLs

Raw direct URLs are discouraged.

If a nonstandard source requires a URL, it must also declare:

```text
trusted_host
immutable_resource_id
size_bytes
sha256
```

Redirects to untrusted hosts must be rejected.

### 11.5 Size and checksum

`size_bytes` must be greater than zero.

`sha256` must:

- contain exactly 64 lowercase hexadecimal characters;
- identify the final uncompressed artifact;
- be verified before atomic installation;
- be verified again before loading when installation state is uncertain.

### 11.6 Content ID

Recommended:

```text
sha256:<digest>
```

This permits deduplication when multiple variants reference identical bytes.

### 11.7 Multipart artifacts

The first Phase 6 schema supports one primary GGUF file per variant.

Additional files may be declared through:

```json
"companion_artifacts": []
```

Examples:

- tokenizer metadata;
- projector file;
- external chat template;
- license text;
- LoRA adapter.

Multimodal projector support is not required in Phase 6.

---

## 12. License and Provenance

Every production variant must declare:

```json
{
  "license": {
    "spdx_id": "Apache-2.0",
    "name": "Apache License 2.0",
    "source_url": "provider-license-reference",
    "redistribution_allowed": true,
    "commercial_use_allowed": true,
    "notice_required": true,
    "accepted_by_project": true
  }
}
```

### 12.1 Required checks

Before enabling a variant:

- license is reviewed;
- redistribution rules are understood;
- model card restrictions are recorded;
- required notices are included;
- the release process can satisfy attribution requirements.

### 12.2 Provenance metadata

Recommended fields:

```json
{
  "provenance": {
    "upstream_model": "provider/model",
    "conversion_author": "provider-or-aura",
    "conversion_tool": "llama.cpp",
    "conversion_tool_version": "pinned-version",
    "quantization_method": "Q4_K_M",
    "quantized_from_revision": "immutable-revision"
  }
}
```

A third-party quantized GGUF must identify both the upstream model and the quantized artifact source.

---

## 13. Compatibility Declaration

### 13.1 Shape

```json
{
  "compatibility": {
    "platforms": [
      {
        "os": "windows",
        "architecture": "x64"
      }
    ],
    "runtime_contract": {
      "minimum": "1.0.0",
      "maximum_exclusive": "2.0.0"
    },
    "runtime_packages": [
      {
        "runtime_id": "aura.llama_cpp.windows.cuda",
        "version_range": ">=1.0.0 <2.0.0"
      }
    ],
    "gguf": {
      "minimum_version": 3,
      "architectures": ["ministral"]
    }
  }
}
```

### 13.2 Platform values

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

### 13.3 Runtime compatibility

A variant must declare:

- supported runtime-contract range;
- supported runtime package family or families;
- required model format support;
- architecture support.

A runtime must reject a model before load when compatibility cannot be established.

### 13.4 External runtime adapter

For `ExternalOpenAiRuntime`, physical loading may be externally owned.

A manifest variant may declare:

```json
"external_binding": {
  "accepted_server_model_ids": [
    "provider/model-id"
  ]
}
```

This exists only for development compatibility.

During the Phase 6.1 migration, `ExternalOpenAiRuntime` may bind a logical model directly to a model already exposed by LM Studio or another compatible development server. In this mode:

- `discoverModels()` remains adapter-specific availability discovery;
- `accepted_server_model_ids` is matched only inside the external adapter/model-management boundary;
- no managed GGUF download, staging operation or local `installed-models.json` entry is required;
- the resulting logical binding still produces a session-scoped `ModelHandle`;
- the binding is treated as externally owned and cannot be reported as a verified managed installation;
- production profiles must not select `external_binding` implicitly;
- Android adapters must ignore `external_binding`.

It must not make provider IDs visible to agents.

---

## 14. Hardware Requirements

### 14.1 Shape

```json
{
  "hardware_requirements": {
    "minimum_system_memory_bytes": 0,
    "recommended_system_memory_bytes": 0,
    "minimum_device_memory_bytes": 0,
    "recommended_device_memory_bytes": 0,
    "minimum_free_storage_bytes": 0,
    "supported_backends": ["cuda", "vulkan", "cpu"],
    "minimum_cpu_threads": 4,
    "mobile": {
      "allowed": false,
      "minimum_android_api": null
    },
    "profile_tags": [
      "desktop-balanced"
    ]
  }
}
```

### 14.2 Semantics

Manifest values are model-specific constraints.

Global hardware-tier classification belongs to `HARDWARE_PROFILE_SPEC.md`.

The resolver combines:

```text
detected hardware profile
variant hardware requirements
runtime compatibility
execution-plan policy
```

### 14.3 Memory estimates

Memory values are estimates and must include a documented safety policy.

The manifest may add:

```json
"memory_estimation": {
  "weights_bytes": 0,
  "estimated_runtime_overhead_bytes": 0,
  "estimated_context_overhead_bytes_at_default": 0,
  "safety_multiplier": 1.15
}
```

The application must not assume GGUF file size equals runtime memory usage.

### 14.4 Android requirements

Android variants may declare:

```text
minimum_android_api
supported_abis
minimum_system_memory_bytes
recommended_thermal_class
maximum_default_context_size
```

A desktop variant is not automatically Android-compatible merely because it uses GGUF.

---

## 15. Inference Profile

### 15.1 Shape

```json
{
  "inference_profile": {
    "default_context_size": 8192,
    "minimum_context_size": 4096,
    "maximum_context_size": 16384,
    "default_max_output_tokens": 512,
    "recommended_temperature": 0.2,
    "recommended_top_p": 0.9,
    "recommended_top_k": 40,
    "recommended_repetition_penalty": 1.05,
    "seed_policy": "supported",
    "thinking_policy": "disabled",
    "load_defaults": {
      "memory_map": true,
      "memory_lock": false
    }
  }
}
```

### 15.2 Purpose

The profile provides validated model defaults.

It does not override agent-level generation policy without an explicit merge rule.

### 15.3 Merge precedence

Recommended precedence:

```text
hard safety bounds
    >
runtime capability bounds
    >
hardware profile adjustments
    >
model variant defaults
    >
agent request preferences
```

The final merged request must remain within hard bounds.

### 15.4 Backend-specific settings

Backend-specific options must be namespaced:

```json
"adapter_options": {
  "llama_cpp": {
    "flash_attention_preferred": true
  }
}
```

Agents and gameplay must not read these fields.

---

## 16. Prompt Format

### 16.1 Shape

```json
{
  "prompt_format": {
    "chat_template": {
      "source": "embedded_model_metadata",
      "template_id": "ministral-instruct"
    },
    "supports_system_role": true,
    "supports_assistant_prefill": false,
    "bos_policy": "runtime_default",
    "eos_policy": "runtime_default",
    "reasoning_format": "none"
  }
}
```

### 16.2 Template sources

Allowed initial values:

```text
embedded_model_metadata
runtime_builtin
manifest_inline
manifest_artifact
```

Inline templates are discouraged for large or complex templates.

### 16.3 Template validation

A variant may not enter `stable` until:

- Actor prompt rendering is tested;
- Evaluator prompt rendering is tested;
- system-role behavior is known;
- unwanted reasoning leakage is tested;
- structured-output behavior is tested.

### 16.4 Reasoning metadata

Possible values:

```text
none
native_field
tagged_content
unknown
```

This informs `ReasoningContentPolicy` but does not authorize rendering reasoning to the user.

---

## 17. Capability Declaration

### 17.1 Shape

```json
{
  "capabilities": {
    "text_generation": true,
    "structured_generation": {
      "prompt_constrained": true,
      "grammar": true,
      "json_schema": false
    },
    "deterministic_seed": true,
    "supports_cancellation": true,
    "supports_token_streaming": true,
    "supports_roles": ["evaluator"],
    "supported_languages": ["it", "en"],
    "validated_output_policies": [
      "actor_dialogue_sanitizer_v1",
      "evaluator_schema_v1"
    ]
  }
}
```

### 17.2 Manifest claims are not runtime facts

The manifest declares expected capability.

At runtime:

```text
effective capability =
manifest capability
∩ runtime capability
∩ selected backend capability
```

The application must use the intersection.

### 17.3 Structured generation

A model suitable for `evaluator` must support at least:

```text
prompt_constrained structured generation
```

Grammar or JSON-schema support is preferred but not mandatory.

Local validation is always mandatory.

### 17.4 Language validation

A model must not be marked as supporting Italian merely because its upstream model card claims multilingual capability.

A.U.R.A. must validate:

- instruction following;
- Italian comprehension;
- Italian output;
- CJK leakage risk;
- schema reliability;
- diegetic consistency where applicable.

---

## 18. Quality Tier and Release State

### 18.1 Quality tiers

```text
recommended
compatible
fallback
experimental
testing
deprecated
```

### 18.2 Release states

```text
candidate
approved
disabled
deprecated
revoked
```

Suggested fields:

```json
"quality_tier": "recommended",
"release_state": "approved",
"enabled": true
```

### 18.3 Revocation

A variant may be revoked due to:

- license issue;
- security issue;
- corrupt upstream artifact;
- incompatible runtime behavior;
- unacceptable output quality;
- regression;
- invalid checksum declaration.

Revocation policy must distinguish:

- prevent new installs;
- warn existing installs;
- block execution;
- require rollback.

Blocking an offline installed model requires a signed or otherwise trusted revocation policy and is finalized in the release specification.

---

## 19. Selection Priority

Each logical model and variant has an integer priority.

Higher values are preferred.

Priority alone is insufficient. Resolution order is:

```text
1. enabled/release state
2. logical-role compatibility
3. platform compatibility
4. runtime-contract compatibility
5. runtime-package compatibility
6. artifact availability/integrity
7. hardware requirements
8. user policy
9. quality tier
10. explicit priority
11. deterministic tie-breaker by variant_id
```

The resolver must produce an explanation of why each rejected variant was rejected.

---

## 20. Resolution Policies

Top-level example:

```json
{
  "resolution_policies": {
    "prefer_installed": true,
    "prefer_recommended_quality": true,
    "allow_experimental": false,
    "allow_backend_fallback": true,
    "allow_quantization_downgrade": true,
    "allow_shared_model_plan": true,
    "allow_deterministic_evaluator": true,
    "require_verified_artifacts": true
  }
}
```

### 20.1 User policy interaction

User settings may narrow allowed choices but must not bypass:

- integrity;
- compatibility;
- license acceptance;
- hard memory limits.

### 20.2 Determinism

Given the same:

- manifest;
- installed registry;
- hardware profile;
- runtime capabilities;
- user policy;

the resolver must return the same result.

---

## 21. Initial Logical Model Set

The first production manifest must include at least:

```text
aura.evaluator.primary
aura.actor.primary
```

It should also prepare:

```text
aura.shared.primary
aura.evaluator.fallback
```

The fallback may resolve to:

- a smaller neural model;
- a deterministic evaluator;
- an application-defined non-artifact implementation.

If a logical model is implemented without a downloadable artifact, its variant source may be:

```json
{
  "type": "builtin"
}
```

Builtin variants must identify an application/runtime implementation version.

---

## 22. Illustrative Manifest Example

The following example is deliberately non-production. Hashes, filenames, revisions, sizes, and versions are placeholders.

```json
{
  "schema_version": "1.0.0",
  "manifest_id": "aura.models.dev",
  "manifest_version": "0.1.0",
  "channel": "dev",
  "generated_at": "2026-07-20T00:00:00Z",
  "minimum_app_version": "0.2.0",
  "minimum_runtime_contract_version": "1.0.0",
  "models": [
    {
      "logical_model_id": "aura.evaluator.primary",
      "display_name": "A.U.R.A. Evaluator",
      "roles": ["evaluator"],
      "required": true,
      "selection_priority": 100,
      "fallback_logical_model_ids": [
        "aura.evaluator.fallback"
      ],
      "variants": [
        {
          "variant_id": "aura.evaluator.primary.example.q4_k_m.win-x64",
          "model_family": "example-family",
          "model_version": "example-version",
          "provider": "example-provider",
          "artifact": {
            "format": "gguf",
            "source": {
              "type": "huggingface",
              "repository": "example/model-gguf",
              "revision": "0000000000000000000000000000000000000000",
              "filename": "example-q4_k_m.gguf"
            },
            "size_bytes": 1,
            "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
            "content_id": "sha256:0000000000000000000000000000000000000000000000000000000000000000",
            "compression": "none",
            "download": {
              "supports_range": true,
              "mirrors": []
            }
          },
          "license": {
            "spdx_id": "Apache-2.0",
            "name": "Apache License 2.0",
            "source_url": "example-license-reference",
            "redistribution_allowed": true,
            "commercial_use_allowed": true,
            "notice_required": true,
            "accepted_by_project": false
          },
          "compatibility": {
            "platforms": [
              {
                "os": "windows",
                "architecture": "x64"
              }
            ],
            "runtime_contract": {
              "minimum": "1.0.0",
              "maximum_exclusive": "2.0.0"
            },
            "runtime_packages": [
              {
                "runtime_id": "aura.llama_cpp.windows.cpu",
                "version_range": ">=1.0.0 <2.0.0"
              }
            ],
            "gguf": {
              "minimum_version": 3,
              "architectures": ["example"]
            }
          },
          "hardware_requirements": {
            "minimum_system_memory_bytes": 8589934592,
            "recommended_system_memory_bytes": 17179869184,
            "minimum_device_memory_bytes": 0,
            "recommended_device_memory_bytes": 0,
            "minimum_free_storage_bytes": 2147483648,
            "supported_backends": ["cpu", "vulkan", "cuda"],
            "minimum_cpu_threads": 4,
            "mobile": {
              "allowed": false,
              "minimum_android_api": null
            },
            "profile_tags": ["desktop-balanced"]
          },
          "inference_profile": {
            "default_context_size": 8192,
            "minimum_context_size": 4096,
            "maximum_context_size": 16384,
            "default_max_output_tokens": 512,
            "recommended_temperature": 0.2,
            "recommended_top_p": 0.9,
            "recommended_top_k": 40,
            "recommended_repetition_penalty": 1.05,
            "seed_policy": "supported",
            "thinking_policy": "disabled",
            "load_defaults": {
              "memory_map": true,
              "memory_lock": false
            }
          },
          "prompt_format": {
            "chat_template": {
              "source": "embedded_model_metadata",
              "template_id": "example-instruct"
            },
            "supports_system_role": true,
            "supports_assistant_prefill": false,
            "bos_policy": "runtime_default",
            "eos_policy": "runtime_default",
            "reasoning_format": "none"
          },
          "capabilities": {
            "text_generation": true,
            "structured_generation": {
              "prompt_constrained": true,
              "grammar": false,
              "json_schema": false
            },
            "deterministic_seed": true,
            "supports_cancellation": true,
            "supports_token_streaming": true,
            "supports_roles": ["evaluator"],
            "supported_languages": ["it", "en"],
            "validated_output_policies": ["evaluator_schema_v1"]
          },
          "quality_tier": "testing",
          "release_state": "candidate",
          "priority": 100,
          "enabled": false
        }
      ]
    }
  ],
  "resolution_policies": {
    "prefer_installed": true,
    "prefer_recommended_quality": true,
    "allow_experimental": false,
    "allow_backend_fallback": true,
    "allow_quantization_downgrade": true,
    "allow_shared_model_plan": true,
    "allow_deterministic_evaluator": true,
    "require_verified_artifacts": true
  },
  "metadata": {
    "note": "Illustrative non-production manifest."
  }
}
```

No example value above is approved for release.

---

## 23. Installed-Model Registry

The local registry must be separate from the catalog.

Conceptual shape:

```json
{
  "schema_version": "1.0.0",
  "updated_at": "2026-07-20T00:00:00Z",
  "installations": [
    {
      "variant_id": "aura.evaluator.primary.example.q4_k_m.win-x64",
      "content_id": "sha256:...",
      "manifest_id": "aura.models.stable",
      "manifest_version": "1.0.0",
      "storage_uri": "platform-specific-managed-uri",
      "size_bytes": 0,
      "sha256": "...",
      "installed_at": "2026-07-20T00:00:00Z",
      "verified_at": "2026-07-20T00:00:00Z",
      "verification_status": "verified",
      "source_type": "download",
      "active": true,
      "rollback_candidate": false
    }
  ]
}
```

### 23.1 Registry rules

- Registry writes must be atomic.
- A registry entry without a verified artifact is invalid.
- A file without a registry entry may be imported but is not automatically trusted.
- Registry corruption must be recoverable by scanning managed storage and re-verifying known artifacts.
- `storage_uri` is platform-owned and must not appear in the catalog.
- A registry entry references the exact manifest version used during installation.

---

## 24. Offline Import

A user may import an existing GGUF file.

### 24.1 Import process

```text
select file
    |
    v
inspect GGUF metadata
    |
    v
compute size and SHA-256
    |
    v
match enabled manifest variant
    |
    +-- exact match -> eligible managed import
    |
    +-- no exact match -> unrecognized artifact
```

### 24.2 Exact match requirements

Managed import requires:

```text
format match
size match
SHA-256 match
architecture match
runtime compatibility
license acceptance
```

Filename alone is never sufficient.

### 24.3 Unrecognized models

Phase 6 production behavior:

- may allow developer-mode binding;
- must not label the artifact verified;
- must not use it automatically for stable gameplay;
- must not write a fake production manifest entry;
- must clearly separate it from supported variants.

---

## 25. Updates and Rollback

### 25.1 Update identity

An update occurs when a newer manifest selects a different:

```text
variant_id
or
content_id
or
artifact revision
```

Changing metadata without changing artifact bytes is a manifest update, not a model-byte update.

### 25.2 Side-by-side installation

Recommended policy:

```text
download new artifact to staging
verify
install side by side
perform smoke validation
activate new registry entry
retain previous verified artifact as rollback candidate
```

### 25.3 Rollback

Rollback must restore:

- previous active variant;
- previous compatible runtime if necessary;
- previous execution plan;
- previous registry state.

The manifest must permit the application to identify superseded variants.

Optional field:

```json
"supersedes_variant_ids": []
```

### 25.4 Garbage collection

Old artifacts may be deleted only when:

- not active;
- not needed for rollback;
- not referenced by another logical model;
- not user-pinned;
- registry update succeeds.

---

## 26. LoRA Extension Boundary

Phase 6 does not require LoRA, but the schema must reserve a compatible extension.

Conceptual future declaration:

```json
{
  "adapters": [
    {
      "adapter_id": "aura.panopticon.actor.lora.v1",
      "type": "lora",
      "artifact": {},
      "compatible_base_content_ids": [
        "sha256:..."
      ],
      "runtime_requirements": {
        "supports_lora": true
      }
    }
  ]
}
```

Rules:

- LoRA compatibility binds to exact base-model content IDs;
- provider/model family alone is insufficient;
- incompatible adapters must be rejected before load;
- the base model remains a normal manifest variant;
- LoRA lifecycle is specified in Phase 8.

---

## 27. Security Requirements

### 27.1 Manifest trust

The application must verify that a production manifest comes from a trusted release channel.

Transport security alone is insufficient for high-assurance update workflows; signature policy is finalized in `RELEASE_PIPELINE_SPEC.md`.

### 27.2 Path traversal

Manifest filenames must be plain relative artifact names.

Forbidden:

```text
../
..\
absolute paths
drive letters
URI schemes inside filename
NUL characters
```

### 27.3 Host allowlist

Download source hosts must be declared and validated.

Unexpected redirects must fail unless the source adapter explicitly validates the final host.

### 27.4 Decompression

If compressed artifacts are introduced:

- expanded size must be declared;
- decompression must be bounded;
- path traversal must be prevented;
- checksum must cover the final loadable artifact.

Phase 6 GGUF downloads should prefer uncompressed source files unless release engineering proves otherwise.

### 27.5 Malicious metadata

All string lengths and collection sizes must be bounded.

Manifest data must never be used to construct a shell command through string concatenation.

---

## 28. Validation Rules

A manifest is invalid when any of the following occurs:

```text
unsupported schema major version
duplicate logical_model_id
duplicate variant_id
unknown logical fallback ID
fallback cycle
invalid semantic version
mutable revision in production channel
invalid SHA-256
non-positive size
missing license review
unsupported source type
invalid platform or architecture
invalid runtime range
unknown role
no enabled variant for a required logical model
duplicate priority tie without deterministic variant_id
path traversal in filename
unsupported manifest channel
```

### 28.1 Cross-field validation

Examples:

- `mobile.allowed == true` requires an Android platform declaration.
- role `evaluator` requires structured-generation capability.
- `json_schema == true` requires a compatible runtime capability declaration.
- `release_state == revoked` cannot have `enabled == true`.
- `quality_tier == recommended` requires `release_state == approved`.
- production channel requires `license.accepted_by_project == true`.
- source `huggingface` requires immutable `revision`.
- source `builtin` must not declare a downloadable filename.

---

## 29. Parser Behavior

### 29.1 Unknown fields

Within the same major schema version:

- unknown optional fields should be ignored but retained where round-trip tooling requires it;
- unknown required-feature declarations must fail;
- unknown enum values must fail unless explicitly designated extensible.

### 29.2 Major versions

An unsupported major version must fail with:

```text
manifestSchemaUnsupported
```

The application must not guess.

### 29.3 Numeric safety

Large byte sizes must use integer types capable of representing multi-gigabyte values without precision loss.

Dart JSON parsing must validate integer semantics explicitly.

---

## 30. Resolution Output

The resolver produces a typed result.

Conceptual type:

```dart
@immutable
class ModelResolution {
  final String logicalModelId;
  final ModelRole requestedRole;
  final ModelVariant selectedVariant;
  final ResolutionDisposition disposition;
  final List<ResolutionDecision> decisions;
  final List<ModelVariantRejection> rejectedVariants;
}
```

Possible dispositions:

```text
installedVerified
downloadRequired
offlineImportRequired
builtinFallback
unresolvable
```

Every resolution must be explainable.

Example rejection reasons:

```text
platformMismatch
runtimeMismatch
insufficientMemory
insufficientStorage
artifactNotInstalled
experimentalDisallowed
licenseNotAccepted
integrityFailure
backendUnavailable
```

---

## 31. Relationship to ModelExecutionPlan

The manifest resolves individual logical models.

`ModelExecutionPlanResolver` combines those resolutions into an execution strategy.

Examples:

```text
Evaluator variant A + Actor variant B + simultaneous
Evaluator variant A + Actor variant B + sequential
Shared variant C + sharedSingleModel
Builtin deterministic Evaluator + Actor variant B
```

The manifest must not hardcode one universal residency policy.

It may provide compatibility and recommendation metadata consumed by the hardware/profile resolver.

---

## 32. Relationship to ExternalOpenAiRuntime

During migration, an external runtime may expose already-loaded model IDs.

The development binding flow is:

```text
logical model ID
    |
    v
manifest external_binding
    |
    v
accepted external server ID
    |
    v
logical ModelHandle
```

Rules:

- discovery remains adapter-specific;
- provider IDs stay inside the adapter/model-management boundary;
- agents still request only `ModelRole`;
- external bindings bypass managed download, staging and installation-registry creation;
- external bindings do not bypass logical-role resolution or session-scoped `ModelHandle` creation;
- production setup must not require external bindings;
- an unmatched external model is not selected automatically.

---

## 33. Testing Requirements

### 33.1 Unit tests

Must cover:

```text
valid manifest parsing
invalid schema version
duplicate IDs
fallback cycles
mutable production revision
invalid checksum
invalid size
license validation
platform filtering
runtime filtering
hardware filtering
deterministic priority
unknown fields
cross-field validation
```

### 33.2 Fixture manifests

Required fixtures:

```text
test/fixtures/model_manifest_valid.json
test/fixtures/model_manifest_minimal.json
test/fixtures/model_manifest_invalid_checksum.json
test/fixtures/model_manifest_fallback_cycle.json
test/fixtures/model_manifest_windows_variants.json
test/fixtures/model_manifest_android_variants.json
test/fixtures/model_manifest_shared_model.json
```

Fixtures must use tiny fake artifacts and must not reference real large model downloads.

### 33.3 Golden schema tests

If a formal JSON Schema is generated, CI must validate:

- the production manifest;
- all fixtures expected to pass;
- all negative fixtures expected to fail.

### 33.4 No network in standard tests

Manifest resolution tests use:

- in-memory catalog;
- fake installed registry;
- fake hardware profile;
- fake runtime capabilities.

They must not call Hugging Face or GitHub.

---

## 34. Release Pipeline Requirements

Before publishing a model manifest, CI must:

1. validate the schema;
2. reject mutable revisions;
3. verify every declared source artifact;
4. verify size;
5. verify SHA-256;
6. validate licenses and notices;
7. check duplicate content IDs;
8. confirm runtime compatibility references;
9. run model-resolution tests;
10. produce a human-readable catalog report;
11. include the exact manifest in release assets;
12. produce signature/checksum metadata according to release policy.

A release manifest must never be assembled from uncommitted local developer state.

---

## 35. Diagnostics

The application should expose:

```text
manifest ID/version/channel
logical model ID
selected variant ID
artifact content ID
installation status
verification status
runtime compatibility
hardware compatibility
rejection reasons
source and pinned revision
license identity
```

Raw local paths should be omitted from normal UI and included only in technical diagnostics where necessary.

---

## 36. Migration from Current ModelCatalog and ModelRouter

### Stage 1 — Introduce logical IDs

Replace direct semantic use of:

```text
mistralai/ministral-3-3b
qwen/qwen3.5-9b
google/gemma-4-12b
```

with:

```text
aura.evaluator.primary
aura.actor.primary
aura.shared.primary
```

Current provider IDs may remain in development variant metadata.

### Stage 2 — Manifest-backed catalog

Refactor `ModelCatalog.initialDefault()` into:

```text
ModelManifestRepository
ModelManifestParser
ModelManifestValidator
```

A small embedded development manifest may preserve current behavior temporarily.

### Stage 3 — Replace server discovery as the source of truth

`discoverModels()` becomes adapter-specific availability information.

The catalog and installed registry become authoritative for production resolution.

### Stage 4 — Introduce typed resolution

Replace string-only router output with typed `ModelResolution` and `ModelExecutionPlan`.

### Stage 5 — Integrate installation state

Resolve only verified installed artifacts, or return `downloadRequired`.

### Stage 6 — Remove physical IDs from UI and agent context

UI displays logical names and technical variant details separately.

Agents receive `ModelRole`, never physical model IDs.

---

## 37. Decisions Deferred to Following Documents

### MODEL_LIFECYCLE_SPEC.md

Will define:

- download state machine;
- staging;
- verification;
- atomic installation;
- registry writes;
- repair;
- update;
- rollback;
- garbage collection;
- offline import.

### HARDWARE_PROFILE_SPEC.md

Will define:

- RAM/VRAM tiers;
- backend capability probing;
- safety margins;
- context-size adjustments;
- simultaneous/sequential/shared selection;
- mobile constraints.

### TEST_RUNTIME_STRATEGY.md

Will define:

- test levels;
- tiny native model fixture;
- opt-in real-model tests;
- CI policies;
- manifest fixture strategy.

### RELEASE_PIPELINE_SPEC.md

Will define:

- manifest signature;
- trusted channels;
- asset publication;
- revocation transport;
- release provenance.

---

## 38. Acceptance Criteria

This specification is approved when all statements are accepted:

```text
- Agents and gameplay use logical model IDs or ModelRole, never provider IDs.
- A production variant pins repository, immutable revision, filename, size and SHA-256.
- Catalog manifest and installed-model registry are separate.
- Model files are not trusted from filenames alone.
- Variant selection is deterministic and explainable.
- Runtime, platform and hardware compatibility are explicit.
- Licenses and provenance are mandatory for production variants.
- The effective capability is the intersection of manifest, runtime and backend capabilities.
- Offline import requires an exact content match for managed status.
- Development-only external bindings may bypass managed installation state without being treated as verified installs.
- Updates support side-by-side verification and rollback.
- The schema supports Windows now and Android later without Windows paths.
- Standard tests validate manifests without network access or real models.
- Future LoRA adapters bind to exact base-model content IDs.
```

---

## 39. Exit Criteria for This Document

The document is complete when:

- committed under `docs/phase6/MODEL_MANIFEST_SPEC.md`;
- reviewed against the runtime ADR and contract;
- logical IDs required by the initial game are agreed;
- no production field permits mutable artifact identity;
- the lifecycle specification can consume the declared artifact and registry models;
- the lifecycle specification can distinguish managed installations from externally owned development bindings;
- the hardware specification can consume variant requirements;
- Antigravity can map the current `ModelCatalog` and `ModelRouter` to the new schema without inventing provider-facing agent contracts.

---

## 40. Recommended Antigravity Review Prompt

After this document is committed:

```text
Read in full:

- docs/phase6/CROSS_PLATFORM_RUNTIME_ADR.md
- docs/phase6/INFERENCE_RUNTIME_CONTRACT.md
- docs/phase6/MODEL_MANIFEST_SPEC.md

Review the current repository against the model-manifest specification.
Do not modify files.

Report:

1. all current physical model IDs and where they propagate;
2. current ModelCatalog and ModelRouter responsibilities;
3. UI/settings fields that expose provider IDs;
4. the minimum development manifest needed to preserve current behavior;
5. proposed Dart domain types for parsing and validation;
6. migration risks from discoverModels() to manifest-backed resolution;
7. any schema fields that cannot be supported by the current code;
8. potential conflicts with Windows managed llama-server;
9. potential conflicts with Android in-process inference;
10. specific changes required in the next MODEL_LIFECYCLE_SPEC.md and
    HARDWARE_PROFILE_SPEC.md.

Classify findings as BLOCKER, HIGH, MEDIUM or LOW.
Do not implement the manifest parser yet.
Do not select final production model files.
```

---

## 41. Final Decision

A.U.R.A. will use a versioned, validated model manifest as the sole production catalog for local inference artifacts.

Stable logical model identities are resolved to exact, immutable physical variants through explicit platform, runtime, hardware, capability, quality, license, and integrity constraints.

Provider model IDs, repository names, filenames, and local paths remain implementation metadata. They do not cross into agents or gameplay.

This model allows A.U.R.A. to replace models, choose device-appropriate quantizations, support offline imports, update and roll back safely, and prepare Android and future LoRA specialization without changing the deterministic game architecture.

---

## 42. Local GGUF Recognition, Variant Matching & Classification Levels

### 42.1 Verification Beyond Filename

When local GGUF files are scanned or presented for import:
1. **Filename Insufficiency:** A filename (e.g. `qwen2.5-9b-instruct-q4_k_m.gguf`) is treated as a **non-binding label** and never used as sole proof of compatibility or integrity.
2. **Deep Header Inspection:** `ModelInspector` parses GGUF binary headers to extract:
   - GGUF magic bytes (`0x46554747`) & header version;
   - Model architecture (e.g. `qwen2`, `llama`);
   - Quantization format (e.g. `Q4_K_M`, `Q8_0`);
   - Context length capability (`context_length`);
   - Chat template presence (`tokenizer.chat_template`).
3. **Integrity Hash Check:** `IntegrityVerifier` computes SHA-256 for exact matching against manifest variants.

### 42.2 Classification Levels

Every inspected local file is assigned one of six normative classification levels:

1. **`exactVerifiedMatch`:**
   - SHA-256 digest matches an active variant in the official manifest.
   - **Status:** Fully verified. Eligible for direct managed store adoption (`importedManaged`).
2. **`compatibleKnownVariant`:**
   - Header metadata matches a known variant architecture and quantization, but SHA-256 differs (e.g. custom re-quantization or patch).
   - **Status:** Compatible known variant. Eligible for managed import or external binding with UI notification.
3. **`compatibleUnverifiedImport`:**
   - Valid GGUF header compatible with A.U.R.A. logical role requirements (`evaluator` or `actor`), but unlisted in manifest.
   - **Status:** Unverified import. Permitted for external binding (`externalLocal`) or manual import with explanatory user warning.
4. **`externallyOwnedBinding`:**
   - File resides outside managed store and is bound directly without copying.
   - **Status:** External binding. Non-managed, read-only lifecycle.
5. **`incompatible`:**
   - Header reveals unsupported architecture, missing chat template, or insufficient context capability.
   - **Status:** Hard-blocked from loading.
6. **`unknownReviewRequired`:**
   - Corrupted file, invalid GGUF magic bytes, or unreadable structure.
   - **Status:** Hard-blocked; flagged for manual review or deletion.

### 42.3 Managed Store Eligibility Matrix

| Classification Level | Managed Store Import (`importedManaged`) | External Binding (`externalLocal`) | Auto-Update / Repair |
| :--- | :--- | :--- | :--- |
| `exactVerifiedMatch` | **Allowed** (Full managed status) | **Allowed** | **Enabled** |
| `compatibleKnownVariant` | **Allowed** (With notification) | **Allowed** | **Manual only** |
| `compatibleUnverifiedImport` | **Allowed** (With warning) | **Allowed** | **Disabled** |
| `externallyOwnedBinding` | N/A | **Active** | **Disabled** |
| `incompatible` | **Prohibited** | **Prohibited** | N/A |
| `unknownReviewRequired` | **Prohibited** | **Prohibited** | N/A |
