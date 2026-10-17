# Third-party licenses, data sources and acknowledgments

**GX-TXT framework:** GNU GPL-3.0-or-later, see [LICENSE](LICENSE). This license does not supersede the license of an independently licensed dataset, library, font or third-party asset.

## Native and scientific dependencies

GX-TXT uses external runtimes such as Tcl/Tk, GNU Octave, Python and optional NumPy/SciPy, HDF5, VTK, Open CASCADE Technology, OpenSSL and FFmpeg. These dependencies are not relicensed as GX-TXT sources. Obtain them under their respective upstream and platform distribution terms.

The Native 3D Viewer has a detailed [third-party license inventory](plugins/modules/viewer.native_3d/THIRD_PARTY_NOTICES.md), including the VTK, OCCT/LGPL exception, OpenSSL and platform runtime notices in its `licenses/` directory. The libjpeg-turbo 3.2.0 license directory carries both `LICENSE.md` and the exact upstream `README.ijg`. As the IJG license requires for executable-only distributions, the following acknowledgment is provided:

> This software is based in part on the work of the Independent JPEG Group.

Precompiled native `.so`, `.oct` and host/worker files are platform-specific artifacts. Their included source/build files and external ABI requirements must be reviewed together when creating binary redistributions. A source checkout alone does not substitute for mandatory component notices or the corresponding source required by applicable copyleft terms.

## Redistributable teaching and reference material

The following are *data-asset* licenses or provenance statements, not replacements for the GX-TXT code license. Follow each cited generator's own `RIGHTS.md`, data references, hashes and upstream attribution when reusing those files.

| Bundle / source | Provenance and terms |
| --- | --- |
| Manchester UV/Vis training data | James Bird (2022), University of Manchester Figshare, DOI [10.48420/21354474.v1](https://doi.org/10.48420/21354474.v1), CC BY 4.0 |
| NIST PNNL/IARPA IR reference records | Individual NIST Chemistry WebBook records C64175/29, C67561/28 and C67630/29 identified as public domain in the bundled provenance |
| RefIMP TUM FTIR training/test | RefIMP 2022, CC BY-SA 4.0; preserve attribution and share-alike terms for applicable adaptations |
| Cambridge Apollo NMR references | University of Cambridge Apollo, DOI [10.17863/CAM.130157](https://doi.org/10.17863/CAM.130157), CC BY 4.0; 24 processed 1H/13C references in the optional NMR library |
| *Occhi sul Molo* WAV | Original recording owned by Giux-Lab; its owner authorizes public redistribution within GX-TXT, while retaining separate copyright. See the generator's [rights notice](session_generator_libraries/gxtxt.accepted_generators/generators/occhi_sul_molo_audio_chain/RIGHTS.md) |
| Ticino Valley geographic example | Derived from Copernicus DEM GLO-30, ISTAT 2021, CORINE Land Cover 2018 and Regione Lombardia hydrography, with source-specific conditions below |
| Synthetic environmental and numeric examples | Follow the generators' SPDX/README statements; generated synthetic values are not laboratory observations |

### Copernicus DEM GLO-30

For the adapted elevation layer in the Ticino example, carry the mandatory attribution:

> produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved.

The following liability notice must accompany public distribution and downstream redistribution:

> The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30.

These provisions are in the [Copernicus DEM license](https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM). They do not grant endorsement by Copernicus or the data provider. The geographic example's [source manifest and credits](session_generator_libraries/gxtxt.accepted_generators/generators/ticino_valley_3d/template/reference/SOURCES.md) also identify ISTAT population/locality data (CC BY 4.0), the official Copernicus CORINE source and Lombardia hydrography (CC BY 4.0).

## Material not included in the public source distribution

The private document-extraction test generator includes two PDFs without public redistribution permission and is excluded. The author's *Occhi sul Molo* WAV and independent generator are permitted in this public source distribution. The scientific software modules and their public APIs remain part of the framework.

## Native solver source and Debian notices

The scientific fitting runtime includes a native Ceres Solver 2.2.0 adapter using
Eigen 3.4.0. Their upstream licenses remain distinct from the GPL-licensed
GX-TXT adapter. The redistributable source archives are provided under
`third_party/source/` together with SHA-256 hashes. Ceres carries
BSD-3-Clause and bundled component notices; Eigen includes MPL-2.0 and
BSD-3-Clause material. This section does not relicense these sources.

See the [native solver license matrix](docs/legal/THIRD_PARTY_LICENSE_MATRIX_dev097.md),
[Debian rebuild instructions](docs/legal/DEBIAN_NATIVE_REBUILD_dev097.md),
[solver source bill of materials](docs/legal/NATIVE_SOLVER_SOURCE_SBOM_dev097.json),
and [Debian runtime notices](docs/legal/debian-runtime-notices/).

## Redistribution guidance

- Preserve per-file SPDX statements, copyright notices, notice directories, licenses and source attribution.
- When bundling binaries or third-party scientific data, audit the *actual package contents*, not only the directory names.
- A new generator may use public-domain, adequately attributed open-licensed or original synthetic fixtures, but cannot assume a research paper, photograph, recording or external measurement is redistributable.
- Do not place credentials, user Sessions, unconsented scientific files or licensing evidence for private-only sources into public Git history.

This notice is a source-distribution index; it does not assert that every separately packaged third-party binary or independently supplied scientific dataset is licensed under GPL.
