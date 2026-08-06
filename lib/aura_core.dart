library aura_core;

// Models & Core Controller
export 'src/models/game_state.dart';
export 'src/models/user_profile.dart';
export 'src/models/victory_readiness.dart';
export 'src/models/deception_state.dart';
export 'src/models/evaluator_delta.dart';
export 'src/models/evaluator_run_result.dart';
export 'src/models/applied_delta.dart';
export 'src/models/evaluator_resolution.dart';
export 'src/models/actor_cue.dart';
export 'src/models/turn_input.dart';
export 'src/models/actor_input.dart';
export 'src/models/difficulty_config.dart';
export 'src/models/objective_definition.dart';
export 'src/models/identity_definition.dart';
export 'src/models/trait_matrix_definition.dart';
export 'src/models/turn_visual_events.dart';
export 'src/models/trait_resolution.dart';
export 'src/game_controller.dart';
export 'src/hint_resolver.dart';
export 'src/command/turn_command.dart';
export 'src/models/override_status.dart';
export 'src/models/override_ineligibility_reason.dart';
export 'src/models/override_resolution.dart';
export 'src/override/override_resolver.dart';
export 'src/replay_logger.dart';
export 'src/constants.dart';

// Desktop Shell Contracts
export 'src/desktop_shell/window_mode.dart';
export 'src/desktop_shell/window_geometry.dart';
export 'src/desktop_shell/window_preferences.dart';
export 'src/desktop_shell/display_descriptor.dart';
export 'src/desktop_shell/desktop_window_event.dart';
export 'src/desktop_shell/desktop_window_controller.dart';
export 'src/desktop_shell/window_geometry_validator.dart';
export 'src/desktop_shell/window_preferences_repository.dart';
export 'src/desktop_shell/window_geometry_persistence_coordinator.dart';

// Audio Domain Contracts (Phase 6.7)
export 'src/audio/audio_manifest.dart';
export 'src/audio/wav_header_verifier.dart';
export 'src/audio/audio_import_engine.dart';

// Agent Runtime Base
export 'src/agent_runtime/agent_card.dart';
export 'src/agent_runtime/inference_bridge.dart';
export 'src/agent_runtime/prompt_builder.dart';
export 'src/agent_runtime/output_validator.dart';
export 'src/agent_runtime/config_loader.dart';
export 'src/agent_runtime/semantic_matcher.dart';
export 'src/agent_runtime/trait_effect_resolver.dart';
export 'src/agent_runtime/config_source.dart';
export 'src/agent_runtime/config_diagnostic.dart';
export 'src/agent_runtime/config_diagnostic_sink.dart';
export 'src/agent_runtime/config_exception.dart';
export 'src/agent_runtime/validators/panopticon_tone_validator.dart';
export 'src/agent_runtime/inference_timeouts.dart';
export 'src/agent_runtime/inference_timeout_exception.dart';

// Inference Runtime Contracts (Phase 6)
export 'src/agent_runtime/runtime/inference_runtime.dart';
export 'src/agent_runtime/runtime/runtime_state.dart';
export 'src/agent_runtime/runtime/runtime_capabilities.dart';
export 'src/agent_runtime/runtime/runtime_health.dart';
export 'src/agent_runtime/runtime/runtime_backend.dart';
export 'src/agent_runtime/runtime/runtime_failure.dart';
export 'src/agent_runtime/runtime/model_handle.dart';
export 'src/agent_runtime/runtime/runtime_ids.dart';
export 'src/agent_runtime/runtime/runtime_requests.dart';
export 'src/agent_runtime/runtime/runtime_results.dart';
export 'src/agent_runtime/runtime/runtime_events.dart';

// Managed llama-server Contracts & DTOs (Phase 6.2b)
export 'src/provisioning/domain/runtime_dependency_models.dart';
export 'src/agent_runtime/runtime/adapters/managed_llama_server/managed_llama_server_failure.dart';
export 'src/agent_runtime/runtime/adapters/managed_llama_server/managed_llama_server_configuration.dart';
export 'src/agent_runtime/runtime/adapters/managed_llama_server/process_launcher.dart';
export 'src/agent_runtime/runtime/adapters/managed_llama_server/port_allocator.dart';
export 'src/agent_runtime/runtime/adapters/managed_llama_server/llama_server_health_probe.dart';
export 'src/agent_runtime/runtime/adapters/managed_llama_server/llama_server_process_supervisor.dart';

// Concrete Agents Base
export 'src/agent_runtime/agents/aura_agent.dart';

// Deception Layer
export 'src/deception/deception_evaluator.dart';
export 'src/deception/deception_evaluation.dart';

// Lexical Tag Evaluator
export 'src/lexical/lexical_tag_evaluator.dart';
export 'src/lexical/lexical_scan_result.dart';
export 'src/lexical/hidden_tag_evaluation.dart';

