# IR Reference Library Type Provider

SPDX-License-Identifier: GPL-3.0-or-later

This independently installable GX-TXT module registers the
`spectroscopy.ir.reference` Scientific Library type. CORE owns package
integrity, managed storage, the registry and install/update/remove lifecycle.
This provider validates IR spectral meaning, checks stable spectrum IDs, and
exposes reference spectra. It contains no bundled library data.

Install the provider through Plugin Install API v1. Install compatible data
packages separately through Scientific Library Manager API v1 or the
Scientific Spectral Library Viewer **Install library...** action.
