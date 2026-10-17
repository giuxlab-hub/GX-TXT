function curvefit_family_metric_csv(path,metrics,identity_columns,value_columns)
% Export legacy scalar columns from CORE-validated row cells.
% SPDX-License-Identifier: GPL-3.0-or-later
  f=fopen(path,'w');if(f<0),error('Cannot write %s',path);endif
  unwind_protect
    fprintf(f,'%s\n',strjoin([identity_columns,value_columns],','));
    for k=1:numel(metrics.export_rows)
      fields={};
      for name=identity_columns
        v=metrics.(name{1});if(iscell(v)),fields{end+1}=v{k};else fields{end+1}=sprintf('%.17g',v(k));endif
      endfor
      cells=metrics.export_rows{k}.cells;
      for name=value_columns
        item=cells.(name{1});v='';if(strcmp(item.status,'value')),v=sprintf('%.17g',item.value);endif
        fields{end+1}=v;
      endfor
      fprintf(f,'%s\n',strjoin(fields,','));
    endfor
  unwind_protect_cleanup
    fclose(f);
  end_unwind_protect
endfunction
