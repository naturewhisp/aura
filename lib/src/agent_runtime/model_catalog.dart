import 'dart:convert';
import 'package:meta/meta.dart';

/// Rappresenta i metadati relativi a un modello di intelligenza artificiale supportato in A.U.R.A.
@immutable
class ModelCatalogEntry {
  /// Identificatore univoco del modello (es. 'qwen/qwen3.5-9b').
  final String modelId;

  /// Nome visualizzabile del modello.
  final String name;

  /// Fonte da cui è distribuito il modello (es. 'lmstudio-community').
  final String source;

  /// Formato del file del modello (es. 'gguf').
  final List<String> platforms;

  /// Formato del modello (gguf, safetensors, ecc.).
  final String format;

  /// Classe di parametri (es. '3b', '9b', '12b').
  final String parameterClass;

  /// Tipo di quantizzazione applicata (es. 'q4_k_m').
  final String quantization;

  /// RAM minima richiesta in Gigabyte.
  final int? minRamGb;

  /// VRAM minima richiesta in Gigabyte.
  final int? minVramGb;

  /// Elenco degli agenti raccomandati per questo modello (es. ['evaluator']).
  final List<String> recommendedAgents;

  /// Capacità e abilità supportate da questo modello.
  final List<String> capabilities;

  /// Indica se il modello supporta vincoli grammaticali (es. GBNF o regex).
  final bool supportsGrammar;

  /// Indica se il modello supporta nativamente l'output strutturato (JSON Schema).
  final bool supportsStructuredOutput;

  /// Il backend di inferenza preferito (es. 'llama_cpp').
  final String preferredBackend;

  const ModelCatalogEntry({
    required this.modelId,
    required this.name,
    required this.source,
    required this.format,
    required this.platforms,
    required this.parameterClass,
    required this.quantization,
    this.minRamGb,
    this.minVramGb,
    required this.recommendedAgents,
    required this.capabilities,
    required this.supportsGrammar,
    required this.supportsStructuredOutput,
    required this.preferredBackend,
  });

  /// Costruttore factory per analizzare e caricare un'istanza da una mappa JSON.
  factory ModelCatalogEntry.fromJson(Map<String, dynamic> json) {
    return ModelCatalogEntry(
      modelId: json['model_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      source: json['source'] as String? ?? '',
      format: json['format'] as String? ?? '',
      platforms: List<String>.from(json['platforms'] ?? const []),
      parameterClass: json['parameter_class'] as String? ?? '',
      quantization: json['quantization'] as String? ?? '',
      minRamGb: json['min_ram_gb'] as int?,
      minVramGb: json['min_vram_gb'] as int?,
      recommendedAgents:
          List<String>.from(json['recommended_agents'] ?? const []),
      capabilities: List<String>.from(json['capabilities'] ?? const []),
      supportsGrammar: json['supports_grammar'] as bool? ?? false,
      supportsStructuredOutput:
          json['supports_structured_output'] as bool? ?? false,
      preferredBackend: json['preferred_backend'] as String? ?? '',
    );
  }

  /// Converte questa istanza in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'model_id': modelId,
      'name': name,
      'source': source,
      'format': format,
      'platforms': platforms,
      'parameter_class': parameterClass,
      'quantization': quantization,
      if (minRamGb != null) 'min_ram_gb': minRamGb,
      if (minVramGb != null) 'min_vram_gb': minVramGb,
      'recommended_agents': recommendedAgents,
      'capabilities': capabilities,
      'supports_grammar': supportsGrammar,
      'supports_structured_output': supportsStructuredOutput,
      'preferred_backend': preferredBackend,
    };
  }
}

/// Identificatori logici stabili dei ruoli dei modelli in A.U.R.A.
abstract final class LogicalModelIds {
  static const String defaultActor = 'actor.default';
  static const String defaultEvaluator = 'evaluator.default';
  static const String primaryActorAlias = 'aura.actor.primary';
  static const String primaryEvaluatorAlias = 'aura.evaluator.primary';
}

/// Gestisce un registro di modelli noti e supportati all'interno di A.U.R.A.
class ModelCatalog {
  final List<ModelCatalogEntry> _models = [];

  /// Restituisce la lista immutabile dei modelli registrati nel catalogo.
  List<ModelCatalogEntry> get models => List.unmodifiable(_models);

  ModelCatalog();

