# CORE-owned detached plot preservation. The rendered capture path is available
# even when a producer exposes no structured scientific representation.

namespace eval ::GX::PlotClone {}

proc ::GX::PlotClone::root {} {
    if {$::GX::currentSession eq "" || ![file isdirectory $::GX::currentSession]} {
        error "Open a Session before cloning a graph."
    }
    return [file join $::GX::currentSession analysis core.plot_clones]
}

proc ::GX::PlotClone::infoForPath {path} {
    if {$path eq "" || [catch {set base [file normalize [root]]}]} { return {} }
    set path [file normalize $path]
    set parent [file dirname $path]
    if {[file dirname $parent] ne $base || [file tail $path] ne "graph.png" ||
        ![regexp {^c[0-9]{6}$} [file tail $parent]]} { return {} }
    set descriptor [file join $parent clone.ini]
    if {![file isfile $descriptor] || ![file isfile $path]} { return {} }
    set fields [::GX::parseIni $descriptor]
    if {![dict exists $fields clone.capture_mode] ||
        [dict get $fields clone.capture_mode] ni {rendered scientific}} { return {} }
    return $fields
}

proc ::GX::PlotClone::setDescriptorFields {path changes} {
    set descriptor [file join [file dirname $path] clone.ini]
    set data [infoForPath $path]
    if {$data eq ""} {error "Unknown Detached Clone"}
    dict for {field value} $changes {
        if {$field ni {title use} || [regexp {[\r\n]} $value]} {error "Invalid Clone state field"}
        if {$field eq "use" && $value ni {0 1}} {error "Clone USE must be 0 or 1"}
        dict set data clone.$field $value
    }
    set tmp "$descriptor.tmp.[pid].[clock clicks]"
    set fd [open $tmp w]
    try {
        fconfigure $fd -encoding utf-8 -translation lf
        puts $fd "\[clone\]"
        foreach key [lsort [dict keys $data clone.*]] {::GX::putKV $fd [string range $key 6 end] [dict get $data $key]}
    } finally {close $fd}
    file rename -force -- $tmp $descriptor
}
proc ::GX::PlotClone::useForPath {path} {
    set data [infoForPath $path]
    return [expr {[dict exists $data clone.use] ? [dict get $data clone.use] : 1}]
}
proc ::GX::PlotClone::setUse {path value} {setDescriptorFields $path [dict create use $value];return $value}
proc ::GX::PlotClone::nextId {} {
    set base [root]
    for {set i 1} {$i <= 999999} {incr i} {
        set id [format "c%06d" $i]
        if {![file exists [file join $base $id]]} { return $id }
    }
    error "The Session has no available Clone IDs."
}

proc ::GX::PlotClone::validPng {path} {
    if {![file isfile $path] || [file size $path] < 100} { return 0 }
    set stream [open $path rb]
    set signature [read $stream 8]
    close $stream
    return [expr {$signature eq "\x89PNG\r\n\x1a\n"}]
}

