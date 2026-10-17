lassign $argv root out mode
set root [file normalize $root];set out [file normalize $out]
if {[file exists $out]} {error {Evidence destination already exists}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __official_dev099_projects__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $out sessions]
set checks {}
proc save {name value} {set f [open [file join $::out $name.tcldict] w];puts $f $value;close $f}
proc check {expression label} {if {![uplevel 1 [list expr $expression]]} {error "FAIL $label"};lappend ::checks $label;puts "PASS $label";flush stdout;save checks $::checks}
proc pause {{ms 100}} {set ::paused 0;after $ms {set ::paused 1};vwait ::paused;update idletasks}
proc sha {p} {lindex [exec sha256sum $p] 0}
proc rd {p} {set f [open $p rb];try {read $f} finally {close $f}}
proc snapshot {name} {raise .;update;pause;exec import -window [winfo id .] [file join $::out $name.png]}
proc seed {} {
 set ::GX::cfg(output_root) [file join $::out sessions]
 set ::a [::GX::projectCreate {Source Project}];set ::b [::GX::projectCreate {Target Project}]
 set ::sessionA [::GX::createNewSession {Active experiment} $::a];set ::eidA $::GX::cfg(experiment_id)
 ::GX::datasetPublicationV2PublishSeries $::sessionA math.numeric [dict create dataset_id scientific099 contract table.generic storage csv x_values {-1 0 2} y_values {2 4 8} x_variable {variable_id time_original unit s} y_variable {variable_id response_original unit V}]
 set ::scientific [dict get [::GX::sessionInspectionDatasetPayload scientific099 $::sessionA] path]
 set ::scientificSha [sha $::scientific]
 set ::sessionB [::GX::createNewSession {Unopened selected experiment} $::a];set ::eidB $::GX::cfg(experiment_id)
 ::GX::openSessionPath $::sessionA
 set ::originalA [rd [file join $::sessionA metadata manifest.ini]]
 ::GX::projectGuiRefresh
 .top.nb select .top.nb.projects
 set t .top.nb.projects.body.left.tree;$t selection set $::a;::GX::projectGuiShowSelected;pause
}
proc selectProject {id} {set t .top.nb.projects.body.left.tree;$t selection set $id;$t focus $id;event generate $t <<TreeviewSelect>>;pause}
proc createProject {name} {
 .top.nb.projects.toolbar.new invoke;pause
 .gxProjectEditor.name delete 0 end;.gxProjectEditor.name insert 0 $name
 .gxProjectEditor.buttons.ok invoke;pause
 foreach id [::GX::projectIds] {if {[::GX::projectField $id name] eq $name} {return $id}}
 error {Created Project not found}
}
proc bgerror {message} {set ::bgfailed "$message\n$::errorInfo";puts stderr $::bgfailed}
