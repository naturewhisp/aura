# A.U.R.A. — Audio Asset Packaging Specification

**Documento:** `docs/phase6/AUDIO_ASSET_PACKAGING_SPEC.md`  
**Fase di origine:** 6.7 — Definitive WAV Import, Manifest & Packaging  
**Tipo:** specifica as-built e contratto di release  
**Stato:** implementato; documento ricostruito dalla baseline applicativa  
**Baseline iniziale:** `1c9015da6c5f445c13e82fa5df0c4d49e0830429`  
**Target iniziale:** Windows x64

---

## 1. Scopo

Questa specifica definisce il lifecycle degli asset audio ufficiali A.U.R.A.:

```text
sorgente di import esplicita
→ validazione WAV
→ manifest canonico
→ sorgente versionata
→ bundle Flutter
→ portable e installer
→ verifica runtime
```

Gli obiettivi sono:

- build riproducibili negli input;
- nessuna dipendenza implicita da AppData;
- inventario completo;
- verifica SHA-256;
- fail-closed sui file obbligatori;
- uso di logical ID nel runtime;
- separazione fra audio ufficiale e file utente;
- fallback sicuro in assenza di audio.

---

## 2. Source of truth

La sorgente canonica di release è:

```text
distribution/audio/
```

Contenuto minimo:

```text
distribution/audio/
  audio-manifest.json
  bgm_main.wav
  bgm_ambient.wav
  bgm_tense.wav
  bgm_epic.wav
  sfx_click.wav
  sfx_alert.wav
  sfx_glitch.wav
  sfx_chime.wav
```

La cartella utente:

```text
%APPDATA%\aura\audio\
```

non è una sorgente implicita di build.

Può essere usata esclusivamente come sorgente di un'importazione esplicita tramite tool.

---

## 3. Importazione esplicita

Entry point:

```powershell
.\tool\import_release_audio.ps1 `
  -SourcePath "$env:APPDATA\aura\audio" `
  -DestinationPath "distribution/audio" `
  -AppAssetPath "app/assets/audio"
