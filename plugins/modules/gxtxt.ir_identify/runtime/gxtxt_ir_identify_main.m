function gxtxt_ir_identify_main(args)
  try,gxtxt_ir_identify_main_impl(args);catch err,try,gxtxt_progress_fail('failed','IR protocol identification failed; see log for details');catch,end_try_catch;rethrow(err);end_try_catch
endfunction

function gxtxt_ir_identify_main_impl(args)
% Protocol identification consumes the deterministic MARK/SPACE artifact from
% gxtxt.ir_waveform. The historical V1 algorithm is used as a design trace,
% with explicit score components, UNKNOWN/AMBIGUOUS outcomes and diagnostics.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('gxtxt.ir_identify: --config is required');endif
  cfg=read_ini(config_path);outdir=ini_get(cfg,'runtime.output_dir','');if(isempty(outdir)),error('gxtxt.ir_identify: runtime.output_dir missing');endif;if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  numeric_fn=discover_numeric_api(cfg);
  session=strtrim(ini_get(cfg,'runtime.session',''));data_path=ini_get(cfg,'dataset.path','');if(isempty(session)),session=fileparts(fileparts(data_path));endif
  dataset_id=strtrim(ini_get(cfg,'dataset.id',''));signal_name=strtrim(ini_get(cfg,'bindings.signal',''));if(isempty(signal_name)),error('gxtxt.ir_identify: signal binding is unresolved');endif
  % The public binding is source-qualified, while waveform records the raw
  % column name in its analysis manifest. Both modules use the primary source.
  if(strncmp(signal_name,'primary.',8)),signal_name=signal_name(9:end);endif

  gxtxt_progress_start('locating_waveform','Locating IR waveform analysis artifact','indeterminate');
  manifest_path=find_waveform_manifest(session,dataset_id,signal_name,outdir);M=read_ini(manifest_path);base=fileparts(manifest_path);
  events_path=fullfile(base,ini_get(M,'ir_analysis.events_file','eventi_mark_space.csv'));if(exist(events_path,'file')!=2),error('gxtxt.ir_identify: events file not found: %s',events_path);endif
  carrier_hz=str2double(ini_get(M,'ir_analysis.carrier_hz','NaN'));carrier_kHz=carrier_hz/1000;

  gxtxt_progress_stage('loading_events','Loading MARK / SPACE sequence','indeterminate');
  E=read_events(events_path);if(numel(E.type)<5),error('gxtxt.ir_identify: too few MARK/SPACE events (%d)',numel(E.type));endif
  protocols=load_protocols();

  gxtxt_progress_stage('matching','Scoring protocol candidates','indeterminate');
  R=struct([]);for k=1:numel(protocols),R(k)=evaluate_protocol(E,carrier_kHz,protocols(k),numeric_fn);endfor
  scores=[R.score];[~,order]=sort(scores);best=order(1);if(numel(order)>1),runner=order(2);margin=R(runner).score-R(best).score;else runner=[];margin=Inf;endif
  acceptScore=get_num(cfg,'config.accept_score_threshold',0.28);minMargin=get_num(cfg,'config.minimum_score_margin',0.03);
  if(R(best).score>=acceptScore),status='UNKNOWN';accepted=false;elseif(margin<minMargin),status='AMBIGUOUS';accepted=false;else status='ACCEPTED';accepted=true;endif
  quality=confidence_text(R(best).score);

  D=timing_diagnostics(E,protocols(best),R(best));
  F=frame_diagnostics(E,protocols(best),R(best));

  gxtxt_progress_stage('writing_results','Writing protocol identification outputs','indeterminate');
  write_candidates(fullfile(outdir,'protocol_candidates.csv'),R,order);
  write_timing(fullfile(outdir,'protocol_timing.csv'),D);
  write_frame(fullfile(outdir,'protocol_frame.csv'),F);
  write_report(fullfile(outdir,'protocol_identification.txt'),cfg,manifest_path,events_path,carrier_kHz,protocols,R,order,best,runner,margin,status,accepted,quality,acceptScore,minMargin);
  ids=gxtxt_ir_identify_publish(session,dataset_id,R,order,D,E,F);
  rank_labels={R(order).name};rank_scores=[R(order).score];best_name=R(best).name;best_score=R(best).score;
  expected_values=gxtxt_ir_expected_values(protocols(best));frame_annotations=gxtxt_ir_frame_annotations(F);
  identification_status=status;
  save('-binary',fullfile(outdir,'render_cache.mat'),'ids','rank_labels','rank_scores','best_name','identification_status','expected_values','frame_annotations');

  gxtxt_progress_stage('rendering','Rendering protocol diagnostic graphs','indeterminate');
  gxtxt_ir_identify_render(outdir,cfg,ids,rank_labels,rank_scores,expected_values,frame_annotations,best_name,status);
  gxtxt_progress_complete('done','IR protocol identification completed');
  fprintf('[gxtxt.ir_identify] status=%s best=%s score=%.4f margin=%.4f carrier=%.3f_kHz\n',status,best_name,best_score,margin,carrier_kHz);
