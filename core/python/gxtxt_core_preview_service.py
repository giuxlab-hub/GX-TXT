import gxtxt
p=gxtxt.gxtxt_context()['parameters']
gxtxt.gxtxt_api_call('DATASET_PREVIEW_API_v1','cache_generate',[p['dataset_id'],p['options'],p['expected_key']])
