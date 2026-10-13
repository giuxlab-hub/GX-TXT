function out=gxtxt_publication_v2_encode(x)
 if(isempty(x)),out='';return;endif
 if(isnumeric(x)||islogical(x)),x=num2str(x,17);endif
 out=char(matlab.net.base64encode(uint8(char(x)))); out=out(:)';
endfunction
