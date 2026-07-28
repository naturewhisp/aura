library aura_offline;

export 'aura_core.dart';

// Concrete Agents & Registries
export 'src/agent_runtime/agent_card.dart';
export 'src/agent_runtime/message_envelope.dart';
export 'src/agent_runtime/agent_registry.dart';
export 'src/agent_runtime/model_catalog.dart';
export 'src/agent_runtime/model_router.dart';
export 'src/agent_runtime/agents/evaluator_agent.dart';
export 'src/agent_runtime/agents/actor_agent.dart';

// Inference Bridges & Runtime Adapters
export 'src/agent_runtime/bridges/rule_based_evaluator_bridge.dart';
export 'src/agent_runtime/bridges/local_api_inference_bridge.dart';
export 'src/agent_runtime/bridges/runtime_inference_bridge.dart';
export 'src/agent_runtime/runtime/adapters/rule_based_inference_runtime.dart';
export 'src/agent_runtime/runtime/adapters/external_openai/external_openai_runtime.dart';
export 'src/agent_runtime/runtime/adapters/external_openai/external_openai_configuration.dart';
export 'src/agent_runtime/runtime/adapters/external_openai/external_openai_model_binding.dart';
export 'src/agent_runtime/runtime/adapters/external_openai/external_openai_client.dart';

// Managed llama-server Implementations (Phase 6.2b)
export 'src/agent_runtime/runtime/adapters/managed_llama_server/llama_server_command_builder.dart';
export 'src/agent_runtime/runtime/adapters/managed_llama_server/dart_io_process_launcher.dart';
export 'src/agent_runtime/runtime/adapters/managed_llama_server/managed_llama_server_runtime.dart';

// Output Policy Components
export 'src/agent_runtime/output/actor_output_extraction_strategy.dart';
export 'src/agent_runtime/output/actor_output_sanitizer.dart';
export 'src/agent_runtime/output/actor_output_sanitization_request.dart';
export 'src/agent_runtime/output/actor_output_sanitization_result.dart';
export 'src/agent_runtime/output/character_set_guard.dart';
export 'src/agent_runtime/output/duplicate_response_guard.dart';
export 'src/agent_runtime/output/output_policy_failure.dart';
export 'src/agent_runtime/output/reasoning_content_policy.dart';

// Application Composition Root Factory & Implementations (Phase 6.2a)
export 'src/bootstrap/application_bootstrap_factory.dart';
export 'src/bootstrap/default_application_bootstrap.dart';

// Provisioning Catalog Providers, Signed Cache & Refresh (Phase 6.4b)
export 'src/provisioning/crypto/rfc8785_jcs_canonicalizer.dart';
export 'src/provisioning/crypto/catalog_trust_store.dart';
export 'src/provisioning/crypto/catalog_signature_verifier.dart';

// Provisioning Download Engine Infrastructure (Phase 6.4c)
export 'src/provisioning/infrastructure/download_checkpoint_repository.dart';
export 'src/provisioning/infrastructure/download_concurrency_controller.dart';

// Provisioning Ingestion & Service Infrastructure (Phase 6.4d)
export 'src/provisioning/domain/catalog_artifact_snapshot.dart';
export 'src/provisioning/infrastructure/provisioning_path_resolver.dart'
    show ProvisioningPathResolver;
export 'src/provisioning/infrastructure/model_provisioning_service.dart'
    show
        ModelProvisioningService,
        ProvisioningEnvironment,
        LocalArtifactImportRequest,
        ModelProvisioningPhase;
// ArtifactImportInspector, LocalGgufInspectionResult sono ri-esportati via model_provisioning_service.dart
// attraverso il metodo applicativo inspectLocalArtifact. Non esposti come tipi diretti.
export 'src/provisioning/validation/artifact_import_inspector.dart'
    show LocalGgufInspectionResult;

// Provisioning Model Lifecycle (Phase 6.4e)
export 'src/provisioning/domain/model_lifecycle_models.dart';
export 'src/provisioning/domain/release_version_comparer.dart';

// Provisioning Runtime & Model Configuration (Phase 6.4f)
export 'src/provisioning/domain/configured_model_reference.dart';
export 'src/provisioning/domain/local_inference_preflight_models.dart';
export 'src/provisioning/domain/model_configuration_models.dart';
export 'src/provisioning/domain/runtime_dependency_models.dart';
export 'src/provisioning/infrastructure/json_model_configuration_repository.dart';
