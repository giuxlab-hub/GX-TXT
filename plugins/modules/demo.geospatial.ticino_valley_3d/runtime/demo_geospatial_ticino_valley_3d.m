% External GX-TXT module launcher.
% SPDX-License-Identifier: GPL-3.0-or-later
runtime_dir=fileparts(mfilename('fullpath'));
module_dir=fileparts(runtime_dir);
framework_root=fileparts(fileparts(fileparts(module_dir)));
addpath(runtime_dir);
for part={'analysis','cache','graphics','io','units','util'}
  addpath(fullfile(framework_root,'core','octave',part{1}));
endfor
demo_geospatial_ticino_valley_3d_main(argv());
