# IR Library Type Provider API v1

SPDX-License-Identifier: GPL-3.0-or-later

Provider module: `library.spectroscopy.ir.reference`.
Library type: `spectroscopy.ir.reference`.

The provider is discovered by Scientific Library Manager API v1 through the
normal installed module descriptor. Its Python provider entrypoint validates
GX-TXT Scientific Reference Library v1 data as IR spectra, including stable
spectrum IDs, valid source integrity, wavenumber or wavelength coordinates,
nonempty response representation and at least eight samples per spectrum.
The data package remains independent of this executable provider plugin.

The public Tcl API exposes `apiInfo`, `listLibraries`, `listEntries` and
`readSpectrum`. All accept logical IDs; consumers receive no managed storage
paths. The generic manager owns install, update, remove and verify.

| Exact signature in `::GX::IRLibraryTypeProviderAPIv1` | Result |
|---|---|
| `apiInfo` | Dictionary with `api_name`, `api_version`, `provider_id` and `library_type`. |
| `listLibraries` | List of compatible logical library ID strings, rather than library records. |
| `listEntries libraryId` | Ordered list of stable entry ID strings, rather than entry records. |
| `readSpectrum libraryId spectrumId` | Manager spectrum dictionary containing the actual arrays, metadata and provenance. |

Discovery uses the Manager's installed registry modes. A listed library does
not prove that remote access or another external runtime is currently available.
