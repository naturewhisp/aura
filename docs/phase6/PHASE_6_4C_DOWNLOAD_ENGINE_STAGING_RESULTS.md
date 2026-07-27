# Documentazione ed Evidenza — Tranche 6.4c (Download Engine, HTTP Range Resume & Staging)

Questo documento registra l'evidenza tecnica e l'esito dei test per la **Tranche 6.4c** del motore di provisioning di A.U.R.A.

---

## 1. Obiettivi e Vincoli Contrattuali Implementati

### 1.1 Strong ETag Resume Policy con `If-Range`
- L'header `Range: bytes=<offset>-` viene inviato esclusivamente accompagnato dall'header `If-Range: "<strong-etag>"`.
- Il resume è consentito **unicamente se** il checkpoint contiene un **ETag forte** (delimitato da virgolette `^"[^"]+"$` e non prefissato da `W/` o `w/`). Se l'ETag nel checkpoint è debole (`W/"..."`), nullo o malformato, `If-Range` non viene inviato, il checkpoint viene resettato ed il download riparte dal byte 0.

### 1.2 Validazione Stringente della Risposta HTTP `206 Partial Content`
Una risposta `206` viene accepted per il resume **esclusivamente se**:
- Status è `206 Partial Content`;
- L'ETag restituito è un ETag forte **obbligatorio** e corrispondente a `checkpoint.strongEtag` (`responseStrongEtag != null && responseStrongEtag == activeCheckpoint.strongEtag`);
- `Content-Range` rispetta `bytes <start>-<end>/<total>`;
- `Content-Range.start == downloadedBytes`;
- `Content-Range.total == expectedSizeBytes` (il totale `*` viene tassativamente rifiutato);
- `Content-Length == (end - start + 1)` (quando presente).

In caso di mancata corrispondenza, la risposta `206` viene rifiutata, il file `.part` viene troncato a 0 byte ed il download riparte dal byte 0 via GET incondizionata.

### 1.3 Prevenzione della Ricorsione Indefinita nei Fallback
- Dopo un `206` non valido o un `416` non riconciliabile, il motore attiva il tentativo di fallback `_executeUnconditionalGet` impostando il flag interno `allowFallbackRestart: false`.
- Se anche il tentativo di fallback riceve una risposta semanticamente non valida o un secondo 206/416 non accettabile, il motore interrompe la ricorsione restituendo immediatamente `DownloadResult.failure(reason: DownloadFailureReason.httpStatusError, isRetryable: false)`.

### 1.4 Applicazione Effettiva del Timeout di Richiesta ed Inattività
- Il parametro `DownloadRequest.timeout` viene applicato sia al tempo di connessione/header HTTP (`_httpClient.send(httpRequest).timeout(...)`) sia all'inattività dello stream di byte (`response.stream.timeout(...)`).
- In caso di superamento del timeout, viene emesso `DownloadResult.failure(reason: DownloadFailureReason.networkTimeout, isRetryable: true)`.

### 1.5 Gestione dei Redirect Cross-Origin e Sicurezza
- Su redirect HTTP, lo stato degli header inoltrati viene mantenuto in una mappa mutabile locale (`forwardedHeaders`), prevenendo eccezioni di tipo `UnsupportedError` su mappe unmodifiable.
- Il confronto Cross-Origin valuta la tripla `scheme + host + port`. Se l'origine cambia, l'header `Authorization` viene rimosso prima del nuovo invio.
- Divieto assoluto di downgrade non sicuro da HTTPS a HTTP (lancia `DownloadFailureReason.insecureRedirect`).

### 1.6 Concorrenza e Locking per Destinazione
- Controller di concorrenza `DownloadConcurrencyController` con throttling globale ed acquisizione di lock esclusivo sulla destinazione per `operationId` rilasciato in blocco `finally`.

---

## 2. Architettura dei Test & Isolamento

### 2.1 Suite Unitari Standard (Veloce / CI)
- **File:** `test/provisioning/infrastructure/artifact_download_engine_test.dart`
- **Caratteristiche:** Test deterministici isolati che utilizzano `MockClient` in-memory. 590 test unitari superati in < 3 secondi.

### 2.2 Suite di Rete On-Demand (Heavy Remote Models)
- **File:** `test/provisioning/download_engine_network_on_demand_test.dart`
- **Tag:** `@Tags(['network', 'on-demand'])`
- **Timeout:** `@Timeout.none`
- **Attivazione:** Condizionata alla variabile d'ambiente `$env:AURA_RUN_NETWORK_TESTS="1"`.
- **Artefatto Testato:** Download reale da Hugging Face del modello di test ufficiale `qwen2.5-0.5b-instruct-download-test-q4_0` (398 MB).

---

## 3. Esito Verifiche

| Verificatore | Risultato | Dettagli |
| :--- | :--- | :--- |
| **`dart format`** | **PASS** | 100% aderenza ai criteri di formattazione Dart canonici. |
| **`dart analyze`** | **PASS** | 0 errori, 0 avvisi, 0 info (Zero Diagnostic Policy). |
| **`flutter analyze`** | **PASS** | 0 errori, 0 avvisi, 0 info. |
| **`dart test`** | **PASS** | 590 test unitari superati con successo in ~2 secondi. |
| **On-Demand Network Test** | **PASS** | Download reale completato (398 MB da Hugging Face, ETag forte ed atomicità verified). |
