function demo_environmental_levoglucosan_campaign_main(args)
% Analyze the synthetic Sardinia levoglucosan campaign using public GX-TXT APIs.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='demo.environmental.levoglucosan_campaign';
  module_version='1.2.1';
  config_path=arg_value(args,'--config','');
  if(isempty(config_path)), error('%s: --config is required',module_id); endif
  cfg=gxtxt_ini_read(config_path);
  demo_environmental_numeric('bind',cfg);
  options=read_options(cfg);
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  source_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  if(isempty(session)||isempty(outdir)||isempty(source_id))
    error('%s: runtime Session, output directory, or primary Analysis Source is missing',module_id);
  endif
  if(exist(outdir,'dir')!=7), mkdir(outdir); endif

  [synthetic,found]=gxtxt_analysis_source_dataset_metadata_get(cfg,'primary','data.synthetic','');
  if(!found || !strcmpi(strtrim(synthetic),'true'))
    error(['%s: Dataset Metadata does not contain data.synthetic=true. ' ...
           'Use the bundled Sardinia Levoglucosan Campaign Session Generator; the generated Session is ready to run and persists this metadata automatically.'],module_id);
  endif
  lod=metadata_number(cfg,'analysis.lod_ppm',0.010);
  loq=metadata_number(cfg,'analysis.loq_ppm',0.030);
  if(!(lod>0 && loq>lod)), error('%s: invalid LOD/LOQ Dataset Metadata',module_id); endif

  binding_names={'day_of_year','month','site_id','replicate_id','levoglucosan','fire_event_id','fire_exposure','fire_distance','latitude','longitude','elevation','below_lod','below_loq'};
  variable_ids=cell(size(binding_names));
  for i=1:numel(binding_names)
    raw_binding=gxtxt_ini_get(cfg,['bindings.' binding_names{i}],'');
    token=binding_column(raw_binding,binding_names{i});
    if(isempty(token) && strcmp(binding_names{i},'elevation'))
      % Sessions generated before generator 1.1.1 already contain elevation_m;
      % resolve that stable variable directly so they remain usable.
      token='elevation_m';
    endif
    if(isempty(token)), error('%s: binding %s is required',module_id,binding_names{i}); endif
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',token);
    if(!isfield(meta,'found') || !meta.found || isempty(strtrim(meta.variable_id)))
      error('%s: binding %s could not be resolved to a stable Dataset variable ID',module_id,binding_names{i});
    endif
    variable_ids{i}=strtrim(meta.variable_id);
  endfor

  raw=read_numeric_source(cfg,variable_ids,binding_names);
  validate_source(raw,module_id);

  daily=aggregate_daily(raw);
  monthly=aggregate_monthly(daily);
  seasonal=aggregate_seasonal(daily);
  site_summary=aggregate_site_summary(raw,daily,seasonal);
  relationships=pairwise_relationships(daily);
  cross_lag=cross_site_lag_relationships(daily,options.cross_site_max_lag_days);
  fire=fire_relationships(daily);
  uncertainty=uncertainty_demo(raw,daily,fire.strongest_event_id);
  qc=qc_analysis(daily,options.qc_cv_threshold_percent);
  anomalies=anomaly_analysis(daily,options.anomaly_window_days,options.anomaly_z_threshold);

  fire_weights=1./max(fire.all_sem_ppm,1e-6).^2;
  exposure_fit=demo_environmental_numeric('linear_regression',fire.all_exposure,fire.all_mean_ppm,fire_weights, ...
    struct('nonfinite','omit','intercept',true,'weight_semantics','inverse_variance'));
  distance_fit=demo_environmental_numeric('linear_regression',fire.all_distance_km,fire.all_mean_ppm,fire_weights, ...
    struct('nonfinite','omit','intercept',true,'weight_semantics','inverse_variance'));
  fire_regression=build_fire_regression(fire,exposure_fit,distance_fit);

  % Derived Datasets are always published. Output-group switches control presentation
  % and reporting, so disabling a graph group never leaves stale scientific tables.
  publish_daily_long(session,module_id,module_version,source_id,daily);
  publish_monthly_long(session,module_id,module_version,source_id,monthly);
  publish_seasonal_long(session,module_id,module_version,source_id,seasonal);
  publish_site_summary(session,module_id,module_version,source_id,site_summary);
  publish_relationships(session,module_id,module_version,source_id,relationships);
  publish_cross_site_lag(session,module_id,module_version,source_id,cross_lag);
  publish_fire_relationships(session,module_id,module_version,source_id,fire);
  publish_fire_regressions(session,module_id,module_version,source_id,fire_regression);
  publish_uncertainty_demo(session,module_id,module_version,source_id,uncertainty);
  publish_qc_daily(session,module_id,module_version,source_id,qc);
  publish_anomalies(session,module_id,module_version,source_id,anomalies);
  publish_site_plot_datasets(session,module_id,module_version,source_id,daily,monthly,seasonal,fire);
  publish_qc_plot_datasets(session,module_id,module_version,source_id,qc);
  publish_anomaly_plot_datasets(session,module_id,module_version,source_id,anomalies);

  write_metrics(outdir,source_id,raw,daily,monthly,seasonal,site_summary,relationships,cross_lag,fire,exposure_fit,distance_fit,qc,anomalies,lod,loq,options);
  write_report(outdir,source_id,raw,daily,monthly,seasonal,site_summary,relationships,cross_lag,fire,exposure_fit,distance_fit,qc,anomalies,lod,loq,options);

  graph_groups=enabled_graph_groups(options);
  if(options.render_2d_graphs && !isempty(graph_groups))
    run_plot_helper(outdir,session,fire,uncertainty,options,graph_groups);
  else
    write_empty_graph_manifest(outdir);
  endif

  spatial3d_files={};
  if(options.render_3d_graphs && options.output_spatial_analysis)
    spatial3d_files=render_spatial_3d(session,outdir,cfg);
  endif
  write_output_manifest(outdir,options,graph_groups,spatial3d_files);

  fprintf('PASS %s: %d replicate rows, %d daily summaries, %d monthly summaries, configurable output groups, 2D=%d, 3D=%d\n', ...
          module_id,numel(raw.levoglucosan),numel(daily.mean_ppm),numel(monthly.mean_ppm),options.render_2d_graphs,options.render_3d_graphs && options.output_spatial_analysis);
endfunction

function O=read_options(cfg)
  O=struct();
  O.output_campaign_summary=parse_bool(gxtxt_ini_get(cfg,'config.output_campaign_summary','1'),true);
  O.output_seasonality=parse_bool(gxtxt_ini_get(cfg,'config.output_seasonality','1'),true);
  O.output_fire_events=parse_bool(gxtxt_ini_get(cfg,'config.output_fire_events','1'),true);
  O.output_uncertainty_qc=parse_bool(gxtxt_ini_get(cfg,'config.output_uncertainty_qc','1'),true);
  O.output_cross_site=parse_bool(gxtxt_ini_get(cfg,'config.output_cross_site','1'),true);
  O.output_anomaly_detection=parse_bool(gxtxt_ini_get(cfg,'config.output_anomaly_detection','1'),true);
  O.output_spatial_analysis=parse_bool(gxtxt_ini_get(cfg,'config.output_spatial_analysis','1'),true);
  O.render_2d_graphs=parse_bool(gxtxt_ini_get(cfg,'config.render_2d_graphs','1'),true);
  O.render_3d_graphs=parse_bool(gxtxt_ini_get(cfg,'config.render_3d_graphs','1'),true);
  O.qc_cv_threshold_percent=str2double(strtrim(gxtxt_ini_get(cfg,'config.qc_cv_threshold_percent','10')));
  O.anomaly_window_days=round(str2double(strtrim(gxtxt_ini_get(cfg,'config.anomaly_window_days','21'))));
  O.anomaly_z_threshold=str2double(strtrim(gxtxt_ini_get(cfg,'config.anomaly_z_threshold','4')));
  O.cross_site_max_lag_days=round(str2double(strtrim(gxtxt_ini_get(cfg,'config.cross_site_max_lag_days','2'))));
  if(!isfinite(O.qc_cv_threshold_percent)||O.qc_cv_threshold_percent<=0), error('demo.environmental.levoglucosan_campaign: QC CV threshold must be positive'); endif
  if(!isfinite(O.anomaly_window_days)||O.anomaly_window_days<3||mod(O.anomaly_window_days,2)==0), error('demo.environmental.levoglucosan_campaign: anomaly window must be an odd integer >= 3'); endif
  if(!isfinite(O.anomaly_z_threshold)||O.anomaly_z_threshold<=0), error('demo.environmental.levoglucosan_campaign: anomaly threshold must be positive'); endif
  if(!isfinite(O.cross_site_max_lag_days)||O.cross_site_max_lag_days<0||O.cross_site_max_lag_days>30), error('demo.environmental.levoglucosan_campaign: cross-site lag range must be 0..30 days'); endif