// Application Composition Root & Bootstrap Contracts (Phase 6.2a)
export 'src/bootstrap/application_runtime_mode.dart';
export 'src/bootstrap/application_runtime_configuration.dart';
export 'src/bootstrap/application_bootstrap_request.dart';
export 'src/bootstrap/application_bootstrap_result.dart';
export 'src/bootstrap/application_bootstrap.dart';
export 'src/bootstrap/application_bootstrap_failure.dart';

// Provisioning Domain & Infrastructure Contracts (Phase 6.3a & 6.3b)
export 'src/provisioning/domain/catalog_manifest.dart';
export 'src/provisioning/domain/provisioning_options.dart';
export 'src/provisioning/domain/provisioning_cancellation_token.dart';
export 'src/provisioning/domain/json_safe_value.dart';
export 'src/provisioning/domain/provisioning_clock.dart';
export 'src/provisioning/domain/installation_record.dart';
export 'src/provisioning/domain/activation_state.dart';
export 'src/provisioning/validation/catalog_manifest_parser.dart';
export 'src/provisioning/validation/catalog_manifest_validator.dart';
export 'src/provisioning/validation/installed_artifact_verifier.dart';
export 'src/provisioning/infrastructure/provisioning_path_resolver.dart';
export 'src/provisioning/infrastructure/provisioning_file_system.dart';
export 'src/provisioning/infrastructure/provisioning_io_exception.dart';
export 'src/provisioning/infrastructure/provisioning_lock.dart';
export 'src/provisioning/infrastructure/provisioning_http_client.dart';
export 'src/provisioning/infrastructure/archive_extractor.dart';
export 'src/provisioning/infrastructure/sha256_verifier.dart';
export 'src/provisioning/infrastructure/atomic_artifact_installer.dart';
export 'src/provisioning/infrastructure/artifact_ingestion_engine.dart';
export 'src/provisioning/infrastructure/installation_record_repository.dart';
export 'src/provisioning/infrastructure/activation_state_repository.dart';
export 'src/provisioning/infrastructure/provisioning_coordinator.dart';

// Provisioning Resolvers, Bootstrap & CLI (Phase 6.3e)
export 'src/provisioning/resolvers/model_resolver.dart';
export 'src/provisioning/resolvers/runtime_resolver.dart';

// Provisioning Acquisition Domain & Trust Model (Phase 6.4a)
export 'src/provisioning/domain/catalog_acquisition_models.dart';
export 'src/provisioning/domain/catalog_acquisition_exceptions.dart';
export 'src/provisioning/domain/immutable_repository_revision_policy.dart';
export 'src/provisioning/domain/catalog_compatibility_evaluator.dart';
export 'src/provisioning/domain/validated_catalog_candidate.dart';
export 'src/provisioning/domain/validated_catalog_candidate_factory.dart';
export 'src/provisioning/domain/catalog_selection_policy.dart';
export 'src/provisioning/validation/catalog_validation_service.dart';
export 'src/provisioning/crypto/catalog_public_key.dart';

export 'src/provisioning/bootstrap/provisioning_bootstrap_service.dart';
export 'src/provisioning/cli/provisioning_cli_runner.dart';

// Provisioning Catalog Providers, Signed Cache & Refresh (Phase 6.4b)
export 'src/provisioning/domain/catalog_refresh_policy.dart';
export 'src/provisioning/domain/catalog_provider_contracts.dart';
export 'src/provisioning/crypto/catalog_signature_verifier.dart';
export 'src/provisioning/crypto/catalog_trust_store.dart';
export 'src/provisioning/crypto/bundled_catalog_trust_store.dart';
export 'src/provisioning/crypto/rfc8785_jcs_canonicalizer.dart';
export 'src/provisioning/infrastructure/catalog_cache_repository.dart';
export 'src/provisioning/infrastructure/lkg_catalog_metadata_repository.dart';
export 'src/provisioning/infrastructure/bundled_catalog_provider.dart';
export 'src/provisioning/infrastructure/cached_catalog_provider.dart';
export 'src/provisioning/infrastructure/remote_catalog_provider.dart';
export 'src/provisioning/infrastructure/catalog_acquisition_coordinator.dart';
export 'src/provisioning/infrastructure/catalog_refresh_service.dart';

// Provisioning Download Engine, HTTP Range Resume & Staging (Phase 6.4c)
export 'src/provisioning/domain/download_request.dart';
export 'src/provisioning/domain/download_checkpoint.dart';
export 'src/provisioning/domain/staging_artifact.dart';
export 'src/provisioning/domain/download_progress.dart';
export 'src/provisioning/domain/download_result.dart';
export 'src/provisioning/domain/download_cancellation_token.dart';
export 'src/provisioning/infrastructure/artifact_download_engine.dart';
