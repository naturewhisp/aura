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
3. **Stato Iniziale sempre Draft**: Tutti i rilasci vengono creati su GitHub in stato **Draft** (`--draft`) e **Prerelease** (se candidate). La pubblicazione finale è un'azione deliberata eseguita dopo lo smoke test.

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

### Fase A: Preparazione Pre-Rilascio
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
4. Assicurarsi che le ultime modifiche siano state pushate sul ramo remoto interessato (`git push origin <branch>`).

---

### Fase B: Dislocazione ed Monitoraggio della Pipeline CI/CD
1. Lanciare il workflow con i parametri appropriati (Candidate o Official):
   ```powershell
   gh workflow run release.yml -f version=<semver> -f channel=<channel> -f release_kind=<kind> -f require_installer=true
   ```
2. Recuperare l'ID della run appena avviata e monitorarla:
   ```powershell
   gh run list --workflow=release.yml --limit 1
   gh run watch <run_id>
   ```

---

### Fase C: Ispezione della Draft Release e Download Asset
Una volta completato con successo il job su GitHub:
1. Ispezionare la Draft Release creata:
   ```powershell
   gh release list --limit 5
   gh release view v<version>
   ```
2. Scaricare gli asset generati in una cartella di test (es. `build/release-verify/`):
   ```powershell
   gh release download v<version> --dir build/release-verify/
   ```

---

### Fase D: Verification Asset Integrity (Fail-Closed)
1. Verificare la corrispondenza dei checksum SHA-256:
   ```powershell
   Get-FileHash -Path 'build/release-verify/*' -Algorithm SHA256
   ```
2. Scompattare lo ZIP `aura-v<version>-win-x64.zip` in `build/release-verify/aura-v<version>-win-x64`.
3. Eseguire lo script di verifica fail-closed:
   ```powershell
   pwsh -File .\tool\verify_release_assets.ps1 -Version <version> -ReleaseDir build/release-verify -RequireInstaller
   ```
4. Verificare l'uscita con exit code 0 e l'esito:
   `✅ TUTTE LE VERIFICHE DI SICUREZZA ED INTEGRITA' SONO SUPERATE!`

---

### Fase E: Pubblicazione Definitiva (Smoke Test & Publish)
Dopo aver confermato l'esito positivo delle verifiche e ricevuto la conferma dell'utente:
1. Promuovere la Draft Release a Release Pubblica scaricabile:
   ```powershell
   gh release edit v<version> --draft=false
   ```
2. Notificare l'utente fornendo l'URL della Release ufficiale pubblicata:
   `https://github.com/naturewhisp/aura/releases/tag/v<version>`
