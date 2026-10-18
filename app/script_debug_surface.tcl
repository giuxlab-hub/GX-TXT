# SPDX-License-Identifier: GPL-3.0-or-later
# One managed Debug client for both established Script Workspace shells.
namespace eval ::GX::ScriptDebug {variable state}
proc ::GX::scriptDebugOpen {editor language} {
    variable ::GX::ScriptDebug::state
    set p $editor.p.debug
    if {[winfo exists $p]} {scriptWorkspaceAssistMount $editor $p;return $p}
    ttk::frame $p -padding 5
    set state($p,editor) $editor;set state($p,language) $language
    if {[catch {scriptJobDebugCapabilities $language} capabilities]} {set capabilities [dict create controls {} pause_supported 0 pause_reason $capabilities]}
    set state($p,capabilities) $capabilities
    set state($p,job) {};set state($p,timer) {};set state($p,uiTimer) {}
    set state($p,contextChanged) 0
    set state($p,token) [scriptWorkspaceSessionToken];set state($p,phase) IDLE
    set state($p,status) {IDLE — save a Session script to debug its immutable snapshot.}
    ttk::frame $p.controls
    foreach {name label operation glyph} {
        start {Start Debug} start start continue Continue continue continue pause Pause pause pause stop Stop stop stop
        into {Step Into} into into over {Step Over} over over out {Step Out} out out
        breakpoint Breakpoint breakpoint breakpoint clear {Clear all} clear clear
    } {
        ttk::button $p.controls.$name -text $label -compound left -image [native2DViewportGlyph debug_$glyph 18] -command [list ::GX::scriptDebugAction $p $operation]
        set state($p,label,$name) $label
        set tip $label
        if {$name eq {pause} && ![dict get $capabilities pause_supported]} {set tip [dict get $capabilities pause_reason]}
        native2DViewportTooltip $p.controls.$name $tip
        bind $p.controls.$name <FocusIn> +[list ::GX::native2DViewportTooltipShow $p.controls.$name $tip]
        bind $p.controls.$name <FocusOut> +[list catch {destroy .gxViewportTip}]
        pack $p.controls.$name -side left -padx 2 -pady 2
    }
    bind $p.controls <Configure> [list ::GX::scriptDebugToolbarLayout $p %w]
    ttk::notebook $p.book
    ttk::frame $p.book.live
    ttk::label $p.book.live.empty -text {Call Stack and Variables are hidden. Restore them from View.} -wraplength 300
    ttk::panedwindow $p.book.live.p -orient horizontal
    pack $p.book.live.p -fill both -expand 1
    foreach {key title weight} {stack {Call Stack} 2 variables {Locals / Globals} 3} {
        set f $p.book.live.p.$key
        ttk::frame $f
        ttk::label $f.title -text $title -anchor w
        grid $f.title -row 0 -column 0 -columnspan 2 -sticky ew
        set state($p,$key) $f.tree
        $p.book.live.p add $f -weight $weight
        grid rowconfigure $f 1 -weight 1;grid columnconfigure $f 0 -weight 1
        ttk::scrollbar $f.v -command [list $f.tree yview]
        ttk::scrollbar $f.h -orient horizontal -command [list $f.tree xview]
        grid $f.v -row 1 -column 1 -sticky ns;grid $f.h -row 2 -column 0 -sticky ew
    }
    set stack $state($p,stack);set variables $state($p,variables)
    ttk::treeview $stack -columns {function file line} -show headings -height 3 -selectmode browse
    foreach {col title width} {function Function 80 file File 100 line Line 45} {$stack heading $col -text $title;$stack column $col -width $width -minwidth 35 -stretch [expr {$col ne {line}}]}
    ttk::treeview $variables -columns {type shape value} -show {tree headings} -height 3
    $variables heading #0 -text Variable;$variables column #0 -width 110 -minwidth 55
    foreach {col width} {type 70 shape 60 value 170} {$variables heading $col -text [string totitle $col];$variables column $col -width $width -minwidth 40}
    foreach key {stack variables} {
        set f $p.book.live.p.$key;set tree $state($p,$key)
        $tree configure -yscrollcommand [list $f.v set] -xscrollcommand [list $f.h set]
        grid $tree -row 1 -column 0 -sticky nsew
    }
    ttk::frame $p.book.breakpoints
    set b $p.book.breakpoints.tree;set state($p,breakpoints) $b
    ttk::treeview $b -columns {line enabled function file source revision} -show headings -height 3 -selectmode browse
    foreach {col label width} {line Line 50 enabled Enabled 60 function Function 100 file File 110 source {Registered source} 180 revision {SHA-256 revision} 190} {$b heading $col -text $label;$b column $col -width $width -minwidth 40}
    ttk::scrollbar $p.book.breakpoints.scroll -orient horizontal -command [list $b xview]
    $b configure -xscrollcommand [list $p.book.breakpoints.scroll set]
    ttk::frame $p.book.breakpoints.actions
    foreach {op label} {navigate {Go to source} enable Enable disable Disable remove Remove clear {Clear all}} {ttk::button $p.book.breakpoints.actions.$op -text $label -command [list ::GX::scriptDebugBreakpoint $p $op];pack $p.book.breakpoints.actions.$op -side left -padx 3}
    pack $p.book.breakpoints.actions -side bottom -fill x
    pack $p.book.breakpoints.scroll -side bottom -fill x;pack $b -fill both -expand 1
    ttk::frame $p.book.output
    set state($p,output) $p.book.output.text
    text $p.book.output.text -height 4 -wrap word -state disabled -font TkFixedFont -exportselection 0
    ttk::scrollbar $p.book.output.scroll -command [list $p.book.output.text yview]
    $p.book.output.text configure -yscrollcommand [list $p.book.output.scroll set]
    pack $p.book.output.scroll -side right -fill y;pack $p.book.output.text -fill both -expand 1
    $p.book add $p.book.live -text {Stack and variables}
    $p.book add $p.book.breakpoints -text Breakpoints
    $p.book add $p.book.output -text {Debugger output}
    ttk::label $p.status -textvariable ::GX::ScriptDebug::state($p,status) -anchor w
    bind $p.status <Configure> {%W configure -wraplength [expr {max(80,%w-8)}]}
    ttk::frame $p.footer
    ttk::button $p.footer.close -text {Close / cancel Debug} -command [list ::GX::scriptDebugClose $p]
    ttk::button $p.footer.output -text {Program output / diagnostics…} -command [list ::GX::scriptDebugProgramOutput $p]
    pack $p.footer.close -side right;pack $p.footer.output -side left
    pack $p.footer $p.status -side bottom -fill x -pady 2
    pack $p.controls -side top -fill x
    pack $p.book -fill both -expand 1
    bind $stack <<TreeviewSelect>> [list ::GX::scriptDebugFrame $p]
    bind $p <Destroy> [list ::GX::scriptDebugDestroyed $p %W]
    scriptWorkspaceAssistMount $editor $p
    scriptDebugLog $p {Debugger idle. Native state and command receipts appear here; program output has its own window.}
    if {![dict get $capabilities pause_supported]} {scriptDebugLog $p [dict get $capabilities pause_reason]}
    scriptDebugUiTick $p
    return $p
}
proc ::GX::scriptDebugProgramOutput {p} {
    set id $::GX::ScriptDebug::state($p,job)
    if {$id ne {}} {scriptJobDetailsWindow $id}
}
proc ::GX::scriptDebugLog {p message} {
    if {![winfo exists $p.book.output.text]} return
    set t $p.book.output.text;$t configure -state normal
    $t insert end "[clock format [clock seconds] -format %H:%M:%S] $message\n"
    if {[lindex [split [$t index end] .] 0]>300} {$t delete 1.0 100.0}
    $t see end;$t configure -state disabled
}
proc ::GX::scriptDebugReady {p} {
    set ns [scriptDebugEditor $p];upvar #0 ${ns}::ui ui
    if {$::GX::currentSession eq {}} {return {No Session open. Editing, User save and import/export remain available.}}
    if {$::GX::ScriptDebug::state($p,token) ne [scriptWorkspaceSessionToken]} {return {Session changed. Close and reopen the debugger for this Session.}}
    ${ns}::_recomputeDirty
    if {$ui(modified)} {return {Save or undo source edits before debugging the immutable registered snapshot.}}
    if {![string match session:* $ui(currentId)]} {return {Save or assign a Session script before starting Debug.}}
    if {[catch {set m [scriptRegistryDescribe $ui(currentId)]} reason]} {return $reason}
    if {[dict get $m sha256] ne $ui(currentSha)} {return {Registered source changed. Reload it before Debug.}}
    return {}
}
proc ::GX::scriptDebugUiUpdate {p} {
    variable ::GX::ScriptDebug::state
    if {![winfo exists $p]} return
    set reason [scriptDebugReady $p];set phase $state($p,phase)
    set active [expr {$phase in {STARTING RUNNING PAUSED CONTINUING EXCEPTION}}]
    set ns [scriptDebugEditor $p];upvar #0 ${ns}::ui ui
    sourceSurfaceBreakpoints $ui(text) [expr {$active ? {lock} : {unlock}}]
    foreach name {enable disable remove clear} {$p.book.breakpoints.actions.$name state [expr {$active ? {disabled} : {!disabled}}]}
    foreach name {start continue pause stop into over out breakpoint clear} {
        switch -- $name {
            start {set enabled [expr {!$active && $reason eq {}}]}
            continue - into - over - out {set enabled [expr {$phase eq {PAUSED} && $reason eq {}}]}
            pause {set enabled [expr {$phase in {RUNNING CONTINUING} && $state($p,job) ne {} && [dict get $state($p,capabilities) pause_supported]}]}
            stop {set enabled [expr {$active && $state($p,job) ne {}}]}
            default {set enabled [expr {!$active}]}
        }
        $p.controls.$name state [expr {$enabled ? {!disabled} : {disabled}}]
    }
    $p.footer.output state [expr {$state($p,job) eq {} ? {disabled} : {!disabled}}]
    if {$phase eq {IDLE}} {set state($p,status) [expr {$reason ne {} ? "IDLE — $reason" : {IDLE — ready to debug the saved Session snapshot.}}]}
    set ns [scriptDebugEditor $p];upvar #0 ${ns}::ui ui
    set points [sourceSurfaceBreakpoints $ui(text) describe]
    set identity [list $points $ui(currentId) $ui(currentSha)]
    if {![info exists state($p,breakpointIdentity)] || $state($p,breakpointIdentity) ne $identity} {
        set state($p,breakpointIdentity) $identity
        set b $state($p,breakpoints);$b delete [$b children {}]
        set file {}
        if {$ui(currentId) ne {} && ![catch {scriptRegistryDescribe $ui(currentId)} metadata]} {set file [file tail [dict get $metadata source_path]]}
        foreach point $points {set line [dict get $point line];$b insert {} end -id line$line -values [list $line [expr {[dict get $point enabled] ? {yes} : {no}}] [sourceSurfaceFunctionAt $ui(text) $line] $file $ui(currentId) $ui(currentSha)]}
    }
}
proc ::GX::scriptDebugUiTick {p} {
    if {![winfo exists $p]} return
    scriptDebugUiUpdate $p
    set ::GX::ScriptDebug::state($p,uiTimer) [after 250 [list ::GX::scriptDebugUiTick $p]]
}
proc ::GX::scriptDebugBreakpoint {p op} {
    variable ::GX::ScriptDebug::state
    set ns [scriptDebugEditor $p];upvar #0 ${ns}::ui ui
    if {$op eq {clear}} {sourceSurfaceBreakpoints $ui(text) clear;return}
    set row [lindex [$state($p,breakpoints) selection] 0]
    if {![regexp {^line([0-9]+)$} $row -> line]} return
    if {$op eq {navigate}} {$ui(text) mark set insert $line.0;$ui(text) see $line.0;focus $ui(text)} else {sourceSurfaceBreakpoints $ui(text) $op $line}
}
proc ::GX::scriptDebugEditor {p} {return ::GX::$::GX::ScriptDebug::state($p,language)ScriptEditorUI}
proc ::GX::scriptDebugAction {p operation} {
    variable ::GX::ScriptDebug::state
    if {[catch {
        set ns [scriptDebugEditor $p];upvar #0 ${ns}::ui ui
        if {$operation in {breakpoint clear}} {
            if {$operation eq {clear}} {sourceSurfaceBreakpoints $ui(text) clear} else {sourceSurfaceBreakpoints $ui(text) toggle [lindex [split [$ui(text) index insert] .] 0]}
            return
        }
        if {$operation eq {stop}} {if {$state($p,job) ne {}} {scriptJobCancel $state($p,job)};return}
        if {$state($p,token) ne [scriptWorkspaceSessionToken]} {error {Session changed; close the debugger to cancel its owned Job}}
        ${ns}::_recomputeDirty
        if {$ui(modified) || ![string match session:* $ui(currentId)]} {error {Save a clean registered Session script before Debug or stepping; the running snapshot cannot change}}
        if {$operation eq {start}} {
            if {$state($p,job) ne {}} {set old [scriptJobDescribe $state($p,job)];if {[dict get $old state] in {QUEUED PREPARING RUNNING FINALIZING}} {error {Stop the existing Debug Job first}}}
            set metadata [scriptRegistryDescribe $ui(currentId)]
            if {[dict get $metadata sha256] ne $ui(currentSha)} {error {Registered source changed; reload the editor}}
            set state($p,sha) $ui(currentSha);set state($p,source) $ui(text)
            set options [dict create session $::GX::currentSession debug_breakpoints [sourceSurfaceBreakpoints $ui(text)]]
            scriptJobDebugSubmit $ui(currentId) {} $options [list ::GX::scriptDebugSubmitted $p]
            set state($p,status) STARTING;set state($p,phase) STARTING;scriptDebugUiUpdate $p;scriptDebugLog $p {Submitting native managed Debug Job}
        } else {
            if {$state($p,job) eq {}} {error {Start a Debug Job first}}
            scriptJobAsync [scriptJobCommand debug_control $state($p,job) $operation $state($p,sha)] {} [list ::GX::scriptDebugControlled $p]
        }
    } reason]} {set state($p,status) $reason;scriptDebugLog $p $reason}
}
proc ::GX::scriptDebugControlled {p response} {
    if {![winfo exists $p]} return
    if {![dict get $response ok]} {set ::GX::ScriptDebug::state($p,status) [dict get $response error];scriptDebugLog $p [dict get $response error]} else {scriptDebugLog $p {Native command acknowledged}}
}
proc ::GX::scriptDebugSubmitted {p response} {
    if {![winfo exists $p]} {if {[dict get $response ok]} {catch {scriptJobCancel [dict get $response result id]}};return}
    if {![dict get $response ok]} {set ::GX::ScriptDebug::state($p,status) [dict get $response error];set ::GX::ScriptDebug::state($p,phase) FAILED;scriptDebugLog $p [dict get $response error];return}
    set ::GX::ScriptDebug::state($p,job) [dict get $response result id];scriptDebugPoll $p
}
proc ::GX::scriptDebugPoll {p} {
    if {![winfo exists $p]} return
    if {$::GX::ScriptDebug::state($p,token) ne [scriptWorkspaceSessionToken] && !$::GX::ScriptDebug::state($p,contextChanged)} {
        set ::GX::ScriptDebug::state($p,contextChanged) 1
        set ::GX::ScriptDebug::state($p,status) {Session changed. Cancelling the owned Debug Job.}
        catch {scriptJobCancel $::GX::ScriptDebug::state($p,job)}
    }
    # Read the owned Job through its original identity until cancellation is
    # genuinely terminal, even after the GUI's current Session closes/changes.
    scriptJobAsync [scriptJobCommand debug_read $::GX::ScriptDebug::state($p,job)] {} [list ::GX::scriptDebugPolled $p] {timeout_ms 10000 max_bytes 2097152 ui_lifetime 1 label {Native debugger observation}}
}
proc ::GX::scriptDebugPolled {p response} {
    variable ::GX::ScriptDebug::state
    if {![winfo exists $p]} return
    if {![dict get $response ok]} {set state($p,status) [dict get $response error]
    } else {
        set debug [dict get $response result];set state($p,observation) $debug
        set status [dict get $debug state];set state($p,status) "$status — $state($p,job)"
        if {$status ne $state($p,phase)} {scriptDebugLog $p "$status — $state($p,job)"}
        set state($p,phase) $status
        set stack $state($p,stack);set variables $state($p,variables)
        if {$status eq {PAUSED} && !$state($p,contextChanged)} {
            set selected [datasetPublicationV2DictDefault $debug selected_frame 0]
            set frame [lindex [dict get $debug stack] $selected]
            set file [datasetPublicationV2DictDefault $frame file {}]
            set snapshot [datasetPublicationV2DictDefault $debug source {}]
            set ns [scriptDebugEditor $p];upvar #0 ${ns}::ui ui
            ${ns}::_recomputeDirty
            if {$ui(modified)} {sourceSurfaceLocation $state($p,source) 0;append state($p,status) { — editor differs from this immutable paused snapshot}
            } elseif {$file ne {} && $snapshot ne {} && [file normalize $file] ne [file normalize $snapshot]} {
                sourceSurfaceLocation $state($p,source) 0
                append state($p,status) " — external frame: $file:[dict get $frame line]"
            } else {sourceSurfaceLocation $state($p,source) [dict get $debug line]}
            $stack delete [$stack children {}];set index 0
            foreach frame [dict get $debug stack] {
                set name [datasetPublicationV2DictDefault $frame function [datasetPublicationV2DictDefault $frame name {}]]
                $stack insert {} end -id frame$index -values [list $name [datasetPublicationV2DictDefault $frame file {}] [dict get $frame line]];incr index
            }
            set selected [datasetPublicationV2DictDefault $debug selected_frame 0]
            if {[$stack exists frame$selected]} {$stack selection set frame$selected}
            $variables delete [$variables children {}]
            foreach scope {locals globals} {
                if {![dict exists $debug $scope]} continue
                dict for {name value} [dict get $debug $scope] {$variables insert {} end -text "$scope.$name" -values [list [dict get $value type] [dict get $value shape] [string range [dict get $value value] 0 1023]]}
            }
        } else {sourceSurfaceLocation $state($p,source) 0;$stack delete [$stack children {}];$variables delete [$variables children {}]}
        scriptDebugUiUpdate $p
        if {$status in {COMPLETED FAILED CANCELLED INTERRUPTED}} {return}
    }
    set state($p,timer) [after 350 [list ::GX::scriptDebugPoll $p]]
}
proc ::GX::scriptDebugFrame {p} {
    set stack $::GX::ScriptDebug::state($p,stack)
    set row [lindex [$stack selection] 0]
    if {![regexp {^frame([0-9]+)$} $row -> index]} return
    if {[info exists ::GX::ScriptDebug::state($p,observation)] && [dict exists $::GX::ScriptDebug::state($p,observation) selected_frame] && [dict get $::GX::ScriptDebug::state($p,observation) selected_frame]==$index} return
    set ns [scriptDebugEditor $p]
    scriptJobAsync [scriptJobCommand debug_control $::GX::ScriptDebug::state($p,job) frame $::GX::ScriptDebug::state($p,sha) $index] {} [list ::GX::scriptDebugControlled $p]
}
proc ::GX::scriptDebugDestroyed {p actual} {
    if {$actual ne $p} return
    variable ::GX::ScriptDebug::state
    if {[info exists state($p,uiTimer)] && $state($p,uiTimer) ne {}} {after cancel $state($p,uiTimer)}
    if {[info exists state($p,timer)] && $state($p,timer) ne {}} {after cancel $state($p,timer)}
    if {[info exists state($p,job)] && $state($p,job) ne {}} {catch {set job [scriptJobDescribe $state($p,job)];if {[dict get $job state] in {QUEUED PREPARING RUNNING FINALIZING}} {scriptJobCancel $state($p,job)}}}
    if {[info exists state($p,source)] && [winfo exists $state($p,source)]} {sourceSurfaceBreakpoints $state($p,source) unlock;sourceSurfaceLocation $state($p,source) 0}
    array unset state $p,*
}

