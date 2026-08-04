# A.U.R.A. — Release & Distribution Operational Guide

**Documento:** `docs/RELEASE_PROCESS.md`  
**Fase:** 6.9 — GitHub Actions, Draft Releases, Catalog Signing & Distribution  
**Stato:** Guida Operativa di Distribuzione  

---

## 1. Panoramica del Processo di Rilascio

A.U.R.A. utilizza una pipeline di Continuous Integration e Release basata su **GitHub Actions**, **Inno Setup**, **Firma Ed25519 dei cataloghi** e **GitHub Draft Releases**.

La regola fondamentale del processo di rilascio è:

```text
build una sola volta
→ verifiche locali e probe
→ creazione Draft Release & caricamento asset
→ download e collaudo degli stessi byte scaricati
→ pubblicazione manuale della medesima Draft (senza rebuild)
```

Nessuna ricompilazione o rigenerazione dei pacchetti viene eseguita tra la fase di collaudo e la pubblicazione finale.

---

## 2. Architettura dei Workflow GitHub Actions

### 2.1 `ci.yml` — CI Ordinaria
- **Trigger**: Pull Request e push su `main`.
- **Ruolo**: Esegue i gate di qualità primari:
  - Format check (`dart format`, `flutter format`)
  - Analisi statica (`dart analyze`, `flutter analyze`)
  - Unit e Widget test (`dart test`, `flutter test`)
  - Compilazione Flutter Release Windows (`flutter build windows --release`)
  - Validazione dei manifest di runtime e audio asset
- **Permessi**: `contents: read` (nessun accesso a segreti di release o permessi di scrittura).

### 2.2 `release.yml` — Pipeline di Rilascio
- **Trigger**: Manuale (`workflow_dispatch`).
- **Ruolo**: Compila, pacchiizza, firma i cataloghi, valida e crea una **Draft Release** con tutti gli asset allegati.
- **Permessi**: `contents: write` limitato al job di release.

### 2.3 `cleanup-draft-release.yml` — Cleanup Candidate
- **Trigger**: Manuale (`workflow_dispatch`).
- **Ruolo**: Elimina in modo sicuro una candidate Draft Release e il relativo git tag temporaneo dopo verifica di sicurezza fail-closed.

---

## 3. Guida Operativa all'Avvio di un Rilascio (`release.yml`)

### 3.1 Procedura di Trigger via GitHub UI
1. Navigare nella tab **Actions** del repository su GitHub.
2. Selezionare il workflow **Release Pipeline** nella barra laterale sinistra.
3. Cliccare su **Run workflow**.
4. Inserire i parametri richiesti:

| Campo | Tipo | Esempio / Valori | Descrizione |
|---|---|---|---|
| `version` | Text | `0.1.0-rc.1` o `0.1.0` | Versione SemVer esatta (SENZA prefisso `v`). |
| `channel` | Choice | `dev`, `beta`, `stable` | Canale di destinazione del pacchetto. |
| `release_kind` | Choice | `candidate`, `official` | `candidate` per test builds; `official` per release finale. |
| `require_installer` | Boolean | `true` / `false` | Se `true`, richiede la compilazione dell'installer Inno Setup. |

---

## 4. Policy SemVer & Requisiti di Sicurezza (Fail-Closed)

La pipeline rifiuta immediatamente l'esecuzione nei seguenti casi:

1. **Prefisso `v` nell'input `version`**: L'input deve essere es. `0.1.0-rc.1`. Il prefisso `v` viene aggiunto automaticamente al git tag (`v0.1.0-rc.1`).
2. **Release `candidate`**: La versione DEVE contenere un suffisso prerelease (es. `-rc.1`, `-beta.1`, `-dev.1`).
3. **Release `official`**:
   - La versione NON deve contenere suffissi prerelease.
   - Il canale DEVE essere `stable`.
   - `require_installer` DEVE essere `true`.
4. **Canale `beta`**: `require_installer` DEVE essere `true`.

---

## 5. Asset Prodotti nella GitHub Draft Release

Ogni esecuzione con successo del workflow `release.yml` produce i seguenti asset caricati nella Draft Release:

