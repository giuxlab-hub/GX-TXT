function demo_geospatial_ticino_valley_3d_render(outdir,cfg,D)
% Publish geographic fields as editable public Plot.dataset variants.
% Terrain, river, settlements and synthetic hydraulics have separate views
% so each retains its own correct color scale and shared 3D controls.
% SPDX-License-Identifier: GPL-3.0-or-later
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(session)),error('demo.geospatial.ticino_valley_3d: Session path missing');endif
  if(!isfield(D,'sources')),error('demo.geospatial.ticino_valley_3d: cached Dataset bindings missing');endif
  prefix='demo.geospatial.ticino_valley_3d.';
  graphs={ ...
    'terrain','primary','surface','x_km','y_km','elevation_m','','01_ticino_terrain_3d.png','Ticino valley terrain','Surface elevation [m]'; ...
    'river','river','line3','x_km','y_km','terrain_or_bed_reference_elevation_m','','02_ticino_river_3d.png','Ticino river centerline','Reference elevation [m]'; ...
    'settlements','settlements','scatter3','x_km','y_km','ground_elevation_m','population','03_ticino_settlements_3d.png','Ticino settlements','Ground elevation [m]'; ...
    'population','primary','surface','x_km','y_km','elevation_m','population_density_km2','04_ticino_population_3d.png','ISTAT 2021 population density on terrain','Surface elevation [m]'; ...
    'landcover_built','primary','heatmap','x_km','y_km','built_fraction','','05_ticino_built_fraction.png','Artificial surface fraction','Fraction'; ...
    'landcover_forest','primary','heatmap','x_km','y_km','forest_fraction','','06_ticino_forest_fraction.png','Forest fraction','Fraction'; ...
    'landcover_agriculture','primary','heatmap','x_km','y_km','agriculture_fraction','','07_ticino_agriculture_fraction.png','Agricultural fraction','Fraction'; ...
    'landcover_water','primary','heatmap','x_km','y_km','water_fraction','','08_ticino_water_fraction.png','Open-water fraction','Fraction'; ...
    'hydraulic','hydraulic','scatter3','x_km','y_km','water_surface_elevation_m','water_depth_m','09_ticino_synthetic_hydraulic_3d.png','SIMULATED Ticino water depth (not observations)','Synthetic water-surface elevation [m]'};
  default_ids=cell(1,rows(graphs));for i=1:rows(graphs),default_ids{i}=[prefix graphs{i,1}];endfor
  enabled=parse_list(gxtxt_ini_get(cfg,'graph_provider.enabled',strjoin(default_ids,';')));
  items={};
  for i=1:rows(graphs)
    id=[prefix graphs{i,1}];if(!any(strcmp(enabled,id))),continue;endif
    source=D.sources.(graphs{i,2});
    config=struct('plot_type',graphs{i,3},'reduction_mode','none','legend_content','none', ...
      'x_label','Local easting [km]','y_label','Local northing [km]', ...
      'z_label',graphs{i,10});
    if(strcmp(graphs{i,3},'heatmap')),config.z_label='';endif
    title_text=strtrim(gxtxt_ini_get(cfg,['plot.' id '.title'],graphs{i,9}));
    if(isempty(title_text)||strcmpi(title_text,'auto')),title_text=graphs{i,9};endif
    spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_3d', ...
      'graph_id','plot.dataset.xyz','dataset_id',source.dataset_id, ...
      'x_variable_id',source_id(source,graphs{i,4}), ...
      'y_variable_id',source_id(source,graphs{i,5}), ...
      'z_variable_id',source_id(source,graphs{i,6}), ...
      'title',title_text,'config',config);
    if(!isempty(graphs{i,7})),spec.color_variable_id=source_id(source,graphs{i,7});endif
    items{end+1}=struct('key',graphs{i,1},'spec',spec,'png',graphs{i,8});
  endfor
  gxtxt_plot_provider_render_v1(session,outdir,'demo.geospatial.ticino_valley_3d',items,'base');
endfunction

function id=source_id(source,name)
  k=find(strcmp(source.columns,name));
  if(numel(k)!=1),error('demo.geospatial.ticino_valley_3d: missing stable binding for %s',name);endif
  id=source.ids{k};
endfunction

function out=parse_list(s)
  s=strrep(s,',',';');if(isempty(strtrim(s))),out={};return;endif
  out=strsplit(s,';');out=cellfun(@strtrim,out,'UniformOutput',false);
  out=out(!cellfun(@isempty,out));
endfunction
