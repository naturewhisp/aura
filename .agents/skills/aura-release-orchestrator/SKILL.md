---
name: aura-release-orchestrator
description: Procedura operativa completa per orchestrazione, esecuzione, verifica fail-closed e pubblicazione dei rilasci Candidate ed Ufficiali di A.U.R.A. via GitHub Actions e GitHub CLI. Utilizzare quando l'utente richiede di effettuare o verificare un rilascio.
---

# A.U.R.A. Release Orchestrator Skill

Questa skill fornisce le istruzioni operative e la procedura passo-passo affinché l'agente orchestri, verifichi e pubblichi i rilasci dell'applicazione su indicazione dell'utente.

---

## 1. Principi di Rilascio Fail-Closed

1. **Trigger Esclusivo Manuale**: Tutti i rilasci sono avviati via `workflow_dispatch`. Nessun rilascio viene scatenato automaticamente da `git push` o Pull Request.
2. **Immutabilità e Zero Warnings**: Prima di avviare qualsiasi rilascio, la codebase locale deve superare `dart analyze .` e `flutter analyze` nel folder `app/` senza warning o info (`Zero Diagnostic Policy`).
3. **Pinning e Congelamento SHA**: L'HEAD locale ed il branch remoto devono coincidere perfettamente prima dell'avvio (`$expectedSha == $remoteSha`). Il tag creato da GitHub deve puntare esattamente a quel commit SHA.
4. **Stato Iniziale sempre Draft**: Tutti i rilasci vengono creati su GitHub in stato **Draft** (`--draft`) e **Prerelease** (se candidate). La pubblicazione finale è un'azione deliberata eseguita solo dopo lo smoke test e l'approvazione dell'utente.

---

## 2. Tipi di Rilascio e Parametri

### 2.1 Release Candidate (Pre-release di Test)
Usare per build candidate, beta o verifiche della pipeline.
- **`version`**: Versione SemVer con suffisso prerelease (es. `0.1.0-rc.1`, `0.1.0-rc.2`).
- **`channel`**: `beta` (o `dev`).
- **`release_kind`**: `candidate`.
- **`require_installer`**: `true`.
- **Environment GitHub**: `release-candidate` (utilizza la chiave `aura-catalog-development-2026-01`).

```powershell
gh workflow run release.yml `
  -f version=0.1.0-rc.1 `
  -f channel=beta `
  -f release_kind=candidate `
  -f require_installer=true
```

### 2.2 Release Ufficiale (Official Production Release)
Usare esclusivamente per le release stabili destinate agli utenti finali.
- **`version`**: Versione SemVer pura senza suffissi (es. `0.1.0`, `1.0.0`).
- **`channel`**: `stable`.
- **`release_kind`**: `official`.
- **`require_installer`**: `true`.
- **Environment GitHub**: `release` (richiede branch `main` o `master` e utilizza la chiave di produzione `aura-catalog-release-2026-01`).

```powershell
gh workflow run release.yml `
  --ref main `
  -f version=0.1.0 `
  -f channel=stable `
  -f release_kind=official `
  -f require_installer=true