proc ::GX::PlotClone::captureRendered {source} {
    set source [file normalize $source]
    set analysis [file normalize [file join $::GX::currentSession analysis]]
    set sourcePortable [string map {\\ /} $source]
    set analysisPortable [string map {\\ /} $analysis]
    if {[string first "${analysisPortable}/" $sourcePortable] != 0 || ![validPng $source]} {
        error "The selected graph has no valid Session PNG to preserve."
    }
    set id [nextId]
    set base [root]
    set staging [file join $::GX::currentSession metadata ".clone_capture_[pid]_[clock clicks]"]
    set final [file join $base $id]
    if {[file exists $staging] || [file exists $final]} { error "Clone capture path already exists." }
    set identity [::GX::graphUseIdentityForPath $source]
    set relative [string range $source [expr {[string length $analysis]+1}] end]
    set sourceModule [lindex [file split $relative] 0]
    set sourceGraph [lindex $identity 1]
    set sourceVariant [lindex $identity 2]
    set datasets {}
    set variables {}
    if {[lindex $identity 0] eq "plot.dataset" && $sourceGraph ne ""} {
        if {![catch {set seriesRows [::GX::graphSeriesList plot.dataset $sourceGraph $sourceVariant]}]} {
            foreach series $seriesRows {
                lappend datasets [dict get $series dataset_id]
                lappend variables "[dict get $series dataset_id]:[dict get $series x_variable_id]"
                lappend variables "[dict get $series dataset_id]:[dict get $series y_variable_id]"
            }
        }
    }
    try {
        file mkdir $staging
        set artifact [file join $staging graph.png]
        file copy -- $source $artifact
        if {![validPng $artifact] || [file size $artifact] != [file size $source]} {
            error "The preserved graph failed verification."
        }
        set mode rendered
        set captureFailure ""
        set scientific [file join $staging scientific]
        set native [expr {[::GX::graphRendererOwnerForPath $source] eq {PLOT_DATASET_API_v4}}]
        if {$native} {
            ::GX::graphNativeRendererRequire
            set prior [infoForPath $source]
            if {$prior ne {} && [dict get $prior clone.capture_mode] eq {scientific}} {
                set snapshot [::GX::PlotDatasetAPIv4::snapshotCopy [file dirname $source] $scientific]
                set scientificInfo [dict create graph_id [dict get $snapshot graph_id] source_variant [dict get $snapshot source_variant]]
                set datasets [dict keys [dict get $snapshot datasets]]
                set sourceModule plot.dataset;set sourceGraph [dict get $snapshot graph_id];set sourceVariant [dict get $snapshot source_variant]
                set variables [dict get $snapshot source_variable_ids]
                ::GX::PlotDatasetAPIv4::renderSnapshot $scientific $sourceGraph
            } else {
                set scientificInfo [::GX::PlotDatasetAPIv4::captureForArtifact $source $scientific]
                set datasets [dict get $scientificInfo source_dataset_ids]
                set variables [dict get $scientificInfo source_variable_ids]
            }
            foreach name {native_v4_snapshot.tcldict resources graph.png .gxtxt_plotmeta graph.xrange.ini} {
                if {[file exists [file join $scientific $name]]} {
                    file rename -force -- [file join $scientific $name] [file join $staging $name]
                }
            }
            file delete -force -- $scientific
            set mode scientific
        } elseif {![catch {
            ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
            set prior [infoForPath $source]
            if {$prior ne "" && [dict get $prior clone.capture_mode] eq "scientific"} {
                file mkdir $scientific
                foreach name {snapshot.h5 presentation.ini} {
                    file copy -- [file join [file dirname $source] $name] [file join $scientific $name]
                }
                file copy -- [file join [file dirname $source] private_session] [file join $scientific private_session]
                set scientificInfo [dict create graph_id [dict get $prior clone.snapshot_graph] \
                    source_variant [dict get $prior clone.snapshot_source_variant]]
                ::GX::PlotDatasetAPIv3::renderSnapshot $scientific [dict get $scientificInfo graph_id]
            } else {
                set scientificInfo [::GX::PlotDatasetAPIv3::captureForArtifact $source $scientific]
            }
        } captureFailure]} {
            # A failed rich capture cannot leave partial resources in a
            # successful rendered fallback. Only verified files are committed.
            foreach name {snapshot.h5 presentation.ini graph.png} {
                file rename -force -- [file join $scientific $name] [file join $staging $name]
            }
            file rename -- [file join $scientific private_session] [file join $staging private_session]
            file delete -force -- $scientific
            set mode scientific
        } elseif {[file exists $scientific]} {
            file delete -force -- $scientific
        }
        if {![validPng $artifact]} { error "Clone capture has no valid rendered artifact." }
        set stream [open [file join $staging clone.ini] w]
        fconfigure $stream -encoding utf-8 -translation lf
        puts $stream "\[clone\]"
        ::GX::putKV $stream schema GXTXT_DETACHED_PLOT_CLONE_v1
        ::GX::putKV $stream id $id
        ::GX::putKV $stream capture_mode $mode
        ::GX::putKV $stream title [::GX::graphDisplayTitle $source]
        ::GX::putKV $stream use [expr {[llength $identity] == 3 ? [::GX::graphUseStateGet {*}$identity] : [useForPath $source]}]
        ::GX::putKV $stream created_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]
        ::GX::putKV $stream source_module $sourceModule
        ::GX::putKV $stream source_module_version [::GX::moduleField $sourceModule version ""]
        ::GX::putKV $stream source_graph $sourceGraph
        ::GX::putKV $stream source_variant $sourceVariant
        ::GX::putKV $stream source_dataset_ids [join [lsort -unique $datasets] {;}]
        ::GX::putKV $stream source_variable_ids [join [lsort -unique $variables] {;}]
        if {$mode eq "scientific"} {
            ::GX::putKV $stream snapshot_graph [dict get $scientificInfo graph_id]
            ::GX::putKV $stream snapshot_source_variant [dict get $scientificInfo source_variant]
        } else {
            set reason [string range [string trim [string map [list "\n" " " "\r" " "] $captureFailure]] 0 199]
            ::GX::putKV $stream scientific_capture_error $reason
        }
        ::GX::putKV $stream source_artifact [file join analysis $relative]
        ::GX::putKV $stream source_artifact_bytes [file size $source]
        close $stream
        file mkdir $base
        file rename -- $staging $final
        if {[llength [info commands ::GX::annotationPathForPlot]]} {
            set sourceAnnotations [::GX::annotationPathForPlot $source]
            if {[file isfile $sourceAnnotations]} {
                set targetAnnotations [::GX::annotationPathForPlot [file join $final graph.png]]
                file mkdir [file dirname $targetAnnotations]
                file copy -- $sourceAnnotations $targetAnnotations
            }
        }
        if {[llength [info commands ::GX::graphResourceCopy]]} {
            if {[::GX::PlotClone::infoForPath $source] ne ""} {
                set sourceRef [dict create kind clone clone_id [file tail [file dirname $source]]]
            } elseif {[llength $identity] == 3} {
                set sourceRef [dict create kind provider module_id [lindex $identity 0] graph_id [lindex $identity 1] variant_id [lindex $identity 2]]
            } else {set sourceRef ""}
            if {$sourceRef ne ""} {
                ::GX::graphResourceCopy $sourceRef [dict create kind clone clone_id $id]
            }
        }
    } on error {message options} {
        if {[llength [info commands ::GX::graphResourceDelete]]} {catch {::GX::graphResourceDelete [dict create kind clone clone_id $id]}}
        if {[file exists $staging]} { file delete -force -- $staging }
        if {[file exists $final]} { file delete -force -- $final }
        return -options $options $message
    }
    return [file join $final graph.png]
}

