#!/usr/bin/env python3
"""Generate two chronological segments and table-transform instructions."""
import argparse
import csv
from pathlib import Path
from session_recipe import configure


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target-session', required=True)
    parser.add_argument('--library-id')
    parser.add_argument('--generator-id')
    root = Path(parser.parse_args().target_session)
    for name in ('raw', 'metadata', 'notes/experiment'):
        (root / name).mkdir(parents=True, exist_ok=True)
    for label, start in (('early', 0), ('late', 200)):
        with (root / f'raw/{label}_segment.csv').open('w', encoding='utf-8', newline='') as stream:
            writer = csv.writer(stream)
            writer.writerow(('timestamp_s', 'time_s', 'value_V'))
            for i in range(100):
                timestamp = start + i
                writer.writerow((timestamp, i, f'{1.0 + 0.01 * timestamp:.12g}'))
    (root / 'metadata/table_transform_ground_truth.txt').write_text(
        'early_rows=100\nlate_rows=100\njoined_rows=200\n'
        'joined_first_timestamp_s=0\njoined_last_timestamp_s=299\n'
        'gap_s=101\nselected_interval_s=220..240\nselected_rows=21\n', encoding='utf-8')
    objective = '''# Experiment objective

Join two time-series segments in chronological order, preserving their 101-second gap. Then use Dataset Extract to retain timestamps 220 through 240 without interpolation or source mutation.
'''
    procedure = '''# Sequential Table Join and Dataset Extract experiment

1. Import `raw/late_segment.csv` and `raw/early_segment.csv` as separate `timeseries.table` Datasets. Both have absolute `timestamp_s`, relative `time_s`, and measured `value_V` in V.
2. Enable **Sequential Table Join**. Supply the late segment as primary and add the early segment second to demonstrate that input order is ignored. Keep `timestamp_s` as absolute time and `time_s` as rebuilt relative time; publish `table_joined.source`.
3. Inspect `join_report.txt` and the derived Dataset. It must contain 200 rows, start at timestamp 0, end at 299, and preserve the gap between 99 and 200.
4. Create a Dataset Selection for the joined Dataset with `timestamp_s` from 220 through 240 inclusive. Enable **Dataset Extract**, choose Selected rows and the full variable schema, and publish `table_extract.selected`.
5. Confirm that the extracted Dataset contains exactly 21 rows and the source and joined Datasets remain unchanged. Inspect each Dataset's framework metadata and Markdown provenance note.

The data are deterministic synthetic teaching values. `metadata/table_transform_ground_truth.txt` records the expected row counts and timestamps.
'''
    (root / 'notes/experiment/objective.md').write_text(objective, encoding='utf-8')
    (root / 'notes/experiment/procedure.md').write_text(procedure, encoding='utf-8')
    (root / 'STUDENT_GUIDE.md').write_text(objective + '\n' + procedure, encoding='utf-8')
    datasets = [dict(source=f'raw/{label}_segment.csv', id=f'table_segment.{label}',
                     kind='timeseries.table', units={'timestamp_s': 's', 'time_s': 's', 'value_V': 'V'},
                     roles={'timestamp_s': 'independent', 'time_s': 'independent', 'value_V': 'measured'})
                for label in ('early', 'late')]
    configure(root, 'table_join_extract', datasets, [
        dict(id='sequence.table_join', sources={'primary': 'table_segment.late',
                                                'early_segment': 'table_segment.early'},
             config={'output_dataset_id': 'table_joined.source',
                     'absolute_time_column': 'timestamp_s', 'relative_time_column': 'time_s'}),
        dict(id='dataset.extract', run=False, sources={'primary': 'table_joined.source'},
             allow_derived_source=True,
             config={'row_mode': 'selected', 'column_mode': 'all',
                     'output_dataset_id': 'table_extract.selected'}),
    ], 'Chronological table join and selected-row extract')
    print('Generated two 100-row time-series segments')


if __name__ == '__main__':
    main()
