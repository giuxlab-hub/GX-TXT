# Format and integration references

The authoritative GX-TXT baseline is the supplied `gxtxt_pipeline_v09809.tar.gz`.
Relevant original files inspected (not redistributed by this plugin):

- `docs/api/ACQUISITION_HANDLER_PLUGIN_API_v1.md`
- `docs/api/PREVIEW_DESCRIPTOR_API_v1.md`
- `docs/api/PLUGIN_INSTALL_API_v1.md`
- `docs/api/CONTRACT_REGISTRY_API_v1.md`
- `plugins/modules/viewer.native_3d/module.ini`
- `plugins/modules/viewer.native_3d/MANUAL.md`
- `plugins/modules/viewer.native_3d/api/native_3d_viewer_api_v1.tcl`
- `core/tcl/acquisition_handler_api_v1.tcl`

External technical references consulted on 2026-09-28:

- VTK project, XML File Formats: https://docs.vtk.org/en/latest/vtk_file_formats/vtkxml_file_format.html
- Open CASCADE Technology, STEP Translator: https://occt3d.com/dev/doc/overview/html/occt_user_guides__step.html

These references explain the serialized containers and the downstream reader
boundary. This plugin does not redistribute VTK/OCCT or claim to implement their
full decoders. No web or network access occurs during import.
