# Third-party license matrix — dev097 native solver build

This is the Debian dev097 source/build and native dependency audit. All twelve
candidate ELF files resolve their dependencies: 126 system libraries from 58
Debian packages. Exact hashes, versions and notices are documented in the adjacent binary
SBOM, alongside the corresponding upstream attribution.

| Component | Exact version | License and source | Build/inclusion |
|---|---|---|---|
| Ceres Solver | 2.2.0 | BSD-3-Clause; included Apache-2.0 portions; complete upstream license supplied | Unmodified static PIC library; C++17. Built-in miniglog retains its BSD notice. Exact source archive included. |
| Eigen | 3.4.0 | MPL-2.0 and BSD-3-Clause; unmodified upstream source archive distributed by Debian | Headers compiled with `EIGEN_MPL2_ONLY`; non-MPL2 headers fail compilation. |
| SuiteSparse, METIS, CUDA, external glog, gflags | Excluded from this Ceres adapter | No linked/distributed implementation selected by this adapter | Explicit CMake OFF settings and actual adapter link inventory agree. |
| BLAS/LAPACK | Excluded from this Ceres build | Existing Octave operations continue using their configured system libraries | Existing Octave mathematics is retained; this exclusion is not a claim about all Octave dependencies. |
| Abseil | Not used by pinned Ceres 2.2.0 | No dependency in inspected release source/configuration | The mandate's blanket 2.2+ assumption does not describe this concrete release. |
| GNU C++ runtime | Exact version in binary SBOM; GCC 14.2.0-19 build toolchain | GPL-3.0-or-later WITH GCC-exception-3.1 for libstdc++; complete Debian notices supplied | System runtime, no copied runtime binary. |
| glibc | Exact version in binary SBOM | LGPL-2.1-or-later and component notices | System runtime, no copied runtime binary. |
| Octave adapter/runtime | Octave 9.4.0; Debian package 9.4.0-1 | GPL-3.0-or-later plus linked component licenses | Adapter source supplied; repeated build byte-identical. System Octave remains a declared prerequisite. |
| VTK / OCCT / OpenSSL / Tcl-Tk and transitive native dependencies | Actual Debian versions in binary SBOM | Complete installed Debian copyright notices supplied per package | Dynamically linked system prerequisites. No bundled third-party runtime libraries. |

Exact source archives:

- Ceres SHA256 `12efacfadbfdc1bbfa203c236e96f4d3c210bed96994288b3ff0c8e7c6f350d4`.
- Eigen SHA256 `b4c198460eba6f28d34894e3a5710998818515104d6e74e5cc331ce31e46e626`.

The adjacent source SBOM records URLs, hashes, exclusions and the remaining
installed-artifact gate. `native_solver_notices/` retains complete upstream
notices. `third_party/source/` supplies both exact source archives; GX-TXT adapter
and native sources and build files accompany the binaries. See
[Debian rebuild instructions](DEBIAN_NATIVE_REBUILD_dev097.md). MPL-covered
source and replacement/relink builds remain available. No proprietary solver
or opaque vendor binary is selected. Historical build receipts retain their
original prototype labels; they are not final release acceptance claims.
