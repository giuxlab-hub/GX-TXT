# Occhi sul Molo: audio acquisition to spectral views

This Session contains the author's original *Occhi sul Molo* WAV (48 kHz, stereo, 16-bit PCM; about 284.4 seconds). The author authorized its distribution for this GX-TXT demonstration. The WAV's SHA-256 is recorded in `metadata/audio_source.sha256`.

## Suggested workflow

1. Import `raw/Occhi_Sul_Molo_lavoro.wav` using **WAV acquisition**. Preview shows a bounded binary summary and does not read the entire file into the GUI.
2. Run **Audio Decode** to publish the canonical PCM Dataset. Check sample rate, channel count, duration and provenance.
3. Run **FFT Spectrum & Error Analysis** on a chosen interval or fixed block. The resulting `spectrum.table` is an audio frequency spectrum; spectroscopy's `spectrum.scientific` is a separate contract.
4. Run **Spectral Features** on that FFT result. Compare dominant bin, spectral centroid, bandwidth, rolloff, flatness and cumulative spectral power. The dominant bin from one short window is not the song's musical pitch.
5. Create a 1-second Temporal Window Set stepped by 0.5 seconds, then run **Time-dependent FFT**. Inspect the 2D time-frequency image, 3D surface and a Plot Variant comparing early, middle and late windows.
6. Use the experiment and Dataset Markdown editors to record assumptions, settings and conclusions. Rerender Plot Variants from cached scientific data, then export the Session as an offline HTML site.

The separately supplied executed faculty DEMO Session includes the real analyses, reports, rich notes and audited HTML. The generator creates a fresh teaching Session so the entire workflow can be repeated.

THD, SINAD and ENOB from a music FFT are diagnostics of the selected numeric procedure, not meaningful audio-quality ratings for a polyphonic song.
