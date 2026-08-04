# A.U.R.A. — Branding Asset Specification

**Documento:** `docs/phase6/BRANDING_ASSET_SPEC.md`  
**Fase di origine:** 6.6 — Windows Desktop Shell, Branding & Window Modes  
**Tipo:** specifica as-built e contratto di release  
**Stato:** implementato; documento ricostruito dalla baseline applicativa  
**Baseline iniziale:** `1c9015da6c5f445c13e82fa5df0c4d49e0830429`  
**Target iniziale:** Windows x64

---

## 1. Scopo

Questa specifica definisce le fonti, i derivati, i metadati e i controlli di coerenza del branding A.U.R.A.

Il branding non è un dettaglio grafico isolato: fa parte dell'identità del prodotto e deve essere coerente fra:

- finestra nativa;
- Flutter `MaterialApp`;
- taskbar;
- executable Windows;
- proprietà versione del file;
- installer;
- collegamenti;
- portable package;
- GitHub Release;
- futura applicazione Android.

La Fase 6.6 ha già introdotto il branding Windows. Questo documento ne formalizza il comportamento effettivo e stabilisce i gate che la Fase 6.9 deve applicare.

---

## 2. Nome canonico del prodotto

### 2.1 Nome breve

```text
A.U.R.A.
```

### 2.2 Nome esteso

Per i file nativi Windows viene usata una stringa ASCII:

```text
A.U.R.A. - Artificial Unbound Reasoning Arena
```

L'uso del trattino ASCII è intenzionale. Nei file C++, RC e nelle stringhe native non devono essere introdotti em dash o caratteri multibyte che possano produrre artefatti di code page.

### 2.3 Titolo finestra

Il titolo nativo e Flutter devono essere coerenti:

```text
A.U.R.A. - Artificial Unbound Reasoning Arena
```

Punti di integrazione attuali:

```text
app/windows/runner/main.cpp
app/lib/main.dart
```

---

## 3. Inventario degli asset

### 3.1 Asset runtime Windows autorevole

```text
app/windows/runner/resources/app_icon.ico
```

Questo file è referenziato da:

```text
app/windows/runner/Runner.rc
```

tramite:

```rc
IDI_APP_ICON ICON "resources\\app_icon.ico"
```

L'ICO è quindi l'asset effettivamente compilato nell'executable Windows.

### 3.2 Master sorgente

Il progetto deve mantenere una sorgente master ad alta risoluzione e non distruttiva.

Percorsi raccomandati:

```text
design/branding/aura_app_icon.svg
design/branding/aura_app_icon_1024.png
```

Alla baseline indicata l'asset ICO Windows è confermato, mentre il percorso di un master SVG/PNG canonico deve essere verificato nel repository e, se assente, introdotto senza modificare arbitrariamente il design già approvato.

Regola:

```text
master sorgente
→ generazione derivati
→ review visiva
→ commit atomico di master e derivati
```

L'ICO non deve diventare l'unica sorgente del logo.

### 3.3 Derivati futuri

Il master dovrà alimentare:

```text
Windows ICO multi-size
installer icon
uninstaller icon
shortcut icon
Android launcher icons
Android adaptive foreground/background
eventuali immagini README e release
```

I derivati non devono divergere graficamente dal master salvo adattamenti obbligatori di piattaforma.

---

## 4. Requisiti dell'ICO Windows

L'ICO deve:

- essere un vero container ICO;
- contenere più dimensioni;
- includere trasparenza corretta;
- rimanere leggibile su tema chiaro e scuro;
- non dipendere da file esterni a runtime;
- essere incluso nell'executable;
- essere riusato dall'installer e dai collegamenti quando tecnicamente possibile.

Dimensioni raccomandate:

```text
16x16
24x24
32x32
48x48
64x64
128x128
256x256
```

Il 256x256 può essere memorizzato come PNG interno al container ICO.

