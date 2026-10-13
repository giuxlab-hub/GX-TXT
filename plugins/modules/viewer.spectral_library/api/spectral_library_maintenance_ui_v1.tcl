# Scientific Spectral Library maintenance, using only versioned CORE APIs.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SpectralLibraryViewer::MaintenanceUI {
    variable dialog .gx_spectral_library_maintenance
    variable form
    variable sourceId ""
    variable spectrumId ""
}

proc ::GX::SpectralLibraryViewer::MaintenanceUI::_versionTarget {sourceId newId newVersion} {
    set api ::GX::ReferenceLibraryAPIv1
    ${api}::_safeId $sourceId
    ${api}::_safeId $newId
    if {$sourceId eq $newId} {error "Choose a new library ID; the source is immutable"}
    if {[string trim $newVersion] eq ""} {error "A new library version is required"}
    if {[file exists [${api}::libraryPath $newId]]} {error "The new library ID already exists"}
    set before [${api}::validateLibrary $sourceId]
    return $before
}

proc ::GX::SpectralLibraryViewer::MaintenanceUI::forkVersion {sourceId newId newVersion} {
    set api ::GX::ReferenceLibraryAPIv1
    set before [_versionTarget $sourceId $newId $newVersion]
    ${api}::forkLibraryVersion $sourceId $newId $newVersion
    set after [${api}::validateLibrary $newId]
    if {[dict get $after owner] ne "user" || [dict get $after forked_from_content_hash] ne [dict get $before content_hash]} {
        error "New user-owned library has invalid fork provenance"
    }
    if {[dict get [${api}::validateLibrary $sourceId] content_hash] ne [dict get $before content_hash]} {
        error "Source library changed during versioned fork"
    }
    return $after
}

proc ::GX::SpectralLibraryViewer::MaintenanceUI::updateReference {sourceId spectrumId newId newVersion displayName note replacementPath format csvOptions} {
    set api ::GX::ReferenceLibraryAPIv1
    set before [_versionTarget $sourceId $newId $newVersion]
    ${api}::_safeId $spectrumId
    if {[string trim $note] eq ""} {error "Document the reason and provenance for the update"}
    if {[string trim $displayName] eq ""} {error "Reference display name is required"}
    set original [${api}::readSpectrum $sourceId $spectrumId]
    if {$replacementPath eq ""} {
        set candidate $original
    } else {
        if {![file isfile $replacementPath]} {error "Replacement spectrum file does not exist"}
        if {$format eq "auto"} {
            set ext [string tolower [file extension $replacementPath]]
            set format [expr {$ext in {.jdx .dx .jcamp} ? "jcamp" : "csv"}]
        }
        if {$format ni {csv jcamp}} {error "Replacement format must be CSV or JCAMP"}
        set fields [dict create spectrum_id $spectrumId display_name $displayName \
            spectrum_kind [dict get $original spectrum_kind] \
            x_quantity [dict get $original x_quantity] x_unit [dict get $original x_unit] \
            y_quantity [dict get $original y_quantity] \
            y_representation [dict get $original y_representation] y_unit [dict get $original y_unit] \
            entity_id [dict get $original entity_id] \
            source_identity [file tail $replacementPath] source_hash [::GX::sha256File $replacementPath] \
            metadata [dict get $original metadata] provenance [dict get $original provenance]]
        if {$format eq "csv"} {
            foreach key {x_column y_column header delimiter} {
                if {![dict exists $csvOptions $key]} {error "CSV replacement option missing: $key"}
                dict set fields $key [dict get $csvOptions $key]
            }
        }
        set candidate [::GX::SpectrumImportAPIv1::parse $format $replacementPath $fields]
        foreach key {spectrum_kind x_quantity x_unit y_quantity y_representation y_unit} {
            if {[dict get $candidate $key] ne [dict get $original $key]} {
                error "Replacement changes $key; create a separate scientific reference instead"
            }
        }
    }
    dict set candidate display_name $displayName
    set metadata [dict get $candidate metadata]
    dict set metadata user_maintenance_note $note
    dict set candidate metadata $metadata
    set provenance [dict get $candidate provenance]
    dict set provenance maintenance_action versioned_reference_update
    dict set provenance maintenance_source_library_id $sourceId
    dict set provenance maintenance_source_content_hash [dict get $before content_hash]
    dict set provenance maintenance_source_spectrum_hash [dict get $original spectrum_hash]
    dict set provenance maintenance_note $note
    dict set candidate provenance $provenance
    set candidate [::GX::SpectrumAPIv1::create $candidate]
    ${api}::updateReference $sourceId $newId $newVersion $candidate
    set after [${api}::validateLibrary $newId]
    if {[dict get $after forked_from_content_hash] ne [dict get $before content_hash]} {
        error "Updated library lost source version provenance"
    }
    if {[dict get [${api}::validateLibrary $sourceId] content_hash] ne [dict get $before content_hash]} {
        error "Source library changed during reference update"
    }
    return $after
}

