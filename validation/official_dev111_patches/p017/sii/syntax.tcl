foreach path $argv {set f [open $path];set text [read $f];close $f;if {![info complete $text]} {error "Incomplete Tcl: $path"};puts "COMPLETE $path"}
