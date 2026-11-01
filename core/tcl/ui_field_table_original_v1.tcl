# SPDX-License-Identifier: GPL-3.0-or-later
# Opt-in, readonly original-cell presentation. TSV copy remains unchanged.
namespace eval ::GX::UiField::TableOriginal {variable tables {};variable dialogs {}}
proc ::GX::uiFieldTableOriginalAttach {widget guard} {
    set tree [uiFieldComponentTableWidget $widget]
    if {![llength $guard] || ![llength [info commands [lindex $guard 0]]]} {error {Original-cell inspection requires a live trusted host guard}}
    variable ::GX::UiField::TableOriginal::tables
    set identity [winfo id $tree]
    if {[dict exists $tables $tree]} {
        if {[dict get $tables $tree identity] ne $identity} {error {Original-cell table incarnation changed}}
        dict set tables $tree guard $guard
        return $tree
    }
    dict set tables $tree [dict create identity $identity guard $guard]
    bind $tree <Double-Button-1> +[list ::GX::_uiFieldTableOriginalPointer $tree %x %y]
    bind $tree <Return> +[list ::GX::_uiFieldTableOriginalKeyboard $tree]
    bind $tree <KP_Enter> +[list ::GX::_uiFieldTableOriginalKeyboard $tree]
    bind $tree <Button-3> +[list ::GX::_uiFieldTableOriginalMenu $tree %x %y %X %Y]
    bind $tree <Destroy> +[list ::GX::_uiFieldTableOriginalDispose $tree %W]
    return $tree
}
proc ::GX::_uiFieldTableOriginalGuard {tree} {
    variable ::GX::UiField::TableOriginal::tables
    if {![dict exists $tables $tree] || ![winfo exists $tree] || [winfo id $tree] ne [dict get $tables $tree identity]} {error {The original-cell table has closed or changed}}
    set admitted [uplevel #0 [dict get $tables $tree guard]]
    if {[string is boolean -strict $admitted] && !$admitted} {error {Original-cell inspection is unavailable in this host scope}}
    return [dict get $tables $tree]
}
proc ::GX::_uiFieldTableOriginalDispose {tree actual} {
    if {$tree ne $actual} return
    variable ::GX::UiField::TableOriginal::tables
    if {[dict exists $tables $tree]} {dict unset tables $tree}
}
proc ::GX::_uiFieldTableOriginalError {tree message} {
    if {[winfo exists $tree]} {tk_messageBox -parent [winfo toplevel $tree] -icon error -title {Original value unavailable} -message $message}
}
proc ::GX::_uiFieldTableOriginalPointer {tree x y} {
    if {[catch {
        _uiFieldTableOriginalGuard $tree
        set row [$tree identify row $x $y];set column [$tree identify column $x $y]
        if {$row ne {} && $column ne {#0}} {
            $tree selection set $row;$tree focus $row
            uiFieldTableOriginalOpen $tree $column
        }
    } message]} {_uiFieldTableOriginalError $tree $message}
}
proc ::GX::_uiFieldTableOriginalKeyboard {tree} {
    if {[catch {uiFieldTableOriginalOpen $tree} message]} {_uiFieldTableOriginalError $tree $message}
}
proc ::GX::_uiFieldTableOriginalMenu {tree x y rootX rootY} {
    if {[catch {
        _uiFieldTableOriginalGuard $tree
        set row [$tree identify row $x $y];set column [$tree identify column $x $y]
        if {$row ne {} && $column ne {#0}} {
            $tree selection set $row;$tree focus $row
            set menu $tree.__originalMenu
            if {![winfo exists $menu]} {menu $menu -tearoff 0}
            $menu delete 0 end
            $menu add command -label {Inspect original value…} -command [list ::GX::_uiFieldTableOriginalOpenSelected $tree $column]
            uiMenuPopup $menu $rootX $rootY
        }
    } message]} {_uiFieldTableOriginalError $tree $message}
}
proc ::GX::_uiFieldTableOriginalOpenSelected {tree column} {
    if {[catch {uiFieldTableOriginalOpen $tree $column} message]} {_uiFieldTableOriginalError $tree $message}
}
proc ::GX::uiFieldTableOriginalOpen {widget {column #2}} {
    variable ::GX::UiField::TableOriginal::dialogs
    set tree [uiFieldComponentTableWidget $widget]
    _uiFieldTableOriginalGuard $tree
    set table [uiFieldComponentTableRead $tree 1]
    if {[llength [dict get $table rows]]!=1} {error {Select exactly one row to inspect its original value}}
    if {![regexp {^#([1-9][0-9]?)$} $column -> ordinal] || $ordinal>[llength [dict get $table columns]]} {error {Choose an actual declared value column}}
    set row [lindex [dict get $table rows] 0];set value [lindex $row [expr {$ordinal-1}]]
    if {[string length [encoding convertto utf-8 $value]]>65536} {error {Original-cell inspection is bounded to 64 KiB of UTF-8 text}}
    set label [lindex $row 0];set heading [$tree heading [lindex [dict get $table columns] [expr {$ordinal-1}]] -text]
    set dialog $tree.__originalValue
    if {[winfo exists $dialog]} {uiFieldDialogClose $dialog}
    if {[dict size $dialogs]>=64} {error {Close an existing original-value inspector before opening another}}
    uiFieldDialogCreate $dialog $tree {Original value — readonly snapshot} 760x480
    try {
    dict set dialogs $dialog [dict create tree $tree identity [winfo id $tree] value $value]
    bind $dialog <Destroy> +[list ::GX::_uiFieldTableOriginalDialogDisposed $dialog %W]
    ttk::label $dialog.context -text "[string range $label 0 255] — $heading" -wraplength 680
    pack $dialog.context -side top -fill x -padx 8 -pady 6
    ttk::frame $dialog.actions
    ttk::button $dialog.actions.copy -text {Copy original value} -command [list ::GX::_uiFieldTableOriginalCopy $dialog]
    ttk::button $dialog.actions.close -text Close -command [list ::GX::uiFieldDialogClose $dialog]
    pack $dialog.actions.copy $dialog.actions.close -side left -padx 4 -pady 5
    pack $dialog.actions -side bottom -fill x -padx 4
    ttk::frame $dialog.body;pack $dialog.body -fill both -expand 1 -padx 8 -pady 3
    text $dialog.body.text -wrap none -font TkFixedFont -undo 0 -exportselection 0
    ttk::scrollbar $dialog.body.y -orient vertical -command [list $dialog.body.text yview]
    ttk::scrollbar $dialog.body.x -orient horizontal -command [list $dialog.body.text xview]
    $dialog.body.text configure -yscrollcommand [list $dialog.body.y set] -xscrollcommand [list $dialog.body.x set]
    grid $dialog.body.text -row 0 -column 0 -sticky nsew;grid $dialog.body.y -row 0 -column 1 -sticky ns;grid $dialog.body.x -row 1 -column 0 -sticky ew
    grid rowconfigure $dialog.body 0 -weight 1;grid columnconfigure $dialog.body 0 -weight 1
    $dialog.body.text insert 1.0 $value;$dialog.body.text configure -state disabled
    uiTextEditingAttach $dialog [list $dialog.body.text]
    _uiFieldTableOriginalGuard $tree
    uiFieldDialogPresent $dialog $dialog.body.text 0
    after idle [list ::GX::uiFieldWindowFit $dialog]
    return $dialog
    } on error {message options} {
        if {[winfo exists $dialog]} {uiFieldDialogClose $dialog}
        return -options $options $message
    }
}
proc ::GX::_uiFieldTableOriginalDialogDisposed {dialog actual} {
    if {$dialog eq $actual && [dict exists $::GX::UiField::TableOriginal::dialogs $dialog]} {dict unset ::GX::UiField::TableOriginal::dialogs $dialog}
}
proc ::GX::_uiFieldTableOriginalCopy {dialog} {
    variable ::GX::UiField::TableOriginal::dialogs
    if {![winfo exists $dialog] || ![dict exists $dialogs $dialog]} {error {The original-value snapshot has closed}}
    set record [dict get $dialogs $dialog];set tree [dict get $record tree]
    if {[catch {_uiFieldTableOriginalGuard $tree} message]} {_uiFieldTableOriginalError $tree $message;return}
    if {[winfo id $tree] ne [dict get $record identity]} {error {The original-cell table incarnation changed}}
    clipboard clear -displayof $dialog
    clipboard append -displayof $dialog -- [dict get $record value]
}
