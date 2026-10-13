function demo_visualization_surface3d_main(args)
% Validate one canonical rectangular XYZ Dataset and render it with GX-TXT 3D APIs.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');
  if(isempty(config_path)), error('demo.visualization.surface3d: --config is required'); endif
  cfg=gxtxt_ini_read(config_path);
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  source_path=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.path',''));
  if(isempty(session)||isempty(outdir)||isempty(dataset_id))
    error('demo.visualization.surface3d: runtime Session, output directory, or source Dataset is missing');
  endif
  if(exist(outdir,'dir')!=7), mkdir(outdir); endif

  x_binding=binding_value(cfg,'x'); y_binding=binding_value(cfg,'y'); z_binding=binding_value(cfg,'z');
  if(isempty(x_binding)||isempty(y_binding)||isempty(z_binding))
    error('demo.visualization.surface3d: bind X coordinate, Y coordinate, and Z value before running');
  endif
  [x_unit,~,x_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',x_binding);
  [y_unit,~,y_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',y_binding);
  [z_unit,~,z_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',z_binding);
  if(!x_meta.found||!y_meta.found||!z_meta.found)
    error('demo.visualization.surface3d: one or more bound variables are missing from the canonical Variable Schema');
  endif
  x_var=strtrim(x_meta.variable_id); y_var=strtrim(y_meta.variable_id); z_var=strtrim(z_meta.variable_id);
  if(isempty(x_var)||isempty(y_var)||isempty(z_var))
    error('demo.visualization.surface3d: current framework runtime must expose stable variable IDs for X, Y, and Z bindings');
  endif
  if(isempty(strtrim(x_unit))||isempty(strtrim(y_unit))||isempty(strtrim(z_unit)))
    error('demo.visualization.surface3d: X, Y, and Z variables require unit metadata; set units in Variables and save the canonical schema');
  endif
  if(!gxtxt_unit_compatible(x_unit,y_unit))
    error('demo.visualization.surface3d: X and Y coordinate units are dimensionally incompatible (%s vs %s)',x_unit,y_unit);
  endif

  gxtxt_progress_start('read','Reading 3D source Dataset','indeterminate');
  [x,y,z]=read_dataset(session,dataset_id,x_var,y_var,z_var);
  gxtxt_progress_stage('validate','Validating complete rectangular grid','indeterminate');
  grid=demo_visualization_surface3d_prepare_grid(x,y,z);
  stats=gxtxt_numeric_v1('statistics',z,struct());
  [zmax,max_idx]=max(z); max_x=x(max_idx); max_y=y(max_idx);
  metadata=read_demo_metadata(cfg);

  write_metrics(fullfile(outdir,'surface3d_metrics.ini'),dataset_id,x_var,y_var,z_var,x_unit,y_unit,z_unit,grid,stats,max_x,max_y);
  write_report(fullfile(outdir,'surface3d_report.txt'),dataset_id,x_var,y_var,z_var,x_unit,y_unit,z_unit,grid,stats,max_x,max_y,metadata);

  sources=struct(); if(!isempty(source_path)), sources.primary=source_path; endif
  meta=gxtxt_render_cache_standard_meta('demo.visualization.surface3d','1.0.3','',sources,struct());
  module_cache=struct('dataset_id',dataset_id,'x_var',x_var,'y_var',y_var,'z_var',z_var, ...
    'x_unit',x_unit,'y_unit',y_unit,'z_unit',z_unit, ...
    'point_count',numel(z),'nx',grid.nx,'ny',grid.ny);
  cache=struct('meta',meta,'module',module_cache);
  gxtxt_render_cache_save(outdir,cache);

  gxtxt_progress_stage('render','Rendering GX-TXT 3D graphs','indeterminate');
  demo_visualization_surface3d_render(outdir,cfg,module_cache);
  gxtxt_progress_complete('done','3D Surface Visualization Demo completed');
  fprintf('PASS demo.visualization.surface3d: dataset=%s grid=%dx%d points=%d Tmin=%.12g Tmax=%.12g\n', ...
    dataset_id,grid.nx,grid.ny,numel(z),stats.min,stats.max);
endfunction

function [x,y,z]=read_dataset(session,dataset_id,x_var,y_var,z_var)
  stream=gxtxt_table_stream_open_dataset(session,dataset_id,{x_var,y_var,z_var},4096, ...
    struct('start',0,'count',-1,'require_direct',false,'numeric_transport','auto'));
  x=[];y=[];z=[];
  unwind_protect
    while(!stream.eof)
      [stream,chunk]=gxtxt_table_stream_next(stream);
      if(chunk.nrows>0)
        x=[x;double(chunk.values{1}(:))];
        y=[y;double(chunk.values{2}(:))];
        z=[z;double(chunk.values{3}(:))];
      endif
    endwhile
  unwind_protect_cleanup
    stream=gxtxt_table_stream_close(stream);
  end_unwind_protect
  if(isempty(x)||numel(x)!=numel(y)||numel(x)!=numel(z))
    error('demo.visualization.surface3d: bound variables do not contain aligned XYZ rows');
  endif
  if(any(!isfinite(x))||any(!isfinite(y))||any(!isfinite(z)))
    error('demo.visualization.surface3d: X, Y, and Z must contain only finite values');
  endif
endfunction

function M=read_demo_metadata(cfg)
  M=struct('synthetic','not declared','demo_type','not declared','domain','not declared','model','not declared','equation','not declared');
  [v,f]=gxtxt_analysis_source_dataset_metadata_get(cfg,'primary','data.synthetic',''); if(f),M.synthetic=v;endif
  [v,f]=gxtxt_analysis_source_dataset_metadata_get(cfg,'primary','demo.type',''); if(f),M.demo_type=v;endif
  [v,f]=gxtxt_analysis_source_dataset_metadata_get(cfg,'primary','demo.domain',''); if(f),M.domain=v;endif
  [v,f]=gxtxt_analysis_source_dataset_metadata_get(cfg,'primary','model.type',''); if(f),M.model=v;endif
  [v,f]=gxtxt_analysis_source_dataset_metadata_get(cfg,'primary','model.equation',''); if(f),M.equation=v;endif
endfunction

function write_metrics(path,dataset_id,x_var,y_var,z_var,x_unit,y_unit,z_unit,G,S,max_x,max_y)
  fid=fopen(path,'w'); if(fid<0), error('demo.visualization.surface3d: cannot write metrics'); endif
  unwind_protect
    fprintf(fid,'[surface3d]\nsource_dataset_id=%s\nx_variable=%s\ny_variable=%s\nz_variable=%s\n',dataset_id,x_var,y_var,z_var);
    fprintf(fid,'x_unit=%s\ny_unit=%s\nz_unit=%s\n',x_unit,y_unit,z_unit);
    fprintf(fid,'x_points=%d\ny_points=%d\npoint_count=%d\n',G.nx,G.ny,S.n);
    fprintf(fid,'x_min=%.15g\nx_max=%.15g\ny_min=%.15g\ny_max=%.15g\n',min(G.x_grid),max(G.x_grid),min(G.y_grid),max(G.y_grid));
    fprintf(fid,'z_min=%.15g\nz_max=%.15g\nz_mean=%.15g\nz_range=%.15g\n',S.min,S.max,S.mean,S.range);
    fprintf(fid,'maximum_x=%.15g\nmaximum_y=%.15g\n',max_x,max_y);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_report(path,dataset_id,x_var,y_var,z_var,x_unit,y_unit,z_unit,G,S,max_x,max_y,M)
  fid=fopen(path,'w'); if(fid<0), error('demo.visualization.surface3d: cannot write report'); endif
  unwind_protect
    fprintf(fid,'3D Surface Visualization Demo\n');
    fprintf(fid,'Source Dataset: %s\n',dataset_id);
    fprintf(fid,'Bindings: X=%s [%s], Y=%s [%s], Z=%s [%s]\n',x_var,x_unit,y_var,y_unit,z_var,z_unit);
    fprintf(fid,'Grid dimensions: %d x %d; point count: %d\n',G.nx,G.ny,S.n);
    fprintf(fid,'X range: %.9g .. %.9g %s\n',min(G.x_grid),max(G.x_grid),x_unit);
    fprintf(fid,'Y range: %.9g .. %.9g %s\n',min(G.y_grid),max(G.y_grid),y_unit);
    fprintf(fid,'Temperature min: %.9g %s\n',S.min,z_unit);
    fprintf(fid,'Temperature max: %.9g %s\n',S.max,z_unit);
    fprintf(fid,'Temperature mean: %.9g %s\n',S.mean,z_unit);
    fprintf(fid,'Temperature range: %.9g %s\n',S.range,z_unit);
    fprintf(fid,'Maximum location: X=%.9g %s, Y=%.9g %s\n',max_x,x_unit,max_y,y_unit);
    fprintf(fid,'Synthetic data metadata: %s\n',M.synthetic);
    fprintf(fid,'Demo type/domain: %s / %s\n',M.demo_type,M.domain);
    fprintf(fid,'Analytical model: %s\n',M.model);
    fprintf(fid,'Analytical equation: %s\n',M.equation);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function v=binding_value(cfg,role)
  q=strtrim(gxtxt_ini_get(cfg,['bindings.' role],''));
  if(isempty(q)||strcmpi(q,'auto')||strcmpi(q,'none')),v='';return;endif
  dot=find(q=='.',1);
  if(!isempty(dot))
    src=q(1:dot-1); if(!strcmp(src,'primary')), error('demo.visualization.surface3d: binding %s must use primary source',role); endif
    v=q(dot+1:end);
  else
    v=q;
  endif
endfunction

function value=arg_value(args,name,default_value)
  value=default_value;
  for i=1:(numel(args)-1), if(strcmp(args{i},name)), value=args{i+1}; return; endif, endfor
endfunction