proc ::GX::SpectralLibraryViewer::MaintenanceUI::removeReference {sourceId spectrumId newId newVersion} {
    set api ::GX::ReferenceLibraryAPIv1
    set before [_versionTarget $sourceId $newId $newVersion]
    ${api}::_safeId $spectrumId
    if {[dict get $before owner] ne "user"} {
        error "Removal requires a user-owned library; fork this source first"
    }
    ${api}::removeUserReference $sourceId $newId $newVersion $spectrumId
    set after [${api}::validateLibrary $newId]
    if {[lsearch -exact [${api}::listSpectra $newId] $spectrumId] >= 0} {
        error "Removed reference remains in the new library"
    }
    if {[dict get [${api}::validateLibrary $sourceId] content_hash] ne [dict get $before content_hash]} {
        error "Source library changed during reference removal"
    }
    return $after
}

proc ::GX::SpectralLibraryViewer::MaintenanceUI::_browse {} {
    variable form
    set path [tk_getOpenFile -title "Replacement IR/UV reference spectrum" \
        -filetypes {{{CSV and JCAMP} {.csv .jdx .dx .jcamp}} {{All files} *}}]
    if {$path ne ""} {set form(path) $path}
}

proc ::GX::SpectralLibraryViewer::MaintenanceUI::_apply {action} {
    variable dialog
    variable form
    variable sourceId
    variable spectrumId
    try {
        set newId [string trim $form(new_id)]
        set newVersion [string trim $form(new_version)]
        set sourceInfo [::GX::ReferenceLibraryAPIv1::validateLibrary $sourceId]
        set summary "Source: $sourceId\nReference: $spectrumId\nSource hash: [dict get $sourceInfo content_hash]\nNew library: $newId\nNew version: $newVersion\nAction: $action"
        if {$action eq "update"} {append summary "\nReplacement file: $form(path)\nReason: $form(note)"}
        if {[tk_messageBox -parent $dialog -icon question -type yesno -title "Review versioned library change" -message $summary] ne "yes"} {
            return
        }
        switch -- $action {
            fork {set result [forkVersion $sourceId $newId $newVersion]}
            update {
                set csv [dict create x_column $form(x_column) y_column $form(y_column) \
                    header $form(header) delimiter $form(delimiter)]
                set result [updateReference $sourceId $spectrumId $newId $newVersion \
                    $form(display_name) $form(note) $form(path) $form(format) $csv]
            }
            remove {set result [removeReference $sourceId $spectrumId $newId $newVersion]}
            default {error "Unknown maintenance action"}
        }
        set ::GX::SpectralLibraryViewer::libraryId $newId
        set ::GX::SpectralLibraryViewer::selectedIds {}
        set ::GX::SpectralLibraryViewer::entityId ""
        set ::GX::SpectralLibraryViewer::statusText "Versioned $action created $newId; original $sourceId retained"
        $::GX::SpectralLibraryViewer::window.toolbar.library configure -values [::GX::SpectralLibraryViewer::_libraries]
        ::GX::SpectralLibraryViewer::_libraryChanged
        destroy $dialog
        tk_messageBox -icon info -title "Versioned library ready" \
            -message "Created $newId\nContent hash: [dict get $result content_hash]\nOriginal library retained."
    } on error {message options} {
        tk_messageBox -parent $dialog -icon error -title "Library maintenance failed" -message $message
    }
}

