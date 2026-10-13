"""Researcher Python script template. Configure a Session Dataset source first."""
from gxtxt import gxtxt_context, gxtxt_api_call

ctx = gxtxt_context()
policy = gxtxt_api_call("PARALLEL_EXECUTION_API_v1", "resources", [])
print(f"GX-TXT run {ctx['run_id']}; maximum workers {policy['max_workers']}")
