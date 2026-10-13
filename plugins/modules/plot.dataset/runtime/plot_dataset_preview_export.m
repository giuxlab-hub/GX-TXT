% Public read-only Preview export. Reuse normal scientific rendering authority.
this_file=mfilename('fullpath');runtime_dir=fileparts(this_file);
root=fileparts(fileparts(fileparts(fileparts(runtime_dir))));addpath(runtime_dir);
for d={'analysis','graphics','io','units','util','cache'},addpath(fullfile(root,'core','octave',d{1}));endfor
args=argv();if(numel(args)!=3),error('Usage: preview_export prepared-cache runtime-ini new-directory');endif
S=load(args{1});cfg=gxtxt_ini_read(args{2});
if(!isfield(S,'cache')||!isfield(S.cache.module,'plot3d')),error('Original prepared 3D cache unavailable; render graph first');endif
pd_render_3d('',cfg,S.cache.module.plot3d,'plot.dataset.xyz','',args{3});
