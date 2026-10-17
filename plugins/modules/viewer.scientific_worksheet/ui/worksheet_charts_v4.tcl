# SPDX-License-Identifier: GPL-3.0-or-later
# Worksheet chart descriptors belong to the existing Workbook. Scientific
# evaluation, native rendering, History and publication keep their public owners.
namespace eval ::GX::ScientificWorksheet::Charts {variable state;variable edit}
proc ::GX::ScientificWorksheet::Charts::get {d key fallback} {return [::GX::datasetPublicationV2DictDefault $d $key $fallback]}
proc ::GX::ScientificWorksheet::Charts::ui {method args} {tailcall ::GX::ScientificWorksheet::UI::$method {*}$args}
proc ::GX::ScientificWorksheet::Charts::model {method args} {tailcall ::GX::ScientificWorksheet::$method {*}$args}
proc ::GX::ScientificWorksheet::Charts::safe {w method args} {
    if {[catch {[namespace current]::$method $w {*}$args} message]} {ui status $w $message;return 0}
    return 1
}
proc ::GX::ScientificWorksheet::Charts::attach {w area tab} {
    variable state;variable edit
    set state($w,area) $area;set state($w,tab) $tab;set state($w,selected) {};set state($w,frames) {}
    set state($w,serial) 0;set state($w,token) [::GX::interactiveDocumentSessionToken]
    set state($w,areaActive) 0
    set state($w,areaReady) 0
    set state($w,selectedError) {}
    $w.menu.insert add command -label {Native chart from selection} -command [list [namespace current]::safe $w add]
    $w.menu.view add command -label {Chart properties} -command [list $w.body.inspector.tabs select $tab]
    ::GX::ScientificWorksheet::UI::paneScroll $tab
    set p $tab.scroller.content
    ttk::label $p.heading -text {Live native charts};pack $p.heading -anchor w
    ttk::combobox $p.choice -state readonly -textvariable [namespace current]::edit($w,id)
    bind $p.choice <<ComboboxSelected>> [list [namespace current]::selectChoice $w];pack $p.choice -fill x -pady 3
    set row 0;ttk::frame $p.fields;pack $p.fields -fill x
    foreach {field label values} {
        title Title {} x_column {X column} {} y_columns {Y columns} {} right_columns {Right Y columns} {}
        first {First row} {} last {Last row} {} kind Kind {line scatter line_marker step bar}
        panels Panels {overlay separate} color Color {} line_width {Line width} {} marker Marker {none circle square triangle_up triangle_down diamond plus x star}
        legend Legend {none inside above below left right} x_min {X minimum} {} x_max {X maximum} {}
        y_min {Y minimum} {} y_max {Y maximum} {} x_scale {X scale} {linear log} y_scale {Y scale} {linear log}
        annotation {Text annotation} {} z_column {Z column (3D)} {} three_d_kind {3D kind} {line3 scatter3 surface mesh contour3 trisurf heatmap}
    } {
        ttk::label $p.fields.l$field -text $label
        if {$values eq {}} {ttk::entry $p.fields.$field -width 14 -textvariable [namespace current]::edit($w,$field)} else {
            ttk::combobox $p.fields.$field -width 12 -state readonly -values $values -textvariable [namespace current]::edit($w,$field)
        }
        grid $p.fields.l$field -row $row -column 0 -sticky w -pady 2
        grid $p.fields.$field -row $row -column 1 -sticky ew -padx 3 -pady 2;incr row
    }
    grid columnconfigure $p.fields 1 -weight 1
    ttk::frame $p.actions;pack $p.actions -fill x -pady 4
    foreach {name label method} {add {Add selection} add apply Apply apply remove Remove remove fit Fit fit} {
        ttk::button $p.actions.$name -text $label -command [list [namespace current]::safe $w $method]
        pack $p.actions.$name -side left -padx 1
    }
    ttk::button $p.publish -text {Publish immutable Graph to Plots} -command [list [namespace current]::safe $w publish]
    ttk::button $p.native3d -text {Publish and open authentic Native3D} -command [list [namespace current]::safe $w open3D]
    pack $p.publish $p.native3d -fill x -pady 3
    ttk::label $p.error -wraplength 250 -foreground #9b1c1c -textvariable [namespace current]::state($w,selectedError)
    pack $p.error -fill x -pady 3
    ttk::label $p.note -wraplength 250 -text {Drag a chart header to move; drag its lower-right grip to resize. Click native plot objects to select. Wheel zooms, middle drag pans, double-click fits. Source ranges use the bounded scientific Worksheet contract. Publication freezes values and provenance.}
    pack $p.note -fill x -pady 5
    bind $area <Configure> [list [namespace current]::layout $w]
    bind $w <Destroy> +[list [namespace current]::windowDestroyed $w %W]
    refresh $w
}
proc ::GX::ScientificWorksheet::Charts::guard {w} {
    variable state
    ui guard $w
    if {![info exists state($w,token)] || $state($w,token) ne [::GX::interactiveDocumentSessionToken]} {error {Chart belongs to a previous Session}}
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
}
proc ::GX::ScientificWorksheet::Charts::descriptors {w} {return [get [ui book $w] charts {}]}
proc ::GX::ScientificWorksheet::Charts::selected {w} {
    variable state;set charts [descriptors $w]
    if {$state($w,selected) eq {} || ![dict exists $charts $state($w,selected)]} {error {Select or add a chart first}}
    return [dict get $charts $state($w,selected)]
}
proc ::GX::ScientificWorksheet::Charts::change {w id descriptor description} {
    guard $w;set b [ui book $w]
    if {[dict exists [get $b charts {}] $id]} {set b [model chartUpdate $b $id $descriptor]} else {set b [model chartAdd $b $descriptor]}
    return [ui applyBook $w $b $description]
}
proc ::GX::ScientificWorksheet::Charts::add {w} {
    variable state
    guard $w;lassign [ui selection $w] a b
    regexp {^([A-Z]+)([0-9]+)$} $a -> ac ar;regexp {^([A-Z]+)([0-9]+)$} $b -> bc br
    set left [model _columnNumber $ac];set right [model _columnNumber $bc]
    if {$left>$right} {lassign [list $right $left] left right}
    set columns {};for {set c [expr {$left+1}]} {$c<=$right} {incr c} {lappend columns [model _columnName $c]}
    if {$columns eq {}} {lappend columns [model _columnName [expr {$left+1}]]}
    set id chart_1;set n 1;while {[dict exists [descriptors $w] $id]} {set id chart_[incr n]}
    set descriptor [dict create id $id sheet [model activeSheet [ui book $w]] x_column [model _columnName $left] y_columns $columns right_columns {} first [expr {min($ar,$br)}] last [expr {max($ar+1,$br)}] kind line title "Chart $n" panels overlay style {line_width 1.5 marker none} axes {x {scale linear} y_left {scale linear}} legend inside annotation {} geometry [list [expr {0.03+0.04*(($n-1)%4)}] [expr {0.03+0.06*(($n-1)%4)}] .9 .9] revision 1]
    # Evaluate before committing so an invalid draft cannot replace live state.
    presentation [ui book $w] $descriptor
    set state($w,selected) $id
    change $w $id $descriptor {Add native Worksheet chart}
    inspect $w
    $w.body.inspector.tabs select $state($w,tab)
}
proc ::GX::ScientificWorksheet::Charts::selectChoice {w} {variable edit;select $w $edit($w,id)}
proc ::GX::ScientificWorksheet::Charts::select {w id {object chart}} {
    variable state
    guard $w;if {![dict exists [descriptors $w] $id]} {error {Chart no longer exists}}
    set state($w,selected) $id;set state($w,object) $object
    if {[dict exists $state($w,frames) $id]} {raise [dict get $state($w,frames) $id]}
    inspect $w;$w.body.inspector.tabs select $state($w,tab)
    ui status $w "Selected $id · $object"
}
proc ::GX::ScientificWorksheet::Charts::inspect {w} {
    variable edit;variable state;set d [selected $w]
    set id [dict get $d id];set state($w,selectedError) [expr {[info exists state($w,error,$id)]?$state($w,error,$id):{}}]
    foreach field {id title x_column y_columns right_columns first last kind panels annotation} {set edit($w,$field) [get $d $field {}]}
    foreach {field fallback} {color auto line_width 1.5 marker none} {set edit($w,$field) [get [get $d style {}] $field $fallback]}
    foreach {prefix axis} {x x y y_left} {foreach field {min max scale} {set edit($w,${prefix}_$field) [get [get [get $d axes {}] $axis {}] $field [expr {$field eq {scale}?{linear}:{}}]]}}
    set edit($w,legend) [get $d legend inside];set edit($w,z_column) [get $d z_column {}];set edit($w,three_d_kind) [get $d three_d_kind line3]
}
proc ::GX::ScientificWorksheet::Charts::apply {w} {
    variable edit;set d [selected $w];set previous $d
    foreach field {title first last kind panels annotation z_column three_d_kind} {dict set d $field $edit($w,$field)}
    foreach field {x_column y_columns right_columns} {dict set d $field [string toupper $edit($w,$field)]}
    foreach field {color line_width marker} {dict set d style $field $edit($w,$field)}
    dict set d legend $edit($w,legend)
    foreach {prefix axis} {x x y y_left} {foreach field {min max scale} {dict set d axes $axis $field $edit($w,${prefix}_$field)}}
    foreach field {x_column y_columns right_columns first last axes panels} {
        if {[get $d $field {}] ne [get $previous $field {}]} {dict set d view_state {};dict set d view_frame {};break}
    }
    if {[dict get $d kind] ni {line scatter line_marker step bar} || [dict get $d panels] ni {overlay separate}} {error {Unsupported Worksheet chart representation}}
    if {![string is double -strict [dict get $d style line_width]] || [dict get $d style line_width]<=0} {error {Line width must be positive}}
    if {[dict get $d style color] ni {auto inherit {}} && ![regexp {^#[0-9a-fA-F]{6}$} [dict get $d style color]]} {error {Color must be auto or #RRGGBB}}
    presentation [ui book $w] $d;dict incr d revision
    change $w [dict get $d id] $d {Edit native chart properties}
    if {[dict get $d panels] eq {separate}} {after idle [list [namespace current]::ensureArea $w]}
}
proc ::GX::ScientificWorksheet::Charts::presentation {book descriptor} {
    set b [model selectSheet $book [dict get $descriptor sheet]]
    set first [dict get $descriptor first];set last [dict get $descriptor last]
    set xc [dict get $descriptor x_column];set columns [dict get $descriptor y_columns]
    if {![llength $columns]} {error {Choose at least one Y column}}
    set x [model columnValues $b $xc $first $last];set panels {};set all {};set units {};set i 0
    set xUnit [get [get [get $descriptor axes {}] x {}] display_unit [dict get $x unit]]
    if {$xUnit in {source auto inherit}} {set xUnit [dict get $x unit]}
    set xConversion [::GX::unitRegistryAffinePlan [dict get $x unit] $xUnit]
    foreach col $columns {
        incr i;set y [model columnValues $b $col $first $last]
        set side [expr {$col in [get $descriptor right_columns {}]?{right}:{left}}]
        set unitKey [expr {[dict get $descriptor panels] eq {separate}?$col:$side}]
        set sourceUnit [dict get $y unit]
        if {![dict exists $units $unitKey]} {
            set canonicalAxis [expr {$side eq {right}?{y_right}:{y_left}}]
            set target [get [get [get $descriptor axes {}] $canonicalAxis {}] display_unit $sourceUnit]
            if {$target in {source auto inherit}} {set target $sourceUnit}
            dict set units $unitKey $target
        }
        set targetUnit [dict get $units $unitKey]
        if {[catch {set conversion [::GX::unitRegistryAffinePlan $sourceUnit $targetUnit]}]} {error {Incompatible Y dimensions require separate panels or a right Y axis}}
        set points {};set rows {};set breaks {};set source {};set priorValid 0;set ordinal 0
        set bounds [list Inf Inf -Inf -Inf]
        foreach xv [dict get $x values] yv [dict get $y values] xl [dict get $x row_lineage] yl [dict get $y row_lineage] {
            set finite [expr {[string is double -strict $xv] && [string is double -strict $yv]}]
            if {$finite} {if {[catch {expr {abs($xv)<Inf && abs($yv)<Inf}} finite]} {set finite 0}}
            if {!$finite} {set priorValid 0;incr ordinal;continue}
            set xv [expr {$xv*[dict get $xConversion scale]+[dict get $xConversion offset]}]
            set yv [expr {$yv*[dict get $conversion scale]+[dict get $conversion offset]}]
            if {!$priorValid && [llength $points]} {lappend breaks [expr {[llength $points]-1}]}
            lappend points [list $xv $yv];lappend rows [dict get $xl source_row_identity]
            lappend source [dict create x $xl y $yl worksheet_row [expr {$first+$ordinal}]]
            foreach index {0 1 2 3} value [list $xv $yv $xv $yv] {lset bounds $index [expr {$index<2?min([lindex $bounds $index],$value):max([lindex $bounds $index],$value)}]}
            set priorValid 1;incr ordinal
        }
        if {![llength $points]} {error "No finite coordinate pairs in $xc / $col"}
        set series [dict create id series_$i label $col axis $side kind [dict get $descriptor kind] style [dict get $descriptor style] points $points source_rows $rows breaks $breaks full_bounds $bounds worksheet_lineage $source coordinate_mapping [dict merge $conversion [dict create source_unit $sourceUnit display_unit $targetUnit]]]
        set axes [dict get $descriptor axes]
        dict set axes x label "$xc $xUnit";dict set axes x display_unit $xUnit;dict set axes $side label "$col $targetUnit";dict set axes $side display_unit $targetUnit
        foreach {canonical native} {y_left left y_right right} {if {[dict exists $axes $canonical]} {dict set axes $native [dict merge [get $axes $native {}] [dict get $axes $canonical]]}}
        if {[dict get $descriptor panels] eq {separate}} {lappend panels [dict create id panel_$i axes $axes series [list $series] annotations [annotations $descriptor $bounds]]} else {lappend all $series}
    }
    if {[dict get $descriptor panels] eq {overlay}} {set panels [list [dict create id main axes $axes series $all annotations [annotations $descriptor $bounds]]]}
    return [dict create title [dict get $descriptor title] panels $panels native_presentation [dict create schema GXTXT_NATIVE_GRAPH_PRESENTATION_v1 graphics {} axes {} panels {} layout {} legend [dict create placement [get $descriptor legend inside]]]]
}
proc ::GX::ScientificWorksheet::Charts::annotations {descriptor bounds} {
    set text [get $descriptor annotation {}];if {$text eq {}} {return {}}
    lassign $bounds xl yl xh yh
    return [list [dict create type text axis left label $text x [expr {$xl+.08*($xh-$xl)}] y [expr {$yh-.12*($yh-$yl)}]]]
}
proc ::GX::ScientificWorksheet::Charts::refresh {w} {
    variable state
    if {![info exists state($w,area)] || ![winfo exists $state($w,area)]} return
    set charts [descriptors $w];set area $state($w,area);set book [ui book $w]
    set choice $state($w,tab).scroller.content.choice;$choice configure -values [dict keys $charts]
    foreach id [dict keys $state($w,frames)] {if {![dict exists $charts $id]} {set f [dict get $state($w,frames) $id];::GX::PlotDatasetAPIv4::widgetDestroy $f.plot;::destroy $f;dict unset state($w,frames) $id;catch {unset state($w,rendered,$id)}}}
    dict for {id d} $charts {
        if {![dict exists $state($w,frames) $id]} {
            set f $area.c[incr state($w,serial)];ttk::frame $f -borderwidth 2 -relief ridge
            ttk::label $f.header -text [dict get $d title] -cursor fleur;pack $f.header -fill x
            bind $f.header <ButtonPress-1> [list [namespace current]::begin $w $id move %X %Y]
            bind $f.header <B1-Motion> [list [namespace current]::motion $w %X %Y]
            bind $f.header <ButtonRelease-1> [list [namespace current]::finish $w]
            ttk::label $f.grip -text {◢} -cursor bottom_right_corner;pack $f.grip -side bottom -anchor e
            bind $f.grip <ButtonPress-1> [list [namespace current]::begin $w $id resize %X %Y]
            bind $f.grip <B1-Motion> [list [namespace current]::motion $w %X %Y]
            bind $f.grip <ButtonRelease-1> [list [namespace current]::finish $w]
            dict set state($w,frames) $id $f
        }
        set f [dict get $state($w,frames) $id];$f.header configure -text [dict get $d title]
        set stamp [list [dict get $book revision] [dict get $d revision] [model activeSheet $book]]
        if {[info exists state($w,rendered,$id)] && $state($w,rendered,$id) eq $stamp} continue
        if {[catch {
            guard $w;set native [presentation $book $d]
            if {[winfo exists $f.plot]} {::GX::PlotDatasetAPIv4::widgetConfigure $f.plot $native {prepared_model 1}} else {
                ::GX::PlotDatasetAPIv4::widgetCreate $f.plot $native {prepared_model 1};pack $f.plot -fill both -expand 1
                bind $f.plot <ButtonPress-1> [list [namespace current]::hit $w $id %x %y]
                foreach event {<Button-4> <Button-5> <MouseWheel> <ButtonRelease-2>} {bind $f.plot $event +[list [namespace current]::queueView $w $id 0]}
                bind $f.plot <Double-Button-1> +[list [namespace current]::queueView $w $id 1]
            }
            set state($w,view_frame,$id) [viewFrame $d $native]
            if {[get $d view_state {}] ne {} && [get $d view_frame {}] eq $state($w,view_frame,$id)} {::GX::PlotDatasetAPIv4::widgetView $f.plot restore [dict get $d view_state]}
            catch {unset state($w,error,$id)}
            if {$state($w,selected) eq $id} {set state($w,selectedError) {}}
            set state($w,rendered,$id) $stamp
        } message]} {
            set state($w,error,$id) "Chart source is unavailable: $message. The last valid representation is retained."
            $f.header configure -text "[dict get $d title] · Source unavailable (last valid view)"
            if {$state($w,selected) eq $id} {set state($w,selectedError) $state($w,error,$id)}
            ui status $w $state($w,error,$id)
        }
    }
    if {$state($w,selected) eq {} && [dict size $charts]} {set state($w,selected) [lindex [dict keys $charts] 0];inspect $w}
    if {![dict size $charts]} {set state($w,selected) {}}
    if {[dict size $charts] && !$state($w,areaActive)} {set state($w,areaActive) 1;after idle [list [namespace current]::ensureArea $w]}
    if {![dict size $charts]} {set state($w,areaActive) 0;set state($w,areaReady) 0}
    layout $w
}
proc ::GX::ScientificWorksheet::Charts::ensureArea {w} {
    variable state
    if {![info exists state($w,area)] || ![winfo exists $w.body.main]} return
    catch {unset state($w,areaPending)}
    set total [winfo height $w.body.main]
    if {$total<=420} return
    set state($w,areaReady) 1
    set required 280
    dict for {id d} [descriptors $w] {
        if {[get $d panels overlay] eq {separate}} {set required [expr {max($required,130*[llength [dict get $d y_columns]]+100)}]}
    }
    set required [expr {min($required,$total-160)}]
    if {[winfo height $state($w,area)]<$required-20} {$w.body.main sashpos 0 [expr {$total-$required}]}
    layout $w
}
proc ::GX::ScientificWorksheet::Charts::layout {w} {
    variable state;if {![info exists state($w,area)] || ![winfo exists $state($w,area)]} return
    set area $state($w,area);set width [winfo width $area];set height [winfo height $area]
    if {$state($w,areaActive) && !$state($w,areaReady) && ![info exists state($w,areaPending)] && [winfo height $w.body.main]>420} {set state($w,areaPending) [after idle [list [namespace current]::ensureArea $w]]}
    dict for {id f} $state($w,frames) {if {![dict exists [descriptors $w] $id]} continue;set d [dict get [descriptors $w] $id];set minimum [expr {[get $d panels overlay] eq {separate}?max(220,130*[llength [dict get $d y_columns]]+60):220}];lassign [dict get $d geometry] x y sw sh;place $f -x [expr {round($x*$width)}] -y [expr {round($y*$height)}] -width [expr {max(250,round($sw*$width))}] -height [expr {max($minimum,round($sh*$height))}]}
}
proc ::GX::ScientificWorksheet::Charts::begin {w id operation x y} {
    variable state;select $w $id
    set state($w,gesture) [dict create id $id operation $operation x $x y $y geometry [dict get [selected $w] geometry] token $state($w,token) revision [dict get [ui book $w] revision]]
}
proc ::GX::ScientificWorksheet::Charts::motion {w x y} {
    variable state;if {![info exists state($w,gesture)]} return
    set g $state($w,gesture);lassign [dict get $g geometry] px py sw sh
    set area $state($w,area);set width [expr {max(1,[winfo width $area])}];set height [expr {max(1,[winfo height $area])}]
    set dx [expr {($x-[dict get $g x])/double($width)}];set dy [expr {($y-[dict get $g y])/double($height)}]
    if {[dict get $g operation] eq {move}} {set px [expr {max(0.,min(.85,$px+$dx))}];set py [expr {max(0.,min(.85,$py+$dy))}]} else {set sw [expr {max(250./$width,min(1.5,$sw+$dx))}];set sh [expr {max(220./$height,min(1.5,$sh+$dy))}]}
    set geometry [list $px $py $sw $sh];dict set state($w,gesture) proposed $geometry
    set f [dict get $state($w,frames) [dict get $g id]];place $f -x [expr {round($px*$width)}] -y [expr {round($py*$height)}] -width [expr {round($sw*$width)}] -height [expr {round($sh*$height)}]
}
proc ::GX::ScientificWorksheet::Charts::finish {w} {
    variable state;if {![info exists state($w,gesture)]} return
    set g $state($w,gesture);unset state($w,gesture)
    if {![dict exists $g proposed]} return
    if {[catch {guard $w} message] || [dict get [ui book $w] revision]!=[dict get $g revision]} {layout $w;ui status $w {Chart gesture discarded because its source revision changed};return}
    set d [dict get [descriptors $w] [dict get $g id]];dict set d geometry [dict get $g proposed];dict incr d revision
    change $w [dict get $d id] $d "[string totitle [dict get $g operation]] native chart"
}
proc ::GX::ScientificWorksheet::Charts::hit {w id x y} {variable state;set f [dict get $state($w,frames) $id];select $w $id [::GX::PlotDatasetAPIv4::widgetHit $f.plot $x $y]}
proc ::GX::ScientificWorksheet::Charts::viewFrame {descriptor native} {
    set result [list [dict get $descriptor sheet] [dict get $descriptor x_column] [dict get $descriptor y_columns] [get $descriptor right_columns {}]]
    foreach panel [dict get $native panels] {
        set axes {};dict for {axis fields} [dict get $panel axes] {dict set axes $axis [list [get $fields display_unit {}] [get $fields scale linear] [get $fields direction normal]]}
        set units {};foreach series [dict get $panel series] {lappend units [list [dict get $series id] [dict get $series axis] [dict get $series coordinate_mapping display_unit]]}
        lappend result [list [dict get $panel id] $axes $units]
    }
    return $result
}
proc ::GX::ScientificWorksheet::Charts::queueView {w id fitted} {
    variable state
    if {![info exists state($w,token)]} return
    if {[info exists state($w,view_pending,$id)]} {after cancel $state($w,view_pending,$id)}
    set state($w,view_pending,$id) [after idle [list [namespace current]::captureView $w $id $fitted [dict get [ui book $w] revision]]]
}
proc ::GX::ScientificWorksheet::Charts::captureView {w id fitted revision} {
    variable state;catch {unset state($w,view_pending,$id)}
    if {[catch {guard $w}] || [dict get [ui book $w] revision]!=$revision || ![dict exists [descriptors $w] $id]} return
    set d [dict get [descriptors $w] $id]
    if {$fitted} {
        if {[get $d view_state {}] eq {}} return
        dict set d view_state {};dict set d view_frame {}
    } else {
        set f [dict get $state($w,frames) $id]
        dict set d view_state [dict get [::GX::PlotDatasetAPIv4::widgetReceipt $f.plot] axes]
        dict set d view_frame $state($w,view_frame,$id)
    }
    change $w $id $d [expr {$fitted?{Fit native chart view}:{Change native chart viewport}}]
}
proc ::GX::ScientificWorksheet::Charts::fit {w} {variable state;guard $w;set d [selected $w];::GX::PlotDatasetAPIv4::widgetView [dict get $state($w,frames) [dict get $d id]].plot fit;queueView $w [dict get $d id] 1}
proc ::GX::ScientificWorksheet::Charts::remove {w} {guard $w;set d [selected $w];ui applyBook $w [model chartRemove [ui book $w] [dict get $d id]] {Remove Worksheet chart}}
proc ::GX::ScientificWorksheet::Charts::publish {w {threeD 0}} {
    guard $w;set d [selected $w]
    if {[dict get [ui book $w] document_id] eq {}} {ui save $w}
    set b [model selectSheet [ui book $w] [dict get $d sheet]]
    set mappings [dict create x [dict get $d x_column]];set i 0
    foreach col [dict get $d y_columns] {dict set mappings y[incr i] $col}
    if {$threeD} {if {[get $d z_column {}] eq {}} {error {Choose a Z column before 3D publication}};dict set mappings z [dict get $d z_column]}
    set datasetId worksheet_chart_[clock microseconds]
    model publish $b $mappings [dict get $d first] [dict get $d last] $datasetId [dict get $d title]
    if {$threeD} {
        set spec [dict create schema PLOT_DATASET_PLOTSPEC_v2 graph_type cartesian_3d graph_id plot.dataset.xyz dataset_id $datasetId x_variable_id x y_variable_id y1 z_variable_id z title [dict get $d title] config [dict create plot_type [get $d three_d_kind line3]]]
    } else {
        set p [presentation $b $d];set panels {};set i 0
        foreach panel [dict get $p panels] {
            set series {};foreach s [dict get $panel series] {incr i;set col [dict get $s label];lappend series [dict create id [dict get $s id] dataset_id $datasetId x_variable_id x y_variable_id y$i kind [dict get $d kind] label $col axis [dict get $s axis] style [dict get $d style]]}
            set axes [dict get $panel axes];foreach {native canonical} {left y_left right y_right} {if {[dict exists $axes $native]} {dict set axes $canonical [dict get $axes $native];dict unset axes $native}}
            lappend panels [dict replace $panel axes $axes series $series]
        }
        set spec [dict create schema PLOT_DATASET_PLOTSPEC_v2 graph_type cartesian_2d graph_id plot.dataset.xy title [dict get $d title] defaults {style {}} panels $panels native_presentation [dict get $p native_presentation] output {}]
    }
    if {[catch {
        set ref [::GX::PlotDatasetAPIv4::createPlotFromSpec $spec variant]
        ::GX::PlotDatasetAPIv4::render $ref
        set graph [dict merge {kind provider module_id plot.dataset} $ref]
        ::GX::graphMetadataUpdate $graph [dict create worksheet.document_id [dict get $b document_id] worksheet.chart_id [dict get $d id] worksheet.source_revision [dict get $b revision] worksheet.published_dataset_id $datasetId]
        ::GX::sessionPersistenceCommit
    } message options]} {return -options $options "Dataset $datasetId was published and preserved; native Graph publication failed: $message"}
    dict lappend d published_graphs [dict create graph $graph dataset_id $datasetId source_revision [dict get $b revision]]
    dict incr d revision;change $w [dict get $d id] $d {Record immutable chart publication}
    ::GX::refreshGraphs;ui status $w "Published immutable Dataset $datasetId and native Graph $ref"
    return $ref
}
proc ::GX::ScientificWorksheet::Charts::open3D {w} {set ref [publish $w 1];return [::GX::PlotDatasetAPIv4::openInteractive $ref]}
proc ::GX::ScientificWorksheet::Charts::windowDestroyed {w actual} {if {$actual eq $w} {destroy $w}}
proc ::GX::ScientificWorksheet::Charts::destroy {w} {
    variable state;variable edit
    if {[info exists state($w,areaPending)]} {after cancel $state($w,areaPending)}
    foreach name [array names state $w,view_pending,*] {after cancel $state($name)}
    if {[info exists state($w,frames)]} {dict for {id f} $state($w,frames) {catch {::GX::PlotDatasetAPIv4::widgetDestroy $f.plot}}}
    array unset state $w,*;array unset edit $w,*
}
