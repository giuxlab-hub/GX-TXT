% External GX-TXT module launcher.
% SPDX-License-Identifier: GPL-3.0-or-later
runtime_dir=fileparts(mfilename('fullpath'));
module_dir=fileparts(runtime_dir);
package_root=fileparts(fileparts(fileparts(module_dir)));
addpath(runtime_dir);
for d={'analysis','graphics','io','util'}
  addpath(fullfile(package_root,'core','octave',d{1}));
endfor
numeric_descriptor=gxtxt_ini_read(fullfile(package_root,'plugins','modules','math.numeric','module.ini'));
numeric_entry=gxtxt_ini_get(numeric_descriptor,'public_api.NUMERIC_API_v1.octave_entrypoint','');
if(isempty(numeric_entry)), error('demo.numeric.nonlinear_fit: NUMERIC_API_v1 is unavailable'); endif
addpath(fileparts(fullfile(package_root,'plugins','modules','math.numeric',numeric_entry)));
demo_numeric_nonlinear_fit_main(argv());
