# Session-independent NMR reference spectrum presentation.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::NmrReferenceViewer {
    variable window .gx_nmr_reference
    variable libraryId ""
    variable entryId ""
    variable spectrum {}
    variable status "Select an NMR reference in Scientific Reference Library."
    variable ppmRange {}
}
proc ::GX::NmrReferenceViewer::_value {dictValue key} {
    return [expr {[dict exists $dictValue $key] ? [dict get $dictValue $key] : ""}]
}
proc ::GX::NmrReferenceViewer::_details {} {
    variable window; variable spectrum; variable libraryId; variable entryId
    if {$spectrum eq ""} {
        $window.header.details configure -text "No reference selected. Open a reference from Scientific Reference Library."
        $window.sourceFrame.source configure -state normal
        $window.sourceFrame.source delete 1.0 end
        $window.sourceFrame.source insert end "The viewer can be inspected without a Session."
        $window.sourceFrame.source configure -state disabled
        return
    }
    set meta [dict get $spectrum metadata]
    set provenance [dict get $spectrum provenance]
    set label "[_value $spectrum display_name]\nNucleus: [_value $meta nucleus]    Frequency: [_value $meta frequency_mhz] MHz    Solvent: [_value $meta solvent]\nShift reference: [_value $meta shift_reference]\nSample: [_value $meta sample]"
    $window.header.details configure -text $label
    set lines [list "Library: $libraryId" "Reference: $entryId" "Scientific spectrum SHA-256: [_value $spectrum spectrum_hash]" "Original JCAMP SHA-256: [_value $provenance original_sha256]"]
    foreach key {source citation license original_path source_archive_sha256 derived_processing processing_note} {
        if {[dict exists $provenance $key]} {lappend lines "$key: [dict get $provenance $key]"}
    }
    $window.sourceFrame.source configure -state normal
    $window.sourceFrame.source delete 1.0 end
    $window.sourceFrame.source insert end [join $lines "\n"]
    $window.sourceFrame.source configure -state disabled
}
proc ::GX::NmrReferenceViewer::_draw {} {
    variable window; variable spectrum; variable ppmRange
    if {![winfo exists $window]} {return}
    set canvas $window.plot
    $canvas delete all
    set width [winfo width $canvas]
    set height [winfo height $canvas]
    if {$width < 100 || $height < 100} {return}
    set left 60; set right [expr {$width-22}]; set top 18; set bottom [expr {$height-42}]
    $canvas create rectangle $left $top $right $bottom -outline #a8b2bf -fill white
    if {$spectrum eq ""} {
        $canvas create text [expr {$width/2}] [expr {$height/2}] -text "No NMR reference selected" -fill #64748b
        return
    }
    set x [dict get $spectrum x]; set y [dict get $spectrum y]
    if {![llength $x] || [llength $x] != [llength $y]} {return}
    set xmax [lindex [lsort -real $x] end]
    set xmin [lindex [lsort -real $x] 0]
    if {[llength $ppmRange] == 2} {lassign $ppmRange xmin xmax}
    if {$xmax <= $xmin} {return}
    set ymin Inf; set ymax -Inf
    foreach xv $x yv $y {
        if {$xv < $xmin || $xv > $xmax} continue
        if {$yv < $ymin} {set ymin $yv}
        if {$yv > $ymax} {set ymax $yv}
    }
    if {$ymin eq "Inf" || $ymax eq "-Inf"} {return}
    if {$ymax <= $ymin} {set ymax [expr {$ymin+1.0}]}
    set span [expr {$ymax-$ymin}]
    set ymin [expr {$ymin-0.04*$span}]; set ymax [expr {$ymax+0.04*$span}]
    # Preserve narrow peaks by drawing each pixel column's minimum and maximum.
    array set low {}
    array set high {}
    foreach xv $x yv $y {
        if {$xv < $xmin || $xv > $xmax} continue
        set column [expr {int(($xmax-$xv)*($right-$left)/double($xmax-$xmin))}]
        if {![info exists low($column)] || $yv < $low($column)} {set low($column) $yv}
        if {![info exists high($column)] || $yv > $high($column)} {set high($column) $yv}
    }
    foreach column [lsort -integer [array names low]] {
        set px [expr {$left+$column}]
        set pyLow [expr {$bottom-($low($column)-$ymin)*($bottom-$top)/double($ymax-$ymin)}]
        set pyHigh [expr {$bottom-($high($column)-$ymin)*($bottom-$top)/double($ymax-$ymin)}]
        $canvas create line $px $pyLow $px $pyHigh -fill #1d4ed8 -width 1.2
    }
    for {set i 0} {$i <= 5} {incr i} {
        set px [expr {$left+($right-$left)*$i/5.0}]
        set ppm [expr {$xmax-($xmax-$xmin)*$i/5.0}]
        $canvas create line $px $bottom $px [expr {$bottom+5}] -fill #64748b
        $canvas create text $px [expr {$bottom+18}] -text [format %.1f $ppm] -fill #334155
    }
    $canvas create text [expr {($left+$right)/2}] [expr {$height-10}] -text "Chemical shift (ppm)  ← decreasing" -fill #334155
}
proc ::GX::NmrReferenceViewer::_load {library entry} {
    variable libraryId; variable entryId; variable spectrum; variable status; variable ppmRange
    if {$library eq "" || $entry eq ""} {return}
    set info [::GX::ScientificLibraryManagerAPIv1::getLibraryInfo $library]
    if {[dict get $info library_type] ne "spectroscopy.nmr.reference"} {error "Selected library is not an NMR reference library"}
    set data [::GX::ScientificLibraryManagerAPIv1::readLibrarySpectrum $library $entry]
    if {[dict get $data spectrum_kind] ne "NMR" || [dict get $data x_unit] ne "ppm"} {error "Selected entry is not a 1-D NMR spectrum"}
    set libraryId $library; set entryId $entry; set spectrum $data; set ppmRange {}
    set status "Viewing $entry from $library"
    _details
    _draw
}
proc ::GX::NmrReferenceViewer::_open {scene} {
    variable window; variable libraryId; variable entryId; variable spectrum; variable status
    package require Tk
    set context [expr {[dict exists $scene open_context] ? [dict get $scene open_context] : {}}]
    set requestedLibrary [_value $context library_id]
    set requestedEntry [_value $context entry_id]
    if {[winfo exists $window]} {
        if {$requestedLibrary ne "" && $requestedEntry ne ""} {_load $requestedLibrary $requestedEntry}
        raise $window
        return $window
    }
    set libraryId ""; set entryId ""; set spectrum {}; set status "Select an NMR reference in Scientific Reference Library."
    toplevel $window
    wm title $window "NMR Reference Spectrum Viewer"
    wm geometry $window 950x680
    wm minsize $window 680 470
    ttk::frame $window.header -padding 10
    ttk::label $window.header.title -text "NMR Reference Spectrum" -font TkHeadingFont
    ttk::label $window.header.details -text "" -wraplength 800 -justify left
    pack $window.header.title -anchor w
    pack $window.header.details -anchor w -fill x -pady {6 0}
    canvas $window.plot -background white -highlightthickness 0
    ttk::labelframe $window.sourceFrame -text "Source and provenance" -padding 5
    text $window.sourceFrame.source -wrap word -height 8 -state disabled -font TkFixedFont
    pack $window.sourceFrame.source -fill both -expand 1
    ttk::label $window.statusBar -textvariable ::GX::NmrReferenceViewer::status -anchor w
    grid $window.header -row 0 -column 0 -sticky ew
    grid $window.plot -row 1 -column 0 -sticky nsew -padx 10
    grid $window.sourceFrame -row 2 -column 0 -sticky nsew -padx 10 -pady 7
    grid $window.statusBar -row 3 -column 0 -sticky ew -padx 10 -pady 4
    grid rowconfigure $window 1 -weight 3
    grid rowconfigure $window 2 -weight 1
    grid columnconfigure $window 0 -weight 1
    bind $window.plot <Configure> ::GX::NmrReferenceViewer::_draw
    _details
    if {$requestedLibrary ne "" && $requestedEntry ne ""} {_load $requestedLibrary $requestedEntry}
    return $window
}
proc ::GX::NmrReferenceViewer::viewerDispatch {action scene} {
    switch -- $action {
        open - rerender {return [_open $scene]}
        default {error "Unsupported NMR Reference Viewer action '$action'"}
    }
}
::GX::viewerBackendRegister nmr_reference_tk ::GX::NmrReferenceViewer::viewerDispatch
