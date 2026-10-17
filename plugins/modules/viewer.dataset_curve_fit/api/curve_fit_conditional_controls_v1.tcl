# SPDX-License-Identifier: GPL-3.0-or-later
# GUI presentation only. Retain widgets and saved values across model changes.
proc ::GX::DatasetCurveFit::_settingsControlsLayout {w area width} {
    variable state
    set parent $w.left.viewport.content.settings.$area
    if {![winfo exists $parent]} return
    set model $state($w,model);set hidden {}
    if {$area eq "parameters"} {
        foreach field {degree initial period smoothing min max samples} {
            set show 0
            switch $field {
                degree {set show [expr {$model in {polynomial parametric_polynomial fourier}}]}
                initial {set show [expr {$model in {exponential power_law gaussian registered}||($model in {linear polynomial}&&$state($w,measurementKind) eq "sigma_xy")}]}
                period {set show [expr {$model eq "fourier"}]}
                smoothing {set show [expr {$model eq "smoothing_spline"}]}
                min - max - samples {set show [expr {$state($w,domain) in {range parameter}}]}
            }
            if {!$show} {lappend hidden $parent.l_$field $parent.$field}
        }
    } else {
        foreach field {components regions formula rational knots implicit complex_response registered parametric polar} {
            set show [expr {$model eq $field}]
            if {$field eq "knots"} {set show [expr {$model in {akima bspline}}]}
            if {$field eq "parametric"} {set show [expr {$model in {parametric_polynomial parametric_spline}}]}
            if {$field eq "polar"} {set show [expr {$state($w,orientation) eq "r_of_theta"}]}
            if {!$show} {lappend hidden $parent.$field}
        }
    }
    set children {};set focused [focus]
    foreach child [winfo children $parent] {
        if {$child in $hidden} {
            if {$focused eq $child} {focus $w.left.viewport.content.settings.body.model}
            pack forget $child;grid remove $child
        } else {lappend children $child}
    }
    # A narrow scrolling sidebar needs a stable label/input column pair.
    # Do not combine the widest label from one row with the widest field from
    # another: that can exceed the viewport even when each pair fits alone.
    foreach child $children {pack forget $child;grid remove $child}
    grid columnconfigure $parent 0 -weight 0 -minsize 0
    grid columnconfigure $parent 1 -weight 1 -minsize 0
    set row 0;set index 0
    while {$index<[llength $children]} {
        set child [lindex $children $index];incr index
        set next [lindex $children $index]
        if {[winfo class $child] in {TLabel Label}&&$next ne {}&&[winfo class $next] in {TEntry TCombobox Entry Combobox}} {
            $child configure -wraplength [expr {max(48,int(.42*$width)-12)}]
            $next configure -width 1
            grid $child -row $row -column 0 -columnspan 1 -sticky w -padx 3 -pady 2
            grid $next -row $row -column 1 -columnspan 1 -sticky ew -padx 3 -pady 2
            incr index
        } else {
            if {[winfo class $child] eq "TButton"} {$child configure -width 1}
            grid $child -row $row -column 0 -columnspan 2 -sticky ew -padx 3 -pady 2
        }
        incr row
    }
    if {![llength $children]} {$parent configure -height 1}
}
proc ::GX::DatasetCurveFit::_refreshSettingsControls {w} {
    foreach area {body parameters} {
        set parent $w.left.viewport.content.settings.$area
        if {[winfo exists $parent]} {_settingsControlsLayout $w $area [winfo width $parent]}
    }
}
proc ::GX::DatasetCurveFit::_technicalResultText {result} {
    if {$result eq {}||![dict exists $result statistical_results training]} {return {Preview a current fit to inspect its technical details.}}
    set content [::GX::StatisticsV1::solverReport [dict get $result statistical_results training] 1]
    if {[dict exists $result registered_model_state]} {
        set saved [dict get $result registered_model_state]
        append content "\n\nRegistered solver: [dict get $saved solver]\nRaw convergence flag: [dict get $saved converged]\nFunction evaluations: [dict get $saved function_evaluations]\n[dict get $saved message]"
    }
    foreach field {model_state_json model_state_resource numeric_model_state_sha256} {
        if {![dict exists $result $field]} continue
        if {$field eq "model_state_json"} {append content "\nModel state: [string length [encoding convertto utf-8 [dict get $result $field]]] UTF-8 bytes (inline)."} else {append content "\n$field: [dict get $result $field]"}
    }
    foreach field {geometry_resource residual_resource source_rows_resource prediction_resource} {
        if {[dict exists $result $field]} {append content "\n$field: [dict get $result $field]"}
    }
    return $content
}
proc ::GX::DatasetCurveFit::_technicalDetailsRender {w} {
    variable state
    set parent $w.right.report.technical
    if {![winfo exists $parent]} return
    if {!$state($w,technicalExpanded)} {_reportViewportFit $w [winfo height $w.right];return}
    set content [_technicalResultText $state($w,preview)]
    $parent.text configure -state normal;$parent.text delete 1.0 end
    $parent.text insert end $content;$parent.text configure -state disabled
    _reportViewportFit $w [winfo height $w.right]
    _reportControlSee $w $parent.text
}
proc ::GX::DatasetCurveFit::_technicalDetailsCreate {w} {
    variable state
    set state($w,technicalExpanded) 0
    ttk::checkbutton $w.right.report.technicalToggle -text {Show technical details} -variable ::GX::DatasetCurveFit::state($w,technicalExpanded) -command [list ::GX::DatasetCurveFit::_technicalDetailsRender $w]
    pack $w.right.report.technicalToggle -anchor w -padx 8
    set parent $w.right.report.technical
    ttk::frame $parent
    text $parent.text -height 6 -width 1 -wrap word -state disabled -yscrollcommand [list $parent.scroll set]
    ttk::scrollbar $parent.scroll -command [list $parent.text yview]
    grid $parent.text -row 0 -column 0 -sticky nsew;grid $parent.scroll -row 0 -column 1 -sticky ns
    grid columnconfigure $parent 0 -weight 1;grid rowconfigure $parent 0 -weight 1
}
proc ::GX::DatasetCurveFit::_reportViewportCreate {w} {
    # The existing report path is the actual clipping canvas. All controls
    # retain their existing parent paths, identities and event bindings.
    set canvas $w.right.report
    ttk::scrollbar $canvas.scroll -command [list $canvas yview]
    $canvas configure -yscrollcommand [list $canvas.scroll set]
    place $canvas.scroll -relx 1 -y 0 -anchor ne -relheight 1
    bind $w.right <Configure> [list ::GX::DatasetCurveFit::_reportViewportFit $w %h]
    bind $w.right.residuals <Configure> [list ::GX::DatasetCurveFit::_reportViewportRefresh $w]
    pack $canvas -side bottom -fill x
}
proc ::GX::DatasetCurveFit::_reportViewportRefresh {w} {_reportViewportFit $w [winfo height $w.right]}
proc ::GX::DatasetCurveFit::_reportViewportFit {w height} {
    variable state
    set canvas $w.right.report
    if {![winfo exists $canvas]||![info exists state($w,technicalExpanded)]} return
    set y 0;set width [expr {max(1,[winfo width $canvas]-[winfo reqwidth $canvas.scroll]-16)}]
    foreach field {result parameters parameterScroll parameterDetail quality technicalToggle technical} {
        set child $canvas.$field
        if {![winfo exists $child]} continue
        if {[winfo manager $child] eq "pack"} {pack forget $child}
        set tag control_$field
        if {[$canvas find withtag $tag] eq {}} {$canvas create window 8 $y -window $child -anchor nw -width $width -tags $tag}
        if {$field eq "technical"&&!$state($w,technicalExpanded)} {$canvas itemconfigure $tag -state hidden;continue}
        $canvas itemconfigure $tag -state normal -width $width
        $canvas coords $tag 8 $y
        incr y [expr {[winfo reqheight $child]+2}]
    }
    set plotReserve [expr {max(190,5*[font metrics TkDefaultFont -linespace]+40)}]
    set remaining [expr {$height-max([winfo reqheight $w.right.residuals],[winfo height $w.right.residuals])-$plotReserve}]
    set wanted [expr {max(80,min($y,int(.42*$height),$remaining))}]
    if {[$canvas cget -height]!=$wanted} {$canvas configure -height $wanted}
    $canvas configure -scrollregion [list 0 0 [expr {$width+16}] $y]
    raise $canvas.scroll
}
proc ::GX::DatasetCurveFit::_reportControlSee {w widget} {
    set canvas $w.right.report;set child $widget
    while {[winfo parent $child] ne $canvas&&$child ne $w} {set child [winfo parent $child]}
    set box [$canvas bbox control_[winfo name $child]]
    if {$box eq {}} return
    set top [$canvas canvasy 0];set bottom [expr {$top+[winfo height $canvas]}]
    lassign $box x y right lower
    set total [lindex [$canvas cget -scrollregion] 3]
    if {$y<$top} {$canvas yview moveto [expr {$y/double(max(1,$total))}]} elseif {$lower>$bottom} {$canvas yview moveto [expr {max(0,($lower-[winfo height $canvas])/double(max(1,$total)))}]}
}
proc ::GX::DatasetCurveFit::_reportScrollBindings {w} {
    foreach child [::GX::_viewerCommandsDescendants $w.right.report] {
        bind $child <FocusIn> +[list ::GX::DatasetCurveFit::_reportControlSee $w $child]
        if {[winfo class $child] in {TLabel TCheckbutton}} {
            bind $child <Button-4> +[list $w.right.report yview scroll -3 units]
            bind $child <Button-5> +[list $w.right.report yview scroll 3 units]
        }
    }
}
