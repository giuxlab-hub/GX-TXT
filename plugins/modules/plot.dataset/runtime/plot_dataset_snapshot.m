% Public Plot Dataset snapshot service for detached CORE scientific Clones.
% The service operates on resolved prepared values and never opens a source Dataset.
this_file = mfilename('fullpath');
runtime_dir = fileparts(this_file);
package_root = fileparts(fileparts(fileparts(fileparts(runtime_dir))));
addpath(runtime_dir);
for directory = {'analysis', 'graphics', 'io', 'units', 'util', 'cache'}
  addpath(fullfile(package_root, 'core', 'octave', directory{1}));
endfor
args = argv();
if (numel(args) != 4)
  error('usage: plot_dataset_snapshot.m capture|render|overlay|points <source> <destination> <graph-id>');
endif
operation = args{1}; source = args{2}; destination = args{3}; graph = args{4};
if (!any(strcmp(graph, {'plot.dataset.xy', 'plot.dataset.xy_region', 'plot.dataset.xyz'})))
  error('plot.dataset snapshot: unsupported graph ID');
endif
if (strcmp(operation, 'transient2d'))
  if(!strcmp(graph,'plot.dataset.xy')),error('2D transient preview requires XY graph');endif
  fid=fopen(source,'r');if(fid<0),error('2D transient request is missing');endif
  unwind_protect
    title=fgetl(fid);x_unit=fgetl(fid);labels=strsplit(fgetl(fid),'\t');units=strsplit(fgetl(fid),'\t');
    n=numel(labels);values=fscanf(fid,'%f',[n+1 Inf]).';
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
  if(rows(values)<2||columns(values)!=n+1||numel(units)!=n||any(!isfinite(values(:))))
    error('2D transient preview requires finite, aligned XY values');
  endif
  if(exist(destination,'dir')!=7),mkdir(destination);endif
  cfg=struct();base=struct('name','','axis','left','panel_id','main','label','','series_id','','dataset_id','', ...
    'meta',struct('unit',''),'x_name','X','x_meta',struct('unit',x_unit),'data',struct(),'presentation',struct());
  series=repmat(base,1,n);
  for k=1:n
    series(k).name=labels{k};series(k).label=labels{k};series(k).series_id=sprintf('transient_%d',k);
    series(k).meta=struct('unit',units{k});series(k).data=struct('x',values(:,1),'y',values(:,k+1), ...
      'source_row_indices',-ones(rows(values),1),'aux_ids',{{}},'aux_values',{{}},'aux_meta',{{}}, ...
      'valid_rows',rows(values),'display_rows',rows(values));
  endfor
  P=struct('mode','graph_series','graph_id',graph,'variant_id','','x_name','X','x_meta',struct('unit',x_unit),'series',series);
  gxtxt_setup_graphics();pd_render_2d(destination,cfg,P,graph,'graph.png');
  printf('2D transient preview points=%d series=%d\n',rows(values),n);
elseif (strcmp(operation, 'transient3d'))
  if(!strcmp(graph,'plot.dataset.xyz')),error('3D transient preview requires XYZ graph');endif
  fid=fopen(source,'r');if(fid<0),error('3D transient request is missing');endif
  unwind_protect
    label=fgetl(fid);points=fscanf(fid,'%f\t%f\t%f',[3 Inf]).';
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
  if(rows(points)<2||columns(points)!=3||any(!isfinite(points(:)))),error('3D transient preview requires finite XYZ points');endif
  if(exist(destination,'dir')!=7),mkdir(destination);endif
  cfg=struct();P=struct();P.groups=struct('key',label,'x',points(:,1),'y',points(:,2),'z',points(:,3),'c',[]);
  P.plot_type='line3';P.x_name='X';P.y_name='Y';P.z_name='Z';
  P.x_meta=struct('unit','');P.y_meta=struct('unit','');P.z_meta=struct('unit','');
  P.color_name='';P.color_meta=struct('unit','');P.family_name='';P.family_meta=struct('unit','');
  gxtxt_setup_graphics();pd_render_3d(destination,cfg,P,graph,'graph.png');
  printf('3D transient preview points=%d\n',rows(points));
