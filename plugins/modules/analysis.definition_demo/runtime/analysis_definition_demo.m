% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT Scientific Analysis Definition API v1 reference module.
thisdir=fileparts(mfilename('fullpath'));
root=fileparts(fileparts(fileparts(fileparts(thisdir))));
addpath(fullfile(root,'core','octave','analysis'));
addpath(fullfile(root,'core','octave','io'));
addpath(fullfile(root,'core','octave','graphics'));
addpath(fullfile(root,'core','octave','cache'));
addpath(fullfile(root,'core','octave','util'));
args=argv(); config_path='';
for k=1:numel(args)-1,if(strcmp(args{k},'--config')),config_path=args{k+1};break;endif;endfor
if(isempty(config_path)),error('analysis.definition_demo: --config is required');endif
cfg=gxtxt_ini_read(config_path);
outdir=gxtxt_ini_get(cfg,'runtime.output_dir','');
source_path=gxtxt_ini_get(cfg,'dataset.path','');
def_path=gxtxt_ini_get(cfg,'analysis_definition.analysis_definition_id.descriptor_path','');
if(isempty(outdir)||isempty(source_path)||isempty(def_path)),error('analysis.definition_demo: incomplete runtime configuration');endif
gxtxt_progress_start('analysis_definition','Executing Scientific Analysis API definition','indeterminate');
sources=struct();sources.primary=source_path;opts=struct('runtime_cfg',cfg);
r=gxtxt_analysis_run(def_path,sources,outdir,opts);
meta=gxtxt_render_cache_standard_meta('analysis.definition_demo','1',def_path,sources,r.context.parameters);cache=gxtxt_render_cache_from_analysis(r,meta);gxtxt_render_cache_save(outdir,cache);
gxtxt_progress_complete('done','Scientific Analysis API demo completed');
fprintf('[analysis.definition_demo] definition=%s rows=%d\n',r.definition_id,r.context.row_count);
