function q=uvvis_shell_quote(value)
% Shell-quote one local bridge argument without changing its bytes.
% Intentionally unbound utility. The current runner uses gxtxt_shell_quote_v1;
% retain this entry point pending review of programmatic compatibility.
  q=['''' strrep(value,'''','''"''"''') ''''];
endfunction
