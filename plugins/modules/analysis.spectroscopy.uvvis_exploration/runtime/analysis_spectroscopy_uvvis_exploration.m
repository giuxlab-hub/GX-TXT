% GX-TXT UV/Vis exploration: public Tcl science pipeline plus cached graph.
% SPDX-License-Identifier: GPL-3.0-or-later
args=argv();config_path='';
for i=1:(numel(args)-1)
  if(strcmp(args{i},'--config')),config_path=args{i+1};break;endif
endfor
if(isempty(config_path)),error('UV/Vis exploration: --config is required');endif
this_file=mfilename('fullpath');runtime_dir=fileparts(this_file);addpath(runtime_dir);
module_dir=fileparts(runtime_dir);modules_dir=fileparts(module_dir);
plugins_dir=fileparts(modules_dir);framework_root=fileparts(plugins_dir);
addpath(fullfile(framework_root,'core','octave'));
addpath(fullfile(framework_root,'core','octave','io'));
addpath(fullfile(framework_root,'core','octave','util'));
addpath(fullfile(framework_root,'core','octave','graphics'));
bridge=fullfile(framework_root,'core','tcl','analysis_tcl_bridge_v1.tcl');
runner=fullfile(runtime_dir,'uvvis_exploration_pipeline.tcl');
cmd=sprintf('tclsh %s %s %s %s',gxtxt_shell_quote_v1(bridge), ...
  gxtxt_shell_quote_v1(framework_root),gxtxt_shell_quote_v1(runner), ...
  gxtxt_shell_quote_v1(config_path));
[status,output]=system(cmd);
if(status!=0),error('UV/Vis exploration pipeline failed: %s',output);endif
fprintf('%s',output);
cfg=gxtxt_ini_read(config_path);
output_dir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
mode=strtrim(gxtxt_ini_get(cfg,'config.workflow','single_spectrum'));
wave=str2double(gxtxt_ini_get(cfg,'config.selected_wavelength_nm','322'));
if(!isfinite(wave)),error('UV/Vis exploration wavelength missing');endif
unit='';
if(strcmp(mode,'single_spectrum'))
  A=dlmread(fullfile(output_dir,'original_plot.tsv'),'\t');
  B=dlmread(fullfile(output_dir,'processed_plot.tsv'),'\t');
  if(rows(A)<8 || rows(B)!=rows(A) || columns(A)!=2 || columns(B)!=2),error('UV/Vis single cache invalid');endif
elseif(strcmp(mode,'time_series'))
  A=dlmread(fullfile(output_dir,'family_plot.tsv'),'\t');
  B=dlmread(fullfile(output_dir,'time_plot.tsv'),'\t');
  if(rows(A)<8 || rows(B)<2 || columns(A)!=4 || columns(B)!=2),error('UV/Vis time cache invalid');endif
  unit=strtrim(fileread(fullfile(output_dir,'time_unit.txt')));
  if(isempty(unit)),error('UV/Vis time unit missing');endif
else
  error('UV/Vis exploration mode invalid');
endif
save('-mat7-binary',fullfile(output_dir,'render_cache.mat'),'mode','A','B','wave','unit');
analysis_spectroscopy_uvvis_exploration_provider(mode,unit,output_dir,cfg);