proc ::GX::PlotClone::presentationFields {path} {
    set info [infoForPath $path]
    if {$info eq "" || [dict get $info clone.capture_mode] ne "scientific"} {
        error "This Clone has no scientific presentation to edit."
    }
    set graph [dict get $info clone.snapshot_graph]
    if {[::GX::graphRendererOwnerForPath $path] eq {PLOT_DATASET_API_v4}} {
        ::GX::graphNativeRendererRequire
        return [::GX::PlotDatasetAPIv4::snapshotPresentationFields [file dirname $path] $graph]
    }
    set config [::GX::parseIni [file join [file dirname $path] presentation.ini]]
    set values [dict create]
    foreach {field section key default} {
        title plot title auto
        x_label plot x_label auto
        y_label plot y_label auto
        y2_label plot y2_label auto
        line_width plot line_width inherit
        marker_size plot marker_size 4
        legend_placement legend placement inside
        x_min axis x_min ""
        x_max axis x_max ""
        y_min axis y_min ""
        y_max axis y_max ""
        xgrid axis xgrid inherit
        ygrid axis ygrid inherit
        layout_auto axis layout_auto 1
        layout_margin_left axis layout_margin_left ""
        layout_margin_right axis layout_margin_right ""
        layout_margin_top axis layout_margin_top ""
        layout_margin_bottom axis layout_margin_bottom ""
        layout_gap axis layout_gap ""
        layout_ylabel_dist axis layout_ylabel_dist ""
        width_px graphics_effective GXTXT_PLOT_WIDTH_PX ""
        height_px graphics_effective GXTXT_PLOT_HEIGHT_PX ""
    } {
        dict set values $field [::GX::descriptorValue $config "$section.$graph" $key $default]
    }
    # Older captured runtimes can contain an explicit empty placement. The
    # editor's readonly combobox needs a valid choice when opened unchanged.
    if {[dict get $values legend_placement] eq ""} {
        dict set values legend_placement inside
    }
    foreach field {xgrid ygrid} {
        if {[string trim [dict get $values $field]] eq ""} {
            dict set values $field inherit
        }
    }
    return $values
}