elseif (strcmp(operation, 'overlay'))
  if(strcmp(graph,'plot.dataset.xyz')),error('XY transient overlay requires a 2D graph');endif
  S=load(source);if(!isfield(S,'P')||isempty(S.P.series)),error('transient overlay needs a prepared source graph');endif
  fid=fopen(destination,'r');if(fid<0),error('transient overlay request is missing');endif
  unwind_protect
    label=fgetl(fid);points=fscanf(fid,'%f\t%f',[2 Inf]).';
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
  if(rows(points)<2||columns(points)!=2||any(!isfinite(points(:)))),error('transient overlay needs finite XY points');endif
  P=S.P;Q=P.series(1);Q.series_id='transient_preview';Q.label=label;Q.name=label;Q.axis='left';
  Q.data.x=points(:,1);Q.data.y=points(:,2);Q.data.source_row_indices=-ones(rows(points),1);
  Q.data.aux_ids={};Q.data.aux_values={};Q.data.aux_meta={};Q.data.valid_rows=rows(points);Q.data.display_rows=rows(points);
  Q.presentation=struct();P.series(end+1)=Q;save('-hdf5',source,'P');
  printf('transient overlay points=%d\n',rows(points));
elseif (strcmp(operation, 'capture'))
  if (exist(destination, 'file') != 0), error('snapshot destination already exists'); endif
  S = load(source);
  if (!isfield(S, 'cache') || !isfield(S.cache, 'module'))
    error('plot.dataset snapshot: render cache is unavailable');
  endif
  M = S.cache.module;
  if (strcmp(graph, 'plot.dataset.xy')), field = 'plot2d_xy';
  elseif (strcmp(graph, 'plot.dataset.xy_region')), field = 'plot2d_xy_region';
  else field = 'plot3d'; endif
  if (!isfield(M, field)), error('plot.dataset snapshot: resolved graph is unavailable'); endif
  P = M.(field);
  save('-hdf5', destination, 'P');
  if (strcmp(graph, 'plot.dataset.xyz')), count = numel(P.groups);
  else count = numel(P.series); endif
  printf('captured graph=%s series=%d\n', graph, count);
elseif (strcmp(operation, 'render'))
  if (exist(destination, 'file') != 2), error('snapshot runtime INI is unavailable'); endif
  S = load(source);
  if (!isfield(S, 'P')), error('snapshot scientific values are unavailable'); endif
  % Relative paths remain valid when the complete Session is copied or moved.
  old_directory = pwd();
  cd(fileparts(destination));
  cfg = gxtxt_ini_read(destination);
  output_dir = strtrim(gxtxt_ini_get(cfg, 'runtime.output_dir', ''));
  if (isempty(output_dir)), error('snapshot output directory is unavailable'); endif
  if (exist(output_dir, 'dir') != 7), mkdir(output_dir); endif
  gxtxt_setup_graphics();
  if (strcmp(graph, 'plot.dataset.xyz'))
    pd_render_3d(output_dir, cfg, S.P, graph, 'graph.png');
  else
    P = pd_refresh_plotspec_v2(S.P, cfg, graph);
    pd_render_2d(output_dir, cfg, P, graph, 'graph.png');
  endif
  cd(old_directory);
  printf('rendered graph=%s\n', graph);
elseif (strcmp(operation, 'points'))
  if (strcmp(graph, 'plot.dataset.xyz'))
    error('Graph point selection requires a 2D plot');
  endif
  S = load(source);
  if (!isfield(S, 'cache') || !isfield(S.cache, 'module'))
    error('Graph point selection requires a valid render cache');
  endif
  if (strcmp(graph, 'plot.dataset.xy')), field = 'plot2d_xy';
  else field = 'plot2d_xy_region'; endif
  if (!isfield(S.cache.module, field)), error('Prepared 2D graph is unavailable'); endif
  P = S.cache.module.(field);
  fid = fopen(destination, 'wt');
  if (fid < 0), error('Cannot create graph point index'); endif
  unwind_protect
    fprintf(fid, 'series_id\tdataset_id\tsource_row\tx\ty\taxis\tpanel_id\n');
    for k = 1:numel(P.series)
      Q = P.series(k); D = Q.data;
      if (!isfield(D, 'source_row_indices'))
        error('Graph cache predates source-row mapping; recalculate the Plot Dataset analysis before selecting points');
      endif
      if (numel(D.source_row_indices) != numel(D.x) || numel(D.x) != numel(D.y))
        error('Graph cache has inconsistent point identities');
      endif
      for i = 1:numel(D.x)
        fprintf(fid, '%s\t%s\t%.0f\t%.17g\t%.17g\t%s\t%s\n', ...
          Q.series_id, Q.dataset_id, D.source_row_indices(i), D.x(i), D.y(i), Q.axis, Q.panel_id);
      endfor
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
  printf('indexed graph=%s series=%d\n', graph, numel(P.series));
else
  error('plot.dataset snapshot: expected capture, render or points');
endif
