# Named, inert fit templates use the existing Session Workspace owner/store.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_templateVariables {recipe} {
    set source [dict get $recipe source];set options [dict get $recipe fit options]
    set ids [list [dict get $source source_x_variable_id] [dict get $source source_y_variable_id]]
    foreach filter [dict get $source source_filters] {lappend ids [dict get $filter variable]}
    set measurement [_measurementOptions $options]
    foreach field {variable_id independent_variable_id} {if {[dict get $measurement $field] ne {}} {lappend ids [dict get $measurement $field]}}
    if {[dict exists $options parameter_variable_id]&&[dict get $options parameter_variable_id] ne {}} {lappend ids [dict get $options parameter_variable_id]}
    if {[dict get $recipe fit model] eq "complex_response"} {
        foreach channel [dict get $options complex_data channels] {foreach field {first_variable_id second_variable_id} {lappend ids [dict get $channel $field]}}
    }
    return [lsort -unique $ids]
}
proc ::GX::DatasetCurveFit::templateCreate {reference name} {
    set record [_recipeResultRecord $reference];set recipe [_recipeFromRecord $record]
    if {[_covarianceOptions [dict get $recipe fit options]] ne {}} {error {A covariance matrix belongs to its exact observation rows; export the exact fit recipe or declare a new covariance binding for the target source}}
    # Reusability depends on captured source-row identity, not fit interpretation.
    if {[dict exists $recipe source complex_binding]&&[dict get $recipe source complex_binding covariance layout] eq "per_observation"} {error {Per-observation complex covariance belongs to exact original rows; export the exact recipe or declare a new covariance binding for the target source}}
    set encoded [::GX::scientificRecipeEncode $recipe];recipeValidate $encoded
    set source [dict get $recipe source]
    if {[dict get $source source_kind] ne "dataset"} {error {Publish the built-in sample as a Dataset before creating a reusable Dataset template}}
    if {[dict exists $source source_transform_manifest]&&[dict get $source source_transform_manifest] ne {}} {error {Materialize the transformed source as a canonical Dataset before creating a reusable template}}
    set requirements {}
    foreach id [_templateVariables $recipe] {
        set descriptor [::GX::datasetVariableV3ById [dict get $source source_dataset_id] $id]
        set requirement {};foreach field {unit value_kind rank dtype} {dict set requirement $field [dict get $descriptor $field]}
        dict set requirements $id $requirement
    }
    set payload [dict create format gxtxt.fit_template.v1 recipe $encoded requirements $requirements origin_result $reference]
    set workspace [::GX::sessionWorkspaceCreate dataset_curve_fit_recipe $name $payload]
    return [templateInspect [dict get $workspace workspace_id]]
}
proc ::GX::DatasetCurveFit::_templatePayload {id} {
    set workspace [::GX::sessionWorkspaceGet $id]
    if {[dict get $workspace provider_id] ne "dataset_curve_fit_recipe"||[dict get $workspace schema] ne "gxtxt.fit_template.v1"} {error {Workspace is not a Fitter recipe template}}
    set payload [dict get $workspace payload];templateWorkspaceValidate $payload
    return $payload
}
proc ::GX::DatasetCurveFit::templateInspect {id} {
    set payload [_templatePayload $id];set workspace [::GX::sessionWorkspaceGet $id]
    set recipe [::GX::scientificRecipeDataDecode [dict get $payload recipe] gxtxt.fit_recipe.v1]
    set mask [dict get $recipe fit selection_descriptor]
    return [dict create template_id $id name [dict get $workspace name] format gxtxt.fit_template.v1 model [dict get $recipe fit model] original_dataset_id [dict get $recipe source source_dataset_id] producers [dict get $recipe producers] requirements [dict get $payload requirements] scope [dict get $recipe fit scope] region_count [llength [dict get $mask regions]] manual_row_count [dict size [dict get $mask manual_rows]]]
}
proc ::GX::DatasetCurveFit::templateList {} {
    set result {}
    foreach workspace [::GX::sessionWorkspaceList] {
        if {[dict get $workspace provider_id] eq "dataset_curve_fit_recipe"} {lappend result [templateInspect [dict get $workspace workspace_id]]}
    }
    return $result
}
proc ::GX::DatasetCurveFit::templateBind {id dataset mapping selectionPolicy} {
    set payload [_templatePayload $id];set recipe [_recipeDecode [dict get $payload recipe]]
    set requirements [dict get $payload requirements]
    if {[lsort [dict keys $mapping]] ne [lsort [dict keys $requirements]]} {error {Explicit mapping must contain every required source Variable exactly once}}
    if {[llength [lsort -unique [dict values $mapping]]]!=[dict size $mapping]} {error {Distinct scientific Variables cannot be silently merged into one template binding}}
    if {$selectionPolicy ni {all_rows coordinate_regions}} {error {Choose all_rows or coordinate_regions; original row-specific picks cannot identify observations in a new Dataset}}
    set checked {}
    dict for {original expected} $requirements {
        set target [dict get $mapping $original];set actual [::GX::datasetVariableV3ById $dataset $target]
        if {![dict get $actual enabled]||[dict get $actual rank]!=1||[dict get $actual value_kind] ne [dict get $expected value_kind]} {error "Target Variable '$target' has an incompatible enabled/type/rank contract for '$original'"}
        if {[dict get $actual unit] ne [dict get $expected unit]} {error "Target Variable '$target' unit '[dict get $actual unit]' differs from template unit '[dict get $expected unit]'. Apply an explicit Unit Registry/Dataset Transform conversion first."}
        dict set checked $original $actual
    }
    set prior [dict get $recipe source];set source $prior
    dict set source source_dataset_id $dataset
    set identity [::GX::curveSourceDatasetIdentity $::GX::currentSession $dataset]
    dict set source source_sha256 [dict get $identity sha256]
    dict set source source_scientific_fingerprints [list $identity]
    foreach axis {x y} {
        set original [dict get $prior source_${axis}_variable_id]
        dict set source source_${axis}_variable_id [dict get $mapping $original]
        dict set source source_axes $axis [dict get $checked $original]
    }
    set filters {}
    foreach filter [dict get $prior source_filters] {dict set filter variable [dict get $mapping [dict get $filter variable]];lappend filters $filter}
    dict set source source_filters $filters
    set source [_logTemplateBind $prior $source]
    set source [_smoothTemplateBind $prior $source]
    if {[dict get $recipe fit model] eq "complex_response"} {
        if {[dict get $recipe fit options complex_data covariance layout] ne "shared"} {error {Per-observation complex covariance requires a new explicit target declaration}}
        dict unset source complex_binding
    }
    dict set recipe source $source
    set options [dict get $recipe fit options]
    if {[dict exists $options measurement]} {
        foreach field {variable_id independent_variable_id} {
            if {[dict exists $options measurement $field]&&[dict get $options measurement $field] ne {}} {dict set options measurement $field [dict get $mapping [dict get $options measurement $field]]}
        }
    }
    if {[dict exists $options parameter_variable_id]&&[dict get $options parameter_variable_id] ne {}} {dict set options parameter_variable_id [dict get $mapping [dict get $options parameter_variable_id]]}
    if {[dict get $recipe fit model] eq "complex_response"} {
        set channels {}
        foreach channel [dict get $options complex_data channels] {
            foreach field {first_variable_id second_variable_id} {dict set channel $field [dict get $mapping [dict get $channel $field]]}
            lappend channels $channel
        }
        dict set options complex_data channels $channels
    }
    dict set recipe fit options $options
    set mask [dict get $recipe fit selection_descriptor];set dropped [dict size [dict get $mask manual_rows]]
    dict set mask manual_rows {}
    if {$selectionPolicy eq "all_rows"} {
        dict set recipe fit scope all
        set mask [dict create api_id CURVE_SOURCE_POINT_MASK_v1 base_selected 0 regions {} manual_rows {}]
    }
    dict set recipe fit selection_descriptor $mask
    set doc [::GX::interactiveDocumentRead $id]
    set binding [dict create schema gxtxt.fit_template_binding.v1 template_id $id template_generation [dict get $doc generation] template_sha256 [dict get $doc sha256] original_dataset_id [dict get $prior source_dataset_id] target_dataset_id $dataset target_sha256 [dict get $identity sha256] variable_mapping $mapping selection_policy $selectionPolicy dropped_original_row_picks $dropped]
    dict set recipe template_binding $binding
    set encoded [::GX::scientificRecipeEncode $recipe]
    recipeValidate $encoded
    return [dict create recipe $encoded review [dict merge $binding [dict create model [dict get $recipe fit model] scope [dict get $recipe fit scope] source_filter_count [llength $filters] coordinate_region_count [llength [dict get $mask regions]] action settings_only explicit_preview_required 1 explicit_accept_required 1]]]
}
proc ::GX::DatasetCurveFit::_templateSaveDialog {w} {
    variable state
    set selected [$w.left.viewport.content.accepted.list curselection]
    if {[llength $selected]!=1} {error {Select one accepted fit to save as a template}}
    set record [lindex $state($w,records) [lindex $selected 0]]
    set reference [resultReference $state($w,documentId) [dict get $record fit_curve_id]]
    set fields [dict create name [dict create type string label {Template name} required 1]]
    ::GX::uiFieldFormCreate $w.saveTemplate {Save reusable fit template} $fields [dict create name "[dict get $record model] recipe"] [list ::GX::DatasetCurveFit::_templateSave $w $reference] $w
}
proc ::GX::DatasetCurveFit::_templateSave {w reference values} {
    variable state
    set saved [templateCreate $reference [dict get $values name]]
    set state($w,status) "Saved template '[dict get $saved name]' in this Session. Apply it with explicit Variable and unit checks."
}
proc ::GX::DatasetCurveFit::_templateDialog {w {requested {}}} {
    variable state;variable serial
    set templates [templateList]
    if {$templates eq {}} {error {Save an accepted fit as a template first}}
    set d .fit_template[incr serial];set labels {};set state($d,templates) {}
    foreach item $templates {
        set label [dict get $item name];lappend labels $label;dict set state($d,templates) $label [dict get $item template_id]
        if {[dict get $item template_id] eq $requested} {set selected $label}
    }
    if {![info exists selected]} {set selected [lindex $labels 0]}
    set state($d,template) $selected;set state($d,dataset) [lindex [datasets] 0];set state($d,selection) {Coordinate regions};set state($d,bound) {}
    toplevel $d;wm title $d {Apply fit template};wm geometry $d 760x620;wm minsize $d 560 400
    bind $d <Destroy> [list ::GX::DatasetCurveFit::_templateDestroyed $d %W]
    if {$w ne {}} {wm transient $d $w}
    ttk::frame $d.actions -padding 8;pack $d.actions -side bottom -fill x
    ttk::button $d.actions.cancel -text Cancel -command [list destroy $d]
    ttk::button $d.actions.review -text {Review bindings} -command [list ::GX::DatasetCurveFit::_templateReviewSafe $d]
    ttk::button $d.actions.apply -text {Apply settings} -state disabled -command [list ::GX::DatasetCurveFit::_templateApplyDialog $w $d]
    pack $d.actions.cancel $d.actions.apply $d.actions.review -side right -padx 4
    ttk::frame $d.top -padding 8;pack $d.top -fill x
    foreach {field label values} [list template Template $labels dataset {Target Dataset} [datasets] selection {Fit-point selection} {{Coordinate regions} {All rows}}] {
        ttk::label $d.top.l_$field -text $label
        ttk::combobox $d.top.$field -values $values -state readonly -textvariable ::GX::DatasetCurveFit::state($d,$field) -width 42
        set row [expr {$field eq "template"?0:$field eq "dataset"?1:2}]
        grid $d.top.l_$field -row $row -column 0 -sticky w -padx 4 -pady 3;grid $d.top.$field -row $row -column 1 -sticky ew -padx 4 -pady 3
    }
    grid columnconfigure $d.top 1 -weight 1
    ttk::label $d.note -text {Map every required Variable explicitly. Units must match the template. Coordinate regions may be reused; individual source-row picks are cleared. Applying settings does not preview or accept a fit.} -wraplength 700
    pack $d.note -fill x -padx 12 -pady 5
    bind $d <Configure> [list ::GX::DatasetCurveFit::_templateLayout $d %W %w]
    text $d.review -height 8 -wrap word -state disabled;pack $d.review -side bottom -fill x -padx 8 -pady 6
    ttk::frame $d.map;pack $d.map -fill both -expand 1 -padx 8
    canvas $d.map.canvas -highlightthickness 0 -yscrollcommand [list $d.map.scroll set]
    ttk::scrollbar $d.map.scroll -command [list $d.map.canvas yview]
    ttk::frame $d.map.canvas.body;set body $d.map.canvas.body
    $d.map.canvas create window 0 0 -window $body -anchor nw -tags fields
    bind $d.map.canvas <Configure> [list $d.map.canvas itemconfigure fields -width %w]
    bind $body <Configure> [list $d.map.canvas configure -scrollregion [list 0 0 %w %h]]
    pack $d.map.scroll -side right -fill y;pack $d.map.canvas -fill both -expand 1
    bind $d.top.template <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_templateFields $d]
    bind $d.top.dataset <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_templateFields $d]
    bind $d.top.selection <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_templateInvalidate $d]
    _templateFields $d
    return $d
}
proc ::GX::DatasetCurveFit::_templateLayout {d widget width} {if {$widget eq $d} {$d.note configure -wraplength [expr {max(300,$width-30)}]}}
proc ::GX::DatasetCurveFit::_templateDestroyed {d widget} {if {$d eq $widget} {variable state;array unset state "$d,*"}}
proc ::GX::DatasetCurveFit::_templateInvalidate {d} {
    variable state
    set state($d,bound) {};$d.actions.apply configure -state disabled
    $d.review configure -state normal;$d.review delete 1.0 end;$d.review configure -state disabled
}
proc ::GX::DatasetCurveFit::_templateFields {d} {
    variable state
    _templateInvalidate $d
    set id [dict get $state($d,templates) $state($d,template)];set item [templateInspect $id]
    set state($d,requirements) [dict get $item requirements]
    array unset state "$d,mapping,*"
    set choices {};if {$state($d,dataset) ne {}} {set choices [dict get [variables $state($d,dataset)] all]}
    set body $d.map.canvas.body;foreach child [winfo children $body] {destroy $child}
    set row 0
    dict for {original requirement} $state($d,requirements) {
        set state($d,mapping,$original) [expr {$original in $choices?$original:{}}]
        ttk::label $body.label$row -text "$original ([dict get $requirement unit])"
        ttk::combobox $body.value$row -state readonly -values $choices -textvariable ::GX::DatasetCurveFit::state($d,mapping,$original) -width 30
        grid $body.label$row -row $row -column 0 -sticky w -padx 5 -pady 4
        grid $body.value$row -row $row -column 1 -sticky ew -padx 5 -pady 4
        bind $body.value$row <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_templateInvalidate $d]
        incr row
    }
    grid columnconfigure $body 1 -weight 1
}
proc ::GX::DatasetCurveFit::_templateReviewSafe {d} {
    if {[catch {_templateReview $d} message]} {tk_messageBox -parent $d -icon error -type ok -title {Fit template} -message $message}
}
proc ::GX::DatasetCurveFit::_templateReview {d} {
    variable state
    _templateInvalidate $d
    set mapping {};dict for {original ignored} $state($d,requirements) {dict set mapping $original $state($d,mapping,$original)}
    set policy [dict get {{Coordinate regions} coordinate_regions {All rows} all_rows} $state($d,selection)]
    set bound [templateBind [dict get $state($d,templates) $state($d,template)] $state($d,dataset) $mapping $policy]
    set review [dict get $bound review];set recipe [_recipeDecode [dict get $bound recipe]]
    set text "Model: [dict get $review model]\nTarget: $state($d,dataset) · [dict get $review scope] fit points\n"
    dict for {original target} $mapping {append text "$original → $target ([dict get $state($d,requirements) $original unit])\n"}
    append text "Source filters: [dict get $review source_filter_count]; coordinate regions: [dict get $review coordinate_region_count]; original row picks cleared: [dict get $review dropped_original_row_picks]\nInitial values: [dict get $recipe fit initial]\nOutput domain: [dict get $recipe fit domain]\nReview the loaded solver and uncertainty settings, then explicitly Preview and Accept."
    $d.review configure -state normal;$d.review insert 1.0 $text;$d.review configure -state disabled
    set state($d,bound) [dict get $bound recipe];$d.actions.apply configure -state normal
    return $bound
}
proc ::GX::DatasetCurveFit::_templateApplyDialog {w d} {
    if {$w eq {}} {set w [open {workspace_id new}]}
    _uiSafe $w [list ::GX::DatasetCurveFit::_templateApply $w $d]
}
proc ::GX::DatasetCurveFit::_templateApply {w d} {
    variable state
    if {$state($d,bound) eq {}} {error {Review the template bindings before applying settings}}
    recipeValidate $state($d,bound)
    set controls [_operationBegin $w]
    try {recipeLoadSettings $w $state($d,bound)} finally {_operationEnd $w $controls}
    set state($w,schema) [variables $state($w,dataset)];_uiVariableChoices $w
    $w.left.viewport.content.filters.list delete 0 end
    foreach filter $state($w,filters) {$w.left.viewport.content.filters.list insert end "[dict get $filter variable] [dict get $filter operator] [join [dict get $filter value] ,]"}
    _orientationLabels $w;_uiModelFields $w;_uiDomainFields $w
    $w.actions.preview configure -state normal;$w.actions.accept configure -state disabled;$w.actions.publish configure -state disabled
    set state($w,status) {Template settings applied to a distinct source. Review settings, then Preview and Accept explicitly.}
    _workspaceCapture $w;_saveState $w;redraw $w
    destroy $d
}