proc ::GX::SpectralLibraryViewer::MaintenanceUI::open {} {
    variable dialog
    variable form
    variable sourceId
    variable spectrumId
    set viewer $::GX::SpectralLibraryViewer::window
    set sourceId $::GX::SpectralLibraryViewer::libraryId
    if {$sourceId eq ""} {tk_messageBox -icon info -message "Select a reference library first"; return}
    set box $viewer.left.results
    set selected [$box curselection]
    if {[llength $selected] != 1} {
        tk_messageBox -icon info -message "Select exactly one reference spectrum to maintain"; return
    }
    set spectrumId [$box get [lindex $selected 0]]
    set api ::GX::ReferenceLibraryAPIv1
    set sourceInfo [${api}::validateLibrary $sourceId]
    set original [${api}::readSpectrum $sourceId $spectrumId]
    if {[winfo exists $dialog]} {destroy $dialog}
    set form(new_id) "user.[lindex [split $sourceId .] 0].[clock format [clock seconds] -format %Y%m%d%H%M%S]"
    set form(new_version) "[dict get $sourceInfo version].1"
    set form(display_name) [dict get $original display_name]
    set form(note) ""
    set form(path) ""
    set form(format) auto
    set form(x_column) 1
    set form(y_column) 2
    set form(header) 1
    set form(delimiter) ,
    toplevel $dialog
    wm title $dialog "Versioned reference maintenance"
    wm geometry $dialog 860x440
    wm minsize $dialog 750 420
    wm transient $dialog $viewer
    grid columnconfigure $dialog 1 -weight 1
    ttk::label $dialog.summary -text "Source: $sourceId  |  Reference: $spectrumId\nOwner: [dict get $sourceInfo owner]  |  SHA-256: [dict get $sourceInfo content_hash]" \
        -wraplength 720 -justify left
    grid $dialog.summary -row 0 -column 0 -columnspan 3 -sticky ew -padx 10 -pady 10
    set row 1
    foreach {label key} {{New library ID} new_id {New version} new_version {Reference display name} display_name {Reason / provenance note} note {Replacement spectrum file (optional)} path} {
        ttk::label $dialog.l$row -text $label
        ttk::entry $dialog.e$row -textvariable ::GX::SpectralLibraryViewer::MaintenanceUI::form($key)
        grid $dialog.l$row -row $row -column 0 -sticky e -padx 8 -pady 4
        grid $dialog.e$row -row $row -column 1 -sticky ew -padx 8 -pady 4
        if {$key eq "path"} {
            ttk::button $dialog.browse -text "Browse..." -command ::GX::SpectralLibraryViewer::MaintenanceUI::_browse
            grid $dialog.browse -row $row -column 2 -padx 8
        }
        incr row
    }
    ttk::label $dialog.fl -text "File format"
    ttk::combobox $dialog.format -textvariable ::GX::SpectralLibraryViewer::MaintenanceUI::form(format) \
        -values {auto csv jcamp} -state readonly -width 10
    grid $dialog.fl -row $row -column 0 -sticky e -padx 8
    grid $dialog.format -row $row -column 1 -sticky w -padx 8
    incr row
    ttk::frame $dialog.csv
    ttk::label $dialog.csv.label -text "CSV: X col / Y col / header rows / delimiter"
    pack $dialog.csv.label -side left -padx 4
    foreach {key width} {x_column 4 y_column 4 header 4 delimiter 5} {
        ttk::entry $dialog.csv.$key -textvariable ::GX::SpectralLibraryViewer::MaintenanceUI::form($key) -width $width
        pack $dialog.csv.$key -side left -padx 3
    }
    grid $dialog.csv -row $row -column 0 -columnspan 3 -sticky w -padx 8 -pady 6
    incr row
    ttk::label $dialog.explain -text "Every action creates a new user-owned library; the source remains intact. Update can change metadata or import a replacement CSV/JCAMP with the same spectral semantics. Removal is available only from a user-owned source; fork a public source first." \
        -wraplength 720 -justify left
    grid $dialog.explain -row $row -column 0 -columnspan 3 -sticky ew -padx 10 -pady 10
    incr row
    ttk::frame $dialog.actions
    ttk::button $dialog.actions.fork -text "Fork library" -command [list ::GX::SpectralLibraryViewer::MaintenanceUI::_apply fork]
    ttk::button $dialog.actions.update -text "Update reference" -command [list ::GX::SpectralLibraryViewer::MaintenanceUI::_apply update]
    ttk::button $dialog.actions.remove -text "Remove reference" -command [list ::GX::SpectralLibraryViewer::MaintenanceUI::_apply remove]
    ttk::button $dialog.actions.cancel -text "Cancel" -command [list destroy $dialog]
    if {[dict get $sourceInfo owner] ne "user"} {$dialog.actions.remove state disabled}
    pack $dialog.actions.fork $dialog.actions.update $dialog.actions.remove $dialog.actions.cancel -side left -padx 6
    grid $dialog.actions -row $row -column 0 -columnspan 3 -sticky w -padx 8 -pady 12
    return $dialog
}
