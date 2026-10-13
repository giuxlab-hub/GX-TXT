#!/usr/bin/env python3
"""Reproducible PySCF calculations for GX-TXT real density examples.

The two SCF calculations are deliberately small validation cases. Their CUBE
files contain solver-computed electron densities, not analytic illustrations.
"""
from pathlib import Path
import hashlib
import json
import pyscf
from pyscf import gto, scf
from pyscf.tools import cubegen
from pyscf.pbc import gto as pbc_gto, scf as pbc_scf

HERE = Path(__file__).resolve().parent
OUT = HERE / "computed"
OUT.mkdir(exist_ok=True)

water = gto.M(
    atom="O 0.000000 0.000000 0.000000; H 0.758602 0.000000 0.504284; H -0.758602 0.000000 0.504284",
    unit="Angstrom", basis="sto-3g", charge=0, spin=0, verbose=4,
    output=str(OUT / "water_pyscf.log"),
)
mf = scf.RHF(water)
mf.conv_tol = 1e-9
mf.kernel()
if not mf.converged:
    raise RuntimeError("Water SCF did not converge")
cubegen.density(water, str(OUT / "water_density.cube"), mf.make_rdm1(),
                nx=48, ny=48, nz=48, margin=3.0)

# Diamond conventional cubic cell, COD 2101499 lattice parameter, expressed
# as primitive vectors with the two-site diamond basis. Periodic RHF density.
a = 3.56658
cell = pbc_gto.Cell()
cell.a = [[0, a/2, a/2], [a/2, 0, a/2], [a/2, a/2, 0]]
cell.atom = [["C", (3*a/8, 3*a/8, 3*a/8)],
             ["C", (5*a/8, 5*a/8, 5*a/8)]]
cell.unit = "Angstrom"
cell.basis = "gth-szv"
cell.pseudo = "gth-pade"
cell.mesh = [15, 15, 15]
cell.verbose = 4
cell.output = str(OUT / "diamond_pyscf.log")
cell.build()
pmf = pbc_scf.RHF(cell)
pmf.conv_tol = 1e-7
pmf.max_cycle = 60
pmf.kernel()
if not pmf.converged:
    raise RuntimeError("Diamond periodic SCF did not converge")
cubegen.density(cell, str(OUT / "diamond_density.cube"), pmf.make_rdm1(),
                nx=32, ny=32, nz=32, resolution=None)

report = {
    "solver": "PySCF", "solver_version": pyscf.__version__,
    "water": {"method": "molecular RHF/STO-3G", "energy_hartree": mf.e_tot},
    "diamond": {"method": "periodic Gamma-point RHF/GTH-SZV/GTH-Pade", "energy_hartree": pmf.e_tot},
    "files": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.iterdir()
              if p.is_file() and p.name != "calculation_provenance.json"},
}
(OUT / "calculation_provenance.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
