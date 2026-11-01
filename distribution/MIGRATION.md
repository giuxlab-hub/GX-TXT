# Side-by-side migration from DEV111

Extract DEV112 into a new directory. All ordinary modules are already present.
Close both applications and workers. Retain the old installation, Configuration,
working-directory profiles, Projects, Sessions, RAW, Libraries, Workspaces and
personal package originals.

Supported order: **fresh extraction → optional personal migration → optional
separate demo installation → normal startup**. Migration requires the pristine
release inventory. It intentionally refuses repeated migration or use after
demos/plugins/runtime files have changed the target. Use a new extraction then.

From the new DEV112 framework:

```sh
python3 -I -B distribution/migrate.py \
  --migrate-from /absolute/existing-dev111 --stopped
```

Old descriptors and registry are read as inventory only; mutable registry rows
are never copied. Provided modules are not installed again. Compatible personal
non-demo packages use the unchanged Plugin Install API. CORE and ALWAYS are
excluded; owner-required CORE flags in the new release take precedence over
missing flags in older descriptors.

Demos remain separate and are named in the receipt. Install them using the demo
installer before opening Sessions requiring them. Custom demo code remains in the
old tree and must not be overwritten blindly.

Retain existing Configuration paths to use the unchanged Configuration API. For
an explicit byte-identical copy to a fresh file, add both:

```sh
  --config-source /absolute/old-configuration.ini \
  --config-target /absolute/new-config-root/gxtxt_pipeline/configuration.ini
```

Use the intended XDG_CONFIG_HOME for a separate Configuration root. Profiles and
other personal files stay in place unless explicitly copied by their owner. No
Default Configuration Generator, merge or user/Session scope change is introduced.

Scientific data are not relocated or copied. Keep the old installation if personal
paths point inside it. Do not open a writable Session in both versions at once.
Saved Session/module references remain unchanged.

Newer compatible personal packages use explicit updates. Superseded older copies
stay in the old tree and are named in the receipt. Same-version content conflicts,
unsafe paths, missing manifests, incompatible SDKs or normal API refusals stop
explicitly; nothing is silently repaired, downgraded or claimed transferred.

Accepted P035 is the reference migration baseline. Earlier DEV111 identities retain
their actual compatibility requirements and are not individually requalified.
Private logs/receipt use a fresh sibling outside the framework; a small receipt
also resides in the new target. No launcher or owner installation is activated.