endfunction

function value=parse_bool(text,default_value)
  q=lower(strtrim(text));
  if(any(strcmp(q,{'1','true','yes','on'}))), value=true;
  elseif(any(strcmp(q,{'0','false','no','off'}))), value=false;
  else value=default_value;
  endif
endfunction

function groups=enabled_graph_groups(O)
  items={};
  if(O.output_campaign_summary), items{end+1}='summary'; endif
  if(O.output_seasonality), items{end+1}='seasonality'; endif
  if(O.output_fire_events), items{end+1}='fire'; endif
  if(O.output_uncertainty_qc), items{end+1}='uncertainty_qc'; endif
  if(O.output_cross_site), items{end+1}='cross_site'; endif
  if(O.output_anomaly_detection), items{end+1}='anomaly'; endif
  if(O.output_spatial_analysis), items{end+1}='spatial'; endif
  groups=strjoin(items,',');
endfunction

function value=metadata_number(cfg,key,default_value)
  [text,found]=gxtxt_analysis_source_dataset_metadata_get(cfg,'primary',key,num2str(default_value));
  if(!found), value=default_value; return; endif
  value=str2double(strtrim(text));
  if(!isfinite(value)), error('demo.environmental.levoglucosan_campaign: Dataset Metadata %s is not numeric',key); endif
endfunction

function token=binding_column(value,role)
  token=strtrim(value);
  if(isempty(token)||strcmp(token,'auto')), token=''; return; endif
  dot=find(token=='.',1);
  if(!isempty(dot))
    source=strtrim(token(1:dot-1));
    if(!strcmp(source,'primary')), error('demo.environmental.levoglucosan_campaign: binding %s must refer to primary.*, got %s',role,token); endif
    token=strtrim(token(dot+1:end));
  endif
endfunction

function D=read_numeric_source(cfg,ids,names)
  S=gxtxt_table_stream_open_source(cfg,'primary',ids,4096,struct('start',0,'count',-1,'require_direct',false,'numeric_transport','auto'));
  values=cell(1,numel(ids));
  for i=1:numel(ids), values{i}=zeros(0,1); endfor
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S);
      if(C.nrows<=0), continue; endif
      for i=1:numel(ids)
        v=C.values{i};
        if(iscell(v)), error('demo.environmental.levoglucosan_campaign: binding %s must be numeric',names{i}); endif
        values{i}=[values{i}; double(v(:))];
      endfor
    endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
  D=struct();
  for i=1:numel(names), D.(names{i})=values{i}; endfor
endfunction

