# Voce sintetica delle identità: analisi preliminare di fattibilità

| | |
|---|---|
| Stato | Proposta in valutazione. Spike eseguito il 25 novembre 2026 fuori dall'app, fino al runtime nativo (§11). Nessun codice o dipendenza introdotti nel gioco. |
| Data dell'analisi | 25 novembre 2026 |
| Baseline del codice | `70dbfe0` (branch `fase6`) |
| Collocazione | Fuori dal perimetro della Fase 6; eventuale ingresso in roadmap dopo lo spike |

## 1. Esito in breve

La voce è **fattibile su CPU e convive con Gemma e Ministral**; manca il prototipo dentro A.U.R.A.

- **Voce scelta per PANOPTICON:** Kokoro `im_nicola` con effetti a riverbero ridotto, approvata dall'utente all'ascolto
  alla cieca (§11.6, §11.8).
- **Fonetica:** propria di A.U.R.A., con lessico e regole scritti a mano, senza espeak-ng e quindi senza la sua GPL.
  Nei campioni ascoltati: vocali e «z» approvate dall'utente, accenti e doppie corretti per Antigravity (§11.11–11.15).
- **Runtime nativo:** eseguibile Dart con ONNX Runtime, senza Python; fonetica identica al prototipo e audio
  equivalente (§11.16).
- **Costo:** con gli LLM attivi Gemma perde circa l'1%, Ministral il 3–4%; primo audio circa 0,5 s, 1,1 s al
  90° percentile; la sintesi va divisa in frasi.
- Pocket `javert` resta candidato per un'identità antagonista futura.
- **Da fare:** prototipo nell'app Flutter, prove con il gioco attivo, Android, parole nuove fuori lessico, intonazione
  delle domande e verifica legale (pesi Kokoro Apache-2.0, ONNX Runtime MIT, origine dei dati della voce `im_nicola`).

## 2. Grado di evidenza

- **Misurato**: ricavato dai dati o dal codice di A.U.R.A.
- **Dichiarato**: scritto da chi pubblica il modello o il pacchetto; non riprodotto.
- **Stima**: calcolo nostro su ipotesi esplicite.
- **Ignoto**: da chiarire con lo spike.

## 3. Requisiti ricavati dal gioco

### 3.1 Lunghezza delle battute

Misurato su 294 battute uniche dei replay locali della workstation di sviluppo, esclusi per quanto riconoscibili
i ripieghi. I replay comprendono simulazioni e versioni diverse del gioco: il campione non rappresenta partite umane.

| | Mediana | 90° percentile | Massimo |
|---|---|---|---|
| Caratteri per battuta | 328 | 496 | 707 |
| Caratteri della prima frase (fino a `.`, `!`, `?`, `;`) | 89 | 213 | 422 |
| Frasi per battuta | 2 | 4 | 6 |

Conseguenze:

1. **La voce dura molto più del testo.** A circa 15 caratteri al secondo (ipotesi) la battuta mediana dura
   circa 22 s e quella al 90° percentile circa 33 s. L'effetto macchina da scrivere, a 15 ms per carattere, finisce
   la mediana in circa 5 s (stima). La voce deve essere interrompibile e non deve mai bloccare l'input.
2. **Serve la sintesi a blocchi**: sintetizzare l'intera battuta prima di parlare può essere troppo lento.
   Le prime frasi lunghe vanno divise anche sulle virgole, oppure serve un modello in streaming.
3. **Serve una normalizzazione**: 10 battute su 294 contengono parole in maiuscolo, 6 cifre e 4 più righe.
   Nessuna contiene Markdown. I tag `<dialogo>` vanno tolti prima della sintesi.

### 3.2 Risorse

- Misurato in precedenza: due modelli aggiungono 10.734 MiB di VRAM e un turno dura 7,6–7,7 s su RTX 3060 12 GB
  ([matrice hardware](phase6/HARDWARE_COMPATIBILITY_MATRIX.md)).
- Con GPU, `computeExecutionBudget` assegna 4 thread all'Attore e 2 al Valutatore. La CPU realmente libera durante
  un turno è **ignota**.
- La sintesi parte dopo la risposta dell'Attore: in quel momento gli LLM sono di norma fermi. La contesa nasce se
  il giocatore invia un nuovo turno mentre la voce parla ancora.
- Senza GPU gli LLM occupano già quasi tutti i core: lì la voce deve restare spenta per impostazione predefinita.

### 3.3 Distribuzione

Licenza che consenta la ridistribuzione, sorgente senza autenticazione, commit a 40 caratteri, SHA-256 e dimensione
esatta, come per i modelli LLM. La licenza va verificata per modello, **singola voce** e librerie.

## 4. Candidati

Dati letti il 25 novembre 2026 da schede ufficiali, API di Hugging Face, GitHub e pub.dev.

| | Pocket TTS | Supertonic 3 | Kokoro 82M | Qwen3-TTS |
|---|---|---|---|---|
| Italiano | Sì: base e `italian_24l` (qualità maggiore, più lento) | Sì | 2 voci, voto dell'autore **C** | Sì |
| Dimensione dei pesi | 208 MiB base, 641 MiB 24 livelli, più le voci | Circa 377 MiB ONNX | 312 MiB | Circa 2,4 GB (0.6B), 4,3 GB (1.7B) |
| Velocità dichiarata | Circa 6× il tempo reale su MacBook Air M4, 2 core, primo audio circa 200 ms | Veloce su CPU; nessun valore riportato qui | Non rilevata | 97 ms, senza garanzia per la nostra CPU |
| Streaming | Sì | Blocchi tramite callback di sherpa-onnx; granularità ignota | Da verificare | Sì |
| Espressività | Scelta del timbro | Tag `<laugh>`, `<breath>`, `<sigh>` | Scelta del timbro | Istruzioni nella tabella ufficiale solo per 1.7B |
| Voci | 27 voci per l'italiano; `giovanni` è indicata come italiana | 10 predefinite (F1–F5, M1–M5) | `if_sara`, `im_nicola` | 9, oppure VoiceDesign 1.7B |
| Licenza | Codice MIT, pesi CC-BY-4.0; **voci con licenze distinte** | Codice MIT, pesi OpenRAIL-M | Apache-2.0; fonemi italiani via espeak-ng | Apache-2.0 |
| Stato del progetto | Attivo (modifica del 23 novembre 2026) | **Archiviato, assistenza terminata** | Pesi fermi ad aprile 2025 | Pubblicato a gennaio 2026 |
| Flutter | sherpa-onnx supporta PocketTTS; **modello italiano convertito non trovato** | sherpa-onnx supporta Supertonic 3 | sherpa-onnx lo supporta | Nessuna via ufficiale individuata |

