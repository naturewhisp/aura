# Attività propedeutica alla Tranche 6.4c
## Preparazione del primo catalogo ufficiale development di A.U.R.A.

Lavora sul repository A.U.R.A. corrente, partendo dalla baseline che chiude formalmente la Tranche 6.4b:

`0215e96310b29a2bc24aa938d9994cbaa3db4542`

Questa attività è propedeutica alla **Phase 6.4c — Download Engine, Resume & Staging**.

Non implementare ancora il download engine di produzione.

L'obiettivo è preparare l'ambiente di sviluppo e produrre il primo catalogo remoto firmato di A.U.R.A., realmente consumabile dall'implementazione 6.4a/6.4b.

Il catalogo deve contenere:

1. il modello Actor ufficiale;
2. il modello Evaluator ufficiale;
3. un modello leggero destinato esclusivamente alle prove tecniche del futuro download engine.

Il risultato deve essere riproducibile, firmato, verificabile, compatibile con i contratti runtime già implementati, privo di riferimenti mobili a branch Hugging Face e utilizzabile per i primi test reali della 6.4c.

---

# 1. Vincoli generali

Prima di modificare il repository:

1. Leggi integralmente:
   - `AGENTS.md`;
   - la documentazione Phase 6.4;
   - `MODEL_MANIFEST_SPEC`;
   - le specifiche di catalog acquisition, trust e signing;
   - l'implementazione 6.4a;
   - l'implementazione 6.4b;
   - i modelli di dominio del catalogo;
   - il canonicalizer RFC 8785/JCS;
   - il verifier Ed25519;
   - il trust store;
   - la candidate factory;
   - la selection policy;
   - il provisioning path resolver.

2. Individua e documenta:
   - struttura esatta di `CatalogEnvelope`;
   - struttura esatta di `CatalogSignedPayload`;
   - struttura esatta di `CatalogManifest`;
   - struttura esatta degli artifact descriptor;
   - valori ammessi per artifact type, source type, quantization e metadata;
   - implementazione RFC 8785/JCS già presente;
   - implementazione Ed25519 già presente;
   - trust store development già disponibile;
   - utility già esistenti e riutilizzabili.

3. Usa esclusivamente i modelli di dominio già presenti.

4. Non creare DTO paralleli.

5. Non reimplementare RFC 8785/JCS, Ed25519, validazione, trust evaluation o compatibility evaluation.

6. Il catalogo generato deve essere accettato attraverso il percorso runtime reale introdotto in 6.4a e 6.4b.

7. Python può essere usato esclusivamente come tooling di sviluppo, mai come dipendenza dell'applicazione o del core.

8. Non inserire GGUF o chiavi private nel repository Git.

9. Se la struttura reale del repository differisce da queste istruzioni, adegua l'implementazione ai contratti correnti, documenta la differenza e non aggirare i contratti esistenti.

---

# 2. Catalogo da produrre

Il catalogo è il primo catalogo ufficiale dal punto di vista del formato, ma deve essere classificato come development.

Usare:

- catalog ID: `aura-official-development`
- catalog revision: `1`
- environment: `development`, solo se esiste un campo metadata/extensions già supportato
- signature algorithm: usare esattamente l'identificatore supportato dal dominio corrente
- key ID: `aura-catalog-development-2026-01`
- issuedAt: timestamp UTC configurabile o fornito esplicitamente
- expiresAt: durata limitata, preferibilmente 90 giorni

Non utilizzare il futuro namespace production e non introdurre proprietà JSON non riconosciute dal parser corrente.

---

# 3. Artifact ufficiali

## 3.1 Actor ufficiale

