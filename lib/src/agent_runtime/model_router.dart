import 'package:meta/meta.dart';
import 'model_catalog.dart';

/// Rappresenta la risoluzione e associazione dei modelli per gli agenti Valutatore (Evaluator) e Attore (Actor).
@immutable
class ModelRouterResolution {
  /// L'identificatore del modello assegnato al Valutatore.
  final String evaluatorModelId;

  /// L'identificatore del modello assegnato all'Attore.
  final String actorModelId;

  /// Il nome del profilo di allocazione risultante (es. 'P1: Standard (Performante)').
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

/// Router dinamico dei modelli che assegna i modelli ottimali caricati al Valutatore e all'Attore.
///
/// Risolve l'allocazione basandosi sui modelli attivi rilevati e sulle raccomandazioni del catalogo.
class ModelRouter {
  const ModelRouter();

  /// Risolve l'allocazione ottimale dei modelli partendo dall'elenco dei modelli attualmente caricati ed il catalogo.
  ModelRouterResolution resolve({
    required List<String> loadedModelIds,
    required ModelCatalog catalog,
  }) {
    if (loadedModelIds.isEmpty) {
      // Fallback in modalità offline o generica
      return const ModelRouterResolution(
        evaluatorModelId: "mistralai/ministral-3-3b",
        actorModelId: "qwen/qwen3.5-9b",
        profileName: "Offline Fallback",
      );
    }

    // P3: Profilo Mono-Model (quando è caricato un solo modello nel backend)
    if (loadedModelIds.length == 1) {
      final singleModel = loadedModelIds.first;
      return ModelRouterResolution(
        evaluatorModelId: singleModel,
        actorModelId: singleModel,
        profileName: "P3: Mono-Model (Risparmio)",
      );
    }

    // Tenta di associare i modelli caricati con i metadati del catalogo
    String? matchedEvaluator;
    String? matchedActor;

    // 1. Risoluzione del modello per il Valutatore (Evaluator)
    // Cerca una corrispondenza esatta o parziale nel catalogo che raccomandi "evaluator"
    for (var id in loadedModelIds) {
      final entry =
          catalog.findModel(id) ?? _findCatalogEntryBySubstring(id, catalog);
      if (entry != null && entry.recommendedAgents.contains("evaluator")) {
        matchedEvaluator = id;
        break;
      }
    }

    // Ricerca secondaria per parole chiave "mistral" o "ministral" nei nomi
    if (matchedEvaluator == null) {
      for (var id in loadedModelIds) {
        if (id.toLowerCase().contains("mistral") ||
            id.toLowerCase().contains("ministral")) {
          matchedEvaluator = id;
          break;
        }
      }
    }

    // Fallback finale per il Valutatore: seleziona il primo modello caricato
    matchedEvaluator ??= loadedModelIds.first;

    // 2. Risoluzione del modello per l'Attore (Actor)
    // Cerca una corrispondenza esatta o parziale nel catalogo che raccomandi "actor"
    for (var id in loadedModelIds) {
      if (id == matchedEvaluator && loadedModelIds.length > 1) {
        // Se possibile, preferisce assegnare un modello diverso
        continue;
      }
      final entry =
          catalog.findModel(id) ?? _findCatalogEntryBySubstring(id, catalog);
      if (entry != null && entry.recommendedAgents.contains("actor")) {
        matchedActor = id;
        break;
      }
    }

    // Ricerca secondaria per parole chiave "qwen", "gemma" o "llama" nei nomi
    if (matchedActor == null) {
      for (var id in loadedModelIds) {
        if (id == matchedEvaluator && loadedModelIds.length > 1) continue;
        final lower = id.toLowerCase();
        if (lower.contains("qwen") ||
            lower.contains("gemma") ||
            lower.contains("llama")) {
          matchedActor = id;
          break;
        }
      }
    }

    // Fallback finale per l'Attore: seleziona il primo modello differente dal valutatore
    if (matchedActor == null) {
      matchedActor = loadedModelIds.firstWhere(
        (id) => id != matchedEvaluator,
        orElse: () => loadedModelIds.last,
      );
    }

    // 3. Determina il nome del profilo di allocazione risultante
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

  /// Funzione di supporto per cercare una voce nel catalogo tramite corrispondenza parziale dell'ID.
  ModelCatalogEntry? _findCatalogEntryBySubstring(
      String loadedId, ModelCatalog catalog) {
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