endfunction

function P=load_protocols()
  thisdir=fileparts(mfilename('fullpath'));path=fullfile(fileparts(thisdir),'protocols','protocols_ir_v1.csv');fid=fopen(path,'r');if(fid<0),error('gxtxt.ir_identify: cannot open protocol table %s',path);endif
  header=fgetl(fid);P=struct([]);k=0;unwind_protect
    while(true),line=fgetl(fid);if(!ischar(line)),break;endif;line=strtrim(line);if(isempty(line)||line(1)=='#'),continue;endif;c=strsplit(line,',','collapsedelimiters',false);if(numel(c)<15),continue;endif;k++;P(k).id=strtrim(c{1});P(k).name=strtrim(c{2});P(k).kind=strtrim(c{3});P(k).carrier=num(c{4});P(k).headerMark=num(c{5});P(k).headerSpace=num(c{6});P(k).bitMark=num(c{7});P(k).zeroSpace=num(c{8});P(k).oneSpace=num(c{9});P(k).zeroMark=num(c{10});P(k).oneMark=num(c{11});P(k).bitSpace=num(c{12});P(k).unit=num(c{13});P(k).bits=parse_num_list(c{14});P(k).lsbFirst=parse_bool(c{15},false);endwhile
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
  if(isempty(P)),error('gxtxt.ir_identify: protocol table is empty');endif
endfunction

function R=evaluate_protocol(E,carrier,P,numeric_fn)
  R=empty_result(P);R.carrierErr=carrier_error(carrier,P.carrier);
  if(strcmp(P.kind,'pulse_distance')),R=evaluate_pulse_distance(E,carrier,P,R,numeric_fn);
  elseif(strcmp(P.kind,'pulse_width')),R=evaluate_pulse_width(E,carrier,P,R,numeric_fn);
  elseif(strcmp(P.kind,'biphase')),R=evaluate_biphase(E,carrier,P,false,R,numeric_fn);
  elseif(strcmp(P.kind,'biphase_header')),R=evaluate_biphase(E,carrier,P,true,R,numeric_fn);
  else R.score=9;R.detail='unsupported protocol kind';endif
endfunction

function R=evaluate_pulse_distance(E,carrier,P,R,numeric_fn)
  [idxHeader,headerErr]=find_header(E.type,E.duration_us,P.headerMark,P.headerSpace);R.headerErr=headerErr;if(isempty(idxHeader)),R.score=9;R.detail='header MARK/SPACE not found';return;endif
  [bits,markErr,dataErr,nBits,bitEvents]=extract_pulse_distance(E.type,E.duration_us,idxHeader,P,numeric_fn);R.markErr=markErr;R.dataErr=dataErr;R.bitErr=bitcount_error(nBits,P.bits);R.headerIndex=idxHeader;R.bitsDecoded=bits;R.bitEventIndex=bitEvents;R.lsbFirst=P.lsbFirst;
  R.score=0.20*R.carrierErr+0.35*headerErr+0.25*dataErr+0.10*markErr+0.10*R.bitErr;
  R.detail=sprintf('header %.3f carrier %.3f data %.3f mark %.3f bitcount %.3f bits=%d',headerErr,R.carrierErr,dataErr,markErr,R.bitErr,nBits);
endfunction

