# A.U.R.A. — Release Pipeline Specification

**Documento:** `docs/phase6/RELEASE_PIPELINE_SPEC.md`  
**Fase:** 6.9 — GitHub Actions, Draft Releases, Catalog Signing & Distribution  
**Stato:** Specifica implementativa  
**Baseline applicativa:** Fase 6.8 completata  
**Commit di riferimento iniziale:** `1c9015da6c5f445c13e82fa5df0c4d49e0830429`  
**Target iniziale:** Windows x64  
**Canali previsti:** `dev`, `beta`, `stable`

---

## 1. Scopo

Questa specifica definisce la pipeline di Continuous Integration, packaging, verifica, firma e distribuzione di A.U.R.A. tramite GitHub Actions e GitHub Releases.

La pipeline deve:

- verificare automaticamente pull request e push;
- compilare l'applicazione Flutter Windows;
- acquisire in modo deterministico i runtime `llama-server`;
- produrre il pacchetto portable;
- produrre l'installer Inno Setup;
- validare manifest, hash, dipendenze e struttura dei pacchetti;
- produrre SBOM, notices e metadata di release;
- firmare e verificare i cataloghi remoti previsti dall'architettura;
- creare GitHub Releases inizialmente in stato **Draft**;
- permettere il collaudo degli asset reali prima della pubblicazione;
- pubblicare gli stessi byte già testati, senza una nuova compilazione;
- supportare la cancellazione sicura di candidate release e tag temporanei.

La regola primaria è:

```text
build una sola volta
→ verifica
→ caricamento in Draft Release
→ download e test manuale
→ pubblicazione della stessa Draft
```

Non deve esistere una seconda build automatica fra il collaudo e la pubblicazione ufficiale.

---

## 2. Relazione con la Fase 6.8

La Fase 6.9 usa come source of truth il packaging implementato nella Fase 6.8.

Componenti già esistenti da riutilizzare:

```text
tool/fetch_llama_binaries.ps1
tool/build_llama_runtimes.ps1
tool/package_release.ps1
tool/aura_installer.iss
runtime/runtime-manifest.json
distribution/audio/audio-manifest.json
```

La pipeline non deve duplicare nel workflow YAML la logica già presente negli script PowerShell.

In particolare, deve invocare:

```powershell
.\tool\package_release.ps1 `
  -Version "<version>" `
  -RequireInstaller
```

Lo script di packaging resta responsabile di:

- build Flutter Windows;
- staging transazionale;
- assemblaggio runtime;
- validazione PE;
- probe `llama-server --version`;
- configurazione process-local del `PATH` vendor;
- verifica SHA-256;
- generazione portable ZIP;
- compilazione installer Inno Setup;
- verifica dell'installer;
- promozione transazionale degli artefatti locali.

La Fase 6.9 aggiunge orchestrazione CI/CD, provenance, firma, upload e lifecycle GitHub Release.

---

## 3. Principi vincolanti

### 3.1 Build deterministica negli input

Tutti gli input della release devono essere:

- versionati nel repository;
- oppure acquisiti tramite versione, revisione e checksum fissati;
- oppure forniti tramite segreti o environment GitHub esplicitamente dichiarati.

Non sono ammessi:

- URL `latest`;
- branch mobili;
- selezione automatica del primo artifact disponibile;
- dipendenza da file presenti in `%APPDATA%`;
- dipendenza da installazioni locali di LM Studio;
- uso implicito di runtime presenti sulla macchina del runner;
- uso di file non tracciati senza verifica crittografica.

### 3.2 Fail-closed

La pipeline deve fallire prima della creazione della Draft Release se fallisce uno dei seguenti controlli:

- formattazione;
- analisi statica;
- test;
- build Flutter;
- acquisizione runtime;
- verifica manifest;
- verifica checksum;
- validazione PE;
- probe runtime;
- compilazione installer;
- verifica installer;
- generazione SBOM;
- presenza delle licenze;
- firma dei cataloghi richiesta;
- verifica delle firme;
- estrazione e verifica del portable;
- generazione dei checksum finali.

