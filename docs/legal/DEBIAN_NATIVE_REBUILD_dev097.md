# Debian native sources and replacement builds — dev097

The release contains GX-TXT source and build files, the exact unmodified Ceres
2.2.0 and Eigen 3.4.0 source archives under `third_party/source/`, and their full
notices in `docs/legal/native_solver_notices/`. The adapter and GX-TXT native
sources are GPL-3.0-or-later; component notices retain their upstream terms.
There is no activation key or signature restriction on replacement builds.

Build from the extracted framework root, using a new directory outside that
tree. Debian development prerequisites include Python 3, CMake, a C++17 compiler,
GNU Octave development headers and `mkoctfile`. The verified adapter toolchain is
Octave 9.4.0 and Debian GCC 14.2.0-19 on x86-64.

```sh
python3 validation/integrated_dev097/native_dependencies.py third_party/source /tmp/gxtxt097-dependencies --parallel 4
python3 validation/integrated_dev097/native_adapter_build.py . /tmp/gxtxt097-dependencies /tmp/gxtxt097-adapter
```

These scripts refuse an existing output directory, verify both source archive
SHA256 values before extraction, and retain every command and build log. Their
historical `PROTOTYPE_BUILD_PASS_NOT_RELEASE_APPROVED` receipt label describes
build success only; it grants no release acceptance. The recipe uses static PIC
Ceres, C++17, built-in miniglog and `EIGEN_MPL2_ONLY`; external glog, gflags,
SuiteSparse, METIS, CUDA and Ceres LAPACK are disabled. Eigen sources are
unmodified. Ceres examples, tests and benchmarks are not compiled into the
adapter. Source archives retain their own complete source and notices.

After closing running GX-TXT/Octave processes, replace only the rebuilt adapter
in a **copy of the extracted release**:
`plugins/modules/math.numeric/api/octave/gxtxt_numeric_ceres_native.oct`.
The current source SHA256 is
`e795b7d9b3a012afb39c6c6e9c5aeb5a4646c798f6808181bbda4fe8a4a4dc40`.
A repeat build against the verified dependency prefix produced the exact shipped
binary SHA256
`713da7d0de29e67e39e551fba23ed6961db6046546b67fe73b7bb739881e77b2`.
This is adapter reproducibility evidence, not a claim that every native component
or every different compiler build is byte-identical.

The two other Numeric Octave extensions use their adjacent `.cc` source:

```sh
mkoctfile -std=c++17 -O3 plugins/modules/math.numeric/api/octave/gxtxt_numeric_smoothing_native.cc -o /tmp/gxtxt_numeric_smoothing_native.oct
mkoctfile -std=c++17 -O3 plugins/modules/math.numeric/api/octave/gxtxt_numeric_cubic_project_native.cc -o /tmp/gxtxt_numeric_cubic_project_native.oct
```

Native2D and CORE Parameters have CMake projects under `core/native2d` and
`core/parameters`. CORE Native3D has its complete source and CMake project under
`core/native3d`, including the shared public Numeric reduction header in
`plugins/modules/math.numeric/api/c/`. Its Debian build uses VTK 9.3, OpenSSL 3
and OCCT 7.8 with `GX3DE_WITH_OCCT=ON`. Tcl/Tk and the Debian development packages
for those dependencies are required. Preserve the existing CMake install RPATHs.
The legacy viewer has its own complete project under
`plugins/modules/viewer.native_3d/native`; use **CMake install output** so its
host resolves `libgx3d.so` from `$ORIGIN/../lib`. A build-tree executable is not a
portable package artifact. Its scientific cache format and public identities
are unchanged by the dev097 RPATH correction.

`DEBIAN_NATIVE_BINARY_SBOM_dev097.json` records every packaged ELF file and its
actual resolved Debian dependency packages, source package versions and copied
copyright notices. These Debian libraries are system prerequisites; they are
not copied into this framework archive. The system package manager retains their
own corresponding-source and notice records. A distributor who bundles any of
those system libraries must also provide its applicable corresponding source and
notices. Dynamic linking remains available for replacing those libraries.
For the release itself, the Ceres/Eigen archives and GX-TXT sources are supplied
directly; source URLs are supplemental provenance.

The installed release gate must recheck the exact ELF hashes and resolve its
libraries from the installed tree or declared system packages. Development
source/build evidence alone does not certify a future installed binary.