### 4.1 Valutazione

**Pocket TTS, prima scelta da provare.** Le velocità dichiarate riguardano un altro processore; per l'italiano a
24 livelli il valore specifico è ignoto. Il repository principale richiede l'accettazione di condizioni (gated) e non
rispetta la politica del progetto; `kyutai/pocket-tts-without-voice-cloning` è accessibile liberamente e contiene i
modelli e le voci italiane. CC-BY-4.0 richiede l'attribuzione nei crediti.

**Supertonic 3, piano B.** È il percorso di integrazione più breve. Il servizio Voice Builder per creare voci nuove
non fa parte dell'archivio: le identità future avrebbero solo le dieci voci esistenti. OpenRAIL-M impone di
trasmettere licenza e restrizioni d'uso, fra cui il divieto di diffondere contenuti senza dichiararli generati da una
macchina. Serve un'avvertenza nell'app e una verifica legale.

**Kokoro, termine di paragone.** Il voto basso delle voci italiane è dell'autore stesso. La dipendenza espeak-ng
(GPL) va valutata prima di ogni distribuzione.

**Qwen3-TTS, fuori dalla prima selezione.** È il più adatto a «interpretare» un'identità, ma la tabella ufficiale
assegna il controllo a istruzioni solo ai modelli 1.7B; la scheda e gli esempi dello 0.6B sono ambigui. Il peso e
l'assenza di una velocità nota su CPU lo rendono improbabile in tempo reale. Resta utile **in sviluppo** per disegnare
timbri, se la licenza consente poi di usarli come riferimento in un altro modello.

**Chatterbox**: licenza MIT e italiano dichiarati, ma i pesi principali sono attorno ai 2 GB. Non approfondito.

## 5. Interpretare la personalità

La voce non deve dedurre emozioni dal testo: A.U.R.A. conosce già lo stato drammaturgico. Tre livelli:

1. **Timbro**, fisso per identità.
2. **Stato di gioco**, da `ActorCue`: `alertLevel`, `dissonancePillar`, `controlPillar`, `deceptionPhase`.
   Regola velocità, pause e volume in modo deterministico.
3. **Catena di effetti**: filtro da impianto militare, riverbero, distorsione e disturbo con dissonanza alta.

Per PANOPTICON (`military_containment_ai`, «freddo, procedurale, strategico, sospettoso») una recitazione sobria è
un vantaggio: maschera i limiti di un modello leggero. Un'identità calda o ironica è più esigente e va inclusa nello
spike, altrimenti si approva un modello adatto al solo PANOPTICON.

Schema indicativo, da non implementare prima dell'approvazione:

```json
{
  "identity_id": "panopticon",
  "voice_profile": {
    "engine_voices": { "pocket_tts": "giovanni" },
    "base": { "speed": 0.95, "gain": 1.0, "sentence_pause_ms": 350 },
    "state_rules": [
      { "metric": "alertLevel", "min": 70, "speed": 1.08, "sentence_pause_ms": 180 },
      { "metric": "dissonancePillar", "min": 60, "effect": "glitch_light" }
    ],
    "effects": ["bandpass_pa", "reverb_vault"]
  }
}
```

I valori sono segnaposto. Vincolo: il profilo usa solo informazioni che il giocatore può già percepire. Una voce che
cambia con `deceptionKind` potrebbe **rivelare una trappola**; la mappatura dei campi di inganno va decisa dal game
design.

## 6. Architettura proposta

```text
ActorAgent -> risposta pulita -> GameController -> testo a schermo (invariato)
                                       |
                                       +-> VoiceDirector (ActorCue + profilo)
                                             -> SpeechEngine (isolate o processo, CPU)
                                             -> effetti -> canale voce -> ducking BGM
```

- **`SpeechEngine`** astratto e sostituibile, con implementazione silenziosa predefinita. Un errore produce silenzio,
  mai un turno fallito.
- **Nessun effetto sul loop**: nessun cambiamento a prompt, Valutatore, replay o dataset LoRA.
- **Annullamento** su nuovo turno, uscita, cambio schermata e perdita di focus secondo le preferenze.
- **Distribuzione opzionale**: pacchetto scaricabile, non nell'installer. `CatalogArtifactType` oggi conosce solo
  `runtime` e `model`; serve decidere se aggiungere un tipo voce.

### 6.1 Punti di integrazione verificati nel codice

| Punto | Osservazione |
|---|---|
| [`AudioManager`](../app/lib/src/audio/audio_manager.dart) | Master, musica ed effetti; manca il canale voce. Valgono master, memorizzazione prima di `initialize()` e `resetForTesting()` |
| [`AudioSceneMachine`](../app/lib/src/audio/audio_scene_machine.dart) | `setDucked` è **un solo booleano**, usato per il focus. Voce e focus devono sommarsi: la fine della voce non deve annullare il ducking del focus |
| [`CLIHistoryView`](../app/lib/src/widgets/cli_history_view.dart) | Il testo scorre a 15 ms per carattere. Al ripristino di una partita non deve partire alcuna voce |
| [`ActorCue`](../lib/src/models/actor_cue.dart) | Contiene già i dati necessari al livello 2 |
| [`IdentityDefinition`](../lib/src/models/identity_definition.dart) | Non ha campi voce; il profilo può stare in un file affiancato |
| [`ActorAgent`](../lib/src/agent_runtime/agents/actor_agent.dart) | Usa `generateText`, risposta completa: prima della voce si attende l'intero turno |
| [`computeExecutionBudget`](../lib/src/provisioning/application/inference_bootstrap_bridge.dart) | Va esteso con una quota per la voce, solo se lo spike mostra contesa |

## 7. Spike proposto

Fuori dall'app, 1–2 giorni, con modelli in una cartella dedicata. **Ogni download richiede il consenso esplicito**
con file, sorgente e dimensione.

