# SPDX-License-Identifier: GPL-3.0-or-later
# Runtime is a projection of existing Configuration fields and drafts.
namespace eval ::GX {variable configurationRuntimeRows {};variable configurationRuntimeAfter {}}
source [file join [file dirname [info script]] python_import_audit.tcl]
source [file join [file dirname [info script]] configuration_contracts.tcl]
proc ::GX::configurationRuntimeBuild {tab} {
    variable configurationRuntimeRows
    set configurationRuntimeRows {}
    ttk::notebook $tab.pages
    ttk::frame $tab.pages.tools
    ttk::frame $tab.pages.contracts
    $tab.pages add $tab.pages.tools -text {Tools and settings}
    $tab.pages add $tab.pages.contracts -text Contracts
    pack $tab.pages -fill both -expand 1
    set content [uiFieldScrollableCreate $tab.viewport 620]
    pack $tab.viewport -in $tab.pages.tools -fill both -expand 1
    configurationContractsBuild $tab.pages.contracts
    grid columnconfigure $content 0 -weight 1
    ttk::frame $content.audit -padding {4 4 4 8}
    ttk::label $content.audit.note -text {Configured local tools. Detect, test, then save your changes.} -wraplength 380
    ttk::button $content.audit.open -text {Check Python imports…} -command ::GX::pythonEnvironmentAuditOverlayOpen
    grid $content.audit.note -row 0 -column 0 -sticky w -padx 4
    grid $content.audit.open -row 0 -column 1 -sticky e -padx 4
    grid columnconfigure $content.audit 0 -weight 1
    grid $content.audit -row 0 -column 0 -sticky ew
    foreach {name title row} {science {Scientific interpreters and solvers} 1 documents {Documents, images and media} 2 settings {Diagnostics and runtime settings} 3} {
        ttk::labelframe $content.$name -text $title -padding 8
        grid $content.$name -row $row -column 0 -sticky ew -padx 4 -pady 5
        grid columnconfigure $content.$name 0 -weight 1
    }
    set ::GX::configurationUi(runtime_content) $content
    bind $content <Configure> +[list ::GX::configurationRuntimeSchedule $content]
    bind $content <Destroy> +[list ::GX::configurationRuntimeDisposed $content %W]
    $tab.viewport.scroll configure -takefocus 1
    bind $tab.viewport.scroll <Home> [list $tab.viewport.scroll yview moveto 0]
    bind $tab.viewport.scroll <End> [list $tab.viewport.scroll yview moveto 1]
    return $content
}
proc ::GX::configurationRuntimeFieldCreate {content id field} {
    variable configurationRuntimeRows;variable configurationGuiEditors
    if {$id in {runtime.python runtime.octave runtime.spice runtime.gmsh runtime.getdp runtime.mpi}} {set category science
    } elseif {[string match runtime.* $id]} {set category documents} else {set category settings}
    set parent $content.$category
    set widgetId [string map {. _ - _} $id]
    set row $parent.field_$widgetId
    set index [llength [grid slaves $parent]]
    ttk::frame $row -padding {2 3}
    grid $row -row $index -column 0 -sticky ew
    ttk::label $row.label -text [dict get $field label] -justify left -wraplength 220
    if {[dict get $field type] in {boolean integer double number choice color}} {
        uiFieldCreate $row.value $field ::GX::configurationUi($id)
    } else {ttk::entry $row.value -textvariable ::GX::configurationUi($id) -width 12}
    if {[dict get $field scope] in {framework runtime session}} {$row.value configure -state readonly}
    if {[dict get $field scope] in {user module} && ![datasetPublicationV2DictDefault $field readonly 0]} {dict set configurationGuiEditors $id $row.value}
    ttk::frame $row.actions
    if {[string match runtime.* $id] && $id ni {runtime.markdown_viewer runtime.html_viewer}} {
        set tool [string range $id 8 end]
        ttk::button $row.actions.detect -text Detect -command [list ::GX::configurationGuiDetect $tool]
        ttk::button $row.actions.test -text Test -command [list ::GX::configurationGuiTestTool $tool]
        pack $row.actions.detect $row.actions.test -side left -padx 2
    } elseif {$id eq {diagnostics.stderr_log_directory}} {
        ttk::button $row.actions.browse -text Browse… -command [list ::GX::configurationGuiDiagnosticDirectory $id]
        pack $row.actions.browse -side left -padx 2
    }
    lappend configurationRuntimeRows $row
    # Widget names are Tk paths, not filesystem paths.
    set viewport [string range $content 0 [expr {[string last . $content]-1}]]
    set tag GXRuntimePages[binary encode hex [encoding convertto utf-8 $content]]
    foreach widget [concat [list $row.value] [winfo children $row.actions]] {
        bindtags $widget [linsert [bindtags $widget] 0 $tag]
    }
    bind $tag <Prior> [format {%s; break} [list $viewport yview scroll -1 pages]]
    bind $tag <Next> [format {%s; break} [list $viewport yview scroll 1 pages]]
    if {$id eq {runtime.python}} {bind $row.value <KeyRelease> +{::GX::pythonEnvironmentAuditRuntimeEdited}}
    configurationRuntimeSchedule $content
}
proc ::GX::configurationRuntimeSchedule {content} {
    variable configurationRuntimeAfter
    if {$configurationRuntimeAfter ne {}} return
    set configurationRuntimeAfter [after idle [list ::GX::configurationRuntimeReflow $content]]
}
proc ::GX::configurationRuntimeReflow {content} {
    variable configurationRuntimeAfter;variable configurationRuntimeRows
    set configurationRuntimeAfter {}
    if {![winfo exists $content]} return
    set width [winfo width $content];set narrow [expr {$width<760}]
    $content.audit.note configure -wraplength [expr {max(100,$width-260)}]
    foreach row $configurationRuntimeRows {
        if {![winfo exists $row]} continue
        foreach column {0 1 2} {grid columnconfigure $row $column -weight 0}
        if {$narrow} {
            $row.label configure -wraplength [expr {max(120,$width-48)}]
            grid $row.label -row 0 -column 0 -columnspan 2 -sticky w -padx 3 -pady {2 1}
            grid $row.value -row 1 -column 0 -columnspan 1 -sticky ew -padx 3 -pady {0 3}
            grid $row.actions -row 1 -column 1 -sticky e -padx 2
            grid columnconfigure $row 0 -weight 1
        } else {
            $row.label configure -wraplength [expr {min(280,max(160,$width/3))}]
            grid $row.label -row 0 -column 0 -columnspan 1 -sticky w -padx 3 -pady 3
            grid $row.value -row 0 -column 1 -columnspan 1 -sticky ew -padx 6 -pady 3
            grid $row.actions -row 0 -column 2 -sticky e -padx 2
            grid columnconfigure $row 1 -weight 1
        }
    }
}
proc ::GX::configurationRuntimeDisposed {content actual} {
    if {$content ne $actual} return
    variable configurationRuntimeAfter
    if {$configurationRuntimeAfter ne {}} {after cancel $configurationRuntimeAfter;set configurationRuntimeAfter {}}
    set tag GXRuntimePages[binary encode hex [encoding convertto utf-8 $content]]
    foreach event [bind $tag] {bind $tag $event {}}
    if {[llength [info commands ::GX::pythonEnvironmentAuditOverlayClose]]} {pythonEnvironmentAuditOverlayClose}
}
proc ::GX::configurationRuntimeFooterResize {actions width} {
    if {[winfo exists $actions.status]} {$actions.status configure -wraplength [expr {max(180,$width-[winfo reqwidth $actions.save]-36)}] -justify left}
}
