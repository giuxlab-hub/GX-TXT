% GX-TXT CSV streaming worker for gxtxt_pipeline.tcl
% SPDX-License-Identifier: GPL-3.0-or-later
%
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% Purpose:
%   - stream a multi-channel oscilloscope CSV in blocks;
%   - avoid loading the full acquisition into RAM;
%   - reconstruct/validate time information;
%   - map CSV columns to logical signal names;
%   - write optional per-channel extracts progressively as *.part;
%   - verify per-channel extracts against the streamed RAW first/last samples;
%   - produce summary.tsv and import_result.ini on successful completion.
%
% This worker performs no GX-TXT-specific signal analysis.

args = argv();
opts = struct();
opts.input = '';
opts.out = '';
opts.parser = 'rigol_ds1000z';
opts.delimiter = ',';
opts.header_lines = 2;
opts.sequence_col = 1;
opts.time_col = 1;
opts.tstart = NaN;
opts.dt = NaN;
opts.channels = '';
opts.make_rigol = true;
opts.make_canonical = false;
opts.manifest = '';
opts.workers = 1;
opts.chunk_rows = 250000;
opts.raw_fields = 0;
opts.drop_trailing_fields = 0;
opts.strict_sequence = true;

k = 1;
while k <= numel(args)
  key = args{k};
  if k == numel(args)
    error('Argument without a value: %s', key);
  endif
  val = args{k+1};
  switch key
    case '--input',          opts.input = val;
    case '--out',            opts.out = val;
    case '--parser',         opts.parser = val;
    case '--delimiter',      opts.delimiter = val;
    case '--header-lines',   opts.header_lines = str2double(val);
    case '--sequence-col',   opts.sequence_col = str2double(val);
    case '--time-col',       opts.time_col = str2double(val);
    case '--tstart',         opts.tstart = str2double(val);
    case '--dt',             opts.dt = str2double(val);
    case '--channels',       opts.channels = val;
    case '--make-rigol',     opts.make_rigol = logical(str2double(val));
    case '--make-canonical', opts.make_canonical = logical(str2double(val));
    case '--manifest',       opts.manifest = val;
    case '--workers',        opts.workers = max(1, round(str2double(val)));
    case '--chunk-rows',     opts.chunk_rows = max(1000, round(str2double(val)));
    case '--raw-fields',     opts.raw_fields = round(str2double(val));
    case '--drop-trailing-fields', opts.drop_trailing_fields = round(str2double(val));
    case '--strict-sequence', opts.strict_sequence = logical(str2double(val));
    otherwise
      error('Unknown option: %s', key);
  endswitch
  k += 2;
endwhile

if strcmp(opts.delimiter, 'tab')
  delim = sprintf('\t');
else
  delim = opts.delimiter;
endif

if isempty(opts.input) || isempty(opts.out) || isempty(opts.channels)
  error('--input, --out and --channels are required.');
endif
if exist(opts.input, 'file') != 2
  error('File not found: %s', opts.input);
endif
if opts.header_lines < 0 || fix(opts.header_lines) != opts.header_lines
  error('--header-lines must be an integer >= 0.');
endif
if exist(opts.out, 'dir') != 7
  [ok, msg] = mkdir(opts.out);
  if !ok, error('Unable to create output: %s', msg); endif
endif

printf('[STAGE 1/5] Reading header and CSV structure\n'); fflush(stdout);

info = dir(opts.input);
file_bytes = info.bytes;
fid = fopen(opts.input, 'r');
if fid < 0, error('Unable to open: %s', opts.input); endif
headers = cell(opts.header_lines, 1);
for i = 1:opts.header_lines
  line = fgetl(fid);
  if !ischar(line)
    fclose(fid);
    error('The file ends within the header rows.');
  endif
  headers{i} = line;
endfor
first_data_pos = ftell(fid);
first_data = fgetl(fid);
while ischar(first_data) && isempty(strtrim(first_data))
  first_data_pos = ftell(fid);
  first_data = fgetl(fid);
endwhile
if !ischar(first_data)
  fclose(fid);
  error('No data rows found.');