### 3.3 Nessun modello incluso

I pacchetti Windows non devono includere file GGUF.

La pipeline deve verificare l'assenza di:

```text
*.gguf
*.safetensors
*.bin di modelli
cache Hugging Face
directory model store utente
```

Il primo avvio e le impostazioni restano responsabili della configurazione dei modelli.

### 3.4 Nessuna dipendenza da AppData

La build GitHub non deve leggere:

```text
%APPDATA%\aura\
%LOCALAPPDATA%\AURA\
```

Gli asset audio di release devono provenire esclusivamente da:

```text
distribution/audio/
```

### 3.5 Nessuna pubblicazione automatica stabile

Una release `stable` deve essere creata come Draft e pubblicata manualmente dopo il collaudo.

---

## 4. Non-obiettivi

La Fase 6.9 non comprende:

- test completi di inferenza CUDA o Vulkan su GPU reale;
- self-hosted runner GPU obbligatorio;
- download o caricamento di modelli reali nella CI ordinaria;
- updater automatico dell'applicazione;
- rollout progressivo automatico;
- firma Authenticode obbligatoria se il certificato non è ancora disponibile;
- production hardening completo su matrice hardware;
- test esaustivi multi-monitor, DPI, proxy e storage insufficiente;
- pubblicazione Android;
- lifecycle automatico dei modelli.

Questi aspetti appartengono alle fasi successive o a workflow opt-in dedicati.

---

## 5. Architettura della pipeline

Struttura consigliata:

```text
.github/
  workflows/
    ci.yml
    release.yml
    cleanup-draft-release.yml        opzionale
  actions/
    setup-aura-build/
      action.yml                     opzionale

docs/
  phase6/
    RELEASE_PIPELINE_SPEC.md
  RELEASE_PROCESS.md

tool/
  fetch_llama_binaries.ps1
  build_llama_runtimes.ps1
  package_release.ps1
  verify_release_bundle.ps1          se necessario
  generate_release_metadata.ps1      se necessario
  sign_catalogs.ps1                  se necessario
  verify_catalog_signatures.ps1      se necessario
```

La logica complessa deve risiedere in script versionati e testabili. I workflow YAML devono limitarsi a:

- configurare il runner;
- installare la toolchain;
- invocare gli script;
- caricare artifact;
- creare tag e Draft Release;
- caricare gli asset.

---

## 6. Workflow CI

### 6.1 Trigger

Il workflow CI deve essere eseguito su:

```yaml
pull_request:
push:
  branches:
    - main
```

### 6.2 Runner

Target iniziale:

```yaml
runs-on: windows-latest
```

La CI Windows è obbligatoria perché il target produttivo iniziale è Windows x64 e deve essere verificata almeno la build Flutter Windows.

Workflow aggiuntivi Linux possono essere introdotti per test del core, ma non sostituiscono il gate Windows.

### 6.3 Permessi

Default:

```yaml
permissions:
  contents: read
```

La CI ordinaria non deve avere permessi di scrittura sul repository.

### 6.4 Concurrency

Esempio:

