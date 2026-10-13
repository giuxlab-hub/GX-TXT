# Native 3D graphics policy (GX-TXT dev-032)

GX-TXT owns Native 3D graphics preferences in **Configuration → Viewers →
Native 3D graphics / performance**. They are saved in the user's
`configuration.ini`, not in a Session. Every Viewer Provider render passes
the effective settings to Native 3D CORE. Direct C consumers use
`gx3de_engine_graphics_policy_set/get`; new targets inherit that policy.
`gx3de_target_graphics_policy_get` reports effective target values, including
explicit quality or GPU budget overrides through the existing target APIs.
`gx3de_target_interaction_set` marks an object drag and restores normal
quality when called with zero. The policy is size-tagged and backend-neutral.
Set it before creating targets when possible; changing it updates targets.
An engine created outside GX-TXT retains the earlier direct-C rendering
defaults until its caller sets a policy: Full display geometry, interaction
LOD Off, MSAA Off, depth peeling, export factor 1, a 4-million-triangle
display cap and no explicit GPU budget. Its policy query also returns worker
limits of 4096 MiB RSS and 8192 MiB address space for callers that supervise
an external renderer process.

| Preference (`viewers.native3d.*`) | Default | Allowed values |
| --- | --- | --- |
| `preset` | High | Low, Medium, High, Ultra, Custom |
| `execution` | Auto | Auto, Hardware, Software |
| `normal_quality` | High | Preview, Low, Medium, High, Full |
| `interaction_lod` | On | Off, On |
| `interaction_quality` | Medium | Preview, Low, Medium, High |
| `msaa` | 4x | Off, 2x, 4x, 8x |
| `transparency` | Depth peeling | Standard, Depth peeling |
| `export_supersampling` | 1 | 1–4 |
| `display_triangle_budget` | 1000000 | 1000–4000000 |
| `gpu_budget_mib` | 512 | `auto` (no explicit cap), or 16–16384 |
| `worker_rss_budget_mib` | 4096 | 128–65536 |
| `worker_address_space_budget_mib` | 8192 | 512–65536 |

Presets change only normal quality, interaction LOD/quality, MSAA,
transparency and triangle budget. Execution, export supersampling and resource
limits stay under user control. Editing a mapped value displays Custom when
the settings match no preset.

| Preset | Normal | Interaction LOD | Interaction quality | MSAA | Transparency | Triangle budget |
| --- | --- | --- | --- | --- | --- | ---: |
| Low | Low | On | Preview | Off | Standard | 250000 |
| Medium | Medium | On | Low | 2x | Standard | 500000 |
| High | High | On | Medium | 4x | Depth peeling | 1000000 |
| Ultra | Full | Off | High | 8x | Depth peeling | 4000000 |

The C policy uses `GX3DE_LOD_*`, `GX3DE_GRAPHICS_*`, the existing
`gx3de_render_quality`, byte budgets and an export factor.
`GX3DE_CAP2_GRAPHICS_POLICY` in the second capability word advertises this
API family. The policy reuses the
target quality/GPU setters, resource and renderer-info queries, and
`gx3de_view_render_rgba_supersampled`. The new
`gx3de_view_write_png_supersampled` writes a PNG at the requested output
dimensions. Off means zero MSAA samples. Standard means alpha fallback;
Depth peeling uses the existing renderer mode. Unsupported settings must
return an error rather than silently map to another value.

For OpenGL Native X11 targets in dev-044, VTK rasterizes into its own render
framebuffer and resolves the image to the caller-owned X11 window. A normal
`XCreateSimpleWindow` host can have zero samples while the rendering framebuffer
has the requested 4x MSAA. CORE checks `GL_SAMPLES` while VTK's render
framebuffer is bound, and returns `GX3DE_UNSUPPORTED` if its effective sample
count is below the request. `gx3de_target_render_diagnostics` reports the
requested level, effective render-framebuffer samples, host/default samples,
and `GL_MAX_SAMPLES` separately. It does not imply the host window itself is
multisampled. The host still needs a usable OpenGL/GLX context, and an OpenGL
backend genuinely unable to allocate the requested sample count remains
unsupported. No new public API is required.

Mesh LOD and B-Rep display tessellation use the effective quality without
changing source geometry. Derived mesh representations are cached per target.
During object interaction, the interaction LOD is active when enabled; normal
quality returns on completion. Picking derived geometry provides an object
point but no claimed source triangle or vertex index. Camera-only movement
does not switch LOD or rebuild unchanged geometry. The display triangle
budget is enforced across visible target geometry.

Auto starts the isolated worker without software forcing and retries with
Mesa llvmpipe after a qualifying renderer failure. Hardware requires a
reported hardware renderer; Software forces Mesa. The Configuration check
reports actual backend, execution, device/driver and GPU accounting class.
The RSS limit is sampled on Linux; the address-space limit uses `prlimit` on
supported Unix hosts. These process limits are returned by the C policy for
framework supervision, not enforced on in-process C callers.

OpenGL GPU use is a conservative estimate, not exact VRAM. The resource query
reports `GX3DE_RESOURCE_ESTIMATED` for the estimate and
`GX3DE_RESOURCE_UNAVAILABLE` for measured usage. An explicit GPU budget is
enforced against that estimate. Hardware capability and Windows Direct3D
behavior require separate acceptance environments.

## dev089 screen-space camera orientation

The additive size-tagged C ABI `gx3de_orientation_indicator` and
`gx3de_view_orientation_indicator_set/get` own per-view orientation presentation.
The caller sets `struct_size`; visible is 0/1, corner uses existing
`gx3de_navcube_corner` values 0..3, size is 48..256 pixels, margin is 0..128.
Invalid arguments return `GX3DE_INVALID_ARGUMENT`. Defaults are off, bottom left,
96 pixels and 16-pixel margin. Reserved fields remain reserved. ABI version 1 and
existing structures/signatures remain unchanged.

The renderer uses a VTK axes actor in its own transparent layer-1 renderer with
a centered parallel camera. Direction and up follow the scientific camera,
including roll. The corner viewport is bounded by the actual host size. Pan,
zoom, scientific units and the distant world origin cannot displace the indicator.
It is not a pickable world gizmo. Static render caching includes this state.
Existing world axes, scientific calibrated axes and colorbar remain separate.
The packaged Debian native engine and Tcl transport were rebuilt together. Other
compiled transports require rebuilding these same source changes before using
the new presentation API.