endif
parts = strsplit(first_data, delim);
detected_raw_fields = numel(parts);
detected_trailing_empty = 0;
tmp_parts = parts;
while !isempty(tmp_parts) && isempty(strtrim(tmp_parts{end}))
  tmp_parts(end) = [];
  detected_trailing_empty += 1;
endwhile
fclose(fid);

if opts.raw_fields > 0
  raw_fields = opts.raw_fields;
else
  raw_fields = detected_raw_fields;
endif
if opts.drop_trailing_fields < 0 || fix(opts.drop_trailing_fields) != opts.drop_trailing_fields
  error('--drop-trailing-fields must be an integer >= 0.');
endif
if raw_fields < 2 || fix(raw_fields) != raw_fields
  error('--raw-fields must be 0 (auto) or an integer >= 2.');
endif
if opts.drop_trailing_fields >= raw_fields
  error('drop_trailing_fields >= raw_fields: invalid configuration.');
endif
ncols = raw_fields - opts.drop_trailing_fields;

printf('Raw fields detected in first data row: %d\n', detected_raw_fields);
printf('Trailing empty fields detected: %d\n', detected_trailing_empty);
if opts.raw_fields > 0, mode_txt='manuale'; else mode_txt='auto'; endif
printf('Raw fields per record USED: %d (%s)\n', raw_fields, mode_txt);
printf('Trailing fields ignored AFTER reading: %d\n', opts.drop_trailing_fields);
printf('Effective data columns: %d\n', ncols);
printf('File size: %.3f MiB\n', file_bytes / 1024 / 1024);
printf('Rows per block: %d\n', opts.chunk_rows);
printf('Requested CPU/threads: %d\n', opts.workers);
fflush(stdout);

% Parse channel specification: CSVcolumn|scope|logical ; ...
rawch = strsplit(opts.channels, ';');
channels = struct('column', {}, 'scope', {}, 'name', {}, 'safe', {}, ...
                  'finite_N', {}, 'min', {}, 'max', {}, 'sum', {}, ...
                  'written_N', {}, 'first_raw', {}, 'last_raw', {}, ...
                  'rigol_fid', {}, 'rigol_tmp', {}, 'rigol_final', {}, ...
                  'canonical_fid', {}, 'canonical_tmp', {}, 'canonical_final', {}, ...
                  'rigol_integrity', {}, 'canonical_integrity', {});
for i = 1:numel(rawch)
  p = strsplit(rawch{i}, '|');
  if numel(p) != 3
    error('Invalid channel specification: %s', rawch{i});
  endif
  col = str2double(p{1});
  if isnan(col) || col < 1 || fix(col) != col || col > ncols
    error('Invalid channel column: %s (ncols=%d)', p{1}, ncols);
  endif
  channels(i).column = col;
  channels(i).scope = p{2};
  channels(i).name = p{3};
  safe = regexprep(strtrim(p{3}), '[^A-Za-z0-9_.-]+', '_');
  safe = regexprep(safe, '_+', '_');
  if isempty(safe), safe = sprintf('channel_%d', i); endif
  channels(i).safe = safe;
  channels(i).finite_N = 0;
  channels(i).min = Inf;
  channels(i).max = -Inf;
  channels(i).sum = 0;
  channels(i).written_N = 0;
  channels(i).first_raw = NaN;
  channels(i).last_raw = NaN;
  channels(i).rigol_integrity = false;
  channels(i).canonical_integrity = false;
  channels(i).rigol_fid = -1;
  channels(i).canonical_fid = -1;
endfor

