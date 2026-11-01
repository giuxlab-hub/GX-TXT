# SPDX-License-Identifier: GPL-3.0-or-later
"""Molecular Library admission delegates geometry validation to molecule_io."""
import base64,tempfile
from pathlib import Path
import molecule_io
def validate_entry(entry,framework):
 fields=entry['fields']
 if fields['coordinate_unit']!='angstrom' or fields['dimensionality'] not in {'2d','3d'}:
  raise ValueError('Structure requires explicit source angstrom units and 2d/3d dimensionality')
 resources=[r for r in entry.get('resources',[]) if r.get('media_type')=='chemical/x-mdl-sdfile' and r.get('availability')=='local']
 if not resources:raise ValueError('A molecular Structure Library entry requires actual admitted SDF bytes')
 for resource in resources:
  raw=base64.b64decode(resource['data_base64'],validate=True)
  with tempfile.TemporaryDirectory(prefix='gxtxt-library-molecule-admission-') as temporary:
   path=Path(temporary)/'source.sdf';path.write_bytes(raw);frames=molecule_io.read_sdf(path)
  if 'validated_atoms' in fields and fields['validated_atoms']!=len(frames[0][1]):raise ValueError('Structure atom count conflicts with original validated coordinates')
  if 'validated_bonds' in fields and fields['validated_bonds']!=len(frames[0][2]):raise ValueError('Structure bond count conflicts with original validated bonds')
