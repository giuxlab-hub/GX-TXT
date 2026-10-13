# SPDX-License-Identifier: GPL-3.0-or-later
# XAS Viewer backend. Live graphs and detached scientific snapshots use PLOT_DATASET_API_v3.
namespace eval ::GX::XASViewer {
    variable window .xas_spectra_viewer
    variable selected ""
    variable statusText ""
}

proc ::GX::XASViewer::_contract {datasetId} {
    if {[catch {set record [::GX::sessionInspectionDataset $datasetId]}]} {return ""}
    if {![dict exists $record id] || [dict get $record id] ne $datasetId} {return ""}
    foreach key {contract kind} {
        if {[dict exists $record $key] && [string trim [dict get $record $key]] ne ""} {
            return [string trim [dict get $record $key]]
        }
    }
    return ""
}

proc ::GX::XASViewer::_compatible {datasetId} {
    expr {[_contract $datasetId] in {spectrum.scientific spectrum.family}}
}

proc ::GX::XASViewer::_activatePlotDataset {} {
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    foreach capability {
        plotspec graph_series series_family_grouping axes_config multi_panel
        series_editor_extension graph_config_extension axis_config_extension
        render rerender artifacts vector_export standalone_v2_editor
    } {
        ::GX::PlotDatasetAPIv3::requireCapability $capability
    }
    set info [::GX::PlotDatasetAPIv3::apiInfo]
    foreach capability {detached_scientific_capture detached_scientific_render source_row_point_index} {
        if {[lsearch -exact [dict get $info capabilities] $capability] < 0} {
            error "viewer.xas_spectra: PLOT_DATASET_API_v3 capability missing: $capability"
        }
    }
}

proc ::GX::XASViewer::_datasetFromContext {scene} {
    if {[dict exists $scene open_context]} {
        set c [dict get $scene open_context]
        foreach key {dataset_id source_dataset_id} {
            if {[dict exists $c $key]} {
                set id [string trim [dict get $c $key]]
                if {$id ne "" && [_compatible $id]} {return $id}
            }
        }
    }
    set ids [_datasets]
    return [lindex $ids 0]
}

proc ::GX::XASViewer::_datasets {} {
    if {[catch {set available [::GX::sessionInspectionDatasetIds]}]} {return {}}
    set ids {}
    foreach id $available {
        if {[_compatible $id]} {lappend ids $id}
    }
    return $ids
}

proc ::GX::XASViewer::_refresh {} {
    variable window; variable selected; variable statusText
    if {![winfo exists $window]} {return}
    set ids [_datasets]
    $window.source configure -values $ids
    if {$selected ni $ids} {set selected [lindex $ids 0]}
    if {$selected eq ""} {
        $window.source configure -state disabled
        $window.plot configure -state disabled
        set statusText "No XAS spectra are available in the current Session."
    } else {
        $window.source configure -state readonly
        $window.plot configure -state normal
        set statusText "Ready to open $selected in the persistent graph editor."
    }
}

proc ::GX::XASViewer::_openSelected {} {
    variable selected; variable window
    if {$selected eq "" || ![_compatible $selected]} {return}
    if {[catch {openDataset $selected} problem]} {
        tk_messageBox -parent $window -icon error -title "XAS graph" -message $problem
    }
}

proc ::GX::XASViewer::_open {scene} {
    variable window; variable selected
    package require Tk
    set selected [_datasetFromContext $scene]
    if {[winfo exists $window]} {
        _refresh
        raise $window
        return $window
    }
    toplevel $window
    wm title $window "XAS Spectra Viewer"
    wm geometry $window 680x260+60+60
    ttk::label $window.title -text "XAS Spectra Viewer" -font TkHeadingFont
    ttk::label $window.sourceLabel -text "XAS source Dataset"
    ttk::combobox $window.source -textvariable ::GX::XASViewer::selected -width 56 -state readonly
    ttk::button $window.plot -text "Open persistent XAS graph" -command ::GX::XASViewer::_openSelected
    ttk::label $window.status -textvariable ::GX::XASViewer::statusText -anchor w -wraplength 620
    grid $window.title -row 0 -column 0 -columnspan 2 -sticky w -padx 12 -pady 12
    grid $window.sourceLabel -row 1 -column 0 -sticky w -padx 12 -pady 8
    grid $window.source -row 1 -column 1 -sticky ew -padx 12 -pady 8
    grid $window.plot -row 2 -column 0 -columnspan 2 -sticky w -padx 12 -pady 12
    grid $window.status -row 3 -column 0 -columnspan 2 -sticky ew -padx 12 -pady 12
    grid columnconfigure $window 1 -weight 1
    bind $window.source <<ComboboxSelected>> ::GX::XASViewer::_refresh
    _refresh
    return $window
}

