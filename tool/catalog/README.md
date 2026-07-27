# Tooling di Sviluppo Catalogo A.U.R.A. (`tool/catalog/`)

Questo set di script e strumenti è destinato esclusivamente alla preparazione, firma e validazione del catalogo ufficiale di sviluppo di A.U.R.A. (`aura-official-development`).

## Struttura del Tooling

- `requirements.txt`: Dipendenze Python pinnate (`huggingface_hub==1.25.1`).
- `catalog_sources.json`: Dichiarazione editoriale iniziale dei 3 modelli ufficiali (Actor, Evaluator, Technical Test).
- `keygen_development.dart`: Generatore della coppia di chiavi Ed25519 di sviluppo (`aura-catalog-development-2026-01`).
- `resolve_huggingface_metadata.py`: Risolutore metadata Hugging Face con pin dei commit SHA completi e verifica hash LFS.
- `download_verify_artifact.py`: Downloader/verificatore locale per l'artifact di test leggero.
- `generate_catalog.dart`: Generatore del catalogo firmato `CatalogEnvelope` con RFC 8785 / JCS canonicalization ed Ed25519 signing.
- `verify_catalog.dart`: Verificatore runtime del catalogo firmato tramite `CatalogValidationService` e `ValidatedCatalogCandidateFactory`.

## Prerequisiti

### Environment Python (Windows PowerShell)

```powershell
py -m venv tool/catalog/.venv
tool/catalog/.venv/Scripts/Activate.ps1
python -m pip install --upgrade pip
pip install -r tool/catalog/requirements.txt
```

## Flusso di Esecuzione Completo

1. **Generazione Chiave Development**:
   ```powershell
   dart run tool/catalog/keygen_development.dart
   ```
2. **Risoluzione Metadata & Pinning Hugging Face**:
   ```powershell
   tool/catalog/.venv/Scripts/python.exe tool/catalog/resolve_huggingface_metadata.py --write
   ```
3. **Download e Verifica Locale Modello Tecnico Leggero**:
   ```powershell
   tool/catalog/.venv/Scripts/python.exe tool/catalog/download_verify_artifact.py
   ```
4. **Generazione e Firma Catalogo**:
   ```powershell
   dart run tool/catalog/generate_catalog.dart
   ```
5. **Verifica Runtime del Catalogo**:
   ```powershell
   dart run tool/catalog/verify_catalog.dart
   ```