- logical model ID: `gemma-4-12b-it-qat-q4_0`
- application model ID: `google/gemma-4-12b-qat` (o `gemma-4-12b-it-qat-q4-0` come registrato in `ModelCatalog`)
- pagina LM Studio di riferimento: `https://lmstudio.ai/models/google/gemma-4-12b-qat`
- Hugging Face repository: `lmstudio-community/gemma-4-12B-it-QAT-GGUF`
- filename: `gemma-4-12B-it-QAT-Q4_0.gguf`
- quantization: `Q4_0`
- role: `actor`
- intended usage: `production-default`
- selectable: `true`
- default Actor: `true`
- default Evaluator: `false`
- auto activation: secondo le regole correnti del manifest

Il modello Gemma 4 12B QAT supporta il ragionamento/thinking nativo. Quando viene utilizzato con backend `llama.cpp` o server locale LM Studio, assicurarsi che il parametro `thinking` sia esplicitamente disattivato (`thinking: false` / `enable_thinking: false` / `thinking: { type: "disabled" }`) per l'inferenza ordinaria, al fine di prevenire latenze eccessive e l'emissione di tag di pensiero parassiti (`<thought>`).

Non usare il precedente Gemma Q4_K_M come default, `resolve/main`, URL non pinnati, branch o tag mobili.

## 3.2 Evaluator ufficiale

- logical model ID: `ministral-3-3b-instruct-2512-q4_k_m`
- application/model router ID: `mistralai/ministral-3-3b`
- pagina LM Studio di riferimento: `https://lmstudio.ai/models/mistralai/ministral-3-3b`
- Hugging Face repository: `lmstudio-community/Ministral-3-3B-Instruct-2512-GGUF`
- filename: `Ministral-3-3B-Instruct-2512-Q4_K_M.gguf`
- quantization: `Q4_K_M`
- role: `evaluator`
- intended usage: `production-default`
- selectable: `true`
- default Evaluator: `true`
- default Actor: `false`

Non includere `mmproj`, artifact vision o dipendenze multimodali. L'Evaluator è usato come modello testuale.

## 3.3 Modello tecnico leggero

- logical model ID: `qwen2.5-0.5b-instruct-download-test-q4_0`
- Hugging Face repository: `bartowski/Qwen2.5-0.5B-Instruct-GGUF`
- filename: `Qwen2.5-0.5B-Instruct-Q4_0.gguf`
- quantization: `Q4_0`
- role: `technical-test`
- intended usage: `download-engine-validation`
- selectable: `false`
- default Actor: `false`
- default Evaluator: `false`
- auto activation: `false`
- gameplay routing: escluso

Questo artifact serve esclusivamente per download, progresso, cancellazione, retry, timeout, resume, Range request, staging, verifica size/SHA-256, corruzione intenzionale e pulizia. Non deve essere selezionato dal `ModelRouter`.

---

# 4. Struttura del tooling

Creare tooling development dedicato:

```text
tool/catalog/
  README.md
  requirements.txt
  catalog_sources.json
  resolve_huggingface_metadata.py
  download_verify_artifact.py
  generate_catalog.dart
  verify_catalog.dart
  keygen_development.dart

.local/catalog-keys/
  aura-catalog-development-2026-01.private

build/catalog/
  resolved_sources.json
  aura-official-development.catalog.json
  aura-official-development.catalog.report.json
  aura-official-development.catalog.report.md
```

Aggiungere a `.gitignore`:

```text
.local/catalog-keys/
build/catalog/
tool/catalog/.venv/
tool/catalog/__pycache__/
```

Separare chiaramente input editoriali, metadata risolti, catalogo firmato, report e secret locali.

---

# 5. Dipendenze Python

Creare `tool/catalog/requirements.txt` con una versione esatta e pinnata di `huggingface_hub`.

Esempio:

```text
huggingface_hub==<VERSIONE_VERIFICATA>
```

Windows PowerShell:

```powershell
py -m venv tool/catalog/.venv
tool/catalog/.venv/Scripts/Activate.ps1
python -m pip install --upgrade pip
pip install -r tool/catalog/requirements.txt
```

Linux/macOS:

```bash
python3 -m venv tool/catalog/.venv
source tool/catalog/.venv/bin/activate
python -m pip install --upgrade pip
pip install -r tool/catalog/requirements.txt
```

