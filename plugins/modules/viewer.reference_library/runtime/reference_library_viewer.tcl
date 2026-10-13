# Generic managed scientific reference library browser.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::ReferenceLibraryViewer {
    variable window .gx_reference_library
    variable libraryId ""
    variable entryId ""
    variable query ""
    variable status "Ready"
    variable allEntries {}
    variable visibleEntries {}
    variable entryViewerAvailable 0
    variable libraryViewerAvailable 0
}

proc ::GX::ReferenceLibraryViewer::_display {widget value} {
    $widget configure -state normal
    $widget delete 1.0 end
    $widget insert end $value
    $widget configure -state disabled
}
proc ::GX::ReferenceLibraryViewer::_format {title data} {
    set lines [list $title]
    foreach key [lsort -dictionary [dict keys $data]] {
        set value [dict get $data $key]
        if {$value ne ""} {lappend lines "$key: $value"}
    }
    return [join $lines "\n"]
}
proc ::GX::ReferenceLibraryViewer::_libraries {} {
    return [::GX::ScientificLibraryManagerAPIv1::listInstalledLibraries]
}
proc ::GX::ReferenceLibraryViewer::_refreshLibraries {} {
    variable window; variable libraryId; variable entryId; variable status
    variable entryViewerAvailable; variable libraryViewerAvailable
    set libraries [_libraries]
    set labels {}
    foreach item $libraries {lappend labels [dict get $item library_id]}
    $window.left.library configure -values $labels
    if {$libraryId ni $labels} {set libraryId [lindex $labels 0]}
    if {$libraryId eq ""} {
        foreach action {update remove verify} {$window.toolbar.$action configure -state disabled}
        set entryViewerAvailable 0
        set libraryViewerAvailable 0
        set entryId ""
        $window.left.entries delete 0 end
        _display $window.info "No managed scientific reference library is installed. Select Install library to add one."
        _display $window.entryInfo "Select a reference to inspect its metadata and provenance."
        set status "No library installed"
        $window.left.open configure -state disabled
        return
    }
    foreach action {update remove verify} {$window.toolbar.$action configure -state normal}
    _selectLibrary
}
proc ::GX::ReferenceLibraryViewer::_selectLibrary {} {
    variable window; variable libraryId; variable entryId; variable allEntries; variable status
    variable entryViewerAvailable; variable libraryViewerAvailable
    if {$libraryId eq ""} {return}
    set info [::GX::ScientificLibraryManagerAPIv1::getLibraryInfo $libraryId]
    set provider [::GX::ScientificLibraryManagerAPIv1::resolveLibraryProvider [dict get $info library_type]]
    set entryViewerAvailable [expr {[dict get $provider entry_viewer_module] ne "" &&
        [dict get $provider entry_viewer_id] ne ""}]
    set libraryViewerAvailable [expr {[dict get $provider library_viewer_module] ne "" &&
        [dict get $provider library_viewer_id] ne ""}]
    $window.left.open configure -state disabled
    _display $window.info "[_format {Installed library} $info]\n\n[_format {Type provider} [dict remove $provider module]]"
    set allEntries [::GX::ScientificLibraryManagerAPIv1::listLibraryEntries $libraryId]
    set entryId ""
    _display $window.entryInfo "Select a reference to inspect its metadata and provenance."
    _filter
    set status "[llength $allEntries] references in [dict get $info display_name]"
}
proc ::GX::ReferenceLibraryViewer::_filter {} {
    variable window; variable query; variable allEntries; variable visibleEntries; variable libraryId
    set needle [string tolower [string trim $query]]
    set visibleEntries {}
    foreach id $allEntries {
        if {$needle eq "" || [string match "*$needle*" [string tolower $id]]} {
            lappend visibleEntries $id
            continue
        }
        # The current manager exposes full entry reads, not a metadata-only query.
        # Search is button-triggered so this cost is explicit to the user.
        if {[catch {set entry [::GX::ScientificLibraryManagerAPIv1::readLibrarySpectrum $libraryId $id]}]} continue
        set haystack [string tolower "[dict get $entry display_name] [dict get $entry metadata] [dict get $entry provenance]"]
        if {[string first $needle $haystack] >= 0} {lappend visibleEntries $id}
    }
    $window.left.entries delete 0 end
    foreach id $visibleEntries {$window.left.entries insert end $id}
}
proc ::GX::ReferenceLibraryViewer::_selectEntry {} {
    variable window; variable libraryId; variable entryId; variable visibleEntries; variable status
    variable entryViewerAvailable; variable libraryViewerAvailable
    set selection [$window.left.entries curselection]
    if {![llength $selection]} {return}
    set entryId [lindex $visibleEntries [lindex $selection 0]]
    if {[catch {set spectrum [::GX::ScientificLibraryManagerAPIv1::readLibrarySpectrum $libraryId $entryId]} problem]} {
        _display $window.entryInfo "Unable to read reference: $problem"
        set status "Reference read failed"
        return
    }
    set summary [dict remove $spectrum x y metadata provenance]
    set content "[_format {Reference identity} $summary]\n\n[_format {Entity and experiment metadata} [dict get $spectrum metadata]]\n\n[_format {Source and processing provenance} [dict get $spectrum provenance]]"
    _display $window.entryInfo $content
    set status "Selected $entryId: [llength [dict get $spectrum x]] samples"
    if {$entryViewerAvailable || $libraryViewerAvailable} {
        $window.left.open configure -state normal
    }
}
proc ::GX::ReferenceLibraryViewer::_openEntry {} {
    variable libraryId; variable entryId; variable window
    if {$libraryId eq "" || $entryId eq ""} {return}
    if {[catch {
        set library [::GX::ScientificLibraryManagerAPIv1::openLibrary $libraryId]
        set provider [::GX::ScientificLibraryManagerAPIv1::resolveLibraryProvider [dict get $library library_type]]
        if {[dict get $provider entry_viewer_module] ne ""} {
            ::GX::ScientificLibraryManagerAPIv1::openLibraryEntry $libraryId $entryId
        } elseif {[dict get $provider library_viewer_module] ne ""} {
            ::GX::viewerOpen [dict get $provider library_viewer_module] \
                [dict get $provider library_viewer_id] \
                [dict create library_id $libraryId entry_id $entryId]
        } else {
            error "No specialized viewer is registered for $libraryId"
        }
    } problem]} {
        tk_messageBox -parent $window -icon error -title "Open reference failed" -message $problem
    }
}
proc ::GX::ReferenceLibraryViewer::_install {} {
    variable window; variable status
    set path [tk_getOpenFile -parent $window -title "Install scientific reference library" -filetypes {{{GX-TXT scientific library} {.zip}} {{All files} *}}]
    if {$path eq ""} {return}
    if {[catch {set result [::GX::ScientificLibraryManagerAPIv1::installLibrary $path]} problem]} {
        tk_messageBox -parent $window -icon error -title "Library installation failed" -message $problem
        return
    }
    set status "Installed [dict get $result display_name] [dict get $result version]"
    _refreshLibraries
}
proc ::GX::ReferenceLibraryViewer::_update {} {
    variable window; variable libraryId; variable status
    if {$libraryId eq ""} {return}
    set path [tk_getOpenFile -parent $window -title "Choose newer version of $libraryId" -filetypes {{{GX-TXT scientific library} {.zip}} {{All files} *}}]
    if {$path eq ""} {return}
    if {[catch {set result [::GX::ScientificLibraryManagerAPIv1::updateLibrary $libraryId $path]} problem]} {
        tk_messageBox -parent $window -icon error -title "Library update failed" -message $problem
        return
    }
    set status "Updated [dict get $result library_id] to [dict get $result version]"
    _refreshLibraries
}
proc ::GX::ReferenceLibraryViewer::_remove {} {
    variable window; variable libraryId; variable status
    if {$libraryId eq ""} {return}
    if {[tk_messageBox -parent $window -type yesno -icon question -title "Remove library" -message "Remove managed library $libraryId?"] ne "yes"} {return}
    if {[catch {::GX::ScientificLibraryManagerAPIv1::removeLibrary $libraryId} problem]} {
        tk_messageBox -parent $window -icon error -title "Library removal failed" -message $problem
        return
    }
    set status "Removed $libraryId"
    set libraryId ""
    _refreshLibraries
}
proc ::GX::ReferenceLibraryViewer::_verify {} {
    variable window; variable libraryId; variable status
    if {$libraryId eq ""} {return}
    if {[catch {set result [::GX::ScientificLibraryManagerAPIv1::verifyLibrary $libraryId]} problem]} {
        tk_messageBox -parent $window -icon error -title "Library verification failed" -message $problem
        return
    }
    set status "Verified $libraryId at [dict get $result verified_at]"
}
proc ::GX::ReferenceLibraryViewer::_open {} {
    variable window; variable libraryId; variable entryId; variable query; variable status
    package require Tk
    if {[winfo exists $window]} {raise $window; return $window}
    set libraryId ""; set entryId ""; set query ""; set status "Ready"
    toplevel $window
    wm title $window "Scientific Reference Library"
    wm geometry $window 1120x730
    wm minsize $window 850 520
    ttk::frame $window.toolbar -padding 8
    ttk::label $window.toolbar.title -text "Scientific Reference Library" -font TkHeadingFont
    ttk::button $window.toolbar.install -text "Install library..." -command ::GX::ReferenceLibraryViewer::_install
    ttk::button $window.toolbar.update -text "Update..." -command ::GX::ReferenceLibraryViewer::_update
    ttk::button $window.toolbar.remove -text "Remove..." -command ::GX::ReferenceLibraryViewer::_remove
    ttk::button $window.toolbar.verify -text "Verify hashes" -command ::GX::ReferenceLibraryViewer::_verify
    pack $window.toolbar.title -side left -padx {0 20}
    foreach child {install update remove verify} {pack $window.toolbar.$child -side left -padx 3}
    ttk::frame $window.left -padding 8
    ttk::label $window.left.libraryLabel -text "Installed library"
    ttk::combobox $window.left.library -textvariable ::GX::ReferenceLibraryViewer::libraryId -state readonly -width 42
    ttk::label $window.left.searchLabel -text "Search references"
    ttk::entry $window.left.search -textvariable ::GX::ReferenceLibraryViewer::query
    ttk::button $window.left.find -text "Search" -command ::GX::ReferenceLibraryViewer::_filter
    listbox $window.left.entries -selectmode browse -exportselection 0 -width 42
    ttk::scrollbar $window.left.entryScroll -command [list $window.left.entries yview]
    $window.left.entries configure -yscrollcommand [list $window.left.entryScroll set]
    ttk::button $window.left.open -text "Open in specialized viewer" -state disabled -command ::GX::ReferenceLibraryViewer::_openEntry
    text $window.info -wrap word -state disabled -width 48
    text $window.entryInfo -wrap word -state disabled -width 58
    ttk::label $window.statusBar -textvariable ::GX::ReferenceLibraryViewer::status -anchor w
    grid $window.toolbar -row 0 -column 0 -columnspan 3 -sticky ew
    grid $window.left.libraryLabel -row 0 -column 0 -sticky w
    grid $window.left.library -row 1 -column 0 -sticky ew -pady 4
    grid $window.left.searchLabel -row 2 -column 0 -sticky w
    grid $window.left.search -row 3 -column 0 -sticky ew
    grid $window.left.find -row 4 -column 0 -sticky ew -pady 4
    grid $window.left.entries -row 5 -column 0 -sticky nsew
    grid $window.left.entryScroll -row 5 -column 1 -sticky ns
    grid $window.left.open -row 6 -column 0 -sticky ew -pady 6
    grid $window.left -row 1 -column 0 -sticky nsew
    grid $window.info -row 1 -column 1 -sticky nsew -padx 5 -pady 8
    grid $window.entryInfo -row 1 -column 2 -sticky nsew -padx {5 8} -pady 8
    grid $window.statusBar -row 2 -column 0 -columnspan 3 -sticky ew -padx 8 -pady 5
    grid columnconfigure $window 0 -weight 1
    grid columnconfigure $window 1 -weight 1
    grid columnconfigure $window 2 -weight 2
    grid rowconfigure $window 1 -weight 1
    grid rowconfigure $window.left 5 -weight 1
    grid columnconfigure $window.left 0 -weight 1
    bind $window.left.library <<ComboboxSelected>> ::GX::ReferenceLibraryViewer::_selectLibrary
    bind $window.left.entries <<ListboxSelect>> ::GX::ReferenceLibraryViewer::_selectEntry
    bind $window.left.search <Return> ::GX::ReferenceLibraryViewer::_filter
    _refreshLibraries
    return $window
}
proc ::GX::ReferenceLibraryViewer::viewerDispatch {action scene} {
    switch -- $action {
        open - rerender {return [_open]}
        default {error "Unsupported Scientific Reference Library action '$action'"}
    }
}
::GX::viewerBackendRegister reference_library_tk ::GX::ReferenceLibraryViewer::viewerDispatch