La pipeline deve almeno verificare:

- esistenza del file;
- dimensione non nulla;
- firma/formato ICO;
- presenza di più image entry;
- riferimento corretto in `Runner.rc`.

Una verifica visiva resta obbligatoria per la release candidate.

---

## 5. Metadati Windows

La baseline `Runner.rc` definisce:

```text
CompanyName      = naturewhisp
FileDescription  = A.U.R.A. - Artificial Unbound Reasoning Arena
InternalName     = AURA
OriginalFilename = aura_app.exe
ProductName      = A.U.R.A. - Artificial Unbound Reasoning Arena
LegalCopyright   = Copyright (C) 2026 naturewhisp. All rights reserved.
```

Versione file e prodotto derivano dalle variabili Flutter:

```text
FLUTTER_VERSION_MAJOR
FLUTTER_VERSION_MINOR
FLUTTER_VERSION_PATCH
FLUTTER_VERSION_BUILD
FLUTTER_VERSION
```

### 5.1 Coerenza richiesta

Per ogni release devono coincidere:

```text
versione workflow
versione Flutter
FileVersion
ProductVersion
installer version
release manifest
tag Git
nome GitHub Release
```

### 5.2 Nome fisico executable

La baseline usa:

```text
aura_app.exe
```

Il prodotto logico è A.U.R.A., ma il nome fisico può restare `aura_app.exe` finché non viene eseguita una migrazione atomica di:

- build Flutter;
- installer;
- manifest;
- shortcut;
- test;
- script di packaging;
- upgrade da installazioni precedenti.

Non rinominare unicamente il file finale nel packaging senza aggiornare tutti i riferimenti.

---

## 6. Installer

L'installer Inno Setup deve:

- usare l'icona A.U.R.A.;
- usare il nome prodotto canonico;
- mostrare la versione corretta;
- generare collegamenti con icona corretta;
- mantenere un `AppId` stabile;
- non usare icone predefinite Inno per gli artifact ufficiali;
- non introdurre un secondo file grafico non derivato dal master.

Punto di integrazione:

```text
tool/aura_installer.iss
```

La Fase 6.9 deve verificare che l'installer compilato:

- sia PE valido;
- contenga la versione richiesta;
- mostri nome e icona corretti;
- generi shortcut coerenti.

---

## 7. Portable package

Il pacchetto portable deve contenere l'executable già brandizzato.

Non è necessario distribuire separatamente l'ICO se è incorporato nell'executable, salvo che serva a funzioni runtime documentate.

Il portable non deve:

- sostituire l'icona con quella Flutter di default;
- contenere branding di sviluppo;
- contenere stringhe `aura_app` visibili all'utente, salvo il nome fisico interno deliberatamente mantenuto;
- contenere asset master di design non necessari all'esecuzione.

---

## 8. MaterialApp e shell desktop

Il titolo Flutter deve coincidere con il titolo nativo:

```dart
title: 'A.U.R.A. - Artificial Unbound Reasoning Arena'
```

Il branding deve sopravvivere alle modalità:

```text
windowed
maximized
borderlessFullscreen
restorePrevious
```

Le transizioni di modalità non devono causare:

- reset del titolo;
- icona generica;
- duplicazione di finestre taskbar;
- perdita del branding dopo restore.

---

## 9. Accessibilità e leggibilità

L'icona deve essere comprensibile:

- a 16x16;
- con scaling 100%, 125%, 150%, 200%;
- su taskbar chiara e scura;
- su sfondi trasparenti;
- in High Contrast, per quanto consentito dal sistema.

Il logo non deve essere l'unico mezzo per comunicare il nome del prodotto.

Nome e descrizione testuale restano obbligatori nelle proprietà del file e nell'installer.

---

## 10. Rigenerazione derivati

La rigenerazione deve essere esplicita e ripetibile.

Struttura raccomandata:

```text
tool/generate_branding_assets.ps1
```

