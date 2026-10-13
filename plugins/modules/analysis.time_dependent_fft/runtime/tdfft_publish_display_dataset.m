function dataset_id=tdfft_publish_display_dataset(session,D,suffix,G,kind,window_indices)
% Publish an explicitly derived bounded display Dataset from the FFT cache.
% The full-resolution scientific Dataset remains unchanged.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<6),window_indices=[];endif
  if(!any(strcmp(kind,{'grid','curve'}))),error('TDFFT display: invalid kind');endif
  dataset_id=[D.dataset_id '.display.' suffix];owner='analysis.time_dependent_fft';
  source=D.dataset_id;P=struct();opened=false;
  provenance=sprintf('source_dataset=%s;representation=display_only;cache_policy=%s;module=%s', ...
    source,G.reduction,owner);
  options=struct('storage','auto','replace_owned',true,'producer_version','1.3.3', ...
    'source_dataset_ids',{{source}},'source',source,'provenance',provenance, ...
    'notes','Bounded presentation Dataset derived from the compact time-dependent FFT render cache; full-resolution scientific values remain in the source Dataset.');
  try
    P=gxtxt_publication_v2_open(session,owner,dataset_id,'table.generic',options);opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,'display_point',0,true);
    if(strcmp(kind,'grid'))
      if(rows(G.Z)!=numel(G.time)||columns(G.Z)!=numel(G.frequency)),error('TDFFT display: inconsistent grid');endif
      P=declare(P,'time',D.time_unit,'independent');
      P=declare(P,'frequency','Hz','independent');
      P=declare(P,'spectral_value',D.value_unit,'measured');
      f=G.frequency(:);nf=numel(f);
      for j=1:numel(G.time)
        values={'time',repmat(G.time(j),nf,1);'frequency',f;'spectral_value',G.Z(j,:)'};
        P=gxtxt_publication_v2_append(P,'display_point',values);
      endfor
    else
      if(rows(G.Z)!=numel(window_indices)||columns(G.Z)!=numel(G.frequency)),error('TDFFT display: inconsistent curves');endif
      P=declare(P,'frequency','Hz','independent');
      P=declare(P,'spectral_value',D.value_unit,'measured');
      P=declare(P,'window_index','1','parameter');
      f=G.frequency(:);nf=numel(f);
      for j=1:numel(window_indices)
        values={'frequency',f;'spectral_value',G.Z(j,:)';'window_index',repmat(window_indices(j),nf,1)};
        P=gxtxt_publication_v2_append(P,'display_point',values);
      endfor
    endif
    [P,result]=gxtxt_publication_v2_finalize(P);opened=false;
  catch err
    if(opened),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif
    rethrow(err);
  end_try_catch
endfunction

function P=declare(P,id,unit,role)
  spec=struct('dtype','float64','dimension_ids','display_point','name',id, ...
    'unit',unit,'semantic_role',role,'coordinate_role','data','axis_kind','none');
  P=gxtxt_publication_v2_declare_variable(P,id,spec);
endfunction
