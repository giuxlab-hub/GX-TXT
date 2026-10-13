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
