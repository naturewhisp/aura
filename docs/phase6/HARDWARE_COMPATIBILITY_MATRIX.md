# A.U.R.A. — Hardware Compatibility Matrix

**Documento:** `docs/phase6/HARDWARE_COMPATIBILITY_MATRIX.md`  
**Tipo:** documento vivo di requisiti, evidenze e certificazione  
**Stato:** baseline iniziale  
**Baseline iniziale:** `1c9015da6c5f445c13e82fa5df0c4d49e0830429`  
**Piattaforme:** Windows x64; Android arm64 futuro

---

## 1. Scopo

Questa matrice separa:

1. requisiti dichiarati;
2. capability rilevate;
3. probe runtime;
4. smoke test;
5. inferenza reale;
6. certificazione manuale.

La parola “supportato” non deve essere usata senza specificare il livello di evidenza.

---

## 2. Livelli di evidenza

```text
DECLARED
DETECTED
PROBE_PASSED
SMOKE_PASSED
INFERENCE_PASSED
MANUALLY_CERTIFIED
FAILED
BLOCKED
NOT_RUN
```

### DECLARED

Compatibilità prevista da manifest o design.

### DETECTED

Capability rilevata dal probe hardware.

### PROBE_PASSED

Executable avviato con probe leggera, per esempio:

```text
llama-server --version
```

Non dimostra inferenza GPU.

### SMOKE_PASSED

Runtime inizializzato e operazione minima controllata completata.

### INFERENCE_PASSED

Modello reale caricato e generazione completata.

### MANUALLY_CERTIFIED

Scenario completo verificato su macchina identificata, inclusi lifecycle e packaging.

---

## 3. Requisiti Windows correnti

### 3.1 Sistema

```text
OS family: Windows
architecture: x64
```

La versione minima Windows deve essere formalizzata dalla Fase 6.10 sulla base di Flutter, plugin e runtime effettivi.

### 3.2 CPU

Le varianti ufficiali correnti richiedono:

| Variante | Feature CPU |
|---|---|
| `win-x64-cuda` | `avx2`, `fma` |
| `win-x64-vulkan` | `avx2` |
| `win-x64-cpu-avx2` | `avx2`, `fma` |

La detection usa:

```text
CPUID
OSXSAVE
XGETBV(0)
XCR0 XMM/YMM bits
```

AVX/AVX2/FMA sono utilizzabili solo quando lo stato OS è abilitato.

### 3.3 Backend

| Variante | Backend capability |
|---|---|
| `win-x64-cuda` | `cuda12` |
| `win-x64-vulkan` | `vulkan` |
| `win-x64-cpu-avx2` | nessuna accelerazione richiesta |

Le backend capability non sono CPU features.

### 3.4 Runtime fallback

Ordine automatico previsto:

```text
CUDA
→ Vulkan
→ CPU AVX2
```

Il fallback deve essere tracciato e visibile.

---

## 4. Requisiti Android preliminari

Stato:

```text
UNVERIFIED
```

Target concettuale:

```text
OS family: Android
architecture: arm64
runtime: llama.cpp native in-process
```

Feature candidate:

```text
NEON
dotprod
i8mm
```

Nessuna feature minima definitiva deve essere dichiarata prima dello spike Fase 7.0.

---

## 5. Campi di una registrazione

Ogni risultato hardware deve includere:

```text
recordId
dateUtc
auraCommit
appVersion
platform
osVersion
architecture
deviceOrMachineId anonimo/manuale
cpuVendor
cpuModel
cpuFeatures
ramTotalGiB
ramAvailableGiB
gpuVendor
gpuModel
vramGiB
driverVersion
backend
runtimeVariantId
llamaCppVersion
llamaCppCommit
modelId
modelFilename
modelSha256
quantization
contextSize
gpuLayers
probeResult
smokeResult
inferenceResult
loadTimeMs
firstTokenMs
tokensPerSecond
peakRamGiB
peakVramGiB
thermalResult
lifecycleResult
packagingSource
evidenceLevel
notes
```

Non registrare username, indirizzi IP o identificativi hardware sensibili.

---

## 6. Matrice requisiti dichiarati

