% External GX-TXT module launcher.
% SPDX-License-Identifier: GPL-3.0-or-later
this_file=mfilename('fullpath');
runtime_dir=fileparts(this_file);
module_dir=fileparts(runtime_dir);
modules_dir=fileparts(module_dir);
plugins_dir=fileparts(modules_dir);
package_root=fileparts(plugins_dir);
addpath(runtime_dir);
addpath(fullfile(package_root,'core','octave'));
for d={'analysis','graphics','io','units','util'}
  addpath(fullfile(package_root,'core','octave',d{1}));
endfor
numeric_descriptor=gxtxt_ini_read(fullfile(package_root,'plugins','modules','math.numeric','module.ini'));
numeric_entry=gxtxt_ini_get(numeric_descriptor,'public_api.NUMERIC_API_v1.octave_entrypoint','');
if(isempty(numeric_entry)), error('demo.environmental.levoglucosan_campaign: NUMERIC_API_v1 is unavailable'); endif
addpath(fileparts(fullfile(package_root,'plugins','modules','math.numeric',numeric_entry)));
demo_environmental_levoglucosan_campaign_main(argv());
