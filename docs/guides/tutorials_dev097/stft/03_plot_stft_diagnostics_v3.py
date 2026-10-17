# GX-TXT Python Script Workspace — native 2D and 3D STFT graphs.
# SPDX-License-Identifier: GPL-3.0-or-later
# Analysis Sources:
#   primary -> tutorial.stft_trace_preview
#   grid    -> tutorial.stft_spectrogram_xyz
# Both plots are ordinary persistent plot.dataset Variants, not script PNGs.

from gxtxt import gxtxt_context, gxtxt_api_call, gxtxt_api_require


def api(api_id, operation, *args):
    return gxtxt_api_call(api_id, operation, list(args))


def input_dataset(alias):
    value = gxtxt_context().get("inputs", {}).get(alias)
    if not isinstance(value, dict) or not value.get("dataset_id"):
        raise RuntimeError(f"STFT_PLOT: bind an Analysis Source with Semantic alias '{alias}'")
    return str(value["dataset_id"])


def publish_plot(spec):
    if not api("PLOT_DATASET_API_v3", "validate_spec", spec):
        raise RuntimeError("STFT_PLOT: PlotSpec validation returned false")
    ref = api("PLOT_DATASET_API_v3", "create_plot", spec, "variant")
    api("SESSION_PERSISTENCE_API_v1", "commit")
    api("PLOT_DATASET_API_v3", "render", ref)
    artifacts = api("PLOT_DATASET_API_v3", "artifacts", ref)
    return ref, artifacts


gxtxt_api_require([
    "DATASET_METADATA_API_v1@1",
    "PLOT_DATASET_API_v3@3:plot.dataset+plotspec",
    "SESSION_PERSISTENCE_API_v1@1",
])

trace_id = input_dataset("primary")
grid_id = input_dataset("grid")
trace_meta = api("DATASET_METADATA_API_v1", "read", trace_id)
grid_meta = api("DATASET_METADATA_API_v1", "read", grid_id)
if trace_meta.get("stft.kind") != "trace_preview":
    raise RuntimeError("STFT_PLOT: primary must be the STFT time trace preview")
if grid_meta.get("stft.kind") != "spectrogram_xyz":
    raise RuntimeError("STFT_PLOT: grid must be the STFT 3D XYZ Dataset")
if trace_meta.get("stft.source_dataset_id") != grid_meta.get("stft.source_dataset_id"):
    raise RuntimeError("STFT_PLOT: inputs originate from different source Datasets")

spec = api("PLOT_DATASET_API_v3", "new_spec", "plot.dataset.xy",
           "STFT — original and reconstructed signal")
original_series = {
    "id": "original", "dataset_id": trace_id,
    "x_variable_id": "v_time_s", "y_variable_id": "v_original_v",
    "kind": "line", "axis": "left", "label": "Original",
}
reconstructed_series = {
    "id": "reconstructed", "dataset_id": trace_id,
    "x_variable_id": "v_time_s", "y_variable_id": "v_reconstructed_v",
    "kind": "line", "axis": "left", "label": "Inverse STFT",
}
error_series = {
    "id": "residual", "dataset_id": trace_id,
    "x_variable_id": "v_time_s", "y_variable_id": "v_residual_v",
    "kind": "line", "axis": "left", "label": "Reconstruction error",
}

spec["multi_panel"] = 1
spec["panels"] = [
    {
        "id": "main", "title": "Nonstationary signal and inverse STFT",
        "axes": {"x": {"label": "Time [s]"}, "y_left": {"label": "Voltage [V]"}},
        "annotations": [], "series": [original_series, reconstructed_series],
    },
    {
        "id": "error", "title": "Numerical reconstruction residual",
        "axes": {"x": {"label": "Time [s]"}, "y_left": {"label": "Residual [V]"}},
        "annotations": [], "series": [error_series],
    },
]
trace_ref, trace_art = publish_plot(spec)
print(f"STFT_PLOT trace_variant={trace_ref['variant_id']} "
      f"artifact={trace_art.get('graph_artifact', '')}")

# A separate PlotSpec uses the regular XYZ visualization Dataset; the full
# rank-2 complex STFT remains in tutorial.stft_complex_matrix in the Session.
plot3 = {
    "schema": "PLOT_DATASET_PLOTSPEC_v2",
    "graph_type": "cartesian_3d",
    "graph_id": "plot.dataset.xyz",
    "dataset_id": grid_id,
    "x_variable_id": "v_time_s",
    "y_variable_id": "v_frequency_hz",
    "z_variable_id": "v_psd_db",
    "title": "STFT spectrogram — chirp and transient events",
    "config": {
        "plot_type": "surface",
        "reduction_mode": "none",
        "x_label": "Time [s]",
        "y_label": "Frequency [Hz]",
        "z_label": "PSD [dB re 1 V^2/Hz]",
    },
}
surface_ref, surface_art = publish_plot(plot3)
print(f"STFT_PLOT surface_variant={surface_ref['variant_id']} "
      f"artifact={surface_art.get('graph_artifact', '')}")

api("SESSION_PERSISTENCE_API_v1", "commit")
print("PASS STFT_PLOTS_V3 ",
      f"trace={trace_ref['graph_id']}:{trace_ref['variant_id']} "
      f"surface={surface_ref['graph_id']}:{surface_ref['variant_id']} "
      f"source={trace_meta['stft.source_dataset_id']}")
