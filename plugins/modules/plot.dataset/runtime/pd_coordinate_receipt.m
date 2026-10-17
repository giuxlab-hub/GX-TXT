function pd_coordinate_receipt(outdir,M,enabled)
% Derived successful-render identity for stale-preview checks (not settings storage).
% SPDX-License-Identifier: GPL-3.0-or-later
  contexts=containers.Map();
  for graph=enabled
    switch graph{1}
      case 'plot.dataset.xy',field='plot2d_xy';
      case 'plot.dataset.xy_region',field='plot2d_xy_region';
      case 'plot.dataset.xyz',field='plot3d';
      otherwise,continue;
    endswitch
    if(!isfield(M,field)),continue;endif
    P=M.(field);metas={};
    if(strcmp(field,'plot3d'))
      for key={'x_meta','y_meta','z_meta','color_meta','family_meta'},metas{end+1}=P.(key{1});endfor
    else
      for k=1:numel(P.series),metas=[metas {P.series(k).x_meta,P.series(k).meta}];endfor
    endif
    for k=1:numel(metas)
      if(isfield(metas{k},'coordinate_context'))
        c=metas{k}.coordinate_context;contexts(c.dataset_id)=c;
      endif
    endfor
  endfor
  path=fullfile(outdir,'coordinate_presentation.ini');tmp=tempname(outdir);fid=fopen(tmp,'w');
  if(fid<0),error('plot.dataset: cannot write coordinate render receipt');endif
  unwind_protect
    ids=sort(keys(contexts));fprintf(fid,'[coordinate_presentation]\napi_version=1\ncount=%d\n',numel(ids));
    for k=1:numel(ids)
      c=contexts(ids{k});fprintf(fid,'\n[dataset.%d]\nid=%s\nrevision=%.0f\nsource_sha256=%s\n',k,c.dataset_id,c.revision,c.source_sha256);
    endfor
    fclose(fid);fid=-1;[ok,message]=movefile(tmp,path,'f');if(!ok),error('plot.dataset: %s',message);endif
  unwind_protect_cleanup
    if(fid>=0),fclose(fid);endif
    if(exist(tmp,'file')==2),unlink(tmp);endif
  end_unwind_protect
endfunction
