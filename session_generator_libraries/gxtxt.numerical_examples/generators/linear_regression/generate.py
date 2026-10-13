#!/usr/bin/env python3
import argparse,csv,random,sys
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('--target-session',required=True); p.add_argument('--library-id'); p.add_argument('--generator-id'); a=p.parse_args()
root=Path(a.target_session); rng=random.Random(1971); aa=2.5; b=1.2
with (root/'raw'/'linear_regression.csv').open('w',newline='',encoding='utf-8') as f:
 w=csv.writer(f); w.writerow(['x','y'])
 for i in range(41):
  x=i*0.5; y=aa*x+b+rng.gauss(0.0,0.12); w.writerow([f'{x:.8g}',f'{y:.12g}'])
(root/'metadata'/'ground_truth.txt').write_text('model=y=a*x+b+noise\na=2.5\nb=1.2\nnoise=Gaussian sigma 0.12\nseed=1971\n',encoding='utf-8')
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from recipe import configure
configure(root,'linear_regression.csv','regression.linear.source','demo.numeric.regression',
          {'x':'independent','y':'measured'}, {'x':'x','measured':'y'},
          {'selection':'','fit_mode':'linear','polynomial_degree':'1','weight_semantics':'relative','output_dataset_id':'demo.numeric.regression.result'})
print('Generated deterministic linear-regression dataset.')