```

Lo script PowerShell delega a:

```text
tool/import_release_audio.dart
```

Responsabilità dell'importer:

- inventario sorgente;
- verifica dei track richiesti;
- verifica RIFF/WAVE;
- verifica formato audio;
- calcolo SHA-256;
- calcolo dimensioni;
- generazione manifest;
- copia verso sorgente canonica;
- copia verso asset Flutter;
- promozione solo dopo validazione completa;
- fallimento con exit code non-zero in caso di errore.

L'import non deve essere eseguito automaticamente da:

```text
flutter build
dart test
GitHub Actions CI ordinaria
package_release.ps1
```

La promozione di nuovi WAV è un atto esplicito, reviewable e committato.

---

## 4. Manifest canonico

Percorso:

```text
distribution/audio/audio-manifest.json
```

Schema iniziale:

```json
{
  "schemaVersion": 1,
  "audioSetId": "aura.windows.release.v1",
  "tracks": []
}
```

Ogni track include:

```text
id
kind
role
filename
sizeBytes
sha256
codec
sampleRate
channels
bitsPerSample
durationMs
loop
required
```

### 4.1 Semantica campi

`id`  
Logical ID stabile usato dal runtime.

`kind`  
Categoria generale:

```text
bgm
sfx
```

`role`  
Ruolo semantico, non necessariamente uguale al filename.

`filename`  
Nome relativo, senza directory esterne.

`sizeBytes`  
Dimensione esatta intera.

`sha256`  
Digest esadecimale lowercase di 64 caratteri.

`codec`  
Baseline:

```text
pcm
```

`sampleRate`, `channels`, `bitsPerSample`, `durationMs`  
Metadata derivati dal WAV validato.

`loop`  
Indica se il runtime può riprodurre il track in loop.

`required`  
Se `true`, l'import e il packaging devono fallire quando il file manca o non è valido.

---

## 5. Inventario as-built

### 5.1 BGM

```text
bgm.main      → bgm_main.wav
bgm.ambient   → bgm_ambient.wav
bgm.tense     → bgm_tense.wav
bgm.epic      → bgm_epic.wav
```

Baseline:

```text
codec: PCM
sample rate: 48000 Hz
channels: 2
bits: 16
loop: true
required: true
```

### 5.2 SFX

```text
sfx.click     → sfx_click.wav
sfx.alert     → sfx_alert.wav
sfx.glitch    → sfx_glitch.wav
sfx.chime     → sfx_chime.wav
```

Baseline:

```text
codec: PCM
sample rate: 22050 Hz
channels: 1
bits: 16
loop: false
required: true
```

Il manifest effettivo resta la fonte autorevole per hash, dimensioni e durate.

---

## 6. Validazione WAV

Ogni file deve essere verificato almeno per:

- header RIFF;
- form type WAVE;
- presenza chunk `fmt `;
- presenza chunk `data`;
- PCM supportato;
- sample rate valido;
- channel count valido;
- bits per sample validi;
- dimensioni coerenti;
- durata derivabile;
- assenza di file vuoti o troncati.

La verifica deve usare il componente condiviso introdotto dalla Fase 6.7, non implementazioni divergenti nei singoli script.

Un'estensione `.wav` non è sufficiente.

---

## 7. Integrità

### 7.1 Durante import

Il manifest viene prodotto solo dopo che tutti i required track sono validi.

### 7.2 Durante CI

La pipeline deve ricalcolare:

```text
sizeBytes
sha256
```

per ogni file dichiarato.

Mismatch:

```text
→ failure
```

### 7.3 Durante packaging

Portable e installer devono contenere la stessa versione del set audio.

Il `audioSetId` deve essere registrato nel `release-manifest.json`.

### 7.4 Durante runtime

Il runtime può verificare o ripristinare asset gestiti secondo la policy implementata, ma non deve bloccare il gameplay quando l'audio non è disponibile.

---

## 8. Layout applicativo

Sorgente canonica:

```text
distribution/audio/
```

Asset Flutter:

```text
app/assets/audio/
```

Il packaging deve evitare duplicazioni non intenzionali.

Regola:

```text
una copia eseguibile nel bundle Flutter
+ eventuale repair source solo se deliberatamente progettata
```

Non distribuire due copie identiche di tutti i WAV senza una funzione esplicita e documentata.

---

## 9. Logical ID e runtime

Widget e controller non devono hardcodare i filename.

Devono richiedere logical ID o ruoli:

```text
bgm.main
bgm.ambient
bgm.tense
bgm.epic
sfx.click
sfx.alert
sfx.glitch
sfx.chime
```

La risoluzione:

```text
logical ID
→ manifest
→ path effettivo
```

permette in futuro di cambiare filename, formato o variante senza modificare il gameplay.

---

## 10. Fallback e degraded mode

L'audio non è autorità sul gameplay.

In caso di:

- file mancante;
- file corrotto;
- device audio non disponibile;
- inizializzazione player fallita;
- permesso negato;
- errore di decode;

l'applicazione deve:

- registrare diagnostica;
- continuare senza crash;
- usare fallback silenzioso;
- non alterare regole, punteggi o stato di gioco.

Eventuali asset procedurali o fallback generati devono essere isolati in una directory degraded, non promossi nella sorgente canonica.

Percorso concettuale:

```text
<appData>/audio/degraded/
```

---

## 11. File gestiti e file utente

### 11.1 File gestiti

Sono i file dichiarati nel manifest con:

```text
required: true
```

e distribuiti dal prodotto.

### 11.2 File utente

Sono file:

- non dichiarati nel manifest;
- importati o creati dall'utente;
- non posseduti dall'installer.

Regole:

- non cancellare file utente durante upgrade;
- non sovrascrivere file utente non gestiti;
- non includere file utente nella build;
- non calcolare il release manifest da contenuti utente.

### 11.3 File gestito modificato

Quando una installazione futura distribuisce asset gestiti in una directory modificabile dall'utente, prima di sostituire un file gestito alterato:

- rilevare mismatch;
- creare backup;
- registrare l'operazione;
- applicare policy repair/upgrade;
- non perdere silenziosamente la modifica.

La baseline Flutter-bundled può rendere questo caso non applicabile ai file interni al bundle, ma la regola resta valida per eventuali copie in AppData.

---

## 12. Installer

L'installer deve:

- distribuire l'audio set canonico;
- non leggere `%APPDATA%` durante la compilazione;
- preservare file utente;
- gestire repair dei file ufficiali;
- non rendere obbligatoria la presenza di hardware audio;
- mantenere coerenza con il portable;
- includere il manifest o i metadata necessari alla verifica;
- preservare configurazioni audio utente durante upgrade.

La disinstallazione deve distinguere:

```text
file applicativi gestiti
configurazioni
replay
modelli
audio utente
```

La rimozione dei dati utente richiede scelta esplicita.

---

## 13. Portable

Il portable deve:

- contenere gli stessi asset ufficiali dell'installer;
- funzionare da percorso con spazi;
- non dipendere da `%APPDATA%\aura\audio`;
- non creare copie canoniche nel repository;
- non fallire se il device audio è assente;
- permettere all'app di risolvere i path dal root corrente.

---

## 14. GitHub Actions

### 14.1 CI ordinaria

Deve:

- validare il manifest;
- validare tutti i WAV;
- ricalcolare hash e dimensioni;
- verificare required track;
- non importare da AppData;
- non modificare `distribution/audio`;
- non generare nuovi WAV;
- non usare fallback procedurali come release asset.

### 14.2 Workflow release

Deve:

- registrare `audioSetId`;
- verificare il set prima del packaging;
- verificare il set nel portable estratto;
- verificare il set nello staging installer;
- pubblicare `audio-manifest.json` fra gli asset Release;
- includere il digest del manifest nel release manifest;
- fallire in caso di divergenza portable/installer.

---

## 15. Change control

Per sostituire o aggiungere un track:

1. preparare il WAV approvato;
2. eseguire import esplicito;
3. verificare diff del manifest;
4. verificare hash, dimensione e metadata;
5. eseguire test audio;
6. verificare volume e loop;
7. committare WAV e manifest insieme;
8. aggiornare `audioSetId` quando il set cambia in modo incompatibile o significativo;
9. annotare il cambiamento nelle release notes.

Non modificare manualmente l'hash nel manifest.

---

## 16. Test automatici richiesti

- manifest parseable;
- schema version supportata;
- ID univoci;
- filename univoci;
- path relativi e contenuti;
- required track presenti;
- hash corretti;
- size corretta;
- RIFF/WAVE valido;
- metadata coerenti;
- BGM loop;
- SFX non loop;
- import fail-closed;
- nessun output in caso di set incompleto;
- risoluzione logical ID;
- fallback silenzioso;
- portable contiene il set;
- package non legge AppData.

---

## 17. Test manuali richiesti

- BGM principale;
- ambient;
- tense;
- epic;
- click;
- alert;
- glitch;
- chime;
- loop senza gap inaccettabili;
- ducking su perdita focus;
- music toggle;
- SFX toggle;
- volume;
- resume;
- device audio assente;
- portable da percorso con spazi;
- installer pulito;
- upgrade;
- repair;
- uninstall e preservazione dati.

---

## 18. Criteri di accettazione

```text
- distribution/audio è la source of truth;
- AppData non è un input implicito;
- tutti i required track sono manifest-driven;
- hash e dimensioni sono verificati;
- WAV invalidi sono rifiutati;
- portable e installer distribuiscono lo stesso set;
- il runtime usa logical ID;
- assenza audio non blocca il gameplay;
- file utente sono preservati;
- la CI è fail-closed;
- il release manifest registra audioSetId e digest.
```

---

## 19. Stato as-built iniziale

Confermato alla baseline:

```text
- esiste distribution/audio/audio-manifest.json;
- il manifest usa schemaVersion 1;
- audioSetId è aura.windows.release.v1;
- sono presenti 4 BGM e 4 SFX required;
- gli asset sono PCM WAV;
- import_release_audio.ps1 delega al tool Dart;
- SourcePath AppData è opzionale ed esplicito;
- DestinationPath è distribution/audio;
- AppAssetPath è app/assets/audio;
- l'import fallisce su exit code non-zero.
```

Da verificare o completare nella Fase 6.9:

```text
- validatore CI standalone;
- confronto automatico portable/installer;
- digest audio manifest nel release manifest;
- test install/repair/uninstall dell'audio;
- controllo automatico contro duplicazioni di bundle;
- documentazione operativa per aggiornare il set audio.
```
