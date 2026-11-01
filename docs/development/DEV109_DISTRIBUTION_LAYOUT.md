# dev109 framework and separate tutorials

The authoritative framework source snapshot is the committed `integrated-next`
tree. The reviewed `validation/dev109_release/freeze.py` stages only tracked
files after checking the commit-bound functional gate, complete SHA256SUMS and
file modes. It then creates and reads back every member of one framework archive.
Protected untracked development helpers remain outside the artifact. Distributed
native libraries, provider configuration, technical manuals and their required
inline illustrations remain tracked resources. Installed Viewers execute those
distributed binaries.

The current independently verified, separate tutorial candidates are:

| Tutorial | Accepted candidate under `/srv/gxtxt/releases/dev109/candidates/tutorials/` | SHA-256 |
| --- | --- | --- |
| 3D Workbench | `GXTXT_3D_WORKBENCH_HTML_GUIDES_FINAL04.zip` | `1a1c50d3ccd18b8bc7646a7c1a5044d8e395702d90e08abfd75f9a0fed0c1798` |
| Electromagnetics Studio | `GXTXT_ELECTROMAGNETICS_STUDIO_HTML_GUIDES_R6.zip` | `f7f7844ccc121bd2f0499aacb09af67349cb45169bdeef5c39aa7ed9c4010d32` |

Their functional, scientific and editorial acceptance is recorded separately in
`/srv/gxtxt/checkpoints/dev109/main_cad_functional394/FUNCTIONAL44_ACCEPTANCE.json`
and `/srv/gxtxt/checkpoints/dev109/main_em_functional397/FUNCTIONAL_ACCEPTANCE.json`.
Final official deposition and overall release acceptance remain pending. Neither
guide belongs inside the framework archive. Electromagnetics examples describe
the tested linear planar static 2D service; they do not establish full 3D FEM,
CFD or nonlinear solver support.

The earlier standalone source remains preserved on `docs/guides118`, commit
`06e31579244d064e3532a27ad1c8cd194130b2d2`, and at
`/srv/gxtxt/examples/dev109/candidate_guides118/`. Those historical candidates
must not replace the current FINAL04/R6 selection during final deposition.

The historical local `docs/dev109_tutorials69/` copy is retained byte-for-byte
on disk and ignored by the principal branch. Its removal from the principal Git
index does not delete the files or rewrite any historical commit. The author
branch and external sites preserve the illustrated material independently.
Integrated module `MANUAL.md` files and the existing Documentation Browser stay
in the framework; an entire standalone screenshot set or tutorial ZIP does not.

Any later filesystem-based release staging must explicitly exclude that local
standalone subtree and the separately downloadable tutorial ZIPs, including when
carrying forward local installation extras. Do not run historical release scripts
that recursively copy all checkout files unchanged. Final source, framework and
module archive member lists must independently verify the separation; source
index checks alone do not accept those final artifacts.

This boundary does not accept dev109, the CAD/EM functional workstreams or their
final tutorials, and does not modify the active dev108 release, scientific
Sessions, existing archives or rollback material.
