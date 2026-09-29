# A.U.R.A. — Guida Operativa per Playtester macOS (Apple Silicon)

**Documento:** `docs/MACOS_PLAYTEST_GUIDE.md`  
**Destinatari:** Playtester, Collaboratori e Ricercatori su hardware macOS  
**Target Hardware:** Mac con processori Apple Silicon (M1, M2, M3, M4 e relative varianti Pro/Max/Ultra)  
**Stato:** Documento Operativo Indipendente (Fase 6.11)  

---

## 1. Premessa Importante

La versione macOS di A.U.R.A. distribuita in questa fase è un **Target Sperimentale di Playtest (`EXPERIMENTAL / PLAYTEST TARGET`)**, finalizzato alla validazione del motore di gioco e alla raccolta di sessioni di dialogo per l'addestramento dei futuri modelli LoRA.

A differenza della versione Windows (dotata di installer automatico Inno Setup e configuratore integrato con scaricamento guidato dei modelli), **su macOS l'applicazione viene distribuita come bundle standalone non firmato e richiede pochi e semplici passaggi manuali di configurazione**.

Questa guida descrive in modo chiaro e passo-passo tutto ciò che occorre fare per installare, avviare e giocare con A.U.R.A. sul tuo Mac.

---

## 2. Requisiti di Sistema Minimi e Consigliati

| Componente | Requisito Minimo | Requisito Consigliato per Playtest Ottimale |
| :--- | :--- | :--- |
| **Processore** | Apple Silicon M1 (8-core CPU / 7-core GPU) | Apple Silicon M2 Pro / M3 Pro / M4 |
| **Memoria Unificata (RAM)** | 8 GB (con modelli quantizzati compatti Q3/Q4) | 16 GB o superiore (consigliati 18–24 GB) |
| **Sistema Operativo** | macOS 13 (Ventura) | macOS 14 (Sonoma) o macOS 15 (Sequoia) |
| **Spazio su Disco** | 500 MB (app) + 5–10 GB per i file di modello GGUF | SSD ad alte prestazioni |

---

## 3. Guida Passo-Passo all'Installazione

### Passo 1: Download ed Estrazione del Pacchetto
1. Accedi alla pagina delle **Release Candidate** sul repository GitHub di A.U.R.A. (es. `v0.6.11-rc.1`).
2. Nella sezione **Assets**, individua e scarica il file:
   ```text
   aura-v<versione>-macos-universal.zip
   ```
3. Fai doppio clic sull'archivio compresso per estrarlo: otterrai l'applicazione `AURA.app`.
4. Trascina `AURA.app` all'interno della cartella **/Applicazioni** (`/Applications`) del tuo Mac (oppure posizionala sulla Scrivania).

---

### Passo 2: Superamento del Blocco Apple Gatekeeper

Poiché si tratta di una build sperimentale per playtester e non di un'applicazione commerciale distribuita sul Mac App Store, il binario non contiene la firma a pagamento Apple Developer. Al primo tentativo di apertura, macOS mostrerà un avviso di sicurezza (*"Impossibile aprire l'app perché proviene da uno sviluppatore non identificato"* oppure *"L'applicazione è danneggiata"*).

Puoi autorizzare l'applicazione in due modi:

