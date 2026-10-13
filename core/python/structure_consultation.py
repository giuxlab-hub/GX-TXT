#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Disposable structural rendering through the established scientific decoders."""
import sys,json
from pathlib import Path
import molecule_io,crystal_data
source,out=map(Path,sys.argv[1:3]);out.mkdir(exist_ok=True)
if source.stat().st_size>64*1024*1024:raise ValueError('Structural consultation input budget is 64 MiB')
if source.suffix.lower() in ('.cif','.cube','.cub'):
 result=crystal_data.render(source,out)
else:
 frames,fmt=molecule_io.read(source)
 molecule_io.make_mesh(source,out/'atoms.vtp',0,'ball_and_stick')
 title,atoms,bonds=frames[0]
 result=dict(format=fmt,name=title,atoms=atoms,bonds=bonds,conformers=len(frames),displayed_conformer=0,coordinate_policy='PDB/SDF Angstrom; XYZ raw declared coordinates',bond_policy='Covalent-radius inferred bonds when the source does not declare connectivity')
(out/'inspection.json').write_text(json.dumps(result,indent=2))
print('STRUCTURE_READY')
