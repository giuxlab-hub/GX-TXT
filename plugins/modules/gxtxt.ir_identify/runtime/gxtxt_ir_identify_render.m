function gxtxt_ir_identify_render(outdir,cfg,ids,rank_labels,rank_scores,expected_values,frame_annotations,best_name,status)
% Render all IR diagnostics through persistent public Plot.dataset variants.
% SPDX-License-Identifier: GPL-3.0-or-later
  enabled=parse_list(gxtxt_ini_get(cfg,'graph_provider.enabled','irid.ranking;irid.timing;irid.clusters;irid.frame'));
  items={};
  if(any(strcmp(enabled,'irid.ranking')))
    title_text=gxtxt_ini_get(cfg,'plot.irid.ranking.title','IR protocol candidate ranking');
    positions=arrayfun(@num2str,1:numel(rank_labels),'UniformOutput',false);
    axes=struct('x',struct('label','Candidate rank','tick_positions',strjoin(positions,';'), ...
      'tick_labels',strjoin(rank_labels,';')),'y_left',struct('label','Score (lower is better)'));
    series={trace('ranking',ids.ranking,'rank','score','Candidate score','bar','solid',1.2)};
    annotations={};
    score_scale=max([rank_scores(:);1]);
    for k=1:numel(rank_scores)
      if(rank_scores(k)==0)
        annotations{end+1}=struct('type','text','axis','left','x',k, ...
          'y',0.025*score_scale,'label','0');
      endif
    endfor
    items{end+1}=item('ranking',title_text,axes,series,annotations,'01_protocol_ranking.png');
  endif
  if(any(strcmp(enabled,'irid.timing'))&&!isempty(ids.timing))
    title_text=[gxtxt_ini_get(cfg,'plot.irid.timing.title','Measured vs expected protocol timing') ' - ' best_name];
    axes=struct('x',struct('label','Timing item'),'y_left',struct('label','Duration [us]','display_unit','us'));
    series={trace('measured',ids.timing,'timing_item','measured_us','Measured','line_marker','solid',1.4), ...
      trace('expected',ids.timing,'timing_item','expected_us','Expected','line_marker','dashed',1.4)};
    items{end+1}=item('timing',title_text,axes,series,{},'02_protocol_timing.png');
  endif
  if(any(strcmp(enabled,'irid.clusters')))
    title_text=[gxtxt_ini_get(cfg,'plot.irid.clusters.title','MARK / SPACE timing fingerprint') ' - ' best_name];
    axes=struct('x',struct('label','Event index'),'y_left',struct('label','Duration [us]','display_unit','us'));
    series={trace('mark',ids.events,'event_index','mark_us','MARK','scatter','none',1.2), ...
      trace('space',ids.events,'event_index','space_us','SPACE','scatter','none',1.2)};
    annotations=cell(1,numel(expected_values));
    for k=1:numel(expected_values)
      annotations{k}=struct('type','reference_line','axis','left','value',expected_values(k),'line_style','dashed');
    endfor
    items{end+1}=item('clusters',title_text,axes,series,annotations,'03_protocol_timing_fingerprint.png');
  endif
  if(any(strcmp(enabled,'irid.frame')))
    title_text=sprintf('%s - %s [%s]',gxtxt_ini_get(cfg,'plot.irid.frame.title','Decoded frame timeline'),best_name,status);
    axes=struct('x',struct('label','Time from frame start [ms]'), ...
      'y_left',struct('label','Carrier present','min',-0.2,'max',1.35));
    series={trace('carrier',ids.frame,'time_ms','carrier_present','Carrier present','line','solid',1.8)};
    items{end+1}=item('frame',title_text,axes,series,frame_annotations,'04_protocol_frame.png');
  endif
  gxtxt_plot_provider_render_v1(gxtxt_ini_get(cfg,'runtime.session',''),outdir,'gxtxt.ir_identify',items,'base');
endfunction
function s=trace(id,dataset,x,y,label,kind,line_style,width)
  style=struct('line_style',line_style,'line_width',width);
  if(any(strcmp(kind,{'scatter','line_marker'}))),style.marker='circle';style.marker_size=5;endif
  s=struct('id',id,'dataset_id',dataset,'x_variable_id',x,'y_variable_id',y, ...
    'axis','left','kind',kind,'label',label,'style',style);
endfunction
function out=item(key,title_text,axes,series,annotations,png)
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{annotations});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d', ...
    'graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()), ...
    'panels',{{panel}},'output',struct('extra_format','none'));
  out=struct('key',key,'spec',spec,'png',png);
endfunction
function a=parse_list(s)
  s=strrep(s,',',';');if(isempty(strtrim(s))),a={};return;endif
  a=strsplit(s,';');a=cellfun(@strtrim,a,'UniformOutput',false);a=a(!cellfun(@isempty,a));
endfunction
