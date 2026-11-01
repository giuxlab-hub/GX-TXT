# SPDX-License-Identifier: GPL-3.0-or-later
# A declared native form projects the existing single Analysis queue. It is not
# a scheduler, scientific pipeline, Registry writer or plugin-specific adapter.
proc ::GX::moduleTargetedAnalysisApiInfo {} {
    return [dict create api_id MODULE_TARGETED_ANALYSIS_API_v1 api_version 1 owner CORE host_only 1 operations {moduleAnalysisCapabilities moduleAnalysisSubmit moduleAnalysisStatus moduleAnalysisCancel} native_client_operations {analysis_command} host_operations {viewerGuiDesignAnalysisCommand} execution_owner standard_analysis_queue result_page_rows_max 25 result_bytes_max 49152 implicit_enablement 0]
}
proc ::GX::_viewerGuiAnalysisDesignValidate {design} {
    set components {};foreach c [dict get $design components] {dict set components [dict get $c id] $c}
    set claimed {};set actions {}
    foreach c [dict get $design components] {
        set p [dict get $c properties]
        set present 0;foreach key [dict keys $p] {if {[string match analysis_* $key]} {set present 1}}
        if {!$present} continue
        if {[dict get $c type] ne {section} || [datasetPublicationV2DictDefault $design target viewer] ne {viewer}} {error {Analysis profile requires a Viewer section}}
        if {[datasetPublicationV2DictDefault [dict get $design requirements] MODULE_TARGETED_ANALYSIS_API_v1 0]!=1} {error {Analysis profile requires its separate targeted Analysis API}}
        foreach key {analysis_module analysis_dataset analysis_bindings analysis_config analysis_status analysis_candidates analysis_candidate analysis_comparison_form analysis_commands} {if {![dict exists $p $key]} {error "Incomplete Analysis profile: $key"}}
        if {![regexp {^[a-z][a-z0-9_.-]{0,127}$} [dict get $p analysis_module]]} {error {Analysis target requires a stable module identity}}
        foreach {key types} {analysis_dataset dataset_selector analysis_status log analysis_candidates table analysis_candidate {choice combobox} analysis_comparison_form section} {
            set id [dict get $p $key]
            if {![dict exists $components $id] || [dict get $components $id type] ni $types} {error "Invalid Analysis component: $key"}
            if {$key ne {analysis_comparison_form}} {
                if {$id in $claimed} {error {Analysis component is already owned by another form}}
                lappend claimed $id
            }
        }
        if {![dict exists $components [dict get $p analysis_comparison_form] properties comparison_target]} {error {Analysis comparison target requires an existing Comparison section}}
        foreach map {analysis_bindings analysis_config} {
            set value [dict get $p $map]
            if {[string bytelength $value]>8192 || [catch {dict size $value}] || [llength $value]!=2*[dict size $value]} {error {Analysis control maps require bounded unique keys}}
            dict for {role id} $value {
                if {![regexp {^[a-z][a-z0-9_]{0,63}$} $role] || ![dict exists $components $id] || [dict get $components $id type] ni {field entry choice combobox toggle checkbutton}} {error {Analysis mapping requires stable parameter/role and declared value control}}
            }
        }
        if {[dict exists $p analysis_page] && (![dict exists $components [dict get $p analysis_page]] || [dict get $components [dict get $p analysis_page] type] ni {field entry})} {error {Analysis page requires an integer value control}}
        dict for {action operation} [dict get $p analysis_commands] {
            set effect [expr {$operation in {submit cancel}?{mutating}:{presentation}}]
            if {$operation ni {discover submit status cancel candidates add_candidate} || $action in $actions || ![dict exists $design handlers $action] || [dict get $design handlers $action effect] ne $effect} {error {Analysis commands require distinct finite handlers with the correct effect}}
            foreach other [dict get $design components] {foreach property {comparison_commands plot_series_commands transform_commands catalog_actions} {if {[dict exists $other properties $property $action]} {error {Analysis action conflicts with another public owner}}}}
            lappend actions $action
        }
    }
}
proc ::GX::_viewerGuiAnalysisForm {window form} {
    if {![viewerGuiDesignGuard $window]} {error {Analysis form belongs to a previous context}}
    set c [viewerGuiDesignComponent $window $form]
    if {[dict get $c type] ne {section} || ![dict exists $c properties analysis_module]} {error {Select a complete declared Analysis form}}
    _viewerGuiAnalysisDesignValidate [dict get $::GX::ViewerGui::instances $window design]
    return [dict get $c properties]
}
proc ::GX::_viewerAnalysisSourceIdentity {dataset} {
    set canonical [curveSourceDatasetIdentity $::GX::currentSession $dataset]
    return [dict create dataset_id $dataset sha256 [dict get $canonical sha256] revision_sha256 [datasetStorageSha256Text $::GX::currentSession [datasetRevisionPortableToken $dataset]] schema_sha256 [datasetStorageSha256Text $::GX::currentSession [datasetVariableSchemaV3 $dataset]]]
}
proc ::GX::_viewerAnalysisResultDefinition {module} {
    set descriptor [parseIni [moduleField $module descriptor]]
    set section analysis_result.ranked_references
    if {[descriptorValue $descriptor $section role {}] ne {ranked_references_v1}} {error {Analysis module has no declared ranked-reference result contract}}
    set definition {}
    foreach key {columns rank_column library_id_column library_version_column library_content_hash_column entry_id_column} {
        set value [descriptorValue $descriptor $section $key {}]
        if {$value eq {}} {error "Analysis result declaration lacks $key"}
        dict set definition $key $value
    }
    dict set definition columns [splitList [dict get $definition columns]]
    if {[llength [dict get $definition columns]]>32 || [llength [dict get $definition columns]]!=[llength [lsort -unique [dict get $definition columns]]]} {error {Invalid ranked result column bound}}
    foreach key {rank_column library_id_column library_version_column library_content_hash_column entry_id_column} {if {[dict get $definition $key] ni [dict get $definition columns]} {error {Result identity mapping is outside declared columns}}}
    return $definition
}
proc ::GX::_viewerGuiAnalysisBindingChoices {window p} {
    set values [viewerGuiDesignValues $window]
    set dataset [dict get $values [dict get $p analysis_dataset]]
    set ids {}
    if {$dataset ne {} && $::GX::currentSession ne {}} {
        foreach variable [datasetVariableSchemaV3 $dataset] {
            if {[dict get $variable enabled] && [dict get $variable rank]==1 && [dict get $variable dtype] ni {string bool}} {lappend ids [dict get $variable variable_id]}
        }
    }
    dict for {role component} [dict get $p analysis_bindings] {
        if {[dict get [viewerGuiDesignComponent $window $component] type] in {choice combobox}} {viewerGuiDesignChoicesSet $window $component $ids}
        if {[dict get $values $component] ni $ids} {viewerGuiDesignValueSet $window $component {}}
    }
    return $ids
}
proc ::GX::_viewerGuiAnalysisInitialize {window} {
    # Mapped controls belong to the public form owner. Palette demonstration
    # values must never masquerade as actual Variable IDs or candidate ranks.
    # This runs once before ordinary Workspace/History restoration; it performs
    # no Analysis submission, module enablement or result generation.
    foreach component [dict get $::GX::ViewerGui::instances $window design components] {
        set p [dict get $component properties]
        if {![dict exists $p analysis_module]} continue
        _viewerGuiAnalysisBindingChoices $window $p
        viewerGuiDesignChoicesSet $window [dict get $p analysis_candidate] {}
        viewerGuiDesignValueSet $window [dict get $p analysis_candidate] {}
        viewerGuiDesignTableSet $window [dict get $p analysis_candidates] {}
        viewerGuiDesignTextSet $window [dict get $p analysis_status] {Select a canonical Dataset and its actual Variable IDs. Run Analysis explicitly, then read its ranked results; no Analysis has been started by opening this form.}
    }
}
proc ::GX::_viewerAnalysisCandidates {window form} {
    set p [_viewerGuiAnalysisForm $window $form];set values [viewerGuiDesignValues $window]
    set module [dict get $p analysis_module];set source [dict get $values [dict get $p analysis_dataset]]
    set identity [_viewerAnalysisSourceIdentity $source];set definition [_viewerAnalysisResultDefinition $module];set found {}
    foreach id [datasetRegistryIds] {
        if {[datasetField $id producer_module {}] ne $module} continue
        set provenance [datasetField $id provenance {}]
        if {[catch {dict size $provenance}] || [datasetPublicationV2DictDefault $provenance analysis_result_role {}] ne {ranked_references_v1} || [datasetPublicationV2DictDefault $provenance source_dataset_id {}] ne $source} continue
        foreach {target field} {source_sha256 sha256 source_revision_sha256 revision_sha256 source_schema_sha256 schema_sha256} {
            if {![dict exists $provenance $target] || [dict get $provenance $target] ne [dict get $identity $field]} {error {Ranked results belong to a stale scientific source; rerun Analysis}}
        }
        lappend found $id
    }
    if {[llength $found]!=1} {error {Select a source with exactly one current declared ranked-reference result Dataset}}
    set id [lindex $found 0];set count [datasetField $id row_count 0]
    # These are the real published result's source Variables, never today's
    # editable form bindings or inferred X/Y names. They remain inspectable even
    # when the user changes a control before consulting a retained result.
    set sourceVariables [splitList [datasetField $id source_variable_ids {}]]
    if {![llength $sourceVariables] || [llength $sourceVariables]>32 || [llength $sourceVariables]!=[llength [lsort -unique $sourceVariables]]} {error {Ranked result requires distinct actual published source Variable identities}}
    foreach variable $sourceVariables {if {![dict get [datasetVariableV3ById $source $variable] enabled]} {error {Ranked result refers to an unavailable source Variable}}}
    if {![string is entier -strict $count] || $count<0 || $count>100} {error {Ranked reference result exceeds its 100-row contract}}
    set offset 0
    if {[dict exists $p analysis_page]} {set page [dict get $values [dict get $p analysis_page]];if {![string is entier -strict $page] || $page<0 || ($count && $page*25>=$count)} {error {Select an existing zero-based ranked-result page}};set offset [expr {$page*25}]}
    set before [_viewerAnalysisSourceIdentity $id]
    set page [datasetPreviewPage $::GX::currentSession $id [dict create start $offset count 25 variable_ids [dict get $definition columns]]]
    if {[_viewerAnalysisSourceIdentity $id] ne $before || [_viewerAnalysisSourceIdentity $source] ne $identity} {error {Scientific result/source changed during read}}
    set ranks {};set records {};set rows [dict get $page rows]
    set rankIndex [lsearch -exact [dict get $definition columns] [dict get $definition rank_column]]
    foreach row $rows {
        set rank [lindex $row $rankIndex]
        if {![string is integer -strict $rank] || $rank<1 || $rank>100 || $rank in $ranks} {error {Malformed stable candidate rank}}
        lappend ranks $rank
        set record {};foreach column [dict get $definition columns] value $row {dict set record $column $value}
        dict set records $rank $record
    }
    set record [dict create source $identity source_variable_ids $sourceVariables result $before definition $definition records $records offset $offset total $count]
    set table [uiFieldComponentTableWidget [dict get $::GX::ViewerGui::instances $window widgets [dict get $p analysis_candidates]]]
    if {![dict exists $::GX::ViewerGui::instances $window analysis_selection_bound $form]} {
        bind $table <<TreeviewSelect>> +[list ::GX::_viewerAnalysisCandidateSelected $window $form $table]
        dict set ::GX::ViewerGui::instances $window analysis_selection_bound $form 1
    }
    dict set ::GX::ViewerGui::instances $window analysis_candidates $form $record
    viewerGuiDesignTableSet $window [dict get $p analysis_candidates] $rows
    set selectionRanks {};foreach item [$table children {}] rank $ranks {dict set selectionRanks $item $rank}
    dict set ::GX::ViewerGui::instances $window analysis_candidates $form selection_ranks $selectionRanks
    viewerGuiDesignChoicesSet $window [dict get $p analysis_candidate] $ranks
    if {[dict get $values [dict get $p analysis_candidate]] ni $ranks} {viewerGuiDesignValueSet $window [dict get $p analysis_candidate] [lindex $ranks 0]}
    return $record
}
proc ::GX::_viewerAnalysisCandidateSelected {window form table} {
    if {![viewerGuiDesignGuard $window] || ![winfo exists $table] || ![dict exists $::GX::ViewerGui::instances $window analysis_candidates $form selection_ranks]} return
    set selection [$table selection]
    if {[llength $selection]!=1} return
    set ranks [dict get $::GX::ViewerGui::instances $window analysis_candidates $form selection_ranks]
    if {![dict exists $ranks [lindex $selection 0]]} return
    set p [_viewerGuiAnalysisForm $window $form]
    viewerGuiDesignValueSet $window [dict get $p analysis_candidate] [dict get $ranks [lindex $selection 0]]
}
proc ::GX::viewerGuiDesignAnalysisCommand {window form operation} {
    set p [_viewerGuiAnalysisForm $window $form];set values [viewerGuiDesignValues $window]
    set module [dict get $p analysis_module];set caller [dict get $::GX::ViewerGui::instances $window actor_module]
    if {$operation ni {discover submit status cancel candidates add_candidate}} {error {Unknown finite Analysis command}}
    if {$operation in {submit cancel add_candidate} && [dict exists $::GX::ScientificHistory::viewers $window] && ![scientificHistoryViewerEditable $window]} {error {Return to latest History before changing Analysis or comparison}}
    set result [dict create status $operation module_id $module]
    switch $operation {
        discover {
            _viewerGuiAnalysisBindingChoices $window $p
            set cap [moduleAnalysisCapabilities $module]
            set result [dict merge $result [dict create available [dict get $cap available] reason [dict get $cap reason]]]
        }
        submit {
            if {![moduleIsEnabled $module]} {error {Enable the target Analysis module explicitly before running it}}
            set dataset [dict get $values [dict get $p analysis_dataset]];set source [_viewerAnalysisSourceIdentity $dataset]
            set config {};dict for {key component} [dict get $p analysis_config] {dict set config $key [dict get $values $component]}
            set bindings {};dict for {role component} [dict get $p analysis_bindings] {set id [dict get $values $component];set variable [datasetVariableV3ById $dataset $id];if {![dict get $variable enabled]} {error {Select an enabled canonical Variable}};dict set bindings $role primary.$id}
            set receipt [moduleAnalysisSubmit $caller $module [dict create session_token [interactiveDocumentSessionToken] sources [dict create primary $dataset] config $config bindings $bindings]]
            dict set ::GX::ViewerGui::instances $window analysis_runs $form [dict get $receipt run_id]
            set result [dict merge $result [dict create run_id [dict get $receipt run_id] state [dict get $receipt state] source $source]]
        }
        status - cancel {
            if {![dict exists $::GX::ViewerGui::instances $window analysis_runs $form]} {error {This form has no admitted Analysis invocation}}
            set run [dict get $::GX::ViewerGui::instances $window analysis_runs $form]
            set receipt [expr {$operation eq {cancel}?[moduleAnalysisCancel $caller $module $run]:[moduleAnalysisStatus $caller $module $run]}]
            set result [dict merge $result [dict create run_id $run state [dict get $receipt state] reason [dict get $receipt reason]]]
        }
        candidates {set result [dict merge $result [dict remove [_viewerAnalysisCandidates $window $form] selection_ranks]]}
        add_candidate {
            if {![_viewerComparisonLibraryAllowed $window]} {error {Candidate consultation requires the separate read-only Library capability}}
            if {![dict exists $::GX::ViewerGui::instances $window analysis_candidates $form]} {error {Read the current candidate table before selecting a reference}}
            set cached [dict get $::GX::ViewerGui::instances $window analysis_candidates $form]
            if {[dict get $values [dict get $p analysis_dataset]] ne [dict get $cached source dataset_id]} {error {The selected Dataset changed; read its ranked results before adding a candidate}}
            foreach key {source result} {set identity [dict get $cached $key];if {[_viewerAnalysisSourceIdentity [dict get $identity dataset_id]] ne $identity} {error {Candidate/source revision changed; refresh the result table}}}
            set rank [dict get $values [dict get $p analysis_candidate]]
            if {![dict exists $cached records $rank]} {error {Select an actual displayed stable candidate rank}}
            set candidate [dict get $cached records $rank];set definition [dict get $cached definition]
            set library [dict get $candidate [dict get $definition library_id_column]];set entry [dict get $candidate [dict get $definition entry_id_column]]
            set info [::GX::ScientificLibraryManagerAPIv1::getLibraryEntryInfo $library $entry]
            foreach {mapping field} {library_version_column source_library_version library_content_hash_column source_library_content_hash} {
                if {![dict exists $info provenance $field] || [dict get $info provenance $field] ne [dict get $candidate [dict get $definition $mapping]]} {error {Candidate references a changed Library version/content; rerun Analysis}}
            }
            set source [comparisonPlotSourceLibrary $library $entry]
            foreach key {source result} {set identity [dict get $cached $key];if {[_viewerAnalysisSourceIdentity [dict get $identity dataset_id]] ne $identity} {error {Candidate/source changed during reference admission}}}
            set target [dict get $p analysis_comparison_form];_viewerGuiComparisonForm $window $target
            set sources [_viewerGuiComparisonSources $window $target]
            if {$source in $sources || [llength $sources]>=8} {error {Duplicate or ninth Comparison source refused}}
            lappend sources $source;dict set ::GX::ViewerGui::instances $window comparison_sources $target $sources
            _viewerGuiComparisonCapture $window;_viewerGuiComparisonRefresh $window $target {Added current ranked reference. Prepare explicitly; similarity is not probability.}
            if {![dict get $::GX::ViewerGui::instances $window restoring] && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerRecordOperation $window {Add current ranked reference}}
            set result [dict merge $result [dict create rank $rank library_id $library entry_id $entry source_count [llength $sources]]]
        }
    }
    viewerGuiDesignTextSet $window [dict get $p analysis_status] $result
    return $result
}
proc ::GX::_viewerAnalysisNativeCommand {window form operation} {
    set scope [_viewerNativeClientScope $window];set r [dict get $::GX::ViewerDevelopment::windows $window]
    set seq [expr {[datasetPublicationV2DictDefault $r analysis_sequence 0]+1}];dict set ::GX::ViewerDevelopment::windows $window analysis_sequence $seq
    set status completed;set problem {};set typed {null {}}
    try {
        if {{analysis_command} ni [datasetPublicationV2DictDefault [dict get $r native_client_grants] MODULE_TARGETED_ANALYSIS_API_v1 {}]} {error {Targeted Analysis native capability is not granted}}
        set p [_viewerGuiAnalysisForm $window $form];set action [dict get $scope action]
        set effect [expr {$operation in {submit cancel}?{mutating}:{presentation}}]
        if {![dict get $scope user_action] || [dict get $scope effect] ne $effect || ![dict exists $p analysis_commands $action] || [dict get $p analysis_commands $action] ne $operation} {error {Analysis requires its exact declared user action}}
        set result [viewerGuiDesignAnalysisCommand $window $form $operation]
        _viewerNativeClientScope $window
        set fields {};dict for {key value} $result {
            if {$key in {records definition}} continue
            if {$key in {source result}} {dict set fields $key [nativeWorkspaceEncode {record {dataset_id text sha256 text revision_sha256 text schema_sha256 text}} $value]
            } elseif {$key eq {source_variable_ids}} {dict set fields $key [nativeWorkspaceEncode {array text} $value]
            } elseif {$key in {available offset total rank source_count}} {dict set fields $key [list int $value]
            } else {dict set fields $key [list text [_viewerNativeClientPublicMessage $value]]}
        }
        if {[dict exists $result records]} {
            set records {};dict for {rank row} [dict get $result records] {lappend records [nativeWorkspaceEncode {map text} $row]}
            dict set fields records [list array $records]
        }
        set typed [list object $fields]
    } on error {message options} {set status failed;set problem [_viewerNativeClientPublicMessage $message];if {[viewerGuiDesignGuard $window]} {catch {viewerGuiDesignTextSet $window [dict get $p analysis_status] "Analysis refused: $problem"}}}
    if {[dict exists $::GX::ViewerDevelopment::windows $window]} {dict set ::GX::ViewerDevelopment::windows $window analysis_result [_viewerNativeClientEnvelope $operation $status $problem $typed [list object [dict create form [list text $form]]] $seq [dict get $scope generation]]}
    if {$status eq {failed}} {return -code error $problem}
}
proc ::GX::_viewerAnalysisSnapshot {window} {
    set r [_viewerNativeClientBase $window]
    return [_viewerWorkspaceTypedJson [datasetPublicationV2DictDefault $r analysis_result [_viewerNativeClientEnvelope snapshot completed {} {null {}} {object {}} 0 0]]]
}

