function analysis_xas_normalize_main(args,framework_root)
% XAS normalization workflow. Generic calculus, smoothing, fitting and array
% arithmetic are delegated to NUMERIC_API_v1.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.xas.normalize'; module_version='1.0.2';
  config_path=arg_value(args,'--config',''); if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path); session=strtrim(gxtxt_ini_get(cfg,'runtime.session','')); outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  source_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id','')); contract=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.contract',''));
  if(isempty(contract)),contract=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.kind',''));endif
  if(isempty(session)||isempty(outdir)||isempty(source_id)),error('%s: Session, output directory and primary Dataset are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  numeric=discover_numeric_api(cfg,module_id);
  output_id=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','xas.normalized')); validate_id(output_id,module_id);
  rep=lower(strtrim(gxtxt_ini_get(cfg,'config.output_representation','normalized'))); if(!any(strcmp(rep,{'normalized','flattened'}))),error('%s: output representation is invalid',module_id);endif
  failed_policy=lower(strtrim(gxtxt_ini_get(cfg,'config.failed_member_policy','skip_with_report')));
  if(!any(strcmp(failed_policy,{'skip_with_report','error'}))),error('%s: failed member policy is invalid',module_id);endif
  gxtxt_progress_start('read','Reading XAS spectra','indeterminate');
  try
    [x_unit,~,x_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary','spectral_x');
    [y_unit,~,y_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary','spectral_y');
    [parameter_unit,~,parameter_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary','parameter_value');
    if(isempty(parameter_unit)),parameter_unit='1';endif
    if(!(isstruct(x_meta)&&isfield(x_meta,'found')&&x_meta.found)),error('%s: spectral_x is unavailable',module_id);endif
    if(!(isstruct(y_meta)&&isfield(y_meta,'found')&&y_meta.found)),error('%s: spectral_y is unavailable',module_id);endif
    if(isempty(x_unit)),error('%s: spectral_x requires an energy unit',module_id);endif
    if(!gxtxt_unit_compatible(x_unit,'eV')),error('%s: spectral_x unit %s is not compatible with eV',module_id,x_unit);endif
    if(strcmp(contract,'spectrum.family'))
      members=read_family(cfg,module_id);
    elseif(strcmp(contract,'spectrum.scientific'))
      [x,y]=read_single(cfg,module_id); members={struct('member_id','spectrum','parameter_value',1,'x',x,'y',y)};
    else
      error('%s: unsupported source contract %s',module_id,contract);
    endif
    gxtxt_progress_stage('normalize','Normalizing XAS spectra','determinate',numel(members));
    normalized={}; diagnostics=struct([]); failures={};
    for i=1:numel(members)
      M=members{i};
      try
        R=normalize_one(M.x,M.y,x_unit,cfg,numeric,module_id);
        R.member_id=M.member_id; R.parameter_value=M.parameter_value;
        normalized{end+1}=R; diagnostics(end+1)=diag_row(R,'PASS','');
      catch err
        if(strcmp(failed_policy,'error') || !strcmp(contract,'spectrum.family')),rethrow(err);endif
        failures{end+1}=sprintf('%s: %s',M.member_id,err.message);
        diagnostics(end+1)=diag_fail(M,err.message);
      end_try_catch
      gxtxt_progress_update(i,numel(members),'normalize',sprintf('Processed %d / %d spectra',i,numel(members)));
    endfor
    if(isempty(normalized)),error('%s: no spectrum could be normalized',module_id);endif
    if(strcmp(contract,'spectrum.family') && numel(normalized)<2),error('%s: fewer than two family members remain after explicit failures',module_id);endif
    gxtxt_progress_stage('publish','Publishing normalized XAS Dataset','indeterminate');
    if(strcmp(contract,'spectrum.family'))
      publish_family(session,module_id,module_version,output_id,source_id,x_unit,parameter_unit,rep,normalized);
    else
      publish_single(session,module_id,module_version,output_id,source_id,x_unit,rep,normalized{1});
    endif
    diag_id=[output_id '.diagnostics']; publish_diagnostics(session,module_id,module_version,diag_id,source_id,parameter_unit,diagnostics);
    write_diagnostics_csv(fullfile(outdir,'xas_normalization_diagnostics.csv'),diagnostics);
    write_report(fullfile(outdir,'xas_normalization_report.txt'),module_id,module_version,source_id,output_id,contract,x_unit,rep,normalized,diagnostics,failures);
    gxtxt_progress_complete('done',sprintf('XAS normalization completed: %d spectrum/spectra published',numel(normalized)));
    fprintf('[%s] version=%s source=%s output=%s normalized=%d failures=%d representation=%s\n',module_id,module_version,source_id,output_id,numel(normalized),numel(failures),rep);
  catch err
    try gxtxt_progress_fail('failed','XAS normalization failed; see log for details');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function api=discover_numeric_api(cfg,module_id)
  sec='public_api.NUMERIC_API_v1'; provider=strtrim(gxtxt_ini_get(cfg,[sec '.module_id'],''));
  if(!strcmp(provider,'math.numeric')),error('%s: runtime NUMERIC_API_v1 provider discovery failed',module_id);endif
  caps=split_list(gxtxt_ini_get(cfg,[sec '.capabilities'],''));
  required={'differentiation','smoothing','polynomial_fit','elementwise_binary','array_reduction'};
  for k=1:numel(required),if(!any(strcmp(caps,required{k}))),error('%s: NUMERIC_API_v1 capability missing: %s',module_id,required{k});endif,endfor
  entry=strtrim(gxtxt_ini_get(cfg,[sec '.octave_entrypoint'],'')); fn=strtrim(gxtxt_ini_get(cfg,[sec '.octave_function'],''));
  if(isempty(entry)||isempty(fn)||exist(entry,'file')!=2),error('%s: runtime NUMERIC_API_v1 Octave binding unavailable',module_id);endif
  addpath(fileparts(entry)); if(exist(fn,'file')!=2),error('%s: advertised NUMERIC_API_v1 function unavailable',module_id);endif
  api=struct('function_name',fn);
endfunction

function members=read_family(cfg,module_id)
  S=gxtxt_table_stream_open_source(cfg,'primary',{'member_id','parameter_value','spectral_x','spectral_y'},25000,struct());
  ids={}; params=[]; xs={}; ys={}; index=containers.Map('KeyType','char','ValueType','int32');
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S); if(C.nrows==0),continue;endif
      cid=gxtxt_table_chunk_column(C,'member_id'); cp=gxtxt_table_chunk_numeric(C,'parameter_value'); cx=gxtxt_table_chunk_numeric(C,'spectral_x'); cy=gxtxt_table_chunk_numeric(C,'spectral_y');
      for r=1:C.nrows
        id=char(cid{r});
        if(!isKey(index,id))
          j=numel(ids)+1; index(id)=j; ids{j}=id; params(j)=cp(r); xs{j}=zeros(0,1); ys{j}=zeros(0,1);
        else
          j=index(id); if(params(j)!=cp(r)),error('%s: family parameter changes within member %s',module_id,id);endif
        endif
        xs{j}(end+1,1)=cx(r); ys{j}(end+1,1)=cy(r);
      endfor
    endwhile
  unwind_protect_cleanup
    gxtxt_table_stream_close(S);
  end_unwind_protect
  members=cell(1,numel(ids)); for j=1:numel(ids),members{j}=struct('member_id',ids{j},'parameter_value',params(j),'x',xs{j},'y',ys{j});endfor
endfunction
function [x,y]=read_single(cfg,module_id)
  S=gxtxt_table_stream_open_source(cfg,'primary',{'spectral_x','spectral_y'},25000,struct()); x=zeros(0,1);y=zeros(0,1);
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S); if(C.nrows==0),continue;endif
      x=[x;gxtxt_table_chunk_numeric(C,'spectral_x')]; y=[y;gxtxt_table_chunk_numeric(C,'spectral_y')];
    endwhile
  unwind_protect_cleanup
    gxtxt_table_stream_close(S);
  end_unwind_protect
  if(numel(x)<2||numel(y)!=numel(x)),error('%s: invalid scientific spectrum',module_id);endif
endfunction

function R=normalize_one(x_source,mu,x_unit,cfg,numeric,module_id)
  fn=numeric.function_name; x_source=double(x_source(:)); mu=double(mu(:));
  fx=feval(fn,'array_unary','is_finite',x_source,struct()); fy=feval(fn,'array_unary','is_finite',mu,struct());
  good=feval(fn,'array_mask','logical_and',fx.values,fy.values); sx=feval(fn,'array_select',x_source,good.values); sy=feval(fn,'array_select',mu,good.values);
  x_source=sx.values;mu=sy.values;
  if(numel(x_source)<8),error('%s: at least eight finite samples are required for XAS normalization',module_id);endif
  x_eV=gxtxt_unit_convert(x_source,x_unit,'eV'); x_eV=double(x_eV(:));
  grid=feval(fn,'grid_info',x_eV,struct());
  if(!grid.strict_monotonic),error('%s: XAS energy must be strictly monotonic',module_id);endif
  if(strcmp(grid.direction,'decreasing')),x_eV=flipud(x_eV);x_source=flipud(x_source);mu=flipud(mu);endif
  e0_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.e0_mode','auto')));
  smooth_n=str2double(strtrim(gxtxt_ini_get(cfg,'config.derivative_smoothing_points','5')));
  if(!isfinite(smooth_n)||smooth_n<1||smooth_n!=fix(smooth_n)||mod(smooth_n,2)==0),error('%s: derivative smoothing points must be a positive odd integer',module_id);endif
  if(strcmp(e0_mode,'manual'))
    requested=parse_required(gxtxt_ini_get(cfg,'config.e0_eV',''),module_id,'Manual E0');
    delta=feval(fn,'array_binary','subtract',x_eV,requested,struct()); ad=feval(fn,'array_unary','abs',delta.values,struct()); nearest=feval(fn,'array_reduce','argmin',ad.values,struct('axis',0));
    ie0=round(nearest.values(1));e0=x_eV(ie0);e0_method='manual_nearest_sample';
  elseif(strcmp(e0_mode,'auto'))
    D=feval(fn,'differentiate',x_eV,mu,struct()); dy=D.dy_dx;
    if(smooth_n>1),Sm=feval(fn,'smooth',x_eV,dy,struct('method','moving_mean','window',smooth_n));dy=Sm.y;endif
    margin=max(2,floor(smooth_n/2));margin=min(margin,floor((numel(dy)-1)/3));candidate=dy((1+margin):(end-margin));
    A=feval(fn,'array_reduce','argmax',candidate,struct('axis',0));idx=round(A.values(1))+margin;ie0=idx;e0=x_eV(ie0);e0_method='max_smoothed_derivative';
  else
    error('%s: E0 mode must be auto or manual',module_id);
  endif
  [pre1,pre2,norm1,norm2]=fit_offsets(cfg,x_eV,e0,numeric,module_id);
  lo=feval(fn,'array_binary','add',e0,pre1,struct());hi=feval(fn,'array_binary','add',e0,pre2,struct());
  a=feval(fn,'array_compare','greater_equal',x_eV,lo.values,struct());b=feval(fn,'array_compare','less_equal',x_eV,hi.values,struct());pre_mask=feval(fn,'array_mask','logical_and',a.values,b.values);
  lo=feval(fn,'array_binary','add',e0,norm1,struct());hi=feval(fn,'array_binary','add',e0,norm2,struct());
  a=feval(fn,'array_compare','greater_equal',x_eV,lo.values,struct());b=feval(fn,'array_compare','less_equal',x_eV,hi.values,struct());post_mask=feval(fn,'array_mask','logical_and',a.values,b.values);
  npre=feval(fn,'array_reduce','count_true',pre_mask.values,struct('axis',0));if(npre.values(1)<2),error('%s: pre-edge range contains fewer than two samples',module_id);endif
  width=norm2-norm1;order_text=lower(strtrim(gxtxt_ini_get(cfg,'config.normalization_order','auto')));
  if(strcmp(order_text,'auto')),if(width<30),nnorm=0;elseif(width<300),nnorm=1;else nnorm=2;endif;else nnorm=str2double(order_text);endif
  if(!isfinite(nnorm)||nnorm<0||nnorm>2||nnorm!=fix(nnorm)),error('%s: normalization order must be auto, 0, 1 or 2',module_id);endif
  npost=feval(fn,'array_reduce','count_true',post_mask.values,struct('axis',0));if(npost.values(1)<nnorm+1),error('%s: post-edge range has insufficient samples for polynomial order %d',module_id,nnorm);endif
  px=feval(fn,'array_select',x_eV,pre_mask.values);py=feval(fn,'array_select',mu,pre_mask.values);
  prefit=feval(fn,'polynomial_fit',px.values,py.values,1,[],struct('center_scale',true));
  preall=feval(fn,'polynomial_evaluate',prefit,x_eV,struct());pre=preall.yq;
  corrected=feval(fn,'array_binary','subtract',mu,pre,struct());corrected=corrected.values;
  qx=feval(fn,'array_select',x_eV,post_mask.values);qy=feval(fn,'array_select',corrected,post_mask.values);
  postfit=feval(fn,'polynomial_fit',qx.values,qy.values,nnorm,[],struct('center_scale',true));
  postall=feval(fn,'polynomial_evaluate',postfit,x_eV,struct());postcorr=postall.yq;
  pre0=feval(fn,'polynomial_evaluate',prefit,e0,struct());post0=feval(fn,'polynomial_evaluate',postfit,e0,struct());edge=post0.yq(1);
  edgeabs=feval(fn,'array_unary','abs',edge,struct());if(!isfinite(edge)||edgeabs.values(1)<=1e-15),error('%s: edge step is zero or numerically undefined',module_id);endif
  norm=feval(fn,'array_binary','divide',corrected,edge,struct());norm=norm.values;
  residue=feval(fn,'array_binary','divide',postcorr,edge,struct());residue=residue.values;
  residue0=feval(fn,'array_binary','divide',post0.yq(1),edge,struct());residue0=residue0.values(1);
  flat=feval(fn,'array_binary','subtract',norm,residue,struct());flat=flat.values;flat=feval(fn,'array_binary','add',flat,residue0,struct());flat=flat.values;
  before=feval(fn,'array_compare','less_than',x_eV,e0,struct());merged=feval(fn,'array_where',before.values,norm,flat);flat=merged.values;
  representation=lower(strtrim(gxtxt_ini_get(cfg,'config.output_representation','normalized')));if(strcmp(representation,'flattened')),outy=flat;else outy=norm;endif
  R=struct('x',x_source,'mu',mu,'normalized',norm,'flattened',flat,'output_y',outy,'e0_eV',e0,'e0_method',e0_method,'edge_step',edge, ...
    'pre1_eV',pre1,'pre2_eV',pre2,'norm1_eV',norm1,'norm2_eV',norm2,'normalization_order',nnorm,'sample_count',numel(x_source));
endfunction

function [pre1,pre2,norm1,norm2]=fit_offsets(cfg,x,e0,numeric,module_id)
  fn=numeric.function_name;pre1=optional_num(gxtxt_ini_get(cfg,'config.pre1_eV',''));pre2=optional_num(gxtxt_ini_get(cfg,'config.pre2_eV',''));norm1=optional_num(gxtxt_ini_get(cfg,'config.norm1_eV',''));norm2=optional_num(gxtxt_ini_get(cfg,'config.norm2_eV',''));
  if(isnan(pre1))
    d=feval(fn,'array_binary','subtract',x(1),e0,struct());q=feval(fn,'array_binary','divide',d.values,5,struct());q=feval(fn,'array_unary','round',q.values,struct());q=feval(fn,'array_binary','multiply',q.values,5,struct());pre1=q.values(1);if(pre1==0),pre1=d.values(1);endif
  endif
  if(isnan(pre2)),q=feval(fn,'array_binary','multiply',pre1,0.5,struct());pre2=q.values(1);endif
  if(isnan(norm2))
    d=feval(fn,'array_binary','subtract',x(end),e0,struct());q=feval(fn,'array_binary','divide',d.values,5,struct());q=feval(fn,'array_unary','round',q.values,struct());q=feval(fn,'array_binary','multiply',q.values,5,struct());norm2=q.values(1);if(norm2<=0),norm2=d.values(1);endif
  endif
  if(isnan(norm1))
    q=feval(fn,'array_binary','divide',norm2,15,struct());q=feval(fn,'array_unary','round',q.values,struct());q=feval(fn,'array_binary','multiply',q.values,5,struct());q=feval(fn,'array_binary','minimum',25,q.values,struct());norm1=q.values(1);
    if(norm1<=0),d=feval(fn,'array_binary','subtract',x(end),e0,struct());q=feval(fn,'array_binary','multiply',d.values,0.25,struct());q=feval(fn,'array_binary','maximum',q.values,1e-12,struct());norm1=q.values(1);endif
  endif
  if(!(pre1<pre2&&pre2<0&&norm1>0&&norm2>norm1)),error('%s: invalid pre/post-edge offsets: pre1 < pre2 < 0 < norm1 < norm2 is required',module_id);endif
endfunction
function v=optional_num(s),s=strtrim(s);if(isempty(s)),v=NaN;else v=str2double(s);if(!isfinite(v)),v=NaN;endif,endif;endfunction
function v=parse_required(s,module_id,label),v=str2double(strtrim(s));if(!isfinite(v)),error('%s: %s must be finite',module_id,label);endif;endfunction

function publish_family(session,module_id,module_version,id,source_id,x_unit,parameter_unit,rep,members)
  P=struct();opened=false;done=false;
  try
    opts=pub_opts(module_version,source_id,sprintf('XAS %s spectral family',rep));
    P=gxtxt_publication_v2_open(session,module_id,id,'spectrum.family',opts);opened=true;P=gxtxt_publication_v2_declare_dimension(P,'row',0,true);
    P=gxtxt_publication_v2_declare_variable(P,'member_id',struct('dtype','string','dimension_ids','row','name','Member ID','semantic_role','member_identity'));
    P=gxtxt_publication_v2_declare_variable(P,'parameter_value',struct('dtype','float64','dimension_ids','row','name','Family parameter','unit',parameter_unit,'semantic_role','parameter'));
    P=gxtxt_publication_v2_declare_variable(P,'spectral_x',struct('dtype','float64','dimension_ids','row','name','Energy','unit',x_unit,'semantic_role','independent','coordinate_role','coordinate','axis_kind','explicit'));
    P=gxtxt_publication_v2_declare_variable(P,'spectral_y',struct('dtype','float64','dimension_ids','row','name',sprintf('XAS %s',rep),'unit','1','semantic_role','measured','coordinate_variable_ids','spectral_x'));
    for i=1:numel(members)
      R=members{i};n=numel(R.x);items={'member_id',repmat({R.member_id},n,1);'parameter_value',repmat(R.parameter_value,n,1);'spectral_x',R.x(:);'spectral_y',R.output_y(:)};
      P=gxtxt_publication_v2_append(P,'row',items);
    endfor
    [P,~]=gxtxt_publication_v2_diagnostics(P);[P,~]=gxtxt_publication_v2_finalize(P);done=true;opened=false;
  catch err
    if(opened&&!done),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif;rethrow(err);
  end_try_catch
endfunction
function publish_single(session,module_id,module_version,id,source_id,x_unit,rep,R)
  P=struct();opened=false;done=false;
  try
    opts=pub_opts(module_version,source_id,sprintf('XAS %s spectrum',rep));P=gxtxt_publication_v2_open(session,module_id,id,'spectrum.scientific',opts);opened=true;P=gxtxt_publication_v2_declare_dimension(P,'sample',0,true);
    P=gxtxt_publication_v2_declare_variable(P,'spectral_x',struct('dtype','float64','dimension_ids','sample','name','Energy','unit',x_unit,'semantic_role','independent','coordinate_role','coordinate','axis_kind','explicit'));
    P=gxtxt_publication_v2_declare_variable(P,'spectral_y',struct('dtype','float64','dimension_ids','sample','name',sprintf('XAS %s',rep),'unit','1','semantic_role','measured','coordinate_variable_ids','spectral_x'));
    P=gxtxt_publication_v2_append(P,'sample',{'spectral_x',R.x(:);'spectral_y',R.output_y(:)});[P,~]=gxtxt_publication_v2_diagnostics(P);[P,~]=gxtxt_publication_v2_finalize(P);done=true;opened=false;
  catch err
    if(opened&&!done),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif;rethrow(err);
  end_try_catch
endfunction
function opts=pub_opts(version,source_id,note)
  opts=struct('storage','auto','replace_owned',true,'producer_version',version,'source','GX-TXT XAS normalization','provenance',sprintf('analysis.xas.normalize %s via NUMERIC_API_v1',version),'notes',note);
  opts.source_dataset_ids={source_id};opts.source_variable_ids={'spectral_x','spectral_y'};
endfunction

function publish_diagnostics(session,module_id,module_version,id,source_id,parameter_unit,D)
  P=struct();opened=false;done=false;
  try
    opts=pub_opts(module_version,source_id,'Per-spectrum XAS normalization diagnostics.');P=gxtxt_publication_v2_open(session,module_id,id,'table.generic',opts);opened=true;P=gxtxt_publication_v2_declare_dimension(P,'result',0,true);
    strs={'member_id','status','message','e0_method'};for i=1:numel(strs),P=gxtxt_publication_v2_declare_variable(P,strs{i},struct('dtype','string','dimension_ids','result','name',strs{i},'semantic_role','label'));endfor
    nums={'parameter_value','e0_eV','edge_step','pre1_eV','pre2_eV','norm1_eV','norm2_eV','normalization_order','sample_count'};
    for i=1:numel(nums),u='';if(strcmp(nums{i},'parameter_value')),u=parameter_unit;elseif(strcmp(nums{i},'e0_eV')||!isempty(strfind(nums{i},'_eV'))),u='eV';endif;P=gxtxt_publication_v2_declare_variable(P,nums{i},struct('dtype','float64','dimension_ids','result','name',nums{i},'unit',u,'semantic_role','derived'));endfor
    items=diag_items(D);P=gxtxt_publication_v2_append(P,'result',items);[P,~]=gxtxt_publication_v2_finalize(P);done=true;opened=false;
  catch err
    if(opened&&!done),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif;rethrow(err);
  end_try_catch
endfunction
function items=diag_items(D)
  items={'member_id',{D.member_id}';'status',{D.status}';'message',{D.message}';'e0_method',{D.e0_method}'; ...
    'parameter_value',[D.parameter_value]';'e0_eV',[D.e0_eV]';'edge_step',[D.edge_step]';'pre1_eV',[D.pre1_eV]';'pre2_eV',[D.pre2_eV]'; ...
    'norm1_eV',[D.norm1_eV]';'norm2_eV',[D.norm2_eV]';'normalization_order',[D.normalization_order]';'sample_count',[D.sample_count]'};
endfunction
function d=diag_row(R,status,msg),d=struct('member_id',R.member_id,'status',status,'message',msg,'e0_method',R.e0_method,'parameter_value',R.parameter_value,'e0_eV',R.e0_eV,'edge_step',R.edge_step,'pre1_eV',R.pre1_eV,'pre2_eV',R.pre2_eV,'norm1_eV',R.norm1_eV,'norm2_eV',R.norm2_eV,'normalization_order',R.normalization_order,'sample_count',R.sample_count);endfunction
function d=diag_fail(M,msg),d=struct('member_id',M.member_id,'status','FAIL','message',msg,'e0_method','','parameter_value',M.parameter_value,'e0_eV',NaN,'edge_step',NaN,'pre1_eV',NaN,'pre2_eV',NaN,'norm1_eV',NaN,'norm2_eV',NaN,'normalization_order',NaN,'sample_count',numel(M.x));endfunction

function write_diagnostics_csv(path,D)
  f=fopen(path,'w');if(f<0),error('analysis.xas.normalize: cannot write diagnostics CSV');endif
  unwind_protect
    fprintf(f,'member_id,status,e0_eV,edge_step,pre1_eV,pre2_eV,norm1_eV,norm2_eV,normalization_order,sample_count,message\n');
    for i=1:numel(D),fprintf(f,'%s,%s,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,"%s"\n',D(i).member_id,D(i).status,D(i).e0_eV,D(i).edge_step,D(i).pre1_eV,D(i).pre2_eV,D(i).norm1_eV,D(i).norm2_eV,D(i).normalization_order,D(i).sample_count,strrep(D(i).message,'"','""'));endfor
  unwind_protect_cleanup fclose(f);end_unwind_protect
endfunction
function write_report(path,module_id,version,source_id,output_id,contract,x_unit,rep,N,D,failures)
  f=fopen(path,'w');if(f<0),error('%s: cannot write report',module_id);endif
  unwind_protect
    fprintf(f,'GX-TXT XAS normalization\nModule: %s %s\nSource Dataset: %s\nSource contract: %s\nEnergy unit: %s\nOutput Dataset: %s\nRepresentation: %s\nPublished spectra: %d\nFailed/skipped members: %d\n\n',module_id,version,source_id,contract,x_unit,output_id,rep,numel(N),numel(failures));
    fprintf(f,'E0 is either user-selected or the maximum of a NUMERIC_API derivative after the configured moving-mean smoothing. Pre/post-edge fits use public NUMERIC_API polynomial fitting/evaluation. Normalization arithmetic uses public NUMERIC_API array operations.\n\n');
    for i=1:numel(D),fprintf(f,'%s  %s  E0=%g eV  edge_step=%g  pre=[%g,%g] eV  post=[%g,%g] eV  order=%g  %s\n',D(i).member_id,D(i).status,D(i).e0_eV,D(i).edge_step,D(i).pre1_eV,D(i).pre2_eV,D(i).norm1_eV,D(i).norm2_eV,D(i).normalization_order,D(i).message);endfor
  unwind_protect_cleanup fclose(f);end_unwind_protect
endfunction
function validate_id(id,module_id),if(isempty(regexp(id,'^[A-Za-z0-9_.-]+$','once'))),error('%s: invalid output Dataset ID',module_id);endif;endfunction
function v=arg_value(args,key,def),v=def;for i=1:(numel(args)-1),if(strcmp(args{i},key)),v=args{i+1};return;endif;endfor;endfunction
function out=split_list(s),parts=strsplit(strrep(char(s),',',';'),';');out={};for i=1:numel(parts),q=strtrim(parts{i});if(!isempty(q)),out{end+1}=q;endif;endfor;endfunction
