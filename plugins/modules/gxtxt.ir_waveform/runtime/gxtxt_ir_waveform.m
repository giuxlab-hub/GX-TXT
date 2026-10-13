% GX-TXT Standard Module API v1 - IR waveform analysis launcher
% SPDX-License-Identifier: GPL-3.0-or-later
thisdir = fileparts(mfilename('fullpath'));
addpath(thisdir);
package_root = fileparts(fileparts(fileparts(fileparts(thisdir))));
addpath(fullfile(package_root,'core','octave','graphics'));
addpath(fullfile(package_root,'core','octave','io'));
addpath(fullfile(package_root,'core','octave','util'));
gxtxt_ir_waveform_main(argv());