1. Dodici battute da replay: brevi, lunghe, con maiuscole e cifre, con allerta bassa e alta. Due battute in un
   registro opposto, per un'identità futura.
2. Pocket TTS `italian` e `italian_24l`, Supertonic 3, Kokoro come riferimento.
3. Misure a macchina ferma e durante un turno reale: tempo al primo audio, rapporto col tempo reale, RAM, core
   usati, variazione di token/s di Attore e Valutatore.
4. Ascolto alla cieca dell'utente, con e senza catena di effetti.
5. Prova di integrazione nativa del vincitore su Windows; per Pocket TTS, modello italiano fuori da Python.
6. Verifica di licenze per modello, voce e librerie.

### 7.1 Criteri di approvazione

| Criterio | Soglia |
|---|---|
| Primo audio dopo la risposta | Al più 1 s, al 90° percentile |
| Velocità | Almeno 2× il tempo reale durante un turno |
| Rallentamento degli LLM | Al più 5% di token/s |
| RAM aggiuntiva | Al più 1,5 GB |
| Italiano | Approvato dall'utente alla cieca, senza errori che cambiano il senso |
| Personalità | PANOPTICON riconoscibile e distinto dalla seconda identità |
| Licenza | Ridistribuzione consentita per modello, voce e librerie |
| Integrazione | Funzionante senza Python su Windows |

Le soglie sono proposte iniziali. Se nessun candidato le supera, **niente voce**: una voce mediocre danneggia
l'atmosfera più del silenzio.

## 8. Rischi principali

| Rischio | Contromisura |
|---|---|
| Modello italiano di Pocket TTS fuori da Python: export ONNX italiano (KevinAHM), port C++ con API C e port Rust esistono, non provati | Prova nel punto 5 dello spike; altrimenti Supertonic 3 |
| Progetto a monte abbandonato | Interfaccia sostituibile, copia dei pesi fissata per hash |
| Voci non commerciali: la pagina licenze di Kyutai ne elenca (Expresso e altre CC BY-NC), accanto a CC0 e CC BY | Elenco di voci ammesse, verificate una per una; licenza di `giovanni` ancora da verificare |
| Pronuncia di acronimi e nomi del gioco | Dizionario di normalizzazione per identità |
| Battute troppo lunghe da ascoltare | Interruzione immediata e opzione spenta/solo prima frase |
| Android: memoria e calore | Valutazione separata nella Fase 7 |
| Imitazione di persone reali | Solo voci del catalogo con licenza verificata; nessuna clonazione nell'app |

## 9. Decisioni aperte

1. Autorizzare la prova di integrazione di Kokoro, compresa la soluzione alla dipendenza GPL.
2. Collocazione in roadmap: si suggerisce **insieme alle nuove identità della Fase 9**, con un eventuale prototipo
   PANOPTICON in anticipo.
3. Voce accesa o spenta al primo avvio: si suggerisce spenta.
4. Quali segnali di inganno possono influire sulla voce: si suggerisce nessuno.

## 10. Fonti

