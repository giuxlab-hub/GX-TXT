#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import sys,json,hashlib,time
from pathlib import Path
root=Path(sys.argv[1]).resolve();out=Path(sys.argv[2]);out.mkdir(exist_ok=False)
sys.path.insert(0,str(root/'core/python'))
import gxtxt_viewer_icons as icons
ids=['select','draw_line','junction','stop','save'];sizes=[20,24]
t=time.monotonic();batch=icons.stock_batch(ids,sizes,'/usr/bin/convert');elapsed=time.monotonic()-t
catalog=icons.shared_catalog()['icons'];results=[]
for id in ids:
 row=catalog[id];expected=icons.admit(row['path'],row['title'],row['category'],row['license'],'/usr/bin/convert')
 assert batch[id]['asset']==expected
 for size in sizes:
  actual=icons.base64.b64decode(batch[id]['photos'][str(size)])
  wanted=icons.raster(icons.base64.b64decode(expected['png']),'png',size,'/usr/bin/convert')
  assert actual==wanted
  results.append(dict(id=id,size=size,sha256=hashlib.sha256(actual).hexdigest()))
for args in [(['select','select'],[20]),(['unknown'],[20]),(['select'],[999])]:
 try:icons.stock_batch(*args,'/usr/bin/convert')
 except ValueError:pass
 else:raise AssertionError('Invalid batch admitted')
(out/'RESULT.json').write_text(json.dumps(dict(result='PASS',byte_identical=results,batch_seconds=elapsed,negative_cases=3),indent=2)+'\n')