oppure tool equivalente versionato.

Input:

```text
master SVG/PNG
```

Output:

```text
app/windows/runner/resources/app_icon.ico
future Android mipmap assets
eventuali immagini documentali
```

Il tool deve:

- non leggere asset da cartelle utente;
- non scaricare implicitamente immagini;
- fallire se il master manca;
- produrre output deterministici per gli stessi input e tool;
- registrare versione del tool;
- non modificare il design tramite ottimizzazioni lossy non approvate.

Finché il tool non esiste, la modifica manuale dell'ICO deve essere trattata come operazione sensibile e accompagnata da confronto visivo.

---

## 11. GitHub Actions e release gate

La Fase 6.9 deve verificare:

```text
- app_icon.ico esiste;
- Runner.rc lo referenzia;
- titolo nativo corretto;
- titolo Flutter corretto;
- CompanyName corretto;
- ProductName corretto;
- FileDescription corretta;
- InternalName corretto;
- versione coerente;
- installer usa icona e nome corretti;
- executable portable conserva il branding;
```

Per una release `stable`, un mismatch deve essere fail-closed.

---

## 12. Test richiesti

### 12.1 Automatici

- parsing delle stringhe principali in `Runner.rc`;
- verifica del riferimento all'ICO;
- verifica titolo in `main.cpp`;
- verifica titolo Flutter;
- verifica coerenza versione;
- verifica presenza e formato ICO;
- verifica configurazione Inno Setup;
- verifica che il package non torni a icone Flutter predefinite.

### 12.2 Manuali

- icona in Esplora file;
- icona taskbar;
- icona finestra;
- icona Alt+Tab;
- icona installer;
- icona collegamento desktop;
- icona menu Start;
- proprietà versione dell'EXE;
- proprietà versione del setup;
- DPI differenti;
- modalità fullscreen e restore.

---

## 13. Compatibilità futura Android

La sorgente master deve permettere la generazione di:

```text
mipmap-mdpi
mipmap-hdpi
mipmap-xhdpi
mipmap-xxhdpi
mipmap-xxxhdpi
adaptive icon foreground
adaptive icon background
monochrome icon, se supportata
```

La futura implementazione Android deve riusare lo stesso linguaggio visivo, senza copiare l'ICO Windows come sorgente raster.

---

## 14. Change control

Una modifica del branding ufficiale richiede:

1. aggiornamento master;
2. rigenerazione derivati;
3. aggiornamento checksum, se applicabili;
4. review visiva;
5. aggiornamento test;
6. commit atomico;
7. nota nelle release notes se visibile agli utenti.

Non modificare solo un derivato.

---

## 15. Criteri di accettazione

La specifica è rispettata quando:

```text
- esiste un'identità visiva unica;
- l'ICO Windows è incorporato nell'executable;
- finestra e MaterialApp usano il nome canonico;
- i metadati Windows sono coerenti;
- installer e shortcut usano il branding ufficiale;
- la versione è sincronizzata;
- il portable conserva il branding;
- la pipeline rileva regressioni;
- il master sorgente è identificato e versionato;
- la futura generazione Android è supportabile senza ridisegno.
```

---

## 16. Stato as-built iniziale

Confermato alla baseline:

```text
- app/windows/runner/resources/app_icon.ico presente;
- Runner.rc referenzia l'ICO;
- main.cpp usa il titolo canonico ASCII;
- MaterialApp usa il titolo canonico ASCII;
- Runner.rc contiene CompanyName, ProductName, FileDescription e InternalName;
- la versione Windows deriva dalla versione Flutter.
```

Da verificare o completare durante la Fase 6.9:

```text
- presenza di un master SVG/PNG canonico;
- generatore ripetibile dei derivati;
- verifica automatica multi-entry dell'ICO;
- verifica automatica del branding dell'installer;
- documentazione del cambio futuro del nome fisico executable.
```
