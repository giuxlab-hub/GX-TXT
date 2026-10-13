% GX-TXT Standard Module API v1 launcher - Fractional-Octave Band Analysis
% SPDX-License-Identifier: GPL-3.0-or-later
this_file=mfilename('fullpath');runtime_dir=fileparts(this_file);module_dir=fileparts(runtime_dir);modules_dir=fileparts(module_dir);plugins_dir=fileparts(modules_dir);package_root=fileparts(plugins_dir);
addpath(runtime_dir);for d={'analysis','graphics','io','units','util'},addpath(fullfile(package_root,'core','octave',d{1}));endfor
if(exist('analysis_fractional_octave_spectrum_main','file')!=2),error('analysis.fractional_octave_spectrum: implementation missing');endif
analysis_fractional_octave_spectrum_main(argv());
