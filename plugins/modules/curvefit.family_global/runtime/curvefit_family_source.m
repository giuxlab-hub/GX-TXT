function [x,family,y,audit]=curvefit_family_source(cfg,xname,fname,yname)
% Canonical source ingestion; CORE owns all Dataset access and CSV decoding.
% SPDX-License-Identifier: GPL-3.0-or-later
  names={xname,fname,yname};ids=names;session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  dataset=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',gxtxt_ini_get(cfg,'dataset.id','')));
  if(!isempty(session))
    if(isempty(dataset)),error('curvefit.family_global: canonical Dataset ID is required');endif
    for i=1:3
      [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',names{i});
      if(meta.found&&!isempty(meta.variable_id)),ids{i}=meta.variable_id;endif
    endfor
    identity=gxtxt_curve_source_dataset_identity_v1(session,dataset);
    stream=gxtxt_table_stream_open_dataset(session,dataset,ids,16384,struct('numeric_transport','resource'));
    provider=stream.storage_provider;
  else
    % Historical standalone callers still use the public CORE CSV facade.
    path=gxtxt_ini_get(cfg,'dataset.path','');
    stream=gxtxt_table_stream_open(path,names,16384);provider='csv';identity='';
  endif
  blocks={};rowblocks={};total=0;kept=0;missing=0;
  unwind_protect
    if(!isempty(session))
      real_types={'bool','int8','uint8','int16','uint16','int32','uint32','int64','uint64','float32','float64'};
      for spec=stream.schema
        if(!any(strcmp(spec.dtype,real_types)))
          error('curvefit.family_global: canonical model inputs require a real numeric dtype; Variable %s has dtype %s',spec.variable_id,spec.dtype);
        endif
      endfor
    endif
    while(true)
      [stream,chunk]=gxtxt_table_stream_next(stream);
      if(total+chunk.nrows>1000000),error('curvefit.family_global: source exceeds the explicit one-million-row fitting bound');endif
      values=zeros(chunk.nrows,3);missing_row=false(chunk.nrows,1);
      for i=1:3
        raw=gxtxt_table_chunk_column(chunk,ids{i});
        if(isa(raw,'int64')||isa(raw,'uint64'))
          limit=cast(flintmax,class(raw));
          if(any(raw(:)>limit)||(!strncmp(class(raw),'uint',4)&&any(raw(:)<-limit)))
            error('curvefit.family_global: integer model coordinates exceed exact binary64 range; publish an explicitly scaled physical Dataset');
          endif
        endif
        if((isnumeric(raw)||islogical(raw))&&!isreal(raw)),error('curvefit.family_global: real mathematical model inputs cannot silently discard imaginary values');endif
        if(isnumeric(raw)||islogical(raw)),column=double(raw(:));
        else column=gxtxt_table_chunk_numeric(chunk,ids{i});endif
        if(!isreal(column)||numel(column)!=chunk.nrows),error('curvefit.family_global: model input column is not a real row-aligned vector');endif
        values(:,i)=column(:);
        if(isfield(chunk,'missing_masks')&&numel(chunk.missing_masks)>=i&&!isempty(chunk.missing_masks{i})),missing_row|=chunk.missing_masks{i}(:);endif
        if(iscell(raw)),missing_row|=cellfun(@(v)ischar(v)&&isempty(strtrim(v)),raw(:));endif
      endfor
      valid=all(isfinite(values),2)&!missing_row;
      ordinals=uint64(total)+uint64((0:chunk.nrows-1)');
      if(any(valid)),blocks{end+1}=values(valid,:);rowblocks{end+1}=ordinals(valid);endif
      total+=chunk.nrows;kept+=sum(valid);missing+=sum(missing_row);
      if(chunk.eof),break;endif
    endwhile
  unwind_protect_cleanup
    stream=gxtxt_table_stream_close(stream);
  end_unwind_protect
  if(!isempty(session)&&!isequal(identity,gxtxt_curve_source_dataset_identity_v1(session,dataset)))
    error('curvefit.family_global: source content or scientific schema changed while reading');
  endif
  if(isempty(blocks)),data=zeros(0,3);ordinals=zeros(0,1,'uint64');else data=vertcat(blocks{:});ordinals=vertcat(rowblocks{:});endif
  x=data(:,1);family=data(:,2);y=data(:,3);
  audit=struct('schema','gxtxt.family_source_rows.v1','version',1,'dataset_id',dataset, ...
    'variable_ids',{ids},'storage_provider',provider,'source_identity',identity, ...
    'row_count',total,'used_row_count',kept,'omitted_row_count',total-kept,'missing_row_count',missing, ...
    'row_policy','joint_finite_real_model_inputs_in_source_order','source_row_ordinals',ordinals, ...
    'row_ordinal_base',0,'row_limit',1000000,'model_coordinate_dtype','float64');
endfunction
