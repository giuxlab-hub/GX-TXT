function [groups,stats]=pd_prepare_3d_canonical_grid(info,opts,runtime_config)
% Canonical rank-two grid consumer. CORE owns metadata and typed nD reads.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(!isempty(info.family)),error('plot.dataset: a rank-two grid has one surface; publish separate grids for families');endif
  if(strcmpi(opts.reduction_mode,'minmax')),error('plot.dataset: canonical grids support none/auto/stride display reduction; minmax would move Z to different physical coordinates');endif
  before=gxtxt_curve_source_dataset_identity_v1(info.session,info.dataset_id);
  gxtxt_script_bridge_start(runtime_config,struct('script_name','Plot Dataset canonical grid','script_sha256','module-owned-reader','arguments_raw',''));
  unwind_protect
    metadata=gxtxt_api_call('CANONICAL_DATASET_API_v2','describe',{info.dataset_id});
    xmeta=variable(metadata,info.x_variable_id);ymeta=variable(metadata,info.y_variable_id);zmeta=variable(metadata,info.z_variable_id);
    sx=shape(xmeta);sy=shape(ymeta);sz=shape(zmeta);
    if(numel(sx)!=1||numel(sy)!=1||numel(sz)!=2||!isequal(sz,[sy,sx])|| ...
       strcmp(xmeta.dimension_ids,ymeta.dimension_ids)||!strcmp(zmeta.dimension_ids,[ymeta.dimension_ids ';' xmeta.dimension_ids]))
      error('plot.dataset: canonical Z must have the exact Y/X axis dimensions; no transposition is inferred');
    endif
    nx=sx;ny=sy;n=nx*ny;
    if(nx<2||ny<2||nx>100000||ny>100000||n>100000000),error('plot.dataset: canonical surface needs2..100000 coordinates per axis and at most100 million cells');endif
    if(!strcmp(xmeta.unit,info.x_meta.unit)||!strcmp(ymeta.unit,info.y_meta.unit)||!strcmp(zmeta.unit,info.z_meta.unit)),error('plot.dataset: physical units changed after runtime binding');endif
    x=read_values(info,info.x_variable_id,0,nx);y=read_values(info,info.y_variable_id,0,ny);
    if(!(all(diff(x)>0)||all(diff(x)<0))||!(all(diff(y)>0)||all(diff(y)<0))),error('plot.dataset: canonical grid axes must be strictly monotonic; no sorting is inferred');endif
    color=!isempty(info.color);
    if(color)
      cmeta=variable(metadata,info.color_variable_id);
      if(!isequal(shape(cmeta),sz)||!strcmp(cmeta.dimension_ids,zmeta.dimension_ids)),error('plot.dataset: canonical color must share the exact Z dimensions');endif
    endif
    stride=1;
    if(!strcmpi(opts.reduction_mode,'none')&&(!strcmpi(opts.reduction_mode,'auto')||n>opts.auto_reduce_threshold)),stride=max(1,ceil(sqrt(n/max(4,opts.target_points))));endif
    xi=unique([1:stride:nx,nx]);yi=unique([1:stride:ny,ny]);
    if(numel(xi)*numel(yi)>8000000),error('plot.dataset: displayed grid exceeds8 million cells; enable display reduction');endif
    Z=nan(numel(yi),numel(xi));C=[];if(color),C=Z;endif
    [ix,iy]=meshgrid(xi,yi);identities=uint64(iy-1)+uint64(ix-1)*uint64(ny);
    chunk=min(ny,65536);cols=max(1,floor(65536/chunk));read_count=0;
    gxtxt_progress_stage('canonical_grid','Reading exact canonical grid cells','determinate',n);
    for cx=1:cols:nx
      nc=min(cols,nx-cx+1);
      for cy=1:chunk:ny
        nr=min(chunk,ny-cy+1);
        values=read_values(info,info.z_variable_id,[cy-1,cx-1],[nr,nc]);
        if(color),colors=read_values(info,info.color_variable_id,[cy-1,cx-1],[nr,nc]);endif
        px=find(xi>=cx&xi<cx+nc);py=find(yi>=cy&yi<cy+nr);
        if(!isempty(px)&&!isempty(py))
          Z(py,px)=values(yi(py)-cy+1,xi(px)-cx+1);
          if(color),C(py,px)=colors(yi(py)-cy+1,xi(px)-cx+1);endif
        endif
        read_count+=nr*nc;gxtxt_progress_update(read_count,n,'canonical_grid','Validating all cells; retaining bounded display samples');
      endfor
    endfor
    if(!isequal(before,gxtxt_curve_source_dataset_identity_v1(info.session,info.dataset_id))),error('plot.dataset: canonical grid changed during preparation');endif
    groups=struct('key','__single__','x',x(xi).','y',y(yi).','z',Z,'c',C,'source_row_indices',double(identities));
    reduction='none';if(stride>1),reduction='grid_stride';endif
    stats=struct('valid_rows',n,'dropped_rows',0,'display_rows',numel(Z),'group_count',1,...
      'requested_reduction',opts.reduction_mode,'effective_reduction',reduction,...
      'source_layout','canonical_grid_yx','source_index_order','column_major','source_index_base',0,'interpolation_performed',false);
  unwind_protect_cleanup
    gxtxt_script_bridge_stop();
  end_unwind_protect
endfunction
function v=variable(metadata,id)
  variables=metadata.variables;
  for k=1:numel(variables)
    if(iscell(variables)),candidate=variables{k};else candidate=variables(k);endif
    if(strcmp(candidate.variable_id,id)),v=candidate;return;endif
  endfor
  error('plot.dataset: canonical grid Variable is unavailable: %s',id);
endfunction
function s=shape(v)
  if(ischar(v.shape)),s=str2double(strsplit(v.shape,';'));else s=v.shape(:).';endif
  if(ischar(v.rank)),rank=str2double(v.rank);else rank=v.rank;endif
  if(numel(s)!=rank||any(!isfinite(s)|s<1|s!=fix(s))),error('plot.dataset: invalid canonical grid shape');endif
endfunction
function values=read_values(info,id,starts,counts)
  block=gxtxt_api_call('CANONICAL_DATASET_API_v2','read_hyperslab',{info.dataset_id,id,starts,counts});values=block.values;
  if(!isreal(values)||(!isnumeric(values)&&!islogical(values))|| ...
    (isa(values,'uint64')&&any(values(:)>uint64(flintmax)))|| ...
    (isa(values,'int64')&&any(values(:)>int64(flintmax)|values(:)<-int64(flintmax))))
    error('plot.dataset: grid display cannot narrow these canonical values exactly');
  endif
  values=double(values);
  if(any(!isfinite(values(:)))),error('plot.dataset: grid contains nonfinite coordinates/cells; no interpolation or hole filling is performed');endif
endfunction
