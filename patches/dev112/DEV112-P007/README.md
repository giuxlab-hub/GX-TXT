# GX-TXT DEV112-r2 P007 — Script Library, Script Jobs and Dataset Preview Usability

## Italiano

**Usabilità Script Library, Script Jobs e Dataset Preview**

Aggiornamento cumulativo con migliorie di reattività per Script Library e Dataset Preview e correzioni della chiusura di Script Jobs.

### Funzionalità

- Script Library: selezione e consultazione più efficienti senza ricostruire continuamente il Registry.
- Script Jobs: persistenza sicura della larghezza delle colonne alla chiusura.
- Dataset Preview: gestione asincrona delle operazioni di presentazione, cache verificate e salvataggio dello stato.
- Aggiorna il componente Curve Digitalizer già incluso nel framework, senza installazione separata.

### Installazione

**Prerequisito:** DEV112-r2 originale, stato esatto post-P005 oppure post-P006-r5.

La P007 è cumulativa: si può applicare direttamente alla DEV112-r2 originale. Eseguire il controllo prima dell'installazione e conservare ricevuta e SHA-256 per il rollback.

L'archivio originale `DEV112-P007.zip` ha SHA-256 `db4b7457edebc3a01bae244e1bc01db7a785d7348b9d808fb000b7a2d20131b3`. L'installazione utilizza lo script `apply.py` e le istruzioni contenute nel pacchetto. Arrestare GX-TXT prima di qualsiasi aggiornamento.

[Sorgenti, manifesti e pacchetti](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev112/patches/dev112/DEV112-P007)

## English

**Script Library, Script Jobs and Dataset Preview Usability**

Cumulative update improving Script Library and Dataset Preview responsiveness and correcting Script Jobs window closure.

### Features

- Script Library: faster selection and inspection without repeatedly rebuilding the Registry.
- Script Jobs: safe persistence of column widths during window closure.
- Dataset Preview: asynchronous presentation work, verified caches and saved-view handling.
- Updates the Curve Digitalizer companion already bundled with the framework, without separate installation.

### Installation

**Required baseline:** Original DEV112-r2, exact post-P005 or post-P006-r5 state.

P007 is cumulative and can be applied directly to the original DEV112-r2. Run the preflight before installation and retain the receipt and SHA-256 for rollback.

The original `DEV112-P007.zip` SHA-256 is `db4b7457edebc3a01bae244e1bc01db7a785d7348b9d808fb000b7a2d20131b3`. Use the supplied `apply.py` and package installation instructions. Stop GX-TXT before any authorized update.

[Source, manifests and packages](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev112/patches/dev112/DEV112-P007)

### Original distribution files

| Filename | SHA-256 |
| --- | --- |
| `DEV112-P007.zip` | `db4b7457edebc3a01bae244e1bc01db7a785d7348b9d808fb000b7a2d20131b3` |
| `DEV112-P007-delivery.zip` | `1a74610834b2a830b97d5b88d7afa2568e36045408b1372b99abf87c32d8d854` |
| `apply.py` | `7caf5a50d80f9aa9d5dad2e2f663ef46e5bbe65af2b7ca5ff1c898344c5c3946` |