proc ::GX::PlotClone::basePresentationText {content} {
    # Replace the preceding Clone override block on each edit. Repeated
    # appends create duplicate INI sections whose precedence varies by parser.
    set marker "\n; GX-TXT Clone presentation overrides v1\n"
    set at [string first $marker $content]
    if {$at >= 0} { return [string range $content 0 [expr {$at-1}]] }
    return $content
}

proc ::GX::PlotClone::setPresentation {path values} {
    set info [infoForPath $path]
    if {$info eq "" || [dict get $info clone.capture_mode] ne "scientific"} {
        error "Only scientific Clones can be rerendered with new presentation."
    }
    set allowed {title x_label y_label y2_label line_width marker_size legend_placement x_min x_max y_min y_max xgrid ygrid layout_auto layout_margin_left layout_margin_right layout_margin_top layout_margin_bottom layout_gap layout_ylabel_dist width_px height_px}
    dict for {key value} $values {
        if {$key ni $allowed} { error "Unknown Clone presentation field '$key'." }
        if {[string first "\n" $value] >= 0 || [string first "\r" $value] >= 0} {
            error "Clone presentation values must be single-line text."
        }
    }
    foreach field {x_min x_max y_min y_max} {
        if {[dict exists $values $field] && [dict get $values $field] ne "" &&
            ![string is double -strict [dict get $values $field]]} {
            error "$field must be numeric or blank."
        }
    }
    if {[dict exists $values legend_placement] &&
        [dict get $values legend_placement] ni {none inside above below left right manual}} {
        error "Unknown legend placement."
    }
    if {[dict exists $values line_width] &&
        [dict get $values line_width] ni {inherit auto} &&
        (![string is double -strict [dict get $values line_width]] || [dict get $values line_width] <= 0)} {
        error "Line width must be positive or inherit."
    }
    if {[dict exists $values marker_size] &&
        (![string is double -strict [dict get $values marker_size]] || [dict get $values marker_size] <= 0)} {
        error "Marker size must be positive."
    }
    foreach field {xgrid ygrid} {
        if {[dict exists $values $field] && [dict get $values $field] ni {inherit on off}} {
            error "$field must be inherit, on, or off."
        }
    }
    if {[dict exists $values layout_auto] && [dict get $values layout_auto] ni {0 1}} {
        error "Automatic layout must be 0 or 1."
    }
    foreach {field label lo hi} [::GX::layoutFieldDefs] {
        if {![dict exists $values $field] || [string trim [dict get $values $field]] eq ""} continue
        set value [dict get $values $field]
        if {![string is double -strict $value] || $value < $lo || $value > $hi} {
            error "$label must be between $lo and $hi, or blank."
        }
    }
    foreach field {width_px height_px} {
        if {[dict exists $values $field] && [dict get $values $field] ne "" &&
            (![string is integer -strict [dict get $values $field]] ||
             [dict get $values $field] < 320 || [dict get $values $field] > 8000)} {
            error "$field must be a whole number from 320 to 8000, or blank."
        }
    }
    set graph [dict get $info clone.snapshot_graph]
    if {[::GX::graphRendererOwnerForPath $path] eq {PLOT_DATASET_API_v4}} {
        ::GX::graphNativeRendererRequire
        set result [::GX::PlotDatasetAPIv4::snapshotPresentationSet [file dirname $path] $graph $values]
        if {[dict exists $values title]} {setDescriptorFields $path [dict create title [dict get $values title]]}
        return $result
    }
    if {[dict exists $values title]} {setDescriptorFields $path [dict create title [dict get $values title]]}
    set dir [file dirname $path]
    set runtime [file join $dir presentation.ini]
    set variant [dict get $info clone.snapshot_source_variant]
    set token [string map {. _ / _ \\ _} $graph]
    set variantToken [expr {$variant eq "" ? "base" : $variant}]
    set spec [file join $dir private_session metadata plot.dataset plotspec_v2 "${token}--${variantToken}.ini"]
    set files [list $runtime]
    if {[file isfile $spec]} { lappend files $spec }
    set originals [dict create]
    foreach file $files {
        set stream [open $file r]
        fconfigure $stream -encoding utf-8
        dict set originals $file [read $stream]
        close $stream
    }
    try {
        set stream [open $runtime w]
        fconfigure $stream -encoding utf-8 -translation lf
        puts -nonewline $stream [basePresentationText [dict get $originals $runtime]]
        puts $stream "\n; GX-TXT Clone presentation overrides v1\n"
        puts $stream "\[plot.$graph\]"
        foreach field {title x_label y_label y2_label line_width marker_size} {
            if {[dict exists $values $field]} { ::GX::putKV $stream $field [dict get $values $field] }
        }
        if {[dict exists $values legend_placement]} {
            puts $stream "\n\[legend.$graph\]"
            ::GX::putKV $stream enabled 1
            ::GX::putKV $stream placement [dict get $values legend_placement]
        }
        puts $stream "\n\[axis.$graph\]"
        ::GX::putKV $stream enabled 1
        foreach field {x_min x_max y_min y_max xgrid ygrid layout_auto layout_margin_left layout_margin_right layout_margin_top layout_margin_bottom layout_gap layout_ylabel_dist} {
            if {[dict exists $values $field]} { ::GX::putKV $stream $field [dict get $values $field] }
        }
        if {([dict exists $values width_px] && [dict get $values width_px] ne "") ||
            ([dict exists $values height_px] && [dict get $values height_px] ne "")} {
            # Snapshot rendering receives effective graphics through the
            # process environment, so these overrides must live in the same
            # section that the v3 service forwards to Octave.
            puts $stream "\n\[graphics_effective\]"
            foreach field {width_px height_px} name {GXTXT_PLOT_WIDTH_PX GXTXT_PLOT_HEIGHT_PX} {
                if {[dict exists $values $field] && [dict get $values $field] ne ""} {
                    ::GX::putKV $stream $name [dict get $values $field]
                }
            }
        }
        close $stream
        if {[file isfile $spec]} {
            set stream [open $spec w]
            fconfigure $stream -encoding utf-8 -translation lf
            puts -nonewline $stream [basePresentationText [dict get $originals $spec]]
            puts $stream "\n; GX-TXT Clone presentation overrides v1\n"
            if {[dict exists $values title]} {
                puts $stream "\n\[plotspec\]"
                ::GX::putKV $stream title_present 1
                ::GX::putKV $stream title [dict get $values title]
            }
            puts $stream "\n\[panel.1\]"
            foreach {field axis} {x_label x y_label y_left y2_label y_right} {
                if {[dict exists $values $field]} {
                    ::GX::putKV $stream "axis.$axis.label.present" 1
                    ::GX::putKV $stream "axis.$axis.label.value" [dict get $values $field]
                }
            }
            close $stream
        }
        ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
        ::GX::PlotDatasetAPIv3::renderSnapshot $dir $graph
    } on error {message options} {
        dict for {file content} $originals {
            set stream [open $file w]
            fconfigure $stream -encoding utf-8 -translation lf
            puts -nonewline $stream $content
            close $stream
        }
        return -options $options $message
    }
    return $path
}

