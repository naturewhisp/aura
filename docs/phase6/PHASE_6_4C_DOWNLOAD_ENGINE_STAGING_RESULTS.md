# Documentazione ed Evidenza — Tranche 6.4c (Download Engine, HTTP Range Resume & Staging)

Questo documento registra l'evidenza tecnica e l'esito dei test per la **Tranche 6.4c** del motore di provisioning di A.U.R.A.

---

## 1. Obiettivi e Vincoli Contrattuali Implementati

### 1.1 Strong ETag Resume Policy con `If-Range`
- L'header `Range: bytes=<offset>-` viene inviato esclusivamente accompagnato dall'header `If-Range: "<strong-etag>"`.
- Il resume è consentito **unicamente se** il checkpoint contiene un **ETag forte** (non prefissato da `W/` e sintatticamente valido). Se l'ETag nel checkpoint è debole (`W/"..."`), nullo o invalido, `If-Range` non viene inviato, il checkpoint viene resettato ed il download riparte dal byte 0.

### 1.2 Validazione Stringente della Risposta HTTP `206 Partial Content`
Una risposta `206` viene accettata per il resume **esclusivamente se**:
- Status è `206 Partial Content`;
- L'ETag restituito è un ETag forte corrispondente a `checkpoint.strongEtag`;
- `Content-Range` rispetta `bytes <start>-<end>/<total>`;
- `Content-Range.start == downloadedBytes`;
- `Content-Range.total == expectedSizeBytes`;
- `Content-Length == (end - start + 1)` (quando presente).

In caso di mancata corrispondenza, la risposta `206` viene rifiutata, il file `.part` viene troncato a 0 byte ed il download riparte dal byte 0 via GET incondizionata.

### 1.3 Gestione Restrittiva HTTP `416 Range Not Satisfiable`
Il completamento per codice status `416` è accettato **unicamente se**:
- `local size == expectedSizeBytes`;
- `remote total == expectedSizeBytes` (da `Content-Range: bytes */<total>`);
- L'URL della richiesta e l'ETag forte corrispondono al checkpoint.

In tal caso viene emesso uno `StagingArtifact` (`downloadComplete: true`, `cryptographicallyVerified: false`). La verifica SHA-256 e l'ingestione nello store gestito rimangono differite alla Tranche 6.4d.

### 1.4 Riconciliazione ed Ordine Atomico di Persistenza
- **Riconciliazione all'avvio:**
  - `checkpoint assente + file .part presente` $\rightarrow$ reset `.part` a 0 byte.
  - `checkpoint.downloadedBytes > part.length` $\rightarrow$ reset `.part` a 0 byte ed eliminazione checkpoint.
  - `checkpoint.downloadedBytes < part.length` $\rightarrow$ tronca il file `.part` a `checkpoint.downloadedBytes`.
  - `checkpoint.downloadedBytes == part.length` $\rightarrow$ candidato idoneo al resume.
- **Ordine Atomico su Disco:** `Scrittura chunk -> Flush file su disco -> Scrittura atomica checkpoint JSON`.

### 1.5 Gestione Redirect Hugging Face e Sicurezza
- Stripping degli header sensibili (`Authorization`) su redirect Cross-Origin (`host` differente).
- Divieto di downgrade non sicuro da HTTPS a HTTP (lancia `DownloadFailureReason.insecureRedirect`).
- Limite massimo di 5 redirect consecutivi.

### 1.6 Concorrenza e Locking per Destinazione
- Controller di concorrenza `DownloadConcurrencyController` con throttling globale ed acquisizione di lock esclusivo sulla destinazione per `operationId` rilasciato in blocco `finally`.

---

## 2. Architettura dei Test & Isolamento

### 2.1 Suite Unitari Standard (Veloce / CI)
- **File:** `test/provisioning/infrastructure/artifact_download_engine_test.dart`
- **Caratteristiche:** Test deterministici isolati che utilizzano `MockClient` in-memory. Esecuzione completata in < 3 secondi.

### 2.2 Suite di Rete On-Demand (Heavy Remote Models)
- **File:** `test/provisioning/download_engine_network_on_demand_test.dart`
- **Tag:** `@Tags(['network', 'on-demand'])`
- **Timeout:** `@Timeout(Duration(minutes: 10))`
- **Attivazione:** Condizionata alla variabile d'ambiente `$env:AURA_RUN_NETWORK_TESTS="1"`.
- **Artefatto Testato:** Download reale da Hugging Face del modello di test ufficiale `qwen2.5-0.5b-instruct-download-test-q4_0` (398 MB).

---

## 3. Esito Verifiche

| Verificatore | Risultato | Dettagli |
| :--- | :--- | :--- |
| **`dart format`** | **PASS** | 100% aderenza ai criteri di formattazione Dart canonici. |
| **`dart analyze`** | **PASS** | 0 errori, 0 avvisi, 0 info (Zero Diagnostic Policy). |
| **`flutter analyze`** | **PASS** | 0 errori, 0 avvisi, 0 info. |
| **`dart test`** | **PASS** | 585 test unitari superati con successo in ~2 secondi. |
| **On-Demand Network Test** | **PASS** | Download reale completato (398 MB da Hugging Face, ETag forte ed atomicità verified). |
