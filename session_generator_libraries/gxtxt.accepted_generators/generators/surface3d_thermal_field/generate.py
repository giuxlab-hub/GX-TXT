#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse
import csv
import math
from pathlib import Path
from session_recipe import configure


def temperature(x: float, y: float) -> float:
    return (
        293.15
        + 18.0 * math.exp(-(((x + 12.0) ** 2) / (2.0 * 9.0**2) + ((y - 8.0) ** 2) / (2.0 * 12.0**2)))
        + 11.0 * math.exp(-(((x - 16.0) ** 2) / (2.0 * 14.0**2) + ((y + 10.0) ** 2) / (2.0 * 8.0**2)))
        + 0.03 * x
        - 0.02 * y
    )


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument('--target-session', required=True)
    p.add_argument('--library-id')
    p.add_argument('--generator-id')
    args = p.parse_args()
    root = Path(args.target_session)
    raw = root / 'raw'
    metadata = root / 'metadata'
    reference = root / 'reference'
    raw.mkdir(parents=True, exist_ok=True)
    metadata.mkdir(parents=True, exist_ok=True)
    reference.mkdir(parents=True, exist_ok=True)

    xs = [-50.0 + 2.5 * i for i in range(41)]
    ys = [-50.0 + 2.5 * i for i in range(41)]
    rows = []
    for y in ys:  # Y outer loop, X inner loop.
        for x in xs:
            rows.append((x, y, temperature(x, y)))

    csv_path = raw / 'thermal_surface_3d.csv'
    with csv_path.open('w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['x_mm', 'y_mm', 'temperature_K'])
        for x, y, t in rows:
            w.writerow([f'{x:.12g}', f'{y:.12g}', f'{t:.15g}'])

    z = [r[2] for r in rows]
    max_row = max(rows, key=lambda r: r[2])
    equation = ('T(x,y)=293.15+18*exp(-((x+12)^2/(2*9^2)+(y-8)^2/(2*12^2)))'
                '+11*exp(-((x-16)^2/(2*14^2)+(y+10)^2/(2*8^2)))+0.03*x-0.02*y')
    metadata_lines = [
        'data.synthetic=true',
        'demo.type=3d_surface',
        'demo.domain=thermal',
        'grid.type=rectangular',
        'grid.x_points=41',
        'grid.y_points=41',
        'grid.x_min_mm=-50',
        'grid.x_max_mm=50',
        'grid.y_min_mm=-50',
        'grid.y_max_mm=50',
        'grid.spacing_x_mm=2.5',
        'grid.spacing_y_mm=2.5',
        'grid.order=Y outer loop; X inner loop',
        'quantity.name=temperature',
        'quantity.unit=K',
        'model.type=two_gaussian_hotspots_with_linear_gradient',
        f'model.equation={equation}',
    ]
    (metadata / 'thermal_surface_3d.metadata.txt').write_text('\n'.join(metadata_lines) + '\n', encoding='utf-8')

    truth = [
        'GX-TXT 3D Thermal Surface deterministic reference',
        'grid.x_points=41',
        'grid.y_points=41',
        'grid.point_count=1681',
        'grid.x_min_mm=-50',
        'grid.x_max_mm=50',
        'grid.y_min_mm=-50',
        'grid.y_max_mm=50',
        'grid.spacing_x_mm=2.5',
        'grid.spacing_y_mm=2.5',
        'grid.order=Y outer loop; X inner loop',
        f'model.equation={equation}',
        f'temperature.minimum_K={min(z):.15g}',
        f'temperature.maximum_K={max(z):.15g}',
        f'temperature.mean_K={sum(z)/len(z):.15g}',
        f'temperature.maximum_x_mm={max_row[0]:.15g}',
        f'temperature.maximum_y_mm={max_row[1]:.15g}',
    ]
    (reference / 'thermal_surface_truth.txt').write_text('\n'.join(truth) + '\n', encoding='utf-8')
    configure(root, 'surface3d_thermal_field', [dict(
        source='raw/thermal_surface_3d.csv', id='thermal.surface.source',
        kind='table.generic', units={'x_mm': 'mm', 'y_mm': 'mm', 'temperature_K': 'K'},
        roles={'x_mm': 'independent', 'y_mm': 'independent', 'temperature_K': 'measured'},
    )], [dict(id='demo.visualization.surface3d', sources={'primary': 'thermal.surface.source'},
             bindings={'x': 'x_mm', 'y': 'y_mm', 'z': 'temperature_K'}),
         dict(id='plot.dataset', run=False, sources={'primary': 'thermal.surface.source'},
             bindings={'x': 'x_mm', 'y': 'y_mm', 'z': 'temperature_K'})],
              'Deterministic 3-D thermal surface')
    print('Generated deterministic 41 x 41 GX-TXT thermal surface dataset.')


if __name__ == '__main__':
    main()
