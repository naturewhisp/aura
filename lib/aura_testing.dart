library aura_testing;

export 'aura_core.dart';

// Concrete Agents used in testing fallback scenarios
export 'src/agent_runtime/agents/evaluator_agent.dart';
export 'src/agent_runtime/agents/actor_agent.dart';

// Inference Bridges & Testing Runtime Mocks
export 'src/agent_runtime/bridges/mock_inference_bridge.dart';
export 'src/agent_runtime/bridges/rule_based_evaluator_bridge.dart';
export 'src/agent_runtime/runtime/testing/mock_inference_runtime.dart';
export 'src/agent_runtime/runtime/adapters/external_openai/external_openai_client.dart';

// Managed llama-server Testing Fakes (Phase 6.2b)
export 'src/testing/fake_llama_server_environment.dart';

// Provisioning Acquisition Mocks (Phase 6.4a)
export 'src/provisioning/crypto/catalog_trust_store.dart';
export 'src/provisioning/crypto/catalog_signature_verifier.dart';

// Provisioning Ingestion Engine & Internal Testing Types (Phase 6.4d)
// Esportati SOLO tramite aura_testing.dart per i test unitari dell'engine.
// Non fanno parte dell'API pubblica di aura_offline.dart.
export 'src/provisioning/infrastructure/single_pass_artifact_ingestion_engine.dart'
    show
        SinglePassArtifactIngestionEngine,
        ArtifactSourceOwnership,
        QuarantineStatus,
        PreparedArtifactInstallation;
export 'src/provisioning/validation/artifact_import_inspector.dart';
