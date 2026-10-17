function P=pd_prepare_3d(info,cfg,opts,plot_type,runtime_config)
% Prepare one generic XYZ/C dataset. No scientific interpolation is performed.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(isempty(info.z)),error('plot.dataset: the enabled 3D graph requires a Z binding');endif
  if(isempty(info.session)||isempty(info.dataset_id)),error('plot.dataset: 3D requires the canonical Session and Dataset ID');endif
  for role={'x','y','z','family','color'}
    name=role{1};if(!isempty(info.(name))&&isempty(info.([name '_variable_id'])))
      error('plot.dataset: 3D %s binding has no canonical Variable ID; resolve the Dataset schema',name);
    endif
  endfor
  plot_type=lower(strtrim(plot_type));
  allowed={'line3','scatter3','surface','mesh','contour3','trisurf','heatmap'};
  if(!any(strcmp(plot_type,allowed))),error('plot.dataset: unsupported 3D plot type %s',plot_type);endif
  if(!isempty(info.color)&&any(strcmp(plot_type,{'line3','contour3'})))
    error('plot.dataset: Color C is not supported by %s; clear Color or choose scatter3/surface/mesh/trisurf',plot_type);
  endif
  if(any(strcmp(plot_type,{'surface','mesh','contour3','heatmap'})))
    if(isfield(info.z_meta,'rank')&&info.z_meta.rank==2)
      [groups,stats]=pd_prepare_3d_canonical_grid(info,opts,runtime_config);
    else
      [groups,stats]=pd_prepare_3d_gridded_stream(info,opts,plot_type);
    endif
    mode='gridded';
  else
    [groups,stats]=prepare_scattered(info,opts,plot_type);
    mode='scattered';
  endif
  P=struct('plot_type',plot_type,'mode',mode,'x_name',info.x,'y_name',info.y,'z_name',info.z,'color_name',info.color, ...
    'family_name',info.family,'x_meta',info.x_meta,'y_meta',info.y_meta,'z_meta',info.z_meta,'color_meta',info.color_meta, ...
    'family_meta',info.family_meta,'groups',groups,'stats',stats);
endfunction

function [groups,stats]=prepare_scattered(info,opts,plot_type)
  cols={info.x_variable_id,info.y_variable_id,info.z_variable_id};if(!isempty(info.color)),cols{end+1}=info.color_variable_id;endif;if(!isempty(info.family)),cols{end+1}=info.family_variable_id;endif
  [keys,counts,valid,dropped,family_numeric]=scan_xyz(cols,info,opts.chunk_rows,'xyz_scan');
  if(valid<1),error('plot.dataset: no finite XYZ rows remain after validation');endif
  effective=lower(strtrim(opts.reduction_mode));if(!any(strcmp(effective,{'auto','none','stride','minmax'}))),effective='auto';endif
  if(strcmp(effective,'auto')),if(valid>opts.auto_reduce_threshold),effective='stride';else effective='none';endif;endif
  if(strcmp(effective,'minmax')),effective='stride_3d';endif
  ng=numel(keys);strides=ones(1,ng);
  if(!strcmp(effective,'none'))
    for g=1:ng
      gt=max(3,round(opts.target_points*counts(g)/max(1,valid)));strides(g)=max(1,ceil(counts(g)/gt));
    endfor
  endif
  groups=repmat(struct('key','','x',[],'y',[],'z',[],'c',[],'source_row_indices',[]),1,ng);for g=1:ng,groups(g).key=keys{g};endfor
  seen=zeros(1,ng);st=gxtxt_table_stream_open_dataset(info.session,info.dataset_id,cols,opts.chunk_rows);total=st.range_count;
  unwind_protect
    gxtxt_progress_stage('xyz_load',sprintf('Loading XYZ data (%s reduction)',effective),'determinate',total);
    while(true)
      [st,ch]=gxtxt_table_stream_next(st);if(ch.nrows>0)
        xv=gxtxt_table_chunk_numeric(ch,info.x_variable_id);yv=gxtxt_table_chunk_numeric(ch,info.y_variable_id);zv=gxtxt_table_chunk_numeric(ch,info.z_variable_id);
        if(!isempty(info.color)),cv=gxtxt_table_chunk_numeric(ch,info.color_variable_id);else cv=[];endif
        fv=pd_3d_family_values(ch,info.family_variable_id);
        for i=1:ch.nrows
          if(!valid_xyz_row(xv(i),yv(i),zv(i),cv,i)),continue;endif
          key=strtrim(fv{i});if(isempty(key)),continue;endif;[key,~]=pd_family_key(key,family_numeric);gi=find(strcmp(keys,key),1);if(isempty(gi)),continue;endif
          seen(gi)+=1;seq=seen(gi);keep=strcmp(effective,'none')||mod(seq-1,strides(gi))==0||seq==counts(gi);
          if(!keep),continue;endif
          groups(gi).x(end+1,1)=xv(i);groups(gi).y(end+1,1)=yv(i);groups(gi).z(end+1,1)=zv(i);
          groups(gi).source_row_indices(end+1,1)=ch.offset+i-1;
          if(!isempty(cv)),groups(gi).c(end+1,1)=cv(i);endif
        endfor
      endif
      gxtxt_progress_update(ch.offset-st.range_start+ch.nrows,total,'xyz_load','Loading XYZ data');if(ch.eof),break;endif
    endwhile
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  if(strcmp(plot_type,'trisurf'))
    for g=1:ng,if(numel(groups(g).x)<3),error('plot.dataset: trisurf family %s has fewer than 3 retained points',keys{g});endif;endfor
  endif
  display_rows=0;for g=1:ng,display_rows+=numel(groups(g).x);endfor
  stats=struct('valid_rows',valid,'dropped_rows',dropped,'display_rows',display_rows,'group_count',ng,'requested_reduction',opts.reduction_mode,'effective_reduction',effective);
