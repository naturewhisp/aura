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
export 'src/agent_runtime/agents/actor_inference_logger.dart';

// Inference Bridges & Runtime Adapters
export 'src/agent_runtime/bridges/rule_based_evaluator_bridge.dart';
export 'src/agent_runtime/bridges/local_api_inference_bridge.dart';
export 'src/agent_runtime/bridges/runtime_inference_bridge.dart';
export 'src/agent_runtime/bridges/dual_model_inference_bridge.dart';
export 'src/agent_runtime/runtime/adapters/rule_based_inference_runtime.dart';
export 'src/agent_runtime/runtime/adapters/external_openai/external_openai_runtime.dart';
export 'src/agent_runtime/runtime/adapters/external_openai/external_openai_configuration.dart';
export 'src/agent_runtime/runtime/adapters/external_openai/external_openai_model_binding.dart';
export 'src/agent_runtime/runtime/adapters/external_openai/external_openai_client.dart';

// Managed llama-server Implementations (Phase 6.2b)
export 'src/agent_runtime/runtime/adapters/managed_llama_server/llama_runtime_launch_environment_resolver.dart';
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
export 'src/bootstrap/managed_inference_topology.dart';

// Provisioning Catalog Providers, Signed Cache & Refresh (Phase 6.4b)
export 'src/provisioning/crypto/rfc8785_jcs_canonicalizer.dart';
export 'src/provisioning/crypto/catalog_trust_store.dart';
export 'src/provisioning/crypto/catalog_signature_verifier.dart';

// Provisioning Download Engine Infrastructure (Phase 6.4c)
export 'src/provisioning/infrastructure/download_checkpoint_repository.dart';
export 'src/provisioning/infrastructure/download_concurrency_controller.dart';

// Provisioning Ingestion & Service Infrastructure (Phase 6.4d)
export 'src/provisioning/domain/runtime_manifest.dart';
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
export 'src/provisioning/application/first_run_model_setup_facade.dart';
export 'src/provisioning/application/inference_bootstrap_bridge.dart';
export 'src/provisioning/application/local_inference_facade.dart';
export 'src/provisioning/application/local_inference_models.dart';
export 'src/provisioning/application/local_inference_status_notifier.dart';
export 'src/provisioning/application/runtime_model_settings_facade.dart';
export 'src/provisioning/infrastructure/json_model_configuration_repository.dart';
export 'src/provisioning/infrastructure/llama_server_dependency_service.dart';
export 'src/provisioning/infrastructure/local_inference_preflight_engine.dart';
export 'src/provisioning/infrastructure/model_configuration_service.dart';
export 'src/provisioning/infrastructure/process_ownership_record.dart';
export 'src/provisioning/infrastructure/process_ownership_registry.dart';
export 'src/provisioning/infrastructure/winget_dependency_adapter.dart';
export 'src/provisioning/cli/aura_cli_environment.dart';
export 'src/provisioning/cli/local_inference_cli_runner.dart';
export 'src/provisioning/cli/local_inference_service_provider.dart';