% Determine fixed time metadata before streaming.
tStart = NaN;
dt = NaN;
if strcmp(opts.parser, 'rigol_ds1000z')
  if opts.header_lines < 2
    error('rigol_ds1000z requires at least 2 header rows.');
  endif
  hnames = strsplit(headers{1}, delim);
  hvals  = strsplit(headers{2}, delim);
  nmeta = min(numel(hnames), numel(hvals));
  idx_start = 0;
  idx_increment = 0;
  for hi = 1:nmeta
    key = strtrim(hnames{hi});
    if strcmpi(key, 'Start'), idx_start = hi; endif
    if strcmpi(key, 'Increment'), idx_increment = hi; endif
  endfor
  if idx_start == 0 || idx_increment == 0
    error('Rigol header: Start/Increment fields not found in the first row.');
  endif
  tStart = str2double(strtrim(hvals{idx_start}));
  dt = str2double(strtrim(hvals{idx_increment}));
  if isnan(tStart) || isnan(dt) || dt <= 0
    error('Rigol header: Start/Increment values are not numeric or are invalid.');
  endif
  printf('Rigol header: Start header column=%d, Increment header column=%d\n', idx_start, idx_increment);
elseif strcmp(opts.parser, 'generic_sequence')
  if isnan(opts.tstart) || isnan(opts.dt) || opts.dt <= 0
    error('generic_sequence requires valid --tstart and --dt values.');
  endif
  tStart = opts.tstart;
  dt = opts.dt;
elseif !strcmp(opts.parser, 'generic_time')
  error('Unknown parser: %s', opts.parser);
endif

if (strcmp(opts.parser, 'rigol_ds1000z') || strcmp(opts.parser, 'generic_sequence')) ...
    && (opts.sequence_col < 1 || opts.sequence_col > ncols)
  error('sequence_col is out of range.');
endif
if strcmp(opts.parser, 'generic_time') && (opts.time_col < 1 || opts.time_col > ncols)
  error('time_col is out of range.');
endif

% Prepare temporary outputs. They are intentionally visible while processing.
for i = 1:numel(channels)
  if opts.make_rigol
    channels(i).rigol_final = fullfile(opts.out, [channels(i).safe '_rigol.csv']);
    channels(i).rigol_tmp = [channels(i).rigol_final '.part'];
    channels(i).rigol_fid = fopen(channels(i).rigol_tmp, 'w');
    if channels(i).rigol_fid < 0, error('Unable to create %s', channels(i).rigol_tmp); endif
    % Estratto Rigol coerente a un solo canale: i metadati temporali
    % restano nell'header, mentre le righe dati contengono Sequence,V.
    fprintf(channels(i).rigol_fid, 'X,%s,Start,Increment,\n', channels(i).scope);
    fprintf(channels(i).rigol_fid, 'Sequence,Volt,%.17g,%.17g\n', tStart, dt);
  endif
  if opts.make_canonical
    channels(i).canonical_final = fullfile(opts.out, [channels(i).safe '_canonical.csv']);
    channels(i).canonical_tmp = [channels(i).canonical_final '.part'];
    channels(i).canonical_fid = fopen(channels(i).canonical_tmp, 'w');
    if channels(i).canonical_fid < 0, error('Unable to create %s', channels(i).canonical_tmp); endif
    fprintf(channels(i).canonical_fid, 'time_s,%s\n', channels(i).name);
  endif
endfor

printf('[STAGE 2/5] Streaming CSV import\n'); fflush(stdout);

fid = fopen(opts.input, 'r');
if fid < 0, error('Unable to reopen CSV.'); endif
for i = 1:opts.header_lines
  if !ischar(fgetl(fid))
    fclose(fid); error('Error while skipping the header.');
  endif
endfor
fmt = repmat('%f', 1, raw_fields);
N = 0;
first_time = NaN;
last_time = NaN;
last_seq = NaN;
first_seq = NaN;
prev_seq = NaN;
sequence_bad = 0;
sequence_checked = 0;
time_dt_samples = [];
block_index = 0;
last_report_clock = time();

