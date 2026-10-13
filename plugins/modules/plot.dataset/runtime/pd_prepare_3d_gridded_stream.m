function [groups,stats]=pd_prepare_3d_gridded_stream(info,opts,plot_type)
% Prepare a rectangular XYZ grid without materializing all scientific rows.
% The complete source is validated; only a bounded display grid is retained.
% SPDX-License-Identifier: GPL-3.0-or-later
  cols={info.x,info.y,info.z};
  if(!isempty(info.color)),cols{end+1}=info.color;endif
  if(!isempty(info.family)),cols{end+1}=info.family;endif
  raw_keys={};raw_counts=[];raw_x={};raw_y={};
  raw_map=containers.Map('KeyType','char','ValueType','int32');
  valid=0;dropped=0;family_numeric=!isempty(info.family);
  if(isempty(info.family))
    raw_keys={'__single__'};raw_counts=0;raw_x={[]};raw_y={[]};raw_map('__single__')=int32(1);
  endif
  if(isempty(info.family)&&isempty(info.color))
    st=gxtxt_table_stream_open_numeric_fast(info.source_path,cols,opts.chunk_rows);
  else
    st=gxtxt_table_stream_open(info.source_path,cols,opts.chunk_rows);
  endif
  total=max(1,st.total_bytes);
  gxtxt_progress_stage('grid_scan',sprintf('Scanning %s grid axes',plot_type),'determinate',total);
  unwind_protect
    while(true)
      [st,ch]=gxtxt_table_stream_next(st);
      if(ch.nrows>0)
        x=gxtxt_table_chunk_numeric(ch,info.x);y=gxtxt_table_chunk_numeric(ch,info.y);z=gxtxt_table_chunk_numeric(ch,info.z);
        if(!isempty(info.color)),c=gxtxt_table_chunk_numeric(ch,info.color);else c=[];endif
        good=isfinite(x)&isfinite(y)&isfinite(z);if(!isempty(c)),good=good&isfinite(c);endif
        if(isempty(info.family))
          n=sum(good);dropped+=ch.nrows-n;valid+=n;raw_counts(1)+=n;
          raw_x{1}=unique([raw_x{1};x(good)]);raw_y{1}=unique([raw_y{1};y(good)]);
          if(numel(raw_x{1})>100000||numel(raw_y{1})>100000)
            error('plot.dataset: grid axis exceeds 100000 coordinates; publish a bounded derived display Dataset');
          endif
        else
          fam=grid_family_values(ch,info.family);gids=zeros(ch.nrows,1);
          for i=1:ch.nrows
            if(!good(i)||isempty(strtrim(fam{i}))),dropped+=1;continue;endif
            key=strtrim(fam{i});
            if(!isfinite(str2double(key))),family_numeric=false;endif
            if(!isKey(raw_map,key))
              raw_keys{end+1}=key;raw_counts(end+1)=0;raw_x{end+1}=[];raw_y{end+1}=[];
              raw_map(key)=int32(numel(raw_keys));
            endif
            gi=double(raw_map(key));gids(i)=gi;raw_counts(gi)+=1;valid+=1;
          endfor
          for gi=reshape(unique(gids(gids>0)),1,[])
            pick=(gids==gi);xx=x(pick);yy=y(pick);
            raw_x{gi}=unique([raw_x{gi};xx(:)]);raw_y{gi}=unique([raw_y{gi};yy(:)]);
            if(numel(raw_x{gi})>100000||numel(raw_y{gi})>100000)
              error('plot.dataset: grid axis exceeds 100000 coordinates; publish a bounded derived display Dataset');
            endif
          endfor
        endif
        if(valid>100000000),error('plot.dataset: grid exceeds 100 million cells; publish a bounded derived display Dataset');endif
      endif
      gxtxt_progress_update(min(ch.bytes_read,total),total,'grid_scan','Scanning XYZ grid axes');
      if(ch.eof),break;endif
    endwhile
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  if(valid<1),error('plot.dataset: no finite XYZ rows remain after validation');endif
  if(isempty(info.family)),family_numeric=false;endif

  keys={};counts=[];xu={};yu={};canonical=containers.Map('KeyType','char','ValueType','int32');
  for r=1:numel(raw_keys)
    [key,~]=pd_family_key(raw_keys{r},family_numeric);
    if(!isKey(canonical,key))
      keys{end+1}=key;counts(end+1)=0;xu{end+1}=[];yu{end+1}=[];
      canonical(key)=int32(numel(keys));
    endif
    gi=double(canonical(key));counts(gi)+=raw_counts(r);
    xu{gi}=unique([xu{gi};raw_x{r}]);yu{gi}=unique([yu{gi};raw_y{r}]);
  endfor
  ng=numel(keys);groups=repmat(struct('key','','x',[],'y',[],'z',[],'c',[]),1,ng);
  seen=cell(1,ng);mapx=cell(1,ng);mapy=cell(1,ng);peak_bucket=false(1,ng);peak_absolute=false(1,ng);
  display_rows=0;total_cells=0;effective='none';
  for g=1:ng
    nx=numel(xu{g});ny=numel(yu{g});n=counts(g);total_cells+=nx*ny;
    if(n!=nx*ny)
      error('plot.dataset: %s family %s is not a complete rectangular grid (%d rows, %d x %d expected)',plot_type,keys{g},n,nx,ny);
    endif
    if(total_cells>100000000),error('plot.dataset: grid exceeds 100 million cells; publish a bounded derived display Dataset');endif
    stride=grid_display_stride(opts,n,ng);
    peak_bucket(g)=stride>1 && any(strcmpi(opts.reduction_mode,{'auto','minmax'}));
    peak_absolute(g)=strcmpi(opts.reduction_mode,'minmax');
    if(peak_bucket(g))
      if(peak_absolute(g)),effective='grid_peak_magnitude';else effective='grid_peak_max';endif
    elseif(stride>1&&strcmp(effective,'none')),effective='grid_stride';endif
    xi=grid_display_indices(nx,stride);yi=grid_display_indices(ny,stride);
    display_rows+=numel(xi)*numel(yi);
    if(display_rows>8000000),error('plot.dataset: displayed grid exceeds 8 million cells; enable automatic grid reduction');endif
    mapx{g}=zeros(nx,1,'int32');mapy{g}=zeros(ny,1,'int32');
    if(peak_bucket(g))
      mapx{g}(:)=int32(min(ceil((1:nx)'/stride),numel(xi)));
      mapy{g}(:)=int32(min(ceil((1:ny)'/stride),numel(yi)));
      mapx{g}(end)=int32(numel(xi));mapy{g}(end)=int32(numel(yi));
    else
      mapx{g}(xi)=int32((1:numel(xi))(:));mapy{g}(yi)=int32((1:numel(yi))(:));
    endif
    seen{g}=false(ny,nx);Z=nan(numel(yi),numel(xi));C=[];
    if(!isempty(info.color)),C=nan(numel(yi),numel(xi));endif
    xgrid=xu{g}(xi);ygrid=yu{g}(yi);
    groups(g)=struct('key',keys{g},'x',xgrid(:)','y',ygrid(:)','z',Z,'c',C);
  endfor

  if(isempty(info.family)&&isempty(info.color))
    st=gxtxt_table_stream_open_numeric_fast(info.source_path,cols,opts.chunk_rows);
  else
    st=gxtxt_table_stream_open(info.source_path,cols,opts.chunk_rows);
  endif
  total=max(1,st.total_bytes);
  gxtxt_progress_stage('grid_load',sprintf('Loading bounded %s display grid',plot_type),'determinate',total);
  unwind_protect
    while(true)
      [st,ch]=gxtxt_table_stream_next(st);
      if(ch.nrows>0)
        x=gxtxt_table_chunk_numeric(ch,info.x);y=gxtxt_table_chunk_numeric(ch,info.y);z=gxtxt_table_chunk_numeric(ch,info.z);
        if(!isempty(info.color)),c=gxtxt_table_chunk_numeric(ch,info.color);else c=[];endif
        good=isfinite(x)&isfinite(y)&isfinite(z);if(!isempty(c)),good=good&isfinite(c);endif
        if(isempty(info.family))
          gids=double(good);
        else
          fam=grid_family_values(ch,info.family);gids=zeros(ch.nrows,1);
          for i=1:ch.nrows
            if(!good(i)||isempty(strtrim(fam{i}))),continue;endif
            [key,~]=pd_family_key(strtrim(fam{i}),family_numeric);
            gids(i)=double(canonical(key));
          endfor
        endif
        for gi=reshape(unique(gids(gids>0)),1,[])
          idx=find(gids==gi);
          [okx,ix]=ismember(x(idx),xu{gi});[oky,iy]=ismember(y(idx),yu{gi});
          if(!all(okx)||!all(oky)),error('plot.dataset: failed to map XYZ grid coordinates');endif
          linear=sub2ind(size(seen{gi}),iy,ix);
          if(numel(unique(linear))!=numel(linear)||any(seen{gi}(linear)))
            error('plot.dataset: %s family %s contains duplicate X/Y grid coordinates',plot_type,keys{gi});
          endif
          seen{gi}(linear)=true;
          dx=double(mapx{gi}(ix));dy=double(mapy{gi}(iy));keep=dx>0&dy>0;
          if(any(keep))
            display_index=sub2ind(size(groups(gi).z),dy(keep),dx(keep));
            zz=z(idx(keep));cc=[];if(!isempty(c)),cc=c(idx(keep));endif
            if(peak_bucket(gi))
              if(peak_absolute(gi)),score=abs(zz);else score=zz;endif
              best=accumarray(display_index,score,[numel(groups(gi).z),1],@max,-Inf);
              old=groups(gi).z(display_index);
              if(peak_absolute(gi)),old_score=abs(old);else old_score=old;endif
              choose=(score==best(display_index))&(isnan(old)|score>=old_score);
              display_index=display_index(choose);zz=zz(choose);
              if(!isempty(cc)),cc=cc(choose);endif
            endif
            groups(gi).z(display_index)=zz;
            if(!isempty(cc)),groups(gi).c(display_index)=cc;endif
          endif
        endfor
      endif
      gxtxt_progress_update(min(ch.bytes_read,total),total,'grid_load','Loading bounded XYZ display grid');
      if(ch.eof),break;endif
    endwhile
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  for g=1:ng
    if(!all(seen{g}(:))),error('plot.dataset: %s family %s has missing X/Y grid coordinates',plot_type,keys{g});endif
  endfor
  stats=struct('valid_rows',valid,'dropped_rows',dropped,'display_rows',display_rows,'group_count',ng, ...
    'requested_reduction',opts.reduction_mode,'effective_reduction',effective);
endfunction

function fam=grid_family_values(ch,name)
  if(isempty(name)),fam=cell(ch.nrows,1);fam(:)={'__single__'};else fam=gxtxt_table_chunk_column(ch,name);endif
endfunction
function ok=grid_valid_row(x,y,z,c,i)
  ok=isfinite(x(i))&&isfinite(y(i))&&isfinite(z(i));
  if(ok&&!isempty(c)),ok=isfinite(c(i));endif
endfunction
function stride=grid_display_stride(opts,n,ng)
  mode=lower(strtrim(opts.reduction_mode));if(strcmp(mode,'none')),stride=1;return;endif
  if(strcmp(mode,'auto')&&n<=opts.auto_reduce_threshold/max(1,ng)),stride=1;return;endif
  target=max(4,round(opts.target_points/max(1,ng)));
  stride=max(1,ceil(sqrt(n/target)));
endfunction
function idx=grid_display_indices(n,stride)
  idx=1:stride:n;if(idx(end)!=n),idx(end+1)=n;endif
endfunction