proc ::GX::scriptDebugPrepareEditorClose {editor} {
    set p $editor.p.debug
    if {![winfo exists $p]} {return 1}
    if {$::GX::ScriptDebug::state($p,phase) in {STARTING RUNNING PAUSED CONTINUING EXCEPTION}} {
        set answer [tk_messageBox -parent $editor -type okcancel -default cancel -icon question -title {Stop the owned Debug Job?} -message {Closing cancels this editor's managed Debug Job. Choose OK to stop it and close, or Cancel to keep inspecting it. Hiding the debugger with View keeps the Job managed.}]
        if {$answer ne {ok}} {return 0}
    }
    return 1
}
proc ::GX::scriptDebugClose {p} {
    if {[scriptDebugPrepareEditorClose $::GX::ScriptDebug::state($p,editor)]} {destroy $p}
}

proc ::GX::scriptDebugToolbarLayout {p width} {
    variable ::GX::ScriptDebug::state
    if {![winfo exists $p.controls]} return
    set size [expr {max(18,min(32,[font metrics TkDefaultFont -linespace]))}]
    set compact [expr {$width<600}];set style [list $compact $size]
    if {![info exists state($p,toolbarStyle)] || $state($p,toolbarStyle) ne $style} {
        set state($p,toolbarStyle) $style
        foreach name {start continue pause stop into over out breakpoint clear} {
            $p.controls.$name configure -text [expr {$compact ? {} : $state($p,label,$name)}] -width [expr {$compact ? 0 : -1}] -image [native2DViewportGlyph debug_$name $size]
        }
        # Ttk computes natural image-only request widths at idle. Measuring the
        # old nine-character minimum immediately would keep three empty rows.
        after idle [list ::GX::scriptDebugToolbarMeasure $p]
    } else {uiFieldControlsLayout $p.controls $width}
}
proc ::GX::scriptDebugToolbarMeasure {p} {
    if {[winfo exists $p.controls]} {uiFieldControlsLayout $p.controls [winfo width $p.controls]}
}