```

---

## 3. Procedura Operativa Passo-Passo per l'Agente

### Fase A: Preparazione Pre-Rilascio e Congelamento SHA
1. Verificare che l'albero di lavoro locale sia pulito: `git status`.
2. Eseguire l'analisi statica locale:
   ```powershell
   dart analyze .
   Set-Location app; flutter analyze; Set-Location ..
   ```
3. Eseguire la suite di test locali:
   ```powershell
   dart test
   Set-Location app; flutter test; Set-Location ..
   ```
4. Congelare e verificare la corrispondenza esatta del commit SHA tra HEAD locale e branch remoto:
   ```powershell
   $branch = git branch --show-current
   $expectedSha = (git rev-parse HEAD).Trim()
   $remoteSha = (git rev-parse "origin/$branch").Trim()

   if ($expectedSha -ne $remoteSha) {
       throw "[FAIL-CLOSED] HEAD locale ($expectedSha) e branch remoto origin/$branch ($remoteSha) non coincidono. Eseguire git push prima del rilascio."
   }
   ```

---

### Fase B: Dislocazione ed Identificazione Deterministica della Run
1. Lanciare il workflow con i parametri appropriati (Candidate o Official):
   ```powershell
   gh workflow run release.yml --ref $branch -f version=<semver> -f channel=<channel> -f release_kind=<kind> -f require_installer=true
   ```
2. Attendere 3 secondi e recuperare in modo deterministico l'ID della run verificando la corrispondenza con `$expectedSha`:
   ```powershell
   Start-Sleep -Seconds 3

   $runsJson = gh run list --workflow=release.yml --event workflow_dispatch --branch $branch --limit 5 --json databaseId,headSha,createdAt
   $matchingRun = ($runsJson | ConvertFrom-Json) | Where-Object { $_.headSha -eq $expectedSha } | Select-Object -First 1

   if (-not $matchingRun) {
       throw "[FAIL-CLOSED] Impossibile individuare in modo univoco la run di workflow per il commit $expectedSha"
   }
   $runId = $matchingRun.databaseId
   Write-Host "Run individuata con successo: ID $runId (HEAD SHA: $expectedSha)"
   ```
3. Monitorare l'esecuzione della run fino alla conclusione:
   ```powershell
   gh run watch $runId
   ```

---

### Fase C: Ispezione della Draft Release, Tag SHA & Download Asset
1. Verificare l'ancoraggio della Draft Release creata e la corrispondenza del Tag Git:
   ```powershell
   $relInfo = gh release view "v$version" --json targetCommitish,tagName,isDraft,isPrerelease | ConvertFrom-Json
   $tagSha = (git rev-list -n 1 "v$version").Trim()

   if ($tagSha -ne $expectedSha) {
       throw "[FAIL-CLOSED] Il tag v$version ($tagSha) non punta al commit atteso ($expectedSha)"
   }
   ```
2. Scaricare gli asset generati in una cartella isolata (es. `build/release-verify/`):
   ```powershell
   gh release download "v$version" --dir build/release-verify/
   ```

---

### Fase D: Verification Asset Integrity Fail-Closed
1. Scompattare l'archivio ZIP portatile `aura-v<version>-win-x64.zip` in `build/release-verify/aura-v<version>-win-x64`.
2. Eseguire l'ispezione ed il verifier autoritativo fail-closed (che convalida automaticamente checksum SHA-256, eseguibili nativi PE, manifest del catalogo Ed25519 e header audio):
   ```powershell
   pwsh -File .\tool\verify_release_assets.ps1 -Version <version> -ReleaseDir build/release-verify -RequireInstaller
   ```
3. Verificare che l'output si concluda con l'esito tassativo:
   `✅ TUTTE LE VERIFICHE DI SICUREZZA ED INTEGRITA' SONO SUPERATE!`

---

### Fase E: Smoke Test Obbligatorio & Pubblicazione

#### Checklist di Smoke Test Manuale Obbligatorio:
Prima di procedere alla pubblicazione della release, l'agente deve verificare o richiedere la conferma dei seguenti punti di smoke test:
- [ ] Installazione completata senza errori tramite `aura_setup_v<version>.exe`.
- [ ] Avvio dell'applicazione sia dalla versione installata che da quella portatile (`.zip`).
- [ ] Rilevamento corretto del backend hardware di inferenza (`win-x64-cuda`, `win-x64-vulkan`, `win-x64-cpu-avx2`).
- [ ] Download ed onboarding/setup verificato del modello dal catalogo.
- [ ] Esecuzione di un turno completo di inferenza (turni `EvaluatorAgent` ed `ActorAgent`).
- [ ] Riproduzione audio e regolazione delle impostazioni.
- [ ] Shutdown dell'applicazione senza processi `llama-server.exe` rimasti orfani in background.
- [ ] Disinstallazione pulita tramite l'uninstaller.
- [ ] Conferma esplicita dell'utente per la pubblicazione finale.

#### Pubblicazione con Preservazione dei Flag Prerelease:
Dopo il superamento dello smoke test e l'approvazione dell'utente, l'agente esegue la pubblicazione specificando esplicitamente il flag prerelease:

- **Per Release Candidate**:
  ```powershell
  gh release edit "v$version" --draft=false --prerelease
  ```

- **Per Release Ufficiale**:
  ```powershell
  gh release edit "v$version" --draft=false --prerelease=false
  ```

Notificare l'utente con il link finale:
`https://github.com/naturewhisp/aura/releases/tag/v<version>`
