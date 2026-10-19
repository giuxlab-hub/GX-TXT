# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out
set out [file normalize $out]
if {![string match */_private_dev108/octave-arguments* $out] || [file exists $out]} {error {Requires a new private Octave arguments fixture}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __dev108_octave_arguments_contract__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $out Sessions]
::GX::createNewSession octave_arguments
::GX::modulePublicApiActivate analysis.octave_script OCTAVE_SCRIPT_EDITOR_API_v1
proc require {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
set arguments {alpha "two words"}
set source {ctx = gxtxt_context();
disp(ctx.arguments_raw);
}
set saved [::GX::OctaveScriptEditor::workspaceSave {} {} session argument_fixture Arguments {String-only regression} $source $arguments]
set read [::GX::OctaveScriptEditor::workspaceRead session:argument_fixture]
require {[dict get $read arguments] eq $arguments} {Default arguments lost on canonical reopen}
set changed [::GX::OctaveScriptEditor::workspaceSave session:argument_fixture [dict get $saved sha256] session argument_fixture Arguments {Updated description} $source $arguments]
require {[dict get $changed revision]==2} {Default arguments update did not retain Registry revision}
set copy [::GX::OctaveScriptEditor::workspaceSave {} {} session argument_copy Copy {} $source $arguments]
require {[dict get [::GX::OctaveScriptEditor::workspaceRead session:argument_copy] arguments] eq $arguments} {Save copy lost default arguments}
set denials {}
foreach bad [list "bad\nline" "bad\x00text" [string repeat a 4097]] {
    require {[catch {::GX::OctaveScriptEditor::workspaceSave session:argument_fixture [dict get $changed sha256] session argument_fixture Arguments {} $source $bad} reason]} {Invalid default arguments admitted}
    lappend denials $reason
}
set job [::GX::scriptJobSubmit session:argument_fixture {}]
set jobid [dict get $job id]
set terminal [::GX::scriptJobWait $jobid 60]
require {[dict get $terminal state] eq {COMPLETED}} "Octave argument Job failed: $terminal"
set log [::GX::scriptJobLogRead $jobid]
set run [::GX::scriptExecutionInspectRun $::GX::currentSession $jobid]
# Existing Script Bridge exposes inert arguments_raw, not the Octave process
# argv used by its trusted runner. No new parser/process argument path exists.
require {[string first $arguments [dict get $log content]]>=0} {Actual public context does not contain exact default argument text}
set runtime [::GX::parseIni [dict get $terminal runtime]]
require {[dict get $runtime config.arguments] eq $arguments} {Frozen runtime arguments provenance differs}
set record [dict create result PASS_REGISTRY_AND_STRING_JOB_ONLY arguments $arguments metadata $changed copy $copy job $terminal log $log inspection $run denials $denials]
set f [open [file join $out result.tcldict] w];puts $f $record;close $f
puts "PASS canonical argument persistence and actual public context string Job $jobid"
