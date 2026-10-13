function demo_geospatial_ticino_valley_3d_main(args)
% Analyze only the four canonical Datasets made from the Ticino generator CSVs.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');
  if(isempty(config_path)),error('demo.geospatial.ticino_valley_3d: --config is required');endif
  cfg=gxtxt_ini_read(config_path);
  demo_geospatial_numeric('bind',cfg);
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  if(isempty(session)||isempty(outdir)),error('demo.geospatial.ticino_valley_3d: Session or output directory missing');endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif

  source_ids={'primary','river','settlements','hydraulic'};
  expected_ids={'ticino_valley_grid','ticino_river_centerline','ticino_valley_settlements','ticino_hydraulic_demo'};
  source_paths=struct();
  for k=1:numel(source_ids)
    sid=source_ids{k};
    actual=strtrim(gxtxt_ini_get(cfg,['analysis_source.' sid '.dataset_id'],''));
    if(!strcmp(actual,expected_ids{k}))
      error('demo.geospatial.ticino_valley_3d: source %s must be the generated Dataset ID %s (got %s)',sid,expected_ids{k},actual);
    endif
    path=strtrim(gxtxt_ini_get(cfg,['analysis_source.' sid '.path'],''));
    if(isempty(path)),error('demo.geospatial.ticino_valley_3d: source %s is not mapped to a canonical Dataset',sid);endif
    source_paths.(sid)=path;
  endfor

  gxtxt_progress_start('read','Reading Ticino canonical Datasets','indeterminate');
  grid_columns={'grid_i','grid_j','x_km','y_km','elevation_m','population','population_density_km2', ...
    'built_fraction','forest_fraction','agriculture_fraction','water_fraction'};
  river_columns={'chainage_km','x_km','y_km','terrain_or_bed_reference_elevation_m'};
  settlement_columns={'x_km','y_km','ground_elevation_m','population'};
  hydraulic_columns={'x_km','y_km','water_surface_elevation_m','water_depth_m','velocity_m_s','bed_elevation_m'};
  [grid,grid_ids]=read_numeric_source(cfg,'primary',grid_columns);
  [river,river_ids]=read_numeric_source(cfg,'river',river_columns);
  [settlement,settlement_ids]=read_numeric_source(cfg,'settlements',settlement_columns);
  [hydraulic,hydraulic_ids]=read_numeric_source(cfg,'hydraulic',hydraulic_columns);

  gxtxt_progress_stage('validate','Validating grid and source provenance','indeterminate');
  G=prepare_grid(grid);
  if(rows(river)<2||any(diff(river(:,1))<=0)||abs(river(1,1))>1e-6)
    error('demo.geospatial.ticino_valley_3d: river chainage must be strictly increasing from zero');
  endif
  if(any(settlement(:,4)<0)),error('demo.geospatial.ticino_valley_3d: negative settlement population');endif
  if(any(hydraulic(:,4)<0)||any(hydraulic(:,5)<0))
    error('demo.geospatial.ticino_valley_3d: negative synthetic hydraulic depth or velocity');
  endif
  balance=max(abs(hydraulic(:,3)-hydraulic(:,6)-hydraulic(:,4)));
  if(balance>1e-6),error('demo.geospatial.ticino_valley_3d: synthetic water-surface/bed/depth identity failed');endif
  if(any(hydraulic(:,1)<min(G.X(:))-1)||any(hydraulic(:,1)>max(G.X(:))+1)|| ...
     any(hydraulic(:,2)<min(G.Y(:))-1)||any(hydraulic(:,2)>max(G.Y(:))+1))
    error('demo.geospatial.ticino_valley_3d: hydraulic samples extend unexpectedly beyond the grid envelope');
  endif

  sources=struct();
  sources.primary=source_binding(expected_ids{1},grid_columns,grid_ids);
  sources.river=source_binding(expected_ids{2},river_columns,river_ids);
  sources.settlements=source_binding(expected_ids{3},settlement_columns,settlement_ids);
  sources.hydraulic=source_binding(expected_ids{4},hydraulic_columns,hydraulic_ids);
  D=struct('grid',G,'river',river,'settlement',settlement,'hydraulic',hydraulic,'sources',sources);
  write_metrics(fullfile(outdir,'ticino_valley_metrics.ini'),D);
  write_report(fullfile(outdir,'ticino_valley_report.txt'),D);
  meta=gxtxt_render_cache_standard_meta('demo.geospatial.ticino_valley_3d','2.0.0','',source_paths,struct());
  gxtxt_render_cache_save(outdir,struct('meta',meta,'module',D));

  gxtxt_progress_stage('render','Rendering Ticino maps','indeterminate');
  demo_geospatial_ticino_valley_3d_render(outdir,cfg,D);
  gxtxt_progress_complete('done','Ticino Valley 3D Cartography Demo completed');
  fprintf('PASS demo.geospatial.ticino_valley_3d: grid=%dx%d river=%d settlements=%d synthetic_hydraulic=%d\n', ...
    G.nx,G.ny,rows(river),rows(settlement),rows(hydraulic));
