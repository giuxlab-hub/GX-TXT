#!/usr/bin/env python3
import argparse,csv,math
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('--target-session',required=True); p.add_argument('--library-id'); p.add_argument('--generator-id'); a=p.parse_args()
root=Path(a.target_session); fs=1024.0; n=1024; f1,a1=50.0,1.0; f2,a2=120.0,0.4
with (root/'raw'/'fft_example.csv').open('w',newline='',encoding='utf-8') as f:
 w=csv.writer(f); w.writerow(['time_s','signal'])
 for i in range(n):
  t=i/fs; y=a1*math.sin(2*math.pi*f1*t)+a2*math.sin(2*math.pi*f2*t); w.writerow([f'{t:.12g}',f'{y:.12g}'])
(root/'metadata'/'ground_truth.txt').write_text('sample_rate_hz=1024\nsamples=1024\ncomponent_1_hz=50\ncomponent_1_amplitude=1\ncomponent_2_hz=120\ncomponent_2_amplitude=0.4\nnoise=none\n',encoding='utf-8')
print('Generated deterministic FFT example dataset.')
