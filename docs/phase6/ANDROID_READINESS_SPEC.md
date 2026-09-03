# A.U.R.A. — Android Readiness Specification

**Documento:** `docs/phase6/ANDROID_READINESS_SPEC.md`  
**Fase:** gate di uscita Fase 6 / ingresso Fase 7  
**Tipo:** readiness assessment e vincoli architetturali  
**Stato:** aggiornato post Fase 6.9 e Fase 6.10; fondazione multipiattaforma pronta per i prerequisiti di Fase 7  
**Baseline di riferimento:** Fase 6.10 consolidata  
**Target futuro:** Android arm64

---

## 1. Scopo

Questo documento non specifica ancora l'intera implementazione Android.

Definisce invece:

- quali proprietà della fondazione desktop devono essere platform-neutral;
- quali dipendenze Windows devono restare isolate;
- quali contratti sono riutilizzabili;
- quali spike sono obbligatori prima dello sviluppo;
- quali blocker impediscono l'avvio della Fase 7;
- quali criteri dimostrano che il core può supportare Android senza fork architetturale.

Il documento deve essere aggiornato dopo la Fase 6.9, perché manifest, catalog signing, release metadata e distribuzione introducono contratti condivisi anche con Android.

---

## 2. Principio fondamentale

Il core di A.U.R.A. non deve conoscere:

```text
Windows Registry
Win32
window_manager
llama-server.exe
porte localhost obbligatorie
processi sidecar obbligatori
%APPDATA%
%LOCALAPPDATA%
path assoluti Windows
Inno Setup
CUDA DLL layout
PowerShell
```

Android implementerà adapter differenti per:

- inferenza;
- storage;
- download;
- lifecycle;
- thermal state;
- power state;
- file import;
- UI window/system chrome.

Gameplay, agenti, schema, controller, replay e model execution planning devono restare condivisi.

---

## 3. Modello runtime previsto

### 3.1 Windows

```text
Flutter app
→ managed sidecar llama-server
→ localhost protocol
→ GGUF
```

### 3.2 Android

Baseline prevista:

```text
Flutter app
→ plugin nativo
→ Kotlin/JNI o Dart FFI
→ llama.cpp in-process
→ GGUF
```

AICore può essere un adapter alternativo quando realmente disponibile.

Non è:

- requisito del core;
- fallback universale;
- sostituto obbligatorio di llama.cpp;
- capability assumibile da modello o versione Android senza probe.

---

## 4. Contratti da riutilizzare

Devono restare platform-neutral:

```text
InferenceRuntime
InferenceBridge
RuntimeFactory
RuntimeCapabilities
ModelStore
ModelConfigurationService
ModelExecutionPlanResolver
HardwareProbe
HardwareProfile
ModelManifest
ModelInstallation
DownloadPolicy
Replay persistence contracts
Agent runtime contracts
GameController
```

Gli adapter Windows e Android devono implementare gli stessi contratti semantici anche quando il meccanismo fisico è differente.

---

## 5. Isolamento della shell desktop

I componenti della Fase 6.6 devono restare fuori dal core gameplay:

```text
DesktopWindowController
WindowsDesktopWindowController
window_manager adapter
monitor geometry
borderless fullscreen
taskbar integration
shutdown window events
```

Su Android saranno sostituiti da concetti differenti:

```text
immersive mode
system bars
orientation
activity lifecycle
back navigation
picture-in-picture policy, se prevista
```

Il core non deve importare package Flutter desktop-only.

---

## 6. Lifecycle inferenza Android

Il runtime Android deve supportare:

- inizializzazione fuori dal main thread;
- caricamento modello cancellabile;
- token streaming;
- cancellazione generazione;
- unload esplicito;
- shutdown idempotente;
- gestione activity pause/resume;
- gestione app background/foreground;
- gestione process death;
- gestione low-memory callback;
- gestione thermal throttling;
- nessun processo orfano;
- nessuna inferenza prolungata incontrollata in background.

Il contratto di lifecycle deve distinguere:

```text
application paused
application backgrounded
activity recreated
process killed
memory pressure
thermal serious/critical
user cancellation
```

---

## 7. Storage

### 7.1 Managed model store

Deve usare storage applicativo o una posizione esplicitamente selezionata.

Requisiti:

- file multi-GB;
- download resumable;
- `.partial`;
- checksum;
- rename atomico, quando supportato;
- spazio libero;
- rollback;
- cleanup controllato;
- nessun accesso tramite path Windows.

### 7.2 Import esterno

Android usa URI e Storage Access Framework.

Non assumere che un file selezionato:

- abbia un path filesystem stabile;
- sia seekable indefinitamente;
- resti accessibile dopo il riavvio;
- possa essere aperto senza permesso persistente.

