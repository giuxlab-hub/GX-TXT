# Complex settings use the existing formula parameter grid and native controls.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_complexSettings {w} {_formulaSettings $w complex_response}
proc ::GX::DatasetCurveFit::_complexCovarianceChoices {} {
    set choices [dict create {Shared matrix entered below} {}]
    foreach dataset [::GX::sessionInspectionDatasetIds] {
        foreach variable [::GX::datasetVariableSchemaV3 $dataset] {
            if {[dict get $variable enabled]&&[dict get $variable rank]==3&&[dict get $variable dtype] in {float32 float64}} {
                set id [dict get $variable variable_id]
                dict set choices "$dataset / $id ([dict get $variable unit])" [dict create dataset_id $dataset variable_id $id]
            }
        }
    }
    return $choices
}
proc ::GX::DatasetCurveFit::_complexEditorControls {w d body} {
    variable state
    set recipe $state($w,complexRecipe);set data $state($w,complexData)
    set variables [dict get [variables $state($w,dataset)] numeric]
    $body.help configure -text {Fit one to three complex responses jointly with shared physical parameters. X is positive physical frequency. Bind real/imaginary or amplitude/phase Variables in exact source-row order. Covariance is absolute Cartesian component covariance, not phase/amplitude variance. The source Y trace must match the chosen display projection. Physical translations are off; wrapped phase is a separate diagnostic. All parameter units must be explicit.}
    pack forget $body.expression
    set state($d,predictorId) [::GX::datasetPublicationV2DictDefault $recipe predictor_id f]
    ttk::frame $body.complex;pack $body.complex -fill x -padx 8 -pady 6
    ttk::label $body.complex.frequencyLabel -text {Frequency symbol}
    ttk::entry $body.complex.frequency -textvariable ::GX::DatasetCurveFit::state($d,predictorId) -width 12
    grid $body.complex.frequencyLabel -row 0 -column 0 -sticky w;grid $body.complex.frequency -row 0 -column 1 -sticky ew
    set declared [::GX::datasetPublicationV2DictDefault $recipe channels {}];set bound [::GX::datasetPublicationV2DictDefault $data channels {}]
    for {set index 1} {$index<=3} {incr index} {
        set channel [lindex $declared [expr {$index-1}]];set binding [lindex $bound [expr {$index-1}]]
        set unit [dict get $state($d,units) y_unit];if {$unit eq "dB"} {set unit 1}
        set defaults [dict create id channel$index unit $unit real_expression a imaginary_expression {b*f}]
        set channel [dict merge $defaults $channel]
        set binding [dict merge [dict create representation cartesian first_variable_id $state($w,y) second_variable_id {} phase_unit deg reference 1] $binding]
        set state($d,c$index,enabled) [expr {$index<=[llength $declared]||($declared eq {}&&$index==1)}]
        foreach field {id unit real_expression imaginary_expression} {set state($d,c$index,$field) [dict get $channel $field]}
        foreach field {representation first_variable_id second_variable_id phase_unit reference} {set state($d,c$index,$field) [dict get $binding $field]}
        set frame $body.complex.c$index;ttk::labelframe $frame -text "Physical channel $index" -padding 5;grid $frame -row $index -columnspan 4 -sticky ew -pady 4
        ttk::checkbutton $frame.enabled -text Include -variable ::GX::DatasetCurveFit::state($d,c$index,enabled);grid $frame.enabled -row 0 -column 0 -sticky w
        set column 0
        foreach {field label} {id {Channel ID} unit {Physical unit} real_expression {Real expression} imaginary_expression {Imaginary expression}} {
            ttk::label $frame.l_$field -text $label;ttk::entry $frame.$field -width 18 -textvariable ::GX::DatasetCurveFit::state($d,c$index,$field)
            grid $frame.l_$field -row 1 -column $column -sticky w;grid $frame.$field -row 2 -column $column -sticky ew -padx 3;grid columnconfigure $frame $column -weight 1;incr column
        }
        set column 0
        foreach {field label choices} [list representation Input {cartesian polar_linear polar_db20} first_variable_id {Real or amplitude Variable} $variables second_variable_id {Imaginary or phase Variable} $variables phase_unit {Phase unit (polar only)} {deg rad}] {
            ttk::label $frame.l_$field -text $label;ttk::combobox $frame.$field -state readonly -width 18 -values $choices -textvariable ::GX::DatasetCurveFit::state($d,c$index,$field)
            grid $frame.l_$field -row 3 -column $column -sticky w;grid $frame.$field -row 4 -column $column -sticky ew -padx 3;incr column
        }
        ttk::label $frame.refLabel -text {db20 input reference in the physical channel unit}
        ttk::entry $frame.reference -textvariable ::GX::DatasetCurveFit::state($d,c$index,reference)
        grid $frame.refLabel -row 5 -column 0 -columnspan 2 -sticky w;grid $frame.reference -row 5 -column 2 -columnspan 2 -sticky ew -padx 3
    }
    set display [dict merge {channel_id channel1 projection real} [::GX::datasetPublicationV2DictDefault $data display {}]]
    foreach field {channel_id projection} {set state($d,display_$field) [dict get $display $field]}
    set state($d,display_reference) [::GX::datasetPublicationV2DictDefault [::GX::datasetPublicationV2DictDefault $display reference {}] value 1]
    set row 4
    foreach {field label choices} {display_channel_id {Displayed channel ID} {} display_projection {Source Y projection} {real imaginary magnitude db20} display_reference {db20 display reference in channel units} {}} {
        ttk::label $body.complex.l_$field -text $label
        if {$choices eq {}} {ttk::entry $body.complex.$field -textvariable ::GX::DatasetCurveFit::state($d,$field)} else {ttk::combobox $body.complex.$field -state readonly -values $choices -textvariable ::GX::DatasetCurveFit::state($d,$field)}
        grid $body.complex.l_$field -row $row -column 0 -columnspan 2 -sticky w;grid $body.complex.$field -row $row -column 2 -columnspan 2 -sticky ew -pady 3;incr row
    }
    set state($d,covarianceChoices) [_complexCovarianceChoices];set state($d,covarianceChoice) {Shared matrix entered below}
    set covariance [::GX::datasetPublicationV2DictDefault $data covariance {}];set state($d,covarianceValues) {}
    if {$covariance ne {}} {
        if {[dict get $covariance layout] eq "shared"} {set state($d,covarianceValues) [join [dict get $covariance values] {; }]} else {
            dict for {label spec} $state($d,covarianceChoices) {if {$spec ne {}&&[dict get $spec dataset_id] eq [dict get $covariance dataset_id]&&[dict get $spec variable_id] eq [dict get $covariance variable_id]} {set state($d,covarianceChoice) $label}}
        }
    }
    set state($d,covarianceConfirmed) [expr {$covariance ne {}}];set state($d,gaussian) [expr {$state($w,noiseModel) eq "independent_gaussian_known_sigma"}]
    ttk::label $body.complex.covarianceLabel -text {Absolute Cartesian covariance}
    ttk::combobox $body.complex.covarianceChoice -state readonly -values [dict keys $state($d,covarianceChoices)] -textvariable ::GX::DatasetCurveFit::state($d,covarianceChoice)
    grid $body.complex.covarianceLabel -row $row -column 0 -columnspan 2 -sticky w;grid $body.complex.covarianceChoice -row $row -column 2 -columnspan 2 -sticky ew;incr row
    ttk::label $body.complex.valuesLabel -text {Shared matrix: spaces between entries; semicolons between rows}
    ttk::entry $body.complex.covarianceValues -textvariable ::GX::DatasetCurveFit::state($d,covarianceValues)
    grid $body.complex.valuesLabel -row $row -columnspan 4 -sticky w;incr row;grid $body.complex.covarianceValues -row $row -columnspan 4 -sticky ew;incr row
    ttk::checkbutton $body.complex.confirm -text {Covariance uses real/imaginary channel order and component-product units; its third axis, if present, matches every original source row} -variable ::GX::DatasetCurveFit::state($d,covarianceConfirmed)
    grid $body.complex.confirm -row $row -columnspan 4 -sticky w;incr row
    ttk::checkbutton $body.complex.gaussian -text {Declare Gaussian innovations under this covariance for conditional parameter intervals} -variable ::GX::DatasetCurveFit::state($d,gaussian)
    grid $body.complex.gaussian -row $row -columnspan 4 -sticky w
    wm geometry $d 1080x800
}
proc ::GX::DatasetCurveFit::_complexEditorRecipe {w d} {
    variable state
    set parameters [dict get [_formulaRead $w $d] parameters];set channels {}
    for {set index 1} {$index<=3} {incr index} {
        if {!$state($d,c$index,enabled)} continue
        set channel {};foreach field {id unit real_expression imaginary_expression} {dict set channel $field [string trim $state($d,c$index,$field)]};lappend channels $channel
    }
    return [dict create predictor_id [string trim $state($d,predictorId)] predictor_unit [dict get $state($d,units) x_unit] channels $channels parameters $parameters]
}
proc ::GX::DatasetCurveFit::_complexEditorData {w d} {
    variable state
    if {!$state($d,covarianceConfirmed)} {error {Confirm the Cartesian covariance component units and original-row correspondence}}
    set channels {};set units {};set physicalUnits {}
    for {set index 1} {$index<=3} {incr index} {
        if {!$state($d,c$index,enabled)} continue
        set id [string trim $state($d,c$index,id)];set unit [string trim $state($d,c$index,unit)];dict set physicalUnits $id $unit;lappend units $unit $unit
        set item [dict create channel_id $id];foreach field {representation first_variable_id second_variable_id} {dict set item $field $state($d,c$index,$field)}
        if {[dict get $item representation] ne "cartesian"} {dict set item phase_unit $state($d,c$index,phase_unit)}
        if {[dict get $item representation] eq "polar_db20"} {dict set item reference [_finite $state($d,c$index,reference) {Physical amplitude reference}]}
        lappend channels $item
    }
    set covariance [dict get $state($d,covarianceChoices) $state($d,covarianceChoice)]
    if {$covariance eq {}} {
        set rows {};foreach row [split [string map {\n {;}} $state($d,covarianceValues)] {;}] {if {[string trim $row] ne {}} {lappend rows [string trim $row]}}
        set covariance [dict create layout shared values $rows]
    } else {dict set covariance layout per_observation;dict set covariance source_dataset_id $state($w,dataset);dict set covariance row_binding original_source_rows}
    dict set covariance component_units $units
    set display [dict create channel_id [string trim $state($d,display_channel_id)] projection $state($d,display_projection)]
    if {[dict get $display projection] eq "db20"} {dict set display reference [dict create value [_finite $state($d,display_reference) {Display amplitude reference}] unit [dict get $physicalUnits [dict get $display channel_id]]]}
    return [dict create channels $channels covariance $covariance display $display]
}
proc ::GX::DatasetCurveFit::_complexEditorValidate {w d} {
    variable state
    set options [_uiFitOptions $w]
    dict set options complex_recipe [_complexEditorRecipe $w $d];dict set options complex_data [_complexEditorData $w $d]
    dict set options orientation y_of_x;dict set options noise_model [expr {$state($d,gaussian)?"independent_gaussian_known_sigma":"unspecified"}]
    foreach axis {u v} {dict set options translation_$axis {mode off delta 0}}
    return [_prepareComplex $w $options]
}
