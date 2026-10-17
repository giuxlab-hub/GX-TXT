"""Clearly synthetic image/NMRPipe prerequisites for actual Viewer opening."""
from pathlib import Path
import sys
import numpy as np
from PIL import Image
framework, output=(Path(p).resolve() for p in sys.argv[1:])
output.mkdir(exist_ok=False)
Image.new('RGB',(128,96),(235,245,255)).save(output/'synthetic_image.png')
sys.path.insert(0,str(framework/'plugins/modules/acq.nmr_multidimensional/runtime/vendor'))
import nmrglue as ng
udic=ng.fileiobase.create_blank_udic(2)
for index,(label,obs,sw,car) in enumerate([('N',60.,1800.,7200.),('H',600.,6000.,3000.)]):
    udic[index].update(size=32,complex=False,sw=sw,obs=obs,car=car,label=label,time=False,freq=True,encoding='direct')
x,y=np.mgrid[-1:1:32j,-1:1:32j]
array=(np.exp(-((x-.3)**2+(y+.2)**2)/.04)+.7*np.exp(-((x+.4)**2+(y-.3)**2)/.07)).astype('float32')
ng.pipe.write(str(output/'synthetic_catalog_spectrum.ft2'),ng.pipe.create_dic(udic),array,overwrite=False)
(output/'README.txt').write_text('Synthetic UI opening prerequisites only. No acquired measurement or scientific validation is claimed.\n')