- Pocket TTS: [codice](https://github.com/kyutai-labs/pocket-tts), [pesi](https://huggingface.co/kyutai/pocket-tts),
  [pesi senza clonazione](https://huggingface.co/kyutai/pocket-tts-without-voice-cloning),
  [licenze delle voci](https://huggingface.co/kyutai/tts-voices)
- Supertonic 3: [pesi](https://huggingface.co/Supertone/supertonic-3),
  [codice archiviato](https://github.com/supertone-oss-archive/supertonic)
- Kokoro: [pesi](https://huggingface.co/hexgrad/Kokoro-82M),
  [voci e voti](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md)
- Qwen3-TTS: [codice e tabella dei modelli](https://github.com/QwenLM/Qwen3-TTS)
- Chatterbox: [pesi](https://huggingface.co/ResembleAI/chatterbox)
- sherpa-onnx: [pacchetto Flutter 2.0.3](https://pub.dev/packages/sherpa_onnx),
  [novità](https://pub.dev/packages/sherpa_onnx/changelog)

## 11. Risultati dello spike

Ryzen 7 7700X, Windows 11, sintesi in Python su CPU; 14 battute, 12 di PANOPTICON (dieci dai replay o loro estratti, due scritte per provare cifre e domande) e 2 di un'identità calda scritte per la prova.
File e script in `spike/tts/`, cartella esclusa da Git.

### 11.1 Prestazioni a macchina ferma (4 thread)

| Voce | Primo audio mediano / massimo | Tempo reale (mediana) | Core | RAM aggiunta |
|---|---|---|---|---|
| Pocket 6 livelli int8 | 0,05 / 0,06 s | 6,2× | 1,8 | 0,93 GB |
| Pocket 6 livelli | 0,10 / 0,12 s | 4,2× | 1,7 | 1,1 GB |
| Pocket 24 livelli int8 | 0,14 / 0,16 s | 2,3× | 1,3 | 1,7 GB (picco 2,3) |
| Pocket 24 livelli | 0,33 / 0,37 s | 1,5× | 1,2 | 2,5 GB |
| Supertonic 3 | 0,8 / 1,1–1,3 s | 6,3× | 4,4 | 0,5 GB |
| Kokoro | 0,67 / 1,2 s | 5,8× | 4,0 | 1,2 GB |

Supertonic e Kokoro sono stati alimentati una frase per volta: dividere anche sulle virgole ridurrebbe il primo audio.
La RAM comprende Python e PyTorch; un runtime nativo può essere diverso. Con 8 thread Supertonic non migliora.

### 11.2 Contesa con Gemma e Ministral

Due `llama-server` CUDA, Ministral e Gemma chiamati in alternanza continua mentre la voce sintetizza.

| | Gemma | Ministral |
|---|---|---|
| Senza voce (prima / dopo) | 40,6 / 41,0 token/s | 121,5 / 120,6 token/s |
| Con Pocket int8 | 40,9 | 117,9 |
| Con Pocket 24 livelli int8 | 40,7 | 117,3 |
| Con Supertonic M3 | 40,7 | 117,9 |
| Con Kokoro, 4 thread (riferimento: 41,1–41,3 e 121,1–121,4) | 40,8 | 117,6 |
| Con Kokoro, 2 thread | 40,8 | 118,4 |

Da 4 a 13 campioni per riga. La voce non ha rallentato e non ha avuto interruzioni. **Non provato**: con il gioco e
gli shader attivi, né con LLM su CPU.

### 11.3 Ascolto alla cieca di Gemini tramite Antigravity

File anonimi, testo e chiave non forniti, due modelli (Gemini 3.8 Flash e Gemini 4 Argon). Controlli: una voce con fonetica
inglese e una voce duplicata. Il controllo negativo è stato riconosciuto come straniero da entrambi (pronuncia 4 e 2),
quindi l'ascolto è reale. La voce duplicata ha ricevuto voti distanti fino a 4 punti sul registro caldo: **scarti
di 1–2 punti non sono significativi**. Entrambi i giudici sono della stessa famiglia e non sostituiscono una persona.

Turno finale con numeri in lettere e senza puntini di sospensione, media dei due giudici (1–10):

| Voce | Naturalezza | Pronuncia | Senza artefatti | PANOPTICON | Registro caldo |
|---|---|---|---|---|---|
| Kokoro `im_nicola` | 8,5 | 9 | 8,5 | 8 | 6 |
| Supertonic `M3` | 8 | 8 | 7 | 7,5 | 7 |
| Pocket 24 livelli int8 `giovanni` | 7,5 | 8 | 8,5 | 8,5 | 4,5 |
| Pocket 6 livelli `javert` | 7 | 8 | 7 | 8,5 | 4,5 |
| Supertonic `M1` | 7 | 7,5 | 8 | 8 | 5 |

Difetti ricorrenti:

- Pocket legge male le cifre (tutte le voci provate) e a volte **salta parole** attorno a «è...» o in fine
  battuta; con `charles` int8 il finale di una battuta è stato tagliato in 3 ripetizioni su 3. `javert` ha letto senza
  salti dieci ripetizioni, ma aveva saltato parole nel primo turno.
- Supertonic legge «03:15» in modo anomalo e ha un accento anglofono lieve su alcuni termini.
- Kokoro è piatto nelle domande e nel registro caldo.
- «Escalation», «audit» e «Panopticon» vanno in un dizionario di pronuncia.

### 11.4 Licenze delle voci

`javert` proviene dalle donazioni CC0; `charles` da VCTK, CC BY 4.0; `jean` (EARS) e `cosette` (Expresso) sono
non commerciali e vanno escluse. `giovanni` viene da Common Voice: termini del file migliorato da verificare.
La fonetica italiana di Kokoro passa da espeak-ng (GPL). Pocket vieta gli usi ingannevoli.

### 11.5 Esito rispetto ai criteri

| Criterio | Pocket 6 livelli | Pocket 24 livelli int8 | Supertonic 3 | Kokoro |
|---|---|---|---|---|
| Primo audio ≤ 1 s | Superato | Superato | Limite, dividere le frasi | Limite, dividere le frasi |
| ≥ 2× tempo reale, sotto carico | Superato (int8) | Superato di poco (2,2×) | Superato | Superato |
| Rallentamento ≤ 5% | Superato (int8) | Superato | Superato | Superato |
| RAM ≤ 1,5 GB | Superato | **Non superato in Python** | Superato | Superato |
| Italiano approvato dall'utente | Con riserva, altra identità | No | Riserva (`M1`) | **Sì**, con le correzioni da confermare all'ascolto |
| Due identità distinguibili | In attesa | Debole sul caldo | In attesa | In attesa |
| Licenza | Plausibile | `giovanni` da verificare | OpenRAIL-M da verificare | espeak-ng da risolvere |
| Nativo senza Python | Da provare | Da provare | Supportato da sherpa-onnx, da provare | Supportato da sherpa-onnx, da provare |

L'indicazione provvisoria data dopo le sole misure (Pocket `javert`) è superata dalla scelta in §11.6.

### 11.6 Scelta d'ascolto

L'utente conferma il giudizio di Antigravity, formulato sui file anonimi, di cui aveva notato da sé le stesse caratteristiche.

| File anonimo | Voce | Giudizio |
|---|---|---|
| `voce_04` | Kokoro `im_nicola` | **Prima scelta per PANOPTICON**, con effetti; correggere «Panoptìcon» |
| `voce_02` | Supertonic `M1` | Riserva, più asettica |
| `voce_01` | Pocket 6 livelli `javert` | Naturale e inquietante: possibile identità malvagia; inglesismi letti all'italiana |
| `voce_03` | Pocket 24 livelli `giovanni` | Spontanea ma troppo colloquiale |
| `voce_05` | Supertonic `M3` | Meno autorevole, inciampa su una battuta |

Effetti: sì, con il 15–20% in meno di coda del riverbero per le sessioni lunghe.

### 11.7 Correzione della pronuncia

Quattro battute, cinque file anonimi, due giudici Gemini.

| Voce | Metodo | Esito |
|---|---|---|
| Kokoro | Sostituzione dei **fonemi** per parola | «Panòpticon», «escalation», «firewall», «sandbox»: corretti per entrambi i giudici |
| Pocket `javert` | **Riscrittura** del testo («eschelèiscion», «Panòpticon») | Corretti in due generazioni su due «escalation», «Panopticon» e «firewall»; «sandbox» e «audit» instabili |

- Difetto residuo comune: «Perché insisti?» suona come un'affermazione. Su Kokoro corretto i giudici sono discordi.
- Il dizionario copre i termini noti; le parole nuove generate dall'Attore restano un rischio.
- Kokoro accetta fonemi in ingresso: espeak-ng si può quindi sostituire, in linea di principio, con un convertitore
  italiano dalla licenza compatibile. Accento tonico e vocali aperte sono la parte difficile; **non provato**.
- Sotto contesa Kokoro mantiene 5,6× con 4 thread (primo audio 0,73 s, massimo 1,32 s) e 3,2× con 2 (1,25 s,
  massimo 2,14 s): servono 4 thread e frasi divise. Il runtime nativo non è ancora stato provato.

### 11.8 Giudizio sulle correzioni

Il riascolto riportato dall'utente promuove Kokoro corretto con la catena a riverbero ridotto
(`prova_1_fx`): **voce ed effetti di riferimento per PANOPTICON**. L'intonazione piatta di «Perché insisti?» è accettata
per questo personaggio. Pocket `javert` resta candidato a un'identità antagonista, con «sandbox», «audit» e le
domande da risolvere. Il limite delle domande resta aperto per le identità espressive.

### 11.9 Kokoro senza espeak-ng

Prototipo di regole ortografiche italiane scritto per lo spike, provato su 306 battute uniche dei replay (2.200 parole
uniche). Riferimento: accento di espeak-ng, che può a sua volta sbagliare.

| | Parole con accento diverso | Battute con almeno una |
|---|---|---|
| Solo regole (metà delle battute non vista) | 9,0% delle occorrenze | 91% |
| Regole e lessico di 154 parole ricavato dall'altra metà | 2,0% | 42% |

Sei battute non viste, ascolto alla cieca di due giudici Gemini, stessa voce:

| Fonetica | Pronuncia | Naturalezza | Errori gravi segnalati | Parole riconosciute |
|---|---|---|---|---|
| espeak-ng | 10 / 9 | 8 / 9 | 0 / 1 | Tutte |
| Regole e lessico | 9 / 7 | 8 / 8 | 1 / 3 | Tutte |
| Solo regole | 7 / 4 | 6 / 6 | 3 / 8 | Tutte |

- L'approccio funziona e non ha bisogno dei fonemi di espeak-ng. Le sole regole non bastano («essère», «nuclèo»).
- Il lessico della prova usava la posizione dell'accento di espeak-ng **come sostituto**: il lessico vero va costruito
  da una fonte compatibile e non da espeak-ng.
- WikiPron, inizialmente indicato come fonte, non è adatto: vedi §11.10.
- Punti deboli residui: verbi sdruccioli con pronomi («fondendoci»), vocali aperte e chiuse, parole nuove.

### 11.10 Esito del lessico WikiPron: non adatto

File `ita_latn_broad_filtered.tsv`, commit `d282e848a211ea31cfd730f0ced8bc8cdab9e83d`, SHA-256
`231c78d1fb89f1f03ad7420b69003023b84863d877ce82ee72d2590fa470b78a`, 2.613.530 byte, 81.354 parole.

- Copre il 69,0% delle parole uniche e l'81,5% delle occorrenze dei replay, ma **nessuna riga contiene
  l'accento tonico**, cioè l'informazione necessaria.
- Deducendolo dalle vocali aperte e dallo iato finale «ia», le parole diverse da espeak-ng passano dal 9,2% al **9,5%**
  delle occorrenze: nessun miglioramento. La deduzione è stata semplice; non se ne sono provate di più elaborate.
- Contiene il timbro delle vocali e potrebbe servire solo per quello. Il README rimanda alle condizioni proprie del
  Wikizionario per i dati.
- Non si è ripetuto l'ascolto: senza accenti non avrebbe misurato nulla di nuovo.

Strade rimaste, non provate:

1. **Estratto Wiktionary di Kaikki** (italiano, 73 MiB compresso): da verificare che riporti l'accento; licenza con
   condivisione allo stesso modo da valutare.
2. **Lessico proprio di A.U.R.A.**: accenti scritti e rivisti per il vocabolario ricorrente dei replay (2.200 parole,
   233 diverse dalle regole), più regole per verbi e pronomi. Nessun vincolo di terzi, ma non copre le parole nuove.
   Nella prova di §11.9 un lessico di questo tipo ha portato le parole diverse dal 9,0% al 2,0%.

### 11.11 Lessico proprio di A.U.R.A.

Circa 190 parole accentate a mano e regole per infiniti, pronomi enclitici, terze persone plurali, suffissi sdruccioli,
dittonghi e iati (`spike/tts/lessico_aura.txt`, `g2p_it2.py`). L'elenco delle parole da trattare nasceva dalle differenze
con espeak-ng; gli accenti sono stati scritti indipendentemente.

Prova su 40 battute **nuove**, generate da Gemma 4 su temi diversi (330 parole, 126 mai viste nei replay):

| | Accento diverso da espeak-ng | Battute con almeno una differenza |
|---|---|---|
| Regole di base | 9,3% delle occorrenze | 88% |
| Lessico e regole nuove | **1,3%** | **20%** |

Dei 6 vocaboli diversi, 5 sono errori nostri («semantica», «poesia», «ambigua», «filosofia», «ripristino»); su
«verrai» la differenza è del conteggio. Alcune differenze nei replay sono invece errori di espeak-ng («valuto»).

Dieci battute nuove, ascolto alla cieca, due giudici Gemini (due file per voce e per giudice):

| Fonetica | Pronuncia media | Naturalezza media | Errori gravi segnalati | Parole riconosciute |
|---|---|---|---|---|
| espeak-ng | 9,25 | 8,25 | 1 | Tutte |
| Lessico e regole di A.U.R.A. | 8,5 | 7,75 | 3 | Tutte |

- Le differenze rientrano nell'oscillazione dei giudici (§11.3); nessuna segnalazione grave è stata confermata da entrambi.
- Difetto reale trovato: le doppie «rr» e «mm» suonavano scempie per una diversa scrittura dei fonemi.
- Dopo l'ascolto si sono corretti doppie e i 5 errori. Le correzioni sono state controllate solo sui simboli,
  **non riascoltate**.
- Il timbro di «e» e «o» non segnate è sempre chiuso: è la differenza più udibile rimasta.

**Esito:** espeak-ng non è indispensabile. Restano il lessico in formato di prodotto con test, l'ascolto dell'utente, il
runtime nativo e la verifica legale.

### 11.12 Riascolto delle correzioni

Antigravity ha riascoltato alla cieca le dieci battute rigenerate (`spike/tts/own2`): doppie «rr» e «mm» risolte e nessun
errore evidente di accento in entrambe le versioni. Giudica `s_2` pienamente utilizzabile.

Ha poi attribuito `s_1` a espeak-ng e `s_2` ad A.U.R.A.: **è il contrario**. La chiave è stata riverificata rigenerando
l'audio (correlazione 0,985–0,992 con il file corrispondente, 0,12–0,30 con l'altro). Dunque:

- la versione a cui riconosceva le vocali aperte «secondo lo standard» e attribuiva a espeak-ng è quella **di A.U.R.A.**;
- la descrizione delle vocali non corrisponde ai fonemi: in `s_1` «cella», «processo», «parola» e «server» sono
  chiuse, mentre «porta» ed «essere» sono aperte in entrambe le versioni;
- il lessico proprio ha avuto il giudizio migliore sul timbro, ma è **una sola scelta tra due**: non dimostra che le
  versioni siano indistinguibili. I giudizi automatici sul timbro di «e» e «o» non vanno usati come prova;
- l'apertura delle vocali resta una rifinitura facoltativa (su queste battute le toniche aperte sono 11 contro 29).

### 11.13 Timbro di «e» e «o»

Ascolto dell'utente: le due versioni sono «talmente simili che è molto facile confonderle», ma `s_2` (espeak-ng) pronuncia
correttamente le «o». Il contrasto descritto da Antigravity in §11.12 era quindi reale, con i due nomi invertiti.

Si sono aggiunte regole scritte a mano sul timbro delle toniche (`spike/tts/g2p_it3.py`). Regole congelate, poi provate
su 40 battute generate **dopo** (299 toniche «e»/«o», confronto con espeak-ng):

| | «o» diverse | «e» diverse |
|---|---|---|
| Versione precedente | 22,6% | 32,9% |
| Con le regole del timbro | **1,9%** | 27,1% |

- Le «o» diverse rimaste sono 3 parole, di cui 1 errore nostro («vergogna») e 2 dubbi a favore nostro («biologiche»,
  «psicologiche»).
- Sulle «e» il divario dipende soprattutto da «procedere» e derivati, molto frequenti, per cui la pronuncia adottata è
  quella aperta («procèdere»); espeak-ng la dà chiusa. Altre sono errori nostri («silenzio», «quarantena», «sequestro»).
- L'accento tonico diverge nell'1,4% delle occorrenze sulle stesse battute, come nella prova precedente.
- Dopo la misura si sono aggiunte 14 parole al lessico. I nuovi campioni (`spike/tts/own3`) **non sono ancora stati
  ascoltati**; le attribuzioni agli errori di espeak-ng sono un giudizio, non verificate su un dizionario.

### 11.14 Riascolto di `own3` e correzione delle «z»

Ascolto alla cieca dell'utente: `t_1` (espeak-ng) sbaglia solo le «e» di «rete» e «neve»; `t_2` (A.U.R.A.) ha le vocali
**corrette**, ma le «z» suonano «con la zeppola». Il timbro delle vocali è quindi approvato.

Antigravity, letta la chiave, ha indicato due cause, verificate sul codice:

| Causa | Riscontro |
|---|---|
| «zi» + vocale resa `ʦj` invece di `ʦi` («azione») | Nostra in 58–81% delle parole con «z»; espeak-ng la usa raramente, ma non mai («grazie») |
| «zz» e «z» sempre sorde («analizzare», «zona», «mezzo») | Sonorità diversa da espeak-ng nel 14–23% delle parole con «z» |
| «non» tonico | Confermato |

Non si è separato quale delle prime due produca la zeppola: sono state corrette insieme (`spike/tts/g2p_it4.py`).
Su 30 battute generate dopo la scrittura delle regole (83 parole con «z»):

| | Prima | Dopo |
|---|---|---|
| Sonorità diversa da espeak-ng | 22,9% | 2,4% |
| `ʦj` | 62,7% | 0% |
| Accento tonico diverso | – | 0,6% delle occorrenze |

Errori residui trovati e poi corretti: «autorizzo», «autorizza», «automatizzata», «magazzino», «dialogo», «facilita».
I campioni `spike/tts/own4` (espeak-ng, versione precedente, versione corretta, ordine casuale) non sono ancora stati
ascoltati.

### 11.15 Esito dell'ascolto delle «z»

Ascolto alla cieca dell'utente su `own4`: `z_1` conserva il difetto (tutte le «z» suonano dolci); in `z_2` e `z_3` le «z» dure
sono corrette. Chiave: `z_1` versione precedente, `z_2` **A.U.R.A. corretta**, `z_3` espeak-ng. **Difetto risolto e
fonetica di A.U.R.A. approvata dall'utente per un prototipo**: accenti e doppie senza errori evidenti, vocali e «z» corrette nei
campioni ascoltati.

Nella versione difettosa tutte le «z» erano scritte sorde: se suonavano dolci, la causa più probabile è `ʦj`, resa
così da Kokoro. Non è stato isolato.

Restano: parole nuove fuori lessico, intonazione delle domande, formato di prodotto con test, runtime nativo senza
Python e verifica legale.

### 11.16 Prova nativa senza Python

Eseguibile Dart AOT (`spike/tts/native/kokoro.exe`, 6,6 MB) che chiama ONNX Runtime 1.32 tramite FFI, con la fonetica
di A.U.R.A. riscritta in Dart. Modello `onnx-community/Kokoro-82M-v1.0-ONNX`, `onnx/model.onnx`, commit
`1939ad2a8e416c0acfeecc08a694d14ef25f2231`, 325.532.232 byte, SHA-256
`8fbea51ea711f2af382e88c833d9e288c6dc82ce5e98421ea61c058ce21a34cb`. Libreria `onnxruntime.dll` di 22,7 MB, presa
dal pacchetto Python per comodità dello spike.

| Verifica | Esito |
|---|---|
| Fonetica Dart contro Python | Identica su 82.559 casi (battute, vocabolario, lessico WikiPron) |
| Audio contro la versione PyTorch | Stessa durata; correlazione degli spettri 0,98 su 6 battute |
| Ambiente senza Python né `PATH` utente | Funziona con il solo eseguibile e la DLL |
| 300 battute di fila | Nessun errore; memoria stabile attorno a 800 MiB dopo le prime 100 |

Prestazioni su 20 battute nuove, modello caricato in 0,5 s:

| Configurazione | Primo audio mediano / 90° perc. / max | Tempo reale | RAM aggiunta |
|---|---|---|---|
| 4 thread, battuta intera | 2,35 / 2,99 / 3,15 s | 5,7× | 0,93 GB |
| 4 thread, una frase per volta | 0,54 / 1,08 / 1,17 s | 6,2× | 0,6 GB |
| 6 thread, frasi e prima virgola | 0,46 / 0,92 / 0,96 s | 7,4× | 0,6 GB |
| 2 thread, una frase per volta | 0,91 / 1,73 / 1,89 s | 3,8× | 0,6 GB |

Con Gemma e Ministral in generazione continua (4 thread, 100 battute): Gemma 41,1 → 40,6 token/s, Ministral 122,1 → 116,8
(−4,3%; −3,2% rispetto alla misura finale senza voce); primo audio 0,55 / 1,09 / 1,23 s, nessuna interruzione.

- La divisione in frasi è obbligatoria; per stare sotto 1 s al 90° percentile servono 6 thread o blocchi più brevi.
- Gli indici delle funzioni di ONNX Runtime non sono stati letti dall'intestazione C (repository non raggiungibile);
  sono stati verificati dal funzionamento, non dalla documentazione.
- **Non provato**: dentro l'app Flutter, con il gioco e gli shader attivi, su Android e con LLM su CPU. Gli shader usano la GPU;
  il gioco in sé non è stato misurato.
- Campioni prodotti dall'eseguibile, mai ascoltati: `spike/tts/native/ascolto`.

## 12. Piano di implementazione

Piano proposto e approvato dall'utente il 2026-11-26, dopo lo spike. Ogni tranche si chiude con analisi senza diagnostiche, test, commit e
revisione dell'utente prima della successiva; nessuna tranche anticipa il contenuto delle altre.

| Tranche | Contenuto | Download |
|---|---|---|
| **V1 — Testo e fonetica** | In `aura_core`: pulizia del testo (tag `<dialogo>`, numeri in lettere, sigle), divisione in frasi, fonetica italiana e lessico portati dallo spike, con test di regressione | Nessuno |
| **V2 — Motore di sintesi** | Contratto `SpeechEngine`, motore silenzioso di ripiego e motore Kokoro tramite ONNX Runtime (FFI); file messi a mano in una cartella di sviluppo; prova da riga di comando | ONNX Runtime da fonte ufficiale, previo consenso |
| **V3 — Voce nel gioco** (divisa in V3a, V3b, V3c) | Profilo voce accanto all'identità; regolazioni da `ActorCue`; catena di effetti; canale voce con abbassamento della musica combinato al focus; interruzione a ogni nuovo turno; nessuna voce al ripristino; **opzione voce on/off** (spenta per impostazione predefinita) e **sincronizzazione del testo** | Nessuno |
| **V4 — Distribuzione** | Modello e libreria scaricabili dal catalogo firmato, verifica di hash e licenze; misura con il gioco attivo | Nessuno in più |

### 12.1 Opzioni e sincronizzazione (V3)

- Opzione «Voce» nella sezione audio delle impostazioni. Rispetta l'audio generale come musica ed effetti: con l'audio
  generale spento la voce tace e mostra `[MUTED]`.
- **Sincronizzazione frase per frase**: ogni frase compare quando inizia il suo audio e scorre alla velocità della voce,
  calcolata dalla durata dell'audio sintetizzato. Non richiede i tempi delle singole parole, che il modello ONNX non
  restituisce.
- Con voce spenta o non disponibile il testo scorre come oggi; un errore della voce non ritarda mai il testo oltre il
  primo audio previsto.
- Sincronizzazione **parola per parola**: rinviata. Richiede di riesportare il modello per ottenere le durate dei
  fonemi.

### 12.2 V1 completata (2026-11-26)

Modulo `lib/src/speech/` di `aura_core`, esportato da `package:aura_core/aura_core.dart`; nessuna dipendenza nuova,
nessun collegamento ancora con il gioco.

| Componente | Ruolo |
|---|---|
| `SpeechTextNormalizer`, `ItalianNumberWords` | Tolgono tag e formattazione; scrivono in lettere numeri, orari, percentuali e decimali; leggono le sigle note |
| `SpeechSegmenter`, `SpeechSpan` | Dividono il **testo mostrato** in frasi e ne restituiscono le posizioni, per la sincronizzazione della V3; primo blocco diviso alla prima virgola utile |
| `ItalianPhonemizer` | Fonetica italiana dello spike, con lessico e regole incorporati |
| `SpeechTextPlanner`, `SpeechChunk` | Uniscono i tre passaggi: per ogni blocco, testo mostrato, testo pronunciato e fonemi |

- I test confrontano la fonetica con 1.600 trascrizioni registrate dal prototipo (`test/fixtures/speech_phonemes_it.json`):
  tutte identiche. Le parole di WikiPron sono state escluse dalla fixture.
- Errori trovati scrivendo i test e corretti: «dodici», «tredici», «quattordici», «sedici» e «venti» uscivano con vocale
  aperta, «sette» chiusa, «virgola» con l'accento sbagliato, «uno» numerale atono e la «s» di «ventisei» sonora.
  Le correzioni non sono state ascoltate.
- Il testo da pianificare deve essere già privo dei tag dell'agent-loop, come quello mostrato a schermo.

### 12.3 V2 completata (2026-11-26)

| Componente | Entrypoint | Ruolo |
|---|---|---|
| `SpeechEngine`, `SpeechAudio`, `SpeechVoiceRequest`, `SpeechEngineException` | `aura_core` | Contratto del motore, audio prodotto, velocità, errori tipizzati con messaggi senza percorsi |
| `SilentSpeechEngine` | `aura_core` | Ripiego silenzioso per voce spenta o non disponibile |
| `encodePcm16Wav` | `aura_core` | Scrittura WAV PCM 16 bit |
| `KokoroTokenizer`, `KokoroVoiceStyle` | `aura_offline` | Simboli del modello (vocabolario Apache-2.0 incorporato) e stili della voce |
| `KokoroOnnxSpeechEngine`, `KokoroEngineFiles` | `aura_offline` | Kokoro con ONNX Runtime via FFI, in un **isolate dedicato**: la sintesi non blocca l'interfaccia |

Nuova dipendenza: `ffi` (pacchetto del team Dart). Nessun file del motore nel repository.

**ONNX Runtime 1.32.0** dal pacchetto NuGet ufficiale `microsoft.ml.onnxruntime.1.32.0.nupkg` (184.391.411 byte,
SHA-512 uguale a quello pubblicato da NuGet). `onnxruntime.dll` win-x64: firma Authenticode valida di Microsoft
Corporation, SHA-256 `348c3d29d6995eee37e3451825eaddb7ea7400be3afda6ca2286b12bc775f042`, licenza MIT. I 19 indici della
tabella `OrtApi` usati sono stati **verificati sull'intestazione ufficiale** del pacchetto, non più ricavati da memoria.
Il repository GitHub di ONNX Runtime risultava irraggiungibile da questa macchina.

Verifiche:

- Test standard (senza codice nativo): contratto, motore silenzioso, WAV, tokenizzatore (copertura di tutti i simboli
  della fonetica italiana), stili, file mancanti o non validi, rilascio single-flight.
- Runner opt-in `tool/tests/speech_native_runner.dart` (`AURA_TEST_RUNTIME_POLICY=nativeSmoke`): 13 verifiche superate
  sul motore reale, tra cui richieste concorrenti, effetto della velocità, blocco troppo lungo e libreria assente.
- Strumento `tool/speech/aura_speak.dart`: sintetizza battute in WAV. File di sviluppo in `.local/speech/`, escluso da Git.

Prestazioni con lo strumento compilato, 4 thread, 20 battute nuove: primo audio mediano 0,85 s, 90° percentile
1,65 s, 4,0× il tempo reale. L'eseguibile dello spike, rieseguito nelle stesse condizioni, dà gli stessi valori
(contro 0,54 s e 6,2× misurati nello spike): la differenza viene dal carico della macchina, con altri programmi
attivi, non dal codice. Cambiare la DLL (pip o NuGet) non cambia nulla.

Limiti noti, da affrontare nella V3:

- Se il primo blocco è lungo e senza virgole, il primo audio arriva tardi (fino a 1,8 s).
- I puntini di sospensione dividono la frase in due blocchi: introducono una pausa, oggi non valutata all'ascolto.
- I campioni della V2 (`.local/speech/v2`) non sono ancora stati ascoltati.

### 12.4 V3 divisa in tre sotto-tranche

| Sotto-tranche | Contenuto |
|---|---|
| **V3a** | Nel core, senza interfaccia: profilo voce per identità, regia dallo stato di gioco, catena di effetti in Dart |
| **V3b** | Nell'app: ciclo di vita del motore, riproduzione, abbassamento della musica combinato al focus, interruzioni, nessuna voce al ripristino, opzione «Voce» |
| **V3c** | Sincronizzazione del testo frase per frase |

### 12.5 V3a completata (2026-11-26)

| Componente | Ruolo |
|---|---|
| `VoiceProfile`, `VoiceEffectSettings`, `VoiceAlertRule` | Profilo voce di un'identità, validato in modo rigoroso (chiavi ammesse, intervalli, nome del file voce senza percorsi) |
| `VoiceDirector`, `VoiceDirection` | Velocità e pausa tra i blocchi dall'allerta; effetti dal profilo |
| `VoiceEffectChain` | Passa-alto, passa-basso, compressore, eco e guadagno in Dart, senza dipendenze native |
| `app/assets/config/panopticon_voice.json` | Profilo di PANOPTICON: voce `im_nicola`, effetti approvati in §11.8, voce un po' più rapida e pause più brevi da allerta 70 |

- **Decisione di game design:** la regia usa **solo l'allerta**, che il giocatore vede già nello sfondo. Pilastri e
  inganni fanno parte del modello di gioco nascosto e la voce non deve rivelarli (§5); un test lo verifica.
- **Equivalenza con gli effetti approvati:** sulle tre battute della V2, la catena in Dart e quella ffmpeg ascoltata in
  §11.8 hanno correlazione 0,99 sull'onda e 0,998 sullo spettro, volume entro 0,2 dB e bande entro 0,35 dB; i picchi
  dei transienti sono un po' più alti in Dart (0,39 contro 0,30). Elaborazione: 31 ms per 12 s di voce.
- Le regole di allerta (velocità 1,06, pause 0,6) sono una proposta, non ancora ascoltata. Campioni con effetti in
  `.local/speech/fx/` (`dart_*.wav` e i corrispondenti `ffmpeg_*.wav`).

### 12.6 V3b completata (2026-11-26)

| Componente | Ruolo |
|---|---|
| `WindowPreferences.voiceEnabled`, `DesktopShellController.setVoiceEnabled` | Preferenza «Voce», **spenta** per impostazione predefinita, salvata come musica ed effetti |
| `AudioManager.setVoiceDucked` | Abbassamento della musica combinato: attivo se la finestra non ha il focus **oppure** se la voce parla |
| `VoiceService` (`app/lib/src/speech/`) | Pianifica, sintetizza con anticipo il blocco successivo, applica gli effetti, riproduce; ogni battuta interrompe la precedente; qualsiasi errore rende la voce muta senza toccare il gioco |
| `VoiceAssetLocation`, `createDesktopVoiceService` | File del motore in `speech/` accanto all'eseguibile (`model.onnx`, `onnxruntime.dll`, `voices/<voce>.bin`) o in `AURA_SPEECH_DIR`; se mancano, la voce è «non disponibile» |
| Opzione nelle impostazioni | «Voce di PANOPTICON (sperimentale)» con `[MUTED]` ad audio generale spento e `[NON DISPONIBILE]` senza file; attivarla riaccende l'audio generale |

Comportamento nel gioco: parla dopo ogni risposta dell'Attore, escluso l'avviso di sistema tra parentesi quadre che
può precederla; si interrompe all'invio di un nuovo turno, a nuova partita, tutorial, ripristino, uscita dal terminale,
audio generale spento e chiusura dell'app. **Al ripristino di una partita non parla.** Le battute del tutorial non
vengono pronunciate.

Verifiche:

- 18 nuovi test dell'app (servizio voce con motore e riproduzione finti, abbassamento combinato, impostazioni, testo
  pronunciato) e un test della preferenza nel core.
- **Prova nella build di sviluppo** con il computer use: opzione disponibile, attivata e salvata; al ripristino nessun
  file audio generato; dopo un turno reale (Gemma e Ministral su CUDA) tre blocchi sintetizzati e riprodotti in
  sequenza, ciascuno avviato al termine del precedente; chiusura dalla finestra senza processi residui.
- Non verificato: ascolto in gioco (l'audio non è udibile dall'agente), interruzione con un nuovo turno nella build
  reale (coperta dai test), effetto delle regole di allerta.
- I file del motore sono stati copiati a mano nella build; il loro inserimento nell'installer è la V4.
