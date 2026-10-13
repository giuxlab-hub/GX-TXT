# SPDX-License-Identifier: GPL-3.0-or-later
# NMR-specific controls with graph rendering delegated to PLOT_DATASET_API_v3.
namespace eval ::GX::NmrViewer {
    variable selected ""
    variable overlay ""
    variable direction reverse
    variable window .nmr_spectrum_viewer
}

proc ::GX::NmrViewer::_session {} {
    if {![info exists ::GX::currentSession] || $::GX::currentSession eq ""} {
        error "NMR viewer requires an open Session"
    }
    return $::GX::currentSession
}
proc ::GX::NmrViewer::_metadata {id} {
    set session [_session]
    if {[catch {set data [::GX::datasetMetadataRead $session $id]}]} {return {}}
    return $data
}
proc ::GX::NmrViewer::_nucleus {id} {
    set md [_metadata $id]
    return [expr {[dict exists $md nmr.nucleus] ? [dict get $md nmr.nucleus] : ""}]
}
proc ::GX::NmrViewer::datasets {} {
    set ids {}
    if {[catch {set available [::GX::sessionInspectionDatasetIds]}]} {return {}}
    foreach id $available {
        if {[_nucleus $id] ne ""} {lappend ids $id}
    }
    return $ids
}
proc ::GX::NmrViewer::_processed {id} {
    set display "[regsub -all {[^A-Za-z0-9._-]} $id _].nmr.display"
    if {[lsearch -exact [::GX::sessionInspectionDatasetIds] $display] >= 0} {return $display}
    set candidate "[regsub -all {[^A-Za-z0-9._-]} $id _].nmr.processed"
    if {[lsearch -exact [::GX::sessionInspectionDatasetIds] $candidate] >= 0} {return $candidate}
    return $id
}
proc ::GX::NmrViewer::_peaks {id} {
    set candidate "[regsub -all {[^A-Za-z0-9._-]} $id _].nmr.peaks"
    if {[lsearch -exact [::GX::sessionInspectionDatasetIds] $candidate] >= 0} {return $candidate}
    return ""
}
proc ::GX::NmrViewer::_integrals {id} {
    set candidate "[regsub -all {[^A-Za-z0-9._-]} $id _].nmr.integrals"
    if {[lsearch -exact [::GX::sessionInspectionDatasetIds] $candidate] >= 0} {return $candidate}
    return ""
}
proc ::GX::NmrViewer::compatibleOverlays {id} {
    set nucleus [_nucleus $id]
    if {$nucleus eq ""} {error "Dataset '$id' is not an acquired NMR spectrum"}
    set out {}
    foreach other [datasets] {
        if {$other ne $id && [_nucleus $other] eq $nucleus} {lappend out $other}
    }
    return $out
}
proc ::GX::NmrViewer::_statePath {} {
    return [file join [_session] metadata nmr_spectrum_viewer.ini]
}
proc ::GX::NmrViewer::saveState {id {overlayId ""} {axisDirection reverse} {plotRef ""}} {
    if {$axisDirection ni {normal reverse}} {error "NMR axis direction must be normal or reverse"}
    if {[_nucleus $id] eq ""} {error "NMR source Dataset is unavailable"}
    if {$overlayId ne "" && $overlayId ni [compatibleOverlays $id]} {error "NMR overlay nucleus is incompatible"}
    set path [_statePath]
    file mkdir [file dirname $path]
    set channel [::open $path w]
    fconfigure $channel -encoding utf-8 -translation lf
    try {
        puts $channel "\[nmr_viewer\]"
        puts $channel "dataset_id=$id"
        puts $channel "overlay_dataset_id=$overlayId"
        puts $channel "axis_direction=$axisDirection"
        if {$plotRef ne ""} {
            puts $channel "plot_graph_id=[dict get $plotRef graph_id]"
            puts $channel "plot_variant_id=[dict get $plotRef variant_id]"
        }
    } finally {close $channel}
    ::GX::sessionPersistenceCommit
    return $path
}
proc ::GX::NmrViewer::loadState {} {
    if {[catch {_session}]} {return {}}
    set path [_statePath]
    if {![file isfile $path]} {return {}}
    set parsed [::GX::parseIni $path]
    set result [dict create]
    foreach key {dataset_id overlay_dataset_id axis_direction plot_graph_id plot_variant_id} {
        dict set result $key [::GX::descriptorValue $parsed nmr_viewer $key ""]
    }
    return $result
}
proc ::GX::NmrViewer::_plotApi {} {
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    foreach capability {plotspec graph_series axes_config render standalone_v2_editor} {
        ::GX::PlotDatasetAPIv3::requireCapability $capability
    }
}
proc ::GX::NmrViewer::_series {id index} {
    set data [_processed $id]
    set label "[_nucleus $id] $id"
    return [dict create id "nmr_$index" dataset_id $data \
        x_variable_id spectral_x y_variable_id spectral_y axis left kind line \
        label $label style [dict create line_width 1.3]]
}
proc ::GX::NmrViewer::createPlot {id {overlayId ""} {axisDirection reverse}} {
    if {$axisDirection ni {normal reverse}} {error "NMR axis direction must be normal or reverse"}
    if {[_nucleus $id] eq ""} {error "Dataset '$id' is not an acquired NMR spectrum"}
    if {$overlayId ne "" && $overlayId ni [compatibleOverlays $id]} {error "NMR overlay nucleus is incompatible"}
    _plotApi
    set series [list [_series $id 1]]
    if {$overlayId ne ""} {lappend series [_series $overlayId 2]}
    set peaks [_peaks $id]
    if {$peaks ne ""} {
        lappend series [dict create id nmr_peaks dataset_id $peaks \
            x_variable_id chemical_shift_ppm y_variable_id intensity \
            axis left kind scatter label {Detected peaks} \
            style [dict create marker_size 4]]
    }
    set md [_metadata $id]
    set title "NMR [_nucleus $id]: $id"
    if {[dict exists $md nmr.solvent] && [dict get $md nmr.solvent] ne ""} {
        append title " • [dict get $md nmr.solvent]"
    }
    set axes [dict create \
        x [dict create label {Chemical shift [ppm]} display_unit ppm scale linear direction $axisDirection] \
        y_left [dict create label {Relative intensity} display_unit 1 scale linear]]
    set panel [dict create id main title $title axes $axes series $series annotations {}]
    set spec [dict create schema PLOT_DATASET_PLOTSPEC_v2 graph_type cartesian_2d \
        graph_id plot.dataset.xy title $title defaults [dict create style [dict create]] \
        panels [list $panel] output [dict create]]
    set ref [::GX::PlotDatasetAPIv3::createPlotFromSpec $spec variant ""]
    saveState $id $overlayId $axisDirection $ref
    return $ref
}
proc ::GX::NmrViewer::openGraph {id {overlayId ""} {axisDirection reverse}} {
    set ref [createPlot $id $overlayId $axisDirection]
    ::GX::PlotDatasetAPIv3::render $ref
    return [::GX::PlotDatasetAPIv3::openEditor $ref]
}
proc ::GX::NmrViewer::_readColumns {id columns} {
    set handle [::GX::datasetAccessOpen [_session] $id]
    try {return [::GX::datasetAccessReadVariables $handle $columns]} \
        finally {::GX::datasetAccessClose $handle}
}
proc ::GX::NmrViewer::peakList {id} {
    set source [_peaks $id]
    if {$source eq ""} {return {}}
    set data [_readColumns $source {chemical_shift_ppm intensity prominence width_ppm}]
    set out {}
    foreach x [dict get $data chemical_shift_ppm values] \
            y [dict get $data intensity values] \
            p [dict get $data prominence values] \
            w [dict get $data width_ppm values] {
        lappend out [dict create ppm $x intensity $y prominence $p width_ppm $w]
    }
    return $out
}
proc ::GX::NmrViewer::integralList {id} {
    set source [_integrals $id]
    if {$source eq ""} {return {}}
    set data [_readColumns $source {region_min_ppm region_max_ppm integral}]
    set out {}
    foreach lo [dict get $data region_min_ppm values] \
            hi [dict get $data region_max_ppm values] \
            value [dict get $data integral values] {
        lappend out [dict create min_ppm $lo max_ppm $hi integral $value]
    }
    return $out
}
proc ::GX::NmrViewer::_refresh {} {
    variable selected
    variable overlay
    variable window
    if {![winfo exists $window]} {return}
    if {$selected eq "" || $selected ni [datasets]} {
        set selected ""
        set overlay ""
        set message "No NMR spectra are available in the current Session."
        $window.source configure -values {} -state disabled
        $window.overlay configure -values {} -state disabled
        $window.direction configure -state disabled
        $window.plot configure -state disabled
        $window.details configure -text $message
        $window.peaks delete [$window.peaks children {}]
        $window.integrals configure -text $message
        return
    }
    $window.source configure -state readonly
    $window.overlay configure -state readonly
    $window.direction configure -state readonly
    $window.plot configure -state normal
    set md [_metadata $selected]
    set summary "Nucleus: [_nucleus $selected]"
    foreach {key label} {nmr.observed_frequency_mhz {Frequency [MHz]} nmr.solvent Solvent \
            nmr.shift_reference Reference nmr.data_type {Source type} nmr.processing Processing \
            nmr.source_sha256 {Source SHA-256}} {
        if {[dict exists $md $key]} {append summary "\n$label: [dict get $md $key]"}
    }
    $window.details configure -text $summary
    $window.peaks delete [$window.peaks children {}]
    foreach peak [peakList $selected] {
        $window.peaks insert {} end -values [list \
            [format %.4f [dict get $peak ppm]] [format %.3g [dict get $peak intensity]] \
            [format %.3g [dict get $peak prominence]]]
    }
    set report ""
    foreach item [integralList $selected] {
        append report "[dict get $item min_ppm]–[dict get $item max_ppm] ppm: [dict get $item integral]\n"
    }
    if {$report eq ""} {set report "Run NMR Analysis to publish integrals."}
    $window.integrals configure -text $report
    $window.overlay configure -values [linsert [compatibleOverlays $selected] 0 ""]
    if {$overlay ne "" && $overlay ni [compatibleOverlays $selected]} {set overlay ""}
}
proc ::GX::NmrViewer::open {context} {
    variable selected
    variable overlay
    variable direction
    variable window
    package require Tk
    set ids [datasets]
    set saved [loadState]
    set selected [lindex $ids 0]
    if {[dict exists $saved dataset_id] && [dict get $saved dataset_id] in $ids} {
        set selected [dict get $saved dataset_id]
    }
    if {[dict exists $context open_context dataset_id] && [dict get $context open_context dataset_id] in $ids} {
        set selected [dict get $context open_context dataset_id]
    }
    set overlay ""
    if {$selected ne "" && [dict exists $saved overlay_dataset_id] && [dict get $saved overlay_dataset_id] in [compatibleOverlays $selected]} {
        set overlay [dict get $saved overlay_dataset_id]
    }
    set direction reverse
    if {[dict exists $saved axis_direction] && [dict get $saved axis_direction] in {normal reverse}} {
        set direction [dict get $saved axis_direction]
    }
    catch {destroy $window}
    toplevel $window
    wm title $window {NMR Spectrum Viewer}
    wm geometry $window 760x620+40+40
    ttk::label $window.title -text {NMR Spectrum Viewer — chemical shift (ppm)}
    ttk::label $window.source_label -text {NMR source}
    ttk::combobox $window.source -textvariable ::GX::NmrViewer::selected -values $ids -state readonly -width 48
    ttk::label $window.overlay_label -text {Compatible overlay}
    ttk::combobox $window.overlay -textvariable ::GX::NmrViewer::overlay -state readonly -width 48
    ttk::label $window.direction_label -text {ppm direction}
    ttk::combobox $window.direction -textvariable ::GX::NmrViewer::direction -values {reverse normal} -state readonly -width 12
    ttk::label $window.details -justify left -anchor w -wraplength 700
    ttk::button $window.plot -text {Open persistent NMR graph} -command {
        if {[catch {::GX::NmrViewer::openGraph $::GX::NmrViewer::selected $::GX::NmrViewer::overlay $::GX::NmrViewer::direction} problem]} {
            tk_messageBox -icon error -title {NMR graph} -message $problem
        }
    }
    ttk::label $window.peak_title -text {Detected peaks (analysis output)}
    ttk::treeview $window.peaks -columns {ppm intensity prominence} -show headings -height 10
    foreach {column label} {ppm {Shift [ppm]} intensity {Intensity} prominence {Prominence}} {
        $window.peaks heading $column -text $label
        $window.peaks column $column -width 140
    }
    ttk::label $window.integrals_title -text {Integration regions (analysis output)}
    ttk::label $window.integrals -justify left -anchor w
    grid $window.title -row 0 -column 0 -columnspan 2 -sticky w -padx 10 -pady 8
    grid $window.source_label -row 1 -column 0 -sticky w -padx 10
    grid $window.source -row 1 -column 1 -sticky ew -padx 10
    grid $window.overlay_label -row 2 -column 0 -sticky w -padx 10
    grid $window.overlay -row 2 -column 1 -sticky ew -padx 10
    grid $window.direction_label -row 3 -column 0 -sticky w -padx 10
    grid $window.direction -row 3 -column 1 -sticky w -padx 10
    grid $window.details -row 4 -column 0 -columnspan 2 -sticky ew -padx 10 -pady 8
    grid $window.plot -row 5 -column 0 -columnspan 2 -sticky w -padx 10 -pady 5
    grid $window.peak_title -row 6 -column 0 -columnspan 2 -sticky w -padx 10 -pady 5
    grid $window.peaks -row 7 -column 0 -columnspan 2 -sticky nsew -padx 10
    grid $window.integrals_title -row 8 -column 0 -columnspan 2 -sticky w -padx 10 -pady 5
    grid $window.integrals -row 9 -column 0 -columnspan 2 -sticky w -padx 10
    grid columnconfigure $window 1 -weight 1
    grid rowconfigure $window 7 -weight 1
    bind $window.source <<ComboboxSelected>> {::GX::NmrViewer::_refresh}
    _refresh
    return $window
}
proc ::GX::NmrViewer::viewerDispatch {action scene} {
    if {$action ni {open rerender}} {error "NMR viewer action must be open or rerender"}
    return [open $scene]
}
::GX::viewerBackendRegister nmr_spectrum_tk ::GX::NmrViewer::viewerDispatch
