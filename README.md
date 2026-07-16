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

### Prerequisiti
*   **Dart SDK & Flutter SDK** (consigliata versione $\ge 3.22$)
*   **LM Studio** o un server API locale compatibile con OpenAI (es. llama.cpp, Ollama) avviato su `http://127.0.0.1:1234`.

### Configurazione LM Studio (Fase 4 Consigliata)
Per un'esperienza ottimale di gioco reale:
*   Carica un modello leggero per il Valutatore (es. `mistralai/ministral-3-3b` o `gemma-2-2b-it`).
*   Carica un modello più grande e reattivo per l'Attore (es. `qwen/qwen3.5-9b` o `gemma-2-9b-it`).
*   Nel pannello di configurazione del modello (Qwen), puoi scegliere se abilitare o meno il **Reasoning** (Chain-of-thought) in base alle tue esigenze di latenza.

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