Non richiedere autenticazione per repository pubblici. Non memorizzare o stampare token Hugging Face.

---

# 6. `catalog_sources.json`

Creare una source declaration leggibile e versionabile:

```json
{
  "schemaVersion": "1.0",
  "catalogId": "aura-official-development",
  "artifacts": [
    {
      "logicalModelId": "gemma-4-12b-it-qat-q4_0",
      "repository": "lmstudio-community/gemma-4-12B-it-QAT-GGUF",
      "filename": "gemma-4-12B-it-QAT-Q4_0.gguf",
      "revision": null,
      "quantization": "Q4_0",
      "role": "actor",
      "intendedUsage": "production-default"
    },
    {
      "logicalModelId": "ministral-3-3b-instruct-2512-q4_k_m",
      "applicationModelId": "mistralai/ministral-3-3b",
      "repository": "lmstudio-community/Ministral-3-3B-Instruct-2512-GGUF",
      "filename": "Ministral-3-3B-Instruct-2512-Q4_K_M.gguf",
      "revision": null,
      "quantization": "Q4_K_M",
      "role": "evaluator",
      "intendedUsage": "production-default"
    },
    {
      "logicalModelId": "qwen2.5-0.5b-instruct-download-test-q4_0",
      "repository": "bartowski/Qwen2.5-0.5B-Instruct-GGUF",
      "filename": "Qwen2.5-0.5B-Instruct-Q4_0.gguf",
      "revision": null,
      "quantization": "Q4_0",
      "role": "technical-test",
      "intendedUsage": "download-engine-validation"
    }
  ]
}
```

Il comando `resolve` deve risolvere il commit corrente, mostrare il risultato e scrivere soltanto con `--write` o conferma esplicita.

Dopo il pin iniziale, `revision` deve contenere un commit SHA completo. Il comando di generazione deve fallire con revisioni nulle, vuote, `main`, branch, tag mobili o commit incompleti.

---

# 7. Uso dell'API Hugging Face

Implementare `resolve_huggingface_metadata.py` usando:

```python
from huggingface_hub import HfApi
```

## 7.1 Risoluzione iniziale

```python
api = HfApi()

info = api.model_info(
    repo_id=repo_id,
    files_metadata=True,
)
```

Recuperare:

```python
commit_sha = info.sha
siblings = info.siblings
```

Validare che `info.sha` sia presente, completo e che il filename richiesto compaia esattamente una volta.

## 7.2 Seconda interrogazione pinnata

```python
pinned_info = api.model_info(
    repo_id=repo_id,
    revision=commit_sha,
    files_metadata=True,
)
```

Usare esclusivamente i metadata della seconda risposta per il catalogo. Questo evita race tra risoluzione del branch e lettura dei metadata.

## 7.3 Ricerca esatta del file

```python
matches = [
    sibling
    for sibling in pinned_info.siblings
    if sibling.rfilename == filename
]

if len(matches) != 1:
    raise RuntimeError(
        f"Expected exactly one file named {filename!r}, found {len(matches)}"
    )

file_info = matches[0]
```

Non usare confronti case-insensitive, filename parziali, glob ambigui o euristiche.

## 7.4 Dimensione

```python
size_bytes = file_info.size

if not isinstance(size_bytes, int) or size_bytes <= 0:
    raise RuntimeError("Remote file size is missing or invalid")
```

Se necessario, usare i metadata LFS/Xet, ma non valori letti dalle pagine HTML.

## 7.5 SHA-256

Gestire oggetti e dizionari:

```python
def read_metadata_value(metadata, *names):
    if metadata is None:
        return None

    if isinstance(metadata, dict):
        for name in names:
            value = metadata.get(name)
            if value is not None:
                return value
        return None

    for name in names:
        value = getattr(metadata, name, None)
        if value is not None:
            return value

    return None
```

Recuperare:

```python
lfs = getattr(file_info, "lfs", None)
sha256 = read_metadata_value(lfs, "sha256", "oid")
```

