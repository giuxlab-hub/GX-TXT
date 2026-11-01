# Separate DEV112 demonstrations

The framework already contains every non-demo module. This separate archive
contains only the 15 demonstrations identified in module_packaging.json.

Close GX-TXT and its workers, verify/extract this archive, then run:

```sh
python3 -I -B install_demo.py /absolute/path/to/gxtxt_pipeline_v09810dev_112 --stopped
```

The existing Plugin Install API owns all installation, version checks, registry
transactions, rollback and runtime admission. This installer never installs
ordinary, CORE or ALWAYS modules and never activates an owner launcher.
Its receipt and private logs are in a new sibling outside the framework.

For migration, first extract a fresh framework and run its personal migration
helper, then install these demos. Existing user data and custom code remain in
their original locations. Use normal Plugin Manager operations for subsequent
supported updates/removal, with the application stopped where required.

analysis.definition_demo uses an added standard package manifest. The geospatial
package contains the unchanged original gxtxt_geospatial_examples_1.0.0.zip,
SHA-256 f8758fec19f43a2ce11605edd8571c6a0c9dc9c789c58d3e903bef6571d2ca08,
already declared by its accepted descriptor. No demo scientific/runtime code was
modified or rebuilt for this consolidation.
