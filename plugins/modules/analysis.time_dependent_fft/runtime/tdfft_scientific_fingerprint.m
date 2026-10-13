function fp=tdfft_scientific_fingerprint(source_dataset_id,source_stamp,time_id,signal_id,T,window_name,detrend_mode,nfft_mode,nfft,representation)
% Fingerprint only scientific inputs. Worker count and plotting/export settings are intentionally excluded.
% SPDX-License-Identifier: GPL-3.0-or-later
  parts={'source_dataset',source_dataset_id,'source_stamp',source_stamp,'time_variable',time_id,'signal_variable',signal_id,'temporal_set',T.id,'temporal_type',T.type, ...
    'basis',T.generator_basis,'window_size',T.window_size,'step',T.step,'partial_policy',T.partial_policy,'parent_selection',T.parent_selection_id, ...
    'effective_row_start',T.effective_row_start,'effective_row_count',T.effective_row_count,'resolved_window_rows',T.resolved_window_rows,'resolved_step_rows',T.resolved_step_rows, ...
    'member_count',T.member_count,'fft_window',window_name,'detrend',detrend_mode,'nfft_mode',nfft_mode,'nfft',nfft,'representation',representation};
  for i=1:T.member_count
    Q=gxtxt_temporal_set_member(T,i);parts(end+1:end+4)={'member',Q.member_id,Q.row_start,Q.row_count};
  endfor
  fp=gxtxt_render_cache_fingerprint(parts);
endfunction
