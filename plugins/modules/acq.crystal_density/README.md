# Crystal and electron-density Acquisition

Import CIF and Gaussian CUBE files through the normal Acquisition source table.
The importer preserves the original bytes as a canonical Dataset, records their
SHA-256 and scientific metadata, and leaves visualization to the dedicated
Crystal Chemistry Viewer. CIF expansion and CUBE values are decoded for
inspection but never written back to the source file.