Gestire anche metadata Xet se richiesto dalla versione pinnata della libreria.

Normalizzare e validare:

```python
import re

if isinstance(sha256, str) and sha256.startswith("sha256:"):
    sha256 = sha256.removeprefix("sha256:")

sha256 = sha256.lower().strip()

if re.fullmatch(r"[0-9a-f]{64}", sha256) is None:
    raise RuntimeError(
        f"Invalid or missing SHA-256 for {repo_id}/{filename}"
    )
```

Non usare ETag, commit Git, hash del pointer LFS, pagina HTML o URL come SHA-256.

## 7.6 URL immutabile

```python
from urllib.parse import quote

encoded_filename = quote(filename, safe="/")

download_url = (
    f"https://huggingface.co/{repo_id}"
    f"/resolve/{commit_sha}/{encoded_filename}"
)
```

Validare l'assenza di `/resolve/main/` e la presenza del commit completo.

## 7.7 Licenza

```python
license_id = None
card_data = getattr(pinned_info, "card_data", None)

if card_data is not None:
    if isinstance(card_data, dict):
        license_id = card_data.get("license")
    else:
        license_id = getattr(card_data, "license", None)
```

Se la licenza non è disponibile, produrre un finding e non classificare l'artifact come release-ready.

---

# 8. Implementazione Python di riferimento

Usare questo comportamento come riferimento, poi aggiungere timeout, gestione errori, output deterministico, exit code, logging sicuro, test, eventuale supporto Xet, scrittura atomica e validazione schema:

```python
from __future__ import annotations

import re
from dataclasses import dataclass
from urllib.parse import quote

from huggingface_hub import HfApi


COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class ResolvedArtifact:
    logical_model_id: str
    repository: str
    filename: str
    revision: str
    download_url: str
    size_bytes: int
    sha256: str
    quantization: str
    role: str
    intended_usage: str
    license: str | None


def metadata_value(metadata: object, *names: str) -> object | None:
    if metadata is None:
        return None

    if isinstance(metadata, dict):
        for name in names:
            if name in metadata:
                return metadata[name]
        return None

    for name in names:
        value = getattr(metadata, name, None)
        if value is not None:
            return value

    return None


def resolve_artifact(
    api: HfApi,
    *,
    logical_model_id: str,
    repository: str,
    filename: str,
    revision: str | None,
    quantization: str,
    role: str,
    intended_usage: str,
) -> ResolvedArtifact:
    if revision is None:
        head_info = api.model_info(
            repo_id=repository,
            files_metadata=True,
        )
        revision = head_info.sha

    if revision is None:
        raise RuntimeError(f"Missing repository revision for {repository}")

    revision = revision.lower().strip()

    if COMMIT_PATTERN.fullmatch(revision) is None:
        raise RuntimeError(
            f"Revision for {repository} is not a full commit SHA: {revision!r}"
        )

    info = api.model_info(
        repo_id=repository,
        revision=revision,
        files_metadata=True,
    )

    if info.sha is None or info.sha.lower() != revision:
        raise RuntimeError(
            f"Unexpected commit for {repository}: "
            f"requested={revision}, resolved={info.sha}"
        )

    matches = [
        sibling
        for sibling in info.siblings
        if sibling.rfilename == filename
    ]

    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one file {filename!r} in "
            f"{repository}@{revision}, found {len(matches)}"
        )

    file_info = matches[0]

    size_bytes = file_info.size
    if not isinstance(size_bytes, int) or size_bytes <= 0:
        lfs_size = metadata_value(getattr(file_info, "lfs", None), "size")
        if isinstance(lfs_size, int):
            size_bytes = lfs_size

    if not isinstance(size_bytes, int) or size_bytes <= 0:
        raise RuntimeError(
            f"Missing or invalid size for {repository}/{filename}"
        )

    lfs = getattr(file_info, "lfs", None)
    sha256 = metadata_value(lfs, "sha256", "oid")

    if not isinstance(sha256, str):
        raise RuntimeError(
            f"Missing SHA-256 metadata for {repository}/{filename}"
        )

    sha256 = sha256.lower().strip()

    if sha256.startswith("sha256:"):
        sha256 = sha256.removeprefix("sha256:")

    if SHA256_PATTERN.fullmatch(sha256) is None:
        raise RuntimeError(
            f"Invalid SHA-256 for {repository}/{filename}: {sha256!r}"
        )

    encoded_filename = quote(filename, safe="/")
    download_url = (
        f"https://huggingface.co/{repository}"
        f"/resolve/{revision}/{encoded_filename}"
    )

    if "/resolve/main/" in download_url:
        raise RuntimeError("Mutable Hugging Face URL generated")

    card_data = getattr(info, "card_data", None)
    license_id = metadata_value(card_data, "license")

    return ResolvedArtifact(
        logical_model_id=logical_model_id,
        repository=repository,
        filename=filename,
        revision=revision,
        download_url=download_url,
        size_bytes=size_bytes,
        sha256=sha256,
        quantization=quantization,
        role=role,
        intended_usage=intended_usage,
        license=license_id if isinstance(license_id, str) else None,
    )
```