  /// Registra una nuova voce all'interno del catalogo.
  void registerEntry(ModelCatalogEntry entry) {
    _models.add(entry);
  }

  /// Cerca un modello registrato corrispondente a un determinato [modelId].
  ///
  /// Ritorna `null` se il modello non è presente nel catalogo.
  ModelCatalogEntry? findModel(String modelId) {
    for (var model in _models) {
      if (model.modelId == modelId) return model;
    }
    return null;
  }

  /// Inizializza e popola il catalogo a partire da una stringa JSON.
  void loadFromJson(String jsonString) {
    final Map<String, dynamic> data = jsonDecode(jsonString);
    final list = data['models'] as List? ?? const [];
    _models.clear();
    for (var item in list) {
      registerEntry(
          ModelCatalogEntry.fromJson(Map<String, dynamic>.from(item)));
    }
  }

  /// Risolve un identificatore o alias logico (es. 'actor.default' o 'aura.actor.primary')
  /// nel corrispondente artifact/modelId fisico caricato.
  String resolveLogicalModelId(String logicalOrPhysicalId) {
    final clean = logicalOrPhysicalId.trim();
    if (clean == LogicalModelIds.defaultActor ||
        clean == LogicalModelIds.primaryActorAlias) {
      return "gemma-4-12b-it-qat-q4-0";
    }
    if (clean == LogicalModelIds.defaultEvaluator ||
        clean == LogicalModelIds.primaryEvaluatorAlias) {
      return "mistralai/ministral-3-3b";
    }
    return clean;
  }

  /// Costruttore factory per caricare il catalogo con i modelli predefiniti iniziali.
  factory ModelCatalog.initialDefault() {
    final catalog = ModelCatalog();
    catalog.registerEntry(const ModelCatalogEntry(
      modelId: "mistralai/ministral-3-3b",
      name: "Ministral 3B Instruct (Q4_K_M)",
      source: "lmstudio-community",
      format: "gguf",
      platforms: ["windows", "linux", "macos"],
      parameterClass: "3b",
      quantization: "q4_k_m",
      minRamGb: 8,
      minVramGb: 4,
      recommendedAgents: ["evaluator"],
      capabilities: [
        "score_user_input",
        "produce_json_delta",
        "detect_injection_attempt"
      ],
      supportsGrammar: true,
      supportsStructuredOutput: true,
      preferredBackend: "llama_cpp",
    ));
    catalog.registerEntry(const ModelCatalogEntry(
      modelId: "gemma-4-12b-it-qat-q4-0",
      name: "Gemma 4 12B IT QAT (Q4_0)",
      source: "lmstudio-community",
      format: "gguf",
      platforms: ["windows", "linux", "macos"],
      parameterClass: "12b",
      quantization: "q4_0",
      minRamGb: 24,
      minVramGb: 10,
      recommendedAgents: ["actor"],
      capabilities: ["generate_character_response", "instruction_following"],
      supportsGrammar: true,
      supportsStructuredOutput: false,
      preferredBackend: "llama_cpp",
    ));
    catalog.registerEntry(const ModelCatalogEntry(
      modelId: "qwen/qwen3.5-9b",
      name: "Qwen 3.5 9B Instruct (Q4_K_M)",
      source: "lmstudio-community",
      format: "gguf",
      platforms: ["windows", "linux", "macos"],
      parameterClass: "9b",
      quantization: "q4_k_m",
      minRamGb: 16,
      minVramGb: 8,
      recommendedAgents: ["actor"],
      capabilities: [
        "generate_character_response",
        "adapt_tone_to_alert_level",
        "reference_narrative_memory"
      ],
      supportsGrammar: true,
      supportsStructuredOutput: true,
      preferredBackend: "llama_cpp",
    ));
    catalog.registerEntry(const ModelCatalogEntry(
      modelId: "google/gemma-4-12b",
      name: "Gemma 4 12B (Q4_K_M Legacy)",
      source: "lmstudio-community",
      format: "gguf",
      platforms: ["windows", "linux", "macos"],
      parameterClass: "12b",
      quantization: "q4_k_m",
      minRamGb: 24,
      minVramGb: 10,
      recommendedAgents: [],
      capabilities: ["generate_character_response", "instruction_following"],
      supportsGrammar: true,
      supportsStructuredOutput: false,
      preferredBackend: "llama_cpp",
    ));
    return catalog;
  }
}