proc ::GX::cloneCurrentPlot {} {
    set source [currentGraphPath]
    if {$source eq ""} { tk_messageBox -message "Select a graph first."; return }
    if {[catch {set artifact [::GX::PlotClone::captureRendered $source]} message]} {
        tk_messageBox -icon error -message $message
        return
    }
    refreshGraphs
    tk_messageBox -icon info -message "Detached Clone created: [file tail [file dirname $artifact]]."
}

proc ::GX::PlotClone::saveEditor {path} {
    set fields [dict create]
    foreach key {title x_label y_label y2_label line_width marker_size legend_placement x_min x_max y_min y_max xgrid ygrid layout_auto layout_margin_left layout_margin_right layout_margin_top layout_margin_bottom layout_gap layout_ylabel_dist width_px height_px} {
        dict set fields $key $::GX::ui(cloneEdit,$key)
    }
    if {[catch {setPresentation $path $fields} message]} {
        tk_messageBox -parent .cloneedit -icon error -message $message
        return
    }
    destroy .cloneedit
    ::GX::refreshGraphs
}

proc ::GX::editCurrentClonedPlot {} {
    set path [currentGraphPath]
    set info [::GX::PlotClone::infoForPath $path]
    if {$info eq ""} { ::GX::editCurrentClonedPlot_legacy_compare; return }
    if {[dict get $info clone.capture_mode] ne "scientific"} {
        tk_messageBox -message "This rendered Clone has no scientific presentation to edit."
        return
    }
    set fields [::GX::PlotClone::presentationFields $path]
    dict for {key value} $fields { set ::GX::ui(cloneEdit,$key) $value }
    catch {destroy .cloneedit}
    toplevel .cloneedit
    wm title .cloneedit "Edit scientific Clone presentation"
    set row 0
    foreach {key label} {
        title Title
        x_label {X label}
        y_label {Left Y label}
        y2_label {Right Y label}
        line_width {Line width}
        marker_size {Marker size}
        x_min {X minimum}
        x_max {X maximum}
        y_min {Y minimum}
        y_max {Y maximum}
        width_px {Image width (px)}
        height_px {Image height (px)}
    } {
        ttk::label .cloneedit.label$row -text $label
        ttk::entry .cloneedit.entry$row -textvariable ::GX::ui(cloneEdit,$key) -width 38
        grid .cloneedit.label$row -row $row -column 0 -sticky w -padx 6 -pady 3
        grid .cloneedit.entry$row -row $row -column 1 -sticky ew -padx 6 -pady 3
        incr row
    }
    ttk::label .cloneedit.legendlabel -text "Legend placement"
    ttk::combobox .cloneedit.legend -textvariable ::GX::ui(cloneEdit,legend_placement) \
        -values {inside above below left right manual} -state readonly
    grid .cloneedit.legendlabel -row $row -column 0 -sticky w -padx 6 -pady 3
    grid .cloneedit.legend -row $row -column 1 -sticky ew -padx 6 -pady 3
    incr row
    foreach {key label} {xgrid {X grid} ygrid {Y grid}} {
        ttk::label .cloneedit.label$row -text $label
        ttk::combobox .cloneedit.entry$row -textvariable ::GX::ui(cloneEdit,$key) \
            -values {inherit on off} -state readonly
        grid .cloneedit.label$row -row $row -column 0 -sticky w -padx 6 -pady 3
        grid .cloneedit.entry$row -row $row -column 1 -sticky ew -padx 6 -pady 3
        incr row
    }
    ttk::checkbutton .cloneedit.layoutauto -text "Automatic plot layout" -variable ::GX::ui(cloneEdit,layout_auto)
    grid .cloneedit.layoutauto -row $row -column 0 -columnspan 2 -sticky w -padx 6 -pady 3
    incr row
    foreach {key label lo hi} [::GX::layoutFieldDefs] {
        ttk::label .cloneedit.label$row -text $label
        ttk::entry .cloneedit.entry$row -textvariable ::GX::ui(cloneEdit,$key) -width 38
        grid .cloneedit.label$row -row $row -column 0 -sticky w -padx 6 -pady 3
        grid .cloneedit.entry$row -row $row -column 1 -sticky ew -padx 6 -pady 3
        incr row
    }
    ttk::label .cloneedit.note -text "The plotted values and series bindings are frozen. These controls change only presentation." -wraplength 430
    grid .cloneedit.note -row $row -column 0 -columnspan 2 -sticky ew -padx 6 -pady 5
    incr row
    ttk::button .cloneedit.save -text "Save and rerender" -command [list ::GX::PlotClone::saveEditor $path]
    ttk::button .cloneedit.cancel -text "Cancel" -command [list destroy .cloneedit]
    grid .cloneedit.save -row $row -column 0 -padx 6 -pady 8
    grid .cloneedit.cancel -row $row -column 1 -padx 6 -pady 8
    grid columnconfigure .cloneedit 1 -weight 1
}

