#!/usr/bin/env python3
"""Copy a real triode family fixture and model-validation instructions."""
import argparse
from pathlib import Path
import shutil
from session_recipe import configure


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target-session', required=True)
    parser.add_argument('--library-id')
    parser.add_argument('--generator-id')
    root = Path(parser.parse_args().target_session)
    (root / 'raw').mkdir(parents=True, exist_ok=True)
    (root / 'notes/experiment').mkdir(parents=True, exist_ok=True)
    shutil.copyfile(Path(__file__).resolve().parent / 'data/real_training_reference_439.csv',
                    root / 'raw/real_training_reference_439.csv')
    objective = '''# Experiment objective

Fit the Koren triode model to a 439-point 6BX7 characteristic-curve family. Then export the fitted parameter set through the model's SPICE adapter and compare an ngspice sweep with the measured family.
'''
    procedure = '''# Triode model fit and SPICE verification experiment

1. Import `raw/real_training_reference_439.csv` as a `curve_family.table` Dataset. Bind `X_V` (plate voltage) as X, `Vg_V` (grid voltage) as Family, and `Y_mA` (plate current) as Y.
2. Enable **Curve Family Fitting** with model `triode.koren_v1`, Fit mode and the automatic numerical solver. Run it and inspect `fit_parameters.csv`, the fit/domain metrics, predicted curves and persistent residual graphs.
3. Enable **SPICE Build and Validation** with the same model, use the fitted parameter CSV, the fitted model-domain sidecar when present, and this canonical curve family as validation data. Run ngspice verification and inspect the generated library, sweep files, metrics and Plot.dataset graphs.
4. Compare fitted and measured currents by family. Explain which discrepancies arise from model fit and which arise from the SPICE adapter. Preserve the parameter file and model-domain sidecar as scientific provenance.

The 439-point input is the GPL-licensed 6BX7 real-training reference fixture distributed with `curvefit.family_global`. This generator preserves it byte for byte; it is an example measurement reference, not newly simulated data.
'''
    (root / 'notes/experiment/objective.md').write_text(objective, encoding='utf-8')
    (root / 'notes/experiment/procedure.md').write_text(procedure, encoding='utf-8')
    (root / 'STUDENT_GUIDE.md').write_text(objective + '\n' + procedure, encoding='utf-8')
    configure(root, 'triode_fit_spice', [dict(
        source='raw/real_training_reference_439.csv', id='triode.family.source',
        kind='curve_family.table',
        units={'X_V': 'V', 'Vg_V': 'V', 'Y_mA': 'mA'},
        roles={'X_V': 'independent', 'Vg_V': 'family', 'Y_mA': 'measured'},
    )], [
        dict(id='curvefit.family_global',
             bindings={'x': 'X_V', 'family': 'Vg_V', 'y': 'Y_mA'},
             config={'dataset_id': 'triode.family.source', 'model_id': 'triode.koren_v1',
                     'operation_mode': 'fit', 'solver': 'auto', 'max_iter': '2000',
                     'tolerance': '1e-8'}),
        dict(id='model.spice_build_validate', run=False,
             bindings={'x': 'X_V', 'family': 'Vg_V', 'y': 'Y_mA'},
             config={'dataset_id': 'triode.family.source', 'model_id': 'triode.koren_v1',
                     'validation_dataset_role': 'training_reused',
                     'parameter_file': '../curvefit.family_global/fit_parameters.csv',
                     'domain_file': '../curvefit.family_global/fit_domain.csv',
                     'ngspice_executable': 'ngspice'}),
        dict(id='plot.dataset', run=False, sources={'primary': 'triode.family.source'}),
    ], 'Real 6BX7 triode fit and SPICE validation')
    print('Generated 439-point triode family training reference')


if __name__ == '__main__':
    main()
