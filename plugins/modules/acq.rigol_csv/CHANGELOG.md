# Changelog

## 2.0.0

- Route Rigol import through its Acquisition Handler Plugin API callback.
- Preview configured headers and a bounded data sample, with channel names,
  units, timing metadata and trailing-field structure from the actual source.
- Keep the established streaming Octave worker and canonical time-series
  Dataset output. The inspector reads descriptor configuration from the public
  callback request and worker count from Configuration API v1.
- Package the module through Plugin Install API v1 for GX-TXT 0.9.8.10-dev.
