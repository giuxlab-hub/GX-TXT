# Managed Viewer UI for the public CORE Scientific Spectrum Import API v1.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SpectralLibraryViewer::ImportUI {
    variable window .gx_spectrum_import
    variable jobs {}
    variable selected ""
    variable form
    variable libraryId ""
    variable newId ""
    variable newName ""
    variable newVersion "1.0.0"
    variable newLicense "user-owned"
    variable status "Choose CSV or JCAMP-DX source files. Inspect and confirm every interpretation before importing."
    variable fields {enabled spectrum_id display_name entity_id compound_name cas phase method spectrum_kind x_quantity x_unit y_quantity y_representation y_unit x_column y_column delimiter header}
}
proc ::GX::SpectralLibraryViewer::ImportUI::_installTumRefimp {{sourceOverride ""}} {
    variable status
    set expected 3ec55d86481da93b73f5f9f46e0c6d7c3d941165fd45beefeb84fb1305a0d19c
    set libraryId tum.refimp.ftir.2022
    set root [::GX::ReferenceLibraryAPIv1::root]
    set dataRoot [file dirname $root]
    set downloads [file join $dataRoot source_downloads tum.refimp.2022]
    set attempt 0
    set incoming [file join $downloads ".incoming-[pid]-$attempt"]
    while {[file exists $incoming]} {
        incr attempt
        set incoming [file join $downloads ".incoming-[pid]-$attempt"]
    }
    file mkdir $incoming
    set sourceFile [file join $incoming FTIR_MP_references.csv]
    set status "Checking official TUM RefIMP 2022 source; the original is staged before import..."
    update idletasks
    if {$sourceOverride eq ""} {
        set previous [expr {[info exists ::env(RSYNC_PASSWORD)] ? $::env(RSYNC_PASSWORD) : ""}]
        set hadPassword [info exists ::env(RSYNC_PASSWORD)]
        set ::env(RSYNC_PASSWORD) m1656656
        try {
            exec rsync --timeout=30 --contimeout=15 \
                rsync://m1656656@dataserv.ub.tum.de/m1656656/FTIR_MP_references.csv $incoming/
        } finally {
            if {$hadPassword} { set ::env(RSYNC_PASSWORD) $previous } else { unset ::env(RSYNC_PASSWORD) }
        }
    } else {
        if {![file isfile $sourceOverride]} { error "Chosen source file is missing" }
        file copy -- $sourceOverride $sourceFile
    }
    if {![file isfile $sourceFile]} { error "Official source download did not produce FTIR_MP_references.csv" }
    set actual [::GX::sha256File $sourceFile]
    if {$actual ne $expected} {
        error "TUM source bytes differ from the audited 2022 version ($actual). The staged original remains at $sourceFile for a new version/rights audit; the installed library was not changed."
    }
    set retained [file join $downloads FTIR_MP_references.csv]
    if {[file exists $retained]} {
        if {[::GX::sha256File $retained] ne $expected} {
            error "Existing local source differs from the audited 2022 bytes; no overwrite was performed"
        }
        file delete -- $sourceFile
    } else {
        file rename -- $sourceFile $retained
    }
    file delete -- $incoming
    if {[file exists [::GX::ReferenceLibraryAPIv1::libraryPath $libraryId]]} {
        set info [::GX::ReferenceLibraryAPIv1::validateLibrary $libraryId]
        set status "TUM RefIMP 2022 source is unchanged; installed library validated: [dict get $info content_hash]"
        return [dict create status already_installed library_id $libraryId content_hash [dict get $info content_hash]]
    }
    set exportRoot [file join $dataRoot reference_library_exports]
    file mkdir $exportRoot
    set exportPath [file join $exportRoot tum.refimp.ftir.2022.gxsrl.zip]
    if {[file exists $exportPath]} { error "Portable export already exists without installed library: $exportPath" }
    set adapter [file join $::GX::scriptDir tools reference_adapters refimp_2022 install_refimp_library.tcl]
    if {![file isfile $adapter]} { error "Audited RefIMP 2022 adapter is missing" }
    set adapterOutput [exec tclsh $adapter $::GX::scriptDir $retained $exportPath 2>@1]
    set info [::GX::ReferenceLibraryAPIv1::validateLibrary $libraryId]
    if {[llength [::GX::ReferenceLibraryAPIv1::listSpectra $libraryId]] != 15} { error "Installed RefIMP reference count is not 15" }
    set status "Installed TUM RefIMP 2022: 15 licensed reference spectra; portable export $exportPath"
    set viewer .gx_spectral_library
    if {[winfo exists $viewer]} {
        $viewer.toolbar.library configure -values [::GX::ReferenceLibraryAPIv1::listLibraries]
        set ::GX::SpectralLibraryViewer::libraryId $libraryId
        ::GX::SpectralLibraryViewer::_libraryChanged
    }
    return [dict create status installed library_id $libraryId content_hash [dict get $info content_hash] adapter_output $adapterOutput]
}
proc ::GX::SpectralLibraryViewer::ImportUI::_publicSourceAction {} {
    variable status
    if {[catch {_installTumRefimp} problem]} { set status "Public source check/install failed: $problem" }
}
proc ::GX::SpectralLibraryViewer::ImportUI::_format {path} {
    switch -- [string tolower [file extension $path]] {
        .csv { return csv }
        .jdx - .dx - .jcm - .jcamp { return jcamp }
        default { error "Unsupported spectrum extension: [file extension $path]" }
    }
}
proc ::GX::SpectralLibraryViewer::ImportUI::_defaults {path} {
    set stem [file rootname [file tail $path]]
    set id [string tolower [regsub -all {[^A-Za-z0-9_.-]+} $stem -]]
    if {$id eq ""} { set id spectrum }
    set format [_format $path]
    set options [dict create enabled 1 spectrum_id $id display_name $stem entity_id "" compound_name "" cas "" phase "" method "" \
        spectrum_kind IR x_quantity wavenumber x_unit cm^-1 y_quantity absorbance y_representation absorbance y_unit 1 \
        x_column 1 y_column 2 delimiter auto header 1]
    if {$format eq "jcamp"} {
        # Blank interpretation fields ask the public parser to use JCAMP metadata.
        foreach key {spectrum_kind x_quantity x_unit y_quantity y_representation y_unit} { dict set options $key "" }
    }
    return $options
}
proc ::GX::SpectralLibraryViewer::ImportUI::_addPaths {paths} {
    variable jobs; variable window; variable selected; variable status
    _saveForm
    foreach path $paths {
        set path [file normalize $path]
        if {![file isfile $path]} { continue }
        if {[catch {_format $path}]} { continue }
        if {![dict exists $jobs $path]} { dict set jobs $path [dict create options [_defaults $path] status pending] }
    }
    _refreshList
    if {$selected eq "" && [dict size $jobs]} {
        set first [lindex [dict keys $jobs] 0]
        $window.left.files selection set $first
        _selectionChanged
    }
    set status "[dict size $jobs] source file(s) queued. Select each file, inspect its preview, and confirm its metadata."
}
proc ::GX::SpectralLibraryViewer::ImportUI::_addFiles {} {
    set paths [tk_getOpenFile -parent .gx_spectrum_import -multiple 1 -filetypes {{Spectra {.csv .jdx .dx .jcm .jcamp}} {All files {*}}}]
    if {[llength $paths]} { _addPaths $paths }
}
proc ::GX::SpectralLibraryViewer::ImportUI::_addDirectory {} {
    set directory [tk_chooseDirectory -parent .gx_spectrum_import -mustexist 1]
    if {$directory eq ""} { return }
    set paths {}
    foreach extension {csv jdx dx jcm jcamp} {
        lappend paths {*}[glob -nocomplain -directory $directory *.$extension *.[string toupper $extension]]
    }
    _addPaths [lsort -unique $paths]
}
proc ::GX::SpectralLibraryViewer::ImportUI::_saveForm {} {
    variable selected; variable jobs; variable form; variable fields
    if {$selected eq "" || ![dict exists $jobs $selected]} { return }
    set options [dict get $jobs $selected options]
    foreach key $fields { dict set options $key $form($key) }
    dict set jobs $selected options $options
}
proc ::GX::SpectralLibraryViewer::ImportUI::_selectionChanged {} {
    variable selected; variable jobs; variable form; variable fields; variable window
    set next [lindex [$window.left.files selection] 0]
    if {$next eq "" || ![dict exists $jobs $next]} { return }
    _saveForm
    set selected $next
    set options [dict get $jobs $next options]
    foreach key $fields { set form($key) [dict get $options $key] }
    set preview "Source: $next\nFormat: [_format $next]\n\n"
    if {[catch {
        set handle [::open $next r]
        fconfigure $handle -encoding utf-8
        try {
            for {set i 0} {$i < 15 && [gets $handle line] >= 0} {incr i} { append preview "$line\n" }
        } finally { close $handle }
    } problem]} { append preview "Unable to read text preview: $problem" }
    $window.right.preview configure -state normal
    $window.right.preview delete 1.0 end
    $window.right.preview insert end $preview
    $window.right.preview configure -state disabled
}
proc ::GX::SpectralLibraryViewer::ImportUI::_refreshList {} {
    variable jobs; variable window
    if {![winfo exists $window]} { return }
    set tree $window.left.files
    set existing [$tree children {}]
    if {[llength $existing]} { $tree delete $existing }
    foreach path [dict keys $jobs] {
        set job [dict get $jobs $path]
        set options [dict get $job options]
        $tree insert {} end -id $path -text [file tail $path] \
            -values [list [_format $path] [dict get $options spectrum_id] [dict get $job status]]
    }
}
proc ::GX::SpectralLibraryViewer::ImportUI::_options {path} {
    variable jobs
    set raw [dict get $jobs $path options]
    set options [dict create]
    foreach key {spectrum_id display_name entity_id spectrum_kind x_quantity x_unit y_quantity y_representation y_unit} {
        if {[string trim [dict get $raw $key]] ne ""} { dict set options $key [string trim [dict get $raw $key]] }
    }
    if {[_format $path] eq "csv"} {
        foreach key {x_column y_column delimiter header} { dict set options $key [dict get $raw $key] }
    }
    set metadata [dict create]
    foreach key {compound_name cas phase method} {
        if {[string trim [dict get $raw $key]] ne ""} { dict set metadata $key [string trim [dict get $raw $key]] }
    }
    dict set options metadata $metadata
    return $options
}
proc ::GX::SpectralLibraryViewer::ImportUI::_inspect {} {
    variable selected; variable status
    if {$selected eq ""} { return }
    _saveForm
    if {[catch {set spectrum [::GX::SpectrumImportAPIv1::parse [_format $selected] $selected [_options $selected]]} problem]} {
        set status "Preview failed: $problem"
        return -code error $problem
    }
    set status "Confirmed [dict get $spectrum sample_count] samples; X [dict get $spectrum x_min]..[dict get $spectrum x_max] [dict get $spectrum x_unit]; Y [dict get $spectrum y_representation]."
    _drawPreview $spectrum
    return $spectrum
}
proc ::GX::SpectralLibraryViewer::ImportUI::_drawPreview {spectrum} {
    variable window
    set canvas $window.right.plot
    $canvas delete all
    set width [winfo width $canvas]
    if {$width < 200} { set width 550 }
    set height 115
    set xs [dict get $spectrum x]
    set ys [dict get $spectrum y]
    set xmin [dict get $spectrum x_min]
    set xmax [dict get $spectrum x_max]
    set ymin [lindex $ys 0]
    set ymax $ymin
    foreach y $ys {
        if {$y < $ymin} { set ymin $y }
        if {$y > $ymax} { set ymax $y }
    }
    if {$xmax == $xmin || $ymax == $ymin} { return }
    $canvas create line 30 10 30 90 [expr {$width-10}] 90 -fill #666666
    set points {}
    set step [expr {max(1, [llength $xs] / 2000)}]
    for {set i 0} {$i < [llength $xs]} {incr i $step} {
        set x [lindex $xs $i]
        set y [lindex $ys $i]
        lappend points [expr {30.0+($x-$xmin)/($xmax-$xmin)*($width-40)}] \
            [expr {10.0+($ymax-$y)/($ymax-$ymin)*80}]
    }
    lappend points [expr {30.0+([lindex $xs end]-$xmin)/($xmax-$xmin)*($width-40)}] \
        [expr {10.0+($ymax-[lindex $ys end])/($ymax-$ymin)*80}]
    $canvas create line {*}$points -fill #1765c1 -width 2 -tags spectrum
    $canvas create text 30 103 -text [format %.2f $xmin] -anchor w
    $canvas create text [expr {$width-10}] 103 -text [format %.2f $xmax] -anchor e
}
proc ::GX::SpectralLibraryViewer::ImportUI::_import {} {
    variable jobs; variable libraryId; variable newId; variable newName; variable newVersion; variable newLicense; variable status
    _saveForm
    if {![dict size $jobs]} { error "Add at least one source spectrum" }
    set id [string trim $libraryId]
    if {$id eq ""} {
        set id [string trim $newId]
        if {$id eq "" || [string trim $newName] eq "" || [string trim $newVersion] eq ""} {
            error "Choose an existing library or enter new library ID, name, and version"
        }
        if {[string trim $newLicense] eq ""} { error "New library license/rights classification is required" }
        ::GX::ReferenceLibraryAPIv1::createLibrary [dict create library_id $id name [string trim $newName] \
            version [string trim $newVersion] owner user license [string trim $newLicense]]
    } else {
        set info [::GX::ReferenceLibraryAPIv1::libraryInfo $id]
        if {![dict exists $info owner] || [dict get $info owner] ne "user"} {
            error "Only user-owned libraries can be modified through this import dialog"
        }
    }
    set imported 0; set failed 0
    foreach path [dict keys $jobs] {
        if {[dict get $jobs $path status] eq "imported"} {continue}
        set raw [dict get $jobs $path options]
        if {![dict get $raw enabled]} { dict set jobs $path status skipped; continue }
        if {[catch {
            set options [_options $path]
            set spectrum [::GX::SpectrumImportAPIv1::parse [_format $path] $path $options]
            set entity [string trim [dict get $raw entity_id]]
            if {$entity ne ""} {
                set entityInfo [dict create display_name [expr {[dict get $raw compound_name] ne "" ? [dict get $raw compound_name] : $entity}]]
                foreach key {compound_name cas phase} {
                    if {[dict get $raw $key] ne ""} { dict set entityInfo $key [dict get $raw $key] }
                }
                ::GX::ReferenceLibraryAPIv1::upsertEntity $id $entity $entityInfo
            }
            ::GX::ReferenceLibraryAPIv1::addSpectrum $id $spectrum
        } problem]} {
            dict set jobs $path status "failed: $problem"
            incr failed
        } else {
            dict set jobs $path status imported
            incr imported
        }
    }
    _refreshList
    set status "Library $id: $imported imported, $failed failed. Status is shown per source file."
    # Refresh the visible Viewer immediately; this library is globally persistent.
    set viewer .gx_spectral_library
    if {[winfo exists $viewer]} {
        $viewer.toolbar.library configure -values [::GX::ReferenceLibraryAPIv1::listLibraries]
        set ::GX::SpectralLibraryViewer::libraryId $id
        ::GX::SpectralLibraryViewer::_libraryChanged
    }
    return [dict create library_id $id imported $imported failed $failed]
}
proc ::GX::SpectralLibraryViewer::ImportUI::open {} {
    variable window; variable jobs; variable selected; variable form; variable fields
    variable libraryId; variable newId; variable newName; variable newVersion; variable newLicense; variable status
    package require Tk
    if {[winfo exists $window]} { raise $window; return $window }
    set jobs {}; set selected ""; set libraryId ""; set newId ""; set newName ""; set newVersion 1.0.0
    set newLicense user-owned
    foreach key $fields { set form($key) "" }
    set status "Choose CSV or JCAMP-DX source files. Inspect and confirm every interpretation before importing."
    toplevel $window
    wm title $window "GX-TXT | Import Scientific Spectra"
    wm geometry $window 1050x735
    wm minsize $window 900 620
    ttk::frame $window.top
    pack $window.top -side top -fill x -padx 8 -pady 6
    ttk::button $window.top.files -text "Add files..." -command ::GX::SpectralLibraryViewer::ImportUI::_addFiles
    ttk::button $window.top.directory -text "Add directory..." -command ::GX::SpectralLibraryViewer::ImportUI::_addDirectory
    ttk::button $window.top.public -text "Check / install TUM RefIMP..." -command ::GX::SpectralLibraryViewer::ImportUI::_publicSourceAction
    ttk::label $window.top.libraryLabel -text "Destination library"
    ttk::combobox $window.top.library -textvariable ::GX::SpectralLibraryViewer::ImportUI::libraryId \
        -values [linsert [::GX::ReferenceLibraryAPIv1::listLibraries] 0 ""] -state readonly -width 32
    foreach widget {files directory public libraryLabel library} { pack $window.top.$widget -side left -padx 4 }
    ttk::frame $window.create
    pack $window.create -side top -fill x -padx 8
    foreach {key label width} {newId {New library ID} 20 newName Name 24 newVersion Version 8 newLicense License/rights 15} {
        ttk::label $window.create.${key}Label -text $label
        ttk::entry $window.create.$key -textvariable ::GX::SpectralLibraryViewer::ImportUI::$key -width $width
        pack $window.create.${key}Label $window.create.$key -side left -padx 3
    }
    ttk::panedwindow $window.body -orient horizontal
    pack $window.body -side top -fill both -expand 1 -padx 8 -pady 6
    ttk::frame $window.left
    ttk::frame $window.right
    $window.body add $window.left -weight 1
    $window.body add $window.right -weight 3
    ttk::treeview $window.left.files -columns {format id status} -show {tree headings} -selectmode browse
    $window.left.files heading #0 -text Source
    foreach column {format id status} { $window.left.files heading $column -text $column }
    $window.left.files column #0 -width 180
    $window.left.files column format -width 60
    $window.left.files column id -width 115
    $window.left.files column status -width 90
    pack $window.left.files -fill both -expand 1
    ttk::frame $window.right.fields
    pack $window.right.fields -side top -fill x
    set i 0
    foreach {key label} {enabled Enabled spectrum_id {Spectrum ID} display_name {Display name} entity_id {Entity ID} compound_name {Compound/material} cas CAS phase Phase method Method spectrum_kind Kind x_quantity {X quantity} x_unit {X unit} y_quantity {Y quantity} y_representation {Y representation} y_unit {Y unit} x_column {CSV X column} y_column {CSV Y column} delimiter {CSV delimiter} header {CSV header 1/0}} {
        set row [expr {$i / 2}]; set pair [expr {$i % 2}]
        ttk::label $window.right.fields.${key}Label -text $label
        if {$key eq "enabled"} {
            ttk::checkbutton $window.right.fields.$key -variable ::GX::SpectralLibraryViewer::ImportUI::form($key)
        } else {
            ttk::entry $window.right.fields.$key -textvariable ::GX::SpectralLibraryViewer::ImportUI::form($key) -width 24
        }
        grid $window.right.fields.${key}Label -row $row -column [expr {$pair*2}] -sticky w -padx 4 -pady 2
        grid $window.right.fields.$key -row $row -column [expr {$pair*2+1}] -sticky ew -padx 4 -pady 2
        incr i
    }
    grid columnconfigure $window.right.fields 1 -weight 1
    grid columnconfigure $window.right.fields 3 -weight 1
    ttk::label $window.right.previewLabel -text "Source preview (first 15 lines); Preview spectrum validates numerical interpretation"
    pack $window.right.previewLabel -side top -anchor w -pady 4
    text $window.right.preview -wrap none -height 13 -state disabled -font TkFixedFont
    pack $window.right.preview -side top -fill both -expand 1
    canvas $window.right.plot -height 115 -background white -highlightthickness 1
    pack $window.right.plot -side top -fill x -pady 4
    ttk::frame $window.actions
    pack $window.actions -side top -fill x -padx 8 -pady 4
    ttk::button $window.actions.preview -text "Preview spectrum" -command {catch {::GX::SpectralLibraryViewer::ImportUI::_inspect}}
    ttk::button $window.actions.import -text "Import enabled files" -command {if {[catch {::GX::SpectralLibraryViewer::ImportUI::_import} problem]} {set ::GX::SpectralLibraryViewer::ImportUI::status "Import failed: $problem"}}
    ttk::button $window.actions.close -text Close -command [list destroy $window]
    pack $window.actions.preview $window.actions.import $window.actions.close -side left -padx 4
    ttk::label $window.status -textvariable ::GX::SpectralLibraryViewer::ImportUI::status -anchor w -wraplength 1000
    pack $window.status -side bottom -fill x -padx 8 -pady 4
    bind $window.left.files <<TreeviewSelect>> ::GX::SpectralLibraryViewer::ImportUI::_selectionChanged
    return $window
}
