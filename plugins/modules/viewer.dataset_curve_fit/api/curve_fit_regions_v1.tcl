# Regional controls and typed input bindings; Numeric owns joint construction.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::regionCatalog {} {
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    return [dict get [::GX::NumericAPIv1::callOperation fit_region_catalog {}] models]
}
proc ::GX::DatasetCurveFit::_validateRegionalMetadata {result} {
    if {[dict get $result model] ne "regions"} {
        foreach field {region_selection region_membership_resource} {if {[dict exists $result $field]} {error {Regional data lack a regional model identity}}}
        return
    }
    set selection [dict get $result region_selection]
    if {[dict get $selection schema] ne "gxtxt.fit_region_selection.v1"||[dict get $selection index_base]!=1||[dict get $selection boundary_ownership] ne "right_region"||[dict get $selection row_identity] ne "original_source_uint64"||[dict get $selection selection_stage] ne "before_measurement_missingness_or_zero_weight"} {error {Regional selection meaning changed}}
    foreach field {input_count retained_count excluded_count} {set value [_finite [dict get $selection $field] {Regional observation count}];if {$value<0||$value!=floor($value)} {error {Invalid regional observation count}}}
    set n [dict get $result statistical_results training quantities n value]
    set retained [dict get $selection retained_count]
    if {$retained+[dict get $selection excluded_count]!=[dict get $selection input_count]||$n>$retained} {error {Regional row selection counts changed}}
    if {[dict exists $result measurement_selection]} {
        if {$retained!=[dict get $result measurement_selection input_count]} {error {Regional and measurement selection stages lost alignment}}
    } elseif {$retained!=$n} {error {Regional fit changed the retained observation rows}}
    set recipe [dict get $result numeric_model_state regional_composition recipe]
    if {[dict get $selection fit_windows] ne [dict get $recipe fit_windows]||![dict exists $result statistical_results training context regional_fit]} {error {Regional windows or joint inference facts changed}}
    set resource [::GX::interactiveDocumentResourceInfo [dict get $result region_membership_resource]]
    if {[dict get $resource size_bytes]!=8*$n||[dict get $resource metadata row_count]!=$n||[dict get $resource metadata format] ne "float64_interleaved_le"||[dict get $resource metadata columns] ne "region_index"||[dict get $resource metadata boundary_ownership] ne "right_region"||[dict get $resource metadata index_base]!=1} {error {Regional membership resource lost its shape or identity}}
}
proc ::GX::DatasetCurveFit::_regionRecipeNode {recipe} {
    set fields {}
    foreach key [dict keys $recipe] {if {$key ni {regions breakpoints origin fit_windows parameters x_unit y_unit}} {error "Unknown regional recipe field: $key"}}
    foreach key {x_unit y_unit} {dict set fields $key [::GX::ScientificTransportv1::text [dict get $recipe $key]]}
    dict set fields origin [::GX::ScientificTransportv1::array {1 1} [list [dict get $recipe origin]]]
    foreach collection {regions breakpoints} {
        set items {}
        foreach element [dict get $recipe $collection] {
            set item {}
            dict for {key value} $element {
                if {$collection eq "regions"&&$key ni {id model_id}||$collection eq "breakpoints"&&$key ni {id initial lower upper fixed continuity}} {error "Unknown $collection field: $key"}
                if {$key in {id model_id continuity}} {set node [::GX::ScientificTransportv1::text $value]} else {set node [::GX::ScientificTransportv1::array {1 1} [list $value]]}
                dict set item $key $node
            }
            lappend items [::GX::ScientificTransportv1::struct $item]
        }
        dict set fields $collection [dict create kind cell items $items]
    }
    set windows [::GX::datasetPublicationV2DictDefault $recipe fit_windows {}]
    if {$windows ne {}} {
        set lower {};set upper {}
        foreach pair $windows {if {[llength $pair]!=2} {error {Each observation window needs lower and upper coordinates}};lappend lower [lindex $pair 0];lappend upper [lindex $pair 1]}
        dict set fields fit_windows [::GX::ScientificTransportv1::array [list [llength $windows] 2] [concat $lower $upper]]
    }
    set overrides {}
    dict for {id values} [::GX::datasetPublicationV2DictDefault $recipe parameters {}] {
        set item {}
        dict for {key value} $values {
            if {$key ni {initial lower upper fixed}} {error "Unknown regional parameter constraint: $key"}
            dict set item $key [::GX::ScientificTransportv1::array {1 1} [list $value]]
        }
        dict set overrides $id [::GX::ScientificTransportv1::struct $item]
    }
    dict set fields parameters [::GX::ScientificTransportv1::struct $overrides]
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::DatasetCurveFit::_resolveRegions {recipe} {
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set resolved [::GX::NumericAPIv1::callOperation fit_region_compose [list [_regionRecipeNode $recipe]]]
    # Bounded result vectors have no row orientation. This field's public
    # contract is an N-by-2 window matrix, including N=1; restore its one-row
    # container before passing the normalized recipe back to Numeric.
    set windows [dict get $resolved regional_composition recipe fit_windows]
    if {[llength $windows]==2&&[llength [lindex $windows 0]]==1&&[llength [lindex $windows 1]]==1} {
        dict set resolved regional_composition recipe fit_windows [list $windows]
    }
    return $resolved
}
proc ::GX::DatasetCurveFit::_prepareRegions {w options} {
    if {![dict exists $options region_recipe]||[dict get $options region_recipe] eq {}} {error {Configure joint regions first}}
    set recipe [dict get $options region_recipe]
    dict for {key value} [_componentUnits $w [::GX::datasetPublicationV2DictDefault $options orientation y_of_x]] {
        if {[dict exists $recipe $key]&&[dict get $recipe $key] ne $value} {error {Regional units differ from the current axes; review region settings}}
        dict set recipe $key $value
    }
    return [_resolveRegions $recipe]
}
proc ::GX::DatasetCurveFit::_regionSettings {w} {
    variable state
    _assertLoaded $w
    set units [_componentUnits $w $state($w,orientation)];set d $w.regions
    if {[winfo exists $d]} {raise $d;return}
    set state($d,owner) $state($w,activeSource);set state($d,orientation) $state($w,orientation)
    set state($d,cards) {};set labels {}
    foreach card [regionCatalog] {dict set state($d,cards) [dict get $card id] $card;lappend labels [dict get $card name]}
    set state($d,choice) [lindex $labels 0];set state($d,serial) 0;set state($d,rows) {}
    set recipe $state($w,regionRecipe);set overrides [::GX::datasetPublicationV2DictDefault $recipe parameters {}]
    set state($d,origin) [::GX::datasetPublicationV2DictDefault $recipe origin 0]
    set state($d,windows) [join [::GX::datasetPublicationV2DictDefault $recipe fit_windows {}] {; }]
    set level [::GX::datasetPublicationV2DictDefault $overrides level {}]
    foreach {field fallback} {initial 0 lower {} upper {} fixed 0} {set state($d,level,$field) [::GX::datasetPublicationV2DictDefault $level $field $fallback]}
    toplevel $d;wm title $d {Joint regional model};wm transient $d $w;wm geometry $d 940x660;wm minsize $d 700 440
    ttk::frame $d.actions -padding 8;pack $d.actions -side bottom -fill x
    ttk::button $d.actions.apply -text {Apply joint regions} -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_regionApply $w $d]]
    ttk::button $d.actions.cancel -text Cancel -command [list destroy $d]
    pack $d.actions.cancel $d.actions.apply -side right -padx 4
    set body [::GX::scrollableDialogBody $d];set state($d,body) $body
    $d.viewport.canvas configure -width 100 -height 100
    ttk::label $body.help -text "One joint fit, with C0 or C1 continuity. Physical X: [dict get $units x_unit]; Y: [dict get $units y_unit]. Breakpoint search bounds and observation windows are separate. Review dimensional initial values. Applying regions sets both coordinate translations to off." -wraplength 840 -justify left
    grid $body.help -row 0 -column 0 -columnspan 5 -sticky ew -pady 6
    ttk::label $body.originLabel -text {First-region physical origin}
    ttk::entry $body.origin -textvariable ::GX::DatasetCurveFit::state($d,origin) -width 14
    grid $body.originLabel -row 1 -column 0 -sticky w;grid $body.origin -row 1 -column 1 -sticky ew
    set column 0
    foreach label {{Level at origin} Initial Lower Upper Fixed} {ttk::label $body.lh$column -text $label;grid $body.lh$column -row 2 -column $column -sticky w;incr column}
    ttk::label $body.levelLabel -text "level ([dict get $units y_unit])";grid $body.levelLabel -row 3 -column 0 -sticky w
    set column 1
    foreach field {initial lower upper fixed} {
        if {$field eq "fixed"} {ttk::checkbutton $body.level_$field -variable ::GX::DatasetCurveFit::state($d,level,$field)} else {ttk::entry $body.level_$field -width 12 -textvariable ::GX::DatasetCurveFit::state($d,level,$field)}
        grid $body.level_$field -row 3 -column $column -sticky ew -padx 4;incr column
    }
    ttk::label $body.windowLabel -text {Observation windows: lower upper; lower upper. Blank uses all selected source rows.}
    ttk::entry $body.windows -textvariable ::GX::DatasetCurveFit::state($d,windows)
    grid $body.windowLabel -row 4 -column 0 -columnspan 5 -sticky w -pady 5
    grid $body.windows -row 5 -column 0 -columnspan 5 -sticky ew
    ttk::frame $body.choose;grid $body.choose -row 6 -column 0 -columnspan 5 -sticky ew -pady 8
    ttk::combobox $body.choose.model -values $labels -state readonly -textvariable ::GX::DatasetCurveFit::state($d,choice) -width 35
    ttk::button $body.choose.add -text {Append region} -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_regionAddChoice $w $d]]
    ttk::button $body.choose.remove -text {Remove last region} -command [list ::GX::DatasetCurveFit::_regionRemove $d]
    pack $body.choose.model $body.choose.add $body.choose.remove -side left -padx 3
    ttk::notebook $body.tabs;grid $body.tabs -row 7 -column 0 -columnspan 5 -sticky nsew
    set state($d,tabs) $body.tabs
    foreach c {1 2 3} {grid columnconfigure $body $c -weight 1}
    bind $d.viewport.canvas <Configure> +[list ::GX::DatasetCurveFit::_regionLayout $d %w]
    if {$recipe ne {}} {
        set index 0
        foreach region [dict get $recipe regions] {
            set breakpoint {};if {$index>0} {set breakpoint [lindex [dict get $recipe breakpoints] [expr {$index-1}]]}
            _regionAdd $d $region $breakpoint $overrides;incr index
        }
    }
}
proc ::GX::DatasetCurveFit::_regionAddChoice {w d} {
    variable state
    dict for {id card} $state($d,cards) {if {[dict get $card name] eq $state($d,choice)} {
        set serial [expr {$state($d,serial)+1}]
        set breakpoint {}
        if {[llength $state($d,rows)]} {set breakpoint [dict create id junction$serial initial {} lower {} upper {} fixed 0 continuity C0]}
        _regionAdd $d [dict create id r$serial model_id $id] $breakpoint {};return
    }}
}
proc ::GX::DatasetCurveFit::_regionAdd {d region breakpoint overrides} {
    variable state
    if {[llength $state($d,rows)]>=8} {error {At most eight regions are supported}}
    set id [dict get $region model_id]
    if {![dict exists $state($d,cards) $id]} {error "Regional descriptor is unavailable: $id. Accepted fits retain their frozen declaration."}
    set card [dict get $state($d,cards) $id];set tabs $state($d,tabs);set page $tabs.p[incr state($d,serial)]
    ttk::frame $page -padding 8;$tabs add $page -text [dict get $region id];$tabs select $page
    lappend state($d,rows) $page;set state($page,id) [dict get $region id];set state($page,model) $id;set state($page,breakpoint) $breakpoint
    ttk::label $page.title -text "[dict get $card name]\nIncrement: [dict get $card increment]";grid $page.title -row 0 -column 0 -columnspan 5 -sticky w
    set row 1
    if {$breakpoint ne {}} {
        ttk::label $page.join -text "Incoming breakpoint: [dict get $breakpoint id] (physical X)";grid $page.join -row $row -column 0 -columnspan 5 -sticky w -pady 6;incr row
        set column 0
        foreach field {initial lower upper fixed continuity} {
            set state($page,break,$field) [dict get $breakpoint $field]
            ttk::label $page.bl_$field -text $field;grid $page.bl_$field -row $row -column $column -sticky w
            if {$field eq "fixed"} {ttk::checkbutton $page.b_$field -variable ::GX::DatasetCurveFit::state($page,break,$field)} elseif {$field eq "continuity"} {
                ttk::combobox $page.b_$field -state readonly -values {C0 C1} -width 8 -textvariable ::GX::DatasetCurveFit::state($page,break,$field)
                bind $page.b_$field <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_regionSlopeState $page]
            } else {ttk::entry $page.b_$field -width 12 -textvariable ::GX::DatasetCurveFit::state($page,break,$field)}
            grid $page.b_$field -row [expr {$row+1}] -column $column -sticky ew -padx 3;incr column
        }
        incr row 2
    }
    set column 0
    foreach label {{Parameter / unit} Initial Lower Upper Fixed} {ttk::label $page.h$column -text $label;grid $page.h$column -row $row -column $column -sticky w -pady 5;incr column};incr row
    foreach parameter [dict get $card parameter_ids] unit [dict get $card parameter_units] initial [dict get $card initial_parameters] {
        set values [::GX::datasetPublicationV2DictDefault $overrides $state($page,id)_$parameter {}]
        foreach {field fallback} [list initial $initial lower {} upper {} fixed 0] {set state($page,$parameter,$field) [::GX::datasetPublicationV2DictDefault $values $field $fallback]}
        ttk::label $page.p_$parameter -text "$parameter ($unit)";grid $page.p_$parameter -row $row -column 0 -sticky w
        set column 1
        foreach field {initial lower upper fixed} {
            if {$field eq "fixed"} {ttk::checkbutton $page.${parameter}_$field -variable ::GX::DatasetCurveFit::state($page,$parameter,$field)} else {ttk::entry $page.${parameter}_$field -width 12 -textvariable ::GX::DatasetCurveFit::state($page,$parameter,$field)}
            grid $page.${parameter}_$field -row $row -column $column -sticky ew -padx 3;incr column
        }
        incr row
    }
    ttk::label $page.note -text "[dict get $card initialization]\n[dict get $card uncertainty]\n[dict get $card extrapolation]" -wraplength 800 -justify left
    grid $page.note -row $row -column 0 -columnspan 5 -sticky ew -pady 8
    foreach column {1 2 3} {grid columnconfigure $page $column -weight 1}
    _regionSlopeState $page
}
proc ::GX::DatasetCurveFit::_regionSlopeState {page} {
    variable state
    set derived [expr {$state($page,breakpoint) ne {}&&$state($page,break,continuity) eq "C1"}]
    foreach field {initial lower upper fixed} {$page.slope_$field configure -state [expr {$derived?"disabled":"normal"}]}
    $page.p_slope configure -text [expr {$derived?"slope (derived C1)":"slope (Y/X)"}]
}
proc ::GX::DatasetCurveFit::_regionLayout {d width} {
    variable state
    if {![info exists state($d,body)]} return
    set body $state($d,body)
    foreach label [concat [list $body.help $body.windowLabel] [lmap page $state($d,rows) {set v $page.note}]] {if {[winfo exists $label]} {$label configure -wraplength [expr {max(240,$width-50)}]}}
}
proc ::GX::DatasetCurveFit::_regionRemove {d} {
    variable state
    if {![llength $state($d,rows)]} return
    set page [lindex $state($d,rows) end];set state($d,rows) [lrange $state($d,rows) 0 end-1]
    $state($d,tabs) forget $page;destroy $page
}
proc ::GX::DatasetCurveFit::_regionParameterValues {owner parameter} {
    variable state
    set values [dict create initial [_finite $state($owner,$parameter,initial) "Initial $parameter"] fixed $state($owner,$parameter,fixed)]
    foreach field {lower upper} {
        set value [string trim $state($owner,$parameter,$field)];if {$value eq {}} continue
        if {!($field eq "lower"&&$value eq "-Inf"||$field eq "upper"&&$value in {Inf +Inf})} {_finite $value "$field $parameter"}
        dict set values $field $value
    }
    return $values
}
proc ::GX::DatasetCurveFit::_regionApply {w d} {
    variable state
    if {$state($d,owner) ne $state($w,activeSource)||$state($d,orientation) ne $state($w,orientation)} {error {Source or orientation changed; reopen regional settings}}
    set recipe [_componentUnits $w $state($w,orientation)]
    dict set recipe origin [_finite $state($d,origin) {Physical origin}]
    dict set recipe parameters level [_regionParameterValues $d level]
    set regions {};set breaks {};set windows {}
    foreach pair [split $state($d,windows) {;}] {
        if {[string trim $pair] eq {}} continue
        set values [regexp -all -inline {\S+} [string map {, { }} $pair]]
        if {[llength $values]!=2} {error {Each observation window needs lower upper, separated from the next window by a semicolon}}
        lappend windows [list [_finite [lindex $values 0] {Window lower}] [_finite [lindex $values 1] {Window upper}]]
    }
    dict set recipe fit_windows $windows
    foreach page $state($d,rows) {
        lappend regions [dict create id $state($page,id) model_id $state($page,model)]
        set breakpoint $state($page,breakpoint)
        if {$breakpoint ne {}} {
            foreach field {initial lower upper} {dict set breakpoint $field [_finite $state($page,break,$field) "Breakpoint $field"]}
            foreach field {fixed continuity} {dict set breakpoint $field $state($page,break,$field)}
            lappend breaks $breakpoint
        }
        foreach parameter [dict get $state($d,cards) $state($page,model) parameter_ids] {
            if {$parameter eq "slope"&&$breakpoint ne {}&&[dict get $breakpoint continuity] eq "C1"} continue
            dict set recipe parameters $state($page,id)_$parameter [_regionParameterValues $page $parameter]
        }
    }
    dict set recipe regions $regions;dict set recipe breakpoints $breaks
    set resolved [_resolveRegions $recipe]
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    set state($w,regionRecipe) [dict get $resolved regional_composition recipe];set state($w,model) regions
    set state($w,translationUMode) off;set state($w,translationUDelta) 0;set state($w,translationVMode) off;set state($w,translationVDelta) 0
    _invalidateSettings $w;_uiModelFields $w;_workspaceCapture $w;_saveState $w
    set state($w,status) {Joint regions saved in physical coordinates; translations are off. Preview to fit all regions and breakpoints together.}
    destroy $d
}