---

# 9. API REST alternativa

Documentare o implementare opzionalmente:

```text
GET https://huggingface.co/api/models/{repository}/revision/{revision}?blobs=true
```

Esempio:

```text
GET https://huggingface.co/api/models/lmstudio-community/gemma-4-12B-it-QAT-GGUF/revision/<COMMIT_SHA>?blobs=true
```

La risposta è input esterno non fidato. Cercare il filename esatto e recuperare `rfilename`, `size`, `lfs.sha256` o metadata Xet equivalenti.

Usare `huggingface_hub` come percorso preferito. Non fare scraping HTML.

---

# 10. Metadata risolti

Produrre `build/catalog/resolved_sources.json` con ordinamento stabile e almeno:

- logical model ID;
- repository;
- filename;
- revision;
- immutable download URL;
- sizeBytes;
- SHA-256;
- quantization;
- role;
- intended usage;
- license;
- verification status.

Non inserire timestamp variabili nel payload firmato salvo previsione esplicita del contratto.

---

# 11. Download e verifica locale

Creare `tool/catalog/download_verify_artifact.py`.

È solo tooling development e non è il download engine 6.4c.

Deve:

1. leggere `resolved_sources.json`;
2. selezionare per logical ID;
3. effettuare download HTTPS;
4. seguire redirect;
5. scrivere su file temporaneo;
6. mostrare progresso;
7. calcolare SHA-256 incrementalmente;
8. contare i byte;
9. confrontare size e hash;
10. rinominare solo dopo verifica;
11. eliminare il temporaneo in caso di errore, salvo opzione diagnostica;
12. restituire exit code non-zero su mismatch.

Per `qwen2.5-0.5b-instruct-download-test-q4_0` eseguire obbligatoriamente il download completo e registrare `locally-downloaded-and-verified`.

Per Actor ed Evaluator sono obbligatori i metadata API; la verifica locale completa deve essere disponibile ma non eseguita nella CI ordinaria.

---

# 12. Chiave Ed25519 development

Creare una coppia compatibile con il verifier esistente.

- key ID: `aura-catalog-development-2026-01`
- directory privata: `.local/catalog-keys/`

Requisiti:

- keygen esplicito;
- nessuna rigenerazione automatica;
- chiave privata mai versionata;
- chiave pubblica registrabile nel trust store;
- formato compatibile col runtime;
- permessi restrittivi quando disponibili;
- nessun secret nei log;
- nessuna chiave production;
- nessuna chiave privata nelle fixture.

`generate` deve fallire se la chiave privata manca.

---

# 13. Generazione catalogo

Implementare `generate_catalog.dart`.

Deve:

1. leggere `catalog_sources.json`;
2. leggere `resolved_sources.json`;
3. verificare corrispondenza esatta di logical ID, repository, filename e revision;
4. rifiutare revisioni mobili;
5. costruire gli artifact descriptor reali;
6. costruire `CatalogManifest`;
7. costruire `CatalogSignedPayload`;
8. serializzare JSON-safe;
9. canonicalizzare col canonicalizer RFC 8785/JCS esistente;
10. firmare i byte canonici con Ed25519;
11. costruire `CatalogEnvelope`;
12. scrivere atomicamente il catalogo;
13. produrre report JSON e Markdown;
14. non esporre la chiave privata;
15. non implementare un secondo canonicalizer.

Timestamp UTC, espliciti, passabili da CLI e controllabili nei test.

---

# 14. Verifica tramite runtime reale

Implementare `verify_catalog.dart` usando il percorso runtime reale:

1. parsing envelope;
2. validazione strutturale;
3. validazione manifest;
4. canonicalizzazione RFC 8785/JCS;
5. verifica Ed25519;
6. lookup trust store;
7. compatibility evaluation;
8. `ValidatedCatalogCandidateFactory`;
9. selection policy quando applicabile;
10. esito finale tipizzato.

Aggiungere test negativi per payload/firma alterati, key ID sconosciuto, hash malformato, size zero, URL `resolve/main`, commit incompleto, filename errato, logical ID duplicato, modello tecnico default e metadata non JSON-safe.

---

# 15. Hosting development

Preparare istruzioni per ospitare esclusivamente il JSON del catalogo.

I GGUF continuano a essere scaricati direttamente da Hugging Face.

La modalità development deve supportare:

- HTTPS;
- `Content-Type: application/json`;
- ETag;
- HTTP 304;
- sostituzione atomica;
- URL stabile.

Documentare la configurazione del `RemoteCatalogProvider`.

---

# 16. Test obbligatori

## API Hugging Face

Testare repository/revisione/filename inesistenti, size/hash mancanti o malformati, commit incompleto, risposta malformata, timeout, HTTP failure, assenza di `main` e URL encoding.

Usare mock o fixture; la suite ordinaria non deve dipendere dalla rete.

## Catalogo

Testare tre artifact presenti, ID univoci, Actor/Evaluator corretti, modello tecnico escluso dal routing, URL HTTPS immutabili, size/hash validi, quantizzazioni corrette, payload deterministico, firma valida, accettazione runtime e rifiuto del tampering.

## Test reale manuale

Eseguire:

1. interrogazione reale Hugging Face per tutti i modelli;
2. pin dei tre commit;
3. download completo del modello tecnico;
4. hash locale;
5. confronto size;
6. generazione catalogo;
7. firma;
8. verifica runtime;
9. pubblicazione su endpoint development;
10. refresh reale tramite 6.4b.

Non inserire il download reale nella CI ordinaria.

---

# 17. Output richiesti

Produrre:

1. `tool/catalog/catalog_sources.json`;
2. `build/catalog/resolved_sources.json`;
3. `build/catalog/aura-official-development.catalog.json`;
4. `build/catalog/aura-official-development.catalog.report.json`;
5. `build/catalog/aura-official-development.catalog.report.md`;
6. descriptor o copia della chiave pubblica development;
7. documentazione per hosting e provider remoto.

Il report deve includere per artifact: logical ID, role, repository, commit, filename, URL immutable, size, SHA-256, quantization, licenza, data acquisizione e stato verifica.

---

# 18. Report finale

Produrre un walkthrough con baseline, file creati/modificati, dipendenze, versioni Python e `huggingface_hub`, commit dei repository, URL, size, hash, licenze, verifica locale, chiave pubblica, key ID, revision, comandi, analyzer, test, verifica catalogo, HTTP 200/304, limitazioni e commit finale.

Non riportare chiave privata, token o altri secret.

---

# 19. Non-obiettivi

Non implementare download engine 6.4c, resume/checkpoint `.part` production, installazione, registrazione verified artifact 6.4d, activation, update/repair/rollback, UI, wizard, pipeline signing production 6.9, mirror GGUF, repository gated, autenticazione Hugging Face, multimodalità o `mmproj`.