function R=evaluate_pulse_width(E,carrier,P,R,numeric_fn)
  [idxHeader,headerErr]=find_header(E.type,E.duration_us,P.headerMark,P.headerSpace);R.headerErr=headerErr;if(isempty(idxHeader)),R.score=9;R.detail='header MARK/SPACE not found';return;endif
  bits=[];errs=[];spaceErrs=[];bitEvents=[];i=idxHeader+2;
  while(i<=numel(E.type))
    if(!strcmp(E.type{i},'MARK')),break;endif;m=E.duration_us(i);e0=abs(m-P.zeroMark)/P.zeroMark;e1=abs(m-P.oneMark)/P.oneMark;if(min(e0,e1)>0.45),break;endif
    bits(end+1)=(e1<e0);errs(end+1)=min(e0,e1);bitEvents(end+1)=i;
    if(i+1<=numel(E.type)&&strcmp(E.type{i+1},'SPACE')),sp=E.duration_us(i+1);if(sp>4*P.bitSpace),break;endif;spaceErrs(end+1)=abs(sp-P.bitSpace)/P.bitSpace;i=i+2;else break;endif
  endwhile
  if(isempty(errs)),dataErr=1;else dataErr=ir_median(numeric_fn,errs);endif;if(isempty(spaceErrs)),spErr=1;else spErr=ir_median(numeric_fn,spaceErrs);endif
  R.dataErr=dataErr;R.spaceErr=spErr;R.bitErr=bitcount_error(numel(bits),P.bits);R.headerIndex=idxHeader;R.bitsDecoded=bits;R.bitEventIndex=bitEvents;R.lsbFirst=P.lsbFirst;
  R.score=0.20*R.carrierErr+0.35*headerErr+0.20*dataErr+0.15*spErr+0.10*R.bitErr;
  R.detail=sprintf('header %.3f carrier %.3f bit-mark %.3f space %.3f bitcount %.3f bits=%d',headerErr,R.carrierErr,dataErr,spErr,R.bitErr,numel(bits));
endfunction

function R=evaluate_biphase(E,carrier,P,hasHeader,R,numeric_fn)
  startIdx=1;headerErr=0;if(hasHeader),[idxHeader,headerErr]=find_header(E.type,E.duration_us,P.headerMark,P.headerSpace);if(isempty(idxHeader)),R.score=9;R.detail='biphase header not found';return;endif;startIdx=idxHeader+2;R.headerIndex=idxHeader;endif
  vals=[];idxs=[];for i=startIdx:numel(E.duration_us),if(strcmp(E.type{i},'SPACE')&&E.duration_us(i)>10000),break;endif;vals(end+1)=E.duration_us(i);idxs(end+1)=i;endfor
  if(isempty(vals)),R.score=9;R.detail='no useful biphase intervals';return;endif
  ratio=vals/P.unit;nearest=max(1,round(ratio));nearest(nearest>4)=4;timingErr=ir_median(numeric_fn,abs(vals-nearest*P.unit)/P.unit);excessive=ir_mean(numeric_fn,double(ratio>4.5));
  R.headerErr=headerErr;R.timingErr=timingErr;R.biphaseEventIndex=idxs;R.biphaseMultiple=nearest;
  if(hasHeader),R.score=0.25*R.carrierErr+0.35*headerErr+0.35*timingErr+0.05*excessive;else R.score=0.35*R.carrierErr+0.55*timingErr+0.10*excessive;endif
  R.detail=sprintf('carrier %.3f header %.3f biphase-unit %.3f',R.carrierErr,headerErr,timingErr);
endfunction

function [bestIdx,bestErr]=find_header(type,dur,markNom,spaceNom)
  bestIdx=[];bestErr=Inf;if(!isfinite(markNom)||!isfinite(spaceNom)),return;endif
  for i=1:numel(dur)-1,if(strcmp(type{i},'MARK')&&strcmp(type{i+1},'SPACE')),e=(abs(dur(i)-markNom)/markNom+abs(dur(i+1)-spaceNom)/spaceNom)/2;if(e<bestErr),bestErr=e;bestIdx=i;endif;endif;endfor
  if(bestErr>0.65),bestIdx=[];endif
endfunction

