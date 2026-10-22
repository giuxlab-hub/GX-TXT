#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Original SI input specifications only. Does not load an EM module or solver."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil

from session_recipe import configure

COLUMNS = ['model_id', 'kind', 'formulation', 'half_width_m', 'height_m', 'mesh_size_m',
           'radius_m', 'current_density_A_m2', 'mu_r', 'voltage_V', 'eps_r']
ROWS = [
    ['magnetic_practice', 'magnetostatic_2d', 'planar_2d', '0.02', '0.04', '0.001',
     '0.005', '1000000', '1', '10', '1'],
    ['electric_practice', 'electrostatic_2d', 'planar_2d', '0.01', '0.01', '0.001',
     '0.002', '1000000', '1', '10', '2'],
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target-session', required=True)
    parser.add_argument('--library-id')
    parser.add_argument('--generator-id')
    args = parser.parse_args()
    root = Path(args.target_session).resolve()
    if not root.is_dir():
        raise ValueError('The normal host must supply an existing fresh target Session')
    source = root/'raw/planar_em_parameters.csv'
    if source.exists() or (root/'STUDENT_GUIDE.md').exists():
        raise FileExistsError('Refusing existing practice sources')
    (root/'raw').mkdir(exist_ok=True)
    (root/'reference').mkdir(exist_ok=True)
    with source.open('x', newline='', encoding='utf-8') as stream:
        writer = csv.writer(stream, lineterminator='\n')
        writer.writerow(COLUMNS)
        writer.writerows(ROWS)
    truth = {
        'reference_kind': 'independent analytic input specification; no simulated observations',
        'license': 'GPL-3.0-or-later; original synthetic source parameters',
        'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'parameter_contract': 'Existing ELECTROMAGNETIC_SIMULATION_API_v1 model field names; table is an instruction source, not a saved model',
        'electric': {'boundary': 'V(-half_width)=0; V(+half_width)=10 V; top and bottom insulating',
                     'full_width_m': 0.02, 'height_m': 0.01, 'eps_r': 2,
                     'exact_V': '10*(x+0.01)/0.02', 'exact_Ex_V_per_m': -500,
                     'exact_Ey_V_per_m': 0, 'at_x_0_V': 5,
                     'qualification': 'Exact only for this homogeneous rectangle and its stated ideal boundaries; no finite-plate fringing or 3D capacitance'},
        'magnetic': {'boundary': 'Az=0 on finite outer rectangle; air mu_r=1; conductor mu_r=1',
                     'radius_m': 0.005, 'current_density_A_per_m2': 1000000,
                     'total_current_formula_A': '1000000*pi*0.005^2 = 25*pi',
                     'mu0_comparison_H_per_m': '4*pi*1e-7, matching existing linear teaching model',
                     'unbounded_Btheta_T': {'r_less_than_a': 'mu0*Jz*r/2',
                                            'r_at_least_a': 'mu0*I/(2*pi*r)'},
                     'unbounded_at_r_0_01_m_T': '0.0005*pi',
                     'qualification': 'Unbounded-conductor comparison only. Finite rectangular Az=0 boundary, polygonal mesh and current/area approximation affect actual FEM output. No asserted finite-domain error tolerance.'},
        'exercise_policy': 'Enter parameters through existing Viewer; Validate does not solve. An independently authorized later Run FEM must create genuine Jobs, verified nodes/cells and published canonical fields.',
        'excluded': ['saved gxtxt.em_model Workspace', 'mesh', 'solver outputs', 'canonical EM fields', 'Jobs', 'precomputed acceptance results'],
    }
    (root/'reference/em_truth.json').write_text(json.dumps(truth, indent=2)+'\n', encoding='utf-8')
    units = {'half_width_m': 'm', 'height_m': 'm', 'mesh_size_m': 'm', 'radius_m': 'm',
             'current_density_A_m2': 'A/m^2', 'mu_r': '1', 'voltage_V': 'V', 'eps_r': '1'}
    configure(root, 'planar_em_practice', [dict(source='raw/planar_em_parameters.csv',
              id='em.practice.parameters', kind='table.generic', units=units,
              roles={name: 'independent' for name in COLUMNS},
              variable_ids={name: name for name in COLUMNS})], [], 'Independent planar EM practice inputs')
    shutil.copyfile(Path(__file__).with_name('STUDENT_GUIDE.md'), root/'STUDENT_GUIDE.md')
    print('Generated SI parameter instructions and independent references; no EM model, Job or results')


if __name__ == '__main__':
    main()
