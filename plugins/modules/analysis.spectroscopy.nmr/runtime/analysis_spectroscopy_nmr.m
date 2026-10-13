% SPDX-License-Identifier: GPL-3.0-or-later
% Standard Analysis runner delegates publication to the public Tcl bridge.
args=argv();config='';
for k=1:(numel(args)-1),if(strcmp(args{k},'--config')),config=args{k+1};break;endif;endfor
if(isempty(config)),error('analysis.spectroscopy.nmr: --config is required');endif
runtime_dir=fileparts(mfilename('fullpath'));module_dir=fileparts(runtime_dir);
framework_root=fileparts(fileparts(fileparts(module_dir)));
bridge=fullfile(framework_root,'core','tcl','analysis_tcl_bridge_v1.tcl');
pipeline=fullfile(runtime_dir,'nmr_pipeline.tcl');
addpath(fullfile(framework_root,'core','octave','util'));
cmd=['tclsh ' gxtxt_shell_quote_v1(bridge) ' ' gxtxt_shell_quote_v1(framework_root) ' ' gxtxt_shell_quote_v1(pipeline) ' ' gxtxt_shell_quote_v1(config)];
[status,output]=system(cmd);
fprintf('%s',output);
if(status~=0),error('analysis.spectroscopy.nmr failed: %s',output);endif
