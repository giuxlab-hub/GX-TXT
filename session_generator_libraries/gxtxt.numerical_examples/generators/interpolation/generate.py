#!/usr/bin/env python3
import argparse,csv,math,sys
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('--target-session',required=True); p.add_argument('--library-id'); p.add_argument('--generator-id'); a=p.parse_args()
root=Path(a.target_session)
xs=[0.0,0.35,0.9,1.4,2.1,2.9,3.8,4.7,5.5,6.2]
with (root/'raw'/'interpolation.csv').open('w',newline='',encoding='utf-8') as f:
 w=csv.writer(f); w.writerow(['x','y'])
 for x in xs: w.writerow([f'{x:.8g}',f'{(math.sin(x)+0.1*x):.12g}'])
(root/'metadata'/'ground_truth.txt').write_text('function=y=sin(x)+0.1*x\nsampling=sparse nonuniform\nnoise=none\n',encoding='utf-8')
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from recipe import configure
configure(root,'interpolation.csv','interpolation.source','demo.numeric.interpolation',
          {'x':'independent','y':'measured'}, {'x':'x','y':'y'},
          {'output_dataset_id':'demo.numeric.interpolation.result','query_point_count':'201'})
print('Generated interpolation dataset.')
