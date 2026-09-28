# A.U.R.A. — Dataset Provenance & Replay Schema Specification

**Documento:** `docs/phase6/DATASET_PROVENANCE_AND_REPLAY_SCHEMA_SPEC.md`  
**Fase:** 6.11 / Preparazione Fase 8 (LoRA Fine-Tuning & Dataset Pipeline)  
**Stato:** Specifica Tecnica di Dominio  
**Baseline di Riferimento:** `lib/src/replay_logger.dart`  
**Destinatari:** Machine Learning Engineers, Core Maintainers, Dataset Curators  

---

## 1. Obiettivi e Fondamenti Teorici

Nei sistemi di intelligenza artificiale agentica basati su Small Language Models (SLM) quantizzati eseguiti su hardware eterogeneo (Windows CUDA, Windows Vulkan, Apple Silicon Metal, Android futuro), la generazione testuale è sensibile a molteplici variabili latenti:
* La precisione del backend di calcolo (es. differenze minime tra kernel CUDA cuBLAS e shader Metal GGML);
* La versione o commit esatto della libreria di inferenza (`llama.cpp`);
* Il tipo di quantizzazione GGUF (es. `Q4_K_M` vs `Q5_K_M` vs `Q8_0`);
* I parametri di sampling (temperatura, top-k, top-p, seed deterministico);
* La classe di hardware e la relativa pressione di memoria.

Se A.U.R.A. raccoglie replay da una popolazione mista di giocatori (Windows e macOS) senza tracciare questi parametri, il dataset risultante conterrà **variabili confondenti inestricabili**: risulterà impossibile determinare se una violazione diegetica o una frizione dialettica sia imputabile a una diversa strategia di gioco umana, all'allucinazione del modello, a una fluttuazione della temperatura o a una discrepanza tra compilazioni di `llama.cpp`.

La presente specifica definisce l'estensione del modello dati di `ReplayEntry` mediante la struttura immutabile `ReplayProvenanceMetadata`.

---

## 2. Il Modello Dati `ReplayProvenanceMetadata`

La classe `ReplayProvenanceMetadata` viene posizionata nel dominio di `aura_core` ed esportata tramite il modulo di replay.

### 2.2 Definizione dei Campi

```dart
import 'package:meta/meta.dart';

/// Origine del dato registrato nel replay.
enum DatasetSource {
  humanPlaytest('human_playtest'),
  syntheticSimulation('synthetic_simulation'),
  developerEvaluation('developer_evaluation');

  final String wireValue;
  const DatasetSource(this.wireValue);

  static DatasetSource fromString(String val) {
    return DatasetSource.values.firstWhere(
      (e) => e.wireValue == val,
      orElse: () => DatasetSource.humanPlaytest,
    );
  }
}

/// Metadati di provenienza sperimentale associati a una voce di replay.
@immutable
class ReplayProvenanceMetadata {
  /// Versione dello schema di provenance (SemVer, es. "1.0.0").
  final String schemaVersion;

  /// Tipologia della fonte di generazione del dato.
  final DatasetSource datasetSource;

  /// Piattaforma del sistema operativo host (es. "windows", "macos", "linux", "android").
  final String platform;

  /// Dettaglio della versione dell'OS e release del kernel (es. "Darwin 24.1.0", "Windows 11 23H2").
  final String osVersion;

  /// Architettura del processore host (es. "x86_64", "arm64").
  final String architecture;

  /// Identificatore della classe hardware (es. "apple_silicon_m3_pro_18gb", "desktop_rtx_4080_16gb").
  final String hardwareClass;

  /// Hash SHA commit Git a 40 caratteri della build che ha generato il dato.
  final String gitCommit;

  /// Versione SemVer dell'applicazione A.U.R.A. (es. "0.6.11-rc.1").
  final String appVersion;

  /// Backend runtime di inferenza utilizzato (es. "managed_llama_server", "external_http", "in_process_ffi").
  final String runtimeBackend;

  /// Tipologia di accelerazione hardware effettiva (es. "cuda", "vulkan", "metal", "cpu").
  final String runtimeAcceleration;

  /// Identificatore o tag di build di llama.cpp (es. "b4210").
  final String llamaCppBuild;

  /// Hash SHA-256 del file GGUF del modello attore utilizzato.
  final String actorModelSha256;

  /// Formato di quantizzazione GGUF del modello (es. "Q4_K_M", "Q5_K_M").
  final String modelQuantization;

  /// Dimensione del contesto impostata per l'inferenza (es. 8192).
  final int contextSize;

  /// Parametri di campionamento attivi durante l'inferenza.
  final Map<String, dynamic> samplingParameters;

  /// Identificatore pseudonimizzato del tester (es. "tester-alpha-04").
  final String? anonymizedTesterId;

  /// Identificatore univoco della sessione di playtest.
  final String sessionId;

  const ReplayProvenanceMetadata({
    this.schemaVersion = '1.0.0',
    required this.datasetSource,
    required this.platform,
    required this.osVersion,
    required this.architecture,
    required this.hardwareClass,
    required this.gitCommit,
    required this.appVersion,
    required this.runtimeBackend,
    required this.runtimeAcceleration,
    required this.llamaCppBuild,
    required this.actorModelSha256,
    required this.modelQuantization,
    required this.contextSize,
    required this.samplingParameters,
    this.anonymizedTesterId,
    required this.sessionId,
  });

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'datasetSource': datasetSource.wireValue,
    'platform': platform,
    'osVersion': osVersion,
    'architecture': architecture,
    'hardwareClass': hardwareClass,
    'gitCommit': gitCommit,
    'appVersion': appVersion,
    'runtimeBackend': runtimeBackend,
    'runtimeAcceleration': runtimeAcceleration,
    'llamaCppBuild': llamaCppBuild,
    'actorModelSha256': actorModelSha256,
    'modelQuantization': modelQuantization,
    'contextSize': contextSize,
    'samplingParameters': samplingParameters,
    if (anonymizedTesterId != null) 'anonymizedTesterId': anonymizedTesterId,
    'sessionId': sessionId,
  };

  factory ReplayProvenanceMetadata.fromJson(Map<String, dynamic> json) {
    return ReplayProvenanceMetadata(
      schemaVersion: json['schemaVersion'] as String? ?? '1.0.0',
      datasetSource: DatasetSource.fromString(json['datasetSource'] as String? ?? 'human_playtest'),
      platform: json['platform'] as String? ?? 'unknown',
      osVersion: json['osVersion'] as String? ?? 'unknown',
      architecture: json['architecture'] as String? ?? 'unknown',
      hardwareClass: json['hardwareClass'] as String? ?? 'generic',
      gitCommit: json['gitCommit'] as String? ?? 'unknown',
      appVersion: json['appVersion'] as String? ?? 'unknown',
      runtimeBackend: json['runtimeBackend'] as String? ?? 'unknown',
      runtimeAcceleration: json['runtimeAcceleration'] as String? ?? 'unknown',
      llamaCppBuild: json['llamaCppBuild'] as String? ?? 'unknown',
      actorModelSha256: json['actorModelSha256'] as String? ?? '',
      modelQuantization: json['modelQuantization'] as String? ?? 'unknown',
      contextSize: json['contextSize'] as int? ?? 0,
      samplingParameters: Map<String, dynamic>.from(json['samplingParameters'] as Map? ?? {}),
      anonymizedTesterId: json['anonymizedTesterId'] as String?,
      sessionId: json['sessionId'] as String? ?? 'unknown',
    );
  }
}
```