| Platform | Arch | Runtime variant | CPU requirements | Backend requirements | Stato |
|---|---|---|---|---|---|
| Windows | x64 | `win-x64-cuda` | AVX2 + FMA + OS YMM state | CUDA 12 runtime/device | DECLARED |
| Windows | x64 | `win-x64-vulkan` | AVX2 + OS YMM state | Vulkan device/driver | DECLARED |
| Windows | x64 | `win-x64-cpu-avx2` | AVX2 + FMA + OS YMM state | CPU | DECLARED |
| Android | arm64 | TBD | TBD after spike | Native llama.cpp/AICore optional | UNVERIFIED |

---

## 7. Evidenze iniziali disponibili

### 7.1 Macchina di sviluppo di riferimento

Dati documentati:

```text
Platform: Windows
RAM: 64 GiB
Dedicated VRAM: 12 GiB
GPU model: non registrato in questa matrice
```

Stato:

```text
reference environment
non ancora MANUALLY_CERTIFIED tramite record completo
```

### 7.2 Packaging probe locale dichiarata

Durante la chiusura della Fase 6.8 sono stati dichiarati risultati positivi per:

```text
win-x64-cuda      → llama-server --version SUCCESS
win-x64-vulkan    → llama-server --version SUCCESS
win-x64-cpu-avx2  → llama-server --version SUCCESS
```

Versione runtime dichiarata:

```text
10255
```

Questa evidenza deve essere registrata come:

```text
PROBE_PASSED, user-reported local run
```

Non dimostra:

- caricamento modello;
- offload GPU;
- token generation;
- stabilità;
- performance;
- compatibilità con altre macchine.

---

## 8. Matrice risultati Windows

Compilare una riga per ogni macchina/backend.

| Record | OS | CPU | RAM | GPU / VRAM | Driver | Variant | Model | Probe | Inference | Lifecycle | Evidence | Note |
|---|---|---|---:|---|---|---|---|---|---|---|---|---|
| `win-ref-001` | Windows, versione TBD | modello CPU TBD | 64 GiB | GPU TBD / 12 GiB | TBD | CUDA | not run | PASS dichiarato | NOT_RUN | NOT_RUN | PROBE_PASSED | Dati da completare |
| `win-ref-002` | Windows, versione TBD | modello CPU TBD | 64 GiB | GPU TBD / 12 GiB | TBD | Vulkan | not run | PASS dichiarato | NOT_RUN | NOT_RUN | PROBE_PASSED | Dati da completare |
| `win-ref-003` | Windows, versione TBD | modello CPU TBD | 64 GiB | CPU | n/a | CPU AVX2 | not run | PASS dichiarato | NOT_RUN | NOT_RUN | PROBE_PASSED | Dati da completare |

Non promuovere queste righe a certificazione finché CPU, GPU, driver, modello e risultati reali non sono registrati.

---

## 9. Matrice risultati Android

| Record | Device | Android/API | SoC | RAM | Backend | Model | Load | Token/s | Thermal | Lifecycle | Evidence | Note |
|---|---|---|---|---:|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — | — | — | — | NOT_RUN | Fase 7.0 |

---

## 10. Scenari Windows da certificare

### 10.1 CUDA primary

```text
CUDA variant selected
vendor DLL resolved process-locally
model load
generation
shutdown
no orphan
restart
```

### 10.2 CUDA failure → Vulkan

Simulare o usare macchina senza CUDA operativo:

```text
CUDA probe/load fails
→ Vulkan selected
→ warning recorded
→ inference succeeds
```

### 10.3 Vulkan failure → CPU

```text
CUDA unavailable
Vulkan unavailable
→ CPU selected
→ inference succeeds
```

### 10.4 CPU incompatible

CPU senza AVX2/FMA:

```text
variant rejected before launch
no illegal instruction
typed incompatibility
```

### 10.5 XCR0 YMM disabled

Ambiente virtualizzato o simulato:

```text
CPUID feature present
OSXSAVE present
XCR0 missing YMM
→ AVX unavailable
```

### 10.6 Corruption

```text
DLL/exe modified
→ SHA mismatch
→ runtime rejected
```

### 10.7 Portable move

```text
portable extracted
configuration persisted
folder moved
runtime re-resolved
inference succeeds
```

### 10.8 Upgrade

```text
old installer
→ upgrade
→ config/models/replays preserved
→ runtime works
```

---

## 11. Classi hardware Windows

Le classi non rappresentano certificazione automatica.

### Low

Indicativo:

