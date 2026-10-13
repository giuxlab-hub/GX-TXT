# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::WorkbenchExtension {variable dialogs {}}
proc ::GX::workbenchExtensionExportDialog {w context {parent ""}} {
    variable ::GX::WorkbenchExtension::dialogs
    set actions [workbenchExtensionProviderList [dict get $context workbench_id] exporter]
    if {$actions eq {}} {error "No enabled exporter supports this viewer. Install or enable an exporter through Modules."}
    if {[winfo exists $w]} {raise $w;return $w}
    set labels {};set mapping {}
    foreach action $actions {
        set label "[dict get $action name] — [dict get $action module_id]"
        lappend labels $label;dict set mapping $label $action
    }
    dict set dialogs $w [dict create context $context mapping $mapping selected [lindex $labels 0]]
    toplevel $w;wm title $w "Export presentation";wm geometry $w 650x210
    if {$parent ne ""} {wm transient $w $parent}
    ttk::label $w.label -text "Exporter";pack $w.label -anchor w -padx 12 -pady 8
    ttk::combobox $w.provider -state readonly -values $labels; $w.provider set [lindex $labels 0]
    pack $w.provider -fill x -padx 12
    ttk::label $w.status -text "Export uses the current scientific view and its recorded display sampling policy." -wraplength 610
    pack $w.status -fill x -padx 12 -pady 8
    ttk::frame $w.actions;pack $w.actions -side bottom -fill x -padx 12 -pady 12
    ttk::button $w.actions.export -text "Export…" -command [list ::GX::_workbenchExtensionExportConfigure $w]
    ttk::button $w.actions.close -text Close -command [list destroy $w]
    pack $w.actions.export $w.actions.close -side right -padx 5
    bind $w <Escape> [list destroy $w]
    bind $w <Destroy> [list ::GX::_workbenchExtensionExportDestroy $w %W]
    return $w
}
proc ::GX::_workbenchExtensionExportDestroy {w destroyed} {
    variable ::GX::WorkbenchExtension::dialogs
    if {$w eq $destroyed} {dict unset dialogs $w}
}
proc ::GX::_workbenchExtensionExportConfigure {w} {
    variable ::GX::WorkbenchExtension::dialogs
    set definition [dict get $dialogs $w mapping [$w.provider get]]
    if {[dict size [dict get $definition fields]]} {
        uiFieldFormCreate $w.parameters [dict get $definition name] [dict get $definition fields] {} [list ::GX::_workbenchExtensionExportWrite $w $definition] $w
    } elseif {[catch {_workbenchExtensionExportWrite $w $definition {}} message]} {$w.status configure -text $message}
}
proc ::GX::_workbenchExtensionExportWrite {w definition parameters} {
    variable ::GX::WorkbenchExtension::dialogs
    set format [dict get $definition output_format]
    set target [tk_getSaveFile -parent $w -title [dict get $definition name] -defaultextension .$format -filetypes [list [list [string toupper $format] .$format]]]
    if {$target eq ""} return
    set context [dict get $dialogs $w context];dict set context parameters $parameters
    set receipt [workbenchExtensionExport [dict get $definition module_id] [dict get $definition action_id] $context $target]
    $w.status configure -text "Created [file tail $target] ([dict get $receipt byte_count] bytes). SHA-256: [dict get $receipt sha256]"
    return $receipt
}

# Context is refreshed on each invocation, so an open chooser cannot retain a
# stale document revision after another successful Workbench action.
proc ::GX::workbenchExtensionActionDialog {w contextCommand parent} {
    variable ::GX::WorkbenchExtension::dialogs
    set context [uplevel #0 $contextCommand];set workbench [dict get $context workbench_id]
    set actions {};foreach action [workbenchExtensionProviderList $workbench] {if {[dict get $action category] ne "exporter"} {lappend actions $action}}
    if {$actions eq {}} {error "No enabled extension action supports this Workbench. Enable its installed module in Modules."}
    if {[winfo exists $w]} {raise $w;return $w}
    set labels {};set mapping {}
    foreach action $actions {set label "[dict get $action name] — [dict get $action module_id]";lappend labels $label;dict set mapping $label $action}
    dict set dialogs $w [dict create context_command $contextCommand mapping $mapping]
    toplevel $w;wm title $w "Workbench extensions";wm transient $w $parent;wm geometry $w 720x240
    ttk::label $w.label -text Action;pack $w.label -anchor w -padx 12 -pady 8
    ttk::combobox $w.provider -state readonly -values $labels;$w.provider set [lindex $labels 0];pack $w.provider -fill x -padx 12
    ttk::label $w.status -text {Action parameters use shared fields. Geometry changes commit as one Undo action; failed proposals roll back.} -wraplength 680;pack $w.status -fill x -padx 12 -pady 8
    bind $w.status <Configure> [list ::GX::_workbenchExtensionActionWrap $w.status %w]
    ttk::frame $w.actions;pack $w.actions -side bottom -fill x -padx 12 -pady 12
    ttk::button $w.actions.run -text "Configure / Run…" -command [list ::GX::_workbenchExtensionActionConfigure $w]
    ttk::button $w.actions.close -text Close -command [list destroy $w];pack $w.actions.run $w.actions.close -side right -padx 5
    bind $w <Escape> [list destroy $w];bind $w <Destroy> [list ::GX::_workbenchExtensionExportDestroy $w %W]
    return $w
}
proc ::GX::_workbenchExtensionActionWrap {widget width} {if {[winfo exists $widget]} {$widget configure -wraplength [expr {max(100,$width-20)}]}}
proc ::GX::_workbenchExtensionActionConfigure {w} {
    variable ::GX::WorkbenchExtension::dialogs
    set definition [dict get $dialogs $w mapping [$w.provider get]]
    if {[dict size [dict get $definition fields]]} {uiFieldFormCreate $w.parameters [dict get $definition name] [dict get $definition fields] {} [list ::GX::_workbenchExtensionActionRun $w $definition] $w} elseif {[catch {_workbenchExtensionActionRun $w $definition {}} message]} {$w.status configure -text $message}
}
proc ::GX::_workbenchExtensionActionRun {w definition parameters} {
    variable ::GX::WorkbenchExtension::dialogs
    set context [uplevel #0 [dict get $dialogs $w context_command]];dict set context parameters $parameters
    set receipt [workbenchExtensionInvoke [dict get $definition module_id] [dict get $definition action_id] $context]
    $w.status configure -text "Action completed: revision [dict get $receipt revision_before] → [dict get $receipt revision_after]; created [join [dict get $receipt created_ids] {, }]; modified [join [dict get $receipt modified_ids] {, }]; [join [dict get $receipt warnings] {; }]."
    return $receipt
}
