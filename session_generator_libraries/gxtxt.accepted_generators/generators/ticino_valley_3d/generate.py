#!/usr/bin/env python3
"""Complete the copied Ticino source template as a runnable GX-TXT Session."""
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse
from pathlib import Path

from session_recipe import configure


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--target-session', required=True)
    parser.add_argument('--library-id')
    parser.add_argument('--generator-id')
    root = Path(parser.parse_args().target_session)
    datasets = [
        dict(source='raw/ticino_valley_grid.csv', id='ticino_valley_grid',
             kind='table.generic', units={'easting_m': 'm', 'northing_m': 'm',
                                          'x_km': 'km', 'y_km': 'km', 'elevation_m': 'm',
                                          'population_density_km2': '1/km^2'}),
        dict(source='raw/ticino_river_centerline.csv', id='ticino_river_centerline',
             kind='table.generic', units={'easting_m': 'm', 'northing_m': 'm',
                                          'x_km': 'km', 'y_km': 'km', 'chainage_km': 'km'}),
        dict(source='raw/ticino_valley_settlements.csv', id='ticino_valley_settlements',
             kind='table.generic', units={'easting_m': 'm', 'northing_m': 'm',
                                          'x_km': 'km', 'y_km': 'km', 'ground_elevation_m': 'm'}),
        dict(source='raw/ticino_hydraulic_demo.csv', id='ticino_hydraulic_demo',
             kind='table.generic', units={'easting_m': 'm', 'northing_m': 'm',
                                          'x_km': 'km', 'y_km': 'km', 'chainage_km': 'km'}),
    ]
    configure(root, 'ticino_valley_3d', datasets, [
        dict(id='demo.geospatial.ticino_valley_3d',
             sources={'primary': 'ticino_valley_grid',
                      'river': 'ticino_river_centerline',
                      'settlements': 'ticino_valley_settlements',
                      'hydraulic': 'ticino_hydraulic_demo'}),
        dict(id='plot.dataset', run=False),
    ], 'Ticino Valley cartography and synthetic hydraulics')
    print('Configured four canonical Ticino Dataset sources and nine 3-D graphs.')


if __name__ == '__main__':
    main()
