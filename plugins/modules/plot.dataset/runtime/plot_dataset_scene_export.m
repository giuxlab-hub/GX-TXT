% Plot Dataset interactive scene export. Prepared Plot Dataset values are the
% scientific interpretation; VTP is only a rebuildable display artifact.
% SPDX-License-Identifier: GPL-3.0-or-later
this_file = mfilename('fullpath');
runtime_dir = fileparts(this_file);
package_root = fileparts(fileparts(fileparts(fileparts(runtime_dir))));
addpath(runtime_dir);
for directory = {'analysis', 'graphics', 'io', 'units', 'util', 'cache'}
  addpath(fullfile(package_root, 'core', 'octave', directory{1}));
endfor
args = argv();
if (numel(args) != 4), error('usage: plot_dataset_scene_export.m <prepared-render-cache.mat> <new-output-dir> <point-order> <contour-levels>'); endif
cache_path = args{1}; output_dir = args{2};
point_order = args{3}; contour_levels = str2double(args{4});
if (!any(strcmp(point_order,{'dataset_order','sort_x'})) || !isfinite(contour_levels) ||
    contour_levels<2 || contour_levels>1000 || contour_levels!=fix(contour_levels))
  error('plot.dataset interactive: invalid point order or contour level count');
endif
if (exist(output_dir, 'file') != 0), error('interactive scene output directory already exists'); endif
S = load(cache_path);
if (!isfield(S, 'cache') || !isfield(S.cache, 'module') || !isfield(S.cache.module, 'plot3d'))
  error('plot.dataset interactive: prepared 3D cache is unavailable');
endif
P = S.cache.module.plot3d;
if (!isfield(P, 'groups') || isempty(P.groups)), error('plot.dataset interactive: no prepared 3D groups'); endif
mkdir(output_dir);
for g = 1:numel(P.groups)
  group = P.groups(g);
  [xyz, scalar, verts, lines, polys, primitive] = pd_scene_group(P, group, point_order, contour_levels);
  if (rows(xyz) > 2000000), error('plot.dataset interactive: scene group exceeds 2 million display points'); endif
  path = fullfile(output_dir, sprintf('scene_%04d.vtp', g));
  pd_scene_write_vtp(path, xyz, scalar, verts, lines, polys);
  printf('scene_group=%d primitive=%s points=%d cells=%d path=%s\n', g, primitive, rows(xyz), rows(verts)+numel(lines)+rows(polys), path);
endfor