```yaml
concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

Le esecuzioni obsolete di una stessa PR possono essere annullate.

### 6.5 Segreti

La CI su pull request:

- non usa segreti di release;
- non usa chiavi private;
- non usa certificati;
- non pubblica release;
- non crea tag;
- non carica asset persistenti di distribuzione.

Evitare `pull_request_target` salvo motivazione documentata e revisione di sicurezza.

### 6.6 Gate CI minimi

Root package:

```powershell
dart format --output=none --set-exit-if-changed lib test bin tool
dart analyze .
dart test
```

Flutter app:

```powershell
Push-Location app
try {
    dart format --output=none --set-exit-if-changed lib test
    flutter analyze
    flutter test
    flutter build windows --release
} finally {
    Pop-Location
}
```

Ulteriori gate:

- validazione `runtime-manifest.json`;
- validazione `audio-manifest.json`;
- verifica che i file audio dichiarati esistano e corrispondano agli hash;
- verifica sintattica workflow con `actionlint`;
- verifica che le suite standard non effettuino download impliciti;
- verifica che nessun modello reale sia richiesto;
- verifica che gli script PowerShell siano parseable.

### 6.7 Installer dry-build

Un eventuale dry-build dell'installer nella CI ordinaria:

- deve usare fixture o staging temporanei;
- non deve generare artefatti con nomi ufficiali;
- non deve caricare output come release asset;
- non deve permettere a placeholder di essere confusi con binari reali;
- deve essere eliminato alla fine del job.

La pipeline release resta l'unica autorizzata a produrre i pacchetti ufficiali.

---

## 7. Workflow release

### 7.1 Trigger iniziale

La Fase 6.9 deve inizialmente usare solo:

```yaml
workflow_dispatch:
```

Non deve pubblicare automaticamente su semplice push di tag.

L'automazione su tag potrà essere introdotta dopo il consolidamento del processo manuale.

### 7.2 Input richiesti

Input minimi:

```text
version
channel
release_kind
require_installer
```

Valori:

```text
channel:
  dev
  beta
  stable

release_kind:
  candidate
  official
