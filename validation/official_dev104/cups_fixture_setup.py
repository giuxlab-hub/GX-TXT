# SPDX-License-Identifier: GPL-3.0-or-later
"""Create a new private OS adapter fixture, never alter historical fixtures."""
from pathlib import Path
import hashlib, json, shutil, sys
root=Path(sys.argv[1]).resolve()
if '_private_dev104' not in root.parts: raise ValueError('Private fixture root required')
root.mkdir(exist_ok=False);(root/'bin').mkdir()
(root/'.private-cups-fixture').write_text('Private fake CUPS; no forwarding to physical devices.\n')
(root/'mode').write_text('normal\n')
source=Path(__file__).with_name('cups_fixture.py')
for name in ('lpstat','lpoptions','lp','cancel'):
    target=root/'bin'/name;shutil.copyfile(source,target);target.chmod(0o755)
(root/'fixture.json').write_text(json.dumps(dict(schema='gxtxt.private_cups_fixture.v1',sha256=hashlib.sha256(source.read_bytes()).hexdigest(),physical_forwarding=False),indent=2)+'\n')
print(root)
