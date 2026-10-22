# SPDX-License-Identifier: GPL-3.0-or-later
# Optional declarative planning only. CORE owns every filesystem operation and
# global exclusion; absence or invalid declarations never affect module loading.
proc ::GX::experimentDuplicationPolicyInfo {} {
    return [dict create api_id EXPERIMENT_DUPLICATION_POLICY_API_v1 api_version 1 optional 1 actions {COPY_PREPARATION RESET_TO_DEFAULT EXCLUDE PRESERVE_VALID_EXTERNAL_REFERENCE} callbacks 0 receipt_version 1]
}
proc ::GX::experimentDuplicationPolicyValidate {descriptor} {
    set errors {};set configs {};set documents {};set files {}
    if {[catch {dict size $descriptor}]} {return [dict create valid 0 errors {not_a_dictionary} configs {} documents {} files {}]}
    if {[descriptorValue $descriptor experiment_duplication api_version {}] ne "1"} {lappend errors unsupported_policy_version}
    set owner [descriptorValue $descriptor meta id {}]
    foreach key [splitList [descriptorValue $descriptor experiment_duplication config_copy {}]] {
        dict set configs $key COPY_PREPARATION
    }
    foreach key [splitList [descriptorValue $descriptor experiment_duplication config_external {}]] {
        if {[dict exists $configs $key]} {lappend errors "conflicting_config:$key"}
        dict set configs $key PRESERVE_VALID_EXTERNAL_REFERENCE
    }
    dict for {key action} $configs {
        if {$key ni [splitList [descriptorValue $descriptor config fields {}]]} {lappend errors "undeclared_config:$key"}
        if {[regexp -nocase {(dataset|workspace|selection|graph|source_descriptor|sha256)} $key]} {lappend errors "scientific_config:$key"}
        # A generic name such as input does not make a Dataset/Selection or
        # variable/table binding independent. Reuse Standard Module types and
        # binding declarations; this is policy validation, never an install gate.
        set type [string tolower [descriptorValue $descriptor "config.$key" type string]]
        if {$type in {dataset variable selection temporal_set table model analysis_definition} || $key in [splitList [descriptorValue $descriptor bindings roles {}]] || [descriptorValue $descriptor "config.$key" source {}] ne {} || [descriptorValue $descriptor "config.$key" source_role {}] ne {}} {lappend errors "scientific_config_type:$key:$type"}
        if {$action eq "PRESERVE_VALID_EXTERNAL_REFERENCE" && $type ni {file path}} {lappend errors "external_config_type:$key:$type"}
    }
    foreach name [splitList [descriptorValue $descriptor experiment_duplication documents {}]] {
        set section duplication_document.$name;set record {}
        foreach key {provider format format_version action payload_kind} {
            dict set record $key [descriptorValue $descriptor $section $key {}]
        }
        if {[dict get $record action] ni {COPY_PREPARATION EXCLUDE RESET_TO_DEFAULT}} {lappend errors "document_action:$name"}
        if {[dict get $record payload_kind] ni {structured author_code}} {lappend errors "document_kind:$name"}
        foreach key {provider format format_version} {if {[dict get $record $key] eq {} || [regexp {[\r\n*?]} [dict get $record $key]]} {lappend errors "document_identity:$name:$key"}}
        set identity [list [dict get $record provider] [dict get $record format] [dict get $record format_version]]
        if {[dict exists $documents $identity]} {lappend errors "duplicate_document:$name"}
        dict set documents $identity $record
    }
    # A module cannot declare arbitrary source Session paths as preparation.
    # This dedicated relative owner root makes file ownership explicit.
    foreach path [splitList [descriptorValue $descriptor experiment_duplication preparation_files {}]] {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $owner] || ![string match "preparation/$owner/*" $path] || [file pathtype $path] ne "relative" || ".." in [file split $path] || [regexp {[*?\[\\]} $path]} {lappend errors "unsafe_preparation_path:$path"} else {lappend files $path}
    }
    return [dict create valid [expr {![llength $errors]}] errors $errors configs $configs documents $documents files $files]
}
proc ::GX::experimentDuplicationPolicyModule {moduleId} {
    set descriptor [moduleField $moduleId dict {}]
    if {$descriptor eq {} || ![dict exists $descriptor experiment_duplication.api_version]} {
        return [dict create module_id $moduleId status unsupported valid 0 errors {optional_policy_absent} configs {} documents {} files {}]
    }
    set result [experimentDuplicationPolicyValidate $descriptor]
    dict set result module_id $moduleId
    dict set result status [expr {[dict get $result valid] ? "supported" : "invalid"}]
    return $result
}
proc ::GX::_experimentDuplicationNativeDocument {format version} {
    # Historical CORE schemas are compatibility adapters, not a growing module
    # ID switch. Unknown old objects have no fabricated preparation provenance.
    set schemas [dict create gxtxt.curve_workbench.workspace EXCLUDE gxtxt.pdf_ocr.workspace EXCLUDE gxtxt.table_extractor.workspace EXCLUDE workbench3d.document.v1 EXCLUDE gxtxt.workspace.staging EXCLUDE gxtxt.plot_dataset.interactive_scene EXCLUDE]
    if {[dict exists $schemas $format]} {return [dict create action EXCLUDE payload_kind structured origin native_legacy_schema]}
    if {$format eq "gxtxt.octave_script.document" && $version eq "1.0"} {return [dict create action COPY_PREPARATION payload_kind author_code origin native_author_code]}
    if {$format eq "gxtxt.native3d.viewer_state" && $version eq "1.0"} {return [dict create action COPY_PREPARATION payload_kind structured origin native_one_source_viewer]}
    return {}
}
proc ::GX::_experimentDuplicationDocumentPolicy {item} {
    set provider [dict get $item provider_id];set format [dict get $item format];set version [dict get $item format_version]
    if {[dict exists $::GX::SessionWorkspace::providers $provider] && $format eq [dict get $::GX::SessionWorkspace::providers $provider schema]} {return [dict create action EXCLUDE payload_kind structured origin registered_workspace]}
    set native [_experimentDuplicationNativeDocument $format $version]
    if {$native ne {} && [dict get $native action] eq "EXCLUDE"} {return $native}
    if {[dict exists $item duplication_policy]} {
        set receipt [dict get $item duplication_policy]
        if {[catch {
            if {[dict get $receipt api_version] ne "1"} {error unsupported_receipt}
            foreach key {module_id provider_id format format_version generation} {if {[dict get $receipt $key] ne [dict get $item $key]} {error "stale_receipt:$key"}}
            if {[dict get $receipt action] ni {COPY_PREPARATION EXCLUDE RESET_TO_DEFAULT} || [dict get $receipt payload_kind] ni {structured author_code}} {error invalid_receipt}
        } reason]} {return [dict create action EXCLUDE payload_kind structured origin "invalid_owner_receipt:$reason"]}
        return $receipt
    }
    if {$native ne {}} {return $native}
    # Old objects require a currently installed exact provider/schema contract.
    set policy [experimentDuplicationPolicyModule [dict get $item module_id]]
    set identity [list $provider $format $version]
    if {[dict get $policy valid] && [dict exists $policy documents $identity]} {return [dict merge [dict get $policy documents $identity] {origin installed_exact_schema}]}
    return [dict create action EXCLUDE payload_kind structured origin unproved_optional_owner]
}
proc ::GX::_experimentDuplicationRegistrationReceipt {item} {
    set policy [_experimentDuplicationDocumentPolicy $item]
    # Only an actual declaration or a documented native adapter can record
    # classification at registration. Absence must stay absence for old modules.
    if {[dict get $policy origin] eq "unproved_optional_owner"} {return $item}
    foreach key {module_id provider_id format format_version generation} {dict set policy $key [dict get $item $key]}
    dict set policy api_version 1
    dict set item duplication_policy $policy
    return $item
}

# A staging import changes its declared schema in the normal Document owner.
# Reclassify only an exact automatically derived prior registration receipt;
# explicit owner policy must never be silently carried into another schema.
proc ::GX::_experimentDuplicationDocumentTransition {prior item} {
    if {[dict exists $prior duplication_policy]} {
        set derived [_experimentDuplicationRegistrationReceipt [dict remove $prior duplication_policy]]
        if {![dict exists $derived duplication_policy]} {error {Explicit duplication policy requires an owner-reviewed format transition}}
        set expected [dict get $derived duplication_policy]
        set actual [dict get $prior duplication_policy]
        if {[lsort [dict keys $actual]] ne [lsort [dict keys $expected]]} {error {Explicit duplication policy requires an owner-reviewed format transition}}
        dict for {key value} $expected {
            if {[dict get $actual $key] ne $value} {error {Explicit duplication policy requires an owner-reviewed format transition}}
        }
    }
    return [_experimentDuplicationRegistrationReceipt [dict remove $item duplication_policy]]
}
