% GX-TXT public standard_octave -> PLOT_DATASET_API_v2 bridge v1.
% SPDX-License-Identifier: GPL-3.0-or-later
function result = gxtxt_plot_dataset_v2(session, plotspec, options)
  if (nargin < 2), plotspec = []; endif
  if (nargin < 3 || isempty(options)), options = struct(); endif
  if (!isstruct(options)), error('GXTXT:PlotDataset','options must be a struct'); endif
  action = opt(options,'action','create');
  kind = opt(options,'kind','base');
  source_variant = opt(options,'source_variant','');
  graph_id = opt(options,'graph_id','');
  variant_id = opt(options,'variant_id','');
  provider_key = opt(options,'provider_key','');
  do_render = logical(opt(options,'render',any(strcmp(action,{'create','ensure'}))));
  if (!any(strcmp(action,{'create','ensure','render','rerender'})))
    error('GXTXT:PlotDataset','action must be create, ensure, render or rerender');
  endif

  request = '';
  if (!isempty(plotspec))
    request = [tempname() '.gxtxt-plotspec'];
    fid = fopen(request,'wt');
    if (fid < 0), error('GXTXT:PlotDataset','cannot create PlotSpec transport'); endif
    try
      write_node(fid,plotspec);
    catch err
      fclose(fid); rethrow(err);
    end_try_catch
    fclose(fid);
  endif
  cleanup = onCleanup(@() cleanup_file(request));

  here = fileparts(mfilename('fullpath'));
  root = fileparts(fileparts(fileparts(here)));
  bridge = fullfile(root,'core','tcl','plot_dataset_v2_bridge.tcl');
  args = {bridge,char(session),action,kind,char(source_variant),char(graph_id),char(variant_id),num2str(do_render),request,char(provider_key)};
  [in_fid,out_fid,pid] = popen2('tclsh',args);
  fclose(in_fid);
  line = gxtxt_persistent_bridge_readline(out_fid,pid);
  fclose(out_fid); waitpid(pid);
  parts = strsplit(strtrim(line),sprintf('\t'),'collapsedelimiters',false);
  if (isempty(parts) || strcmp(parts{1},'ERROR'))
    if (numel(parts) > 1), msg = decode(parts{2}); else msg = 'empty response from plot.dataset bridge'; endif
    error('GXTXT:PlotDataset','%s',msg);
  endif
  if (!strcmp(parts{1},'RESULT') || numel(parts) != 7)
    error('GXTXT:PlotDataset','invalid response from plot.dataset bridge: %s',line);
  endif
  result = struct('graph_id',decode(parts{2}),'variant_id',decode(parts{3}), ...
    'artifact',decode(parts{4}),'output_dir',decode(parts{5}), ...
    'render_cache',decode(parts{6}),'summary',decode(parts{7}));
endfunction

function value = opt(s,name,default)
  if (isfield(s,name)), value=s.(name); else value=default; endif
endfunction
function text = encode(value)
  if (isempty(value)), text=''; return; endif
  text=char(matlab.net.base64encode(uint8(char(value)))); text=text(:)';
endfunction
function text = decode(value)
  if (isempty(value)), text=''; return; endif
  text=char(matlab.net.base64decode(value)); text=text(:)';
endfunction
function write_scalar(fid,value)
  if (islogical(value)), value=num2str(value != 0);
  elseif (isnumeric(value)), value=num2str(value,17);
  elseif (isstring(value)), value=char(value);
  endif
  fprintf(fid,'S\t%s\n',encode(value));
endfunction
function write_node(fid,value)
  if (isstruct(value))
    if (numel(value) != 1)
      fprintf(fid,'L\t%d\n',numel(value));
      for i=1:numel(value), write_node(fid,value(i)); endfor
      return;
    endif
    names=fieldnames(value); fprintf(fid,'D\t%d\n',numel(names));
    for i=1:numel(names), write_scalar(fid,names{i}); write_node(fid,value.(names{i})); endfor
  elseif (iscell(value))
    fprintf(fid,'L\t%d\n',numel(value));
    for i=1:numel(value), write_node(fid,value{i}); endfor
  elseif ((isnumeric(value) || islogical(value)) && numel(value) > 1)
    fprintf(fid,'L\t%d\n',numel(value));
    for i=1:numel(value), write_scalar(fid,value(i)); endfor
  else
    write_scalar(fid,value);
  endif
endfunction
function cleanup_file(path)
  if (!isempty(path) && exist(path,'file')), unlink(path); endif
endfunction
