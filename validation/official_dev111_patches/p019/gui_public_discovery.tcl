lassign $argv framework output
if {[file exists $output]} {error {Fresh output required}}
file mkdir $output;set output [file normalize $output];file attributes $output -permissions 0700
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1;set argv0 __p019_public_discovery__
source [file join $framework gxtxt_pipeline.tcl];::GX::defaults
set info [::GX::native2DCadApiInfo]
foreach family {construction topology constraint dimension control direction} {if {$family ni [dict get $info host_tool_families]} {error "Missing public host family $family"}}
foreach command {native2DCadConstructionCount native2DCadDimensionKinds} {if {$command ni [dict get $info host_commands] || ![llength [info commands ::GX::$command]]} {error "Missing advertised public command $command"}}
if {[::GX::native2DCadConstructionCount cubic_bezier]!=4 || {radius} ni [::GX::native2DCadDimensionKinds]} {error {Public operation discovery does not match callable behavior}}
set f [open [file join $output receipt.tcldict] w];puts $f [dict create info $info cubic_count [::GX::native2DCadConstructionCount cubic_bezier] dimension_kinds [::GX::native2DCadDimensionKinds] status PASS];close $f
puts {PASS: exact final-source public CORE CAD discovery and commands.}
