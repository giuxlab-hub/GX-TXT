function gxtxt_ir_render_public(outdir,cfg,S,D)
% Persistent Graph Provider / Plot.dataset presentation of IR diagnostics.
% SPDX-License-Identifier: GPL-3.0-or-later
  session=strtrim(ir_get(cfg,'runtime.session',''));
  if(isempty(session)),error('gxtxt.ir_waveform: Session required for public plots');endif
  defaults='ir.full;ir.carrier;ir.markspace;ir.durations;ir.compare;ir.compare_baseline;ir.compare_envelope;ir.compare_gain;ir.compare_margin';
  enabled=ir_list(ir_get(cfg,'graph_provider.enabled',defaults));items={};
  if(ir_enabled(enabled,'ir.full'))
    graph='ir.full';axes=ir_axes(cfg,graph,'Time [ms]',ir_signal_label(cfg,S.signal_name));
    series={ir_series('maximum',D.full,'time_ms','maximum','Local maximum','line',struct('color',ir_color(1))), ...
            ir_series('minimum',D.full,'time_ms','minimum','Local minimum','line',struct('line_style','dashed','color',ir_color(1)))};
    items{end+1}=ir_item('full',graph,cfg,axes,series,{},'01_vir_comando_completo.png');
  endif
  if(ir_enabled(enabled,'ir.carrier'))
    graph='ir.carrier';axes=ir_axes(cfg,graph,'Time from first cycle [us]',ir_signal_label(cfg,S.signal_name));
    series={ir_series('carrier',D.carrier,'time_us','signal',S.signal_name,'line',struct())};
    item=ir_item('carrier',graph,cfg,axes,series,{},'02_vir_portante_zoom.png');
    title_text=ir_get(cfg,['plot.' graph '.title'],'IR waveform - carrier detail');
    item.spec.title=sprintf('%s - %.3f kHz',title_text,S.Fcarrier/1e3);
    item.spec.panels{1}.title=item.spec.title;items{end+1}=item;
  endif
  if(ir_enabled(enabled,'ir.markspace'))
    graph='ir.markspace';axes=ir_axes(cfg,graph,'Time [ms]','MARK / SPACE');
    if(!isfield(axes.y_left,'min')),axes.y_left.min=-0.15;axes.y_left.max=1.15;endif
    series={ir_series('state',D.markspace,'time_ms','state','MARK state','step',struct())};
    items{end+1}=ir_item('markspace',graph,cfg,axes,series,{},'03_mark_space_ricostruito.png');
  endif
  if(ir_enabled(enabled,'ir.durations'))
    graph='ir.durations';axes=ir_axes(cfg,graph,'Burst number','Duration [us]');
    series={ir_series('mark',D.durations,'burst','mark_us','MARK','line_marker',struct('marker','circle'))};
    if(!isempty(S.spaceDuration)),series{end+1}=ir_series('space',D.durations,'burst','space_us','Following SPACE','line_marker',struct('marker','square'));endif
    items{end+1}=ir_item('durations',graph,cfg,axes,series,{},'04_durate_mark_space.png');
  endif
  if(D.count>=2)
    defs={'ir.compare','absolute','Absolute voltage [V]','05_ir_comparison.png'; ...
      'ir.compare_baseline','baseline','V - baseline [V]','06_ir_comparison_baseline_removed.png'; ...
      'ir.compare_envelope','envelope','Carrier amplitude [V]','07_ir_carrier_envelopes.png'; ...
      'ir.compare_gain','gain','Relative carrier amplitude','08_ir_relative_gain.png'; ...
      'ir.compare_margin','margin','Envelope - threshold [V]','09_ir_threshold_margin.png'; ...
      'ir.compare_normalized','normalized','Normalized amplitude','10_ir_comparison_normalized.png'};
    for j=1:rows(defs)
      graph=defs{j,1};if(!ir_enabled(enabled,graph)),continue;endif
      key=defs{j,2};axes=ir_axes(cfg,graph,'Time [ms]',defs{j,3});series={};panels={};
      mode=lower(strtrim(ir_get(cfg,'config.comparison_plot_mode','stacked')));
      stacked=strcmp(mode,'stacked')&&any(strcmp(key,{'absolute','baseline','normalized'}));
      ids=D.compare.(key);start=1;if(strcmp(key,'gain')),start=2;endif
      if(stacked),axes=ir_common_y(axes,S.analog_chain,key);endif
      for k=start:D.count
        if(k>numel(ids)||isempty(ids{k})),continue;endif
        name=D.names{k};id=ids{k};col=ir_color(k);
        local={ir_series(sprintf('trace_%d',k),id,'time_ms','value',name,'line',struct('color',col))};
        if(any(strcmp(key,{'absolute','baseline','normalized'})))
          local{end+1}=ir_series(sprintf('low_%d',k),id,'time_ms','minimum',[name ' minimum'],'line',struct('line_style','dashed','color',col));
        endif
        if(stacked)
          pane=struct('id',sprintf('trace_%d',k),'title',name,'axes',axes, ...
            'series',{local},'annotations',{{}});panels{end+1}=pane;
        else series=[series,local];endif
      endfor
      if(isempty(panels)&&isempty(series)),continue;endif
      if(strcmp(key,'margin')),ann={struct('type','reference_line','axis','left','value',0,'line_style','dashed')};else ann={};endif
      if(stacked)
        title_text=ir_get(cfg,['plot.' graph '.title'],ir_title(graph));
        spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d', ...
          'graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()), ...
          'panels',{panels},'output',struct('extra_format','none'));
        items{end+1}=struct('key',strrep(graph,'ir.',''),'spec',spec,'png',defs{j,4});
      else
        items{end+1}=ir_item(strrep(graph,'ir.',''),graph,cfg,axes,series,ann,defs{j,4});
      endif
    endfor
  endif
  gxtxt_plot_provider_render_v1(session,outdir,'gxtxt.ir_waveform',items,'base');