L'adapter deve gestire:

```text
content:// URI
persistable URI permission
copy-to-managed-store opzionale
streaming/seek capability
provider failure
file revocato
```

### 7.3 Dati applicativi

Replay, config e metadata devono usare directory applicative platform-neutral risolte da adapter.

---

## 8. Download

Il download manager Android deve supportare:

- file grandi;
- resume;
- retry;
- checksum;
- rete metered/unmetered;
- cancellazione;
- foreground service o meccanismo equivalente quando richiesto;
- notifica di avanzamento;
- battery saver;
- storage insufficiente;
- app restart;
- proxy/VPN nei limiti della piattaforma.

Le suite standard non devono scaricare modelli.

---

## 9. Hardware profile Android

Il probe Android deve poter osservare:

```text
ABI
API level
RAM totale e disponibile
memory class
low-RAM device flag
storage disponibile
thermal status
battery saver
power source
GPU/driver metadata, se affidabili
NNAPI/AICore capability, se disponibile
instruction set ARM
```

CPU feature iniziali rilevanti:

```text
arm64
neon
dotprod
i8mm
sve, se realmente disponibile e utile
```

Nessuna capability deve essere dedotta unicamente dal nome commerciale del SoC.

Runtime facts e smoke test prevalgono sul profilo teorico.

---

## 10. Model execution plans Android

Piani previsti:

```text
single shared model
two small models
sequential residency
deterministic evaluator + local actor
system-managed backend, se disponibile
```

Il client Android non deve essere obbligato a eseguire la stessa combinazione desktop.

Il resolver deve considerare:

- RAM disponibile;
- context/KV cache;
- modello;
- quantizzazione;
- thermal state;
- battery state;
- backend;
- latency;
- ruolo Actor/Evaluator;
- capacità di unload/reload.

---

## 11. Manifest e cataloghi

Gli schemi devono supportare varianti Android senza rompere Windows.

Esempio concettuale:

```text
platform: android
architecture: arm64
runtimeBackend: llamaCppNative
minimumApiLevel
requiredCpuFeatures
modelFormat: gguf
quantization
context limits
memory estimate
```

I manifest non devono contenere:

- path assoluti Windows;
- nomi `.exe`;
- `vendorDirectories` obbligatorie per tutte le piattaforme;
- assunzione di sidecar process.

Campi Windows-specific possono esistere in descrittori o sezioni discriminated, non nel contratto universale obbligatorio.

I cataloghi firmati della Fase 6.9 devono poter essere verificati anche dal client Android.

---

## 12. Audio e branding

### 12.1 Audio

Gli asset ufficiali sono già Flutter assets e devono essere riutilizzabili.

Verificare:

- codec supportato;
- dimensione APK/AAB;
- eventuale compressione;
- loop;
- audio focus;
- interruption handling;
- cuffie/Bluetooth;
- background policy;
- asset loading da bundle Android.

### 12.2 Branding

Il master branding deve generare:

```text
launcher icon
adaptive foreground
adaptive background
monochrome icon
splash branding
```

Non usare l'ICO Windows come sorgente.

---

## 13. Privacy e permessi

La baseline Android deve minimizzare i permessi.

Non richiedere senza necessità:

```text
MANAGE_EXTERNAL_STORAGE
accesso storage globale
permessi hardware non usati
servizi in background permanenti
```

Preferire:

```text
Storage Access Framework
directory app-private
permessi URI persistenti
network permission solo per download espliciti
```

La telemetria resta opt-in e fuori dal runtime locale obbligatorio.

---

## 14. Threading e FFI/JNI

Vincoli:

- nessuna inferenza sul UI thread;
- callback token thread-safe;
- backpressure;
- cancellazione;
- gestione isolate/engine teardown;
- nessun puntatore nativo usato dopo dispose;
- ownership esplicita di model/context;
- errori nativi convertiti in failure tipizzate;
- crash nativo non trattato come normale fallback;
- test di repeated load/unload.

La scelta JNI vs FFI deve essere motivata dallo spike e può essere ibrida.

---

## 15. Build e distribuzione

La Fase 7 dovrà aggiungere:

```text
Android CI
debug APK
release AAB/APK
signing Android
Play integrity/publishing, se previsto
SBOM Android
manifest/catalog verification
```

La Fase 6.9 non deve simulare che la pipeline Android esista già.

Deve però evitare di chiudere i cataloghi e la provenance in formati Windows-only.

---

## 16. Test strategy

### 16.1 Core

Riutilizzare:

- unit test;
- schema test;
- model resolver test;
- replay test;
- deterministic evaluator test;
- manifest signature test.

### 16.2 Android adapter