```

`require_installer` deve essere `true` per:

```text
candidate beta
official stable
```

Può essere opzionale solo per build `dev` esplicitamente ZIP-only.

### 7.3 Validazione SemVer

La versione deve rispettare SemVer.

Regole:

```text
candidate/dev     → prerelease obbligatoria
candidate/beta    → prerelease obbligatoria
official/stable   → nessun suffisso prerelease
```

Esempi validi:

```text
0.1.0-dev.1
0.1.0-beta.1
0.1.0-rc.1
0.1.0
```

Esempi non validi:

```text
latest
main
release-final
0.1
v0.1.0 come input, se il workflow aggiunge già il prefisso v
```

### 7.4 Coerenza versione

La stessa versione deve comparire in:

- tag;
- nome release;
- ZIP;
- installer;
- Inno Setup;
- `release-manifest.json`;
- manifest runtime dove previsto;
- checksum file;
- release notes.

Il workflow deve aggiungere il prefisso `v` al tag in un solo punto.

---

## 8. Canali di distribuzione

### 8.1 Dev

Uso:

- build sperimentali;
- verifica della pipeline;
- debug;
- test interni.

Regole:

```text
Draft = true
Prerelease = true
Pubblicazione automatica = false
Compatibilità garantita = no
```

### 8.2 Beta

Uso:

- release candidate;
- test manuali completi;
- collaudo ZIP e installer.

Regole:

```text
Draft = true
Prerelease = true
Pubblicazione automatica = false
Asset completi = sì
Firma cataloghi = raccomandata o obbligatoria secondo policy
Installer = obbligatorio
```

### 8.3 Stable

Uso:

- release pubblica ufficiale.

Regole:

```text
Draft iniziale = true
Prerelease = false
Pubblicazione automatica = mai
Firma cataloghi = obbligatoria
Installer = obbligatorio
Test manuale = obbligatorio
```

Le release `dev` e `beta` non devono diventare la GitHub “latest release”.

---

## 9. Acquisizione runtime

### 9.1 Varianti obbligatorie

La release Windows deve includere:

```text
win-x64-cuda
win-x64-vulkan
win-x64-cpu-avx2
```

### 9.2 Fonte

Il workflow deve usare il meccanismo versionato esistente, preferibilmente:

```powershell
.\tool\fetch_llama_binaries.ps1
```

La sorgente deve essere fissata tramite:

```text
provider
repository
release/tag o commit
filename
sha256
```

### 9.3 Requisiti

La fase di acquisizione deve:

- non usare `latest`;
- non selezionare automaticamente il primo asset disponibile;
- verificare l'hash dell'archivio scaricato;
- estrarre in staging;
- copiare tutte le DLL richieste;
- preservare licenze e notices;
- verificare executable e dipendenze;
- produrre input compatibili con `build_llama_runtimes.ps1`;
- fallire se una variante è incompleta.

### 9.4 Cache

È ammessa una cache GitHub Actions soltanto se la chiave include:

```text
llama.cpp version
source commit
asset filename
asset SHA-256
target architecture
variant ID
```

Una cache incompleta o non verificabile deve essere scartata.

---

## 10. Toolchain

La pipeline deve installare versioni fissate di:

- Flutter;
- Dart, coerente con Flutter;
- Inno Setup;
- `actionlint`;
- tool SBOM;
- tool di firma cataloghi;
- eventuali utility di verifica.

Le GitHub Actions di terze parti devono essere fissate preferibilmente a SHA completo.

La pipeline deve registrare nel release manifest:

```text
Flutter version
Dart version
Inno Setup version
llama.cpp version
llama.cpp source commit
tool SBOM version
signing tool version
```

Non affidarsi implicitamente alla versione corrente preinstallata sul runner.

---

## 11. Sequenza del workflow release

Ordine vincolante:

```text
1. Checkout del commit richiesto.
2. Validazione input e versione.
3. Setup toolchain.
4. Format check.
5. Analisi statica.
6. Test Dart.
7. Test Flutter.
8. Build Flutter Windows.
9. Acquisizione runtime.
10. Build runtime staging.
11. Packaging con -RequireInstaller.
12. Validazione manifest.
13. Verifica integrità runtime.
14. Probe delle tre varianti.
15. Verifica portable.
16. Verifica installer.
17. Generazione SBOM.
18. Generazione notices.
19. Generazione/firma cataloghi.
20. Verifica firme.
21. Generazione checksum degli asset.
22. Generazione release manifest e release notes.
23. Upload workflow artifact temporaneo.
24. Creazione tag.
25. Creazione Draft Release.
26. Upload asset GitHub Release.
27. Verifica post-upload, se tecnicamente disponibile.
```

Tag e Draft Release devono essere creati solo dopo che tutti gli asset sono pronti e verificati localmente.

---

## 12. Verifiche pre-release

Prima della creazione del tag verificare:

### 12.1 Codice

- formattazione;
- analisi statica;
- unit test;
- integration test standard;
- build Flutter Windows release.

### 12.2 Runtime

- manifest parseable;
- schema supportato;
- tre varianti presenti;
- executable presente;
- file vendor presenti;
- hash SHA-256 corretti;
- dimensioni corrette;
- executable PE valido;
- `llama-server --version` con exit code `0`;
- working directory corretta;
- `PATH` vendor process-local;
- nessuna dipendenza da LM Studio;
- nessun placeholder.

### 12.3 Audio

- manifest parseable;
- file dichiarati presenti;
- hash e dimensione corretti;
- nessuna lettura da AppData;
- asset inclusi nel portable;
- asset inclusi nell'installer secondo la strategia prevista.

### 12.4 Portable

- ZIP presente;
- estrazione riuscita;
- executable A.U.R.A. presente;
- runtime manifest presente;
- runtime presenti;
- notices presenti;
- release manifest presente;
- checksum interni presenti;
- nessun GGUF;
- nessun file temporaneo;
- nessuna chiave privata;
- nessun path assoluto della macchina di build nei file di configurazione.

### 12.5 Installer

- EXE presente;
- PE valido;
- versione corretta;
- nome corretto;
- AppId stabile;
- icona corretta;
- nessuna modifica del `PATH` globale;
- nessun kill generico di `llama-server.exe`;
- dati utente preservati secondo specifica;
- Inno Setup obbligatorio quando richiesto.

### 12.6 Smoke test installer

Quando stabile sul runner:

```text
installazione silent in directory temporanea
→ verifica file
→ verifica uninstaller
→ uninstall silent
→ verifica rimozione file applicativi
```

Il test non deve cancellare dati reali del runner né accedere a profili utente esterni allo staging dedicato.

---

## 13. Asset della GitHub Release

Asset minimi:

```text
aura-v<version>-win-x64.zip
aura_setup_v<version>.exe
AURA-<version>-SHA256SUMS.txt
release-manifest.json
runtime-manifest.json
audio-manifest.json
model-manifest.json
SBOM.spdx.json oppure SBOM.cdx.json
THIRD_PARTY_NOTICES.txt
```

Asset opzionali:

```text
AURA-AudioPack-<version>.zip
catalog signature files
public key metadata
provenance attestations
debug symbols
```

I nomi effettivi già prodotti dagli script possono essere mantenuti. Un cambio di naming deve essere atomico e documentato.

---

## 14. Checksum

Sono richiesti due livelli.

### 14.1 Checksum interno

Il portable deve contenere un checksum file che copra i file del bundle.

### 14.2 Checksum degli asset Release

Un file separato deve coprire almeno:

- ZIP portable;
- installer;
- manifest standalone;
- SBOM;
- notices;
- cataloghi;
- file firma.

Il checksum file non deve contenere il proprio hash.

Gli hash devono essere ricalcolati immediatamente prima dell'upload.

---

## 15. Workflow artifact e Release asset

### 15.1 Workflow artifact

Scopo:

- debug;
- ispezione;
- candidate interne;
- recupero temporaneo;
- analisi dei failure.

Deve avere retention esplicita e limitata.

### 15.2 GitHub Release asset

Scopo:

- distribuzione persistente;
- download da parte dei tester;
- release ufficiale;
- associazione a tag e release notes.

Gli utenti finali devono scaricare dalla sezione **Releases**, non dalla pagina Actions.

---

## 16. Draft Release

### 16.1 Regola

Ogni release deve nascere come Draft.

### 16.2 Candidate

Esempio:

```text
tag: v0.1.0-rc.1
name: A.U.R.A. v0.1.0-rc.1
draft: true
prerelease: true
```

### 16.3 Official

Esempio:

```text
tag: v0.1.0
name: A.U.R.A. v0.1.0
draft: true
prerelease: false
```

### 16.4 Pubblicazione

La pubblicazione avviene manualmente dalla UI GitHub.

Dopo la creazione della Draft:

- non ricompilare;
- non rigenerare manifest;
- non sostituire asset;
- non modificare i checksum;
- non creare una seconda release.

Gli stessi asset testati devono essere pubblicati.

---

## 17. Test manuale della Draft

Checklist minima:

```text
1. Scaricare il checksum file.
2. Scaricare ZIP e installer.
3. Verificare gli hash.
4. Estrarre il portable in un percorso con spazi.
5. Avviare il portable.
6. Verificare bootstrap e first-run.
7. Verificare rilevamento runtime.
8. Verificare selezione CUDA.
9. Verificare fallback Vulkan.
10. Verificare fallback CPU.
11. Verificare audio.
12. Verificare caricamento configurazione.
13. Chiudere l'app.
14. Verificare assenza di processi llama-server orfani.
15. Installare tramite installer.
16. Verificare collegamenti e branding.
17. Verificare installazione pulita.
18. Verificare upgrade da versione precedente.
19. Verificare conservazione configurazioni.
20. Verificare conservazione replay.
21. Verificare conservazione modelli esterni e gestiti.
22. Verificare gestione audio utente.
23. Disinstallare.
24. Verificare comportamento dati preservati/rimossi.
25. Registrare esito e macchina usata.
```

I test reali CUDA e Vulkan devono essere svolti su hardware compatibile fuori dal runner GitHub hosted.

---

## 18. Cleanup candidate

La cancellazione di una Draft Release non implica automaticamente la cancellazione del tag.

Procedura manuale raccomandata:

```powershell
gh release delete <tag> --cleanup-tag
```

Un eventuale workflow `cleanup-draft-release.yml` deve richiedere:

```text
tag esatto
stringa di conferma
```

Deve inoltre verificare:

- la release esiste;
- la release è ancora Draft;
- non è una stable pubblicata;
- il tag coincide esattamente;
- non esistono riferimenti protetti che impediscano la cancellazione.

Non eseguire cleanup automatici basati solo sull'età.

---

## 19. Gestione tag e collisioni

Default:

```text
tag esistente       → failure
release esistente   → failure
asset esistente     → failure
```

Un'eventuale modalità replace deve:

- essere esplicita;
- funzionare solo su Draft non pubblicate;
- verificare che la release appartenga allo stesso commit;
- non sostituire asset di una release già approvata;
- lasciare audit log chiaro.

Per ridurre ambiguità, preferire versioni candidate incrementali:

```text
0.1.0-rc.1
0.1.0-rc.2
0.1.0-rc.3
```

---

## 20. Sicurezza GitHub Actions

### 20.1 Permessi

Default workflow:

```yaml
permissions:
  contents: read