# Ordinary Builder model operation: all dependent mappings, handlers and API
# requirement enter one validated undoable edit, with no source execution.
proc ::GX::viewerGuiDesignAnalysisProfile {design form properties} {
    if {[catch {dict size $properties}] || [string bytelength $properties]>16384} {error {Analysis profile properties require a bounded dictionary}}
    foreach key [dict keys $properties] {if {$key ni {analysis_module analysis_dataset analysis_bindings analysis_config analysis_status analysis_candidates analysis_candidate analysis_comparison_form analysis_page}} {error {Unknown Analysis profile field}}}
    set components [dict get $design components];set index -1
    for {set i 0} {$i<[llength $components]} {incr i} {if {[dict get [lindex $components $i] id] eq $form} {set index $i;break}}
    if {$index<0 || [dict get [lindex $components $index] type] ne {section}} {error {Select an ordinary declared section}}
    set component [lindex $components $index];set old [datasetPublicationV2DictDefault [dict get $component properties] analysis_commands {}]
    set stem analysis_[format %08x [zlib crc32 $form]];set commands {};set labels {}
    foreach {operation label} {discover {Discover Analysis source} submit {Run Analysis} status {Analysis status} cancel {Cancel owned Analysis} candidates {Read ranked references} add_candidate {Add selected ranked reference}} {
        set action ${stem}_$operation
        if {[dict exists $design handlers $action] && (![dict exists $old $action] || [dict get $old $action] ne $operation)} {error {Generated Analysis action conflicts with another declared owner}}
        dict set commands $action $operation
        dict set design handlers $action [dict create arguments {window action} effect [expr {$operation in {submit cancel}?{mutating}:{presentation}}] label $label]
    }
    set menu ${stem}_menu;set replaced 0
    for {set i 0} {$i<[llength $components]} {incr i} {
        set c [lindex $components $i]
        if {[dict get $c id] ne $menu} continue
        if {[dict get $c type] ne {menu} || ![dict exists $c properties actions] || [dict get $c properties actions] ne [dict keys $old]} {error {Analysis menu identity conflicts with another owner}}
        dict set c properties actions [dict keys $commands];lset components $i $c;set replaced 1
    }
    if {!$replaced} {lappend components [dict create id $menu type menu parent menubar properties [dict create label Analysis actions [dict keys $commands]] layout {row 0 column 0 weight 0 sticky ew padding 0}]}
    dict set component properties [dict merge [dict get $component properties] $properties [dict create analysis_commands $commands]]
    lset components $index $component;dict set design components $components
    dict set design requirements MODULE_TARGETED_ANALYSIS_API_v1 1
    return [viewerGuiDesignValidate $design]
}