Richiesti in Fase 7:

- plugin unit test;
- JNI/FFI integration test;
- emulator test dove significativo;
- physical device test;
- load/unload;
- cancellation;
- process recreation;
- low-memory;
- thermal;
- download resume;
- URI persistence.

### 16.3 Real model

Opt-in e separato dalla CI standard.

---

## 17. Spike obbligatori Fase 7.0

Prima dell'implementazione produttiva:

1. selezionare almeno tre classi device arm64;
2. misurare RAM utilizzabile;
3. provare caricamento GGUF;
4. misurare load time;
5. misurare token/s;
6. testare context size;
7. testare unload;
8. testare background/resume;
9. testare thermal throttling;
10. testare import URI;
11. testare download multi-GB;
12. verificare AICore reale, senza assunzioni;
13. confrontare JNI e FFI;
14. definire minimum API level basato su evidenze.

---

## 18. Stato readiness

Legenda:

```text
READY
PARTIAL
NOT READY
NOT APPLICABLE
UNVERIFIED
```

### 18.1 Stato dei Prerequisiti Architetturali (Post-Fase 6.10)

| Area | Stato | Nota |
|---|---|---|
| Game controller platform-neutral | READY | Nessuna autorità runtime sulle regole; 100% puro Dart |
| Agent contracts | READY | Contratti Dart condivisibili ed immutabili |
| Inference abstraction | READY | Interfaccia `InferenceRuntime` neutrale; adapter Android pianificato in 7.1 |
| Windows sidecar isolation | READY | Nessun leakage di Win32 o sidecar nei consumer; platform layer confinato |
| Model lifecycle contracts | READY | Schema DTO e contratti isolati; backend storage Android pianificato in 7.2 |
| Manifest schemas | READY | Schemi manifest privi di path o binari Windows vincolanti |
| Catalog signing | READY | Ed25519 RFC 8032 + JCS RFC 8785 in puro Dart, verificabile su Android |
| Android native runtime | NOT READY | Perimetro esclusivo Fase 7.1 |
| Android model store | NOT READY | Perimetro esclusivo Fase 7.2 |
| Android hardware probe | NOT READY | Perimetro esclusivo Fase 7.0/7.3 |
| Thermal lifecycle | NOT READY | Perimetro esclusivo Fase 7.4 |
| Audio asset portability | READY | Logical ID e mapping asset Flutter multipiattaforma consolidati |
| Branding master | READY | Master iconografico disponibile per generazione icone adaptive |
| Android CI/release | NOT READY | Perimetro esclusivo Fase 7 |
| Real device evidence | NOT READY | Spike obbligatorio Fase 7.0 |

---

## 19. Blocker di ingresso Fase 7

Tutti i blocker architetturali iniziali di pertinenza della fondazione sono stati risolti con successo nel corso della Fase 6:
- [x] Core totalmente privo di dipendenze da Win32 o registry.
- [x] Manifest universali privi di path Windows obbligatori.
- [x] Catalog signing Ed25519 / JCS RFC 8785 formalizzato e testato in pure Dart.
- [x] Model lifecycle separato dalla UI desktop e centralizzato in service facades.
- [x] Runtime selection non vincolata a `llama-server.exe` nel core.
- [x] Storage contracts e download platform-neutral.

L'ingresso formale alla Fase 7 avverrà non appena concluso il collaudo esteso multi-hardware della Fase 6.10.

---

## 20. Criteri di readiness dopo Fase 6.9

```text
- release/catalog schemas non sono Windows-only;
- signer e verifier sono riutilizzabili;
- il core compila senza adapter Windows;
- desktop shell resta isolata;
- runtime sidecar è un adapter;
- model configuration non richiede path bundled Windows;
- storage e download hanno contratti platform-neutral;
- audio usa logical ID;
- branding ha master riutilizzabile;
- test core restano offline;
- esiste un piano Fase 7.0 misurabile.
```

---

## 21. Output richiesto all'avvio Fase 7

Il prompt di Fase 7 dovrà richiedere:

- audit di questo documento;
- aggiornamento tabella readiness;
- risultati spike;
- decisione JNI/FFI;
- device matrix;
- minimum API;
- modello/quantizzazione pilota;
- storage strategy;
- lifecycle strategy;
- benchmark;
- roadmap implementativa aggiornata.

---

## 22. Change control

Aggiornare il documento:

- al termine della Fase 6.9;
- dopo lo spike 7.0;
- dopo scelta JNI/FFI;
- dopo prima inferenza su device;
- dopo definizione minimum API;
- dopo prima pipeline Android;
- prima della beta Android.

Ogni stato `READY` deve essere sostenuto da codice o test, non da intenzione.
