import 'package:meta/meta.dart';
import 'model_catalog.dart';

/// Represents the resolved mapping of models for Evaluator and Actor agents.
@immutable
class ModelRouterResolution {
  final String evaluatorModelId;
  final String actorModelId;
  final String profileName;

  const ModelRouterResolution({
    required this.evaluatorModelId,
    required this.actorModelId,
    required this.profileName,
  });

  @override
  String toString() {
    return 'ModelRouterResolution(evaluator: $evaluatorModelId, actor: $actorModelId, profile: $profileName)';
  }
}

/// Dynamic Model Router that assigns the optimal loaded models to Evaluator and Actor.
class ModelRouter {
  const ModelRouter();

  /// Resolves the optimal models from the list of loaded model IDs and the catalog.
  ModelRouterResolution resolve({
    required List<String> loadedModelIds,
    required ModelCatalog catalog,
  }) {
    if (loadedModelIds.isEmpty) {
      // Offline or generic fallback
      return const ModelRouterResolution(
        evaluatorModelId: "mistralai/ministral-3-3b",
        actorModelId: "qwen/qwen3.5-9b",
        profileName: "Offline Fallback",
      );
    }

    // P3: Mono-Model Profile (only 1 model is loaded in the backend)
    if (loadedModelIds.length == 1) {
      final singleModel = loadedModelIds.first;
      return ModelRouterResolution(
        evaluatorModelId: singleModel,
        actorModelId: singleModel,
        profileName: "P3: Mono-Model (Risparmio)",
      );
    }

    // Attempt to match loaded IDs with catalog metadata
    String? matchedEvaluator;
    String? matchedActor;

    // 1. Resolve Evaluator Model
    // Try exact or substring match in catalog recommending "evaluator"
    for (var id in loadedModelIds) {
      final entry = catalog.findModel(id) ?? _findCatalogEntryBySubstring(id, catalog);
      if (entry != null && entry.recommendedAgents.contains("evaluator")) {
        matchedEvaluator = id;
        break;
      }
    }

    // Secondary fallback search for mistral/ministral in names
    if (matchedEvaluator == null) {
      for (var id in loadedModelIds) {
        if (id.toLowerCase().contains("mistral") || id.toLowerCase().contains("ministral")) {
          matchedEvaluator = id;
          break;
        }
      }
    }

    // Tertiary fallback: pick first loaded model
    matchedEvaluator ??= loadedModelIds.first;

    // 2. Resolve Actor Model
    // Try exact or substring match in catalog recommending "actor"
    for (var id in loadedModelIds) {
      if (id == matchedEvaluator && loadedModelIds.length > 1) {
        // Prefer assigning a different model if possible
        continue;
      }
      final entry = catalog.findModel(id) ?? _findCatalogEntryBySubstring(id, catalog);
      if (entry != null && entry.recommendedAgents.contains("actor")) {
        matchedActor = id;
        break;
      }
    }

    // Secondary fallback search for qwen/gemma/llama in names
    if (matchedActor == null) {
      for (var id in loadedModelIds) {
        if (id == matchedEvaluator && loadedModelIds.length > 1) continue;
        final lower = id.toLowerCase();
        if (lower.contains("qwen") || lower.contains("gemma") || lower.contains("llama")) {
          matchedActor = id;
          break;
        }
      }
    }

    // Tertiary fallback: pick the last model that is different from evaluator
    if (matchedActor == null) {
      matchedActor = loadedModelIds.firstWhere(
        (id) => id != matchedEvaluator,
        orElse: () => loadedModelIds.last,
      );
    }

    // 3. Determine allocation profile name
    String profile = "Custom Profile";
    final isEvalMistral = matchedEvaluator.toLowerCase().contains("mistral") ||
        matchedEvaluator.toLowerCase().contains("ministral");
    final isActorQwen = matchedActor.toLowerCase().contains("qwen");
    final isActorGemma = matchedActor.toLowerCase().contains("gemma");

    if (matchedEvaluator == matchedActor) {
      profile = "P3: Mono-Model (Risparmio)";
    } else if (isEvalMistral && isActorQwen) {
      profile = "P1: Standard (Performante)";
    } else if (isEvalMistral && isActorGemma) {
      profile = "P2: Deep Reasoning";
    }

    return ModelRouterResolution(
      evaluatorModelId: matchedEvaluator,
      actorModelId: matchedActor,
      profileName: profile,
    );
  }

  /// Helper to find catalog entry by partial ID matching.
  ModelCatalogEntry? _findCatalogEntryBySubstring(String loadedId, ModelCatalog catalog) {
    final lowerId = loadedId.toLowerCase();
    for (var entry in catalog.models) {
      if (lowerId.contains(entry.modelId.toLowerCase()) || 
          entry.modelId.toLowerCase().contains(lowerId)) {
        return entry;
      }
    }
    return null;
  }
}