while !feof(fid)
  C = textscan(fid, fmt, opts.chunk_rows, 'Delimiter', delim, 'CollectOutput', true, ...
               'EmptyValue', NaN, 'ReturnOnError', false);
  if isempty(C) || isempty(C{1})
    break;
  endif
  rawdata = C{1};
  nr = rows(rawdata);
  if nr == 0, break; endif
  if columns(rawdata) != raw_fields
    fclose(fid); error('Field count changed during import: expected %d, read %d.', raw_fields, columns(rawdata));
  endif
  data = rawdata(:, 1:ncols);

  if strcmp(opts.parser, 'rigol_ds1000z') || strcmp(opts.parser, 'generic_sequence')
    seq = data(:, opts.sequence_col);
    t = tStart + seq .* dt;
    goodseq = seq(isfinite(seq));
    if !isempty(goodseq)
      if isnan(first_seq), first_seq = goodseq(1); endif
      if !isnan(prev_seq)
        if abs(goodseq(1) - prev_seq - 1) > 1e-9, sequence_bad += 1; endif
      endif
      if numel(goodseq) > 1
        dd = diff(goodseq);
        sequence_bad += sum(abs(dd - 1) > 1e-9);
        sequence_checked += numel(dd);
      endif
      prev_seq = goodseq(end);
      last_seq = goodseq(end);
    endif
  else
    t = data(:, opts.time_col);
    goodt = t(isfinite(t));
    if !isempty(goodt)
      if isnan(first_time), first_time = goodt(1); endif
      last_time = goodt(end);
      if numel(time_dt_samples) < 10000
        need = 10001 - numel(time_dt_samples);
        take = goodt(1:min(numel(goodt), need));
        time_dt_samples = [time_dt_samples; take(:)];
      endif
    endif
    seq = (N:(N+nr-1))';
  endif

  if isnan(first_time)
    goodt = t(isfinite(t));
    if !isempty(goodt), first_time = goodt(1); endif
  endif
  goodt = t(isfinite(t));
  if !isempty(goodt), last_time = goodt(end); endif

  for i = 1:numel(channels)
    v = data(:, channels(i).column);
    if channels(i).written_N == 0 && !isempty(v)
      channels(i).first_raw = v(1);
    endif
    if !isempty(v), channels(i).last_raw = v(end); endif
    channels(i).written_N += nr;
    mask = isfinite(v);
    vf = v(mask);
    if !isempty(vf)
      channels(i).finite_N += numel(vf);
      channels(i).min = min(channels(i).min, min(vf));
      channels(i).max = max(channels(i).max, max(vf));
      channels(i).sum += sum(vf);
    endif

    if opts.make_rigol
      block = [seq, v]';
      fprintf(channels(i).rigol_fid, '%.12g,%.12g\n', block);
    endif
    if opts.make_canonical
      block = [t, v]';
      fprintf(channels(i).canonical_fid, '%.12g,%.12g\n', block);
    endif
  endfor

  N += nr;
  block_index += 1;
  pos = ftell(fid);
  if file_bytes > 0
    pct = min(100, 100 * pos / file_bytes);
  else
    pct = NaN;
  endif
  nowc = time();
  if block_index == 1 || nowc - last_report_clock >= 3 || feof(fid)
    printf('[IMPORT] block=%d rows=%d total=%d progress=%.1f%% block_RAM=%.1f MiB\n', ...
           block_index, nr, N, pct, numel(rawdata)*8/1024/1024);
    fflush(stdout);
    last_report_clock = nowc;
  endif
  clear C rawdata data t seq;
endwhile
fclose(fid);

if N == 0
  error('Numeric import failed or dataset is empty.');
endif
printf('Imported samples: %d\n', N); fflush(stdout);

printf('[STAGE 3/5] Reconstructing and validating the time axis\n'); fflush(stdout);
if strcmp(opts.parser, 'generic_time')
  if numel(time_dt_samples) >= 2
    d = diff(time_dt_samples);
    d = d(isfinite(d) & d > 0);
    if isempty(d), dt = NaN; else dt = median(d); endif
  endif
  tStart = first_time;
