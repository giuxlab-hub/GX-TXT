lassign $argv framework output mode
set skipJob [expr {$mode eq {skip_job}}]
if {[file exists $output]} {error {New output required}}
file mkdir $output
set output [file normalize $output]
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_JOB_ROOT jobs GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE resource-files GXTXT_INSTALLATION_ROOT installation} {set ::env($key) [file join $output $dir]}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __p003_registry__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults
::GX::loadModuleCatalog
package require Tk
proc check {test label} {if {![uplevel 1 [list expr $test]]} {error "FAIL $label"};puts "PASS $label";flush stdout}
proc paramEqual {a b} {
    if {[lsort [dict keys $a]] ne [lsort [dict keys $b]]} {return 0}
    dict for {name descriptor} $a {
        if {[lsort [dict keys $descriptor]] ne [lsort [dict keys [dict get $b $name]]]} {return 0}
        dict for {key value} $descriptor {if {$value ne [dict get $b $name $key]} {return 0}}
    }
    return 1
}
proc pause {{ms 120}} {set end [expr {[clock milliseconds]+$ms}];while {[clock milliseconds]<$end} {update;after 10}}
proc click {w} {
    update
    check {[winfo ismapped $w]} "mapped native control $w"
    exec xdotool mousemove --sync [expr {[winfo rootx $w]+[winfo width $w]/2}] [expr {[winfo rooty $w]+[winfo height $w]/2}] click 1
    pause
}
proc typeInto {w value} {
    click $w
    exec xdotool key --clearmodifiers Home shift+End
    if {$value eq {}} {exec xdotool key BackSpace} else {exec xdotool type --clearmodifiers --delay 1 -- $value}
    pause
}
proc selectRow {tree id} {
    $tree see $id;update
    lassign [$tree bbox $id #0] x y width height
    exec xdotool mousemove --sync [expr {[winfo rootx $tree]+$x+min(35,$width/2)}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1
    pause
    check {[$tree selection] eq $id} "native Library row $id"
}
proc waitStatus {pattern} {
    set end [expr {[clock seconds]+35}]
    while {[clock seconds]<$end} {
        pause 100
        if {[string match $pattern $::GX::scriptRunUi(status)]} {return}
    }
    error "Runner status timeout: $::GX::scriptRunUi(status)"
}
proc body {} {
    set output $::output
    set ::GX::cfg(output_root) [file join $output sessions]
    set session [::GX::createNewSession {Registry A}]
    set params [dict create dataset_prefix [dict create type string required 1 default {} description {Base name for four temperature Datasets}] count [dict create type integer required 1 default 4 min 1 max 8 description {Number of temperatures}] model [dict create type choice required 0 default linear values {linear quadratic} description {Fit model}]]
    set code {% Registered regression, variables are not parameters.
ctx = gxtxt_context();
arbitrary_local = 5;
assert(strcmp(ctx.parameters.dataset_prefix, 'temp'));
assert(ctx.parameters.count == 3);
assert(strcmp(ctx.parameters.model, 'linear'));
disp('P003_TYPED_OCTAVE_CONTEXT_PASS');
}
    set m [::GX::scriptRegistrySave session thermal {Four temperatures} $code [dict create language Octave version 2.3.4 parameters $params required_apis SCRIPT_EXECUTION_API_v1]]
    set params [dict get $m parameters]
    check {[paramEqual [dict get [::GX::scriptRegistryDescribe session:thermal] parameters] $params]} {registry structured typed round trip}
    wm geometry . 760x140
    ttk::frame .selector
    pack .selector -fill x
    ::GX::scriptAnalysisSelectorWidget .selector analysis.octave_script registered_script 0
    update
    check {[.selector.w0.choice cget -values] eq {session:thermal}} {Analysis lists active Session Octave script}
    click .selector.w0.library
    selectRow .gxtxtScriptLibrary.body.left.tree session:thermal
    update
    check {[string first {dataset_prefix | string | 1 |} [.gxtxtScriptLibrary.body.right.parameters get 1.0 end-1c]] >= 0} {Library displays required typed Octave parameter}
    click .gxtxtScriptLibrary.body.right.buttons.save
    set after [::GX::scriptRegistryDescribe session:thermal]
    check {[paramEqual [dict get $after parameters] $params]} {Library preserves supported descriptor validation keys}
    check {[dict get $after version] eq {2.3.4}} {Library preserves version}
    click .gxtxtScriptLibrary.body.right.buttons.close
    click .selector.w0.library
    selectRow .gxtxtScriptLibrary.body.left.tree session:thermal
    check {[string first {dataset_prefix | string | 1 |} [.gxtxtScriptLibrary.body.right.parameters get 1.0 end-1c]] >= 0} {Library reopen retains parameter presentation}
    click .gxtxtScriptLibrary.body.right.buttons.run
    update
    check {[winfo exists .gxtxtScriptRun.e_dataset_prefix] && [winfo exists .gxtxtScriptRun.e_count]} {Runner presents typed parameter controls}
    check {[catch {::GX::scriptExecutionParameters $after [dict create count abc dataset_prefix temp]}] && [catch {::GX::scriptExecutionParameters $after [dict create count 99 dataset_prefix temp]}]} {Runner uses existing integer and bounds validation}
    check {[catch {::GX::scriptExecutionParameters $after [dict create count 3]}]} {Runner rejects missing required dataset prefix}
    check {[dict get [::GX::scriptExecutionParameters $after [dict create count 3 dataset_prefix temp]] count] == 3} {Runner accepts typed parameters}
    click .gxtxtScriptRun.run
    waitStatus {Submission failed:*}
    check {[string match {*dataset_prefix*missing*} $::GX::scriptRunUi(status)]} {native Runner rejects missing required parameter}
    typeInto .gxtxtScriptRun.e_dataset_prefix.entry temp
    typeInto .gxtxtScriptRun.e_count.entry abc
    click .gxtxtScriptRun.run
    waitStatus {Submission failed:*}
    check {[string match {*integer*} $::GX::scriptRunUi(status)]} {native Runner rejects invalid integer}
    typeInto .gxtxtScriptRun.e_count.entry 3
    exec import -window root [file join $output library_runner.png]
    if {!$::skipJob} {
    click .gxtxtScriptRun.run
    waitStatus {*: script-*}
    set jobs [::GX::scriptJobList]
    set jobId {}
    foreach job $jobs {if {[dict get $job reference] eq {session:thermal}} {set jobId [dict get $job id]}}
    check {$jobId ne {}} {native Runner submitted exact typed Octave Script identity}
    set end [expr {[clock seconds]+90}]
    while {[clock seconds]<$end} {
        set job [::GX::scriptJobDescribe $jobId]
        if {[dict get $job state] in {COMPLETED FAILED CANCELLED INTERRUPTED}} break
        pause 200
    }
    check {[dict get $job state] eq {COMPLETED}} "actual supervised GNU Octave completion: [dict get $job error]"
    check {[string first P003_TYPED_OCTAVE_CONTEXT_PASS [dict get [::GX::scriptJobLogRead $jobId] content]]>=0} {actual GNU Octave received typed parameters}
    exec import -window root [file join $output octave_completed.png]
    }
    if {[winfo exists .gxtxtScriptJobs]} {::GX::scriptJobsClose}
    click .gxtxtScriptRun.cancel
    click .gxtxtScriptLibrary.body.right.buttons.close
    click .selector.w0.library
    selectRow .gxtxtScriptLibrary.body.left.tree session:thermal
    click .gxtxtScriptLibrary.body.right.code
    exec xdotool key --clearmodifiers ctrl+End
    exec xdotool type --clearmodifiers --delay 1 -- {% UNSAVED_LIBRARY_DRAFT}
    pause
    set draft [.gxtxtScriptLibrary.body.right.code get 1.0 end-1c]
    set parameterDraft [.gxtxtScriptLibrary.body.right.parameters get 1.0 end-1c]
    set other [::GX::createNewSession {Registry B}]
    update
    check {[.selector.w0.choice cget -values] eq {}} {Analysis Session switching removes old scripts}
    check {[.gxtxtScriptLibrary.body.right.code get 1.0 end-1c] eq $draft && [.gxtxtScriptLibrary.body.right.parameters get 1.0 end-1c] eq $parameterDraft} {Session switch retains unsaved Library source and parameter draft}
    click .gxtxtScriptLibrary.body.right.buttons.save
    check {[string match {Save failed: Session changed*} $::GX::scriptLibraryUi(status)]} {stale Library Session save rejected clearly}
    click .gxtxtScriptLibrary.body.right.buttons.close
    ::GX::scriptRegistrySave session second {Second Session} {disp('second');} [dict create language Octave]
    update
    check {[.selector.w0.choice cget -values] eq {session:second}} {new registry registration refreshes selectors}
    click .selector.w0.choice
    exec xdotool key Home Return
    pause
    check {$::GX::moduleCfg(analysis.octave_script,registered_script) eq {session:second}} {native Analysis chooses exact session identity}
    set second [::GX::scriptRegistryDescribe session:second]
    ::GX::scriptRegistryUpdate session second [dict get $second sha256] [dict create version 1.2.3] {disp('second updated');}
    pause
    check {[string first {version 1.2.3} [.selector.w0.info cget -text]]>=0} {Registry update refreshes selected Analysis metadata}

    ::GX::openSessionPath $session
    update
    check {[.selector.w0.choice cget -values] eq {session:thermal}} {reopened Session restores exact Session identity}
    ::GX::scriptRegistryRemove session:thermal
    update
    check {[.selector.w0.choice cget -values] eq {}} {registry removal refreshes selector}
    set padded [dict get [::GX::scriptRegistryValidate [dict create id example scope user name Example parameters [dict create text [dict create type string required 0 default {  padded | C:\path\s  } description {a | description}]]]] parameters]
    check {[paramEqual [::GX::scriptParameterDefinitionsParse [::GX::scriptParameterDefinitionsFormat $padded] $padded] $padded]} {parameter text preserves padded defaults pipes and backslashes}
    check {[catch {::GX::scriptParameterDefinitionsParse "same | string\nsame | integer"}]} {duplicate parameter identities rejected}
    check {[file isdirectory $other]} {independent synthetic Session retained}
}
if {[catch {body} reason options]} {puts stderr "$reason\n[dict get $options -errorinfo]";exit 1}
puts {PASS focused P003 Registry/Library/Analysis/Runner regression}
destroy .
exit 0
