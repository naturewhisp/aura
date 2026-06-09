import 'dart:convert';
import 'package:meta/meta.dart';

/// Metadata entry representing a supported AI model in A.U.R.A.
@immutable
class ModelCatalogEntry {
  final String modelId;
  final String name;
  final String source;
  final String format;
  final List<String> platforms;
  final String parameterClass;
  final String quantization;
  final int? minRamGb;
  final int? minVramGb;
  final List<String> recommendedAgents;
  final List<String> capabilities;
  final bool supportsGrammar;
  final bool supportsStructuredOutput;
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

  /// Factory to parse from a JSON map.
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
      recommendedAgents: List<String>.from(json['recommended_agents'] ?? const []),
      capabilities: List<String>.from(json['capabilities'] ?? const []),
      supportsGrammar: json['supports_grammar'] as bool? ?? false,
      supportsStructuredOutput: json['supports_structured_output'] as bool? ?? false,
      preferredBackend: json['preferred_backend'] as String? ?? '',
    );
  }

  /// Converts to JSON map.
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

/// Holds a registry of known supported models.
class ModelCatalog {
  final List<ModelCatalogEntry> _models = [];

  List<ModelCatalogEntry> get models => List.unmodifiable(_models);

  ModelCatalog();

  /// Registers a new entry in the catalog.
  void registerEntry(ModelCatalogEntry entry) {
    _models.add(entry);
  }

  /// Searches for a model matching a specific ID.
  ModelCatalogEntry? findModel(String modelId) {
    for (var model in _models) {
      if (model.modelId == modelId) return model;
    }
    return null;
  }

  /// Initializes the catalog from a JSON string.
  void loadFromJson(String jsonString) {
    final Map<String, dynamic> data = jsonDecode(jsonString);
    final list = data['models'] as List? ?? const [];
    _models.clear();
    for (var item in list) {
      registerEntry(ModelCatalogEntry.fromJson(Map<String, dynamic>.from(item)));
    }
  }

  /// Factory to load a catalog with the initial default models.
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
      capabilities: ["score_user_input", "produce_json_delta", "detect_injection_attempt"],
      supportsGrammar: true,
      supportsStructuredOutput: true,
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
      capabilities: ["generate_character_response", "adapt_tone_to_alert_level", "reference_narrative_memory"],
      supportsGrammar: true,
      supportsStructuredOutput: true,
      preferredBackend: "llama_cpp",
    ));
    catalog.registerEntry(const ModelCatalogEntry(
      modelId: "google/gemma-4-12b",
      name: "Gemma 4 12B (Q4_K_M)",
      source: "lmstudio-community",
      format: "gguf",
      platforms: ["windows", "linux", "macos"],
      parameterClass: "12b",
      quantization: "q4_k_m",
      minRamGb: 24,
      minVramGb: 10,
      recommendedAgents: ["actor"],
      capabilities: ["generate_character_response", "high_logic_reasoning"],
      supportsGrammar: true,
      supportsStructuredOutput: false,
      preferredBackend: "llama_cpp",
    ));
    return catalog;
  }
}