```

Solo il job finale di release può usare:

```yaml
permissions:
  contents: write
```

### 20.2 Environment

Creare:

```text
release-candidate
release
```

L'environment `release` deve richiedere approvazione manuale prima di rendere disponibili chiavi private o certificati.

### 20.3 Segreti

Segreti possibili:

```text
CATALOG_SIGNING_PRIVATE_KEY
CATALOG_SIGNING_KEY_ID
WINDOWS_SIGNING_CERTIFICATE
WINDOWS_SIGNING_CERTIFICATE_PASSWORD
```

Regole:

- mai disponibili su PR da fork;
- mai stampati nei log;
- mai salvati in cache;
- mai caricati come artifact;
- mai inclusi nei package;
- accessibili solo al job di firma;
- ruotabili senza modificare il codice client, tramite key ID e trust policy versionata.

### 20.4 Azioni terze parti

Preferire SHA completi invece di tag mobili.

### 20.5 Concurrency release

Esempio:

```yaml
concurrency:
  group: release-${{ inputs.version }}
  cancel-in-progress: false
```

Due release con la stessa versione non devono essere eseguite contemporaneamente.

---

## 21. Firma dei cataloghi

### 21.1 Cataloghi previsti

Almeno:

```text
model-manifest.json
```

Eventualmente:

```text
runtime-manifest.json
audio-manifest.json
channel metadata
```

secondo il verifier client effettivamente implementato.

### 21.2 Regola di compatibilità

Prima di implementare il signer:

1. individuare il verifier client;
2. identificare algoritmo;
3. identificare canonicalizzazione;
4. identificare formato firma;
5. identificare key ID;
6. implementare known-answer test;
7. verificare signer e verifier end-to-end.

Non introdurre un formato incompatibile con il client.

### 21.3 Chiavi

Nel repository possono essere versionati:

- chiave pubblica;
- key ID;
- metadata di trust;
- algoritmo.

Non può essere versionata la chiave privata.

### 21.4 Stable

Per `official/stable`:

```text
firma mancante       → failure
firma non valida     → failure
key ID sconosciuto   → failure
digest differente    → failure
```

### 21.5 Candidate

Le candidate destinate a testare la pipeline produttiva devono usare lo stesso processo di firma delle stable.

---

## 22. Authenticode

La firma Authenticode degli eseguibili Windows è distinta dalla firma dei cataloghi.

Il release manifest deve dichiarare:

```text
authenticodeSigned: true|false
```

Non dichiarare firmato un installer o executable non firmato.

Se il certificato non è disponibile:

- il workflow deve continuare per candidate non ufficiali, secondo policy;
- la stable può essere bloccata oppure pubblicata dichiarando esplicitamente l'assenza di firma, secondo decisione di progetto;
- il hook di firma deve essere predisposto senza inserire segreti nel repository.

---

## 23. SBOM

Formato ammesso:

```text
SPDX JSON
CycloneDX JSON
```

L'SBOM deve includere, per quanto disponibile:

- applicazione Dart/Flutter;
- dipendenze pub;
- runtime `llama.cpp`;
- versione runtime;
- source commit runtime;
- DLL redistribuite;
- audio pack;
- licenze;
- tool di packaging rilevanti.

La pipeline deve usare una versione fissata del generatore SBOM.

L'SBOM deve essere validato prima dell'upload.

---

## 24. THIRD_PARTY_NOTICES

Il file deve essere derivato dai componenti realmente inclusi.

Deve includere almeno:

- Flutter;
- Dart;
- dipendenze runtime rilevanti;
- `llama.cpp`;
- CUDA redistributables, se presenti;
- Vulkan runtime components, se redistribuiti;
- OpenMP/runtime DLL;
- altri componenti vendor inclusi.

La pipeline deve fallire se una licenza obbligatoria manca.

Una lista statica non aggiornata non è sufficiente quando cambia il runtime set.

---

## 25. Release manifest

Il `release-manifest.json` deve includere almeno:

```json
{
  "schemaVersion": 1,
  "appVersion": "0.1.0",
  "channel": "stable",
  "releaseKind": "official",
  "sourceCommit": "...",
  "tag": "v0.1.0",
  "workflowRunId": "...",
  "workflowRunAttempt": 1,
  "buildTimestampUtc": "...",
  "targetPlatform": "windows-x64",
  "flutterVersion": "...",
  "dartVersion": "...",
  "innoSetupVersion": "...",
  "llamaCppVersion": "...",
  "llamaCppSourceCommit": "...",
  "runtimeSetId": "...",
  "runtimeVariantIds": [
    "win-x64-cuda",
    "win-x64-vulkan",
    "win-x64-cpu-avx2"
  ],
  "audioPackVersion": "...",
  "catalogDigests": {},
  "catalogSignatureKeyId": "...",
  "sbomFile": "SBOM.spdx.json",
  "checksumsFile": "AURA-0.1.0-SHA256SUMS.txt",
  "installerFile": "aura_setup_v0.1.0.exe",
  "portableFile": "aura-v0.1.0-win-x64.zip",
  "signedCatalogs": true,
  "authenticodeSigned": false,
  "modelsBundled": false
}
```

Non dichiarare una build bit-for-bit riproducibile se non è stata verificata.

Terminologia corretta:

```text
input deterministici
build tracciabile
build verificabile
```

Usare `reproducible build` solo dopo prova reale di riproducibilità binaria.

---

## 26. Release notes

Le release notes devono includere:

- versione;
- canale;
- commit;
- runtime set;
- versione `llama.cpp`;
- varianti runtime;
- audio pack;
- modelli non inclusi;
- requisiti hardware;
- modalità portable;
- modalità installer;
- stato firma cataloghi;
- stato Authenticode;
- limitazioni note;
- istruzioni checksum;
- documentazione runtime e modelli.

Per candidate:

```text
TEST BUILD — DO NOT REDISTRIBUTE
```

deve comparire chiaramente.

---

## 27. Gestione dei fallimenti

### 27.1 Prima della Draft

Nessuna release o tag deve essere creato.

### 27.2 Durante upload

Se un upload fallisce:

- la release resta Draft;
- non viene pubblicata;
- viene marcata come incompleta nelle note o eliminata;
- il workflow fallisce;
- non vengono sostituiti asset esistenti senza autorizzazione.

### 27.3 Dopo creazione tag

Se la Draft non può essere completata:

- lasciare tag e Draft per diagnosi;
- oppure effettuare rollback esplicito;
- documentare il comportamento scelto;
- non eliminare automaticamente una release potenzialmente utile al debug senza log.

### 27.4 Retry

Un retry deve:

- usare lo stesso commit;
- usare la stessa versione solo se la Draft precedente viene eliminata esplicitamente;
- non sovrascrivere silenziosamente asset già testati.

---

## 28. Documentazione operativa

Creare:

```text
docs/RELEASE_PROCESS.md
```

Contenuti minimi:

- come avviare il workflow;
- significato input;
- differenza `candidate` / `official`;
- differenza Draft / Prerelease / Published;
- dove scaricare asset;
- come verificare checksum;
- come testare una Draft;
- come pubblicare la stessa Draft;
- come eliminare Draft e tag;
- come configurare environment;
- come configurare secret;
- come ruotare la chiave;
- come rigenerare una candidate;
- come interpretare failure;
- limiti del runner senza GPU;
- assenza dei modelli nei pacchetti;
- recovery da upload parziale.

Aggiornare inoltre:

```text
README.md
AURA_TGDD_v1_1_revised.md
```

per rimuovere descrizioni obsolete della pipeline e indicare la sezione GitHub Releases come canale di download.

---

## 29. Criteri di accettazione Fase 6.9

La fase è completata quando:

```text
- una PR esegue format, analyze, test e build Windows;
- la CI ordinaria non usa runtime di produzione o modelli reali;
- il workflow release è manuale;
- il workflow release usa permessi minimi;
- una candidate produce ZIP reale;
- una candidate produce installer reale;
- Inno Setup è obbligatorio quando richiesto;
- le tre varianti runtime sono presenti;
- gli hash runtime sono verificati;
- le probe runtime hanno exit code zero;
- nessun placeholder raggiunge gli asset;
- nessun GGUF è incluso;
- audio manifest e WAV sono verificati;
- portable e installer contengono asset coerenti;
- SBOM è presente e valido;
- THIRD_PARTY_NOTICES è presente;
- cataloghi richiesti sono firmati;
- firme e digest sono verificati;
- checksum degli asset sono pubblicati;
- la GitHub Draft Release contiene tutti gli asset;
- gli asset sono scaricabili dai collaboratori;
- la candidate può essere cancellata insieme al tag;
- una official Draft può essere pubblicata senza rebuild;
- gli asset pubblicati sono byte-per-byte quelli testati;
- la procedura è documentata;
- una prima Draft Release di prova è stata creata con successo,
  oppure sono documentati con precisione i prerequisiti esterni mancanti.
