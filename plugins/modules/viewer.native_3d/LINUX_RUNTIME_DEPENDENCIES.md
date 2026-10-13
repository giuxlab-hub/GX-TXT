# Linux Native 3D runtime dependencies

The Linux package contains `bin/gx3d-host`, `bin/gx3d-worker`, and
`lib/libgx3d.so`. The executables use `RUNPATH=$ORIGIN/../lib`; the shared
library uses `RUNPATH=$ORIGIN`. `libgx3d.so` therefore resolves from this
module's own `lib/` directory. No empty RUNPATH element or build directory is
part of the installed binaries.

VTK 9.3, OCCT 7.8, OpenSSL 3 and their recursive system dependencies are
provided by the supported Debian Linux installation. They are intentionally
not copied into the plugin. The runtime needs the corresponding Debian
`libvtk9.3`, OCCT 7.8 data-exchange/runtime, OpenSSL 3 and OpenGL/X11 stacks.
The package is relocatable within a compatible Linux environment; changing
the host ABI or removing system VTK/OCCT requires a new compatibility build.

The Linux STEP worker includes an OCCT 7.8.1 assembly-transfer lookup cache
in `native/src/step_transfer_cache.cpp`. Two exported OCCT member functions
are replaced only for this exact header version. They retain the original
translation operations while reusing representation links within one worker
import. The source is compiled on Linux only; other OCCT versions use the
library implementation until their transfer behavior is profiled and checked.
The worker handles one source per process, and its lookup maps are local to
each thread. No extra import threads are launched. Rebuild against the target
OCCT headers and test symbol export, the small and large STEP fixtures, and
byte parity of display geometry before changing the OCCT runtime version.
The output cache algorithm and key remain compatible with version 0.9.0, so
existing valid warm caches continue to reopen without reconstruction.

Rebuild from `native/CMakeLists.txt` with CMake Release mode,
`GX3D_WITH_OCCT=ON`, and a development OCCT sysroot when headers and linker
names are unavailable in the host system packages. Use a fresh out-of-tree
build and a distinct CMake install prefix. Install with `cmake --install`;
copy only the installed `bin/` and `lib/` artifacts into this module. The
development sysroot supplies compile-time headers/linker names only and must
not appear in installed ELF RUNPATH or `ldd`. Update both module checksum
inventories and the root inventory after replacing binaries.

Verification commands:

```sh
readelf -d bin/gx3d-host bin/gx3d-worker lib/libgx3d.so
ldd bin/gx3d-host
ldd bin/gx3d-worker
ldd lib/libgx3d.so
```

Reject any `not found`, source/staging path, empty RUNPATH element, or
unexpected private library resolution. A real Xvfb/GL Native 3D render is
required after ELF checks; ELF metadata alone does not prove renderer startup.
