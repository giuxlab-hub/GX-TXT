% Public read-only Preview export. Reuse normal scientific rendering authority.
this_file=mfilename('fullpath');runtime_dir=fileparts(this_file);
root=fileparts(fileparts(fileparts(fileparts(runtime_dir))));addpath(runtime_dir);
for d={'analysis','graphics','io','units','util','cache'},addpath(fullfile(root,'core','octave',d{1}));endfor
args=argv();if(!any(numel(args)==[3 4])),error('Usage: preview_export prepared-cache runtime-ini new-directory [source-expectation]');endif
S=load(args{1});cfg=gxtxt_ini_read(args{2});
if(!isfield(S,'cache')||!isfield(S.cache.module,'plot3d')),error('Original prepared 3D cache unavailable; render graph first');endif
P=S.cache.module.plot3d;
if(numel(args)==4)
  expected=gxtxt_ini_read(args{4});
  for i=1:2
    key={'source.cache_sha256','source.runtime_sha256'};
    if(!strcmp(gxtxt_render_cache_file_fingerprint(args{i}),gxtxt_ini_get(expected,key{i},'')))
      error('Scientific preparation changed before Preview export');
    endif
  endfor
  canonical=gxtxt_ini_get(expected,'source.path','');
  source_sha=gxtxt_render_cache_file_fingerprint(canonical);
  if(!strcmp(source_sha,gxtxt_ini_get(expected,'source.sha256',''))),error('Canonical Dataset changed before Preview export');endif
  % Cache provenance includes the historical path string. Verify that same
  % identity against the current canonical bytes without following an old
  % absolute path in a copied Session.
  original=gxtxt_ini_get(cfg,'analysis_source.primary.path',gxtxt_ini_get(cfg,'dataset.path',''));
  source_fp=gxtxt_render_cache_fingerprint({'GXTXT_SOURCE_MAP_V1','primary',original,source_sha});
  report=gxtxt_render_cache_validate(S.cache,struct('module_id','plot.dataset','source_fingerprint',source_fp));
  if(!report.valid),error('Retained 3D cache source mismatch: %s',strjoin(report.errors,', '));endif
  if(!strcmp(P.plot_type,gxtxt_ini_get(expected,'source.plot_type',''))||!strcmp(P.plot_type,gxtxt_ini_get(cfg,'plot.plot.dataset.xyz.plot_type','')))
    error('Actual prepared geometry kind differs from the graph/runtime contract');
  endif
  if(!isfield(S.cache.module,'info')||!strcmp(S.cache.module.info.dataset_id,gxtxt_ini_get(expected,'source.dataset_id','')))
    error('Prepared geometry belongs to a different canonical Dataset');
  endif
  for role={'x','y','z'}
    r=role{1};m=P.([r '_meta']);prefix=['variable.' r '.'];
    if(!isfield(m,'variable_id')||!strcmp(m.variable_id,gxtxt_ini_get(expected,[prefix 'variable_id'],''))|| ...
       !strcmp(P.([r '_name']),gxtxt_ini_get(expected,[prefix 'name'],''))||!strcmp(m.unit,gxtxt_ini_get(expected,[prefix 'unit'],'')))
      error('Prepared %s geometry has different Variable identity, name or physical unit',r);
    endif
  endfor
  if(isempty(P.groups)),error('Prepared 3D source has no geometry groups');endif
  for i=1:numel(P.groups)
    G=P.groups(i);
    if(any(strcmp(P.plot_type,{'surface','mesh','contour3','heatmap'})))
      if(numel(G.x)<2||numel(G.y)<2||!isequal(size(G.z),[numel(G.y),numel(G.x)])|| ...
         numel(unique(G.x))!=numel(G.x)||numel(unique(G.y))!=numel(G.y))
        error('Prepared 3D grid topology is inconsistent');
      endif
    elseif(numel(G.x)!=numel(G.y)||numel(G.x)!=numel(G.z))
      error('Prepared 3D coordinate arrays are not aligned');
    endif
    if(any(!isfinite(G.x(:)))||any(!isfinite(G.y(:)))||any(!isfinite(G.z(:))))
      error('Prepared 3D geometry contains nonfinite coordinates');
    endif
  endfor
endif
pd_render_3d('',cfg,P,'plot.dataset.xyz','',args{3});
