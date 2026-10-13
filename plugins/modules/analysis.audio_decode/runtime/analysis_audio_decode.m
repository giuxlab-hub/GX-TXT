% GX-TXT Standard Module API v1 - Audio decode (audio.waveform -> timeseries.table) launcher
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
addpath(fullfile(package_root,'core','octave','io'));
addpath(fullfile(package_root,'core','octave','units'));
addpath(fullfile(package_root,'core','octave','util'));

if(exist('analysis_audio_decode_main','file')!=2)
  error('analysis.audio_decode: implementation missing');
endif
analysis_audio_decode_main(argv());
