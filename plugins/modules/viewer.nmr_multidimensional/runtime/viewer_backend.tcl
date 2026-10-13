# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::NmrMultiViewer {
    variable window .nmr_multidimensional_viewer
    variable worker [file normalize [file join [file dirname [info script]] .. .. acq.nmr_multidimensional runtime nmr_pipe_worker.py]]
    variable state
    array set state {dataset_id {} planeLabel F1/F2 i0 0 i1 0 i2 0 threshold 0.08 levels 8 positive 1 negative 1 xlim {} ylim {} publicationId {} hasSaved 0 status {Choose a spectrum.}}
    variable photo ""
    variable bbox {}
    variable xbounds {}
    variable ybounds {}
    variable drag {}
}

proc ::GX::NmrMultiViewer::_session {} {
    if {![info exists ::GX::currentSession] || $::GX::currentSession eq ""} {error "Open a Session first"}
    return $::GX::currentSession
}
proc ::GX::NmrMultiViewer::_metadata {id} {
    return [::GX::datasetMetadataRead [_session] $id]
}
proc ::GX::NmrMultiViewer::datasets {} {
    set out {}
    foreach id [::GX::sessionInspectionDatasetIds] {
        if {[catch {set md [_metadata $id]}]} continue
        if {[dict exists $md nmr_multi.dimensions]} {lappend out $id}
    }
    return $out
}
proc ::GX::NmrMultiViewer::_sourcePath {} {
    variable state
    if {$state(dataset_id) ni [datasets]} {error "Select an acquired multidimensional NMR Dataset"}
    return [::GX::datasetResolvePath [_session] $state(dataset_id)]
}
proc ::GX::NmrMultiViewer::_runWorker {args} {
    variable worker
    set python [::GX::runtimeToolRequired python]
    set raw [exec $python -B $worker {*}$args]
    set out [dict create]
    foreach line [split [string trim $raw] "\n"] {
        if {$line eq ""} continue
        lassign [split $line "\t"] key encoded
        if {$key eq "" || $encoded eq ""} {error "NMR worker returned malformed output"}
        dict set out $key [encoding convertfrom utf-8 [binary decode base64 -strict $encoded]]
    }
    return $out
}
proc ::GX::NmrMultiViewer::_plane {} {
    variable state
    switch -- $state(planeLabel) {
        F1/F2 {return 0,1}
        F1/F3 {return 0,2}
        F2/F3 {return 1,2}
        default {return 0,1}
    }
}
proc ::GX::NmrMultiViewer::_coords {} {
    variable state
    set md [_metadata $state(dataset_id)]
    set result {}
    for {set i 0} {$i < [dict get $md nmr_multi.dimensions]} {incr i} {
        set n [dict get $md nmr_multi.axis_[expr {$i+1}]_points]
        lappend result [expr {max(0,min($n-1,int(round($state(i$i)))))}]
    }
    return [join $result ,]
}
proc ::GX::NmrMultiViewer::_sourceChanged {} {
    variable state
    variable window
    set md [_metadata $state(dataset_id)]
    set dims [dict get $md nmr_multi.dimensions]
    set planes {F1/F2}
    if {$dims == 3} {set planes {F1/F2 F1/F3 F2/F3}}
    $window.controls.plane configure -values $planes
    if {$state(planeLabel) ni $planes} {set state(planeLabel) F1/F2}
    set shape [split [dict get $md nmr_multi.shape] ,]
    if {!$state(hasSaved)} {
        for {set i 0} {$i < $dims} {incr i} {set state(i$i) [expr {int([lindex $shape $i]/2)}]}
        set state(publicationId) "[regsub -all {[^A-Za-z0-9._-]} $state(dataset_id) _].nmr.profile"
        set state(xlim) ""; set state(ylim) ""
    }
    for {set i 0} {$i < 3} {incr i} {
        set frame $window.body.side.axes.f$i
        if {$i < $dims} {
            set n [lindex $shape $i]
            $frame.scale configure -to [expr {$n-1}]
            grid $frame -row $i -column 0 -sticky ew -pady 3
            set nuc [dict get $md nmr_multi.axis_[expr {$i+1}]_nucleus]
            $frame.label configure -text "F[expr {$i+1}] $nuc"
        } else {grid remove $frame}
    }
    set details "[dict get $md nmr_multi.dimensions]-D acquired NMR • [dict get $md nmr_multi.shape] samples\n"
    for {set i 1} {$i <= $dims} {incr i} {
        append details "F$i [dict get $md nmr_multi.axis_${i}_nucleus] ([dict get $md nmr_multi.axis_${i}_label]): [format %.3f [dict get $md nmr_multi.axis_${i}_ppm_first]] → [format %.3f [dict get $md nmr_multi.axis_${i}_ppm_last]] ppm; [format %.3f [dict get $md nmr_multi.axis_${i}_frequency_mhz]] MHz\n"
    }
    foreach {key label} {nmr_multi.original_filename {Original file} nmr_multi.source_sha256 {Source SHA-256} nmr_multi.source_citation Citation nmr_multi.source_license Rights} {
        if {[dict exists $md $key] && [dict get $md $key] ne ""} {append details "$label: [dict get $md $key]\n"}
    }
    $window.body.side.details configure -text [string trim $details]
    set state(hasSaved) 0
    render
}
proc ::GX::NmrMultiViewer::_chooseSource {} {
    variable state
    set state(hasSaved) 0
    _sourceChanged
}
proc ::GX::NmrMultiViewer::render {} {
    variable state
    variable window
    variable photo
    variable bbox
    variable xbounds
    variable ybounds
    if {![winfo exists $window] || $state(dataset_id) eq ""} return
    set output [file join [_session] report nmr_multidimensional_view.png]
    file mkdir [file dirname $output]
    set args [list render [_sourcePath] --out $output --plane [_plane] --coords [_coords] \
        --threshold $state(threshold) --levels $state(levels) \
        --positive $state(positive) --negative $state(negative)]
    if {$state(xlim) ne ""} {lappend args --xlim $state(xlim)}
    if {$state(ylim) ne ""} {lappend args --ylim $state(ylim)}
    set result [_runWorker {*}$args]
    if {$photo ne ""} {image delete $photo}
    set photo [image create photo -file $output]
    $window.body.canvas delete all
    $window.body.canvas create image 0 0 -anchor nw -image $photo
    set bbox [split [dict get $result plot_bbox] ,]
    set xbounds [split [dict get $result x_bounds] ,]
    set ybounds [split [dict get $result y_bounds] ,]
    set state(xlim) [dict get $result x_bounds]
    set state(ylim) [dict get $result y_bounds]
    set md [_metadata $state(dataset_id)]
    set ppm [split [dict get $result selected_ppm] ,]
    set summary "Selected: "
    for {set i 0} {$i < [llength $ppm]} {incr i} {
        append summary "F[expr {$i+1}] [dict get $md nmr_multi.axis_[expr {$i+1}]_nucleus] [format %.4f [lindex $ppm $i]] ppm   "
        $window.body.side.axes.f$i.value configure -text "[format %.3f [lindex $ppm $i]] ppm"
    }
    append summary "Intensity [format %.6g [dict get $result intensity]]"
    set state(status) $summary
    $window.body.side.peaks delete [$window.body.side.peaks children {}]
    foreach line [split [dict get $result peak_table] "\n"] {
        if {$line ne ""} {$window.body.side.peaks insert {} end -values [split $line "\t"]}
    }
    return $result
}
proc ::GX::NmrMultiViewer::_renderSafely {} {
    variable state
    if {[catch {render} problem]} {set state(status) $problem; catch {tk_messageBox -icon error -title {NMR Viewer} -message $problem}}
}
proc ::GX::NmrMultiViewer::_planeChanged {} {
    variable state
    set state(xlim) ""; set state(ylim) ""
    _renderSafely
}
proc ::GX::NmrMultiViewer::_cursor {x y} {
    variable bbox
    variable xbounds
    variable ybounds
    if {[llength $bbox] != 4} {return {}}
    lassign $bbox x0 y0 x1 y1
    if {$x < $x0 || $x > $x1 || $y < $y0 || $y > $y1} {return {}}
    set xp [expr {[lindex $xbounds 0]+($x-$x0)/($x1-$x0)*([lindex $xbounds 1]-[lindex $xbounds 0])}]
    set yp [expr {[lindex $ybounds 1]+($y-$y0)/($y1-$y0)*([lindex $ybounds 0]-[lindex $ybounds 1])}]
    return [list $xp $yp]
}
proc ::GX::NmrMultiViewer::_nearest {axis ppm} {
    variable state
    set md [_metadata $state(dataset_id)]
    set n [dict get $md nmr_multi.axis_[expr {$axis+1}]_points]
    set first [dict get $md nmr_multi.axis_[expr {$axis+1}]_ppm_first]
    set last [dict get $md nmr_multi.axis_[expr {$axis+1}]_ppm_last]
    return [expr {max(0,min($n-1,int(round(($ppm-$first)/($last-$first)*($n-1)))))}]
}
proc ::GX::NmrMultiViewer::_click {x y} {
    variable state
    set coords [_cursor $x $y]
    if {![llength $coords]} return
    lassign [split [_plane] ,] yi xi
    set state(i$xi) [_nearest $xi [lindex $coords 0]]
    set state(i$yi) [_nearest $yi [lindex $coords 1]]
    _renderSafely
}
proc ::GX::NmrMultiViewer::_zoom {x y delta} {
    variable state
    variable xbounds
    variable ybounds
    set c [_cursor $x $y]
    if {![llength $c]} return
    set factor [expr {$delta > 0 ? 0.75 : 1.333333}]
    lassign $c cx cy
    set state(xlim) "[expr {$cx+([lindex $xbounds 0]-$cx)*$factor}],[expr {$cx+([lindex $xbounds 1]-$cx)*$factor}]"
    set state(ylim) "[expr {$cy+([lindex $ybounds 0]-$cy)*$factor}],[expr {$cy+([lindex $ybounds 1]-$cy)*$factor}]"
    _renderSafely
}
proc ::GX::NmrMultiViewer::_dragStart {x y} {
    variable drag
    set drag [list $x $y]
}
proc ::GX::NmrMultiViewer::_dragEnd {x y} {
    variable drag
    variable bbox
    variable xbounds
    variable ybounds
    variable state
    if {[llength $drag] != 2 || [llength $bbox] != 4} return
    lassign $drag sx sy
    set drag {}
    if {abs($x-$sx)+abs($y-$sy) < 4} return
    lassign $bbox x0 y0 x1 y1
    set dx [expr {-double($x-$sx)/($x1-$x0)*([lindex $xbounds 1]-[lindex $xbounds 0])}]
    set dy [expr {double($y-$sy)/($y1-$y0)*([lindex $ybounds 1]-[lindex $ybounds 0])}]
    set state(xlim) "[expr {[lindex $xbounds 0]+$dx}],[expr {[lindex $xbounds 1]+$dx}]"
    set state(ylim) "[expr {[lindex $ybounds 0]+$dy}],[expr {[lindex $ybounds 1]+$dy}]"
    _renderSafely
}
proc ::GX::NmrMultiViewer::_reset {} {
    variable state
    set state(xlim) ""; set state(ylim) ""
    _renderSafely
}
proc ::GX::NmrMultiViewer::_statePath {} {return [file join [_session] metadata nmr_multidimensional_viewer.ini]}
proc ::GX::NmrMultiViewer::saveState {} {
    variable state
    set path [_statePath]
    file mkdir [file dirname $path]
    set ch [::open $path w]
    fconfigure $ch -encoding utf-8 -translation lf
    try {
        puts $ch "\[nmr_multidimensional_viewer\]"
        foreach key {dataset_id planeLabel i0 i1 i2 threshold levels positive negative xlim ylim} {
            puts $ch "$key=$state($key)"
        }
    } finally {close $ch}
    ::GX::sessionPersistenceCommit
    set state(status) "View saved in Session."
    return $path
}
proc ::GX::NmrMultiViewer::loadState {} {
    variable state
    set path [_statePath]
    if {![file isfile $path]} {return {}}
    set ini [::GX::parseIni $path]
    foreach key {dataset_id planeLabel i0 i1 i2 threshold levels positive negative xlim ylim} {
        set value [::GX::descriptorValue $ini nmr_multidimensional_viewer $key ""]
        if {$value ne ""} {set state($key) $value}
    }
    set state(hasSaved) 1
    return [array get state]
}
proc ::GX::NmrMultiViewer::publish {kind id} {
    variable state
    if {$kind ni {plane projection_max profile_x profile_y}} {error "Unsupported NMR extraction '$kind'"}
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9._-]*$} $id]} {error "Enter a valid output Dataset ID"}
    set session [_session]
    set temp [file join $session report nmr_multidimensional_extract.csv]
    file mkdir [file dirname $temp]
    _runWorker extract [_sourcePath] --out $temp --plane [_plane] --coords [_coords] --kind $kind
    lassign [split [_plane] ,] yi xi
    if {$kind in {plane projection_max}} {set columns [list f[expr {$yi+1}]_ppm f[expr {$xi+1}]_ppm intensity]} \
    elseif {$kind eq "profile_x"} {set columns [list f[expr {$xi+1}]_ppm intensity]} \
    else {set columns [list f[expr {$yi+1}]_ppm intensity]}
    set md [_metadata $state(dataset_id)]
    set sourceSha [dict get $md nmr_multi.source_sha256]
    set definition [dict create dataset_id $id contract table.generic storage csv replace_owned 1 \
        producer_version 1.0.0 source {Multidimensional NMR Viewer} \
        source_dataset_ids [list $state(dataset_id)] \
        provenance "Acquired source Dataset $state(dataset_id), SHA-256 $sourceSha; $kind; plane $state(planeLabel); indices [_coords]"]
    set plan [::GX::datasetPublicationV2Prepare $session viewer.nmr_multidimensional $definition]
    set writer ""
    set ch ""
    try {
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        foreach column $columns {
            set role [expr {$column eq "intensity" ? "data" : "coordinate"}]
            set unit [expr {$column eq "intensity" ? "1" : "ppm"}]
            ::GX::datasetPublicationV2DeclareVariable $writer $column [dict create name $column unit $unit semantic_role $role dtype float64 rank 1 dimension_ids row coordinate_role $role axis_kind explicit]
        }
        set ch [::open $temp r]
        fconfigure $ch -encoding utf-8
        gets $ch
        set batch [dict create]
        foreach column $columns {dict set batch $column {}}
        set count 0
        while {[gets $ch line] >= 0} {
            set values [split $line ,]
            if {[llength $values] != [llength $columns]} {error "Malformed extracted NMR row"}
            foreach column $columns value $values {dict lappend batch $column $value}
            incr count
            if {$count >= 1000} {
                ::GX::datasetPublicationV2Append $writer row $batch
                set batch [dict create]
                foreach column $columns {dict set batch $column {}}
                set count 0
            }
        }
        if {$count} {::GX::datasetPublicationV2Append $writer row $batch}
        close $ch; set ch ""
        set result [::GX::datasetPublicationV2Finalize $writer]
        set writer ""
    } on error {problem options} {
        if {$ch ne ""} {catch {close $ch}}
        if {$writer ne ""} {catch {::GX::datasetPublicationV2Abort $writer}}
        catch {file delete -force -- $temp}
        return -options $options $problem
    }
    catch {file delete -force -- $temp}
    set metadata [dict create nmr_multi.source_dataset_id $state(dataset_id) \
        nmr_multi.source_sha256 $sourceSha nmr_multi.extraction_kind $kind \
        nmr_multi.plane $state(planeLabel)]
    if {$kind eq "projection_max"} {
        for {set i 0} {$i < [dict get $md nmr_multi.dimensions]} {incr i} {
            if {$i != $yi && $i != $xi} {dict set metadata nmr_multi.projected_axis F[expr {$i+1}]}
        }
    } else {
        dict set metadata nmr_multi.fixed_indices [_coords]
        for {set i 0} {$i < [dict get $md nmr_multi.dimensions]} {incr i} {
            set first [dict get $md nmr_multi.axis_[expr {$i+1}]_ppm_first]
            set last [dict get $md nmr_multi.axis_[expr {$i+1}]_ppm_last]
            set n [dict get $md nmr_multi.axis_[expr {$i+1}]_points]
            set idx [lindex [split [_coords] ,] $i]
            dict set metadata nmr_multi.fixed_f[expr {$i+1}]_ppm [expr {$first+double($idx)/($n-1)*($last-$first)}]
        }
    }
    ::GX::datasetMetadataWrite $session $id $metadata
    set state(status) "Published $kind as Dataset $id."
    return $result
}
proc ::GX::NmrMultiViewer::_publishSafely {kind} {
    variable state
    if {[catch {publish $kind $state(publicationId)} problem]} {
        set state(status) $problem
        tk_messageBox -icon error -title {NMR publication} -message $problem
    }
}
proc ::GX::NmrMultiViewer::open {context} {
    variable window
    variable state
    package require Tk
    set ids [datasets]
    if {![llength $ids]} {error "No acquired 2-D or 3-D NMR Dataset is available"}
    catch {loadState}
    if {$state(dataset_id) ni $ids} {set state(dataset_id) [lindex $ids 0]}
    if {[dict exists $context open_context dataset_id] && [dict get $context open_context dataset_id] in $ids} {
        set state(dataset_id) [dict get $context open_context dataset_id]
    }
    catch {destroy $window}
    toplevel $window
    wm title $window {Multidimensional NMR Viewer}
    wm geometry $window 1230x930+10+10
    ttk::frame $window.controls -padding 8
    ttk::label $window.controls.sourceLabel -text {Acquired Dataset}
    ttk::combobox $window.controls.source -textvariable ::GX::NmrMultiViewer::state(dataset_id) -values $ids -state readonly -width 32
    ttk::label $window.controls.planeLabel -text {Slice plane}
    ttk::combobox $window.controls.plane -textvariable ::GX::NmrMultiViewer::state(planeLabel) -values {F1/F2} -state readonly -width 9
    ttk::label $window.controls.thresholdLabel -text {Contour floor (fraction of max)}
    ttk::spinbox $window.controls.threshold -textvariable ::GX::NmrMultiViewer::state(threshold) -from .005 -to .9 -increment .01 -width 7
    ttk::label $window.controls.levelsLabel -text {Levels}
    ttk::spinbox $window.controls.levels -textvariable ::GX::NmrMultiViewer::state(levels) -from 2 -to 20 -increment 1 -width 4
    ttk::checkbutton $window.controls.positive -text {Positive} -variable ::GX::NmrMultiViewer::state(positive) -command ::GX::NmrMultiViewer::_renderSafely
    ttk::checkbutton $window.controls.negative -text {Negative} -variable ::GX::NmrMultiViewer::state(negative) -command ::GX::NmrMultiViewer::_renderSafely
    ttk::button $window.controls.apply -text {Apply contours} -command ::GX::NmrMultiViewer::_renderSafely
    grid $window.controls.sourceLabel $window.controls.source $window.controls.planeLabel $window.controls.plane $window.controls.thresholdLabel $window.controls.threshold $window.controls.levelsLabel $window.controls.levels -padx 3 -sticky w
    grid $window.controls.positive -row 1 -column 0 -columnspan 2 -sticky w -padx 3
    grid $window.controls.negative -row 1 -column 2 -columnspan 2 -sticky w -padx 3
    grid $window.controls.apply -row 1 -column 4 -columnspan 2 -sticky w -padx 3
    pack $window.controls -side top -fill x
    ttk::frame $window.body -padding 8
    canvas $window.body.canvas -width 860 -height 630 -background white -highlightthickness 1 -highlightbackground #c5cfda
    ttk::frame $window.body.side
    ttk::label $window.body.side.axisTitle -text {Slice coordinates} -font {TkDefaultFont 10 bold}
    ttk::frame $window.body.side.axes
    for {set i 0} {$i < 3} {incr i} {
        ttk::frame $window.body.side.axes.f$i
        ttk::label $window.body.side.axes.f$i.label -width 10
        ttk::scale $window.body.side.axes.f$i.scale -from 0 -to 100 -variable ::GX::NmrMultiViewer::state(i$i) -orient horizontal -length 140
        ttk::label $window.body.side.axes.f$i.value -width 11
        grid $window.body.side.axes.f$i.label $window.body.side.axes.f$i.scale $window.body.side.axes.f$i.value -sticky w -padx 2
        bind $window.body.side.axes.f$i.scale <ButtonRelease-1> {::GX::NmrMultiViewer::_renderSafely}
    }
    ttk::label $window.body.side.sourceTitle -text {Acquisition and source} -font {TkDefaultFont 10 bold}
    ttk::label $window.body.side.details -justify left -anchor nw -wraplength 300
    ttk::label $window.body.side.peakTitle -text {Cross-peaks above contour floor} -font {TkDefaultFont 10 bold}
    ttk::treeview $window.body.side.peaks -columns {x y intensity} -show headings -height 5
    foreach {name label width} {x {X ppm} 85 y {Y ppm} 85 intensity Intensity 110} {
        $window.body.side.peaks heading $name -text $label
        $window.body.side.peaks column $name -width $width -anchor e
    }
    ttk::frame $window.body.side.actions
    ttk::button $window.body.side.actions.reset -text {Reset view} -command ::GX::NmrMultiViewer::_reset
    ttk::button $window.body.side.actions.save -text {Save view} -command ::GX::NmrMultiViewer::saveState
    ttk::label $window.body.side.actions.idLabel -text {Output Dataset ID}
    ttk::entry $window.body.side.actions.id -textvariable ::GX::NmrMultiViewer::state(publicationId) -width 25
    ttk::button $window.body.side.actions.profile -text {Publish X profile} -command {::GX::NmrMultiViewer::_publishSafely profile_x}
    ttk::button $window.body.side.actions.plane -text {Publish plane} -command {::GX::NmrMultiViewer::_publishSafely plane}
    ttk::button $window.body.side.actions.projection -text {Publish max projection} -command {::GX::NmrMultiViewer::_publishSafely projection_max}
    grid $window.body.side.actions.reset $window.body.side.actions.save -sticky ew -pady 3
    grid $window.body.side.actions.idLabel -columnspan 2 -sticky w -pady {12 0}
    grid $window.body.side.actions.id -columnspan 2 -sticky ew
    grid $window.body.side.actions.profile -columnspan 2 -sticky ew -pady 3
    grid $window.body.side.actions.plane -columnspan 2 -sticky ew -pady 3
    grid $window.body.side.actions.projection -columnspan 2 -sticky ew -pady 3
    pack $window.body.side.axisTitle $window.body.side.axes $window.body.side.sourceTitle $window.body.side.details $window.body.side.peakTitle $window.body.side.peaks $window.body.side.actions -side top -fill x -anchor nw -pady 5
    grid $window.body.canvas -row 0 -column 0 -sticky nw -padx {0 10}
    grid $window.body.side -row 0 -column 1 -sticky nsew
    grid columnconfigure $window.body 1 -weight 1
    pack $window.body -side top -fill both -expand 1
    ttk::label $window.status -textvariable ::GX::NmrMultiViewer::state(status) -anchor w -padding 8
    pack $window.status -side bottom -fill x
    bind $window.controls.source <<ComboboxSelected>> {::GX::NmrMultiViewer::_chooseSource}
    bind $window.controls.plane <<ComboboxSelected>> {::GX::NmrMultiViewer::_planeChanged}
    bind $window.body.canvas <Button-1> {::GX::NmrMultiViewer::_click %x %y}
    bind $window.body.canvas <MouseWheel> {::GX::NmrMultiViewer::_zoom %x %y %D}
    bind $window.body.canvas <Button-4> {::GX::NmrMultiViewer::_zoom %x %y 120}
    bind $window.body.canvas <Button-5> {::GX::NmrMultiViewer::_zoom %x %y -120}
    bind $window.body.canvas <ButtonPress-3> {::GX::NmrMultiViewer::_dragStart %x %y}
    bind $window.body.canvas <ButtonRelease-3> {::GX::NmrMultiViewer::_dragEnd %x %y}
    _sourceChanged
    return $window
}
proc ::GX::NmrMultiViewer::viewerDispatch {action scene} {
    if {$action ni {open rerender}} {error "NMR viewer action must be open or rerender"}
    return [open $scene]
}
::GX::viewerBackendRegister nmr_multidimensional_tk ::GX::NmrMultiViewer::viewerDispatch
