function identity=gxtxt_curve_source_dataset_identity_v1(session,dataset_id)
% Read public CORE scientific content/schema identity without a display token.
% SPDX-License-Identifier: GPL-3.0-or-later
  root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
  bridge=fullfile(root,'core','tcl','curve_source_identity_bridge.tcl');
  [input,output,pid]=popen2('tclsh',{bridge,char(session),char(dataset_id)});
  if(pid<0),error('GXTXT:CurveSource','Cannot start CORE identity adapter');endif
  unwind_protect
    fclose(input);input=-1;
    line=gxtxt_persistent_bridge_readline(output,pid,'Curve Source identity');
    fields=strsplit(line,sprintf('\t'));
    if(numel(fields)==2&&strcmp(fields{1},'CURVE_SOURCE_IDENTITY_ERROR_V1'))
      error('GXTXT:CurveSource','%s',native2unicode(matlab.net.base64decode(fields{2}),'UTF-8'));
    endif
    if(numel(fields)!=4||!strcmp(fields{1},'CURVE_SOURCE_IDENTITY_V1')|| ...
       isempty(regexp(fields{3},'^[0-9a-f]{64}$','once'))||isempty(regexp(fields{4},'^[0-9a-f]{64}$','once')))
      error('GXTXT:CurveSource','Invalid CORE scientific identity response');
    endif
    identity=struct('dataset_id',fields{2},'sha256',fields{3},'schema_identity',fields{4});
  unwind_protect_cleanup
    if(input>=0),fclose(input);endif
    fclose(output);[~,status]=waitpid(pid);
  end_unwind_protect
  if(status!=0),error('GXTXT:CurveSource','CORE scientific identity adapter failed');endif
endfunction
