# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework output
if {[file exists $output]} {error {Use a new private output}}
file mkdir $output
namespace eval ::GX {}
namespace eval ::GX::NativeCadSketch {}
namespace eval ::GX::ViewerGui {variable instances {}}
oo::class create ::GX::NativeCadSketch::Component {}
source [file join $framework core tcl native2d_cad_presentation_v1.tcl]
source [file join $framework core tcl viewer_gui_cad_sketch_v1.tcl]
set batch [expr {[llength [info commands ::GX::native2DCadActionStates]]>0}]
set counters {};set cursor 1;set count 2;set alive 1;set construction {};set geometry 0;set domain {}
proc hit {name} {dict incr ::counters $name}
proc check {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message};puts "PASS $message"}
proc winfo {op widget} {return 1}
proc ::GX::datasetPublicationV2DictDefault {record key fallback} {if {[dict exists $record $key]} {return [dict get $record $key]};return $fallback}
proc ::GX::scientificHistoryViewerStatus {context} {hit history;if {[info exists ::failHistory] && $::failHistory} {error fixture-history-unavailable};return [dict create cursor $::cursor count $::count]}
proc ::GX::scientificHistoryViewerNavigate {context direction} {if {$direction eq {undo}} {incr ::cursor -1} else {incr ::cursor}}
oo::class create Advanced {
    method state {} {hit advanced;return [dict create construction $::construction]}
    method cancel {reason} {set ::construction {}}
}
set advanced [Advanced new]
oo::class create Context {
    method selection {op} {hit selection;return [dict create objects {42} references {{object 42 entity control index 0}}]}
    method object {op id} {hit definition;return {family path controls {{0 0} {1 0} {2 1}}}}
}
set context [Context new]
oo::class create Host {
    variable tool
    constructor {} {set tool select}
    method advanced {} {return $::advanced}
    method context {} {return $::context}
    method tool {{value {}}} {if {$value ne {}} {set tool $value;if {$value eq {select}} {$::advanced cancel tool_change}};return $tool}
    method cancel {reason} {$::advanced cancel $reason}
    method refresh {kind} {}
    method event {kind value} {
        if {$value eq {Return} && $::construction ne {} && [dict get $::construction places] ne {}} {
            if {[llength [dict get $::construction places]]<2} {error {Place the remaining defining controls first}}
            incr ::geometry;incr ::cursor;set ::count $::cursor
            dict set ::construction places {}
        }
    }
}
set host [Host new]
oo::class create Sketch {
    superclass ::GX::NativeCadSketch::Component
    method guard {} {hit guard;if {!$::alive} {error closed};return 1}
    method get {key} {switch $key {host {return $::host} history_context {return fixture-history} document_id {return fixture-document}}}
    method actionState {action} {return [::GX::native2DCadActionState [self] $action]}
    method changed {message} {hit changed}
}
set sketch [Sketch new]
proc predicates {window} {
    dict for {id descriptor} [::GX::native2DCadActions] {
        foreach key {enabled checked} {::GX::native2DCadActionPredicate $::sketch $id $key}
    }
}
foreach command {viewerCommandToolbarStatesRefresh viewerCommandMenusRefresh viewerCommandWidgetsRefresh} {proc ::GX::$command {window} {predicates $window}}
proc ::GX::viewerGuiDesignGuard {window} {return 1}
proc ::GX::viewerGuiDesignComponent {window component} {return {type cad_sketch}}
proc ::GX::viewerGuiDesignContextGet {window} {return $::domain}
proc ::GX::viewerGuiDesignContextSet {window value} {set ::domain $value}
proc ::GX::viewerGuiActionsRefresh {window} {
    dict for {component sketch} [dict get $::GX::ViewerGui::instances $window cad_sketches] {
        dict for {id descriptor} [native2DCadActions] {
            foreach key {enabled checked} {_viewerGuiCadBindingState $window [list $component $id] $key}
        }
    }
}
dict set ::GX::ViewerGui::instances viewer cad_sketches sketch $sketch
set ::GX::NativeCadSketch::mounts [dict create panel1 $sketch panel2 $sketch panel3 $sketch panel4 $sketch]
set start [clock microseconds]
if {$batch} {
    ::GX::native2DCadPresentationRefresh $sketch [list ::GX::_viewerGuiCadSketchChanged viewer sketch {document_id fixture-document}]
} else {
    ::GX::native2DCadPresentationRefresh $sketch
    ::GX::_viewerGuiCadSketchChanged viewer sketch {document_id fixture-document}
}
set elapsed [expr {[clock microseconds]-$start}]
set refreshCounters $counters
if {$batch} {
    foreach key {guard advanced selection definition history} {check {[dict get $counters $key]==1} "One $key query serves every presentation predicate"}
    check {$::GX::NativeCadSketch::actionScopes eq {}} {Presentation scope releases all references}
    check {[dict get $domain cad_sketches sketch document_id] eq {fixture-document}} {Authored Workspace reference remains intact}
    set cursor 0
    check {![dict get [::GX::native2DCadActionState $sketch undo] enabled]} {Later calls observe changed History state}
    proc fail {} {::GX::native2DCadActionState $::sketch line;error expected}
    catch {::GX::_native2DCadWithActionStates $sketch fail}
    check {$::GX::NativeCadSketch::actionScopes eq {}} {Callback failure does not retain snapshots}
    set failHistory 1
    check {[catch {::GX::_native2DCadWithActionStates $sketch [list ::GX::native2DCadActionState $sketch line]}]} {Collection errors remain visible}
    check {$::GX::NativeCadSketch::actionScopes eq {}} {Collection failure does not retain snapshots}
    set failHistory 0
    set alive 0
    set states [::GX::native2DCadActionStates $sketch]
    dict for {id state} $states {check {![dict get $state enabled]} "Stale source disables $id"}
    set alive 1;set cursor 1;set count 2
    set construction {family line places {}}
    ::GX::native2DCadActionInvoke $sketch finish
    check {$construction eq {} && [$host tool] eq {select} && $geometry==0 && $cursor==1} {Finish exits an auto-committed tool without geometry or History changes}
    set construction {family path places {{0 0} {1 0} {2 1}}}
    ::GX::native2DCadActionInvoke $sketch finish
    check {$construction eq {} && $geometry==1 && $cursor==2} {Finish commits a valid variable-length proposal and leaves its tool}
    set construction {family line places {{0 0}}};set before $construction
    check {[catch {::GX::native2DCadActionInvoke $sketch finish}] && $construction eq $before && $geometry==1 && $cursor==2} {Incomplete Finish preserves its native proposal and committed state}
    ::GX::native2DCadActionInvoke $sketch cancel
    check {$construction eq {}} {Cancellation remains available after rejected Finish}
    proc mutateInsideScope {} {
        set prior [::GX::native2DCadActionState $::sketch undo]
        ::GX::native2DCadActionInvoke $::sketch undo
        return [list [dict get $prior enabled] [dict get [::GX::native2DCadActionState $::sketch redo] enabled]]
    }
    set cursor 2;set count 2
    check {[::GX::_native2DCadWithActionStates $sketch mutateInsideScope] eq {1 1} && $cursor==1} {Action execution revalidates and invalidates an enclosing presentation snapshot}
    check {$::GX::NativeCadSketch::actionScopes eq {}} {Mutation scope releases all references}
    set second [Sketch new]
    dict set ::GX::ViewerGui::instances viewer cad_sketches second $second
    set counters {}
    ::GX::_viewerGuiCadSketchChanged viewer sketch {document_id fixture-document}
    check {[dict get $counters guard]==2 && [dict get $counters history]==2} {Independent Sketches each receive one authored-state snapshot}
    check {$::GX::NativeCadSketch::actionScopes eq {}} {Multiple Sketch refresh releases all references}
    $second destroy
}
set receipt [dict create scope contract_only gui_acceptance 0 batching $batch elapsed_us $elapsed refresh_counters $refreshCounters]
set f [open [file join $output result.tcldict] w];puts $f $receipt;close $f
puts $receipt
