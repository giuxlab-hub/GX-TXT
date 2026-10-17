# SPDX-License-Identifier: GPL-3.0-or-later
# One managed Debug client for both established Script Workspace shells.
namespace eval ::GX::ScriptDebug {variable state}
proc ::GX::scriptDebugOpen {editor language} {
    variable ::GX::ScriptDebug::state
    set p $editor.p.debug
    if {[winfo exists $p]} {return $p}
    ttk::frame $p -padding 6;scriptWorkspaceAssistMount $editor $p
    set state($p,editor) $editor;set state($p,language) $language;set state($p,job) {};set state($p,timer) {};set state($p,token) [interactiveDocumentSessionToken]
    set state($p,status) {Save a Session script, set gutter breakpoints, then Start Debug. Closing this panel cancels its Debug Job.}
    ttk::label $p.title -text "$language Debug — native managed execution"
    ttk::frame $p.controls
    foreach {name label operation} {start {Start Debug} start into {Step Into} into over {Step Over} over out {Step Out} out continue Continue continue pause Pause pause stop Stop stop} {
        ttk::button $p.controls.$name -text $label -command [list ::GX::scriptDebugAction $p $operation]
        pack $p.controls.$name -side left -padx 2 -pady 2
    }
    bind $p.controls <Configure> {::GX::uiFieldControlsLayout %W %w}
    ttk::treeview $p.stack -columns {function line} -show headings -height 5
    foreach col {function line} {$p.stack heading $col -text [string totitle $col]}
    ttk::treeview $p.variables -columns {type shape value} -show {tree headings} -height 12
    $p.variables heading #0 -text Variable;$p.variables column #0 -width 120 -stretch 1
    foreach col {type shape value} {$p.variables heading $col -text [string totitle $col];$p.variables column $col -width 100 -stretch 1}
    ttk::scrollbar $p.scroll -command [list $p.variables yview];$p.variables configure -yscrollcommand [list $p.scroll set]
    ttk::label $p.status -textvariable ::GX::ScriptDebug::state($p,status) -wraplength 420
    ttk::button $p.close -text {Close debugger / cancel owned Debug Job} -command [list destroy $p]
    pack $p.title $p.controls $p.stack -fill x
    pack $p.scroll -side right -fill y;pack $p.variables -fill both -expand 1;pack $p.status $p.close -fill x
    bind $p.stack <<TreeviewSelect>> [list ::GX::scriptDebugFrame $p]
    bind $p <Destroy> [list ::GX::scriptDebugDestroyed $p %W]
    return $p
}
proc ::GX::scriptDebugEditor {p} {return ::GX::$::GX::ScriptDebug::state($p,language)ScriptEditorUI}
proc ::GX::scriptDebugAction {p operation} {
    variable ::GX::ScriptDebug::state
    if {[catch {
        set ns [scriptDebugEditor $p];upvar #0 ${ns}::ui ui
        if {$operation eq {stop}} {if {$state($p,job) ne {}} {scriptJobCancel $state($p,job)};return}
        if {$state($p,token) ne [interactiveDocumentSessionToken]} {error {Session changed; close the debugger to cancel its owned Job}}
        ${ns}::_recomputeDirty
        if {$ui(modified) || ![string match session:* $ui(currentId)]} {error {Save a clean registered Session script before Debug or stepping; the running snapshot cannot change}}
        if {$operation eq {start}} {
            if {$state($p,job) ne {}} {set old [scriptJobDescribe $state($p,job)];if {[dict get $old state] in {QUEUED PREPARING RUNNING FINALIZING}} {error {Stop the existing Debug Job first}}}
            set metadata [scriptRegistryDescribe $ui(currentId)]
            if {[dict get $metadata sha256] ne $ui(currentSha)} {error {Registered source changed; reload the editor}}
            set state($p,sha) $ui(currentSha);set state($p,source) $ui(text)
            set options [dict create session $::GX::currentSession debug_breakpoints [sourceSurfaceBreakpoints $ui(text)]]
            scriptJobDebugSubmit $ui(currentId) {} $options [list ::GX::scriptDebugSubmitted $p]
            set state($p,status) STARTING
        } else {
            if {$state($p,job) eq {}} {error {Start a Debug Job first}}
            scriptJobAsync [scriptJobCommand debug_control $state($p,job) $operation $state($p,sha)] {} [list ::GX::scriptDebugControlled $p]
        }
    } reason]} {set state($p,status) $reason}
}
proc ::GX::scriptDebugControlled {p response} {if {![winfo exists $p]} return;if {![dict get $response ok]} {set ::GX::ScriptDebug::state($p,status) [dict get $response error]}}
proc ::GX::scriptDebugSubmitted {p response} {
    if {![winfo exists $p]} {if {[dict get $response ok]} {catch {scriptJobCancel [dict get $response result id]}};return}
    if {![dict get $response ok]} {set ::GX::ScriptDebug::state($p,status) [dict get $response error];return}
    set ::GX::ScriptDebug::state($p,job) [dict get $response result id];scriptDebugPoll $p
}
proc ::GX::scriptDebugPoll {p} {
    if {![winfo exists $p]} return
    if {$::GX::ScriptDebug::state($p,token) ne [interactiveDocumentSessionToken]} {set ::GX::ScriptDebug::state($p,status) {Session changed. Cancelling the owned Debug Job.};catch {scriptJobCancel $::GX::ScriptDebug::state($p,job)};return}
    scriptJobAsync [scriptJobCommand debug_read $::GX::ScriptDebug::state($p,job)] {} [list ::GX::scriptDebugPolled $p] {timeout_ms 10000 max_bytes 2097152 ui_lifetime 1 label {Native debugger observation}}
}
proc ::GX::scriptDebugPolled {p response} {
    variable ::GX::ScriptDebug::state
    if {![winfo exists $p]} return
    if {![dict get $response ok]} {set state($p,status) [dict get $response error]
    } else {
        set debug [dict get $response result];set state($p,observation) $debug
        set status [dict get $debug state];set state($p,status) "$status — $state($p,job)"
        if {$status eq {PAUSED}} {
            sourceSurfaceLocation $state($p,source) [dict get $debug line]
            $p.stack delete [$p.stack children {}];set index 0
            foreach frame [dict get $debug stack] {
                set name [datasetPublicationV2DictDefault $frame function [datasetPublicationV2DictDefault $frame name {}]]
                $p.stack insert {} end -id frame$index -values [list $name [dict get $frame line]];incr index
            }
            set selected [datasetPublicationV2DictDefault $debug selected_frame 0]
            if {[$p.stack exists frame$selected]} {$p.stack selection set frame$selected}
            $p.variables delete [$p.variables children {}]
            foreach scope {locals globals} {
                if {![dict exists $debug $scope]} continue
                dict for {name value} [dict get $debug $scope] {$p.variables insert {} end -text "$scope.$name" -values [list [dict get $value type] [dict get $value shape] [string range [dict get $value value] 0 1023]]}
            }
        } else {sourceSurfaceLocation $state($p,source) 0}
        if {$status in {COMPLETED FAILED CANCELLED INTERRUPTED}} {return}
    }
    set state($p,timer) [after 350 [list ::GX::scriptDebugPoll $p]]
}
proc ::GX::scriptDebugFrame {p} {
    set row [lindex [$p.stack selection] 0]
    if {![regexp {^frame([0-9]+)$} $row -> index]} return
    if {[info exists ::GX::ScriptDebug::state($p,observation)] && [dict exists $::GX::ScriptDebug::state($p,observation) selected_frame] && [dict get $::GX::ScriptDebug::state($p,observation) selected_frame]==$index} return
    set ns [scriptDebugEditor $p]
    scriptJobAsync [scriptJobCommand debug_control $::GX::ScriptDebug::state($p,job) frame $::GX::ScriptDebug::state($p,sha) $index] {} [list ::GX::scriptDebugControlled $p]
}
proc ::GX::scriptDebugDestroyed {p actual} {
    if {$actual ne $p} return
    variable ::GX::ScriptDebug::state
    if {[info exists state($p,timer)] && $state($p,timer) ne {}} {after cancel $state($p,timer)}
    if {[info exists state($p,job)] && $state($p,job) ne {}} {catch {set job [scriptJobDescribe $state($p,job)];if {[dict get $job state] in {QUEUED PREPARING RUNNING FINALIZING}} {scriptJobCancel $state($p,job)}}}
    if {[info exists state($p,source)] && [winfo exists $state($p,source)]} {sourceSurfaceLocation $state($p,source) 0}
    array unset state $p,*
}
