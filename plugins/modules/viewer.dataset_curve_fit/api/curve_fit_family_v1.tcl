# SPDX-License-Identifier: GPL-3.0-or-later
# Independent family members reuse existing filtered source and batch fit owners.
proc ::GX::DatasetCurveFit::_familyMembersChecked {dataset variable members} {
    set spec [::GX::datasetVariableV3ById $dataset $variable]
    if {![dict get $spec enabled]||[dict get $spec rank]!=1||[dict get $spec dtype] in {complex64 complex128}} {error {Family grouping requires an enabled real or text rank-one Variable}}
    if {[llength $members]<1||[llength $members]>64} {error {Choose one to 64 explicit independent family members}}
    set canonical {};set seen {}
    foreach value $members {
        if {[string bytelength $value]>1024} {error {Family member identity exceeds the 1024-byte chooser bound}}
        set identity [::GX::graphSeriesCanonicalMember [dict get $spec dtype] $value]
        if {[dict exists $seen $identity]} {error {Family members must be distinct in their declared scientific dtype}}
        dict set seen $identity 1;lappend canonical $identity
    }
    return $canonical
}
proc ::GX::DatasetCurveFit::familyMembers {dataset variable} {
    set before [::GX::curveSourceDatasetIdentity $::GX::currentSession $dataset]
    set spec [::GX::datasetVariableV3ById $dataset $variable]
    if {![dict get $spec enabled]||[dict get $spec rank]!=1||[dict get $spec dtype] in {complex64 complex128}} {error {Family grouping requires an enabled real or text rank-one Variable}}
    set values [::GX::graphSeriesDistinctValues $dataset $variable 4096 1 64]
    set members {};set seen {}
    foreach value $values {
        set identity [::GX::graphSeriesCanonicalMember [dict get $spec dtype] $value]
        if {![dict exists $seen $identity]} {dict set seen $identity 1;lappend members $identity}
    }
    if {$before ne [::GX::curveSourceDatasetIdentity $::GX::currentSession $dataset]} {error {Dataset changed during family discovery}}
    return [dict create api_id FITTER_FAMILY_MEMBERS_v1 api_version 1 dataset_id $dataset variable_id $variable dtype [dict get $spec dtype] members $members source_identity $before scope dataset_before_active_filters]
}
proc ::GX::DatasetCurveFit::familySourcesCreate {key variable members} {
    variable state
    _assertLoaded $key
    if {$state($key,sourceKind) ne "dataset"||$state($key,sourceTransformManifest) ne {}} {error {Independent family sources require a canonical Dataset; materialize an edited source first}}
    lassign $state($key,loadedBinding) dataset x y filters
    set members [_familyMembersChecked $dataset $variable $members]
    # The explicitly chosen member replaces an existing equality on that same
    # family Variable. Other source predicates remain in every independent fit.
    set filters [lmap filter $filters {if {[dict get $filter variable] eq $variable&&[dict get $filter operator] eq "="} continue;set filter}]
    set spec [::GX::datasetVariableV3ById $dataset $variable];set axis [::GX::datasetVariableV3ById $dataset $x]
    if {[dict get $spec shape] ne [dict get $axis shape]||[dict get $spec dimension_ids] ne [dict get $axis dimension_ids]} {error {Family values must align with the source observation rows}}
    _workspaceCapture $key;set active $state($key,activeSource);set prior [dict keys $state($key,sources)];set created {};set mapping {}
    set expected $state($key,sourceIdentities)
    set template {};if {[info exists state($key,templateBinding)]} {set template $state($key,templateBinding)}
    try {
        foreach member $members {
            loadSource $key $dataset $x $y [concat $filters [list [dict create variable $variable operator = value $member]]] {} $expected
            set id $state($key,activeSource);lappend created $id
            set state($key,scope) all
            if {$template ne {}} {set state($key,templateBinding) $template}
            _workspaceCapture $key
            lappend mapping [dict create member_value $member source_curve_id $id]
        }
    } on error {message options} {
        set added {};foreach id [dict keys $state($key,sources)] {if {$id ni $prior} {lappend added $id}}
        if {$added ne {}} {removeSources $key $added}
        return -options $options "Family member '$member': $message"
    } finally {if {[dict exists $state($key,sources) $active]} {activateSource $key $active}}
    return [dict create api_id FITTER_FAMILY_SOURCES_v1 api_version 1 dataset_id $dataset variable_id $variable source_curve_ids $created members $mapping fit_semantics independent_per_member]
}
proc ::GX::DatasetCurveFit::familyRun {encoded variable members name} {
    variable state
    recipeValidate $encoded;set recipe [_recipeDecode $encoded]
    if {[dict get $recipe source source_kind] ne "dataset"||[::GX::datasetPublicationV2DictDefault [dict get $recipe source] source_transform_manifest {}] ne {}} {error {Family execution needs a canonical Dataset recipe}}
    if {[dict get $recipe fit model] eq "registered"} {error {Registered family models require their supervised asynchronous callback workflow}}
    set members [_familyMembersChecked [dict get $recipe source source_dataset_id] $variable $members]
    set name [string trim $name]
    if {$name eq {}||[string length $name]>160||[regexp {[\x00-\x1f\x7f]} $name]} {error {Family Workspace name must contain one to 160 printable characters}}
    foreach workspace [::GX::sessionWorkspaceList] {if {[dict get $workspace name] eq $name} {error {Choose a new family Workspace name}}}
    # Explicit family semantics: use every row passing each member's filters.
    # Old observation-specific picks never become picks in another member.
    dict set recipe fit scope all
    dict set recipe fit selection_descriptor [dict create api_id CURVE_SOURCE_POINT_MASK_v1 base_selected 0 regions {} manual_rows {}]
    set key [new]
    try {
        recipeLoadSettings $key [::GX::scientificRecipeEncode $recipe] 0
        set base $state($key,activeSource);set planned [familySourcesCreate $key $variable $members]
        set ids [dict get $planned source_curve_ids];removeSources $key [list $base]
        set fit [dict get $recipe fit];set state($key,workspaceName) $name
        previewSources $key $ids [dict get $fit model] all [dict get $fit domain] [dict get $fit degree] [dict get $fit initial] [dict get $fit options]
        set names {};set index 0;foreach id $ids {dict set names $id "Independent family fit [incr index]"}
        acceptSources $key $ids $names;_saveState $key
        ::GX::sessionWorkspaceRename $state($key,documentId) $name
        set results {};foreach member [dict get $planned members] record $state($key,records) {
            dict set member reference [resultReference $state($key,documentId) [dict get $record fit_curve_id]]
            lappend results $member
        }
        return [dict create api_id FITTER_FAMILY_RESULT_v1 api_version 1 document_id $state($key,documentId) dataset_id [dict get $planned dataset_id] variable_id $variable fit_semantics independent_per_member selection_policy all_rows_matching_nonmember_filters_and_selected_member members $results]
    } finally {close $key}
}
proc ::GX::DatasetCurveFit::_familyContext {w} {
    variable state
    _assertLoaded $w
    return [list $state($w,activeSource) $state($w,loadedBinding) $state($w,sourceSha)]
}
proc ::GX::DatasetCurveFit::_familyDialog {w} {
    variable state
    set context [_familyContext $w]
    if {$state($w,sourceKind) ne "dataset"||$state($w,sourceTransformManifest) ne {}} {error {Load a canonical Dataset source for independent family fitting}}
    set variables {};foreach spec [::GX::datasetVariableSchemaV3 $state($w,dataset)] {if {[dict get $spec enabled]&&[dict get $spec rank]==1&&[dict get $spec dtype] ni {complex64 complex128}} {lappend variables [dict get $spec variable_id]}}
    set fields [dict create variable [dict create type choice label {Family / group Variable ID} values $variables required 1]]
    set variable [lindex $variables end]
    foreach preferred {member_id family_id family_value group_id group} {if {$preferred in $variables} {set variable $preferred;break}}
    ::GX::uiFieldFormCreate $w.familyVariable {Independent family sources} $fields [dict create variable $variable] [list ::GX::DatasetCurveFit::_familyChoose $w $context] $w
    $w.familyVariable.actions.apply configure -text {Choose members}
}
proc ::GX::DatasetCurveFit::_familyChoose {w context values} {
    variable state
    if {[_familyContext $w] ne $context} {error {Active source changed; reopen family selection}}
    set variable [dict get $values variable];set plan [familyMembers $state($w,dataset) $variable]
    set fields {};set defaults {};set index 0
    foreach member [dict get $plan members] {
        set id member[incr index];set label $member;if {$label eq {}} {set label {(empty text)}}
        dict set fields $id [dict create type boolean label $label];dict set defaults $id 1
    }
    if {$index==0} {error {The Dataset has no finite/text member values to choose}}
    destroy $w.familyVariable
    ::GX::uiFieldFormCreate $w.familyMembers {Replace family equality; keep other filters — choose members} $fields $defaults [list ::GX::DatasetCurveFit::_familyApply $w $context $plan] $w
    $w.familyMembers.actions.apply configure -text {Add independent sources}
}
proc ::GX::DatasetCurveFit::_familyApply {w context plan values} {
    variable state
    if {[_familyContext $w] ne $context} {error {Active source changed; reopen family selection}}
    set members {};set index 0;foreach member [dict get $plan members] {if {[dict get $values member[incr index]]} {lappend members $member}}
    _familyMembersChecked $state($w,dataset) [dict get $plan variable_id] $members
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    set controls [_operationBegin $w]
    try {
        set result [familySourcesCreate $w [dict get $plan variable_id] $members]
        set ids [dict get $result source_curve_ids];activateSource $w [lindex $ids 0]
        $w.left.viewport.content.sources.body.sources selection set $ids
        _workspaceCapture $w
    } finally {_operationEnd $w $controls}
    set state($w,historyDescription) {Add independent family sources}
    try {_saveState $w;redraw $w} finally {unset -nocomplain state($w,historyDescription)}
    set state($w,status) "Added [llength $ids] independent member sources. Review settings, Fit selected curves, then Accept selected previews and publish their parameter Dataset."
    destroy $w.familyMembers
    return $result
}