---

# 20. Gate di completamento

L'attività può essere chiusa solo se:

1. il catalogo contiene esattamente i tre artifact;
2. repository e filename sono quelli definiti;
3. tutti i commit sono pinnati;
4. nessun URL usa `main`;
5. size e SHA-256 provengono dalla revisione pinnata;
6. il modello tecnico è stato scaricato e verificato;
7. il catalogo è firmato;
8. il runtime 6.4a/6.4b lo accetta;
9. un catalogo alterato viene rifiutato;
10. la chiave privata non è versionata;
11. analyzer e test passano;
12. esiste il walkthrough finale.

Prima di modificare il repository, mostra:

- piano operativo;
- struttura file proposta;
- versione Python;
- versione `huggingface_hub`;
- gestione della chiave;
- incompatibilità con i contratti correnti.

Non procedere con implementazioni alternative senza segnalare prima il problema.

---

# 21. Esito dello Sviluppo e Certificazione del Catalogo (Completamento)

## 21.1 Sintesi dell'Esecuzione

L'attività propedeutica alla **Tranche 6.4c** è stata eseguita e verificata con esito positivo in data **27 Luglio 2026**.

- **Baseline di partenza**: `0215e96310b29a2bc24aa938d9994cbaa3db4542`
- **Ambiente di Sviluppo**: Python `3.12.10`, `huggingface_hub==1.25.1`
- **Stato del Gate di Completamento**: **TUTTI I 12 CRITERI APPLICATI E SUPERATI CON SUCCESSO**

---

## 21.2 Struttura del Catalogo Generato

Il primo catalogo remoto firmato di sviluppo (`build/catalog/aura-official-development.catalog.json`) contiene l'envelope firmata `CatalogEnvelope`:

- **Catalog ID**: `aura-official-development`
- **Catalog Revision**: `1`
- **Key ID**: `aura-catalog-development-2026-01`
- **Signature Algorithm**: `ed25519-v1`
- **Chiave Pubblica Hex**: `0112e7984ea2f973a3c5d7e2c9d7b504a76a8e031f93796756a719dbc8b745bf`
- **Canonicalizzazione**: RFC 8785 (JSON Canonicalization Scheme - JCS) tramite `Rfc8785JcsCanonicalizer`
- **Firma crittografica**: Ed25519 (Base64) generata tramite `keygen_development.dart` e conservata in `.local/catalog-keys/` (esclusa da Git via `.gitignore`).

---

## 21.3 Certificazione degli Artifacts del Catalogo

