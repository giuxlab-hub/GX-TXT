% GX-TXT Standard Module API v1 rerender launcher.
% SPDX-License-Identifier: GPL-3.0-or-later
runtime_dir=fileparts(mfilename('fullpath'));
module_dir=fileparts(runtime_dir);
package_root=fileparts(fileparts(fileparts(module_dir)));
addpath(runtime_dir);
for d={'analysis','cache','graphics','io','units','util'}
  addpath(fullfile(package_root,'core','octave',d{1}));
endfor
demo_visualization_surface3d_rerender_main(argv());
