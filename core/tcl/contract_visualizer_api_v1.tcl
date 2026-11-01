# SPDX-License-Identifier: GPL-3.0-or-later
# Provider resolution over the existing Contract/Module/Viewer/Preview owners.
# This is not another contract, package, Dataset or rendering registry.
proc ::GX::contractVisualizerApiInfo {} {
    return [dict create api_id CONTRACT_VISUALIZER_API_v1 api_version 1 owner CORE operations {contractRegistryDescribe contractVisualizerProviders contractVisualizerCandidates contractVisualizerResolve contractVisualizerPreferenceGet contractVisualizerPreferenceSet contractVisualizerOpen} targets {open preview} declaration_section contract_visualizers preference_owner CONFIGURATION_API_v1 provenance_constraints bounded_literal_subset scientific_fact_sources {canonical_provenance structured_metadata} conflict_policy reject]
}
proc ::GX::_contractVisualizerIdentifier {value} {
    expr {[string length $value]<=128 && [regexp {^[A-Za-z0-9_][A-Za-z0-9_.:+-]*$} $value]}
}
proc ::GX::_contractVisualizerContractIdentifier {value} {
    # Existing Registry contains literal media-style IDs such as model/step.
    expr {[string length $value]<=128 && [regexp {^[A-Za-z0-9_][A-Za-z0-9_.:+/-]*$} $value]}
}
proc ::GX::_contractVisualizerToken {value} {
    set parts [split $value /]
    expr {[llength $parts]==2 && [_contractVisualizerIdentifier [lindex $parts 0]] && [_contractVisualizerIdentifier [lindex $parts 1]]}
}
proc ::GX::contractVisualizerPreferencesValidate {value} {
    if {[string bytelength $value]>65536 || [catch {dict size $value}] || [dict size $value]>256} {error {Contract preferences require a bounded contract-to-provider map}}
    dict for {contract token} $value {
        if {![_contractVisualizerContractIdentifier $contract] || ![_contractVisualizerToken $token]} {error {Contract preferences contain an invalid contract or qualified provider identity}}
    }
    return $value
}
proc ::GX::contractRegistryDescribe {contract} {
    if {![_contractVisualizerContractIdentifier $contract]} {error {Invalid Dataset contract identity}}
    set providers [contractRegistryField $contract providers {}]
    set owners {};set recommendations [dict create open {} preview {}];set declarations {};set identities {}
    foreach owner $providers {
        if {$owner eq {GX-TXT core}} {lappend owners $owner;continue}
        if {[moduleField $owner descriptor {}] eq {}} continue
        lappend owners $owner
        set data [moduleField $owner dict {}]
        set identity [descriptorValue $data contract.$contract schema_identity {}]
        if {$identity ne {}} {lappend identities $identity}
        set row [dict create owner $owner version [descriptorValue $data contract.$contract version {Not declared}] module_version [moduleField $owner version {}] schema_identity $identity]
        foreach target {open preview} {
            set token [descriptorValue $data contract.$contract recommended_${target}_visualizer {}]
            if {$token ne {}} {
                if {![_contractVisualizerToken $token]} {dict lappend row diagnostics "Invalid recommended $target visualizer";continue}
                dict lappend recommendations $target $token
            }
            dict set row recommended_$target $token
        }
        lappend declarations $row
    }
    set status [expr {[llength $owners] ? {registered} : {missing_provider}}]
    if {[llength [lsort -unique $identities]]>1} {set status conflict}
    foreach target {open preview} {dict set recommendations $target [lsort -unique [dict get $recommendations $target]]}
    return [dict create api_id CONTRACT_REGISTRY_API_v1 contract_id $contract known [contractRegistryKnown $contract] status $status owners $owners description [contractRegistryField $contract description {}] parents [contractRegistryField $contract parents {}] consumers [contractRegistryField $contract consumers {}] producers [contractRegistryField $contract producers {}] declarations $declarations recommendations $recommendations]
}
proc ::GX::_contractVisualizerList {value {limit 32}} {
    set items [splitList $value]
    if {[llength $items]>$limit || [llength [lsort -unique $items]]!=[llength $items]} {error {Invalid bounded visualizer declaration list}}
    return $items
}
proc ::GX::_contractVisualizerProvenanceFields {value} {
    if {[string bytelength $value]>4096 || [catch {dict size $value}] || [dict size $value]>32 || [llength $value]!=2*[dict size $value]} {error {Visualizer provenance constraints require a bounded unique-key dictionary}}
    dict for {key expected} $value {
        if {![regexp {^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,127}$} $key] || $expected eq {} || [string bytelength $expected]>512 || [regexp {[\x00\r\n]} $expected]} {error {Invalid literal provenance constraint}}
    }
    return $value
}
proc ::GX::_contractVisualizerProvenanceMatches {expected actual} {
    if {![dict size [_contractVisualizerProvenanceFields $expected]]} {return 1}
    if {[catch {dict size $actual}]} {return 0}
    dict for {key value} [_contractVisualizerProvenanceFields $expected] {if {![dict exists $actual $key] || [dict get $actual $key] ne $value} {return 0}}
    return 1
}
proc ::GX::_contractVisualizerScientificFactsMatch {expected provenance metadata} {
    set expected [_contractVisualizerProvenanceFields $expected]
    if {![dict size $expected]} {return 1}
    if {[catch {dict size $provenance}]} {set provenance {}}
    if {[catch {dict size $metadata}]} {return 0}
    dict for {key value} $expected {
        set found 0
        foreach actual [list $provenance $metadata] {
            if {![dict exists $actual $key]} continue
            if {[dict get $actual $key] ne $value} {return 0}
            set found 1
        }
        if {!$found} {return 0}
    }
    return 1
}
proc ::GX::_contractVisualizerDatasetFactsMatch {expected datasetId} {
    if {![dict size [_contractVisualizerProvenanceFields $expected]]} {return 1}
    if {[catch {set metadata [datasetMetadataRead $::GX::currentSession $datasetId]}]} {return 0}
    return [_contractVisualizerScientificFactsMatch $expected [datasetField $datasetId provenance {}] $metadata]
}
proc ::GX::_contractVisualizerProvider {module provider} {
    set data [moduleField $module dict {}]
    if {[descriptorValue $data contract_visualizers api_version {}] ne {1} || $provider ni [_contractVisualizerList [descriptorValue $data contract_visualizers ids {}]]} {error {Contract Visualizer is not declared by its installed module}}
    set section contract_visualizer.$provider
    set contracts [_contractVisualizerList [descriptorValue $data $section contracts {}]]
    if {![llength $contracts]} {error {Contract Visualizer must declare actual Dataset contracts}}
    foreach contract $contracts {if {![_contractVisualizerContractIdentifier $contract]} {error {Invalid visualizer contract identity}}}
    set targets [_contractVisualizerList [descriptorValue $data $section targets {}] 2]
    if {![llength $targets]} {error {Contract Visualizer must declare Open or Preview}}
    foreach target $targets {if {$target ni {open preview}} {error {Unknown Contract Visualizer target}}}
    set inheritance [descriptorValue $data $section inheritance exact]
    if {$inheritance ni {exact declared}} {error {Contract inheritance must be exact or declared}}
    set row [dict create token $module/$provider module_id $module provider_id $provider version [moduleField $module version {}] name [descriptorValue $data $section name [moduleField $module name $module]] contracts $contracts targets $targets inheritance $inheritance viewer_id [descriptorValue $data $section viewer_id {}] document_kinds [_contractVisualizerList [descriptorValue $data $section document_kinds {}]] media_types [_contractVisualizerList [descriptorValue $data $section media_types {}]] formats [_contractVisualizerList [descriptorValue $data $section formats {}]] available_targets {} unavailable_reasons {}]
    set sourcePolicy [descriptorValue $data $section source_note_open none]
    if {$sourcePolicy ni {none source_editor_first} || ($sourcePolicy eq {source_editor_first} && {open} ni $targets)} {error {Invalid source-note Open policy}}
    dict set row source_note_open $sourcePolicy
    dict set row match_provenance_fields [_contractVisualizerProvenanceFields [descriptorValue $data $section match_provenance_fields {}]]
    foreach target $targets {
        if {$target eq {open}} {
            set viewer [dict get $row viewer_id]
            if {$viewer eq {} || $viewer ni [viewerProviderIds $module]} {error {Open visualizer requires an existing declared Viewer ID}}
            set available [expr {[moduleIsEnabled $module] && [viewerProviderEnabled $module $viewer]}]
            set reason [expr {$available ? {} : ([moduleIsEnabled $module] ? {Viewer presentation is disabled} : {Visualizer module is disabled})}]
        } else {
            if {[moduleField $module kind {}] ne {preview}} {error {Embedded Preview requires a genuine Preview module}}
            set info [datasetPreviewProviderInfo $module]
            set available [dict get $info available];set reason [dict get $info reason]
        }
        if {$available} {dict lappend row available_targets $target} else {dict set row unavailable_reasons $target $reason}
    }
    return $row
}
proc ::GX::contractVisualizerProviders {} {
    set rows {}
    foreach module $::GX::moduleOrder {
        set data [moduleField $module dict {}]
        set version [descriptorValue $data contract_visualizers api_version {}]
        if {$version eq {}} continue
        if {[catch {set ids [_contractVisualizerList [descriptorValue $data contract_visualizers ids {}]]} reason]} {
            lappend rows [dict create module_id $module valid 0 reason $reason];continue
        }
        foreach provider $ids {
            if {![_contractVisualizerIdentifier $provider] || [catch {_contractVisualizerProvider $module $provider} row]} {
                lappend rows [dict create token $module/$provider module_id $module provider_id $provider valid 0 reason {Invalid or unavailable Contract Visualizer declaration}]
            } else {dict set row valid 1;lappend rows $row}
        }
    }
    return $rows
}
proc ::GX::contractVisualizerCandidates {contract target {datasetId {}}} {
    if {$target ni {open preview}} {error {Visualizer target must be Open or Preview}}
    set result {}
    foreach row [contractVisualizerProviders] {
        if {![dict get $row valid] || $target ni [dict get $row targets]} continue
        set compatible 0
        foreach accepted [dict get $row contracts] {
            if {$contract eq $accepted || ([dict get $row inheritance] eq {declared} && [contractSatisfies $contract $accepted])} {set compatible 1;break}
        }
        if {!$compatible} continue
        if {$datasetId ne {}} {
            if {$datasetId ni [datasetRegistryIds] || [datasetField $datasetId contract [datasetField $datasetId kind {}]] ne $contract} {error {Canonical Dataset identity does not match the requested contract}}
            set kind [datasetDocumentKind $datasetId]
            if {[llength [dict get $row document_kinds]] && $kind ni [dict get $row document_kinds]} continue
            foreach {key field} {media_types media_type formats format} {
                if {[llength [dict get $row $key]] && [datasetField $datasetId $field {}] ni [dict get $row $key]} {set compatible 0}
            }
            if {!$compatible} continue
            if {![_contractVisualizerDatasetFactsMatch [dict get $row match_provenance_fields] $datasetId]} continue
            if {$target eq {preview} && [catch {_datasetPreviewProviderMatch $datasetId [_datasetPreviewProviderDescriptor [dict get $row module_id]]} match]} continue
            if {$target eq {preview} && $match eq {}} continue
        }
        lappend result $row
    }
    return $result
}
proc ::GX::contractVisualizerPreferenceGet {contract target} {
    if {![_contractVisualizerContractIdentifier $contract] || $target ni {open preview}} {error {Invalid contract preference identity or target}}
    set values [configurationGet contracts.${target}_visualizers]
    return [expr {[dict exists $values $contract] ? [dict get $values $contract] : {auto}}]
}
proc ::GX::contractVisualizerPreferenceSet {contract target token} {
    set prior [contractVisualizerPreferenceGet $contract $target]
    if {$token ni {{} auto}} {
        set eligible 0
        foreach row [contractVisualizerCandidates $contract $target] {if {[dict get $row token] eq $token && $target in [dict get $row available_targets]} {set eligible 1}}
        if {!$eligible} {error {Choose an installed, available, compatible visualizer or Restore Auto}}
    }
    set field contracts.${target}_visualizers
    set expected [configurationGet $field];set values $expected
    if {$token in {{} auto}} {dict unset values $contract} else {dict set values $contract $token}
    configurationCommit [list [dict create id $field scope user value $values expected $expected session_token {}]] 1
    return [dict create contract_id $contract target $target prior $prior preference [contractVisualizerPreferenceGet $contract $target]]
}
proc ::GX::contractVisualizerResolve {contract target {datasetId {}}} {
    set definition [contractRegistryDescribe $contract]
    set preference [contractVisualizerPreferenceGet $contract $target]
    set out [dict create schema gxtxt.contract_visualizer_resolution.v1 contract_id $contract target $target contract_status [dict get $definition status] preference $preference status core_fallback selected_token {} selection_source core candidates {} diagnostics {}]
    if {$datasetId ne {}} {
        set reference [datasetViewerReference $datasetId]
        if {[dict get $reference contract] ne $contract} {error {Requested contract differs from its canonical Dataset}}
        dict set out dataset_reference $reference
        dict set out dataset_revision [datasetRevisionToken $datasetId]
    }
    if {[dict get $definition status] ne {registered}} {
        dict set out status [dict get $definition status]
        dict lappend out diagnostics {Contract definition is missing or conflicting; original Dataset bytes and metadata remain preserved}
        return $out
    }
    set candidates [contractVisualizerCandidates $contract $target $datasetId]
    set available {}
    foreach row $candidates {if {$target in [dict get $row available_targets]} {dict set available [dict get $row token] $row}}
    dict set out candidates [dict keys $available]
    set selected {};set reason {}
    if {$preference ne {auto}} {
        if {[dict exists $available $preference]} {set selected $preference;set reason user
        } else {dict lappend out diagnostics "Preferred $target visualizer $preference is unavailable or incompatible; preference retained"}
    }
    if {$selected eq {}} {
        set recommendations [dict get $definition recommendations $target]
        set eligible {}
        foreach token $recommendations {if {[dict exists $available $token]} {lappend eligible $token}}
        if {[llength $eligible]==1} {set selected [lindex $eligible 0];set reason recommendation
        } elseif {[llength $eligible]>1} {dict lappend out diagnostics {Contract owners recommend competing compatible providers}}
    }
    if {$selected eq {} && [dict size $available]==1} {set selected [lindex [dict keys $available] 0];set reason unique_compatible}
    if {$selected ne {}} {
        dict set out status selected;dict set out selected_token $selected;dict set out selection_source $reason
        foreach key {module_id provider_id viewer_id version} {dict set out $key [dict get $available $selected $key]}
    } elseif {[dict size $available]>1} {dict set out status ambiguous;dict lappend out diagnostics {Several compatible providers are available; select a preference or retain the safe CORE fallback}}
    return $out
}
proc ::GX::contractVisualizerOpen {datasetId {resolution {}}} {
    set reference [datasetViewerReference $datasetId]
    if {$resolution eq {}} {set resolution [contractVisualizerResolve [dict get $reference contract] open $datasetId]}
    if {[dict get $resolution status] ne {selected} || [dict get $resolution target] ne {open}} {error {No compatible Open visualizer was selected}}
    if {![dict exists $resolution dataset_reference] || ![dict exists $resolution dataset_revision]} {error {Open requires a Dataset-aware resolution pinned to its original revision}}
    set pinned [_datasetViewerReferenceValidate [dict get $resolution dataset_reference]]
    if {[dict get $pinned dataset_id] ne $datasetId || [dict get $resolution dataset_revision] ne [datasetRevisionToken $datasetId]} {error {Canonical Dataset changed before visualizer dispatch}}
    set current [contractVisualizerResolve [dict get $reference contract] open $datasetId]
    if {$current ne $resolution} {error {Visualizer preference or provider changed before dispatch}}
    set row [_contractVisualizerProvider [dict get $resolution module_id] [dict get $resolution provider_id]]
    if {[dict get $row source_note_open] eq {source_editor_first} && [llength [info commands ::GX::sourceNoteOpen]]} {return [sourceNoteOpen $datasetId $resolution]}
    return [viewerOpen [dict get $resolution module_id] [dict get $resolution viewer_id] [dict create dataset_id $datasetId dataset_reference $reference open_role contract_visualizer]]
}
