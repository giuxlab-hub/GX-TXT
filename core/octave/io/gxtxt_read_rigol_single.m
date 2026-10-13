% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT pipeline - lettore dell'estratto Rigol normalizzato a singolo canale.
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
% GNU GPL v3 or later.
%
% Formato prodotto dal worker della pipeline:
%   X,CHx,Start,Increment,
%   Sequence,Volt,<tStart>,<dt>
%   0,8.8
%   1,8.8
%   ...

function [seq,v,tStart,dt] = gxtxt_read_rigol_single(path,chunkRows)
  if (nargin < 2 || isempty(chunkRows)), chunkRows = 250000; endif
  fid = fopen(path,'r');
  if (fid < 0), error('Unable to open %s',path); endif
  cleaner = onCleanup(@() fclose(fid));

  h1 = fgetl(fid); h2 = fgetl(fid);
  if (!ischar(h1) || !ischar(h2)), error('Incomplete header: %s',path); endif
  [tStart,dt] = gxtxt_parse_rigol_header(h1,h2);

  sc = {};
  vc = {};
  n = 0;
  while (!feof(fid))
    % I record generati dalla pipeline NON hanno la virgola terminale.
    % fscanf ripete il formato per coppie complete Sequence,Volt e non
    % perde l'allineamento tra righe come il precedente scanset textscan.
    A = fscanf(fid,'%f,%f\n',[2,chunkRows])';
    if (isempty(A)), break; endif
    if (columns(A) != 2), error('Incomplete record in %s',path); endif
    if (any(!isfinite(A(:)))), error('NaN/Inf nell''estratto %s',path); endif
    sc{end+1,1} = A(:,1);
    vc{end+1,1} = A(:,2);
    n += rows(A);
  endwhile

  if (n == 0), error('No data in %s',path); endif
  seq = vertcat(sc{:});
  v = vertcat(vc{:});

  if (numel(seq) > 1)
    bad = sum(abs(diff(seq)-1) > 1e-9);
    if (bad != 0)
      error('Sequence non continua in %s: %d errori.',path,bad);
    endif
  endif
endfunction
