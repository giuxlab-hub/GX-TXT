# Plot display units and dual-Y GUI — v0.9.2

GX-TXT v0.9.2 completes the user interface for plotting capabilities introduced in v0.9.1.

`Axes / grid / display units` now exposes independently:

- X display unit, min, max, step and format;
- Y Left display unit, min, max, step and format;
- Y Right display unit, min, max, step and format.

Display conversion is presentation-only. Canonical scientific data are not modified.

Time display units include:

```text
ns, us, ms, s, min, h, day
```

The unit parser also recognizes `min`, `h` and `day` as source time units. The legacy `time_unit` transport remains a compatibility alias for v0.9.1 plots.

The generic scientific renderer records display-to-source scale/offset metadata in the plot geometry sidecar so Dataset Selection API v1 can persist canonical coordinates even when the displayed axis is scaled.
