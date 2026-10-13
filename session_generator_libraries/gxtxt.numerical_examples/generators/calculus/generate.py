#!/usr/bin/env python3
import argparse,csv,sys
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('--target-session',required=True); p.add_argument('--library-id'); p.add_argument('--generator-id'); a=p.parse_args()
root=Path(a.target_session)
with (root/'raw'/'calculus.csv').open('w',newline='',encoding='utf-8') as f:
 w=csv.writer(f); w.writerow(['x','f','df_dx','F'])
 for i in range(81):
  x=-2.0+i*0.05; y=x**3-2*x; d=3*x*x-2; F=x**4/4-x*x; w.writerow([f'{x:.8g}',f'{y:.12g}',f'{d:.12g}',f'{F:.12g}'])
(root/'metadata'/'ground_truth.txt').write_text('f=x^3-2*x\nderivative=3*x^2-2\nantiderivative=x^4/4-x^2\n',encoding='utf-8')
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from recipe import configure
configure(root,'calculus.csv','calculus.source','demo.numeric.calculus',
          {'x':'independent','f':'measured','df_dx':'reference','F':'reference'},
          {'x':'x','function':'f','derivative_reference':'df_dx','antiderivative_reference':'F'},
          {'selection':'','output_dataset_id':'demo.numeric.calculus.result'})
print('Generated calculus dataset.')