```

---

## 30. Exit criteria della Fase 6 Windows

Con il completamento della Fase 6.9:

```text
GitHub Release pubblica installer, portable, checksum,
manifest, SBOM, notices e cataloghi firmati/verificabili.
```

La Fase 6.10 resta responsabile del production hardening su macchine Windows pulite, hardware reale, proxy, upgrade, repair, rollback e matrice completa CPU/CUDA/Vulkan.

---

## 31. Checklist di implementazione

### Workflow

- [ ] `ci.yml`
- [ ] `release.yml`
- [ ] concurrency
- [ ] permissions
- [ ] environment
- [ ] input validation
- [ ] SemVer validation
- [ ] action pinning
- [ ] actionlint

### Packaging

- [ ] acquisizione runtime fissata
- [ ] checksum input
- [ ] build runtime staging
- [ ] `package_release.ps1 -RequireInstaller`
- [ ] ZIP verification
- [ ] installer verification
- [ ] no GGUF
- [ ] no placeholder
- [ ] no AppData dependency

### Metadata

- [ ] release manifest
- [ ] checksum asset
- [ ] SBOM
- [ ] notices
- [ ] release notes
- [ ] provenance fields

### Signing

- [ ] verifier client identificato
- [ ] formato firma definito
- [ ] signer compatibile
- [ ] known-answer test
- [ ] secret configurato
- [ ] environment protetto
- [ ] firma verificata

### GitHub Release

- [ ] tag creato dopo build
- [ ] Draft Release
- [ ] prerelease policy
- [ ] upload asset
- [ ] collision policy
- [ ] cleanup candidate
- [ ] publish manuale
- [ ] nessun rebuild

### Documentazione

- [ ] `docs/RELEASE_PROCESS.md`
- [ ] README aggiornato
- [ ] TGDD aggiornato
- [ ] procedura test Draft
- [ ] procedura cleanup
- [ ] configurazione secret
- [ ] limitazioni runner

---

## 32. Walkthrough finale richiesto

L'implementazione della Fase 6.9 deve produrre un walkthrough contenente:

1. riepilogo architetturale;
2. file creati e modificati;
3. workflow introdotti;
4. input del workflow release;
5. strategia candidate/official;
6. strategia tag;
7. strategia cleanup;
8. permessi GitHub;
9. environment e secret richiesti;
10. asset prodotti;
11. firma e SBOM;
12. comandi eseguiti;
13. risultati dei test;
14. risultato packaging;
15. URL della Draft Release, se creata;
16. configurazioni manuali ancora necessarie;
17. limitazioni residue;
18. commit finale.

Non pubblicare automaticamente una stable release.

Non eliminare una Draft Release senza autorizzazione esplicita.