endfunction

function [keys,counts,valid,dropped,family_numeric]=scan_xyz(cols,info,chunk_rows,stage)
  st=gxtxt_table_stream_open_dataset(info.session,info.dataset_id,cols,chunk_rows);total=st.range_count;raw_keys={};raw_counts=[];valid=0;dropped=0;family_numeric=!isempty(info.family);
  unwind_protect
    gxtxt_progress_stage(stage,'Scanning XYZ data','determinate',total);
    while(true)
      [st,ch]=gxtxt_table_stream_next(st);if(ch.nrows>0)
        x=gxtxt_table_chunk_numeric(ch,info.x_variable_id);y=gxtxt_table_chunk_numeric(ch,info.y_variable_id);z=gxtxt_table_chunk_numeric(ch,info.z_variable_id);
        if(!isempty(info.color)),c=gxtxt_table_chunk_numeric(ch,info.color_variable_id);else c=[];endif
        [fam,numeric_ok]=pd_3d_family_values(ch,info.family_variable_id);family_numeric=family_numeric&&numeric_ok;
        for i=1:ch.nrows
          if(!valid_xyz_row(x(i),y(i),z(i),c,i)||isempty(strtrim(fam{i}))),dropped+=1;continue;endif
          key=strtrim(fam{i});if(!isempty(info.family)&&!isfinite(str2double(key))),family_numeric=false;endif
          gi=find(strcmp(raw_keys,key),1);if(isempty(gi)),raw_keys{end+1}=key;raw_counts(end+1)=0;gi=numel(raw_keys);endif
          raw_counts(gi)+=1;valid+=1;
        endfor
      endif
      gxtxt_progress_update(ch.offset-st.range_start+ch.nrows,total,stage,'Scanning XYZ data');if(ch.eof),break;endif
    endwhile
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  if(isempty(info.family)),family_numeric=false;endif
  [keys,counts]=normalize_group_catalog(raw_keys,raw_counts,family_numeric);
endfunction

function [keys,counts]=normalize_group_catalog(raw_keys,raw_counts,numeric_mode)
  keys={};counts=[];
  for i=1:numel(raw_keys)
    [key,~]=pd_family_key(raw_keys{i},numeric_mode);gi=find(strcmp(keys,key),1);
    if(isempty(gi)),keys{end+1}=key;counts(end+1)=0;gi=numel(keys);endif
    counts(gi)+=raw_counts(i);
  endfor
endfunction

function tf=valid_xyz_row(x,y,z,c,i)
  tf=isfinite(x)&&isfinite(y)&&isfinite(z);if(tf&&!isempty(c)),tf=isfinite(c(i));endif
endfunction