### 1. Actor Ufficiale (`gemma-4-12b-it-qat-q4_0`)
- **Role**: `actor`
- **Application Model ID**: `google/gemma-4-12b-qat`
- **Pagina LM Studio**: [https://lmstudio.ai/models/google/gemma-4-12b-qat](https://lmstudio.ai/models/google/gemma-4-12b-qat)
- **Repository HF**: `lmstudio-community/gemma-4-12B-it-QAT-GGUF`
- **Commit SHA (pinnato)**: `aaec3dd9d1012557147a627142759994d1fd8d37`
- **Filename**: `gemma-4-12B-it-QAT-Q4_0.gguf`
- **Download URL (immutabile)**: `https://huggingface.co/lmstudio-community/gemma-4-12B-it-QAT-GGUF/resolve/aaec3dd9d1012557147a627142759994d1fd8d37/gemma-4-12B-it-QAT-Q4_0.gguf`
- **Size**: `6.975.879.008` byte
- **SHA-256**: `f568ac5de71c8fcac5d5794494388ad94db9e18b4368ca897e21b30d2448eeec`
- **Quantizzazione**: `Q4_0`
- **Disponibilità Server**: Verificata tramite richiesta HTTP HEAD (`STATUS 200 OK`)
- **Direttiva Thinking**: Disattivato esplicitamente per `llama.cpp` (`thinking: false` / `enable_thinking: false`).

### 2. Evaluator Ufficiale (`ministral-3-3b-instruct-2512-q4_k_m`)
- **Role**: `evaluator`
- **Application Model ID**: `mistralai/ministral-3-3b`
- **Pagina LM Studio**: [https://lmstudio.ai/models/mistralai/ministral-3-3b](https://lmstudio.ai/models/mistralai/ministral-3-3b)
- **Repository HF**: `lmstudio-community/Ministral-3-3B-Instruct-2512-GGUF`
- **Commit SHA (pinnato)**: `94b49547f1931930f002226bc0a68b5f10a4ee25`
- **Filename**: `Ministral-3-3B-Instruct-2512-Q4_K_M.gguf`
- **Download URL (immutabile)**: `https://huggingface.co/lmstudio-community/Ministral-3-3B-Instruct-2512-GGUF/resolve/94b49547f1931930f002226bc0a68b5f10a4ee25/Ministral-3-3B-Instruct-2512-Q4_K_M.gguf`
- **Size**: `2.146.498.240` byte
- **SHA-256**: `ee46f8f2cc4acf15e89699563e23b4a3919dce2e9ce7c44b53778d6590318e96`
- **Quantizzazione**: `Q4_K_M`
- **Disponibilità Server**: Verificata tramite richiesta HTTP HEAD (`STATUS 200 OK`).

### 3. Modello Tecnico Leggero per Test (`qwen2.5-0.5b-instruct-download-test-q4_0`)
- **Role**: `technical-test` (`intendedUsage: "download-engine-validation"`, `selectable: false`)
- **Repository HF**: `bartowski/Qwen2.5-0.5B-Instruct-GGUF`
- **Commit SHA (pinnato)**: `41ba88dbac95fed2528c92514c131d73eb5a174b`
- **Filename**: `Qwen2.5-0.5B-Instruct-Q4_0.gguf`
- **Download URL (immutabile)**: `https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/41ba88dbac95fed2528c92514c131d73eb5a174b/Qwen2.5-0.5B-Instruct-Q4_0.gguf`
- **Size**: `352.972.352` byte (~336 MB)
- **SHA-256**: `c8cd5f37dd1235fb010c45316d4ff8af875e1a4e0ff368b4bf6cacb9053d4919`
- **Quantizzazione**: `Q4_0`
- **Disponibilità Server**: Verificata tramite richiesta HTTP HEAD (`STATUS 200 OK`)
- **Verifica Locale**: Scaricato integralmente ed HASH convalidato con successo da `download_verify_artifact.py` con esito `locally-downloaded-and-verified`.

---

## 21.4 Risultati delle Verifiche e Collaudi

1. **Verificatore Runtime (`verify_catalog.dart`)**:
   - Valutato tramite la pipeline di produzione 6.4a/6.4b (`DefaultValidatedCatalogCandidateFactory`, `Ed25519CatalogSignatureVerifier`, `CatalogValidationService`).
   - Esito: **Firma valida** (`CatalogSignatureVerificationStatus.valid`), **Trust Level**: `CatalogTrustLevel.signatureVerified`.

2. **Analisi Statica (Zero-Diagnostic Policy)**:
   - `dart analyze`: **No issues found!**
   - `flutter analyze` in `app/`: **No issues found!**

3. **Suite dei Test Unitari**:
   - `dart test`: **574/574 test superati con successo**. Include test di regressione, validazione semantica e reiezione della manomissione di firma e payload in `catalog_official_development_test.dart`.

4. **Walkthrough e Documentazione Prodotta**:
   - Creati [README.md](file:///c:/Users/dendo/Documents/GitHub/aura/tool/catalog/README.md), [walkthrough.md](file:///C:/Users/dendo/.gemini/antigravity-ide/brain/5f49e9d4-d0ad-413b-b360-686416254a05/walkthrough.md) ed i report automatici `aura-official-development.catalog.report.json` ed `aura-official-development.catalog.report.md`.

