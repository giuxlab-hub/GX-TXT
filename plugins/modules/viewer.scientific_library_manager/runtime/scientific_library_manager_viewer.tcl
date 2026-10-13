# GX-TXT Scientific Library Manager GUI.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::ScientificLibraryManagerViewer {
    variable window .gx_scientific_library_manager
    variable typeFilter "All types"
    variable query ""
    variable selectedLibrary ""
    variable selectedEntry ""
    variable status "Ready"
    variable rows {}
    variable entries {}
}

proc ::GX::ScientificLibraryManagerViewer::_show {widget content} {
    $widget configure -state normal
    $widget delete 1.0 end
    $widget insert end $content
    $widget configure -state disabled
}
proc ::GX::ScientificLibraryManagerViewer::_format {heading data} {
    set lines [list $heading]
    foreach key [lsort -dictionary [dict keys $data]] {
        set value [dict get $data $key]
        if {$value ne ""} {lappend lines "$key: $value"}
    }
    return [join $lines "\n"]
}
proc ::GX::ScientificLibraryManagerViewer::_report {action problem} {
    variable window; variable status
    set status "$action failed: $problem"
    tk_messageBox -parent $window -icon error -title "$action failed" -message $problem
}
proc ::GX::ScientificLibraryManagerViewer::_refresh {} {
    variable window; variable typeFilter; variable query; variable selectedLibrary
    variable selectedEntry; variable rows; variable entries; variable status
    set types [lsort -dictionary [::GX::ScientificLibraryManagerAPIv1::listLibraryTypes]]
    set choices [linsert $types 0 "All types"]
    $window.filter.type configure -values $choices
    if {$typeFilter ni $choices} {set typeFilter "All types"}
    set providers {}
    foreach type $types {
        dict set providers $type [::GX::ScientificLibraryManagerAPIv1::resolveLibraryProvider $type]
    }
    set installed [::GX::ScientificLibraryManagerAPIv1::listInstalledLibraries]
    set rows {}
    set needle [string tolower [string trim $query]]
    foreach library $installed {
        set type [dict get $library library_type]
        if {$typeFilter ne "All types" && $type ne $typeFilter} continue
        set haystack [string tolower "[dict get $library library_id] [dict get $library display_name] $type [dict get $library origin]"]
        if {$needle ne "" && [string first $needle $haystack] < 0} continue
        lappend rows $library
    }
    set list $window.body.list
    $list delete 0 end
    foreach library $rows {
        $list insert end "[dict get $library display_name]  |  [dict get $library version]  |  [dict get $library library_type]"
    }
    set providerLines [list "Registered Library Type Providers ([llength $types])"]
    foreach type $types {
        set provider [dict get $providers $type]
        lappend providerLines "$type  →  [dict get $provider provider_id] ([dict get $provider provider_version])"
    }
    _show $window.providers [join $providerLines "\n"]
    set selectedIndex -1
    for {set i 0} {$i < [llength $rows]} {incr i} {
        if {[dict get [lindex $rows $i] library_id] eq $selectedLibrary} {set selectedIndex $i; break}
    }
    if {$selectedIndex >= 0} {
        $list selection set $selectedIndex
        $list see $selectedIndex
        _select
    } else {
        set selectedLibrary ""; set selectedEntry ""; set entries {}
        $window.body.entries delete 0 end
        _show $window.details "Select an installed library to inspect its version, source, license, checksums and storage."
        foreach action {verify update remove open} {$window.actions.$action configure -state disabled}
        set status "[llength $rows] installed libraries shown; [llength $types] provider types available"
    }
}
proc ::GX::ScientificLibraryManagerViewer::_select {} {
    variable window; variable rows; variable entries; variable selectedLibrary
    variable selectedEntry; variable status
    set selection [$window.body.list curselection]
    if {![llength $selection]} return
    set library [lindex $rows [lindex $selection 0]]
    set selectedLibrary [dict get $library library_id]
    set selectedEntry ""
    set provider [::GX::ScientificLibraryManagerAPIv1::resolveLibraryProvider [dict get $library library_type]]
    _show $window.details "[_format {Installed library} $library]\n\n[_format {Type provider} $provider]"
    set entries [::GX::ScientificLibraryManagerAPIv1::listLibraryEntries $selectedLibrary]
    $window.body.entries delete 0 end
    foreach entry $entries {$window.body.entries insert end $entry}
    foreach action {verify update remove} {$window.actions.$action configure -state normal}
    set canOpen [expr {([dict get $provider library_viewer_module] ne "" && [dict get $provider library_viewer_id] ne "") ||
        ([dict get $provider entry_viewer_module] ne "" && [dict get $provider entry_viewer_id] ne "" && [llength $entries] > 0)}]
    $window.actions.open configure -state [expr {$canOpen ? "normal" : "disabled"}]
    set status "Selected $selectedLibrary: [llength $entries] references; state [dict get $library state]"
}
proc ::GX::ScientificLibraryManagerViewer::_selectEntry {} {
    variable window; variable entries; variable selectedEntry; variable status
    set selection [$window.body.entries curselection]
    if {![llength $selection]} return
    set selectedEntry [lindex $entries [lindex $selection 0]]
    set status "Selected reference $selectedEntry"
}
proc ::GX::ScientificLibraryManagerViewer::_install {} {
    variable window; variable selectedLibrary; variable status
    set package [tk_getOpenFile -parent $window -title "Install scientific library package" -filetypes {{{GX-TXT scientific libraries} {.zip}} {{All files} *}}]
    if {$package eq ""} return
    if {[catch {set result [::GX::ScientificLibraryManagerAPIv1::installLibrary $package]} problem]} {
        _report "Installation" $problem; return
    }
    set selectedLibrary [dict get $result library_id]
    _refresh
    set status "Installed $selectedLibrary [dict get $result version]"
}
proc ::GX::ScientificLibraryManagerViewer::_update {} {
    variable window; variable selectedLibrary; variable status
    if {$selectedLibrary eq ""} return
    set package [tk_getOpenFile -parent $window -title "Choose newer package for $selectedLibrary" -filetypes {{{GX-TXT scientific libraries} {.zip}} {{All files} *}}]
    if {$package eq ""} return
    if {[catch {set result [::GX::ScientificLibraryManagerAPIv1::updateLibrary $selectedLibrary $package]} problem]} {
        _report "Update" $problem; return
    }
    _refresh
    set status "Updated $selectedLibrary to [dict get $result version]"
}
proc ::GX::ScientificLibraryManagerViewer::_verify {} {
    variable selectedLibrary; variable status
    if {$selectedLibrary eq ""} return
    if {[catch {set result [::GX::ScientificLibraryManagerAPIv1::verifyLibrary $selectedLibrary]} problem]} {
        _report "Verification" $problem; return
    }
    set status "Verified $selectedLibrary at [dict get $result verified_at]"
}
proc ::GX::ScientificLibraryManagerViewer::_remove {} {
    variable window; variable selectedLibrary; variable status
    if {$selectedLibrary eq ""} return
    if {[tk_messageBox -parent $window -icon question -type yesno -title "Remove library" -message "Remove managed scientific library $selectedLibrary? Saved references to this library will become unavailable."] ne "yes"} return
    set removed $selectedLibrary
    if {[catch {::GX::ScientificLibraryManagerAPIv1::removeLibrary $removed} problem]} {
        _report "Removal" $problem; return
    }
    set selectedLibrary ""
    _refresh
    set status "Removed $removed"
}
proc ::GX::ScientificLibraryManagerViewer::_openConsumer {} {
    variable selectedLibrary; variable selectedEntry
    if {$selectedLibrary eq ""} return
    if {[catch {
        set library [::GX::ScientificLibraryManagerAPIv1::openLibrary $selectedLibrary]
        set provider [::GX::ScientificLibraryManagerAPIv1::resolveLibraryProvider [dict get $library library_type]]
        if {[dict get $provider library_viewer_module] ne ""} {
            set context [dict create library_id $selectedLibrary]
            if {$selectedEntry ne ""} {dict set context entry_id $selectedEntry}
            ::GX::viewerOpen [dict get $provider library_viewer_module] [dict get $provider library_viewer_id] $context
        } elseif {[dict get $provider entry_viewer_module] ne ""} {
            if {$selectedEntry eq ""} {set selectedEntry [lindex [::GX::ScientificLibraryManagerAPIv1::listLibraryEntries $selectedLibrary] 0]}
            if {$selectedEntry eq ""} {error "This library contains no reference to open"}
            ::GX::ScientificLibraryManagerAPIv1::openLibraryEntry $selectedLibrary $selectedEntry
        } else {error "The provider for $selectedLibrary has no specialized viewer"}
    } problem]} {_report "Open" $problem}
}
proc ::GX::ScientificLibraryManagerViewer::_open {} {
    variable window; variable typeFilter; variable query; variable selectedLibrary
    variable selectedEntry; variable status
    package require Tk
    if {[winfo exists $window]} {raise $window; return $window}
    set typeFilter "All types"; set query ""; set selectedLibrary ""; set selectedEntry ""; set status "Ready"
    toplevel $window
    wm title $window "Scientific Library Manager"
    wm geometry $window 1180x760
    wm minsize $window 840 520
    ttk::frame $window.filter -padding 8
    ttk::label $window.filter.title -text "Scientific Library Manager" -font TkHeadingFont
    ttk::label $window.filter.typeLabel -text "Library type"
    ttk::combobox $window.filter.type -textvariable ::GX::ScientificLibraryManagerViewer::typeFilter -state readonly -width 32
    ttk::label $window.filter.searchLabel -text "Search libraries"
    ttk::entry $window.filter.search -textvariable ::GX::ScientificLibraryManagerViewer::query -width 28
    ttk::button $window.filter.searchButton -text "Search" -command ::GX::ScientificLibraryManagerViewer::_refresh
    pack $window.filter.title $window.filter.typeLabel $window.filter.type $window.filter.searchLabel $window.filter.search $window.filter.searchButton -side left -padx 5
    ttk::frame $window.actions -padding 8
    foreach {name label command} {
        install "Install..." _install verify "Verify" _verify update "Update..." _update
        remove "Remove..." _remove open "Open / use" _openConsumer refresh "Refresh" _refresh
    } {
        ttk::button $window.actions.$name -text $label -command ::GX::ScientificLibraryManagerViewer::$command
        pack $window.actions.$name -side left -padx 4
    }
    ttk::frame $window.body -padding 8
    ttk::label $window.body.libraryLabel -text "Installed libraries"
    listbox $window.body.list -exportselection 0 -width 52
    ttk::scrollbar $window.body.scroll -command [list $window.body.list yview]
    $window.body.list configure -yscrollcommand [list $window.body.scroll set]
    ttk::label $window.body.entryLabel -text "References"
    listbox $window.body.entries -exportselection 0 -width 28
    ttk::scrollbar $window.body.entryScroll -command [list $window.body.entries yview]
    $window.body.entries configure -yscrollcommand [list $window.body.entryScroll set]
    text $window.details -wrap word -state disabled -width 60
    text $window.providers -wrap word -state disabled -height 7
    ttk::label $window.statusBar -textvariable ::GX::ScientificLibraryManagerViewer::status -anchor w
    grid $window.filter -row 0 -column 0 -columnspan 3 -sticky ew
    grid $window.actions -row 1 -column 0 -columnspan 3 -sticky ew
    grid $window.body -row 2 -column 0 -sticky nsew
    grid $window.details -row 2 -column 1 -columnspan 2 -sticky nsew -padx 8 -pady 8
    grid $window.providers -row 3 -column 0 -columnspan 3 -sticky ew -padx 8
    grid $window.statusBar -row 4 -column 0 -columnspan 3 -sticky ew -padx 8 -pady 5
    grid $window.body.libraryLabel -row 0 -column 0 -sticky w
    grid $window.body.list -row 1 -column 0 -sticky nsew
    grid $window.body.scroll -row 1 -column 1 -sticky ns
    grid $window.body.entryLabel -row 2 -column 0 -sticky w
    grid $window.body.entries -row 3 -column 0 -sticky nsew
    grid $window.body.entryScroll -row 3 -column 1 -sticky ns
    grid rowconfigure $window 2 -weight 1
    grid columnconfigure $window 0 -weight 1
    grid columnconfigure $window 1 -weight 1
    grid columnconfigure $window 2 -weight 1
    grid rowconfigure $window.body 1 -weight 2
    grid rowconfigure $window.body 3 -weight 1
    grid columnconfigure $window.body 0 -weight 1
    bind $window.filter.type <<ComboboxSelected>> ::GX::ScientificLibraryManagerViewer::_refresh
    bind $window.filter.search <Return> ::GX::ScientificLibraryManagerViewer::_refresh
    bind $window.body.list <<ListboxSelect>> ::GX::ScientificLibraryManagerViewer::_select
    bind $window.body.entries <<ListboxSelect>> ::GX::ScientificLibraryManagerViewer::_selectEntry
    if {[catch {_refresh} problem]} {_report "Refresh" $problem}
    return $window
}
proc ::GX::ScientificLibraryManagerViewer::viewerDispatch {action scene} {
    switch -- $action {
        open - rerender {return [_open]}
        default {error "Unsupported Scientific Library Manager action '$action'"}
    }
}
::GX::viewerBackendRegister scientific_library_manager_tk ::GX::ScientificLibraryManagerViewer::viewerDispatch
