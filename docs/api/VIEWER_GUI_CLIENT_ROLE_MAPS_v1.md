# Native client component roles, version 1

The shared Viewer design model accepts two optional dictionary properties on a
`section`: `script_library_components` and `scientific_preview_components`.
Builder exposes them through its normal component property editor. Each value
maps a finite semantic role to an actual declared component ID in the same
design. An absent or empty dictionary is unbound. No module identity is special.

`::GX::viewerGuiClientRoleMaps design` validates the entire design and returns
`form_ID → property → role → component_ID`. `viewerGuiRoleMapApiInfo` documents
this inert versioned projection. IDs retain their original component order and
SDK ordinal. Referenced components may belong to another panel of the same
design. Paths, widget names, missing components, duplicate keys, wrong types,
role aliases and shared components between controllers are refused.

For a Viewer, `script_library_components` requires all these roles:

| Roles | Component type |
| --- | --- |
| scope_filter, language_filter | choice |
| search_query | entry |
| records | table |
| record_scope, record_language, record_id, record_name, record_version, record_description, record_required_apis | field |
| record_identity | log |
| operation_status | status |
| source_files, registered_source, parameter_definitions | panel |

The three panels contain no authored children. The admitted CORE controller
owns their SourceSurface and source-file controls at runtime.

For a managed C++ Preview, `scientific_preview_components` requires `values`,
`metadata` and `source`, each a read-only `table`. A frame-capable declaration
additionally supplies all five roles together: `frame_view` (`panel`),
`frame_variable`, `frame_x_dimension`, `frame_y_dimension` (`choice`), and
`frame_indices` (`field`). The frame panel contains no authored children; its
scientific renderer remains the existing canonical plane owner. Ordinary
managed numeric Preview field controls use the existing UI Field validation.

These maps grant no capability. Runtime admission must independently verify
the actual installed SDK/module, finite operation, live window and Preview
mount where applicable, current Session/Dataset identity and user event. Source,
Registry, canonical numeric reads, Workspace and History retain their existing
owners. This model extension alone does not establish implementation or
acceptance of either native client.