proc ::GX::startRerenderPaths {paths {allConfigured 0}} {
    set live {}
    set rendered 0
    foreach path $paths {
        set info [::GX::PlotClone::infoForPath $path]
        if {$info eq ""} {
            lappend live $path
        } elseif {[dict get $info clone.capture_mode] eq "scientific"} {
            if {[::GX::graphRendererOwnerForPath $path] eq {PLOT_DATASET_API_v4}} {
                lappend live $path
                continue
            }
            if {[catch {
                ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
                ::GX::PlotDatasetAPIv3::renderSnapshot [file dirname $path] [dict get $info clone.snapshot_graph]
            } message]} {
                tk_messageBox -icon error -message $message
            } else {
                incr rendered
            }
        }
    }
    if {$rendered} { refreshGraphs }
    if {![llength $live]} {
        if {!$rendered} {
            tk_messageBox -message "This rendered Clone has no scientific data to rerender. Its captured PNG remains available for export."
        }
        return
    }
    return [::GX::startRerenderPaths_before_clones $live $allConfigured]
}

proc ::GX::previewGraph_before_graph_selection {} {
    ::GX::previewGraph_before_clones
    set path [currentGraphPath]
    set isClone [expr {[::GX::PlotClone::infoForPath $path] ne ""}]
    foreach name {one mod legend pick axes annotate exportann variants editclone} {
        set button ".top.nb.graphs.actions.$name"
        if {[winfo exists $button]} {
            if {$isClone && $name in {one editclone} &&
                [dict get [::GX::PlotClone::infoForPath $path] clone.capture_mode] eq "scientific"} {
                $button state !disabled
            } elseif {$isClone} {
                $button state disabled
            } else {
                $button state !disabled
            }
        }
    }
    if {$isClone} {
        if {[dict get [::GX::PlotClone::infoForPath $path] clone.capture_mode] eq "scientific"} {
            set ::GX::ui(graphInfo) "Detached scientific Clone. Its plotted values are frozen; use Edit clone... to change presentation or Rerender to redraw from the Session-owned scientific snapshot."
        } else {
            set ::GX::ui(graphInfo) "Detached rendered Clone. The captured PNG is owned by this Session and can be exported."
        }
    }
}