function validate_source(D,module_id)
  n=numel(D.levoglucosan);
  required={'day_of_year','month','site_id','replicate_id','levoglucosan','fire_event_id','fire_exposure','latitude','longitude','elevation','below_lod','below_loq'};
  for i=1:numel(required)
    v=D.(required{i});
    if(numel(v)!=n || any(!isfinite(v))), error('%s: %s contains missing/non-finite values or has inconsistent length',module_id,required{i}); endif
  endfor
  if(n!=4380), error('%s: expected 4380 replicate rows (365 x 4 x 3), got %d',module_id,n); endif
  if(!isequal(unique(round(D.day_of_year)).',(1:365))), error('%s: source must contain day_of_year 1..365 exactly',module_id); endif
  if(!isequal(unique(round(D.site_id)).',(1:4))), error('%s: source must contain numeric site_id 1..4',module_id); endif
  if(!isequal(unique(round(D.replicate_id)).',(1:3))), error('%s: source must contain replicate_id 1..3',module_id); endif
  if(any(D.month<1|D.month>12|D.month!=round(D.month))), error('%s: invalid month values',module_id); endif
  if(any(D.levoglucosan<=0)), error('%s: levoglucosan measurements must be positive retained values, not silent zeros',module_id); endif
  if(any(D.fire_exposure<0)), error('%s: fire exposure must be non-negative',module_id); endif
  for day=1:365
    for site=1:4
      idx=find(round(D.day_of_year)==day & round(D.site_id)==site);
      if(numel(idx)!=3 || !isequal(sort(round(D.replicate_id(idx))).',(1:3)))
        error('%s: day %d site %d does not contain exactly three technical replicates',module_id,day,site);
      endif
    endfor
  endfor
endfunction

function A=aggregate_daily(D)
  n=365*4;
  A.day_of_year=zeros(n,1); A.month=zeros(n,1); A.site_id=zeros(n,1);
  A.latitude_deg=zeros(n,1); A.longitude_deg=zeros(n,1);
  A.mean_ppm=zeros(n,1); A.sd_ppm=zeros(n,1); A.sem_ppm=zeros(n,1);
  A.ci95_half_width_ppm=zeros(n,1); A.ci95_lower_ppm=zeros(n,1); A.ci95_upper_ppm=zeros(n,1);
  A.fire_event_id=zeros(n,1); A.fire_exposure_index=zeros(n,1); A.nearest_fire_distance_km=NaN(n,1);
  A.below_lod_count=zeros(n,1); A.below_loq_count=zeros(n,1); A.n_replicates=zeros(n,1);
  row=0;
  for day=1:365
    for site=1:4
      row+=1; idx=find(round(D.day_of_year)==day & round(D.site_id)==site);
      st=demo_environmental_numeric('statistics',D.levoglucosan(idx),struct());
      sem=st.std_sample/sqrt(st.n); half=student_t_975(st.n-1)*sem;
      A.day_of_year(row)=day; A.month(row)=round(D.month(idx(1))); A.site_id(row)=site;
      A.latitude_deg(row)=D.latitude(idx(1)); A.longitude_deg(row)=D.longitude(idx(1));
      A.mean_ppm(row)=st.mean; A.sd_ppm(row)=st.std_sample; A.sem_ppm(row)=sem;
      A.ci95_half_width_ppm(row)=half; A.ci95_lower_ppm(row)=max(0,st.mean-half); A.ci95_upper_ppm(row)=st.mean+half;
      A.fire_event_id(row)=round(max(D.fire_event_id(idx))); A.fire_exposure_index(row)=environmental_mean(D.fire_exposure(idx));
      finite_distance=D.fire_distance(idx(isfinite(D.fire_distance(idx))));
      if(!isempty(finite_distance)), A.nearest_fire_distance_km(row)=environmental_mean(finite_distance); endif
      A.below_lod_count(row)=sum(D.below_lod(idx)>0.5); A.below_loq_count(row)=sum(D.below_loq(idx)>0.5); A.n_replicates(row)=st.n;
    endfor
  endfor
endfunction

function M=aggregate_monthly(D)
  n=12*4;
  M.month=zeros(n,1); M.site_id=zeros(n,1); M.n_days=zeros(n,1);
  M.mean_ppm=zeros(n,1); M.sd_between_days_ppm=zeros(n,1); M.sem_ppm=zeros(n,1); M.ci95_half_width_ppm=zeros(n,1);
  M.ci95_lower_ppm=zeros(n,1); M.ci95_upper_ppm=zeros(n,1);
  row=0;
  for month=1:12
    for site=1:4
      row+=1; idx=find(round(D.month)==month & round(D.site_id)==site);
      st=demo_environmental_numeric('statistics',D.mean_ppm(idx),struct());
      sem=st.std_sample/sqrt(st.n); half=student_t_975(st.n-1)*sem;
      M.month(row)=month; M.site_id(row)=site; M.n_days(row)=st.n; M.mean_ppm(row)=st.mean;
      M.sd_between_days_ppm(row)=st.std_sample; M.sem_ppm(row)=sem; M.ci95_half_width_ppm(row)=half;
      M.ci95_lower_ppm(row)=max(0,st.mean-half); M.ci95_upper_ppm(row)=st.mean+half;
    endfor
  endfor
endfunction

function S=aggregate_seasonal(D)
  S.category_code=(1:5).';
  S.mean_ppm=NaN(5,4); S.sd_between_days_ppm=NaN(5,4); S.sem_ppm=NaN(5,4); S.ci95_half_width_ppm=NaN(5,4); S.n_days=zeros(5,4);
  for site=1:4
    for cat=1:5
      idx=find(round(D.site_id)==site & seasonal_mask(D,cat));
      if(isempty(idx)), continue; endif
      st=demo_environmental_numeric('statistics',D.mean_ppm(idx),struct());
      sem=st.std_sample/sqrt(st.n); half=student_t_975(st.n-1)*sem;
      S.mean_ppm(cat,site)=st.mean; S.sd_between_days_ppm(cat,site)=st.std_sample; S.sem_ppm(cat,site)=sem; S.ci95_half_width_ppm(cat,site)=half; S.n_days(cat,site)=st.n;
    endfor
  endfor
endfunction

function mask=seasonal_mask(D,cat)
  m=round(D.month); fire=round(D.fire_event_id)>0;
  switch(cat)
    case 1, mask=(m==12|m==1|m==2);
    case 2, mask=(m>=3&m<=5);
    case 3, mask=(m>=6&m<=8&!fire);
    case 4, mask=(m>=6&m<=8&fire);
    case 5, mask=(m>=9&m<=11);
    otherwise, mask=false(size(m));
  endswitch
endfunction

function S=aggregate_site_summary(R,D,seasonal)
  S.site_id=(1:4).'; S.latitude_deg=zeros(4,1); S.longitude_deg=zeros(4,1); S.elevation_m=zeros(4,1);
  fields={'annual_mean_ppm','annual_sd_between_days_ppm','annual_sem_ppm','annual_ci95_half_width_ppm', ...
          'winter_mean_ppm','spring_mean_ppm','summer_nonfire_mean_ppm','summer_fire_mean_ppm','autumn_mean_ppm', ...
          'summer_fire_ci95_half_width_ppm','fire_enhancement_factor','below_lod_count','below_loq_count'};
  for f=1:numel(fields), S.(fields{f})=zeros(4,1); endfor
  for site=1:4
    idx=find(round(D.site_id)==site); st=demo_environmental_numeric('statistics',D.mean_ppm(idx),struct());
    sem=st.std_sample/sqrt(st.n); half=student_t_975(st.n-1)*sem;
    rawidx=find(round(R.site_id)==site);
    S.latitude_deg(site)=environmental_mean(R.latitude(rawidx)); S.longitude_deg(site)=environmental_mean(R.longitude(rawidx)); S.elevation_m(site)=environmental_mean(R.elevation(rawidx));
    S.annual_mean_ppm(site)=st.mean; S.annual_sd_between_days_ppm(site)=st.std_sample; S.annual_sem_ppm(site)=sem; S.annual_ci95_half_width_ppm(site)=half;
    S.winter_mean_ppm(site)=seasonal.mean_ppm(1,site); S.spring_mean_ppm(site)=seasonal.mean_ppm(2,site);
    S.summer_nonfire_mean_ppm(site)=seasonal.mean_ppm(3,site); S.summer_fire_mean_ppm(site)=seasonal.mean_ppm(4,site); S.autumn_mean_ppm(site)=seasonal.mean_ppm(5,site);
    S.summer_fire_ci95_half_width_ppm(site)=seasonal.ci95_half_width_ppm(4,site);
    S.fire_enhancement_factor(site)=S.summer_fire_mean_ppm(site)/S.summer_nonfire_mean_ppm(site);
    S.below_lod_count(site)=sum(R.below_lod(rawidx)>0.5); S.below_loq_count(site)=sum(R.below_loq(rawidx)>0.5);
  endfor
endfunction

function R=pairwise_relationships(D)
  means=daily_site_matrix(D.mean_ppm,D.site_id,D.day_of_year);
  pairs=nchoosek(1:4,2); n=rows(pairs);
  R.pair_code=(1:n).'; R.site_a_id=pairs(:,1); R.site_b_id=pairs(:,2); R.pearson_r=zeros(n,1); R.sample_count=zeros(n,1);
  for i=1:n
    x=means(:,pairs(i,1)); y=means(:,pairs(i,2));
    fit=demo_environmental_numeric('linear_regression',x,y,[],struct('nonfinite','omit','intercept',true));
    R.pearson_r(i)=sign(fit.slope)*sqrt(max(0,min(1,fit.r_squared))); R.sample_count(i)=fit.n;
  endfor
endfunction

function L=cross_site_lag_relationships(D,max_lag)
  means=daily_site_matrix(D.mean_ppm,D.site_id,D.day_of_year);
  pairs=nchoosek(1:4,2); total=rows(pairs)*(2*max_lag+1);
  L.pair_code=zeros(total,1); L.site_a_id=zeros(total,1); L.site_b_id=zeros(total,1);
  L.lag_days=zeros(total,1); L.pearson_r=zeros(total,1); L.sample_count=zeros(total,1);
  row=0;
  for p=1:rows(pairs)
    a=pairs(p,1); b=pairs(p,2); x=means(:,a); y=means(:,b);
    for lag=-max_lag:max_lag
      row+=1;
      if(lag>=0)
        xa=x(1:(end-lag)); yb=y((1+lag):end);
      else
        k=-lag; xa=x((1+k):end); yb=y(1:(end-k));
      endif
      fit=demo_environmental_numeric('linear_regression',xa,yb,[],struct('nonfinite','omit','intercept',true));
      L.pair_code(row)=p; L.site_a_id(row)=a; L.site_b_id(row)=b; L.lag_days(row)=lag;
      L.pearson_r(row)=sign(fit.slope)*sqrt(max(0,min(1,fit.r_squared))); L.sample_count(row)=fit.n;
    endfor
  endfor
endfunction

function Q=qc_analysis(D,cv_threshold)
  Q.day_of_year=D.day_of_year(:); Q.site_id=D.site_id(:); Q.mean_ppm=D.mean_ppm(:); Q.sd_ppm=D.sd_ppm(:);
  Q.cv_percent=100.*D.sd_ppm(:)./max(D.mean_ppm(:),1e-12);
  Q.high_cv=double(Q.cv_percent>cv_threshold);
  Q.any_below_lod=double(D.below_lod_count(:)>0);
  Q.any_below_loq=double(D.below_loq_count(:)>0);
  Q.threshold=cv_threshold;
  Q.high_cv_count=sum(Q.high_cv>0.5); Q.below_lod_sample_count=sum(Q.any_below_lod>0.5); Q.below_loq_sample_count=sum(Q.any_below_loq>0.5);
  Q.site=cell(1,4);
  for site=1:4
    idx=find(round(Q.site_id)==site); [~,ord]=sort(Q.day_of_year(idx)); idx=idx(ord);
    Q.site{site}=struct('day_of_year',Q.day_of_year(idx),'cv_percent',Q.cv_percent(idx),'high_cv',Q.high_cv(idx));
  endfor
endfunction

function A=anomaly_analysis(D,window_days,z_threshold)
  A.day_of_year=[]; A.site_id=[]; A.mean_ppm=[]; A.baseline_ppm=[]; A.residual_ppm=[]; A.robust_z=[]; A.anomaly_flag=[]; A.fire_event_id=[]; A.fire_exposure_index=[];
  A.window_days=window_days; A.z_threshold=z_threshold; A.site=cell(1,4);
  total_anomalies=0; fire_overlap=0;
  for site=1:4
    idx=find(round(D.site_id)==site); [days,ord]=sort(D.day_of_year(idx)); idx=idx(ord); y=D.mean_ppm(idx);
    sm=demo_environmental_numeric('smooth',days,y,struct('method','moving_median','window',window_days,'nonfinite','error'));
    residual=y-sm.y;
    rst=demo_environmental_numeric('statistics',residual,struct()); center=rst.median;
    ast=demo_environmental_numeric('statistics',abs(residual-center),struct()); mad=ast.median;
    scale=max(1.4826*mad,1e-9); rz=(residual-center)./scale; flag=double(rz>=z_threshold);
    ev=D.fire_event_id(idx); ex=D.fire_exposure_index(idx);
    A.day_of_year=[A.day_of_year;days(:)]; A.site_id=[A.site_id;site*ones(numel(days),1)]; A.mean_ppm=[A.mean_ppm;y(:)];
    A.baseline_ppm=[A.baseline_ppm;sm.y(:)]; A.residual_ppm=[A.residual_ppm;residual(:)]; A.robust_z=[A.robust_z;rz(:)]; A.anomaly_flag=[A.anomaly_flag;flag(:)];
    A.fire_event_id=[A.fire_event_id;ev(:)]; A.fire_exposure_index=[A.fire_exposure_index;ex(:)];
    total_anomalies+=sum(flag>0.5); fire_overlap+=sum(flag>0.5 & ex>0);
    A.site{site}=struct('day_of_year',days(:),'robust_z',rz(:),'mean_ppm',y(:),'baseline_ppm',sm.y(:),'anomaly_flag',flag(:));
  endfor
  A.anomaly_count=total_anomalies; A.fire_overlap_count=fire_overlap;
endfunction

function F=fire_relationships(D)
  active=find(D.fire_exposure_index>0 & isfinite(D.nearest_fire_distance_km));
  if(isempty(active)), error('demo.environmental.levoglucosan_campaign: no wildfire-affected daily observations were found'); endif
  [~,imax]=max(D.mean_ppm(active)); strongest_row=active(imax); F.strongest_event_id=round(D.fire_event_id(strongest_row));
  event_rows=find(round(D.fire_event_id)==F.strongest_event_id & D.fire_exposure_index>0);
  F.strongest_event_start_day=min(D.day_of_year(event_rows)); F.strongest_event_end_day=max(D.day_of_year(event_rows));
  F.strongest_event_peak_day=D.day_of_year(strongest_row); F.strongest_event_peak_site=round(D.site_id(strongest_row)); F.strongest_event_peak_ppm=D.mean_ppm(strongest_row);
  F.site=cell(1,4); counts=zeros(4,1);
  for site=1:4
    idx=find(round(D.site_id)==site & D.fire_exposure_index>0 & isfinite(D.nearest_fire_distance_km));
    counts(site)=numel(idx);
    F.site{site}=struct('day_of_year',D.day_of_year(idx),'exposure',D.fire_exposure_index(idx),'mean_ppm',D.mean_ppm(idx), ...
                        'distance_km',D.nearest_fire_distance_km(idx),'sem_ppm',D.sem_ppm(idx));
  endfor
  if(any(counts!=counts(1))), error('demo.environmental.levoglucosan_campaign: fire relationship site row counts differ'); endif
  F.n_fire_days=counts(1);
  F.all_exposure=[]; F.all_mean_ppm=[]; F.all_distance_km=[]; F.all_sem_ppm=[]; F.all_site_id=[];
  for site=1:4
    q=F.site{site};
    F.all_exposure=[F.all_exposure;q.exposure]; F.all_mean_ppm=[F.all_mean_ppm;q.mean_ppm];
    F.all_distance_km=[F.all_distance_km;q.distance_km]; F.all_sem_ppm=[F.all_sem_ppm;q.sem_ppm];
    F.all_site_id=[F.all_site_id;site*ones(numel(q.mean_ppm),1)];
  endfor
endfunction

function U=uncertainty_demo(R,D,event_id)
  event=find(round(D.fire_event_id)==event_id & D.fire_exposure_index>0);
  [~,i]=max(D.mean_ppm(event)); peakrow=event(i); site=round(D.site_id(peakrow));
  lo=max(1,min(D.day_of_year(event))-2); hi=min(365,max(D.day_of_year(event))+2); days=(lo:hi).'; n=numel(days);
  U.day_of_year=days; U.site_id=site*ones(n,1); U.rep1_ppm=NaN(n,1); U.rep2_ppm=NaN(n,1); U.rep3_ppm=NaN(n,1);
  U.mean_ppm=NaN(n,1); U.sd_ppm=NaN(n,1); U.ci95_half_width_ppm=NaN(n,1);
  for j=1:n
    ridx=find(round(R.day_of_year)==days(j)&round(R.site_id)==site); [~,ord]=sort(round(R.replicate_id(ridx))); ridx=ridx(ord);
    vals=R.levoglucosan(ridx); U.rep1_ppm(j)=vals(1); U.rep2_ppm(j)=vals(2); U.rep3_ppm(j)=vals(3);
    didx=find(round(D.day_of_year)==days(j)&round(D.site_id)==site,1); U.mean_ppm(j)=D.mean_ppm(didx); U.sd_ppm(j)=D.sd_ppm(didx); U.ci95_half_width_ppm(j)=D.ci95_half_width_ppm(didx);
  endfor
  U.start_day=lo; U.end_day=hi; U.site=site;
endfunction

function G=build_fire_regression(F,exposure_fit,distance_fit)
  [G.exposure_index,ord]=sort(F.all_exposure); G.exposure_fit_ppm=exposure_fit.intercept+exposure_fit.slope.*G.exposure_index;
  [G.distance_km,ord2]=sort(F.all_distance_km); G.distance_fit_ppm=distance_fit.intercept+distance_fit.slope.*G.distance_km;
endfunction

function M=daily_site_matrix(values,sites,days)
  M=NaN(365,4);
  for i=1:numel(values), M(round(days(i)),round(sites(i)))=values(i); endfor
endfunction


function t=student_t_975(df)
  if(df<1), t=NaN; return; endif
  table=[12.7062047364,4.30265272991,3.18244630528,2.7764451052,2.57058183564,2.44691184879,2.36462425159,2.3060041352,2.26215716285,2.22813885196,2.20098516008,2.17881282966,2.16036865646,2.14478668792,2.13144954556,2.11990529922,2.10981557783,2.10092204024,2.09302405441,2.08596344727,2.07961384473,2.0738730679,2.06865761042,2.06389856163,2.05953855275,2.05552943864,2.05183051648,2.0484071418,2.04522964213,2.0422724563];
  if(df<=30), t=table(round(df)); return; endif
  z=1.95996398454005; v=df;
  t=z+(z^3+z)/(4*v)+(5*z^5+16*z^3+3*z)/(96*v^2)+(3*z^7+19*z^5+17*z^3-15*z)/(384*v^3);
endfunction

function names=site_names()
  names={'Cagliari metropolitan','Gonnostramatza / Marmilla','Nuoro / Barbagia','Olbia / Gallura'};
endfunction

function names=category_names()
  names={'winter','spring','summer non-fire','summer fire','autumn'};
endfunction

function publish_daily_long(session,module_id,version,source_id,D)
  vars={ ...
    'day_of_year','day','independent',D.day_of_year; 'month','', 'independent',D.month; 'site_id','', 'group',D.site_id; ...
    'latitude_deg','deg','coordinate',D.latitude_deg; 'longitude_deg','deg','coordinate',D.longitude_deg; ...
    'mean_ppm','ppm','concentration',D.mean_ppm; 'sd_ppm','ppm','uncertainty',D.sd_ppm; 'sem_ppm','ppm','uncertainty',D.sem_ppm; ...
    'ci95_half_width_ppm','ppm','uncertainty',D.ci95_half_width_ppm; 'ci95_lower_ppm','ppm','uncertainty',D.ci95_lower_ppm; 'ci95_upper_ppm','ppm','uncertainty',D.ci95_upper_ppm; ...
    'fire_event_id','','group',D.fire_event_id; 'fire_exposure_index','','independent',D.fire_exposure_index; ...
    'below_lod_count','','count',D.below_lod_count; 'below_loq_count','','count',D.below_loq_count; 'n_replicates','','count',D.n_replicates};
  publish_numeric_table(session,module_id,version,'demo.environmental.levoglucosan.daily',source_id,vars,'Daily site summary from triplicate IC measurements');
endfunction

function publish_monthly_long(session,module_id,version,source_id,M)
  vars={'month','','independent',M.month; 'site_id','','group',M.site_id; 'n_days','','count',M.n_days; 'mean_ppm','ppm','concentration',M.mean_ppm; ...
        'sd_between_days_ppm','ppm','variability',M.sd_between_days_ppm; 'sem_ppm','ppm','uncertainty',M.sem_ppm; 'ci95_half_width_ppm','ppm','uncertainty',M.ci95_half_width_ppm; ...
        'ci95_lower_ppm','ppm','uncertainty',M.ci95_lower_ppm; 'ci95_upper_ppm','ppm','uncertainty',M.ci95_upper_ppm};
  publish_numeric_table(session,module_id,version,'demo.environmental.levoglucosan.monthly',source_id,vars,'Monthly site statistics calculated from daily site means');
endfunction

function publish_seasonal_long(session,module_id,version,source_id,S)
  category=[]; site_id=[]; mean_ppm=[]; ci=[]; n_days=[];
  for cat=1:5
    for site=1:4
      category(end+1,1)=cat; site_id(end+1,1)=site;
      mean_ppm(end+1,1)=S.mean_ppm(cat,site); ci(end+1,1)=S.ci95_half_width_ppm(cat,site); n_days(end+1,1)=S.n_days(cat,site);
    endfor
  endfor
  vars={'category_code','','season_category',category; 'site_id','','group',site_id; 'mean_ppm','ppm','concentration',mean_ppm; ...
        'ci95_half_width_ppm','ppm','uncertainty',ci; 'n_days','','count',n_days};
  publish_numeric_table(session,module_id,version,'demo.environmental.levoglucosan.seasonal',source_id,vars,'Seasonal categories: 1 winter, 2 spring, 3 summer non-fire, 4 summer fire, 5 autumn');
endfunction

function publish_site_summary(session,module_id,version,source_id,S)
  vars={'site_id','','group',S.site_id; 'latitude_deg','deg','coordinate',S.latitude_deg; 'longitude_deg','deg','coordinate',S.longitude_deg; 'elevation_m','m','coordinate',S.elevation_m; ...
        'annual_mean_ppm','ppm','concentration',S.annual_mean_ppm; 'annual_sd_between_days_ppm','ppm','variability',S.annual_sd_between_days_ppm; 'annual_sem_ppm','ppm','uncertainty',S.annual_sem_ppm; 'annual_ci95_half_width_ppm','ppm','uncertainty',S.annual_ci95_half_width_ppm; ...
        'winter_mean_ppm','ppm','concentration',S.winter_mean_ppm; 'spring_mean_ppm','ppm','concentration',S.spring_mean_ppm; 'summer_nonfire_mean_ppm','ppm','concentration',S.summer_nonfire_mean_ppm; 'summer_fire_mean_ppm','ppm','concentration',S.summer_fire_mean_ppm; 'autumn_mean_ppm','ppm','concentration',S.autumn_mean_ppm; ...
        'summer_fire_ci95_half_width_ppm','ppm','uncertainty',S.summer_fire_ci95_half_width_ppm; 'fire_enhancement_factor','','ratio',S.fire_enhancement_factor; ...
        'below_lod_count','','count',S.below_lod_count; 'below_loq_count','','count',S.below_loq_count};
  publish_numeric_table(session,module_id,version,'demo.environmental.levoglucosan.site_summary',source_id,vars,'Annual and seasonal four-site campaign summary');
endfunction

function publish_relationships(session,module_id,version,source_id,R)
  vars={'pair_code','','group',R.pair_code; 'site_a_id','','group',R.site_a_id; 'site_b_id','','group',R.site_b_id; 'pearson_r','','correlation',R.pearson_r; 'sample_count','','count',R.sample_count};
  publish_numeric_table(session,module_id,version,'demo.environmental.levoglucosan.relationships',source_id,vars,'Pairwise synchronized daily-mean site correlations');
endfunction

function publish_cross_site_lag(session,module_id,version,source_id,L)
  row_index=(1:numel(L.pearson_r)).';
  vars={'row_index','','independent',row_index; 'pair_code','','group',L.pair_code; 'site_a_id','','group',L.site_a_id; 'site_b_id','','group',L.site_b_id; ...
        'lag_days','day','independent',L.lag_days; 'pearson_r','','correlation',L.pearson_r; 'sample_count','','count',L.sample_count};
  publish_numeric_table(session,module_id,version,'demo.environmental.levoglucosan.cross_site_lag',source_id,vars,'Pairwise synchronized cross-site correlations over configured day lags');
endfunction

function publish_fire_relationships(session,module_id,version,source_id,F)
  day=[]; site_id=[]; exposure=[]; mean_ppm=[]; distance=[]; sem=[];
  for site=1:4
    q=F.site{site}; n=numel(q.day_of_year);
    day=[day; q.day_of_year(:)]; site_id=[site_id; repmat(site,n,1)]; exposure=[exposure; q.exposure(:)];
    mean_ppm=[mean_ppm; q.mean_ppm(:)]; distance=[distance; q.distance_km(:)]; sem=[sem; q.sem_ppm(:)];
  endfor
  vars={'day_of_year','day','independent',day; 'site_id','','group',site_id; 'fire_exposure_index','','independent',exposure; ...
        'mean_ppm','ppm','concentration',mean_ppm; 'distance_km','km','independent',distance; 'sem_ppm','ppm','uncertainty',sem};
  publish_numeric_table(session,module_id,version,'demo.environmental.levoglucosan.fire_relationships',source_id,vars,'Long-form fire-affected daily observations for relationship analysis');
endfunction

function publish_fire_regressions(session,module_id,version,source_id,G)
  publish_numeric_table(session,module_id,version,'demo.environmental.levoglucosan.fire_exposure_regression',source_id, ...
    {'exposure_index','','independent',G.exposure_index; 'fit_ppm','ppm','fitted',G.exposure_fit_ppm}, ...
    'Weighted linear regression line for wildfire exposure');
  publish_numeric_table(session,module_id,version,'demo.environmental.levoglucosan.fire_distance_regression',source_id, ...
    {'distance_km','km','independent',G.distance_km; 'fit_ppm','ppm','fitted',G.distance_fit_ppm}, ...
    'Weighted linear regression line for active-fire distance');
endfunction

function publish_uncertainty_demo(session,module_id,version,source_id,U)
  vars={'day_of_year','day','independent',U.day_of_year; 'site_id','','group',U.site_id; 'replicate_1_ppm','ppm','concentration',U.rep1_ppm; 'replicate_2_ppm','ppm','concentration',U.rep2_ppm; 'replicate_3_ppm','ppm','concentration',U.rep3_ppm; ...
        'daily_mean_ppm','ppm','concentration',U.mean_ppm; 'replicate_sd_ppm','ppm','uncertainty',U.sd_ppm; 'daily_ci95_half_width_ppm','ppm','uncertainty',U.ci95_half_width_ppm};
  publish_numeric_table(session,module_id,version,'demo.environmental.levoglucosan.uncertainty_demo',source_id,vars,'Representative triplicate measurements with daily mean, replicate SD and Student-t 95% confidence interval');
endfunction

function publish_qc_daily(session,module_id,version,source_id,Q)
  row_index=(1:numel(Q.day_of_year)).';
  vars={'row_index','','independent',row_index; 'day_of_year','day','independent',Q.day_of_year; 'site_id','','group',Q.site_id; ...
        'mean_ppm','ppm','concentration',Q.mean_ppm; 'sd_ppm','ppm','uncertainty',Q.sd_ppm; 'cv_percent','','ratio',Q.cv_percent; ...
        'high_cv','','generic',Q.high_cv; 'any_below_lod','','generic',Q.any_below_lod; 'any_below_loq','','generic',Q.any_below_loq};
  publish_numeric_table(session,module_id,version,'demo.environmental.levoglucosan.qc_daily',source_id,vars,'Daily analytical-QC summary from technical triplicates');
endfunction

function publish_anomalies(session,module_id,version,source_id,A)
  row_index=(1:numel(A.day_of_year)).';
  vars={'row_index','','independent',row_index; 'day_of_year','day','independent',A.day_of_year; 'site_id','','group',A.site_id; ...
        'mean_ppm','ppm','concentration',A.mean_ppm; 'baseline_ppm','ppm','baseline',A.baseline_ppm; 'residual_ppm','ppm','residual',A.residual_ppm; ...
        'robust_z','','generic',A.robust_z; 'anomaly_flag','','generic',A.anomaly_flag; 'fire_event_id','','group',A.fire_event_id; 'fire_exposure_index','','independent',A.fire_exposure_index};
  publish_numeric_table(session,module_id,version,'demo.environmental.levoglucosan.anomalies',source_id,vars,'Moving-median residuals and positive robust anomaly scores');
endfunction

function publish_qc_plot_datasets(session,module_id,version,source_id,Q)
  for site=1:4
    q=Q.site{site};
    vars={'day_of_year','day','independent',q.day_of_year; 'cv_percent','','ratio',q.cv_percent; 'high_cv','','generic',q.high_cv};
    publish_numeric_table(session,module_id,version,sprintf('demo.environmental.levoglucosan.qc.site%d',site),source_id,vars,sprintf('Daily technical-replicate CV plotting Dataset for site %d',site));
  endfor
endfunction

function publish_anomaly_plot_datasets(session,module_id,version,source_id,A)
  for site=1:4
    q=A.site{site};
    vars={'day_of_year','day','independent',q.day_of_year; 'robust_z','','generic',q.robust_z; 'mean_ppm','ppm','concentration',q.mean_ppm; ...
          'baseline_ppm','ppm','baseline',q.baseline_ppm; 'anomaly_flag','','generic',q.anomaly_flag};
    publish_numeric_table(session,module_id,version,sprintf('demo.environmental.levoglucosan.anomaly.site%d',site),source_id,vars,sprintf('Robust anomaly-score plotting Dataset for site %d',site));
  endfor
endfunction

function publish_site_plot_datasets(session,module_id,version,source_id,D,M,S,F)
  for site=1:4
    idx=find(round(D.site_id)==site); [~,ord]=sort(D.day_of_year(idx)); idx=idx(ord);
    vars={'day_of_year','day','independent',D.day_of_year(idx); 'mean_ppm','ppm','concentration',D.mean_ppm(idx); ...
          'ci95_half_width_ppm','ppm','uncertainty',D.ci95_half_width_ppm(idx); 'ci95_lower_ppm','ppm','uncertainty',D.ci95_lower_ppm(idx); 'ci95_upper_ppm','ppm','uncertainty',D.ci95_upper_ppm(idx)};
    publish_numeric_table(session,module_id,version,sprintf('demo.environmental.levoglucosan.daily.site%d',site),source_id,vars,sprintf('Daily plotting Dataset for site %d',site));

    idx=find(round(M.site_id)==site); [~,ord]=sort(M.month(idx)); idx=idx(ord);
    vars={'month','','independent',M.month(idx); 'mean_ppm','ppm','concentration',M.mean_ppm(idx); 'ci95_half_width_ppm','ppm','uncertainty',M.ci95_half_width_ppm(idx)};
    publish_numeric_table(session,module_id,version,sprintf('demo.environmental.levoglucosan.monthly.site%d',site),source_id,vars,sprintf('Monthly plotting Dataset for site %d',site));

    vars={'category_code','','season_category',S.category_code; 'mean_ppm','ppm','concentration',S.mean_ppm(:,site); 'ci95_half_width_ppm','ppm','uncertainty',S.ci95_half_width_ppm(:,site); 'n_days','','count',S.n_days(:,site)};
    publish_numeric_table(session,module_id,version,sprintf('demo.environmental.levoglucosan.seasonal.site%d',site),source_id,vars,sprintf('Seasonal plotting Dataset for site %d',site));

    xmin=max(1,F.strongest_event_start_day-2); xmax=min(365,F.strongest_event_end_day+2);
    idx=find(round(D.site_id)==site & D.day_of_year>=xmin & D.day_of_year<=xmax); [~,ord]=sort(D.day_of_year(idx)); idx=idx(ord);
    vars={'day_of_year','day','independent',D.day_of_year(idx); 'mean_ppm','ppm','concentration',D.mean_ppm(idx); 'ci95_half_width_ppm','ppm','uncertainty',D.ci95_half_width_ppm(idx)};
    publish_numeric_table(session,module_id,version,sprintf('demo.environmental.levoglucosan.wildfire.site%d',site),source_id,vars,sprintf('Strongest-wildfire plotting Dataset for site %d',site));

    q=F.site{site};
    vars={'day_of_year','day','independent',q.day_of_year; 'fire_exposure_index','','independent',q.exposure; 'distance_km','km','independent',q.distance_km; ...
          'mean_ppm','ppm','concentration',q.mean_ppm; 'sem_ppm','ppm','uncertainty',q.sem_ppm};
    publish_numeric_table(session,module_id,version,sprintf('demo.environmental.levoglucosan.fire.site%d',site),source_id,vars,sprintf('Fire-relationship plotting Dataset for site %d',site));
  endfor
endfunction

function publish_numeric_table(session,module_id,version,dataset_id,source_id,vars,provenance)
  opts=struct('storage','csv','producer_version',version,'source_dataset_ids',source_id,'provenance',provenance,'replace_owned',true);
  P=gxtxt_publication_v2_open(session,module_id,dataset_id,'table.generic',opts); complete=false;
  unwind_protect
    P=gxtxt_publication_v2_declare_dimension(P,'row',0,true);
    for i=1:rows(vars)
      vid=vars{i,1}; unit=vars{i,2}; role=vars{i,3};
      spec=struct('name',vid,'unit',unit,'dtype','float64','dimension_ids','row','semantic_role',role);
      if(i==1)
        spec.coordinate_role='coordinate'; spec.axis_kind='explicit';
      else
        spec.coordinate_role='data'; spec.coordinate_variable_ids=vars{1,1};
      endif
      P=gxtxt_publication_v2_declare_variable(P,vid,spec);
    endfor
    blocks=cell(rows(vars),2);
    for i=1:rows(vars)
      values=vars{i,4}(:);
      if(any(!isfinite(values)))
        error('%s: publication %s variable %s contains non-finite values; publish only quantities defined for every row',module_id,dataset_id,vars{i,1});
      endif
      blocks{i,1}=vars{i,1}; blocks{i,2}=values;
    endfor
    P=gxtxt_publication_v2_append(P,'row',blocks);
    [P,published]=gxtxt_publication_v2_finalize(P); complete=true;
  unwind_protect_cleanup
    if(!complete), try P=gxtxt_publication_v2_abort(P); catch; end_try_catch, endif
  end_unwind_protect
endfunction

function write_metrics(outdir,source_id,R,D,M,S,site,rel,crosslag,F,exposure_fit,distance_fit,Q,A,lod,loq,O)
  path=fullfile(outdir,'levoglucosan_campaign_metrics.ini'); fid=fopen(path,'w'); if(fid<0), error('cannot write metrics'); endif
  names=site_names();
  unwind_protect
    fprintf(fid,'[campaign]\nsource_dataset_id=%s\nsynthetic=true\nreplicate_rows=%d\ndaily_site_samples=%d\nsite_count=4\nday_count=365\nreplicates_per_sample=3\nlod_ppm=%.9g\nloq_ppm=%.9g\n',source_id,numel(R.levoglucosan),numel(D.mean_ppm),lod,loq);
    fprintf(fid,'below_lod_replicates=%d\nbelow_loq_replicates=%d\nstrongest_fire_event_id=%d\nstrongest_fire_start_day=%d\nstrongest_fire_end_day=%d\nstrongest_fire_peak_day=%d\nstrongest_fire_peak_site=%d\nstrongest_fire_peak_ppm=%.12g\n', ...
      sum(R.below_lod>0.5),sum(R.below_loq>0.5),F.strongest_event_id,F.strongest_event_start_day,F.strongest_event_end_day,F.strongest_event_peak_day,F.strongest_event_peak_site,F.strongest_event_peak_ppm);
    fprintf(fid,'\n[output_groups]\ncampaign_summary=%d\nseasonality=%d\nfire_events=%d\nuncertainty_qc=%d\ncross_site=%d\nanomaly_detection=%d\nspatial_analysis=%d\nrender_2d_graphs=%d\nrender_3d_graphs=%d\n', ...
      O.output_campaign_summary,O.output_seasonality,O.output_fire_events,O.output_uncertainty_qc,O.output_cross_site,O.output_anomaly_detection,O.output_spatial_analysis,O.render_2d_graphs,O.render_3d_graphs);
    fprintf(fid,'\n[qc]\ncv_threshold_percent=%.9g\nhigh_cv_daily_samples=%d\ndaily_samples_with_below_lod=%d\ndaily_samples_with_below_loq=%d\n',Q.threshold,Q.high_cv_count,Q.below_lod_sample_count,Q.below_loq_sample_count);
    fprintf(fid,'\n[anomaly_detection]\nwindow_days=%d\nrobust_z_threshold=%.9g\npositive_anomalies=%d\nanomalies_overlapping_fire_exposure=%d\n',A.window_days,A.z_threshold,A.anomaly_count,A.fire_overlap_count);
    fprintf(fid,'\n[cross_site]\nmax_lag_days=%d\nlag_rows=%d\n',O.cross_site_max_lag_days,numel(crosslag.pearson_r));
    fprintf(fid,'\n[fire_exposure_regression]\nslope=%.15g\nintercept=%.15g\nr_squared=%.15g\nsample_count=%d\nweighted=true\nweight_semantics=inverse_variance_from_daily_sem\n',exposure_fit.slope,exposure_fit.intercept,exposure_fit.r_squared,exposure_fit.n);
    fprintf(fid,'\n[fire_distance_regression]\nslope=%.15g\nintercept=%.15g\nr_squared=%.15g\nsample_count=%d\nweighted=true\nweight_semantics=inverse_variance_from_daily_sem\n',distance_fit.slope,distance_fit.intercept,distance_fit.r_squared,distance_fit.n);
    for site_id=1:4
      fprintf(fid,'\n[site.%d]\nname=%s\nlatitude_deg=%.9g\nlongitude_deg=%.9g\nelevation_m=%.9g\nannual_mean_ppm=%.12g\nwinter_mean_ppm=%.12g\nspring_mean_ppm=%.12g\nsummer_nonfire_mean_ppm=%.12g\nsummer_fire_mean_ppm=%.12g\nautumn_mean_ppm=%.12g\nfire_enhancement_factor=%.12g\nbelow_lod_count=%d\nbelow_loq_count=%d\n', ...
        site_id,names{site_id},site.latitude_deg(site_id),site.longitude_deg(site_id),site.elevation_m(site_id),site.annual_mean_ppm(site_id),site.winter_mean_ppm(site_id),site.spring_mean_ppm(site_id),site.summer_nonfire_mean_ppm(site_id),site.summer_fire_mean_ppm(site_id),site.autumn_mean_ppm(site_id),site.fire_enhancement_factor(site_id),site.below_lod_count(site_id),site.below_loq_count(site_id));
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_report(outdir,source_id,R,D,M,S,site,rel,crosslag,F,exposure_fit,distance_fit,Q,A,lod,loq,O)
  path=fullfile(outdir,'levoglucosan_campaign_report.txt'); fid=fopen(path,'w'); if(fid<0), error('cannot write report'); endif
  names=site_names();
  unwind_protect
    fprintf(fid,'Sardinia Levoglucosan Campaign Demo - Configurable Scientific Report\n');
    fprintf(fid,'====================================================================\n\n');
    fprintf(fid,'SCIENTIFIC STATUS\nAll campaign measurements analyzed here are synthetic. The 2025 calendar is a deterministic modeling frame and does not imply that these measurements occurred in 2025.\n\n');
    fprintf(fid,'ENABLED OUTPUT GROUPS\nCampaign summary: %s\nSeasonality: %s\nWildfire events: %s\nMeasurement uncertainty / QC: %s\nCross-site: %s\nAnomaly detection: %s\nSpatial analysis: %s\n2D graphs: %s\n3D spatial views: %s\n\n', ...
      yn(O.output_campaign_summary),yn(O.output_seasonality),yn(O.output_fire_events),yn(O.output_uncertainty_qc),yn(O.output_cross_site),yn(O.output_anomaly_detection),yn(O.output_spatial_analysis),yn(O.render_2d_graphs),yn(O.render_3d_graphs&&O.output_spatial_analysis));
    fprintf(fid,'CAMPAIGN AND ANALYTICAL METHOD\nSource Dataset: %s\nFour Sardinian reference areas, 365 daily PM aerosol filter samples per site, three technical IC replicates per sample.\nAnalytical context: synthetic HPAEC-PAD / IC-PAD determination of levoglucosan in an aqueous filter extract.\nReported concentration: ppm in extract, with 1 ppm = 1 mg/L = 1 ug/mL.\nReplicate rows: %d; daily site samples: %d.\nLOD: %.6g ppm; LOQ: %.6g ppm. Values below limits are retained and flagged rather than replaced with zero.\n\n',source_id,numel(R.levoglucosan),numel(D.mean_ppm),lod,loq);

    if(O.output_campaign_summary)
      fprintf(fid,'CAMPAIGN SUMMARY\n');
      for s=1:4
        fprintf(fid,'%d. %s: annual mean %.5g ppm; coordinates %.4f deg, %.4f deg; elevation %.1f m.\n',s,names{s},site.annual_mean_ppm(s),site.latitude_deg(s),site.longitude_deg(s),site.elevation_m(s));
      endfor
      fprintf(fid,'\nMONTHLY EXTREMES\n');
      for s=1:4
        idx=find(round(M.site_id)==s); [mx,imax]=max(M.mean_ppm(idx)); [mn,imin]=min(M.mean_ppm(idx)); rows_idx=idx;
        fprintf(fid,'%s: highest monthly mean month %d = %.5g ppm; lowest month %d = %.5g ppm.\n',names{s},round(M.month(rows_idx(imax))),mx,round(M.month(rows_idx(imin))),mn);
      endfor
      fprintf(fid,'\n');
    endif

    if(O.output_seasonality)
      fprintf(fid,'SEASONALITY\n');
      for s=1:4
        fprintf(fid,'%s: winter %.5g; spring %.5g; summer non-fire %.5g; summer fire %.5g; autumn %.5g ppm.\n',names{s},site.winter_mean_ppm(s),site.spring_mean_ppm(s),site.summer_nonfire_mean_ppm(s),site.summer_fire_mean_ppm(s),site.autumn_mean_ppm(s));
      endfor
      fprintf(fid,'\n');
    endif

    if(O.output_uncertainty_qc)
      fprintf(fid,'MEASUREMENT UNCERTAINTY AND QC\nDaily replicate SD describes dispersion among the three technical IC replicates. SEM = SD/sqrt(3). Daily 95%% confidence intervals use Student t with df=2. The demonstration QC high-CV threshold is %.4g%% and is a configurable teaching threshold, not a universal analytical acceptance criterion.\nHigh-CV daily samples: %d. Daily samples with at least one below-LOD replicate: %d; with at least one below-LOQ replicate: %d.\n\n',Q.threshold,Q.high_cv_count,Q.below_lod_sample_count,Q.below_loq_sample_count);
    endif

    if(O.output_fire_events)
      fprintf(fid,'WILDFIRE EVENTS AND RELATIONSHIPS\nEvent ID %d spans campaign days %d-%d. The largest affected daily mean is %.5g ppm on day %d at %s.\n',F.strongest_event_id,F.strongest_event_start_day,F.strongest_event_end_day,F.strongest_event_peak_ppm,F.strongest_event_peak_day,names{F.strongest_event_peak_site});
      fprintf(fid,'Weighted regression versus fire exposure: slope %.6g ppm/index, intercept %.6g ppm, R^2 %.5g, n=%d.\n',exposure_fit.slope,exposure_fit.intercept,exposure_fit.r_squared,exposure_fit.n);
      fprintf(fid,'Weighted regression versus nearest active-fire distance: slope %.6g ppm/km, intercept %.6g ppm, R^2 %.5g, n=%d.\nThese are relationships in generated measurements, not independent causal evidence.\n\n',distance_fit.slope,distance_fit.intercept,distance_fit.r_squared,distance_fit.n);
    endif

    if(O.output_cross_site)
      fprintf(fid,'CROSS-SITE RELATIONSHIPS\n');
      for i=1:numel(rel.pearson_r)
        fprintf(fid,'%s vs %s: same-day Pearson r = %.5f, n = %d.\n',names{round(rel.site_a_id(i))},names{round(rel.site_b_id(i))},rel.pearson_r(i),round(rel.sample_count(i)));
      endfor
      for pair=1:6
        idx=find(round(crosslag.pair_code)==pair); [~,j]=max(abs(crosslag.pearson_r(idx))); k=idx(j);
        fprintf(fid,'Pair %d (%s vs %s): strongest |r| within +/- %d days at lag %+d d: r=%.5f, n=%d.\n',pair,names{round(crosslag.site_a_id(k))},names{round(crosslag.site_b_id(k))},O.cross_site_max_lag_days,round(crosslag.lag_days(k)),crosslag.pearson_r(k),round(crosslag.sample_count(k)));
      endfor
      fprintf(fid,'\n');
    endif

    if(O.output_anomaly_detection)
      fprintf(fid,'ANOMALY DETECTION\nA %d-day moving-median baseline is subtracted independently at each site. Positive residuals are scaled with 1.4826 x MAD; robust-z >= %.4g is flagged. This is a descriptive event detector, not source apportionment.\nDetected positive anomalies: %d; anomalies overlapping non-zero synthetic fire exposure: %d.\n',A.window_days,A.z_threshold,A.anomaly_count,A.fire_overlap_count);
      for s=1:4
        q=A.site{s}; idx=find(q.anomaly_flag>0.5);
        if(isempty(idx))
          fprintf(fid,'%s: no flagged anomaly.\n',names{s});
        else
          [z,j]=max(q.robust_z(idx)); k=idx(j); fprintf(fid,'%s: %d flagged days; highest score %.4g on day %d.\n',names{s},numel(idx),z,round(q.day_of_year(k)));
        endif
      endfor
      fprintf(fid,'\n');
    endif

    if(O.output_spatial_analysis)
      fprintf(fid,'SPATIAL ANALYSIS\nThe four sites span urban/coastal, rural inland, mountain inland and north-eastern coastal settings. Site-level geographical comparisons are descriptive because four sites do not form a statistically dense spatial survey.\nThe optional 3D topographic view uses longitude, latitude and elevation as geometry and annual mean levoglucosan as color. The optional wildfire 3D surface uses longitude/latitude with summer wildfire mean concentration as Z and enhancement factor as color. Its Delaunay triangles provide connectivity only; GX-TXT does not claim spatial interpolation between the four sites.\n\n');
    endif

    fprintf(fid,'DERIVED DATASETS (always published for reuse)\n');
    ids={'demo.environmental.levoglucosan.daily','demo.environmental.levoglucosan.monthly','demo.environmental.levoglucosan.seasonal','demo.environmental.levoglucosan.site_summary','demo.environmental.levoglucosan.relationships','demo.environmental.levoglucosan.cross_site_lag','demo.environmental.levoglucosan.fire_relationships','demo.environmental.levoglucosan.fire_exposure_regression','demo.environmental.levoglucosan.fire_distance_regression','demo.environmental.levoglucosan.uncertainty_demo','demo.environmental.levoglucosan.qc_daily','demo.environmental.levoglucosan.anomalies'};
    for i=1:numel(ids), fprintf(fid,'%s\n',ids{i}); endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function s=yn(v), if(v),s='yes';else s='no';endif, endfunction

function run_plot_helper(outdir,session,F,U,O,groups)
  runtime_dir=fileparts(mfilename('fullpath')); helper=fullfile(runtime_dir,'create_automatic_graphs.tcl');
  if(exist(helper,'file')!=2), error('demo.environmental.levoglucosan_campaign: plot helper is missing'); endif
  cmd=['tclsh ' shell_quote(helper) ' --session ' shell_quote(session) ' --output-dir ' shell_quote(outdir) ...
       ' --fire-event-id ' num2str(F.strongest_event_id) ' --fire-start-day ' num2str(F.strongest_event_start_day) ...
       ' --fire-end-day ' num2str(F.strongest_event_end_day) ' --uncertainty-start-day ' num2str(U.start_day) ...
       ' --uncertainty-end-day ' num2str(U.end_day) ' --uncertainty-site ' num2str(U.site) ...
       ' --groups ' shell_quote(groups) ' --qc-threshold ' num2str(O.qc_cv_threshold_percent,'%.15g') ...
       ' --anomaly-threshold ' num2str(O.anomaly_z_threshold,'%.15g')];
  [status,text]=system(cmd);
  if(status!=0), error('demo.environmental.levoglucosan_campaign: automatic plot.dataset graph generation failed: %s',strtrim(text)); endif
  if(!isempty(strtrim(text))), fprintf('%s\n',strtrim(text)); endif
endfunction

function write_empty_graph_manifest(outdir)
  path=fullfile(outdir,'automatic_graphs.ini'); fid=fopen(path,'w'); if(fid<0), error('cannot write automatic graph manifest'); endif
  unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=0\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\npersistent_variants=true\n');
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function files=render_spatial_3d(session,outdir,runtime_cfg)
  files={'13_spatial_3d_topography.png','14_spatial_3d_fire_surface.png'};
  dataset='demo.environmental.levoglucosan.site_summary';
  base=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_3d', ...
    'graph_id','plot.dataset.xyz','dataset_id',dataset, ...
    'x_variable_id','longitude_deg','y_variable_id','latitude_deg');
  top=base;top.z_variable_id='elevation_m';top.color_variable_id='annual_mean_ppm';
  top.family_variable_id='site_id';
  top.title='Sardinia monitoring sites - topography and annual levoglucosan';
  top.config=struct('plot_type','scatter3','marker_size',11,'legend_content','family', ...
    'family_label_prefix','Site','x_label','Longitude [deg]', ...
    'y_label','Latitude [deg]','z_label','h [m]','reduction_mode','none');
  fire=base;fire.z_variable_id='summer_fire_mean_ppm';
  fire.color_variable_id='fire_enhancement_factor';
  fire.title='Four-site wildfire response - descriptive triangulated connectivity';
  fire.config=struct('plot_type','trisurf','x_label','Longitude [deg]', ...
    'y_label','Latitude [deg]','z_label','C [ppm]', ...
    'reduction_mode','none');
  items={struct('key','spatial_topography','spec',top,'png',files{1}), ...
    struct('key','spatial_fire_surface','spec',fire,'png',files{2})};
  gxtxt_plot_provider_render_v1(session,outdir,'demo.environmental.levoglucosan_campaign',items,'base',true);
endfunction

function write_output_manifest(outdir,O,groups,files3d)
  path=fullfile(outdir,'analysis_outputs.ini'); fid=fopen(path,'w'); if(fid<0), error('cannot write output manifest'); endif
  unwind_protect
    fprintf(fid,'[analysis_outputs]\nmodule_version=1.2.1\n2d_groups=%s\n2d_enabled=%d\n3d_enabled=%d\n3d_count=%d\n',groups,O.render_2d_graphs,O.render_3d_graphs&&O.output_spatial_analysis,numel(files3d));
    fprintf(fid,'campaign_summary=%d\nseasonality=%d\nfire_events=%d\nuncertainty_qc=%d\ncross_site=%d\nanomaly_detection=%d\nspatial_analysis=%d\n',O.output_campaign_summary,O.output_seasonality,O.output_fire_events,O.output_uncertainty_qc,O.output_cross_site,O.output_anomaly_detection,O.output_spatial_analysis);
    for i=1:numel(files3d), fprintf(fid,'3d_file_%d=%s\n',i,files3d{i}); endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function q=shell_quote(s)
  sq=char(39); dq=char(34); replacement=[sq dq sq dq sq]; q=[sq strrep(s,sq,replacement) sq];
endfunction

function value=arg_value(args,name,default_value)
  value=default_value;
  for i=1:(numel(args)-1), if(strcmp(args{i},name)), value=args{i+1}; return; endif, endfor
endfunction

function v=environmental_mean(values)
  s=demo_environmental_numeric('reduce_summary',double(values(:)),struct());v=s.mean;
endfunction
