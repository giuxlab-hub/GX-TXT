function tdfft_split_export_from_results(outdir,cfg,D,result_paths)
% Export full-resolution per-window CSV files from already computed worker results.
% This avoids rereading the canonical long-form Dataset during the compute run.
% SPDX-License-Identifier: GPL-3.0-or-later
  index_path=fullfile(outdir,'split_export_index.txt');mode=lower(strtrim(gxtxt_ini_get(cfg,'config.split_export','none')));
  dirp=fullfile(outdir,'window_exports');if(exist(dirp,'dir')==7),rmdir(dirp,'s');endif
  if(strcmp(mode,'none')),write_text(index_path,'Separate per-window data export is disabled.\n');return;endif
  if(strcmp(mode,'all_windows'))
    idx=(1:D.window_count)';
  elseif(strcmp(mode,'selected_windows'))
    idx=tdfft_select_windows(cfg,'analysis.time_dependent_fft.window_spectra',D.time_centers,D.member_ids);
  else
    error('analysis.time_dependent_fft: invalid split export mode: %s',mode);
  endif
  mkdir(dirp);fid=fopen(index_path,'w');if(fid<0),error('analysis.time_dependent_fft: cannot write split export index');endif
  unwind_protect
    fprintf(fid,'window_index\tmember_id\ttime\tfile\n');
    for q=1:numel(idx)
      wi=idx(q);loaded=load(result_paths{wi});if(!isfield(loaded,'R')),error('analysis.time_dependent_fft: worker result %d is unavailable for split export',wi);endif
      R=loaded.R;freq=(0:numel(R.values)-1)'*D.df;name=sprintf('fft_window_data_%04d.csv',wi);path=fullfile(dirp,name);fo=fopen(path,'w');if(fo<0),error('analysis.time_dependent_fft: cannot write split export %s',path);endif
      unwind_protect
        fprintf(fo,'time,frequency,spectral_value,window_index\n');
        for k=1:numel(R.values),fprintf(fo,'%.17g,%.17g,%.17g,%d\n',D.time_centers(wi),freq(k),R.values(k),wi-1);endfor
      unwind_protect_cleanup
        fclose(fo);
      end_unwind_protect
      fprintf(fid,'%d\t%s\t%.17g\t%s\n',wi,D.member_ids{wi},D.time_centers(wi),fullfile('window_exports',name));
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_text(path,text),fid=fopen(path,'w');if(fid<0),error('analysis.time_dependent_fft: cannot write %s',path);endif;unwind_protect fputs(fid,text);unwind_protect_cleanup fclose(fid);end_unwind_protect;endfunction