endif
if isfinite(dt) && dt > 0, fs = 1/dt; else fs = NaN; endif
if isfinite(first_time) && isfinite(last_time), duration = last_time - first_time; else duration = NaN; endif
expected_duration_N = NaN;
expected_duration_seq = NaN;
if isfinite(dt) && N > 1, expected_duration_N = (N-1) * dt; endif
if isfinite(dt) && isfinite(first_seq) && isfinite(last_seq), expected_duration_seq = (last_seq-first_seq) * dt; endif
printf('tStart = %.12g s\n', tStart);
printf('dt     = %.12g s\n', dt);
printf('Fs     = %.12g Sa/s\n', fs);
printf('duration = %.12g s\n', duration);
if strcmp(opts.parser, 'rigol_ds1000z') || strcmp(opts.parser, 'generic_sequence')
  printf('Initial Sequence = %.12g\n', first_seq);
  printf('Final Sequence   = %.12g\n', last_seq);
  printf('Duration from N       = %.12g s\n', expected_duration_N);
  printf('Duration from Sequence= %.12g s\n', expected_duration_seq);
  printf('Sequence errors    = %d\n', sequence_bad);
  if opts.strict_sequence && sequence_bad > 0
    error('Sequence validation failed: %d discontinuities/misalignments. Outputs were left as .part files.', sequence_bad);
  endif
  if opts.strict_sequence && isfinite(expected_duration_N) && isfinite(expected_duration_seq) && abs(expected_duration_N-expected_duration_seq) > max(1e-12, 0.5*dt)
    error('Inconsistent duration between N and Sequence. Outputs left as .part.');
  endif
endif
fflush(stdout);

printf('[STAGE 4/5] Finalization, integrity checks and statistics\n'); fflush(stdout);

% Chiudere prima tutti gli output .part. Nessun file viene promosso a finale
% finche tutti i controlli di integrita non sono superati.
for i = 1:numel(channels)
  if opts.make_rigol && channels(i).rigol_fid >= 0
    fclose(channels(i).rigol_fid);
    channels(i).rigol_fid = -1;
  endif
  if opts.make_canonical && channels(i).canonical_fid >= 0
    fclose(channels(i).canonical_fid);
    channels(i).canonical_fid = -1;
  endif
  if channels(i).written_N != N
    error('Integrity %s: rows written=%d, expected=%d. Outputs left as .part.', ...
          channels(i).name, channels(i).written_N, N);
  endif
endfor

