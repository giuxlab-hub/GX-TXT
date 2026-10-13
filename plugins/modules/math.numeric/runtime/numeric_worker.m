% math.numeric private one-shot worker used by NUMERIC_API_v1 Tcl binding.
% SPDX-License-Identifier: GPL-3.0-or-later
this_file=mfilename('fullpath');
runtime_dir=fileparts(this_file);
module_dir=fileparts(runtime_dir);
modules_dir=fileparts(module_dir);
plugins_dir=fileparts(modules_dir);
package_root=fileparts(plugins_dir);
addpath(runtime_dir);
addpath(fullfile(module_dir,'api','octave'));
addpath(fullfile(package_root,'core','octave'));
addpath(fullfile(package_root,'core','octave','analysis'));
addpath(fullfile(package_root,'core','octave','io'));
addpath(fullfile(package_root,'core','octave','units'));
addpath(fullfile(package_root,'core','octave','util'));
gxtxt_numeric_worker_main(argv());
