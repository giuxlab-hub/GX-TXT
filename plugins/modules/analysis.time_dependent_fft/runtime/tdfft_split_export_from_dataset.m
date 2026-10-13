function tdfft_split_export_from_dataset(outdir,cfg,D)
% One-pass full-resolution split export from the canonical Dataset.
% Used only for render-only/reuse runs when the user explicitly asks for split CSV files.
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
  wanted=false(D.window_count,1);wanted(idx)=true;mkdir(dirp);
  fi=fopen(index_path,'w');if(fi<0),error('analysis.time_dependent_fft: cannot write split export index');endif
  current=0;fo=-1;
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  S=gxtxt_table_stream_open_dataset(session,D.dataset_id,{'frequency','spectral_value','window_index'},65536,struct('start',0,'count',-1,'require_direct',false,'numeric_transport','auto'));
  unwind_protect
    fprintf(fi,'window_index\tmember_id\ttime\tfile\n');
    while(!S.eof)
      [S,ch]=gxtxt_table_stream_next(S);
      if(ch.nrows>0)
        freq=double(gxtxt_table_chunk_numeric(ch,'frequency'));vals=double(gxtxt_table_chunk_numeric(ch,'spectral_value'));wins=double(gxtxt_table_chunk_numeric(ch,'window_index'))+1;
        for k=1:numel(vals)
          wi=wins(k);if(wi<1||wi>D.window_count||!wanted(wi)),continue;endif
          if(wi!=current)
            if(fo>=0),fclose(fo);fo=-1;endif
            current=wi;name=sprintf('fft_window_data_%04d.csv',wi);path=fullfile(dirp,name);fo=fopen(path,'w');if(fo<0),error('analysis.time_dependent_fft: cannot write split export %s',path);endif
            fprintf(fo,'time,frequency,spectral_value,window_index\n');
            fprintf(fi,'%d\t%s\t%.17g\t%s\n',wi,D.member_ids{wi},D.time_centers(wi),fullfile('window_exports',name));
          endif
          fprintf(fo,'%.17g,%.17g,%.17g,%d\n',D.time_centers(wi),freq(k),vals(k),wi-1);
        endfor
      endif
    endwhile
  unwind_protect_cleanup
    if(fo>=0),fclose(fo);endif
    fclose(fi);S=gxtxt_table_stream_close(S);
  end_unwind_protect
endfunction
function write_text(path,text),fid=fopen(path,'w');if(fid<0),error('analysis.time_dependent_fft: cannot write %s',path);endif;unwind_protect fputs(fid,text);unwind_protect_cleanup fclose(fid);end_unwind_protect;endfunction
