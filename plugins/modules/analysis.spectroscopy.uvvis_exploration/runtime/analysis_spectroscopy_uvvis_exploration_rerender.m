% GX-TXT UV/Vis exploration cache-only Plot Variant renderer.
% SPDX-License-Identifier: GPL-3.0-or-later
args=argv();config_path='';
for i=1:(numel(args)-1)
  if(strcmp(args{i},'--config')),config_path=args{i+1};break;endif
endfor
if(isempty(config_path)),error('UV/Vis exploration rerender: --config required');endif
this_file=mfilename('fullpath');runtime_dir=fileparts(this_file);addpath(runtime_dir);
module_dir=fileparts(runtime_dir);modules_dir=fileparts(module_dir);
plugins_dir=fileparts(modules_dir);framework_root=fileparts(plugins_dir);
addpath(fullfile(framework_root,'core','octave'));
addpath(fullfile(framework_root,'core','octave','io'));
addpath(fullfile(framework_root,'core','octave','util'));
addpath(fullfile(framework_root,'core','octave','graphics'));
cfg=gxtxt_ini_read(config_path);
output_dir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
cache_path=strtrim(gxtxt_ini_get(cfg,'render_cache_api.path',fullfile(output_dir,'render_cache.mat')));
if(exist(cache_path,'file')!=2),error('UV/Vis exploration rerender cache missing');endif
cached=load(cache_path);
for key={'mode','A','B','wave','unit'}
  if(!isfield(cached,key{1})),error('UV/Vis exploration cache field missing');endif
endfor
analysis_spectroscopy_uvvis_exploration_provider(cached.mode,cached.unit,output_dir,cfg);
