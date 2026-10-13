#!/usr/bin/env python3
"""Public CORE transport for standard-module Dataset Transform execution.

The JSON request contains logical Dataset/Variable IDs and a Transform
Manifest. This executable owns framework bootstrap and publication; consumers
never inspect canonical payload paths or construct their own Dataset writers.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse
import json
from pathlib import Path
import sys
from gxtxt_script_bridge_server import Host
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from script_bindings.dataset_transform import invoke

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime', required=True)
    parser.add_argument('--request', required=True)
    parser.add_argument('--result', required=True)
    args = parser.parse_args()
    host = Host(Path(args.runtime))
    try:
        manifest = json.loads(Path(args.request).read_text(encoding='utf-8'))
        if 'selection_id' in manifest:
            selection = manifest.pop('selection_id')
            operation = manifest.pop('selection_operation', 'keep')
            trace = manifest.pop('selection_trace', False)
            members = host.as_list(host.call('::GX::datasetSelectionMembers', host.session, selection, operation))
            sources = []
            for value in members:
                source = host.as_dict(value)
                for key in ('rows', 'variable_ids'):
                    if key in source: source[key] = host.as_list(source[key])
                for key in ('row_filters', 'selection_filters'):
                    if key in source: source[key] = [host.as_dict(v) for v in host.as_list(source[key])]
                if trace:
                    if not source.get('y_variable_id'):
                        raise ValueError('Trace extraction requires an X/Y binding for every Selection member')
                    source['variable_ids'] = list(dict.fromkeys([source['x_variable_id'], source['y_variable_id']]))
                sources.append(source)
            manifest['sources'] = sources
        result = invoke(host, 'execute', [manifest])
        destination = Path(args.result)
        temporary = destination.with_name(destination.name + '.tmp')
        temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
        temporary.replace(destination)
        print('Dataset Transform published ' + str(result.get('dataset_id', result.get('dataset_ids'))))
    finally:
        host.cleanup()

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
