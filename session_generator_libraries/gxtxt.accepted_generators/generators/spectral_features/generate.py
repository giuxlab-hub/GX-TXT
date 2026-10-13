#!/usr/bin/env python3
'''Generate the deterministic GX-TXT Spectral Features teaching dataset.'''
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse, csv, math
from pathlib import Path
FS_HZ=4096.0
SAMPLES=4096
TONES=((100.0,1.0,0.0),(300.0,0.5,0.4),(900.0,0.25,-0.7))
DC_V=0.15

def main()->int:
    ap=argparse.ArgumentParser();ap.add_argument('--target-session',required=True);ap.add_argument('--library-id');ap.add_argument('--generator-id');args=ap.parse_args()
    root=Path(args.target_session);raw=root/'raw';meta=root/'metadata';raw.mkdir(parents=True,exist_ok=True);meta.mkdir(parents=True,exist_ok=True)
    path=raw/'spectral_features_demo.csv'
    with path.open('w',newline='',encoding='utf-8') as h:
        wr=csv.writer(h);wr.writerow(['time_s','signal_V'])
        for i in range(SAMPLES):
            t=i/FS_HZ;y=DC_V+sum(a*math.sin(2*math.pi*f*t+p) for f,a,p in TONES);wr.writerow([f'{t:.12g}',f'{y:.12g}'])
    powers=[a*a for _,a,_ in TONES];total=sum(powers);q=[p/total for p in powers];freq=[f for f,_,_ in TONES]
    centroid=sum(f*p for f,p in zip(freq,q));rms=math.sqrt(sum(f*f*p for f,p in zip(freq,q)));bw=math.sqrt(sum((f-centroid)**2*p for f,p in zip(freq,q)))
    entropy=-sum(p*math.log(p) for p in q)/math.log(2048.0)
    truth=[
        'dataset=spectral_features_demo.csv','sampling=uniform',f'sample_rate_hz={FS_HZ:.12g}',f'samples={SAMPLES}','frequency_resolution_hz=1','columns=time_s;signal_V','units=s;V',f'dc_offset_V={DC_V:.12g}',
        'tone_1_frequency_hz=100','tone_1_amplitude_V=1','tone_2_frequency_hz=300','tone_2_amplitude_V=0.5','tone_3_frequency_hz=900','tone_3_amplitude_V=0.25',
        'recommended_fft_analysis_mode=full_record','recommended_fft_window=rectangular','recommended_fft_detrend=mean','recommended_input_semantics=amplitude','recommended_exclude_dc=yes',
        'ideal_power_weights=1;0.25;0.0625',f'dominant_frequency_hz=100',f'spectral_centroid_hz={centroid:.17g}',f'rms_frequency_hz={rms:.17g}',f'spectral_bandwidth_hz={bw:.17g}','frequency_05_hz=100','frequency_50_hz=100','frequency_85_hz=300','frequency_95_hz=300','occupied_bandwidth_90_hz=200',f'ideal_normalized_entropy_2048_bins={entropy:.17g}',
        'note_flatness=An ideal sparse line spectrum contains exact zero bins and therefore has exact spectral flatness 0. Numerical FFT roundoff can make the measured flatness a very small positive value.'
    ]
    (meta/'spectral_features_ground_truth.txt').write_text('\n'.join(truth)+'\n',encoding='utf-8')
    guide='''# Spectral Features student exercise

This Session Generator creates a deterministic coherent waveform for `analysis.fft_spectrum` followed by `analysis.spectral_features`.

## Known signal

- Sampling rate: 4096 Hz
- Samples: 4096 (exactly 1 second)
- Full-record FFT spacing: 1 Hz
- DC offset: 0.15 V
- Tone 1: 100 Hz, 1.000 V peak
- Tone 2: 300 Hz, 0.500 V peak
- Tone 3: 900 Hz, 0.250 V peak

For amplitude-spectrum semantics the power-equivalent line weights are `1`, `0.25`, and `0.0625`.

## GX-TXT workflow

1. Import `raw/spectral_features_demo.csv` through the normal CSV acquisition path.
2. In Variables, set `time_s` as the independent elapsed-time coordinate with unit `s`; set `signal_V` as measured with unit `V`.
3. Enable **FFT Spectrum & Error Analysis** and bind Independent -> `time_s`, Signal -> `signal_V`.
4. For the exact reference exercise use Full record, rectangular window, and mean detrend.
5. Run FFT Spectrum. The one-sided spectrum should contain coherent lines at 100, 300, and 900 Hz.
6. Enable **Spectral Features** and select the FFT `spectrum.table` as its Analysis Source.
7. Bind Frequency -> `frequency` and Spectral value -> the linear amplitude variable from the FFT result.
8. Set Input spectral semantics = `amplitude` and Exclude DC = `yes`.
9. Run the module and compare the summary Dataset/report with `metadata/spectral_features_ground_truth.txt`.
10. Create graph variants for Relative power dB, Normalized power percent, and Cumulative power percent. Variants use the cache and do not recompute the descriptors.

## Reference interpretation

- Dominant frequency = 100 Hz.
- Spectral centroid is about 176.190476 Hz.
- RMS frequency is about 251.661148 Hz.
- Spectral bandwidth is about 179.694879 Hz.
- F50 = 100 Hz, F85 = 300 Hz, F95 = 300 Hz.
- The 90% occupied bandwidth `F95 - F05` is 200 Hz.

## Questions for students

- Why are amplitude values squared before they become distribution weights?
- Why is the centroid above 100 Hz even though 100 Hz is the dominant line?
- What does RMS frequency emphasize compared with the centroid?
- Why does F85 move to 300 Hz while F50 remains at 100 Hz?
- Why can spectral flatness of a mathematically sparse line spectrum be exactly zero, while a numerical FFT may return a tiny positive value?
- How do window leakage and a non-coherent record alter centroid, bandwidth, entropy, and flatness?
- Why should harmonic THD remain the responsibility of Harmonic Analysis instead of this module?
'''
    (root/'STUDENT_GUIDE.md').write_text(guide,encoding='utf-8')
    print(f'Generated {SAMPLES} deterministic spectral-features samples in {path}')
    return 0
if __name__=='__main__': raise SystemExit(main())