```text
aura-v<version>-win-x64.zip           Archive Portable ZIP
aura_setup_v<version>.exe              Installer Standalone Inno Setup
AURA-<version>-SHA256SUMS.txt          Checksum SHA-256 degli asset di release
release-manifest.json                  Metadata ufficiali di release e tracciabilità
runtime-manifest.json                  Manifest di runtime multi-variante
audio-manifest.json                    Manifest degli asset audio di release
model-manifest.json                    Catalogo dei modelli firmato (Ed25519 envelope)
SBOM.spdx.json                         Software Bill of Materials (SPDX 2.3 JSON)
THIRD_PARTY_NOTICES.txt                Avvisi di terze parti e licenze incluse
```

---

## 6. Procedura di Collaudo Manuale della Draft Release

Prima di pubblicare una Draft Release, un collaboratore deve eseguire la seguente procedura di collaudo su una macchina target Windows:

1. **Verifica Checksum**:
   - Scaricare `AURA-<version>-SHA256SUMS.txt`, `aura-v<version>-win-x64.zip` e `aura_setup_v<version>.exe`.
   - Verificare gli hash via PowerShell:
     ```powershell
     Get-FileHash -Algorithm SHA256 aura-v<version>-win-x64.zip
     Get-FileHash -Algorithm SHA256 aura_setup_v<version>.exe
     ```
   - Confrontare con i valori presenti in `AURA-<version>-SHA256SUMS.txt`.

2. **Test della Versione Portable (ZIP)**:
   - Estrarre `aura-v<version>-win-x64.zip` in una cartella locale.
   - Avviare `aura_app.exe`.
   - Verificare che il bootstrap rilevi correttamente i runtime bundled (`win-x64-cuda`, `win-x64-vulkan`, `win-x64-cpu-avx2`).
   - Verificare l'assenza di crash e la riproduzione dell'audio di sottofondo.
   - Chiudere l'applicazione e verificare che nessun processo `llama-server.exe` rimanga orfano.

3. **Test dell'Installer Inno Setup (EXE)**:
   - Eseguire `aura_setup_v<version>.exe`.
   - Completare l'installazione guidata.
   - Avviare A.U.R.A. dal collegamento sul Desktop / Menu Start.
   - Verificare il corretto funzionamento.
   - Disinstallare tramite *Impostazioni > App installate* e verificare la pulizia completa.

---

## 7. Pubblicazione della Draft Release (Official / Stable)

Una volta superato il collaudo manuale:

1. Accedere alla sezione **Releases** su GitHub.
2. Individuare la Draft Release creata per la versione target.
3. Cliccare su **Edit draft**.
4. Deselezionare la spunta **Save as draft**.
5. Cliccare su **Publish release**.

> [!IMPORTANT]
> **Nessun Rebuild**: Gli asset pubblicati sono esattamente quelli caricati durante la fase di Draft. Nessuna nuova build o rigenerazione viene eseguita.

---

## 8. Procedura di Cleanup Candidate (`cleanup-draft-release.yml`)

Se una candidate release non supera i test o deve essere sostituita:

1. Navigare nella tab **Actions** > **Cleanup Draft Release**.
2. Cliccare su **Run workflow**.
3. Inserire:
   - `tag`: Il tag della release da eliminare (es. `v0.1.0-rc.1`).
   - `confirm_string`: La stringa di conferma esatta: `DELETE-v0.1.0-rc.1`.
4. Il workflow verificherà che la release sia effettivamente in stato **Draft** prima di procedere all'eliminazione della release e del tag.

---

## 9. Configurazione Secret ed Environment GitHub

Per la firma dei cataloghi di produzione e la gestione dei ruoli, sono previsti due Environment su GitHub:

1. `release-candidate`: Per release candidate e test automatizzati.
2. `release`: Per le release ufficiali (protetto con approvazione manuale dei reviewer).

### Secret di Repository / Environment:
- `CATALOG_SIGNING_PRIVATE_KEY`: Chiave privata hex Ed25519 per la firma dei cataloghi di produzione.
- `CATALOG_SIGNING_KEY_ID`: ID simbolico della chiave (es. `aura-catalog-production-2026-v1`).

---

## 10. Assenza dei Modelli nei Pacchetti

I pacchetti di distribuzione ufficiali di A.U.R.A. **NON includono file di modello GGUF** per mantenere il payload distribuibile ridotto (< 150 MB).

Alla prima esecuzione dell'applicazione, la procedura di prima installazione guida l'utente nel download verificato del modello tramite il catalogo firmato `model-manifest.json`.