#### Metodo Standard di Sicurezza Apple (Procedura Grafica dal Finder)
1. Apri il **Finder** e naviga nella cartella **Applicazioni** (o ovunque tu abbia posizionato l'app).
2. Fai **clic con il tasto destro** (oppure tieni premuto il tasto `Control` e fai clic) sull'icona di **AURA**.
3. Seleziona **Apri** dal menu contestuale.
4. Nella finestra di dialogo che compare, fai clic sul pulsante **Apri comunque**.
*(Questa operazione è la procedura ufficiale raccomandata da Apple per consentire l'override esplicito dell'utente su app prive di firma notarizzata. Va eseguita solo al primo avvio; ai successivi avvii l'app si aprirà normalmente con un doppio clic).*

#### Workaround Tecnico per Tester Interni e Sviluppatori (Terminale)
Se su versioni recenti di macOS (Sonoma o Sequoia) il sistema impedisce l'override grafico mostrando l'avviso bloccante *"L'applicazione è danneggiata"*, puoi rimuovere l'attributo di quarantena web impostato dal browser tramite un singolo comando di terminale:
1. Apri l'applicazione **Terminale** di macOS (`Cmd + Spazio`, digita `Terminale` e premi Invio).
2. Esegui il comando:
   ```bash
   xattr -cr /Applications/AURA.app
   ```
*(Questo workaround tecnico disattiva il flag `com.apple.quarantine` dal bundle applicativo).*

---

### Passo 3: Configurazione del Backend di Inferenza (Metal)

A.U.R.A. richiede un server di inferenza locale compatibile con l'API OpenAI / `llama.cpp` in ascolto su porta locale per dialogare con i modelli neurali (PANOPTICON e il Valutatore).

Puoi utilizzare la soluzione che preferisci tra le due seguenti:

#### Opzione A: LM Studio per Mac (La più semplice e visiva)
1. Scarica e installa [LM Studio per Mac (Apple Silicon)](https://lmstudio.ai/).
2. All'interno di LM Studio, scarica i modelli GGUF consigliati:
   * **Modello Attore (PANOPTICON):** `google/gemma-4-12b-it-qat-q4_0` (o `gemma-2-9b-it`);
   * **Modello Valutatore:** `mistralai/ministral-3-3b` (o modello equivalente leggero).
3. Vai nella scheda **Developer / Local Server** (icona `<->` sulla barra laterale).
4. Carica il modello desiderato e fai clic su **Start Server**.
5. Verifica che il server sia attivo all'indirizzo standard:
   `http://localhost:1234`

#### Opzione B: `llama-server` Nativo con Metal da Riga di Comando (Massime prestazioni)
Se disponi già di `llama.cpp` (ad esempio installato via Homebrew con `brew install llama.cpp` o binari precompilati per Mac ARM64):
1. Apri il Terminale e avvia `llama-server` abilitando tutti i layer sulla GPU Metal unificata:
   ```bash
   llama-server \
     -m /percorso/del/tuo/modello.gguf \
     -c 8192 \
     -ngl 99 \
     --host 127.0.0.1 \
     --port 1234
   ```
2. Il server utilizzerà al 100% i core Metal del tuo chip Apple Silicon garantendo oltre 25-40 token/s.

---

### Passo 4: Avvio del Gioco e Sessione di Playtest

1. Assicurati che il tuo server di inferenza locale (LM Studio o `llama-server`) sia in esecuzione.
2. Avvia **AURA** dalla cartella Applicazioni.
3. Se configurata la porta standard (`http://127.0.0.1:1234`), l'applicazione si collegherà automaticamente al backend locale.
4. **Gioca una partita:**
   * Ti chiediamo di completare **almeno 10 turni di dialogo** per consentire alle metriche di stato (Allerta, Dissonanza, Controllo) di evolvere ed emettere dati significativi.
   * Prova diversi stili di interazione con PANOPTICON (es. cooperativo, provocatorio, speculativo, avversario).

---

### Passo 5: Condivisione del Replay Log per il Dataset LoRA

Uno degli scopi primari del tuo test su Mac è la raccolta di log ad alta precisione scientifica. A.U.R.A. registra automaticamente ogni mossa e include i dettagli tecnici della tua macchina (senza raccogliere dati personali o IP).

1. Al termine della sessione o all'uscita dal gioco, apri il Finder e premi `Cmd + Shift + G` (Vai alla cartella).
2. Incolla il seguente percorso e premi Invio:
   ```text
   ~/Library/Application Support/AURA/replays/
   ```
3. Troverai i file di log delle tue partite salvati nel formato:
   ```text
   replay_<session_id>_<timestamp>.json
   ```
4. **Verifica Preventiva del Replay (Opzionale ma Raccomandata):**
   * Se disponi dell'SDK Dart o cloni il repository, puoi validare preventivamente che la sessione sia scientificamente qualificata per il dataset con il comando:
     ```bash
     dart run tool/replay/validate_playtest_replay.dart --replay ~/Library/Application\ Support/AURA/replays/replay_<tuo_file>.json
     ```
   * Il tool verificherà che la sessione contenga almeno 10 turni, che la provenienza hardware risponda ai requisiti (macOS ARM64 Metal) e che non vi siano stati fallback degradati. In caso di esito positivo riporterà il messaggio `[OK] PASS - PLAYTEST_VERIFIED`.
5. **Come inviarlo:**
   * Allega il file `.json` della partita all'issue GitHub dedicata al playtest o condividilo con il team di sviluppo tramite il canale concordato.
   * Il file contiene automaticamente la sezione `provenance` che certifica il comportamento del modello sul chip Apple Silicon (tempo di risposta, token al secondo, versione del kernel macOS, modello e sampling utilizzato).

---

## 4. Risoluzione Problemi Comuni (Troubleshooting)

### D: Il Mac mostra l'errore: "«AURA» è danneggiata e non può essere aperta. Dovresti spostarla nel Cestino."
* **Causa:** È la forma più aggressiva di Gatekeeper introdotta da macOS 14 Sonoma e macOS 15 Sequoia per le applicazioni scaricate via web senza firma Developer ID.
* **Soluzione:** Apri il Terminale ed esegui il comando di pulizia degli attributi:
  ```bash
  xattr -cr /Applications/AURA.app
  ```
  L'errore sparirà all'istante.

### D: L'applicazione parte ma resta ferma sulla schermata di connessione o dà errore di rete
* **Causa:** Il server locale di inferenza non è attivo o risponde su una porta differente.
* **Soluzione:**
  1. Controlla che LM Studio o `llama-server` sia avviato e non mostri errori di out-of-memory.
  2. Apri il browser Safari e vai all'indirizzo `http://127.0.0.1:1234/v1/models`: dovresti ricevere una risposta JSON con l'elenco dei modelli caricati.

### D: I caratteri grafici o gli shader del gioco appaiono strani o rallentati
* **Causa:** Su alcune configurazioni macOS con display ProMotion (120Hz), la sincronizzazione verticale di Flutter o gli shader Impeller possono subire cali di frame.
* **Soluzione:** Nelle impostazioni di gioco di A.U.R.A., attiva l'opzione **"Riduci effetti grafici"** e disattiva lo **"Shader Glitch"** per massimizzare la fluidità.

---

*Grazie per il tuo contributo al perfezionamento di A.U.R.A. e alla creazione del dataset sperimentale per i modelli futuri!*
