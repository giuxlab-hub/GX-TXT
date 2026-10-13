% GX-TXT analysis.xas.normalize standard_octave entrypoint.
% SPDX-License-Identifier: GPL-3.0-or-later
this_file=mfilename('fullpath');runtime_dir=fileparts(this_file);module_dir=fileparts(runtime_dir);modules_dir=fileparts(module_dir);plugins_dir=fileparts(modules_dir);framework_root=fileparts(plugins_dir);
addpath(runtime_dir);addpath(fullfile(framework_root,'core','octave'));addpath(fullfile(framework_root,'core','octave','analysis'));addpath(fullfile(framework_root,'core','octave','io'));addpath(fullfile(framework_root,'core','octave','units'));addpath(fullfile(framework_root,'core','octave','util'));
analysis_xas_normalize_main(argv(),framework_root);