function [bits,markErr,dataErr,nBits,bitEvents]=extract_pulse_distance(type,dur,idxHeader,P,numeric_fn)
  bits=[];markErrors=[];dataErrors=[];bitEvents=[];i=idxHeader+2;frameGap=max(8000,5*P.oneSpace);
  while(i<=numel(dur))
    if(!strcmp(type{i},'MARK')),break;endif;m=dur(i);markErrors(end+1)=abs(m-P.bitMark)/P.bitMark;if(i+1>numel(dur)||!strcmp(type{i+1},'SPACE')),break;endif
    sp=dur(i+1);if(sp>=frameGap),break;endif;e0=abs(sp-P.zeroSpace)/P.zeroSpace;e1=abs(sp-P.oneSpace)/P.oneSpace;if(min(e0,e1)>0.55),break;endif
    bits(end+1)=(e1<e0);bitEvents(end+1)=i;dataErrors(end+1)=min(e0,e1);i=i+2;
  endwhile
  nBits=numel(bits);if(isempty(markErrors)),markErr=1;else markErr=ir_median(numeric_fn,markErrors);endif;if(isempty(dataErrors)),dataErr=1;else dataErr=ir_median(numeric_fn,dataErrors);endif
endfunction

function D=timing_diagnostics(E,P,R)
  D=struct('event_index',{},'event_type',{},'label',{},'measured_us',{},'expected_us',{},'relative_error',{});n=0;
  if(isfinite(R.headerIndex))
    i=R.headerIndex;if(i>=1&&i+1<=numel(E.type)),n++;D(n)=diagrow(i,E.type{i},'HEADER MARK',E.duration_us(i),P.headerMark);n++;D(n)=diagrow(i+1,E.type{i+1},'HEADER SPACE',E.duration_us(i+1),P.headerSpace);endif
  endif
  if(strcmp(P.kind,'pulse_distance'))
    for b=1:numel(R.bitsDecoded),i=R.bitEventIndex(b);n++;D(n)=diagrow(i,'MARK',sprintf('bit %d MARK',b-1),E.duration_us(i),P.bitMark);if(i+1<=numel(E.type)),if(R.bitsDecoded(b)),exp=P.oneSpace;lab=sprintf('bit %d = 1',b-1);else exp=P.zeroSpace;lab=sprintf('bit %d = 0',b-1);endif;n++;D(n)=diagrow(i+1,'SPACE',lab,E.duration_us(i+1),exp);endif;endfor
  elseif(strcmp(P.kind,'pulse_width'))
    for b=1:numel(R.bitsDecoded),i=R.bitEventIndex(b);if(R.bitsDecoded(b)),exp=P.oneMark;lab=sprintf('bit %d = 1',b-1);else exp=P.zeroMark;lab=sprintf('bit %d = 0',b-1);endif;n++;D(n)=diagrow(i,'MARK',lab,E.duration_us(i),exp);if(i+1<=numel(E.type)),n++;D(n)=diagrow(i+1,'SPACE',sprintf('bit %d SPACE',b-1),E.duration_us(i+1),P.bitSpace);endif;endfor
  elseif(strncmp(P.kind,'biphase',7))
    for q=1:numel(R.biphaseEventIndex),i=R.biphaseEventIndex(q);n++;D(n)=diagrow(i,E.type{i},sprintf('%dx unit',R.biphaseMultiple(q)),E.duration_us(i),R.biphaseMultiple(q)*P.unit);endfor
  endif
endfunction

function d=diagrow(idx,type,label,meas,exp),d=struct('event_index',idx,'event_type',type,'label',label,'measured_us',meas,'expected_us',exp,'relative_error',abs(meas-exp)/exp);endfunction

function F=frame_diagnostics(E,P,R)
  start=1;if(isfinite(R.headerIndex)),start=R.headerIndex;endif;last=min(numel(E.type),start+100);labels=repmat({''},numel(E.type),1);
  if(isfinite(R.headerIndex)&&R.headerIndex+1<=numel(E.type)),labels{R.headerIndex}='HEADER';labels{R.headerIndex+1}='HEADER';endif
  for b=1:numel(R.bitsDecoded),i=R.bitEventIndex(b);if(strcmp(P.kind,'pulse_distance')),j=i+1;else j=i;endif;if(j<=numel(labels)),labels{j}=sprintf('%d',R.bitsDecoded(b));endif;endfor
  F=struct('start_index',start,'end_index',last,'type',{E.type(start:last)},'start_s',E.start_s(start:last),'end_s',E.end_s(start:last),'duration_us',E.duration_us(start:last),'label',{labels(start:last)});
endfunction