```text
CPU x64 AVX2
RAM ridotta
GPU non utile
CPU backend
single/shared model
```

### Balanced

```text
CPU AVX2/FMA
RAM adeguata
Vulkan o GPU entry-level
modello condiviso o sequential
```

### High

```text
GPU dedicata
VRAM adeguata
CUDA
Actor/Evaluator separati possibili
```

### Workstation

```text
RAM elevata
VRAM elevata
parallel residency
benchmark e profiling avanzati
```

Le soglie numeriche devono derivare dai benchmark, non da stime arbitrarie.

---

## 12. Metriche performance

Per ogni inferenza reale registrare:

```text
runtime startup ms
model load ms
first token ms
tokens/s
prompt tokens
generated tokens
context size
RAM peak
VRAM peak
CPU usage
GPU usage
temperature
thermal throttling
```

Separare:

```text
Evaluator
Actor
shared model
simultaneous
sequential
```

---

## 13. Modelli

La compatibilità hardware è inseparabile dal modello.

Ogni risultato deve identificare:

```text
logical model ID
provider/repository
revision
filename
SHA-256
quantization
parameter count
context
```

Una macchina non è genericamente “compatibile con A.U.R.A.” senza specificare il piano di esecuzione.

---

## 14. Driver e runtime

Registrare:

- driver NVIDIA;
- Vulkan driver;
- Windows build;
- runtime variant;
- DLL set;
- `llama.cpp` version/commit.

Una regressione deve poter essere correlata a:

```text
app commit
runtime set
driver
model
```

---

## 15. Packaging evidence

Campo `packagingSource`:

```text
local-dev
github-draft-release
github-published-release
```

Per la certificazione release usare preferibilmente asset scaricati dalla Draft Release, non file locali pre-upload.

Regola:

```text
testare gli stessi byte che verranno pubblicati
```

---

## 16. Certificazione manuale

Una riga può diventare `MANUALLY_CERTIFIED` solo quando sono verificati:

- checksum asset;
- portable;
- installer;
- runtime selection;
- modello reale;
- almeno una generazione;
- shutdown;
- no orphan;
- restart;
- upgrade o installazione pulita secondo scenario;
- evidenza conservata.

La certificazione è valida per la combinazione specifica, non per tutta la famiglia hardware.

---

## 17. Evidenze

Percorso raccomandato:

```text
docs/hardware/evidence/
  <record-id>/
    environment.json
    test-results.json
    logs/
    screenshots/
    checksums.txt
```

Non committare:

- modelli;
- chiavi;
- dati personali;
- log con input sensibili;
- dump troppo grandi.

Gli artifact CI possono contenere evidenze temporanee con retention limitata.

---

## 18. Aggiornamento della matrice

Aggiornare quando cambia:

- app;
- runtime set;
- `llama.cpp`;
- manifest;
- driver critico;
- modello;
- quantizzazione;
- Android plugin;
- minimum OS/API;
- packaging.

Una certificazione precedente non deve essere copiata automaticamente su una nuova runtime version.

---

## 19. Gate Fase 6.10

La Fase 6.10 deve completare almeno:

```text
- una macchina Windows pulita;
- CUDA inference;
- Vulkan inference;
- CPU inference;
- fallback;
- CPU incompatible;
- corrupt runtime;
- portable move;
- install/upgrade/uninstall;
- no orphan;
- benchmark;
- proxy/offline/storage failure;
```

---

## 20. Gate Fase 7.0

La sezione Android deve includere almeno:

```text
- tre classi device;
- minimum API evidence;
- modello pilota;
- quantizzazione;
- load time;
- token/s;
- peak RAM;
- thermal;
- background/resume;
- URI import;
- download resume;
```

---

## 21. Criteri di qualità del documento

```text
- nessun supporto dichiarato senza livello evidenza;
- nessuna deduzione da nome commerciale;
- nessun benchmark senza modello;
- nessuna certificazione senza runtime version;
- nessuna riga Android fittizia;
- risultati falliti conservati;
- hardware e software identificati;
- asset testati provenienti dalla Draft Release quando possibile.
```

---

## 22. Registro modifiche

| Data | Commit | Modifica |
|---|---|---|
| 2026-08-04 | `1c9015d` baseline | Creazione matrice iniziale |

Le revisioni future devono aggiungere righe senza cancellare risultati storici, salvo correzione documentata.
