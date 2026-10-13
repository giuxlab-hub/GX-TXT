#!/usr/bin/env python3
"""Copy reproducible 2D21 tagged-curve fixtures into a teaching Session."""
import argparse
import csv
from pathlib import Path
import shutil
from session_recipe import configure


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target-session', required=True)
    parser.add_argument('--library-id')
    parser.add_argument('--generator-id')
    root = Path(parser.parse_args().target_session)
    source = Path(__file__).resolve().parent / 'data'
    (root / 'raw').mkdir(parents=True, exist_ok=True)
    (root / 'notes/experiment').mkdir(parents=True, exist_ok=True)
    for index in (1, 2, 3):
        name = f'2D21-cal{index}-tagged-shuffled.csv'
        shutil.copyfile(source / name, root / 'raw' / name)
    with (root / 'raw/2D21-combined-tagged.csv').open('w', newline='', encoding='utf-8') as output:
        writer = csv.writer(output)
        writer.writerow(('Vg1_V', 'Ib_mA', 'Ig1_mA', 'replicate_id'))
        for index in (1, 2, 3):
            with (root / 'raw' / f'2D21-cal{index}-tagged-shuffled.csv').open(
                    newline='', encoding='utf-8') as input_file:
                reader = csv.DictReader(input_file)
                for row in reader:
                    writer.writerow((row['Vg1_V'], row['Ib_mA'], row['Ig1_mA'],
                                     f"cal{index}.{row['replicate_id']}"))
    (root / 'raw/2d21_tagged_sources.lst').write_text(
        'source2\t2D21-cal2-tagged-shuffled.csv\n'
        'source3\t2D21-cal3-tagged-shuffled.csv\n', encoding='utf-8')
    objective = '''# Experiment objective

Use three independently tagged 2D21 characteristic-curve sources to estimate a family-wise consensus, replicate variation and an uncertainty profile without fitting a physical model. The canonical input combines all three originals and prefixes replicate IDs with their calibration source.
'''
    procedure = '''# Replicate curve analysis experiment

1. Inspect the three original `raw/2D21-cal*-tagged-shuffled.csv` files and their deterministic combined canonical Dataset. Bind `Vg1_V` as X, `Ib_mA` as Family, `Ig1_mA` as Y, and `replicate_id` as the replicate label.
2. Run **Replicate Curve Analysis** using the selected canonical Dataset and Automatic replicate handling.
3. Run the analysis with a reference output grid of 73 points. Inspect the consensus CSV, uncertainty profile, replicate statistics and four persistent graphs.
4. Compare labeled trace variation across source files. Explain why the module does not fit a physical 2D21 model, and why row shuffling cannot change the result for tagged replicates.

The CSVs are the GPL-licensed tagged/shuffled reference fixtures distributed with `curve.replicate_analysis`. This package preserves them byte for byte and lists both additional sources explicitly.
'''
    (root / 'notes/experiment/objective.md').write_text(objective, encoding='utf-8')
    (root / 'notes/experiment/procedure.md').write_text(procedure, encoding='utf-8')
    (root / 'STUDENT_GUIDE.md').write_text(objective + '\n' + procedure, encoding='utf-8')
    configure(root, 'replicate_curve_analysis', [dict(
        source='raw/2D21-combined-tagged.csv', id='curve_family.primary',
        kind='curve_family.table',
        units={'Vg1_V': 'V', 'Ib_mA': 'mA', 'Ig1_mA': 'mA'},
        roles={'Vg1_V': 'independent', 'Ib_mA': 'family',
               'Ig1_mA': 'measured', 'replicate_id': 'replicate'},
    )], [dict(id='curve.replicate_analysis',
             bindings={'x': 'Vg1_V', 'family': 'Ib_mA', 'y': 'Ig1_mA',
                       'replicate': 'replicate_id'},
             config={'dataset_id': 'curve_family.primary',
                     'include_primary_dataset': '1', 'replicate_handling': 'automatic',
                     'fit_output_grid': 'reference_grid', 'fit_output_grid_points': '73'}),
        dict(id='plot.dataset', run=False, sources={'primary': 'curve_family.primary'})],
              'Three tagged 2D21 curve replicates')
    print('Generated three tagged 2D21 replicate-curve source files')


if __name__ == '__main__':
    main()