function write_candidates(path,R,order)
  fid=fopen(path,'w');if(fid<0),error('Cannot write %s',path);endif;unwind_protect
    fprintf(fid,'rank,id,name,kind,expected_carrier_khz,score,quality,carrier_error,header_error,data_error,mark_error,space_error,bitcount_error,timing_error,bits_decoded,detail\n');
    for q=1:numel(order),k=order(q);fprintf(fid,'%d,%s,%s,%s,%.12g,%.12g,%s,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%d,%s\n',q,R(k).id,csv_atom(R(k).name),R(k).kind,R(k).expectedCarrier,R(k).score,confidence_text(R(k).score),R(k).carrierErr,R(k).headerErr,R(k).dataErr,R(k).markErr,R(k).spaceErr,R(k).bitErr,R(k).timingErr,numel(R(k).bitsDecoded),csv_atom(R(k).detail));endfor
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction
function write_timing(path,D),fid=fopen(path,'w');if(fid<0),error('Cannot write %s',path);endif;unwind_protect;fprintf(fid,'event_index,event_type,label,measured_us,expected_us,relative_error\n');for k=1:numel(D),fprintf(fid,'%d,%s,%s,%.12g,%.12g,%.12g\n',D(k).event_index,D(k).event_type,csv_atom(D(k).label),D(k).measured_us,D(k).expected_us,D(k).relative_error);endfor;unwind_protect_cleanup,fclose(fid);end_unwind_protect;endfunction
function write_frame(path,F),fid=fopen(path,'w');if(fid<0),error('Cannot write %s',path);endif;unwind_protect;fprintf(fid,'event_index,type,start_s,end_s,duration_us,label\n');for q=1:numel(F.type),idx=F.start_index+q-1;fprintf(fid,'%d,%s,%.12g,%.12g,%.12g,%s\n',idx,F.type{q},F.start_s(q),F.end_s(q),F.duration_us(q),csv_atom(F.label{q}));endfor;unwind_protect_cleanup,fclose(fid);end_unwind_protect;endfunction

function write_report(path,cfg,manifest_path,events_path,carrier,protocols,R,order,best,runner,margin,status,accepted,quality,acceptScore,minMargin)
  fid=fopen(path,'w');if(fid<0),error('Cannot write %s',path);endif;unwind_protect
    fprintf(fid,'GX-TXT IR protocol identification\nModule: gxtxt.ir_identify v2.0.2\nSource waveform manifest: %s\nSource events: %s\nMeasured carrier: %.6f kHz\n\n',manifest_path,events_path,carrier);
    fprintf(fid,'CANDIDATE RANKING\n');for q=1:numel(order),k=order(q);fprintf(fid,'%d) %-24s score=%8.4f quality=%s\n   %s\n',q,R(k).name,R(k).score,confidence_text(R(k).score),R(k).detail);endfor
    fprintf(fid,'\nRESULT\nStatus: %s\nBest candidate: %s\nScore: %.6f\nMatch quality: %s\nExpected carrier (best candidate): %.6f kHz\nMeasured/expected carrier deviation: %+.3f %%\n',status,R(best).name,R(best).score,quality,R(best).expectedCarrier,100*(carrier-R(best).expectedCarrier)/R(best).expectedCarrier);if(!isempty(runner)),fprintf(fid,'Runner-up: %s\nScore margin: %.6f\n',R(runner).name,margin);endif
    fprintf(fid,'Acceptance score threshold: %.6f\nMinimum score margin: %.6f\n',acceptScore,minMargin);
    if(accepted),fprintf(fid,'Identification accepted: yes\n');else fprintf(fid,'Identification accepted: no\n');endif
    fprintf(fid,'\nSCORE COMPONENTS (best candidate)\ncarrier=%.6f\nheader=%.6f\ndata=%.6f\nmark=%.6f\nspace=%.6f\nbitcount=%.6f\nbiphase_timing=%.6f\n',R(best).carrierErr,R(best).headerErr,R(best).dataErr,R(best).markErr,R(best).spaceErr,R(best).bitErr,R(best).timingErr);
    if(!isempty(R(best).bitsDecoded)),bits=R(best).bitsDecoded;fprintf(fid,'\nDECODE\nBits: %d\nTX order: %s\n',numel(bits),bits_string(bits));if(R(best).lsbFirst&&mod(numel(bits),8)==0),bytes=bits_to_bytes_lsb(bits);fprintf(fid,'Bytes LSB-first: %s\n',bytes_hex(bytes));if(strcmp(R(best).id,'nec')&&numel(bytes)==4),write_nec(fid,bytes);endif;endif;endif
    fprintf(fid,'\nNOTE\nIdentification is based on measured carrier and MARK/SPACE timing. Similar protocol variants may require payload, repeat-frame or long-press behaviour for unambiguous identification.\n');
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction

