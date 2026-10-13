% GX-TXT Standard Module API v1 launcher - Envelope Spectrum & Demodulation Analysis
% SPDX-License-Identifier: GPL-3.0-or-later
this_file=mfilename('fullpath');runtime_dir=fileparts(this_file);module_dir=fileparts(runtime_dir);modules_dir=fileparts(module_dir);plugins_dir=fileparts(modules_dir);package_root=fileparts(plugins_dir);
addpath(runtime_dir);for d={'analysis','io','units','util'},addpath(fullfile(package_root,'core','octave',d{1}));endfor
analysis_envelope_spectrum_main(argv());
