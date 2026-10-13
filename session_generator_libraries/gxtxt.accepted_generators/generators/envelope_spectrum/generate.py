#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse,csv,math
from pathlib import Path
FS=8192.0;DUR=8.0;N=int(FS*DUR);FC=2048.0;F1=47.0;M1=0.40;F2=93.0;M2=0.15;NOISE=0.03;SEED=271828;PM=2147483647;A=16807
class RNG:
    def __init__(self,s): self.s=s;self.spare=None
    def u(self): self.s=(self.s*A)%PM;return self.s/PM
    def n(self):
        if self.spare is not None:z=self.spare;self.spare=None;return z
        u1=max(self.u(),1e-15);u2=self.u();r=math.sqrt(-2*math.log(u1));a=2*math.pi*u2;self.spare=r*math.sin(a);return r*math.cos(a)
def env(t): return 1.0+M1*math.cos(2*math.pi*F1*t)+M2*math.cos(2*math.pi*F2*t)
def clean(t): return env(t)*math.cos(2*math.pi*FC*t)
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--target-session',required=True);ap.add_argument('--library-id');ap.add_argument('--generator-id');a=ap.parse_args();root=Path(a.target_session);raw=root/'raw';meta=root/'metadata';raw.mkdir(parents=True,exist_ok=True);meta.mkdir(parents=True,exist_ok=True);rng=RNG(SEED);noise=[]
    with (raw/'envelope_spectrum_demo.csv').open('w',newline='',encoding='utf-8') as h:
        w=csv.writer(h);w.writerow(['time_s','envelope_truth_V','clean_V','measured_V'])
        for i in range(N):
            t=i/FS;e=env(t);c=e*math.cos(2*math.pi*FC*t);q=NOISE*rng.n();noise.append(q);w.writerow([f'{t:.12g}',f'{e:.12g}',f'{c:.12g}',f'{c+q:.12g}'])
    truth=f'''dataset=envelope_spectrum_demo.csv\nsample_rate_hz={FS:.12g}\nduration_s={DUR:.12g}\nsamples={N}\ncarrier_frequency_hz={FC:.12g}\nenvelope_mean_V=1\nmodulation_1_frequency_hz={F1:.12g}\nmodulation_1_amplitude_V={M1:.12g}\nmodulation_2_frequency_hz={F2:.12g}\nmodulation_2_amplitude_V={M2:.12g}\nnoise_sigma_V={NOISE:.12g}\nnoise_seed={SEED}\nrecommended_band_low_hz=1500\nrecommended_band_high_hz=2600\nrecommended_envelope_dc=remove_mean\nrecommended_fft_window=hann\nrecommended_nfft=auto\nexpected_frequency_resolution_hz={1/DUR:.12g}\n''';(meta/'envelope_spectrum_ground_truth.txt').write_text(truth,encoding='utf-8')
    (root/'STUDENT_GUIDE.md').write_text('''# Envelope Spectrum student exercise\n\nThis Session contains an amplitude-modulated 2048 Hz carrier. The envelope contains known 47 Hz and 93 Hz components.\n\n## Workflow\n\n1. Import `raw/envelope_spectrum_demo.csv`.\n2. Configure `time_s` as the independent elapsed-time coordinate in seconds and `measured_V` as a measured signal in volts.\n3. Enable **Envelope Spectrum & Demodulation Analysis**.\n4. Bind Time = `time_s`, Signal = `measured_V`.\n5. Use the full Dataset (no Selection).\n6. Input detrend = `mean`.\n7. Pre-demodulation isolation = `ideal_fft_bandpass`.\n8. Lower/upper band = `1500 / 2600 Hz`.\n9. Envelope DC = `remove_mean`.\n10. FFT window = `hann`, NFFT = `auto`.\n11. Run. The expected envelope-spectrum peaks are 47 Hz and 93 Hz.\n12. Enable the optional Time-domain envelope graph and compare it with `envelope_truth_V`.\n13. Create graph variants for amplitude, PSD dB and different frequency ranges without recalculating.\n\n## Questions\n\n- Why does amplitude modulation create sidebands around the 2048 Hz carrier?\n- Why does envelope demodulation move the 47 Hz and 93 Hz modulation frequencies back to baseband?\n- Why is removing the envelope mean useful before the envelope FFT?\n- Why should a resonance/carrier band be isolated before demodulation in broadband vibration data?\n''',encoding='utf-8')
    print(f'Generated {N} deterministic envelope-spectrum samples')
if __name__=='__main__': raise SystemExit(main())
