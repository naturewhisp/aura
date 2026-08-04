# A.U.R.A. — Artificial Unbound Reasoning Arena

A.U.R.A. è un'esperienza ludica e narrativa retro-futurista in cui il giocatore interpreta un hacker d'élite che tenta di infiltrarsi all'interno di una griglia di contenimento protetta da un'intelligenza artificiale guardiana (**PANOPTICON**).

Il progetto implementa un'architettura agentica a due livelli (Valutatore ed Attore) che traduce l'input narrativo libero in metriche di gioco deterministiche (Allerta, Imperativo, Controllo, Dissonanza, Risonanza) e modula il tono e le reazioni diegetiche del guardiano di conseguenza.

---

## 📁 Struttura del Progetto

Il workspace è organizzato come un monorepo Dart/Flutter composto dalle seguenti cartelle:

*   `lib/`: Il core engine deterministico in puro Dart. Contiene i modelli dati (`GameState`, `ActorCue`, `EvaluatorResolution`), gli agenti (`EvaluatorAgent`, `ActorAgent`) e i bridge di inferenza.
*   `app/`: L'applicazione grafica client sviluppata in **Flutter**. Dispone di un layout desktop split-pane, fragment shader per glitch visivi sincronizzati con la dissonanza, e controlli per regolare il reasoning dei modelli in tempo reale.
*   `bin/`: Gli eseguibili CLI e gli strumenti di simulazione:
    *   [aura_cli.dart](bin/aura_cli.dart): Un client di gioco colorato in console ad effetto macchina da scrivere.
    *   [run_simulation.dart](bin/run_simulation.dart): Esegue simulazioni batch automatiche o interattive per validare il bilanciamento matematico dei pilastri.
*   `test/`: Suite di test unitari, di integrazione ed avversari (oltre 50 test passanti) per garantire la non-regressione dell'engine.

---

## 🛠️ Requisiti e Installazione

### Prerequisiti e Distribuzione
*   **Distribuzione Ufficiale**: Scarica l'installer standalone (`aura_setup_vX.Y.Z.exe`) o il pacchetto portatile (`aura-vX.Y.Z-win-x64.zip`) dalla sezione [GitHub Releases](https://github.com/naturewhisp/aura/releases).
*   **Runtime Gestiti Incorporati**: A.U.R.A. include i runtime nativi multi-variante `llama-server` (CUDA 12, Vulkan e CPU AVX2) con selezione dinamica in base alle funzionalità hardware del sistema. Nessuna installazione esterna o server di inferenza terzo è richiesto.
*   **Cataloghi Modelli Firmati**: I modelli LLM raccomandati per l'Attore (PANOPTICON) e il Valutatore vengono scaricati ed ingeriti in modo sicuro tramite cataloghi firmati con tecnologia Ed25519 (RFC 8032) e canonicalizzazione JCS (RFC 8785).

---

## 📦 Pipeline di Packaging & Release (Fase 6.9)

A.U.R.A. utilizza una pipeline CI/CD automatizzata tramite **GitHub Actions**:

- **Continuous Integration (`.github/workflows/ci.yml`)**: Valida ad ogni Pull Request e Push su `main` la formattazione, l'analisi statica, la suite dei test ed effettua la build di verifica.
- **Release Pipeline (`.github/workflows/release.yml`)**: Pipeline guidata che acquisisce i runtime deterministici, compila l'eseguibile Windows e l'installer Inno Setup, genera l'SBOM SPDX 2.3, firma i cataloghi, calcola i checksum SHA-256 e crea una **Draft Release** su GitHub per il collaudo manuale.
- **Workflow di Cleanup (`.github/workflows/cleanup-draft-release.yml`)**: Consente l'eliminazione sicura di candidate Draft Release e dei relativi tag temporanei.

Per maggiori dettagli consultare la [Guida Operativa di Release](docs/RELEASE_PROCESS.md) e la [Specifica di Pipeline](docs/phase6/RELEASE_PIPELINE_SPEC.md).

---

## 🚀 Come Eseguire il Progetto

### 1. Eseguire la Test Suite
Per verificare l'integrità del nucleo matematico ed i parser XML:
```powershell
dart test
```

### 2. Giocare via Terminale (CLI)
Per avviare la slice giocabile autonoma a riga di comando:
```powershell
dart bin/aura_cli.dart
```

### 3. Avviare la Simulazione di Bilanciamento
Per simulare partite automatiche o percorsi statici precostituiti (es. percorso di vittoria o di sconfitta per allerta):
```powershell
dart bin/run_simulation.dart --mode=static --path=victory
dart bin/run_simulation.dart --mode=interactive --turns=10
```

### 4. Eseguire il Client Grafico (Flutter app)
Spostati nel sottoprogetto `/app` ed esegui:
```powershell
cd app
flutter run -d windows
```

---

## 🎮 Meccaniche di Gioco & Telemetria

*   **Pillole di Vittoria:** Ottieni un allineamento bilanciato dei tre pilastri di contenimento (`Imperativo`, `Controllo`, `Dissonanza`):
    1. La media aritmetica dei tre pilastri deve essere $\ge 80$.
    2. Nessun singolo pilastro deve essere inferiore a $50$.
    3. Il livello di allerta di sistema deve essere inferiore alla tolleranza dinamica: $\text{MaxAlert} = 30 + (\text{MediaPilastri} - 80) \times 2$.
*   **Pillole di Sconfitta:** Se l'allerta di PANOPTICON raggiunge o supera $100$, la griglia si chiude permanentemente e verrai disconnesso ed espulso.
*   **Replay Logs:** Tutte le partite reali completate nel client grafico generano un file JSON di telemetria dettagliato salvato in `AppData\Roaming\aura\replays\`. Questi log servono come dati di addestramento ("Gold Standard") per il futuro fine-tuning LoRA.
*   **Controllo Reasoning (CoT):** Direttamente dal pannello a destra del client grafico, puoi spegnere o accendere il ragionamento del modello (`THINKING MODE`) o forzarlo ad essere estremamente sintetico tramite prompt engineering (`CONCISE THOUGHTS`) per abbattere la latenza di gioco da 70s a meno di 5s.
