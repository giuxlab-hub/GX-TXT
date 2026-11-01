# Editable oscilloscope Preview source

The installed package contains its editable `gui/design.tcldict` and handwritten
`handlers.tcl`. These are the actual inputs accepted by the installed Viewer
Interface Builder/Module Builder, with target `preview`. It also contains the
functional `MANUAL.md`, API contracts and exact package checksums. No separate
Session Generator or unshipped project file is required.

## Recover a source project from an installed module

Copy the shipped inputs into a NEW source directory outside `plugins`. For
example, use the following placeholders for your installation and scratch paths:

```sh
preview_framework=/absolute/path/to/framework
preview_module="$preview_framework/plugins/modules/preview.oscilloscope_waveform"
preview_project=/absolute/path/to/new-preview-source
preview_packages=/absolute/path/to/new-package-output
mkdir "$preview_project"
cp "$preview_module/gui/design.tcldict" "$preview_project/design.gxtxt-viewer"
cp "$preview_module/handlers.tcl" "$preview_project/handlers.tcl"
cp "$preview_module/MANUAL.md" "$preview_project/WAVEFORM_GUIDE.md"
python3 -B "$preview_framework/plugins/modules/tool.script_module_builder/runtime/builder.py" \
  viewer-build "$preview_project/design.gxtxt-viewer" \
  "$preview_project" "$preview_packages"
```

The normal Builder validates the Preview target and produces an ordinary
`preview.oscilloscope_waveform` Module ZIP. Regeneration preserves handwritten
callbacks exactly. Open the copied `design.gxtxt-viewer` in Viewer Interface
Builder to edit the layout with the Preview Module target. Its design display is
a simulation; exercise the resulting installed package in normal Dataset Preview
for source/Session/viewport behavior. Source edits belong in the copied project,
not the active installed module.

The Builder generates its general framework manual. `WAVEFORM_GUIDE.md` above
preserves the authored functional instructions for review when preparing an
updated package through the same standard Module writer. No importer release,
Session Generator version or private scientific reader is required.

## Optional engineering-checkout reproduction

The full engineering checkout additionally provides
`examples/oscilloscope_waveform_preview/project` and
`validation/dev111_p028_preview/build.py`; these are NOT runtime package paths.
In that checkout only, the following helper runs the public Builder model and
`viewer-build` twice, checks exact callback preservation, overlays the authored
functional manual and packages through the SAME ordinary Module writer:

```
python3 -B validation/dev111_p028_preview/build.py FRAMEWORK NEW_OUTPUT
```

The final normal Plugin Manager ZIP is under NEW_OUTPUT/final. Actual generation
and package receipts remain under scratch. Synthetic/generated or authorized
read-only recording fixtures used for validation are not product package data.