function E=read_events(path),fid=fopen(path,'r');if(fid<0),error('Cannot open %s',path);endif;header=fgetl(fid);C=textscan(fid,'%f%s%f%f%f%f','Delimiter',',','CollectOutput',false);fclose(fid);if(numel(C)<6||isempty(C{1})),error('gxtxt.ir_identify: unrecognized events CSV');endif;valid=isfinite(C{5});E=struct('index',C{1}(valid),'type',{C{2}(valid)},'start_s',C{3}(valid),'end_s',C{4}(valid),'duration_us',C{5}(valid),'carrier_cycles',C{6}(valid));endfunction

function path=find_waveform_manifest(session,dataset_id,signal_name,outdir)
  files=recursive_find(session,'ir_analysis_manifest.ini');best='';bestTime=-Inf;
  for k=1:numel(files),if(strncmp(files{k},outdir,numel(outdir))),continue;endif;try,M=read_ini(files{k});catch,continue;end_try_catch;if(!strcmp(strtrim(ini_get(M,'ir_analysis.dataset_id','')),dataset_id)),continue;endif;if(!strcmp(strtrim(ini_get(M,'ir_analysis.signal','')),signal_name)),continue;endif;d=dir(files{k});if(!isempty(d)&&d.datenum>bestTime),best=files{k};bestTime=d.datenum;endif;endfor
  if(isempty(best)),error('gxtxt.ir_identify: no gxtxt.ir_waveform v3.3 analysis manifest found for dataset %s / signal %s. Run gxtxt.ir_waveform first.',dataset_id,signal_name);endif;path=best;
endfunction
function out=recursive_find(root,name),out={};if(exist(root,'dir')!=7),return;endif;D=dir(root);for k=1:numel(D),n=D(k).name;if(strcmp(n,'.')||strcmp(n,'..')),continue;endif;p=fullfile(root,n);if(D(k).isdir),sub=recursive_find(p,name);out=[out sub];elseif(strcmp(n,name)),out{end+1}=p;endif;endfor;endfunction

