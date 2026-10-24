lassign $argv framework output
if {[file exists $output]} {error {New output required}}
file mkdir $output
set output [file normalize $output]
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_JOB_ROOT jobs GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE resource-files GXTXT_INSTALLATION_ROOT installation} {set ::env($key) [file join $output $dir]}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __p003_declarations__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults
::GX::loadModuleCatalog
proc check {e label} {if {![uplevel 1 [list expr $e]]} {error "FAIL $label"};puts "PASS $label"}
set ::GX::cfg(output_root) [file join $output sessions]
set code {% GX-TXT-ANALYSIS-SOURCES-V1: {"api_version":1,"sources":[{"id":"primary","label":"Measured source","required":true,"contracts":["table.generic"]}]}
disp('inert fixture');
}
set module analysis.octave_script
foreach letter {a b} {
    set session [::GX::createNewSession "Binding $letter"]
    dict set sessions $letter $session
    ::GX::datasetPublicationV2PublishSeries $session math.numeric [dict create dataset_id source_$letter contract table.generic storage csv x_values {0 1} y_values {2 3} x_variable {variable_id x name Time unit s} y_variable {variable_id y name Voltage unit V}]
    set m [::GX::scriptRegistrySave session shared {Shared identity} $code [dict create language Octave]]
    dict set hashes $letter [dict get $m sha256]
    set ::GX::moduleCfg($module,registered_script) session:shared
    set ::GX::moduleCfg($module,source_mode) registered_script
    ::GX::scriptAnalysisApplyDeclarations $module
    check {$::GX::scriptSourceDeclarationError($module) eq {}} "Session $letter valid static declaration"
    set ::GX::moduleAnalysisSource($module,1,dataset_id) source_$letter
    ::GX::writeManifest [file join $session metadata manifest.ini]
}
check {[dict get $hashes a] eq [dict get $hashes b]} {two Sessions genuinely own identical script ID and source SHA}
foreach letter {a b a} {
    ::GX::openSessionPath [dict get $sessions $letter]
    ::GX::scriptAnalysisApplyDeclarations $module
    check {$::GX::moduleCfg($module,registered_script) eq {session:shared}} "Session $letter restores exact qualified script identity"
    check {$::GX::moduleAnalysisSource($module,1,id) eq {primary} && $::GX::moduleAnalysisSource($module,1,dataset_id) eq "source_$letter"} "Session $letter restores its own persisted Analysis binding"
}
set ::GX::moduleCfg($module,registered_script) session:missing
::GX::scriptAnalysisApplyDeclarations $module
check {[::GX::scriptAnalysisDeclarationRows $module] eq {}} {missing script clears previous declarations}
check {$::GX::scriptSourceDeclarationError($module) ne {}} {missing script retains actionable validation failure}
set meta [::GX::scriptRegistrySave session apis {API metadata} {gxtxt_api_require('DATASET_API_v1');} [dict create language Octave required_apis SCRIPT_EXECUTION_API_v1]]
check {[dict get $meta explicit_apis] eq {SCRIPT_EXECUTION_API_v1} && [dict get $meta declared_apis] eq {DATASET_API_v1}} {Registry stores manual and declared API requirements separately}
set copy [::GX::scriptRegistrySave session apis_copy {Full metadata copy} {gxtxt_api_require('DATASET_API_v1');} $meta]
check {[dict get $copy explicit_apis] eq {SCRIPT_EXECUTION_API_v1}} {full metadata Save preserves manual API set}
set changed [::GX::scriptRegistryUpdate session apis [dict get $meta sha256] $meta {disp('declaration removed');}]
check {[dict get $changed explicit_apis] eq {SCRIPT_EXECUTION_API_v1} && [dict get $changed declared_apis] eq {} && [dict get $changed required_apis] eq {SCRIPT_EXECUTION_API_v1}} {full metadata source Update removes obsolete automatic API without promoting it}
puts {PASS P003 saved-manifest Analysis binding regression}
exit 0
