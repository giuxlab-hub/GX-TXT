% Public CORE ingress for a staged computation-owned binary descriptor.
% Descriptor validation/dtype/layout remain at the shared CORE buffer owner.
% SPDX-License-Identifier: GPL-3.0-or-later
function values=gxtxt_scientific_array_read_v1(workspace,descriptor)
  if(!ischar(workspace)||isempty(workspace)||workspace(1)!=filesep()),error('GXTXT:ScientificTransport:Workspace','An absolute computation workspace is required');endif
  [st,err]=lstat(workspace);
  if(err||!S_ISDIR(st.mode)||st.uid!=getuid()),error('GXTXT:ScientificTransport:Workspace','Computation workspace owner/type mismatch');endif
  addpath(fullfile(fileparts(mfilename('fullpath')),'util'));
  values=gxtxt_binary_resource_v1('read',workspace,descriptor);
endfunction