% Verifica leggera ma indipendente: rilettura del primo e ultimo record di
% ciascun estratto e confronto con Sequence/time e tensione osservati nel RAW.
for i = 1:numel(channels)
  if opts.make_rigol
    path = channels(i).rigol_tmp;
    vf = fopen(path, 'r');
    if vf < 0, error('Integrity: unable to reread %s', path); endif
    h1 = fgetl(vf); h2 = fgetl(vf); first_line = fgetl(vf);
    fclose(vf);
    if !ischar(first_line), error('Integrity %s: first Rigol record is missing.', channels(i).name); endif

    finfo = dir(path);
    vf = fopen(path, 'r');
    if vf < 0, error('Integrity: unable to reread tail of %s', path); endif
    back = min(8192, finfo.bytes);
    fseek(vf, -back, 'eof');
    tail = fread(vf, Inf, '*char')';
    fclose(vf);
    tail = strrep(tail, sprintf('\r'), '');
    lines = strsplit(tail, sprintf('\n'));
    while !isempty(lines) && isempty(strtrim(lines{end}))
      lines(end) = [];
    endwhile
    if isempty(lines), error('Integrity %s: last Rigol record is missing.', channels(i).name); endif
    last_line = lines{end};

    fp = strsplit(first_line, ',');
    lp = strsplit(last_line, ',');
    if numel(fp) < 2 || numel(lp) < 2
      error('Integrity %s: invalid Rigol extract format.', channels(i).name);
    endif
    out_first_seq = str2double(strtrim(fp{1}));
    out_first_v = str2double(strtrim(fp{2}));
    out_last_seq = str2double(strtrim(lp{1}));
    out_last_v = str2double(strtrim(lp{2}));
    vtol1 = max(1e-10, 1e-9 * max(1, abs(channels(i).first_raw)));
    vtol2 = max(1e-10, 1e-9 * max(1, abs(channels(i).last_raw)));
    ok_seq = isfinite(out_first_seq) && isfinite(out_last_seq) && ...
             abs(out_first_seq-first_seq) <= 1e-9 && abs(out_last_seq-last_seq) <= 1e-9;
    ok_v = ((isnan(channels(i).first_raw) && isnan(out_first_v)) || abs(out_first_v-channels(i).first_raw) <= vtol1) && ...
           ((isnan(channels(i).last_raw) && isnan(out_last_v)) || abs(out_last_v-channels(i).last_raw) <= vtol2);
    if !ok_seq || !ok_v
      error('Rigol integrity %s failed: first/last record does not match RAW. Outputs left as .part.', channels(i).name);
    endif
    channels(i).rigol_integrity = true;
    printf('[VERIFY] %-20s Rigol     rows=%d first=OK last=OK\n', channels(i).name, channels(i).written_N);
  endif

  if opts.make_canonical
    path = channels(i).canonical_tmp;
    vf = fopen(path, 'r');
    if vf < 0, error('Integrity: unable to reread %s', path); endif
    hh = fgetl(vf); first_line = fgetl(vf);
    fclose(vf);
    if !ischar(first_line), error('Integrity %s: first canonical record is missing.', channels(i).name); endif

    finfo = dir(path);
    vf = fopen(path, 'r');
    if vf < 0, error('Integrity: unable to reread tail of %s', path); endif
    back = min(8192, finfo.bytes);
    fseek(vf, -back, 'eof');
    tail = fread(vf, Inf, '*char')';
    fclose(vf);
    tail = strrep(tail, sprintf('\r'), '');
    lines = strsplit(tail, sprintf('\n'));
    while !isempty(lines) && isempty(strtrim(lines{end}))
      lines(end) = [];
    endwhile
    if isempty(lines), error('Integrity %s: last canonical record is missing.', channels(i).name); endif
    last_line = lines{end};

    fp = strsplit(first_line, ',');
    lp = strsplit(last_line, ',');
    if numel(fp) < 2 || numel(lp) < 2
      error('Integrity %s: invalid canonical extract format.', channels(i).name);
    endif
    out_first_t = str2double(strtrim(fp{1}));
    out_first_v = str2double(strtrim(fp{2}));
    out_last_t = str2double(strtrim(lp{1}));
    out_last_v = str2double(strtrim(lp{2}));
    ttol = max(1e-12, abs(dt)*1e-6);
    vtol1 = max(1e-10, 1e-9 * max(1, abs(channels(i).first_raw)));
    vtol2 = max(1e-10, 1e-9 * max(1, abs(channels(i).last_raw)));
    ok_t = isfinite(out_first_t) && isfinite(out_last_t) && ...
           abs(out_first_t-first_time) <= ttol && abs(out_last_t-last_time) <= ttol;
    ok_v = ((isnan(channels(i).first_raw) && isnan(out_first_v)) || abs(out_first_v-channels(i).first_raw) <= vtol1) && ...
           ((isnan(channels(i).last_raw) && isnan(out_last_v)) || abs(out_last_v-channels(i).last_raw) <= vtol2);
    if !ok_t || !ok_v
      error('Canonical integrity %s failed: first/last record does not match RAW. Outputs left as .part.', channels(i).name);
    endif
    channels(i).canonical_integrity = true;
    printf('[VERIFY] %-20s canonical rows=%d first=OK last=OK\n', channels(i).name, channels(i).written_N);
  endif
  fflush(stdout);
endfor

% Solo ora creare statistiche e promuovere tutti i .part a file finali.
summary_tmp = fullfile(opts.out, 'summary.tsv.part');
summary_final = fullfile(opts.out, 'summary.tsv');
sf = fopen(summary_tmp, 'w');
if sf < 0, error('Unable to create summary.tsv.part'); endif
fprintf(sf, 'logical_name\tscope_channel\tcsv_column\tN\tfinite_N\tmin_V\tmax_V\tVpp_V\tmean_V\trigol_integrity\tcanonical_integrity\n');
for i = 1:numel(channels)
  if channels(i).finite_N > 0
    vmin = channels(i).min; vmax = channels(i).max;
    vmean = channels(i).sum / channels(i).finite_N;
    vpp = vmax - vmin;
  else
    vmin = NaN; vmax = NaN; vmean = NaN; vpp = NaN;
  endif
  fprintf(sf, '%s\t%s\t%d\t%d\t%d\t%.12g\t%.12g\t%.12g\t%.12g\t%d\t%d\n', ...
          channels(i).name, channels(i).scope, channels(i).column, N, ...
          channels(i).finite_N, vmin, vmax, vpp, vmean, ...
          channels(i).rigol_integrity, channels(i).canonical_integrity);
