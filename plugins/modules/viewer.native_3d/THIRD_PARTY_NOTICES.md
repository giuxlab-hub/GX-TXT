# Native 3D Viewer third-party notices

The Native 3D Viewer uses dynamically linked third-party components. GX-TXT
source is GPL-3.0-or-later; these components retain their own licenses.

| Component | Use | License texts supplied with this module |
|---|---|---|
| VTK 9.6.2 | Display, interaction, geometry filters and image capture | `licenses/vtk/Copyright.txt` and the notices for VTK's bundled components under `licenses/vtk/` |
| Open CASCADE Technology 7.9.3 | STEP/B-Rep import, assembly structure and tessellation | `licenses/opencascade/LICENSE_LGPL_21.txt` and `licenses/opencascade/OCCT_LGPL_EXCEPTION.txt` |
| OpenSSL | SHA-256 cache and source integrity checks | `licenses/openssl/LICENSE` |

The core component notices above were first collected from local development
packages. Platform packages must also carry the notices for their exact
distributed runtime binaries. OCCT remains a separately identifiable dynamic
library so users can exercise the applicable LGPL rights.

The isolated Windows development installation has a recursive binary import
report for its MSYS2 UCRT64 build. It stages the exact DLL closure locally,
but some transitive packages in that toolchain did not install license texts.
That MinGW development build is retained only as historical test evidence.

The Windows release candidate is compiled with MSVC 19.44.35229 and the
Windows 10.0.26100 SDK. Its VTK 9.6.2, OCCT 7.9.3 and OpenSSL 3.6.4
development and runtime packages are pinned in the dedicated installation's
`tools/msvc-deps/conda-explicit-win64.txt`. The exact recursively imported
MSVC DLL closure is staged beside the host and worker, and its package notices
are under `licenses/windows-runtime/`. The conda-forge FreeType runtime output
does not contain its own license files; the same-version `freetype` output
supplies the FTL/GPL texts under the runtime package's notice directory. A
recursive import and package-owner audit found no missing DLL or notice gap.
The conda-forge `libexpat` runtime output likewise has no license text; its
MIT `COPYING` notice was taken from the separately installed MSYS2 Expat
2.8.5 package of the same upstream version and is included under the
`libexpat` runtime notice directory.
The FFmpeg command-line tools used by GX-TXT come from the supplied `compito`
binaries and are kept under the separate installation `tools/ffmpeg/` folder.

The tested Linux build uses Debian's VTK 9.3 (`libvtk9.3`), OCCT 7.8
(`libocct-data-exchange-7.8` and its declared dependencies), and OpenSSL 3
(`libssl3t64`). The Linux plugin installer check uses a package without
development-sysroot symlinks and verifies the installed worker with `ldd`
and a real OBJ opening. A release package must declare and verify the exact
runtime ABI requirements on its supported Linux distribution.
