# GX-TXT DEV111-P025-r2 — API Catalog and Scientific Libraries — Revision 2

## Italiano

**DEV111-P025-r2 — Catalogo API e librerie scientifiche — revisione 2**

Revisione della P025 con Catalogo API nativo, servizi per le librerie scientifiche e aggiornamenti al catalogo e alla consultazione delle API Viewer.

### Funzionalità
- Comprende Catalogo API e Scientific Library Manager della P025, con dichiarazioni indicizzate, manuali e provider di librerie.
- Aggiorna catalog.sqlite, il manifesto delle sorgenti e il Viewer Development API Browser rispetto alla prima distribuzione P025.
- Conserva registrazione pubblica delle librerie, provider JSON/IR/NMR e integrazioni con i Builder.
- Il prerequisito è DEV111-P024. Non applicare P025-r2 sopra P025 originale: ripristinare prima la baseline P024 esatta.
- La P026 richiede P025-r2. La P025 originale e la revisione 2 restano entrambe disponibili.

### Distribuzione
**Revisione alternativa:** P025-r2 sostituisce P025 dalla baseline P024; non va applicata sopra la P025 originale. P026 richiede P025-r2.

Framework: `GX-TXT 0.9.8.10-dev-111`. Prerequisito: `DEV111-P024` secondo il README dell'archivio.

Archivio ufficiale: `DEV111-P025-r2.zip` (SHA-256: `6c5de23f2a0440cf2333b3c501dc1939dce281e28ff4f87e6af99c7a94e81dbc`).

La patch contiene i file incrementali e le istruzioni di applicazione/ripristino in `patch_notes/`.

[Codice, archivio e manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P025-r2)

## English

**DEV111-P025-r2 — API Catalog and Scientific Libraries — Revision 2**

Revised P025 package with the native API Catalog, scientific library services and updated catalog and Viewer API browsing.

### Features
- Provides the P025 API Catalog and Scientific Library Manager functionality, with indexed declarations, manuals and library providers.
- Updates catalog.sqlite, its source manifest and the Viewer Development API Browser relative to the original P025 distribution.
- Preserves public library registration, JSON/IR/NMR reference providers and Builder integrations.
- The required predecessor is DEV111-P024. Do not install P025-r2 over the original P025; restore the exact P024 baseline first.
- DEV111-P026 uses P025-r2 as its prerequisite. Both original P025 and revision 2 remain separately available.

### Distribution
**Alternative revision:** P025-r2 replaces P025 from the P024 baseline; it must not be overlaid on original P025. P026 requires P025-r2.

Framework: `GX-TXT 0.9.8.10-dev-111`. Required predecessor: `DEV111-P024`, according to the bundled README.

Original archive: `DEV111-P025-r2.zip` (SHA-256: `6c5de23f2a0440cf2333b3c501dc1939dce281e28ff4f87e6af99c7a94e81dbc`).

The patch includes incremental files and its application/rollback instructions under `patch_notes/`.

[Files, archive and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P025-r2)