---

## 3. Integrazione in `ReplayEntry` e Retrocompatibilità

In [`lib/src/replay_logger.dart`](file:///c:/Users/dendo/Documents/GitHub/aura/lib/src/replay_logger.dart), la classe `ReplayEntry` viene estesa con un campo opzionale:

```dart
class ReplayEntry {
  // Campi esistenti invariati...
  final int turnId;
  final String userInput;
  // ...
  
  /// Metadati di provenienza sperimentale (opzionale per retrocompatibilità).
  final ReplayProvenanceMetadata? provenance;

  const ReplayEntry({
    required this.turnId,
    required this.userInput,
    // ...
    this.provenance,
  });
}
```

### Regole di Retrocompatibilità:
1. **Deserializzazione dei Replay Storici (Fase 5 e 6.0–6.10):** Se la chiave `"provenance"` è assente nel JSON, la factory `ReplayEntry.fromJson` assegna `provenance: null`. Nessun replay esistente risulterà corrotto o illeggibile.
2. **Serializzazione Nuovi Replay:** Qualsiasi sessione generata a partire dalla versione 0.6.11 compila obbligatoriamente il blocco `provenance`.
3. **Canonicalizzazione JSON RFC 8785 (JCS):** I campi del dizionario `provenance` devono essere serializzati con chiavi ordinate lessicograficamente, garantendo hash stabili e verificabili.

---

## 4. Pipeline di Curatela del Dataset per LoRA (Fase 8 Preview)

L'introduzione della provenance abilita script deterministici di estrazione e curatela (in `tool/dataset/`):

### 4.1 Criteri di Filtraggio e Qualità del Dato
Prima di includere una coppia `(TurnInput, ActorOutput)` nel set di addestramento:
1. **Verifica Human Source:** `datasetSource == 'human_playtest'`.
2. **Esclusione Rule Fallback:** `usedRuleFallback == false` (esclude turni in cui l'LLM ha fallito ed è intervenuto il motore euristico).
3. **Verifica Conflitti Hardware/Quantizzazione:** Possibilità di isolare sotto-dataset ad alta fedeltà (es. solo quantizzazioni $\ge \text{Q4\_K\_M}$ ed escludere run con temperature anomale).
4. **Coerenza Semantica:** `evaluatorOutput.semanticCategory != SemanticCategory.irrelevant`.

### 4.2 Partizionamento Train / Validation / Test
Il partizionamento del dataset deve avvenire **a livello di intera sessione** (`sessionId`) e mai a livello di singolo turno, per prevenire *data leakage* tra turni contigui della medesima partita.

---

## 5. Test Suite e Validazione

La conformità della specifica deve essere validata da test unitari dedicati in `test/replay/replay_provenance_test.dart`:
* Test di serializzazione/deserializzazione bidirezionale con `ReplayProvenanceMetadata`.
* Test di regressione su fixture JSON reali prive del campo `provenance` (garanzia di retrocompatibilità).
* Test di integrità dei tipi enumerati e di default resilience in presenza di chiavi ignote.
