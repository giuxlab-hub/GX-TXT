% GX-TXT Standard Module API v1 - Replicate Curve Analysis cache-only rerender launcher
% SPDX-License-Identifier: GPL-3.0-or-later
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
this_file=mfilename('fullpath');
runtime_dir=fileparts(this_file);
module_dir=fileparts(runtime_dir);
modules_dir=fileparts(module_dir);
plugins_dir=fileparts(modules_dir);
package_root=fileparts(plugins_dir);
addpath(runtime_dir);
addpath(fullfile(package_root,'core','octave'));
addpath(fullfile(package_root,'core','octave','graphics'));
addpath(fullfile(package_root,'core','octave','io'));
addpath(fullfile(package_root,'core','octave','util'));
addpath(fullfile(package_root,'core','octave','units'));
if(exist('curve_replicate_rerender_main','file')!=2)
  error('curve.replicate_analysis rerender: implementation missing');
endif
curve_replicate_rerender_main(argv());
