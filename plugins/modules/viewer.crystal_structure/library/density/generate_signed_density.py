#!/usr/bin/env python3
"""Compute a signed RHF density difference on the water reference CUBE grid."""
from pathlib import Path
import hashlib
import json
import numpy as np
import pyscf
from pyscf import gto, scf
from pyscf.dft import numint
from pyscf.tools import cubegen

HERE = Path(__file__).resolve().parent
OUT = HERE / "computed"
REFERENCE = OUT / "water_density.cube"
original = gto.M(atom="O 0.000000 0.000000 0.000000; H 0.758602 0.000000 0.504284; H -0.758602 0.000000 0.504284",
                 unit="Angstrom", basis="sto-3g", charge=0, spin=0, verbose=0)
perturbed = gto.M(atom="O 0.000000 0.000000 0.000000; H 0.818602 0.000000 0.504284; H -0.758602 0.000000 0.504284",
                  unit="Angstrom", basis="sto-3g", charge=0, spin=0, verbose=4,
                  output=str(OUT / "water_perturbed_pyscf.log"))
mf = scf.RHF(perturbed)
mf.conv_tol = 1e-9
mf.kernel()
if not mf.converged:
    raise RuntimeError("Perturbed-water SCF did not converge")

reference_grid = cubegen.Cube(original, nx=48, ny=48, nz=48, margin=3.0)
header = REFERENCE.read_text().splitlines()
source_origin = np.array([float(x) for x in header[2].split()[1:4]])
source_axes = np.array([[float(x) for x in header[3+i].split()[1:4]] for i in range(3)])
expected_axes = np.array([reference_grid.box[i] / 47 for i in range(3)])
if not np.allclose(reference_grid.boxorig, source_origin, atol=1e-5) or not np.allclose(expected_axes, source_axes, atol=1e-5):
    raise RuntimeError("Reference CUBE grid differs from the documented input")
rho_ref = np.fromstring(" ".join(header[9:]).replace("D", "E"), sep=" ").reshape((48,48,48))

grid = cubegen.Cube(perturbed, nx=48, ny=48, nz=48, resolution=None,
                   origin=reference_grid.boxorig,
                   extent=np.diag(reference_grid.box))
coords = grid.get_coords()
rho_new = np.empty(len(coords))
dm = mf.make_rdm1()
for start in range(0,len(coords),8000):
    stop = min(start+8000,len(coords))
    ao = perturbed.eval_gto("GTOval",coords[start:stop])
    rho_new[start:stop] = numint.eval_rho(perturbed,ao,dm)
rho_diff = rho_new.reshape((48,48,48)) - rho_ref
if not (rho_diff.min() < 0 < rho_diff.max()):
    raise RuntimeError("Computed difference density is not signed")
target = OUT / "water_displacement_difference.cube"
grid.write(rho_diff,target,comment="Difference electron density: perturbed water minus reference water (e/Bohr^3)")
report = {"solver":"PySCF","solver_version":pyscf.__version__,
          "method":"molecular RHF/STO-3G for perturbed water; scalar subtraction on original-water CUBE grid",
          "perturbation":"One O-H bond endpoint moved from x=0.758602 to 0.818602 Angstrom; other coordinates unchanged",
          "perturbed_energy_hartree":float(mf.e_tot),
          "reference_cube_sha256":hashlib.sha256(REFERENCE.read_bytes()).hexdigest(),
          "grid_shape":[48,48,48],"difference_range_e_per_bohr3":[float(rho_diff.min()),float(rho_diff.max())],
          "source_rights":"CC0-1.0 dedication by GX-TXT Task 006 authors",
          "files":{p.name:hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in [OUT/"water_perturbed_pyscf.log",target]}}
(OUT / "signed_calculation_provenance.json").write_text(json.dumps(report,indent=2)+"\n")
print(json.dumps(report,indent=2))