endfunction

function [result,ids]=read_numeric_source(cfg,source_id,columns)
  options=struct('start',0,'count',-1,'require_direct',false,'numeric_transport','auto');
  % Table Stream v3 selects stable variable IDs, not CSV/canonical names.
  % Discover the active schema first, then reopen only the requested columns.
  catalog=gxtxt_table_stream_open_source(cfg,source_id,{},4096,options);
  unwind_protect
    schema=catalog.schema;
    ids=cell(1,numel(columns));
    canonical_names={schema.canonical};
    for col=1:numel(columns)
      matches=find(strcmp(canonical_names,columns{col}));
      if(numel(matches)!=1)
        error('demo.geospatial.ticino_valley_3d: source %s must contain one active canonical variable named %s (found %d)', ...
          source_id,columns{col},numel(matches));
      endif
      ids{col}=schema(matches).variable_id;
    endfor
  unwind_protect_cleanup
    catalog=gxtxt_table_stream_close(catalog);
  end_unwind_protect
  stream=gxtxt_table_stream_open_source(cfg,source_id,ids,4096,options);
  result=zeros(0,numel(columns));
  unwind_protect
    while(!stream.eof)
      [stream,chunk]=gxtxt_table_stream_next(stream);
      if(chunk.nrows==0),continue;endif
      block=zeros(chunk.nrows,numel(columns));
      for col=1:numel(columns)
        values=gxtxt_table_chunk_numeric(chunk,ids{col});
        if(numel(values)!=chunk.nrows),error('demo.geospatial.ticino_valley_3d: source %s has misaligned variable %s',source_id,columns{col});endif
        block(:,col)=values;
      endfor
      result=[result;block];
    endwhile
  unwind_protect_cleanup
    stream=gxtxt_table_stream_close(stream);
  end_unwind_protect
  if(isempty(result)||any(!isfinite(result(:))))
    error('demo.geospatial.ticino_valley_3d: source %s is empty or contains non-finite selected values',source_id);
  endif
endfunction

function b=source_binding(dataset_id,columns,ids)
  b=struct('dataset_id',dataset_id,'columns',{columns},'ids',{ids});
endfunction

function G=prepare_grid(data)
  i=data(:,1);j=data(:,2);n=rows(data);
  if(any(i<0)||any(j<0)||any(i!=fix(i))||any(j!=fix(j)))
    error('demo.geospatial.ticino_valley_3d: grid indices must be non-negative integers');
  endif
  nx=max(i)+1;ny=max(j)+1;
  if(nx*ny!=n||min(i)!=0||min(j)!=0)
    error('demo.geospatial.ticino_valley_3d: incomplete rectangular 1 km grid');
  endif
  idx=sub2ind([ny,nx],j+1,i+1);
  if(numel(unique(idx))!=n),error('demo.geospatial.ticino_valley_3d: duplicate grid cell index');endif
  X=zeros(ny,nx);Y=zeros(ny,nx);Z=zeros(ny,nx);P=zeros(ny,nx);PD=zeros(ny,nx);
  B=zeros(ny,nx);F=zeros(ny,nx);A=zeros(ny,nx);W=zeros(ny,nx);
  X(idx)=data(:,3);Y(idx)=data(:,4);Z(idx)=data(:,5);P(idx)=data(:,6);PD(idx)=data(:,7);
  B(idx)=data(:,8);F(idx)=data(:,9);A(idx)=data(:,10);W(idx)=data(:,11);
  if(any(P(:)<0)||any(PD(:)<0)||any([B(:);F(:);A(:);W(:)]<0)|| ...
     any([B(:);F(:);A(:);W(:)]>1+1e-8)||any(B(:)+F(:)+A(:)+W(:)>1+1e-5))
    error('demo.geospatial.ticino_valley_3d: population or CORINE fraction outside allowed range');
  endif
  if(any(abs(X-repmat(X(1,:),ny,1))(:)>1e-7)|| ...
     any(abs(Y-repmat(Y(:,1),1,nx))(:)>1e-7))
    error('demo.geospatial.ticino_valley_3d: grid coordinates are not rectangular');
  endif
  if(nx>1&&any(abs(diff(X(1,:))-1)>1e-5)),error('demo.geospatial.ticino_valley_3d: X spacing is not 1 km');endif
  if(ny>1&&any(abs(diff(Y(:,1))-1)>1e-5)),error('demo.geospatial.ticino_valley_3d: Y spacing is not 1 km');endif
  G=struct('nx',nx,'ny',ny,'X',X,'Y',Y,'Z_m',Z,'population',P,'population_density',PD, ...
    'built',B,'forest',F,'agriculture',A,'water',W);
