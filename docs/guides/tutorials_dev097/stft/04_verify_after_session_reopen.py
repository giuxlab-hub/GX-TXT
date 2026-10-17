# GX-TXT Python Script Workspace — verify STFT Dataset state after Session reopen.
# SPDX-License-Identifier: GPL-3.0-or-later
# Standalone read-only Session script. No Dataset bindings required.

from gxtxt import gxtxt_api_call, gxtxt_api_require

INPUT_ID = "tutorial.stft_nonstationary_signal"
MATRIX_ID = "tutorial.stft_complex_matrix"
RECON_ID = "tutorial.stft_reconstruction"
TRACE_ID = "tutorial.stft_trace_preview"
GRID_ID = "tutorial.stft_spectrogram_xyz"


def api(api_id, operation, *args):
    return gxtxt_api_call(api_id, operation, list(args))


gxtxt_api_require(["CANONICAL_DATASET_API_v2@2", "DATASET_METADATA_API_v1@1"])
all_ids = set(api("CANONICAL_DATASET_API_v2", "list"))
required_ids = (INPUT_ID, MATRIX_ID, RECON_ID, TRACE_ID, GRID_ID)
missing = [dataset_id for dataset_id in required_ids if dataset_id not in all_ids]
if missing:
    raise RuntimeError("STFT_PERSISTENCE: missing registered Datasets: " + ", ".join(missing))

meta = api("DATASET_METADATA_API_v1", "read", MATRIX_ID)
if meta.get("stft.kind") != "complex_stft_rank2":
    raise RuntimeError("STFT_PERSISTENCE: complex matrix metadata are missing")
if meta.get("stft.source_dataset_id") != INPUT_ID:
    raise RuntimeError("STFT_PERSISTENCE: original Dataset identity not preserved")

info = api("CANONICAL_DATASET_API_v2", "describe", MATRIX_ID)
variables = {str(v.get("variable_id", "")): v for v in info.get("variables", [])}
for variable_id in ("v_stft_real", "v_stft_imag"):
    if variable_id not in variables or int(variables[variable_id].get("rank", -1)) != 2:
        raise RuntimeError(
            f"STFT_PERSISTENCE: expected a rank-2 scientific variable {variable_id}"
        )

recon_meta = api("DATASET_METADATA_API_v1", "read", RECON_ID)
if "stft.reconstruction_rmse_v" not in recon_meta:
    raise RuntimeError("STFT_PERSISTENCE: inverse-STFT diagnostics missing")

print(
    "PASS STFT_PERSISTENCE "
    f"datasets={len(required_ids)} matrix={MATRIX_ID} "
    f"real_shape={variables['v_stft_real'].get('shape')} "
    f"imag_shape={variables['v_stft_imag'].get('shape')} "
    f"rmse_v={recon_meta['stft.reconstruction_rmse_v']}"
)
