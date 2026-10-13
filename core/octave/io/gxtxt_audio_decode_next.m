function [A,C]=gxtxt_audio_decode_next(A)
 if(A.closed),error('GXTXT:AudioDecode','Decode handle is closed');endif;fputs(A.bridge_in,"NEXT\n");fflush(A.bridge_in);p=gxtxt_table_stream_v3_parts(gxtxt_persistent_bridge_readline(A.bridge_out,A.bridge_pid,'Audio Decode'));
 if(strcmp(p{1},'ERROR')),error('GXTXT:AudioDecode','%s',gxtxt_table_stream_v3_decode(p{2}));endif
 n=str2double(p{2});ch=str2double(p{3});eof=logical(str2double(p{4}));bytes=uint8(matlab.net.base64decode(p{5}));
 if(strcmp(A.sample_format,'float32')),v=typecast(bytes,'single');elseif(strcmp(A.sample_format,'int16')),v=typecast(bytes,'int16');else v=typecast(bytes,'int32');endif
 if(n),v=reshape(v,ch,n)';else v=zeros(0,ch,class(v));endif;C=struct('frames',n,'channels',ch,'values',v,'eof',eof,'interleaved_transport',true);A.eof=eof;
endfunction
