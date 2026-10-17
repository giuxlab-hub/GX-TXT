function R=gxtxt_numeric_replicate_summary_v1(Y,source_ids,options)
% Numerical owner for aligned replicate/source profile reductions and envelopes.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<3),options=struct();endif
  if(!isstruct(options)||!isscalar(options)),error('GXTXT:Numeric','Replicate options must be a scalar struct');endif
  for key=fieldnames(options)'
    if(!any(strcmp(key{1},{'mode','sampling_model','local_dispersion','local_available'}))),error('GXTXT:Numeric','Unknown replicate option: %s',key{1});endif
  endfor
  mode='labelled_traces_anova';sampling='unspecified';
  if(isfield(options,'mode')),mode=options.mode;endif
  if(isfield(options,'sampling_model')),sampling=options.sampling_model;endif
  if(!ischar(mode)||!any(strcmp(mode,{'labelled_traces_anova','unlabelled_point_cloud'}))),error('GXTXT:Numeric','Unknown replicate mode');endif
  if(!ischar(sampling)||!any(strcmp(sampling,{'unspecified','independent_traces'}))),error('GXTXT:Numeric','Unknown replicate sampling model');endif
  if(!isnumeric(Y)||!isreal(Y)||ndims(Y)>2||isempty(Y)||any(!isfinite(Y(:)))),error('GXTXT:Numeric','Replicate values must be a finite real matrix: rows=coordinates, columns=curves');endif
  if(!isnumeric(source_ids)||!isreal(source_ids)||!isvector(source_ids)||numel(source_ids)!=columns(Y)||any(!isfinite(source_ids(:)))||any(source_ids(:)<1)||any(source_ids(:)!=fix(source_ids(:)))),error('GXTXT:Numeric','Each curve needs one positive integer source ID');endif
  Y=double(Y);source_ids=double(source_ids(:)');n=columns(Y);nx=rows(Y);
  sources=unique(source_ids);ns=numel(sources);counts=zeros(1,ns);
  for j=1:ns,counts(j)=sum(source_ids==sources(j));endfor
  source_means=zeros(nx,ns);
  for j=1:ns
    block=Y(:,source_ids==sources(j));group=gxtxt_numeric_v1('reduce_summary',block,struct('dimension',2));source_means(:,j)=group.mean(:);
  endfor
  row=gxtxt_numeric_v1('matrix_statistics',Y,struct('dimension',2));
  location=row.mean(:);middle=row.median(:);spread=NaN(nx,1);
  if(n>=2),spread=row.std_sample(:);endif
  sem=NaN(nx,1);within=NaN(nx,1);between=NaN(nx,1);total=NaN(nx,1);
  identifiable=zeros(nx,1);clamped=NaN(nx,1);df=NaN;coefficient=NaN;
  if(strcmp(mode,'unlabelled_point_cloud'))
    if(!strcmp(sampling,'unspecified')||n!=ns),error('GXTXT:Numeric','Cloud profiles require one curve per source and cannot assert independent repeat counts');endif
    if(!isfield(options,'local_dispersion')),error('GXTXT:Numeric','Cloud profiles require captured local dispersion');endif
    local=options.local_dispersion;
    if(!isnumeric(local)||!isreal(local)||!isequal(size(local),size(Y))||any(isinf(local(:)))||any(local(:)<0)),error('GXTXT:Numeric','Local dispersion must match the profile matrix and contain nonnegative values or NaN');endif
    if(isfield(options,'local_available'))
      available=options.local_available;
      if(!(isnumeric(available)||islogical(available))||!isreal(available)||!isequal(size(available),size(Y))||any(!isfinite(available(:)))||any(available(:)!=0&available(:)!=1)),error('GXTXT:Numeric','Local availability must be a matching zero/one matrix');endif
      if(any(!isfinite(local(logical(available))))),error('GXTXT:Numeric','Available local dispersion must be finite');endif
      local(!logical(available))=NaN;
    endif
    if(ns>=2)
      available=all(isfinite(local),2);identifiable(available)=1;
      for i=find(available)',within(i)=norm(local(i,:))/sqrt(n);endfor
      between(available)=row.std_sample(available);total(available)=hypot(within(available),between(available));
      spread(available)=total(available);
    endif
    component_method='local_residual_rms_plus_source_location_spread';
  else
    if(isfield(options,'local_dispersion')||isfield(options,'local_available')),error('GXTXT:Numeric','Labelled profiles do not accept local cloud dispersion');endif
    if(n>=2&&strcmp(sampling,'independent_traces')),sem=spread/sqrt(n);endif
    df=n-ns;
    if(ns>=2),coefficient=(n-sum(counts.^2)/n)/(ns-1);endif
    if(ns>=2&&df>0&&coefficient>0)
      identifiable(:)=1;ssw=zeros(nx,1);ssb=zeros(nx,1);
      for j=1:ns
        block=Y(:,source_ids==sources(j));center=source_means(:,j);ssw+=sum((block-center).^2,2);ssb+=counts(j)*(center-location).^2;
      endfor
      msw=ssw/df;msb=ssb/(ns-1);raw_between=(msb-msw)/coefficient;
      clamped=double(raw_between<0);within=sqrt(msw);between=sqrt(max(0,raw_between));total=hypot(within,between);
    endif
    component_method='one_way_random_effects_unequal_counts_nonnegative_between';
  endif
  R=struct('y_mean',location,'y_median',middle,'y_std',spread,'y_sem',sem, ...
    'sigma_within',within,'sigma_between',between,'sigma_total',total,'n',n,'n_sources',ns, ...
    'within_df',df,'component_coefficient',coefficient,'components_identifiable',identifiable,'between_clamped',clamped, ...
    'lower_std',location-spread,'upper_std',location+spread,'lower_sem',location-sem,'upper_sem',location+sem, ...
    'lower_total',location-total,'upper_total',location+total, ...
    'mode',mode,'sampling_model',sampling,'component_method',component_method, ...
    'source_ids',source_ids,'source_counts',counts,'sources',sources,'source_means',source_means);
  for key=fieldnames(R)'
    value=R.(key{1});if(isnumeric(value)&&any(isinf(value(:)))),error('GXTXT:Numeric','Replicate reduction exceeds finite numerical range');endif
  endfor
endfunction
