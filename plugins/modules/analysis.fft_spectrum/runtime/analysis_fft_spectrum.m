% GX-TXT Standard Module API v1 - FFT Spectrum & Error Analysis launcher
% SPDX-License-Identifier: GPL-3.0-or-later

this_file=mfilename('fullpath');
runtime_dir=fileparts(this_file);
module_dir=fileparts(runtime_dir);
modules_dir=fileparts(module_dir);
plugins_dir=fileparts(modules_dir);
package_root=fileparts(plugins_dir);

addpath(runtime_dir);
addpath(fullfile(package_root,'core','octave'));
addpath(fullfile(package_root,'core','octave','analysis'));
addpath(fullfile(package_root,'core','octave','graphics'));
addpath(fullfile(package_root,'core','octave','io'));
addpath(fullfile(package_root,'core','octave','units'));
addpath(fullfile(package_root,'core','octave','util'));

if(exist('analysis_fft_spectrum_main','file')!=2)
  error('analysis.fft_spectrum: implementation missing');
endif
analysis_fft_spectrum_main(argv());
