# Reusable Numeric model cards; this viewer owns only controls and input bindings.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::componentCatalog {} {
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    return [dict get [::GX::NumericAPIv1::callOperation fit_model_catalog {}] models]
}
proc ::GX::DatasetCurveFit::_componentRecipeNode {recipe} {
    set fields {};set components {}
    foreach key [dict keys $recipe] {if {$key ni {components parameters x_unit y_unit}} {error "Unknown component recipe field: $key"}}
    foreach component [dict get $recipe components] {
        set item {}
        dict for {key value} $component {
            switch -- $key {
                id - model_id {set node [::GX::ScientificTransportv1::text $value]}
                initial_parameters {set node [::GX::ScientificTransportv1::array [list [llength $value] 1] $value]}
                bindings {set bindings {};dict for {name identity} $value {dict set bindings $name [::GX::ScientificTransportv1::text $identity]};set node [::GX::ScientificTransportv1::struct $bindings]}
                default {error "Unknown component field: $key"}
            }
            dict set item $key $node
        }
        lappend components [::GX::ScientificTransportv1::struct $item]
    }
    dict set fields components [dict create kind cell items $components]
    foreach key {x_unit y_unit} {dict set fields $key [::GX::ScientificTransportv1::text [dict get $recipe $key]]}
    set overrides {}
    dict for {id values} [::GX::datasetPublicationV2DictDefault $recipe parameters {}] {
        set item {};dict for {key value} $values {
            if {$key ni {initial lower upper fixed}} {error "Unknown parameter constraint: $key"}
            dict set item $key [::GX::ScientificTransportv1::array {1 1} [list $value]]
        }
        dict set overrides $id [::GX::ScientificTransportv1::struct $item]
    }
    dict set fields parameters [::GX::ScientificTransportv1::struct $overrides]
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::DatasetCurveFit::_componentUnits {w orientation} {
    if {$orientation ni {y_of_x x_of_y}} {error {Component fitting supports Y=f(X) or X=f(Y); choose a functional orientation}}
    set axes [dict get [_sourceProvenance $w] source_axes]
    set x [dict get $axes x unit];set y [dict get $axes y unit]
    if {$x eq {}} {set x unspecified};if {$y eq {}} {set y unspecified}
    if {$orientation eq "x_of_y"} {return [dict create x_unit $y y_unit $x]}
    return [dict create x_unit $x y_unit $y]
}
proc ::GX::DatasetCurveFit::_resolveComponents {recipe} {
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    return [::GX::NumericAPIv1::callOperation fit_model_compose [list [_componentRecipeNode $recipe]]]
}
proc ::GX::DatasetCurveFit::_prepareComponents {w options} {
    if {![dict exists $options component_recipe]} {error {Configure model components first}}
    set recipe [dict get $options component_recipe]
    dict for {key value} [_componentUnits $w [::GX::datasetPublicationV2DictDefault $options orientation y_of_x]] {
        if {[dict exists $recipe $key]&&[dict get $recipe $key] ne $value} {error {Component units differ from the current axes; review component settings}}
        dict set recipe $key $value
    }
    return [_resolveComponents $recipe]
}
proc ::GX::DatasetCurveFit::_componentSettings {w} {
    variable state
    _assertLoaded $w
    set d $w.components
    if {[winfo exists $d]} {raise $d;return}
    set state($d,owner) $state($w,activeSource);set state($d,orientation) $state($w,orientation)
    set state($d,cards) {};set labels {}
    foreach card [componentCatalog] {dict set state($d,cards) [dict get $card id] $card;lappend labels [dict get $card name]}
    set state($d,choice) [lindex $labels 0];set state($d,serial) 0;set state($d,rows) {}
    toplevel $d;wm title $d {Model components};wm transient $d $w
    wm geometry $d 980x530;wm minsize $d 720 400
    ttk::frame $d.top -padding 8;pack $d.top -fill x
    ttk::combobox $d.top.model -values $labels -state readonly -width 40 -textvariable ::GX::DatasetCurveFit::state($d,choice)
    ttk::button $d.top.add -text {Add component} -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_componentAddChoice $w $d]]
    ttk::button $d.top.remove -text {Remove selected component} -command [list ::GX::DatasetCurveFit::_componentRemove $d]
    pack $d.top.model $d.top.add $d.top.remove -side left -padx 4
    set units [_componentUnits $w $state($w,orientation)]
    ttk::label $d.help -text "Components are summed in one fit. X: [dict get $units x_unit]; Y: [dict get $units y_unit]. Review initial values and bounds. Use the same shared name to tie parameters with matching units and initial values. Blank bounds use the model domain." -wraplength 900
    pack $d.help -fill x -padx 12 -pady 5
    bind $d <Configure> [list ::GX::DatasetCurveFit::_componentDialogLayout $d %W %w]
    ttk::notebook $d.tabs;pack $d.tabs -fill both -expand 1 -padx 8
    set recipe $state($w,componentRecipe)
    if {$recipe ne {}} {
        foreach component [dict get $recipe components] {_componentAdd $d $component [::GX::datasetPublicationV2DictDefault $recipe parameters {}]}
    }
    ttk::frame $d.actions -padding 8;pack $d.actions -side bottom -fill x -before $d.tabs
    ttk::button $d.actions.apply -text {Apply components} -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_componentApply $w $d]]
    ttk::button $d.actions.cancel -text Cancel -command [list destroy $d]
    pack $d.actions.cancel $d.actions.apply -side right -padx 4
}
proc ::GX::DatasetCurveFit::_componentAddChoice {w d} {
    variable state
    dict for {id card} $state($d,cards) {if {[dict get $card name] eq $state($d,choice)} {
        set serial [incr state($d,serial)]
        while {[lsearch -exact [lmap page $state($d,rows) {set state($page,id)}] c$serial]>=0} {set serial [incr state($d,serial)]}
        _componentAdd $d [dict create id c$serial model_id $id initial_parameters [dict get $card initial_parameters]] {};return
    }}
}
proc ::GX::DatasetCurveFit::_componentAdd {d component overrides} {
    variable state
    if {[llength $state($d,rows)]>=32} {error {At most 32 components are supported}}
    set id [dict get $component model_id]
    if {![dict exists $state($d,cards) $id]} {error "Saved component descriptor is unavailable: $id. Accepted fits retain their frozen model."}
    set card [dict get $state($d,cards) $id];set page $d.tabs.p[incr state($d,serial)]
    ttk::frame $page -padding 10;$d.tabs add $page -text [dict get $component id];$d.tabs select $page
    set body [::GX::scrollableDialogBody $page]
    $page.viewport.canvas configure -width 100 -height 100
    lappend state($d,rows) $page;set state($page,id) [dict get $component id];set state($page,model) $id
    ttk::label $body.title -text [dict get $card name];grid $body.title -row 0 -column 0 -columnspan 6 -sticky w
    ttk::label $body.equation -text "Equation: [dict get $card expression]";grid $body.equation -row 1 -column 0 -columnspan 6 -sticky w -pady 5
    set column 0
    foreach label {{Parameter / unit} Initial Lower Upper Fixed {Shared name (optional)}} {ttk::label $body.h$column -text $label;grid $body.h$column -row 2 -column $column -sticky w -padx 4;incr column}
    $body.h5 configure -text "Shared name\n(optional)"
    set j 0
    foreach parameter [dict get $card parameter_ids] role [dict get $card parameter_units] domain [dict get $card parameter_domains] {
        set identity [dict get $component id]_$parameter
        set bound [::GX::datasetPublicationV2DictDefault [::GX::datasetPublicationV2DictDefault $component bindings {}] $parameter $identity]
        set values [::GX::datasetPublicationV2DictDefault $overrides $bound {}]
        set state($page,$parameter,initial) [::GX::datasetPublicationV2DictDefault $values initial [lindex [dict get $component initial_parameters] $j]]
        foreach field {lower upper} {set state($page,$parameter,$field) [::GX::datasetPublicationV2DictDefault $values $field {}]}
        set state($page,$parameter,fixed) [::GX::datasetPublicationV2DictDefault $values fixed 0]
        set state($page,$parameter,shared) [expr {$bound eq $identity?{}:$bound}]
        set row [expr {$j+3}];ttk::label $body.p$j -text "$parameter ($role; $domain)";grid $body.p$j -row $row -column 0 -sticky w -padx 4 -pady 5
        set column 1
        foreach field {initial lower upper fixed shared} {
            if {$field eq "fixed"} {ttk::checkbutton $body.${field}$j -variable ::GX::DatasetCurveFit::state($page,$parameter,$field)} else {ttk::entry $body.${field}$j -width 10 -textvariable ::GX::DatasetCurveFit::state($page,$parameter,$field)}
            grid $body.${field}$j -row $row -column $column -sticky ew -padx 4;incr column
        }
        incr j
    }
    set explanation "[dict get $card description]\n[dict get $card initialization]\n[dict get $card uncertainty]\n[dict get $card extrapolation]"
    ttk::label $body.note -text $explanation -wraplength 850 -justify left
    grid $body.note -row [expr {$j+3}] -column 0 -columnspan 6 -sticky nw -pady 8
    foreach column {1 2 3 5} {grid columnconfigure $body $column -weight 1}
    bind $page.viewport.canvas <Configure> +[list ::GX::DatasetCurveFit::_componentCardLayout $page %w]
}
proc ::GX::DatasetCurveFit::_componentDialogLayout {d window width} {
    if {$window eq $d&&[winfo exists $d.help]} {$d.help configure -wraplength [expr {max(240,$width-30)}]}
}
proc ::GX::DatasetCurveFit::_componentCardLayout {page width} {
    set body $page.viewport.canvas.body
    foreach label [list $body.title $body.equation $body.note] {
        if {[winfo exists $label]} {$label configure -wraplength [expr {max(200,$width-50)}]}
    }
}
proc ::GX::DatasetCurveFit::_componentRemove {d} {
    variable state
    set page [$d.tabs select];if {$page eq {}} return
    set index [lsearch -exact $state($d,rows) $page];set state($d,rows) [lreplace $state($d,rows) $index $index]
    $d.tabs forget $page;destroy $page
}
proc ::GX::DatasetCurveFit::_componentApply {w d} {
    variable state
    if {$state($d,owner) ne $state($w,activeSource)||$state($d,orientation) ne $state($w,orientation)} {error {Source or orientation changed; reopen component settings}}
    set recipe [_componentUnits $w $state($w,orientation)];set components {};set overrides {}
    foreach page $state($d,rows) {
        set card [dict get $state($d,cards) $state($page,model)];set initials {};set bindings {}
        foreach parameter [dict get $card parameter_ids] {
            set initial [_finite $state($page,$parameter,initial) "Initial $parameter"];lappend initials $initial
            set identity $state($page,id)_$parameter
            if {[string trim $state($page,$parameter,shared)] ne {}} {set identity [string trim $state($page,$parameter,shared)]}
            dict set bindings $parameter $identity
            set values [dict create initial $initial fixed $state($page,$parameter,fixed)]
            foreach field {lower upper} {
                set value [string trim $state($page,$parameter,$field)]
                if {$value eq {}} continue
                if {!($field eq "lower"&&$value eq "-Inf"||$field eq "upper"&&$value in {Inf +Inf})} {_finite $value "$field $parameter"}
                dict set values $field $value
            }
            if {[dict exists $overrides $identity]&&[dict get $overrides $identity] ne $values} {error "Shared parameter $identity has conflicting values or constraints"}
            dict set overrides $identity $values
        }
        lappend components [dict create id $state($page,id) model_id $state($page,model) initial_parameters $initials bindings $bindings]
    }
    dict set recipe components $components;dict set recipe parameters $overrides
    set resolved [_resolveComponents $recipe]
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    set state($w,componentRecipe) [dict get $resolved composition recipe]
    set state($w,model) components
    _invalidateSettings $w;_uiModelFields $w;_workspaceCapture $w;_saveState $w
    set state($w,status) {Component settings saved. Preview to fit all components together.}
    destroy $d
}