function R=empty_result(P),R=struct('id',P.id,'name',P.name,'kind',P.kind,'expectedCarrier',P.carrier,'score',Inf,'detail','','bitsDecoded',[],'lsbFirst',false,'carrierErr',NaN,'headerErr',NaN,'dataErr',NaN,'markErr',NaN,'spaceErr',NaN,'bitErr',NaN,'timingErr',NaN,'headerIndex',NaN,'bitEventIndex',[],'biphaseEventIndex',[],'biphaseMultiple',[]);endfunction
function e=carrier_error(f,nom),if(!isfinite(f)),e=0.10;else e=abs(f-nom)/nom;endif;endfunction
function e=bitcount_error(n,expected),if(isempty(expected)),e=0;return;endif;e=Inf;for k=1:numel(expected),e=min(e,abs(n-expected(k))/expected(k));endfor;e=min(e,1);endfunction
function s=confidence_text(score),if(score<0.08),s='HIGH';elseif(score<0.16),s='GOOD';elseif(score<0.28),s='POSSIBLE';else s='LOW';endif;endfunction
function s=bits_string(bits),s=repmat('0',1,numel(bits));for k=1:numel(bits),if(bits(k)),s(k)='1';endif;endfor;endfunction
function bytes=bits_to_bytes_lsb(bits),n=numel(bits)/8;bytes=zeros(1,n);for b=1:n,idx=(b-1)*8+(1:8);val=0;for k=1:8,if(bits(idx(k))),val=val+2^(k-1);endif;endfor;bytes(b)=val;endfor;endfunction
function s=bytes_hex(bytes),parts=cell(1,numel(bytes));for k=1:numel(bytes),parts{k}=sprintf('0x%02X',bytes(k));endfor;s=strjoin(parts,' ');endfunction
function write_nec(fid,bytes),aInv=(bitxor(bytes(1),bytes(2))==255);cInv=(bitxor(bytes(3),bytes(4))==255);fprintf(fid,'NEC address complement: %s\n',yesno(aInv));fprintf(fid,'NEC command complement: %s\n',yesno(cInv));if(aInv&&cInv),fprintf(fid,'Interpretation: NEC standard strongly compatible\nAddress: 0x%02X\nCommand: 0x%02X\n',bytes(1),bytes(3));elseif(!aInv&&cInv),fprintf(fid,'Interpretation: NEC extended / NEC-family variant possible\nAddress 16 bit: 0x%04X\nCommand: 0x%02X\n',bytes(1)+256*bytes(2),bytes(3));else fprintf(fid,'Interpretation: NEC-family timing; payload is not standard NEC\n');endif;endfunction
function s=yesno(v),if(v),s='yes';else s='no';endif;endfunction
function n=num(s),n=str2double(strtrim(s));if(!isfinite(n)),n=NaN;endif;endfunction
function a=parse_num_list(s),s=strtrim(s);if(isempty(s)),a=[];return;endif;p=strsplit(s,';');a=[];for k=1:numel(p),v=str2double(p{k});if(isfinite(v)),a(end+1)=v;endif;endfor;endfunction
function s=csv_atom(s),s=strrep(s,'"','""');if(any(s==',')||any(s=='"')),s=['"' s '"'];endif;endfunction
function fn=discover_numeric_api(cfg)
  prefix='public_api.NUMERIC_API_v1.';
  provider=strtrim(ini_get(cfg,[prefix 'module_id'],''));version=strtrim(ini_get(cfg,[prefix 'api_version'],''));
  entry=strtrim(ini_get(cfg,[prefix 'octave_entrypoint'],''));fn=strtrim(ini_get(cfg,[prefix 'octave_function'],''));
  caps=parse_list(ini_get(cfg,[prefix 'capabilities'],''));
  if(!strcmp(provider,'math.numeric')||!strcmp(version,'1')||isempty(entry)||exist(entry,'file')!=2||isempty(fn))
    error('gxtxt.ir_identify: public NUMERIC_API_v1 runtime binding is unavailable');
  endif
  for required={'descriptive_statistics','linear_reductions'}
    if(!any(strcmp(caps,required{1}))),error('gxtxt.ir_identify: numeric capability missing: %s',required{1});endif
  endfor
  addpath(fileparts(entry));if(exist(fn,'file')!=2),error('gxtxt.ir_identify: numeric entrypoint is unavailable');endif
endfunction
function v=ir_median(fn,x),s=feval(fn,'statistics',double(x(:)),struct());v=s.median;endfunction
function v=ir_mean(fn,x),s=feval(fn,'reduce_summary',double(x(:)),struct());v=s.mean;endfunction
function v=arg_value(args,key,def),v=def;for k=1:numel(args)-1,if(strcmp(args{k},key)),v=args{k+1};return;endif;endfor;endfunction
function d=read_ini(path),d=struct();sec='';fid=fopen(path,'r');if(fid<0),error('Cannot open INI: %s',path);endif;unwind_protect;while(true),line=fgetl(fid);if(!ischar(line)),break;endif;line=strtrim(line);if(isempty(line)||line(1)==';'||line(1)=='#'),continue;endif;tok=regexp(line,'^\[(.+)\]$','tokens','once');if(!isempty(tok)),sec=tok{1};continue;endif;eq=find(line=='=',1);if(isempty(eq)),continue;endif;key=strtrim(line(1:eq-1));val=line(eq+1:end);d.(make_key([sec '.' key]))=val;endwhile;unwind_protect_cleanup;fclose(fid);end_unwind_protect;endfunction
function k=make_key(s),k=regexprep(s,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif;endfunction
function v=ini_get(d,key,def),k=make_key(key);if(isfield(d,k)),v=d.(k);else v=def;endif;endfunction
function v=get_num(d,key,def),v=str2double(ini_get(d,key,num2str(def,17)));if(!isfinite(v)),v=def;endif;endfunction
function b=parse_bool(s,def),s=lower(strtrim(s));if(any(strcmp(s,{'1','true','yes','on'}))),b=true;elseif(any(strcmp(s,{'0','false','no','off'}))),b=false;else b=def;endif;endfunction
function a=parse_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),a={};else a=strsplit(s,';');a=cellfun(@strtrim,a,'UniformOutput',false);endif;endfunction