endfunction

function axes=ir_common_y(axes,A,key)
  lo=Inf;hi=-Inf;
  fields=struct('absolute',{{'abs_vMin','abs_vMax'}}, ...
    'baseline',{{'zero_vMin','zero_vMax'}},'normalized',{{'norm_vMin','norm_vMax'}});
  pair=fields.(key);
  for k=1:numel(A)
    for j=1:2
      v=A(k).(pair{j});v=v(isfinite(v));
      if(!isempty(v)),lo=min(lo,min(v));hi=max(hi,max(v));endif
    endfor
  endfor
  if(isfinite(lo)&&isfinite(hi)&&!isfield(axes.y_left,'min'))
    pad=max(1e-12,0.05*max(hi-lo,abs(lo)*1e-10));axes.y_left.min=lo-pad;axes.y_left.max=hi+pad;
  endif
endfunction
function s=ir_series(id,dataset,x,y,label,kind,style)
  s=struct('id',id,'dataset_id',dataset,'x_variable_id',x,'y_variable_id',y, ...
    'axis','left','kind',kind,'label',label,'style',style);
endfunction
function out=ir_item(key,graph,cfg,axes,series,annotations,png)
  title_text=ir_get(cfg,['plot.' graph '.title'],ir_title(graph));
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{annotations});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d', ...
    'graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()), ...
    'panels',{{panel}},'output',struct('extra_format','none'));
  out=struct('key',key,'spec',spec,'png',png);
endfunction
function axes=ir_axes(cfg,graph,xdefault,ydefault)
  xl=ir_get(cfg,['plot.' graph '.x_label'],xdefault);
  yl=ir_get(cfg,['plot.' graph '.y_label'],ydefault);
  if(strcmpi(strtrim(xl),'auto')),xl=xdefault;endif
  if(strcmpi(strtrim(yl),'auto')),yl=ydefault;endif
  axes=struct('x',struct('label',xl),'y_left',struct('label',yl));
  for pair={'x','x_min','x_max';'y_left','y_min','y_max'}'
    a=pair{1};lo=str2double(ir_get(cfg,['plot.' graph '.' pair{2}],''));
    hi=str2double(ir_get(cfg,['plot.' graph '.' pair{3}],''));
    if(isfinite(lo)&&isfinite(hi)&&hi>lo),axes.(a).min=lo;axes.(a).max=hi;endif
  endfor
endfunction
function s=ir_signal_label(cfg,name)
  s=strrep(name,'_',' ');if(isempty(s)),s='Signal';endif
endfunction
function s=ir_title(graph)
  names=struct('full','IR waveform - full command','carrier','IR waveform - carrier detail', ...
    'markspace','IR waveform - MARK / SPACE reconstruction','durations','IR MARK / SPACE durations', ...
    'compare','IR analog-chain comparison','compare_baseline','IR comparison - baseline removed', ...
    'compare_envelope','IR carrier envelopes','compare_gain','IR relative carrier gain', ...
    'compare_margin','IR threshold margin','compare_normalized','IR normalized comparison');
  key=strrep(graph,'ir.','');if(isfield(names,key)),s=names.(key);else s=graph;endif
endfunction
function c=ir_color(k)
  palette={'#1f77b4','#d95f02','#2ca02c','#9467bd','#8c564b','#17becf','#bcbd22','#e377c2'};
  c=palette{mod(k-1,numel(palette))+1};
endfunction
function tf=ir_enabled(enabled,id),tf=any(strcmp(enabled,id));endfunction
function a=ir_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),a={};else a=strsplit(s,';');a=cellfun(@strtrim,a,'UniformOutput',false);endif,endfunction
function v=ir_get(d,key,def),k=regexprep(key,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif;if(isfield(d,k)),v=d.(k);else v=def;endif,endfunction