endfor
fclose(sf);

for i = 1:numel(channels)
  if opts.make_rigol
    if exist(channels(i).rigol_final, 'file') == 2, unlink(channels(i).rigol_final); endif
    [ok,msg] = movefile(channels(i).rigol_tmp, channels(i).rigol_final);
    if !ok, error('Rename failed %s: %s', channels(i).rigol_tmp, msg); endif
    printf('Created and verified: %s\n', channels(i).rigol_final);
  endif
  if opts.make_canonical
    if exist(channels(i).canonical_final, 'file') == 2, unlink(channels(i).canonical_final); endif
    [ok,msg] = movefile(channels(i).canonical_tmp, channels(i).canonical_final);
    if !ok, error('Rename failed %s: %s', channels(i).canonical_tmp, msg); endif
    printf('Created and verified: %s\n', channels(i).canonical_final);
  endif
endfor
if exist(summary_final, 'file') == 2, unlink(summary_final); endif
[ok,msg] = movefile(summary_tmp, summary_final);
if !ok, error('Summary rename failed: %s', msg); endif
printf('Extract integrity: OK (%d channels, %d samples per channel)\n', numel(channels), N);
fflush(stdout);

printf('[STAGE 5/5] Writing import metadata\n'); fflush(stdout);
result_tmp = fullfile(opts.out, 'import_result.ini.part');
result_final = fullfile(opts.out, 'import_result.ini');
rf = fopen(result_tmp, 'w');
if rf < 0, error('Unable to create import_result.ini.part'); endif
fprintf(rf, '[dataset]\n');
fprintf(rf, 'source=%s\n', opts.input);
fprintf(rf, 'parser=%s\n', opts.parser);
fprintf(rf, 'rows=%d\n', N);
fprintf(rf, 'raw_fields=%d\n', raw_fields);
fprintf(rf, 'drop_trailing_fields=%d\n', opts.drop_trailing_fields);
fprintf(rf, 'columns=%d\n', ncols);
fprintf(rf, 'tStart_s=%.17g\n', tStart);
fprintf(rf, 'dt_s=%.17g\n', dt);
fprintf(rf, 'sample_rate_Sa_s=%.17g\n', fs);
fprintf(rf, 'duration_s=%.17g\n', duration);
fprintf(rf, 'sequence_first=%.17g\n', first_seq);
fprintf(rf, 'sequence_last=%.17g\n', last_seq);
fprintf(rf, 'sequence_errors=%d\n', sequence_bad);
fprintf(rf, 'channels=%d\n', numel(channels));
fprintf(rf, 'workers=%d\n', opts.workers);
fprintf(rf, 'chunk_rows=%d\n', opts.chunk_rows);
fprintf(rf, 'manifest=%s\n', opts.manifest);
fprintf(rf, '\n[integrity]\n');
fprintf(rf, 'status=OK\n');
fprintf(rf, 'expected_rows=%d\n', N);
for i = 1:numel(channels)
  fprintf(rf, 'channel%d.name=%s\n', i, channels(i).name);
  fprintf(rf, 'channel%d.rows_written=%d\n', i, channels(i).written_N);
  fprintf(rf, 'channel%d.rigol=%d\n', i, channels(i).rigol_integrity);
  fprintf(rf, 'channel%d.canonical=%d\n', i, channels(i).canonical_integrity);
endfor
fclose(rf);
if exist(result_final, 'file') == 2, unlink(result_final); endif
[ok,msg] = movefile(result_tmp, result_final);
if !ok, error('import_result rename failed: %s', msg); endif

printf('OK: streaming import/split completed.\n'); fflush(stdout);