proc ::GX::XASViewer::_unit {datasetId variableId} {
    set v [::GX::datasetVariableById $datasetId $variableId]
    if {$v eq ""} {return ""}
    return [expr {[dict exists $v unit] ? [dict get $v unit] : ""}]
}

proc ::GX::XASViewer::_spec {datasetId} {
    set contract [_contract $datasetId]
    set xu [_unit $datasetId spectral_x]
    set yu [_unit $datasetId spectral_y]
    set xlabel "Energy"
    if {$xu ne ""} {append xlabel " \[$xu\]"}
    set ylabel "mu(E)"
    if {$yu ne ""} {append ylabel " \[$yu\]"}
    set axes [dict create \
        x [dict create label $xlabel display_unit $xu scale linear] \
        y_left [dict create label $ylabel display_unit $yu scale linear]]
    set series [dict create \
        id xas_spectrum \
        dataset_id $datasetId \
        x_variable_id spectral_x \
        y_variable_id spectral_y \
        axis left \
        kind line \
        label "XAS spectrum" \
        style [dict create line_width 1.2]]
    if {$contract eq "spectrum.family"} {
        dict set series family_variable_id parameter_value
        dict set series family_label_prefix "Spectrum"
        dict set series label "XAS spectral family"
    }
    set panel [dict create \
        id main \
        title "XAS spectra" \
        axes $axes \
        series [list $series] \
        annotations {}]
    # Presentation not specified here inherits the standard plot.dataset graph
    # configuration. The standard editor therefore owns legend, layout, ranges,
    # scaling, units, styles, annotations, panels and export configuration.
    return [dict create \
        schema PLOT_DATASET_PLOTSPEC_v2 \
        graph_type cartesian_2d \
        graph_id plot.dataset.xy \
        title "XAS spectra: $datasetId" \
        defaults [dict create style [dict create]] \
        panels [list $panel] \
        output [dict create]]
}

proc ::GX::XASViewer::createPlot {datasetId} {
    if {![_compatible $datasetId]} {
        error "viewer.xas_spectra: Dataset '$datasetId' is not a supported XAS spectral contract."
    }
    _activatePlotDataset
    set spec [_spec $datasetId]
    return [::GX::PlotDatasetAPIv3::createPlotFromSpec $spec variant ""]
}

proc ::GX::XASViewer::openDataset {datasetId} {
    set ref [createPlot $datasetId]
    ::GX::PlotDatasetAPIv3::render $ref
    return [::GX::PlotDatasetAPIv3::openEditor $ref]
}

proc ::GX::XASViewer::captureDetachedSnapshot {artifact destinationDir} {
    _activatePlotDataset
    return [::GX::PlotDatasetAPIv3::captureForArtifact $artifact $destinationDir]
}

proc ::GX::XASViewer::writePointIndex {artifact destination} {
    _activatePlotDataset
    return [::GX::PlotDatasetAPIv3::writePointIndex $artifact $destination]
}

proc ::GX::XASViewer::renderDetachedSnapshot {cloneDir graphId} {
    _activatePlotDataset
    return [::GX::PlotDatasetAPIv3::renderSnapshot $cloneDir $graphId]
}

proc ::GX::XASViewer::viewerDispatch {action scene} {
    if {$action ni {open rerender}} {
        error "XAS viewer action must be open or rerender."
    }
    set shell [_open $scene]
    if {[dict exists $scene open_context]} {
        set context [dict get $scene open_context]
        foreach key {dataset_id source_dataset_id} {
            if {[dict exists $context $key] && [_compatible [dict get $context $key]]} {
                return [openDataset [dict get $context $key]]
            }
        }
    }
    return $shell
}

::GX::viewerBackendRegister xas_plot_dataset ::GX::XASViewer::viewerDispatch
