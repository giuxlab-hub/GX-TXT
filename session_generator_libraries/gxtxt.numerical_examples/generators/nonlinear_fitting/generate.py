#!/usr/bin/env python3
import argparse,csv,math,random,sys
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('--target-session',required=True); p.add_argument('--library-id'); p.add_argument('--generator-id'); a=p.parse_args()
root=Path(a.target_session); rng=random.Random(1973); A,k,c=4.2,0.65,0.35
with (root/'raw'/'nonlinear_fitting.csv').open('w',newline='',encoding='utf-8') as f:
 w=csv.writer(f); w.writerow(['x','y'])
 for i in range(51):
  x=i*0.12; y=A*math.exp(-k*x)+c+rng.gauss(0.0,0.03); w.writerow([f'{x:.8g}',f'{y:.12g}'])
(root/'metadata'/'ground_truth.txt').write_text('model=y=A*exp(-k*x)+c+noise\nA=4.2\nk=0.65\nc=0.35\nnoise=Gaussian sigma 0.03\nseed=1973\n',encoding='utf-8')
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from recipe import configure
configure(root,'nonlinear_fitting.csv','nonlinear.source','demo.numeric.nonlinear_fit',
          {'x':'independent','y':'measured'}, {'x':'x','y':'y'}, {})
print('Generated deterministic nonlinear-fitting dataset.')