endfunction

function write_metrics(path,D)
  G=D.grid;fid=fopen(path,'w');if(fid<0),error('demo.geospatial.ticino_valley_3d: cannot write metrics');endif
  unwind_protect
    fprintf(fid,'[ticino_valley]\ncrs=EPSG:25832\ngrid_nx=%d\ngrid_ny=%d\ngrid_cells=%d\n',G.nx,G.ny,numel(G.Z_m));
    fprintf(fid,'elevation_min_m=%.15g\nelevation_max_m=%.15g\nelevation_mean_m=%.15g\n',min(G.Z_m(:)),max(G.Z_m(:)),geo_mean(G.Z_m(:)));
    fprintf(fid,'allocated_population_sum=%.15g\npopulation_reference_year=2021\n',sum(G.population(:)));
    fprintf(fid,'mean_built_fraction=%.15g\nmean_forest_fraction=%.15g\nmean_agriculture_fraction=%.15g\nmean_water_fraction=%.15g\n', ...
      geo_mean(G.built(:)),geo_mean(G.forest(:)),geo_mean(G.agriculture(:)),geo_mean(G.water(:)));
    fprintf(fid,'river_samples=%d\nriver_chainage_max_km=%.15g\nsettlement_count=%d\n', ...
      rows(D.river),D.river(end,1),rows(D.settlement));
    fprintf(fid,'hydraulic_synthetic=true\nhydraulic_samples=%d\nsynthetic_depth_mean_m=%.15g\nsynthetic_depth_max_m=%.15g\n', ...
      rows(D.hydraulic),geo_mean(D.hydraulic(:,4)),max(D.hydraulic(:,4)));
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_report(path,D)
  G=D.grid;fid=fopen(path,'w');if(fid<0),error('demo.geospatial.ticino_valley_3d: cannot write report');endif
  unwind_protect
    fprintf(fid,'Ticino Valley 3D Cartography Demo — GX-TXT external plugin 2.0.0\n\n');
    fprintf(fid,'Study grid: %d x %d = %d cells of 1 km, EPSG:25832.\n',G.nx,G.ny,numel(G.Z_m));
    fprintf(fid,'DEM elevation: %.3f .. %.3f m (mean %.3f m), Copernicus GLO-30 digital surface model, EGM2008 heights.\n', ...
      min(G.Z_m(:)),max(G.Z_m(:)),geo_mean(G.Z_m(:)));
    fprintf(fid,'ISTAT 2021 area-weighted allocated population sum over target cells: %.3f; not an official municipality or study-area census total.\n',sum(G.population(:)));
    fprintf(fid,'Mean CORINE 2018 fractions: artificial %.4f, forest %.4f, agriculture %.4f, open water %.4f.\n', ...
      geo_mean(G.built(:)),geo_mean(G.forest(:)),geo_mean(G.agriculture(:)),geo_mean(G.water(:)));
    fprintf(fid,'RIRU-derived ordered river samples: %d, chainage 0 .. %.3f km.\n',rows(D.river),D.river(end,1));
    fprintf(fid,'ISTAT 2021 localities: %d source-derived selected points.\n',rows(D.settlement));
    fprintf(fid,'Synthetic hydraulic demonstration samples: %d, mean water depth %.3f m. These are NOT measured levels, discharges, forecasts, or a calibrated model.\n', ...
      rows(D.hydraulic),geo_mean(D.hydraulic(:,4)));
    fprintf(fid,'3D display uses vertical plot-box emphasis only; the source numeric values are unchanged.\n');
    fprintf(fid,'Provenance and license obligations are in the generated Session reference/ directory.\n');
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function value=arg_value(args,name,default_value)
  value=default_value;
  for i=1:(numel(args)-1)
    if(strcmp(args{i},name)),value=args{i+1};return;endif
  endfor
endfunction

function value=geo_mean(values)
  summary=demo_geospatial_numeric('reduce_summary',double(values(:)),struct());value=summary.mean;
endfunction
