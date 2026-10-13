#!/usr/bin/env python3
"""Generate a deterministic Dataset and a bridge-based Octave experiment."""
import argparse
import csv
import hashlib
from pathlib import Path
from session_recipe import configure


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target-session', required=True)
    parser.add_argument('--library-id')
    parser.add_argument('--generator-id')
    root = Path(parser.parse_args().target_session)
    for name in ('raw', 'scripts', 'metadata', 'notes/experiment'):
        (root / name).mkdir(parents=True, exist_ok=True)
    with (root / 'raw/octave_script_bridge_demo.csv').open('w', encoding='utf-8', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(('sample_index', 'response'))
        writer.writerows((i, 2 * i + 1) for i in range(256))
    (root / 'scripts/inspect_response.m').write_text('''% GX-TXT Octave Script Bridge teaching example.
info=gxtxt_bridge_info();
assert(strcmp(info.api_id,'OCTAVE_SCRIPT_BRIDGE_API_v1') && info.active);
ctx=gxtxt_context();
assert(strcmp(ctx.module_id,'analysis.octave_script'));
assert(gxtxt_api_has_operation('CANONICAL_DATASET_API_v2','read_range'));
dataset_id=ctx.inputs.primary.dataset_id;
ids=gxtxt_api_call('CANONICAL_DATASET_API_v2','list',{});
assert(any(strcmp(ids,dataset_id)));
description=gxtxt_api_call('CANONICAL_DATASET_API_v2','describe',{dataset_id});
response_id='';
for i=1:numel(description.variables)
  item=description.variables{i};
  if(strcmp(item.canonical,'response')),response_id=item.variable_id;break;endif
endfor
assert(!isempty(response_id));
block=gxtxt_api_call('CANONICAL_DATASET_API_v2','read_range',{dataset_id,{response_id},0,256});
values=double(block.(response_id).values(:));
assert(numel(values)==256 && abs(mean(values)-256)<1e-12);
fprintf('Octave Script Bridge DEMO: dataset=%s rows=%d mean_response=%.12g\\n',dataset_id,numel(values),mean(values));
''', encoding='utf-8')
    registered = root / 'scripts/registered/inspect_response'
    registered.mkdir(parents=True, exist_ok=True)
    source = registered / 'source.m'
    source.write_bytes((root / 'scripts/inspect_response.m').read_bytes())
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    (registered / 'script.ini').write_text(
        '[script]\n'
        'id=inspect_response\nname=Inspect response\n'
        'language=Octave\nscope=session\n'
        'description=Read the canonical teaching Dataset through the public Octave bridge.\n'
        'version=1.0.0\nrevision=1\n'
        f'sha256={digest}\n'
        'required_apis=CANONICAL_DATASET_API_v2\n'
        'source_scope=\nsource_id=\nsource_sha256=\n'
        'created_at=\nupdated_at=\nparameter_ids=\n', encoding='utf-8')
    (root / 'metadata/octave_script_ground_truth.txt').write_text(
        'rows=256\nresponse_formula=2*sample_index+1\nmean_response=256\n', encoding='utf-8')
    objective = '''# Experiment objective

Use a user-authored GNU Octave script to discover and read a GX-TXT Dataset through `OCTAVE_SCRIPT_BRIDGE_API_v1`. Compute the mean response and compare it with the exact value 256.
'''
    procedure = '''# Octave Script Bridge experiment

1. Import `raw/octave_script_bridge_demo.csv` as a tabular Dataset. `sample_index` runs from 0 to 255 and `response = 2 × sample_index + 1`.
2. Open **Octave Script**, use the preselected Session script `session:inspect_response`, and inspect its editable source in the Workspace.
3. Run the module. The script discovers `CANONICAL_DATASET_API_v2`, lists and describes the bound Dataset, then reads all 256 response values through the generic bridge.
4. Inspect `analysis/analysis.octave_script/octave_script_run_report.txt` and the run log. Confirm that the script reports a mean response of 256 and the run completed successfully.
5. Edit the script to request only the first 16 rows, predict their mean, and run again. Keep the generated script snapshot with the Session for reproducibility.

These are deterministic synthetic teaching values. The generator package and `metadata/octave_script_ground_truth.txt` document their provenance.
'''
    (root / 'notes/experiment/objective.md').write_text(objective, encoding='utf-8')
    (root / 'notes/experiment/procedure.md').write_text(procedure, encoding='utf-8')
    (root / 'STUDENT_GUIDE.md').write_text(objective + '\n' + procedure, encoding='utf-8')
    configure(root, 'octave_script_bridge', [dict(
        source='raw/octave_script_bridge_demo.csv', id='octave_script.source',
        kind='table.generic', roles={'sample_index': 'independent', 'response': 'measured'},
    )], [dict(id='analysis.octave_script', sources={'primary': 'octave_script.source'},
             config={'registered_script': 'session:inspect_response',
                     'source_mode': 'registered_script',
                     'required_apis': 'CANONICAL_DATASET_API_v2'})],
              'Octave Script Bridge canonical Dataset demo')
    print('Generated 256 Octave Script Bridge teaching rows')


if __name__ == '__main__':
    main()
