# SPDX-License-Identifier: GPL-3.0-or-later
# Standard Module-owned Preview contributions. Presentation components use the
# existing public API loader; native components retain their strict ABI/package
# admission. Module/Package/GUI owners retain lifecycle and rendering authority.
namespace eval ::GX::PreviewProvider {
    variable descriptorKeys {api_version native_abi native_library native_sha256 native_platform native_layout_id native_build_id dataset_contracts capabilities gui_design gui_design_sha256 gui_contract gui_public_api gui_handler_factory}
    variable capabilities {grouped_curves bounded_array_plane raster_overlay}
    variable matchKeys {view_role match_producer_modules match_source_modules match_producer_versions match_provenance match_metadata match_semantic_roles match_source_contracts}
}
proc ::GX::_datasetPreviewProviderError {code message} {return -code error -errorcode [list GX PREVIEW_PROVIDER $code] $message}
proc ::GX::_datasetPreviewProviderRelative {value} {
    if {$value eq {} || [string bytelength $value]>2048 || [file pathtype $value] ne {relative} || [regexp {[\\:\x00\r\n]} $value]} {error {Invalid package-relative Preview asset}}
    foreach component [split $value /] {if {$component in {{} . ..}} {error {Invalid package-relative Preview asset}}}
    return $value
}
proc ::GX::_datasetPreviewProviderDescriptor {id} {
    set data [moduleField $id dict {}]
    if {[moduleField $id kind {}] ne {preview} || [descriptorValue $data meta id {}] ne $id || [moduleField $id runner {}] ne {service} || ![moduleField $id selectable 1]} {error {Expected an ordinary selectable Preview service module}}
    if {[moduleField $id enabled_key {}] ne {} || [moduleField $id run_key {}] ne {}} {error {Preview components require ordinary per-module activation without legacy Configuration aliases}}
    set profile [descriptorValue $data preview_provider profile native]
    if {$profile ni {native presentation}} {error {Unsupported Preview provider profile}}
    set allowed [linsert $::GX::PreviewProvider::descriptorKeys 0 profile]
    if {$profile eq {presentation}} {set allowed {profile api_version dataset_contracts gui_public_api}}
    set allowed [concat $allowed $::GX::PreviewProvider::matchKeys gui_api_version]
    set prefix preview_provider.
    foreach key [dict keys $data ${prefix}*] {
        if {[string range $key [string length $prefix] end] ni $allowed} {error {Unknown Preview provider descriptor field for its profile}}
    }
    set out [dict create component_id $id profile $profile]
    set guiVersion [descriptorValue $data preview_provider gui_api_version 0]
    if {$guiVersion ni {0 1}} {error {Unsupported optional Preview GUI API version}}
    dict set out gui_api_version $guiVersion
    dict set out view_role [descriptorValue $data preview_provider view_role [expr {$profile eq {native} ? {primary} : {complementary}}]]
    if {[dict get $out view_role] ni {primary complementary}} {error {Invalid Preview view role}}
    foreach key [lrange $::GX::PreviewProvider::matchKeys 1 end] {
        set value [descriptorValue $data preview_provider $key {}]
        if {[string bytelength $value]>4096 || [regexp {[\x00\r\n]} $value]} {error {Invalid Preview match declaration}}
        if {$key eq {match_metadata}} {
            if {[catch {dict size $value}] || [dict size $value]>32} {error {Invalid Preview metadata constraints}}
            dict for {name expected} $value {_datasetMetadataValidateKey $name}
        } elseif {$key ne {match_provenance}} {
            set value [splitList $value]
            if {[llength $value]>32 || [llength [lsort -unique $value]]!=[llength $value]} {error {Invalid Preview match list}}
            foreach item $value {if {![regexp {^[A-Za-z0-9_][A-Za-z0-9_.:+-]*$} $item]} {error {Invalid Preview match identity}}}
        }
        dict set out $key $value
    }
    if {$profile eq {presentation}} {
        foreach key {api_version dataset_contracts gui_public_api} {
            set value [descriptorValue $data preview_provider $key {}]
            if {$value eq {} || [string bytelength $value]>4096 || [regexp {[\x00\r\n]} $value]} {error "Missing or invalid Preview presentation field: $key"}
            dict set out $key $value
        }
        if {[dict get $out api_version] ne {1}} {error {Unsupported Preview presentation API version}}
        dict set out dataset_contracts [_datasetPreviewProviderContracts [dict get $out dataset_contracts]]
        dict set out capabilities {tabs}
        _datasetPreviewProviderPublicApi $data [dict get $out gui_public_api]
        return $out
    }
    foreach key $::GX::PreviewProvider::descriptorKeys {
        set value [descriptorValue $data preview_provider $key {}]
        if {$value eq {} || [string bytelength $value]>4096 || [regexp {[\x00\r\n]} $value]} {error "Missing or invalid Preview provider field: $key"}
        dict set out $key $value
    }
    if {[dict get $out api_version] ne {1} || [dict get $out native_abi] ne {gxtxt.preview.provider.v1} || [dict get $out gui_contract] ne {VIEWER_GUI_HOST_API_v1}} {error {Unsupported Preview provider contract}}
    foreach key {native_sha256 gui_design_sha256 native_layout_id} {if {![regexp {^[0-9a-f]{64}$} [dict get $out $key]]} {error {Invalid Preview provider digest or layout ID}}}
    foreach key {native_library gui_design} {dict set out $key [_datasetPreviewProviderRelative [dict get $out $key]]}
    foreach key {dataset_contracts capabilities} {
        set values [splitList [dict get $out $key]]
        if {![llength $values] || [llength $values]>32 || [llength [lsort -unique $values]]!=[llength $values]} {error {Invalid Preview provider declaration list}}
        foreach value $values {
            if {$key eq {capabilities} && $value ni $::GX::PreviewProvider::capabilities} {error {Unknown Preview processing capability}}
            if {$key eq {dataset_contracts} && ![regexp {^[A-Za-z0-9][A-Za-z0-9_.:-]*$} $value]} {error {Invalid canonical Dataset contract ID}}
        }
        dict set out $key $values
    }
    # An explicit ordinary public-API activation declaration is mandatory for
    # Builder-generated handlers. Context never supplies an arbitrary command.
    if {[dict get $out gui_handler_factory] ne {handlers}} {error {Preview controlled GUI factory is not declared}}
    _datasetPreviewProviderPublicApi $data [dict get $out gui_public_api]
    return $out
}
proc ::GX::_datasetPreviewProviderContracts {raw} {
    set values [splitList $raw]
    if {![llength $values] || [llength $values]>32 || [llength [lsort -unique $values]]!=[llength $values]} {error {Invalid Preview Dataset contracts}}
    foreach value $values {if {![regexp {^[A-Za-z0-9][A-Za-z0-9_.:-]*$} $value]} {error {Invalid canonical Dataset contract ID}}}
    return $values
}
proc ::GX::_datasetPreviewProviderPublicApi {data gui} {
    if {$gui ne {PREVIEW_COMPONENT_GUI_API_v1} || $gui ni [splitList [descriptorValue $data public_apis ids {}]]} {error {Preview public API is not declared}}
    set section public_api.$gui
    if {[descriptorValue $data $section api_version {}] ne {1}} {error {Unsupported Preview public API contract}}
    _datasetPreviewProviderRelative [descriptorValue $data $section entrypoint {}]
    if {![regexp {^::GX::[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)*$} [descriptorValue $data $section namespace {}]]} {error {Invalid Preview public API namespace}}
}
proc ::GX::_datasetPreviewProviderHostInfo {} {
    # Compiled CORE metadata only; this operation may not dlopen a provider.
    if {![llength [info commands ::gx::native2d::_preview_provider]] && [llength [info commands ::GX::datasetPreviewNativeEnsure]]} {datasetPreviewNativeEnsure}
    if {![llength [info commands ::gx::native2d::_preview_provider]]} {return {}}
    set result [::gx::native2d::_preview_provider info]
    foreach key {native_abi native_platform native_layout_id native_build_id} {if {![dict exists $result $key]} {error {Incomplete native Preview host identity}}}
    return $result
}
proc ::GX::_datasetPreviewProviderPackageState {id} {
    # MAIN owns this strictly inert lifecycle/package projection, including
    # current byte verification/admission invalidation. No private fallback.
    if {![llength [info commands ::GX::_pluginPreviewProviderState]]} {return {}}
    set state [::GX::_pluginPreviewProviderState $id]
    foreach key {schema component_id installed_version enabled generation active_version pending_version admission} {if {![dict exists $state $key]} {error {Incomplete Preview package state}}}
    if {[dict get $state schema] ne {gxtxt.preview_package_state.v1} || [dict get $state component_id] ne $id || ![string is boolean -strict [dict get $state enabled]] || ![string is entier -strict [dict get $state generation]] || [dict get $state generation]<0} {error {Invalid Preview package state}}
    dict set state enabled [expr {!![dict get $state enabled]}]
    return $state
}
proc ::GX::datasetPreviewProviderInfo {componentId} {
    if {$componentId ni $::GX::moduleOrder || [moduleField $componentId kind {}] ne {preview}} {_datasetPreviewProviderError INVALID_ARGUMENT {Unknown Preview component}}
    set id $componentId
    set out [dict create component_id $id profile native name [moduleField $id name $id] installed_version [moduleField $id version {}] active_version {} pending_version {} enabled 0 descriptor_valid 0 assets_valid 0 native_abi {} native_platform {} native_layout_id {} native_build_id {} dataset_contracts {} capabilities {} verified_capabilities {} gui_design_sha256 {} compatibility_status unknown load_status not_checked available 0 admission_fingerprint {} reason {Preview descriptor is invalid}]
    # Reject forbidden Configuration aliases before either activation or package
    # state can interpret an unrelated cfg value as a module boolean.
    if {[catch {set declaration [_datasetPreviewProviderDescriptor $id]} message]} {dict set out reason [string range $message 0 255];return $out}
    dict set out enabled [moduleIsEnabled $id]
    dict set out profile [dict get $declaration profile]
    foreach key $::GX::PreviewProvider::matchKeys {dict set out $key [dict get $declaration $key]}
    if {[dict get $declaration profile] eq {presentation}} {
        dict set out descriptor_valid 1
        dict set out assets_valid 1
        dict set out dataset_contracts [dict get $declaration dataset_contracts]
        dict set out capabilities {tabs}
        dict set out compatibility_status compatible
        if {[dict exists $::GX::pluginRuntimeLoaded $id]} {dict set out active_version [dict get $::GX::pluginRuntimeLoaded $id]}
        if {[dict exists $::GX::pluginRuntimePending $id]} {
            dict set out pending_version [dict get $::GX::pluginRuntimePending $id version]
            dict set out load_status restart_required;dict set out reason {Preview update requires activation}
        } elseif {![dict get $out enabled]} {
            dict set out reason {Preview component is disabled}
        } else {
            # This is callable presentation, not native byte admission. Keep
            # native verified-capability/fingerprint fields empty and honest.
            dict set out available 1
            dict set out reason {Presentation API activates on Dataset Preview}
        }
        return $out
    }
    set stateInvalid [catch {set state [_datasetPreviewProviderPackageState $id]}]
    if {!$stateInvalid && $state ne {}} {
        foreach key {active_version pending_version} {dict set out $key [dict get $state $key]}
        if {[dict get $state pending_version] ne {}} {dict set out load_status restart_required}
    }
    dict set out descriptor_valid 1
    if {![llength [info commands ::GX::_datasetPreviewNativeAssets]] || [catch {_datasetPreviewNativeAssets $id} assetsReason]} {dict set out reason {Preview native package assets are missing or invalid};return $out}
    dict set out assets_valid 1
    foreach key {native_abi native_platform native_layout_id native_build_id dataset_contracts capabilities gui_design_sha256} {dict set out $key [dict get $declaration $key]}
    if {[catch {set host [_datasetPreviewProviderHostInfo]}]} {dict set out reason {Native Preview host identity is unavailable};return $out}
    if {$host eq {}} {dict set out reason {Native Preview provider ABI is unavailable};return $out}
    foreach key {native_abi native_platform native_layout_id} {
        if {[dict get $declaration $key] ne [dict get $host $key]} {dict set out compatibility_status incompatible;dict set out reason {Preview native ABI, platform or value layout does not match};return $out}
    }
    dict set out compatibility_status compatible
    if {$stateInvalid} {dict set out reason {Package admission state is invalid};return $out}
    if {$state eq {}} {dict set out reason {Package admission is unavailable};return $out}
    if {[dict get $state installed_version] ne [dict get $out installed_version] || [dict get $state enabled]!=[dict get $out enabled]} {dict set out reason {Preview activation or installed version changed};return $out}
    if {[dict get $state pending_version] ne {}} {dict set out load_status restart_required;dict set out reason {Preview update requires activation};return $out}
    if {![dict get $out enabled]} {dict set out reason {Preview component is disabled};return $out}
    set admission [dict get $state admission]
    if {$admission eq {}} {dict set out reason {Preview native admission has not been checked};return $out}
    set valid [expr {![catch {
        if {[dict get $admission schema] ne {gxtxt.preview_admission.v1} || [dict get $admission component_id] ne $id || [dict get $admission version] ne [dict get $out installed_version] || [dict get $admission generation]!=[dict get $state generation] || [dict get $admission host_build_id] ne [dict get $host native_build_id]} {error {Admission identity changed}}
        foreach key {native_abi native_platform native_layout_id native_build_id native_sha256 gui_design_sha256} {if {[dict get $admission $key] ne [dict get $declaration $key]} {error {Admission bytes or ABI changed}}}
        if {![regexp {^[0-9a-f]{64}$} [dict get $admission fingerprint]]} {error {Invalid admission fingerprint}}
        set verified [dict get $admission verified_capabilities]
        if {![llength $verified] || [llength [lsort -unique $verified]]!=[llength $verified]} {error {Invalid admitted capabilities}}
        foreach capability $verified {if {$capability ni [dict get $declaration capabilities]} {error {Undeclared admitted capability}}}
    }]}]
    if {!$valid} {dict set out load_status failed;dict set out reason {Preview admission does not match the current package};return $out}
    dict set out verified_capabilities $verified
    dict set out admission_fingerprint [dict get $admission fingerprint]
    dict set out load_status verified;dict set out available 1;dict set out reason {}
    return $out
}
proc ::GX::_datasetPreviewCoreSpecialization {id} {
    if {[datasetProviderFor $id] eq {remote}} {return [dict create component_id remote reason {Existing remote Preview owner}]}
    set format [string tolower [datasetField $id format]]
    set media [datasetPreviewMediaClass [datasetField $id media_type] $format [datasetField $id contract [datasetField $id kind]] [datasetField $id path]]
    if {$format in {stl obj step stp vtp vtu vti} || $media eq {mesh}} {return [dict create component_id native3d reason {Existing CORE geometry Preview}]}
    if {$media in {image pdf audio video}} {return [dict create component_id media reason {Existing CORE media Preview}]}
    if {![catch {set manifest [datasetPreviewCurveManifest $id]}] && $manifest ne {}} {return [dict create component_id curve_digitizer reason {Validated Curve Digitizer Dataset schema}]}
    return {}
}
proc ::GX::_datasetPreviewProviderMatch {id declaration} {
    set actual [datasetField $id contract [datasetField $id kind]]
    if {![contractSatisfiesAny $actual [dict get $declaration dataset_contracts]]} {return {}}
    set reasons {}
    foreach key {producer_modules source_modules producer_versions} field {producer_module source_module producer_version} {
        set expected [dict get $declaration match_$key]
        if {![llength $expected]} continue
        if {[datasetField $id $field {}] ni $expected} {return {}}
        lappend reasons $field
    }
    set expected [dict get $declaration match_provenance]
    if {$expected ne {}} {
        if {[datasetField $id provenance {}] ne $expected} {return {}}
        lappend reasons provenance
    }
    set expected [dict get $declaration match_metadata]
    if {[dict size $expected]} {
        set metadata [datasetMetadataRead $::GX::currentSession $id]
        set contributors [datasetMetadataContributors $::GX::currentSession $id]
        dict for {key value} $expected {
            if {![dict exists $metadata $key] || [dict get $metadata $key] ne $value || ![dict exists $contributors $key]} {return {}}
            set origin [dict get $contributors $key]
            if {![dict get $origin verified] || ![string match module:* [dict get $origin original_contributor]] || ![string match module:* [dict get $origin last_contributor]]} {return {}}
        }
        lappend reasons metadata
    }
    set expected [dict get $declaration match_semantic_roles]
    if {[llength $expected]} {
        set roles {}
        foreach variable [datasetVariableSchemaV3 $id] {if {[dict get $variable enabled]} {lappend roles [dict get $variable semantic_role]}}
        foreach role $expected {if {$role ni $roles} {return {}}}
        lappend reasons semantic_roles
    }
    set expected [dict get $declaration match_source_contracts]
    if {[llength $expected]} {
        set sources [splitList [datasetField $id source_dataset_ids {}]]
        if {![llength $sources]} {return {}}
        foreach source $sources {if {$source ni [datasetRegistryIds]} {return {}}}
        foreach contract $expected {
            set matched 0
            foreach source $sources {if {[contractSatisfiesAny [datasetField $source contract [datasetField $source kind]] [list $contract]]} {set matched 1}}
            if {!$matched} {return {}}
        }
        lappend reasons source_contracts
        foreach contract $expected {if {$contract ne {table.generic}} {lappend reasons scientific_source_contract;break}}
    }
    if {$actual ne {table.generic} && $actual in [dict get $declaration dataset_contracts]} {lappend reasons scientific_contract}
    set scientific 0
    foreach reason $reasons {if {$reason in {producer_module source_module metadata semantic_roles scientific_contract scientific_source_contract}} {set scientific 1}}
    return [dict create match_strength [expr {$scientific ? {specialized} : {generic}}] match_reasons $reasons]
}
proc ::GX::datasetPreviewProviders {{datasetId {}}} {
    if {$datasetId ne {} && $datasetId ni [datasetRegistryIds]} {_datasetPreviewProviderError INVALID_ARGUMENT {Unknown canonical Dataset}}
    set out {}
    foreach id [lsort $::GX::moduleOrder] {
        if {[moduleField $id kind {}] ne {preview}} continue
        set item [datasetPreviewProviderInfo $id]
        if {$datasetId ne {}} {
            if {![dict get $item descriptor_valid] || [catch {set match [_datasetPreviewProviderMatch $datasetId [_datasetPreviewProviderDescriptor $id]]}] || $match eq {}} continue
            set item [dict merge $item $match]
        }
        lappend out $item
    }
    return $out
}
proc ::GX::datasetPreviewSelection {id {successful *}} {
    set core [_datasetPreviewCoreSpecialization $id]
    set specialized {};set generic {}
    foreach item [datasetPreviewProviders $id] {
        if {![dict get $item enabled] || [dict get $item compatibility_status] eq {incompatible} || [dict get $item pending_version] ne {}} continue
        set component [dict get $item component_id]
        if {[dict get $item profile] eq {native} && ![dict get $item assets_valid]} continue
        if {[dict get $item profile] eq {presentation} && (![dict get $item available] || ($successful ne {*} && $component ni $successful))} continue
        if {[dict get $item view_role] ne {primary}} continue
        if {[dict get $item match_strength] eq {specialized}} {lappend specialized $component} else {lappend generic $component}
    }
    set preferred [expr {[llength $specialized] ? $specialized : $generic}]
    set winner {};set reason {Generic CORE inspection; no specialized component applies}
    if {[llength $specialized]==1} {
        set candidate [lindex $specialized 0]
        if {$successful eq {*} || $candidate in $successful} {set winner $candidate;set reason {One metadata-compatible specialized component}}
    }
    if {[llength $preferred]>1} {set reason {Equally suitable Preview alternatives; choose explicitly}}
    if {$core ne {}} {set winner {};set reason [dict get $core reason]}
    return [dict create core_specialized [expr {$core ne {}}] core_id [datasetPublicationV2DictDefault $core component_id {}] primary_components $preferred specialized_components $specialized default_component $winner conflict [expr {$core eq {} && [llength $preferred]>1}] generic_available 1 reason $reason]
}
proc ::GX::_datasetPreviewProviderDefaultCapability {id} {
    # Standard is the existing default owner plan, not arbitrary render options.
    # Other media/mesh/remote/one-column descriptive routes remain with their
    # existing owners; a scientific provider candidate never suppresses them.
    if {[datasetProviderFor $id] eq {remote}} {return {}}
    set format [string tolower [datasetField $id format]]
    set media [datasetPreviewMediaClass [datasetField $id media_type] $format [datasetField $id contract [datasetField $id kind]] [datasetField $id path]]
    if {$format in {stl obj step stp vtp vtu vti} || $media in {mesh image pdf audio video}} {return {}}
    set axes [scientificDatasetAxes $id]
    if {[dict get $axes x] ne {} && [dict get $axes y] ne {}} {return grouped_curves}
    # Match the existing Preview default plan when roles are not assigned: its
    # first two numeric variables supply the ordinary curve axes.
    if {[dict get $axes x] eq {} && [llength [dict get $axes numeric]]>=2} {return grouped_curves}
    foreach variable [datasetVariableSchemaV3 $id] {if {[dict get $variable enabled] && [dict get $variable rank]>=2 && [dict get $variable value_kind] ne {text}} {return bounded_array_plane}}
    return {}
}
proc ::GX::datasetPreviewProviderSelect {datasetId {capability standard} {preferred {}}} {
    if {$datasetId ni [datasetRegistryIds]} {_datasetPreviewProviderError INVALID_ARGUMENT {Unknown canonical Dataset}}
    foreach one $capability {if {$one ni [linsert $::GX::PreviewProvider::capabilities 0 standard]} {_datasetPreviewProviderError INVALID_ARGUMENT {Unknown Preview capability}}}
    if {$capability eq {standard}} {set capability [_datasetPreviewProviderDefaultCapability $datasetId]}
    set result [dict create status unavailable component_id {} capability $capability candidates {} admission_required 0 code NO_COMPATIBLE_PROVIDER reason {Standard CORE Preview remains available}]
    if {$capability eq {} || $preferred eq {generic}} {return $result}
    set core [_datasetPreviewCoreSpecialization $datasetId]
    if {$core ne {}} {dict set result status core;dict set result code CORE_SPECIALIZED;dict set result reason [dict get $core reason];return $result}
    set specialized {};set generic {};set records {}
    foreach item [datasetPreviewProviders $datasetId] {
        if {[dict get $item profile] ne {native} || ![dict get $item assets_valid] || ![dict get $item enabled] || [dict get $item compatibility_status] eq {incompatible} || [dict get $item pending_version] ne {}} continue
        set compatible 1
        foreach one $capability {if {$one ni [dict get $item capabilities]} {set compatible 0}}
        if {!$compatible} continue
        set component [dict get $item component_id];dict set records $component $item
        if {[dict get $item match_strength] eq {specialized}} {lappend specialized $component} else {lappend generic $component}
    }
    set candidates [expr {[llength $specialized] ? $specialized : $generic}]
    dict set result candidates $candidates
    if {$preferred ne {}} {
        if {$preferred ni $candidates} {dict set result code INCOMPATIBLE_SELECTION;dict set result reason {Selected Preview is missing, disabled or incompatible};return $result}
        set candidates [list $preferred]
    }
    if {[llength $candidates]>1} {dict set result status selection_required;dict set result code PREVIEW_CONFLICT;dict set result reason {Equally suitable native Preview components; choose explicitly};return $result}
    if {![llength $candidates]} {return $result}
    set item [dict get $records [lindex $candidates 0]]
    dict set result status candidate;dict set result component_id [dict get $item component_id];dict set result code {};dict set result reason {}
    set admission [expr {![dict get $item available]}]
    foreach one $capability {if {$one ni [dict get $item verified_capabilities]} {set admission 1}}
    dict set result admission_required $admission
    return $result
}

# Read-only cache binding of ordinary Module/loader state and current source
# bytes. This is derived on demand, never a second provider/package registry.
proc ::GX::_datasetPreviewProviderCanonicalIdentity {id} {
    set result {}
    foreach field {contract producer_module source_module producer_version provenance source_dataset_ids} {dict set result $field [datasetField $id $field {}]}
    set linked {}
    foreach source [splitList [dict get $result source_dataset_ids]] {
        dict set linked $source [expr {$source in [datasetRegistryIds] ? [datasetField $source contract [datasetField $source kind]] : {unavailable}}]
    }
    dict set result source_contracts $linked
    dict set result contributors [datasetMetadataContributors $::GX::currentSession $id]
    return $result
}
proc ::GX::datasetPreviewProviderIdentity {datasetId} {
    set identity [list canonical [_datasetPreviewProviderCanonicalIdentity $datasetId]];set hasNative 0
    foreach info [datasetPreviewProviders $datasetId] {
        set id [dict get $info component_id]
        set assets {}
        set descriptor [moduleField $id descriptor {}]
        set data [moduleField $id dict {}]
        set root [file dirname $descriptor]
        set entry [descriptorValue $data public_api.PREVIEW_COMPONENT_GUI_API_v1 entrypoint {}]
        foreach relative [list [file tail $descriptor] $entry] {
            set digest unavailable
            if {![catch {_datasetPreviewProviderRelative $relative}]} {
                set path [file normalize [file join $root $relative]]
                if {[string match ${root}/* $path] && [file isfile $path]} {set digest [sha256File $path]}
            }
            lappend assets $relative $digest
        }
        set state {}
        foreach key {component_id profile installed_version enabled descriptor_valid dataset_contracts capabilities pending_version view_role match_strength match_reasons} {dict set state $key [dict get $info $key]}
        if {[dict get $info profile] eq {native}} {set hasNative 1}
        lappend identity [list $state $assets]
    }
    if {$hasNative && [llength [info commands ::GX::datasetPreviewNativeIdentity]]} {
        if {[catch {set native [datasetPreviewNativeIdentity $datasetId]} why]} {set native [list unavailable $why]}
        lappend identity [list native $native]
    }
    return $identity
}

# Ephemeral execution projection of the existing Module owner, not saved state.
proc ::GX::_datasetPreviewActivationIdentity {id} {
    set descriptor [moduleField $id descriptor {}]
    if {$descriptor eq {} || ![file isfile $descriptor] || [parseIni $descriptor] ne [moduleField $id dict {}]} {error {Preview activation catalog bytes changed}}
    return [dict create version [moduleField $id version {}] descriptor_sha256 [sha256File $descriptor]]
}
proc ::GX::_datasetPreviewActivationDependencies {previews} {
    set dependencies {}
    dict for {id record} $previews {
        if {![dict get $record enabled]} continue
        set graph [_modulePreviewDependencyPaths $id]
        if {[llength [dict get $graph cycles]]} {error {Preview activation has a dependency cycle}}
        foreach dependency [lsort [dict keys [dict get $graph paths]]] {
            if {$dependency ni $::GX::moduleOrder} {error {Preview activation dependency is not installed}}
            if {[dict exists $previews $dependency] && ![dict get $previews $dependency enabled]} {error {Preview activation dependency is explicitly disabled}}
            dict set dependencies $dependency [_datasetPreviewActivationIdentity $dependency]
        }
    }
    return $dependencies
}
proc ::GX::_datasetPreviewActivationSnapshot {} {
    set session [sessionInspectionCurrentSession]
    _modulePreviewValidateSelection [join [selectedModuleIds] {;}]
    set previews {}
    foreach id [_modulePreviewSelectionIds] {dict set previews $id [dict merge [_datasetPreviewActivationIdentity $id] [dict create enabled [moduleIsEnabled $id]]]}
    return [dict create schema gxtxt.preview_activation.v1 session $session previews $previews dependencies [_datasetPreviewActivationDependencies $previews]]
}
proc ::GX::_datasetPreviewActivationValidate {snapshot} {
    if {[string bytelength $snapshot]>262144 || [catch {dict size $snapshot}] || [lsort [dict keys $snapshot]] ne {dependencies previews schema session}} {error {Invalid private Preview activation snapshot}}
    if {[dict get $snapshot schema] ne {gxtxt.preview_activation.v1} || [dict get $snapshot session] ne [sessionInspectionCurrentSession]} {error {Preview activation Session identity changed}}
    set previews [dict get $snapshot previews]
    if {[catch {dict size $previews}] || [dict size $previews]>512 || [lsort [dict keys $previews]] ne [_modulePreviewSelectionIds]} {error {Preview activation catalog identity changed}}
    dict for {id record} $previews {
        if {[catch {dict size $record}] || [lsort [dict keys $record]] ne {descriptor_sha256 enabled version} || ![string is boolean -strict [dict get $record enabled]]} {error {Invalid private Preview activation state}}
        if {[dict remove $record enabled] ne [_datasetPreviewActivationIdentity $id]} {error {Preview activation descriptor or version changed}}
        dict set previews $id enabled [expr {[dict get $record enabled] ? 1 : 0}]
    }
    set dependencies [dict get $snapshot dependencies]
    if {[catch {dict size $dependencies}] || [dict size $dependencies]>1024 || $dependencies ne [_datasetPreviewActivationDependencies $previews]} {error {Preview activation dependency identity changed}}
    return $previews
}
proc ::GX::_datasetPreviewActivationApply {snapshot} {
    # Validate the complete projection before mutating any child-local Module.
    set previews [_datasetPreviewActivationValidate $snapshot]
    dict for {id record} $previews {if {![dict get $record enabled]} {moduleSetEnabled $id 0}}
    dict for {id record} $previews {if {[dict get $record enabled]} {moduleSetEnabled $id 1}}
    dict for {id record} $previews {if {[moduleIsEnabled $id] != [dict get $record enabled]} {error {Preview activation projection changed during dependency resolution}}}
    _modulePreviewValidateSelection [join [selectedModuleIds] {;}]
}

proc ::GX::_datasetPreviewProviderContext {datasetId representation} {
    set session [sessionInspectionCurrentSession]
    set token [interactiveDocumentSessionToken]
    set metadata [datasetMetadataRead $session $datasetId]
    set contributors [datasetMetadataContributors $session $datasetId]
    set core [_datasetPreviewCoreSpecialization $datasetId]
    set summary {}
    foreach key {key kind current row_count displayed_points description axes dimensions selections ordering} {
        if {[dict exists $representation $key]} {dict set summary $key [dict get $representation $key]}
    }
    # Curve buffers remain with the existing renderer. Modules receive the
    # already-prepared source/Quality summaries, never a duplicate model/store.
    if {[datasetPublicationV2DictDefault $core component_id {}] eq {curve_digitizer} && [dict exists $representation digitizer] && [dict get $representation digitizer] ne {}} {
        set digitizer [dict get $representation digitizer];set selected {}
        foreach key {dataset_id quality quality_rows quality_summary host_source_verification original_image main_image images image_message raster_available} {
            if {[dict exists $digitizer $key]} {dict set selected $key [dict get $digitizer $key]}
        }
        dict set summary digitizer $selected
    }
    set rows [datasetField $datasetId row_count 0]
    set availability [dict create source 0 native_model [dict exists $representation native_model] table [expr {[string is entier -strict $rows] && $rows>0}] media_artifact 0 source_image 0 quality 0 curve_controls [dict exists $summary digitizer]]
    if {![catch {sessionInspectionDatasetLocation $datasetId $session}]} {dict set availability source 1}
    if {[dict exists $representation media_artifact path] && [file isfile [dict get $representation media_artifact path]]} {
        dict set availability media_artifact 1
        dict set summary media_artifact [dict get $representation media_artifact]
    }
    if {[dict exists $summary digitizer images] && [dict exists $summary digitizer host_source_verification status] && [dict get $summary digitizer host_source_verification status] eq {verified}} {
        dict for {image record} [dict get $summary digitizer images] {
            if {[dict exists $record path] && [file isfile [dict get $record path]]} {dict set availability source_image 1}
        }
    }
    if {[dict exists $summary digitizer quality_summary] && [dict exists $summary digitizer quality report_json] && [dict get $summary digitizer quality report_json] ne {}} {dict set availability quality 1}
    return [dict create schema gxtxt.preview_context.v1 dataset_id $datasetId session $session token $token canonical_identity [_datasetPreviewProviderCanonicalIdentity $datasetId] \
        contract [datasetField $datasetId contract [datasetField $datasetId kind]] \
        producer_module [datasetField $datasetId producer_module {}] source_module [datasetField $datasetId source_module {}] \
        producer_version [datasetField $datasetId producer_version {}] provenance [datasetField $datasetId provenance {}] source_dataset_ids [splitList [datasetField $datasetId source_dataset_ids {}]] \
        core_specialized [expr {$core ne {}}] core_id [datasetPublicationV2DictDefault $core component_id {}] \
        metadata $metadata contributors $contributors variables [datasetVariableSchemaV3 $datasetId] \
        representation $summary availability $availability]
}

proc ::GX::_datasetPreviewProviderContextCurrent {id context identity} {
    expr {![catch {interactiveDocumentSessionToken} token] && $token eq [dict get $context token] && ![catch {datasetViewerScientificIdentity $id} actual] && $actual eq $identity && ![catch {_datasetPreviewProviderCanonicalIdentity $id} canonical] && $canonical eq [dict get $context canonical_identity]}
}

# Extensions contribute data descriptors to the one CORE Preview notebook.
# Their contract is read-only; existing trusted Module and Dataset owners remain
# responsible for package code and scientific access. No new loader/registry.
proc ::GX::datasetPreviewProviderTabs {datasetId {representation {}}} {
    set tabs {};set diagnostics {};set successful {}
    if {$datasetId ni [datasetRegistryIds]} {_datasetPreviewProviderError INVALID_ARGUMENT {Unknown canonical Dataset}}
    if {[dict exists $representation source] && ([catch {datasetPreviewCacheSource $datasetId} current] || $current ne [dict get $representation source])} {
        return [dict create tabs {} diagnostics [list {Previous Preview source changed; render the current Dataset again}] selection [datasetPreviewSelection $datasetId {}]]
    }
    set candidates [datasetPreviewProviders $datasetId]
    if {![llength $candidates]} {return [dict create tabs {} diagnostics {} selection [datasetPreviewSelection $datasetId]]}
    if {[catch {
        set context [_datasetPreviewProviderContext $datasetId $representation]
        set identity [datasetViewerScientificIdentity $datasetId]
    } message]} {return [dict create tabs {} diagnostics [list "Dataset Preview: $message"]]}
    set previewDir {}
    if {[dict exists $representation key] && [regexp {^[a-f0-9]{64}$} [dict get $representation key]]} {
        set previewDir [datasetPreviewCachePath $::GX::currentSession [dict get $representation key]]
    }
    foreach info $candidates {
        set id [dict get $info component_id]
        if {![dict get $info enabled]} continue
        if {[dict get $context core_specialized] && [dict get $info profile] eq {native}} continue
        set preparedNative 0
        if {[dict get $info profile] eq {native} && [dict exists $representation native_provider component_id] && [dict get $representation native_provider component_id] eq $id && [llength [info commands ::GX::datasetPreviewNativeReceiptCurrent]]} {
            catch {
                if {[dict get $representation native_provider receipt source_receipt cache_key] eq [dict get $representation key]} {
                    set preparedNative [datasetPreviewNativeReceiptCurrent $datasetId [dict get $representation native_provider]]
                }
            }
        }
        if {$preparedNative} {lappend successful $id}
        if {![dict get $info available] && !$preparedNative} {
            lappend diagnostics "$id: [dict get $info reason]"
            continue
        }
        if {[catch {
            set declaration [_datasetPreviewProviderDescriptor $id]
            modulePublicApiActivate $id PREVIEW_COMPONENT_GUI_API_v1
            set namespace [descriptorValue [moduleField $id dict {}] public_api.PREVIEW_COMPONENT_GUI_API_v1 namespace {}]
            set callback ${namespace}::preview
            if {![llength [info commands $callback]]} {
                if {[dict get $info profile] eq {native}} continue
                error {Preview public API has no preview(context) operation}
            }
            set response [_datasetPrivateWithModule $id [list $callback $context]]
            if {[string bytelength $response]>1048576 || [catch {dict size $response}]} {error {Preview response must be a dictionary up to1MiB}}
            if {[dict keys $response] ne {tabs} || [llength [dict get $response tabs]]>32} {error {Preview response requires at most32 tab descriptors}}
            set contribution {};set ids {}
            foreach tab [dict get $response tabs] {
                if {[dict exists $tab kind] && [dict get $tab kind] eq {gui} && [dict get $declaration gui_api_version]!=1} {error {GUI panes require preview_provider.gui_api_version=1}}
                if {[dict get $context core_specialized] && [datasetPublicationV2DictDefault $tab role [dict get $info view_role]] eq {primary}} continue
                if {[dict exists $tab kind] && [dict get $tab kind] eq {native} && (![dict get $context availability native_model] || [dict get $context core_specialized] || ([dict get $info profile] eq {native} && !$preparedNative))} continue
                if {[dict exists $tab kind] && [dict get $tab kind] eq {table}} {
                    if {![dict exists $tab dataset_id]} {dict set tab dataset_id $datasetId}
                    set target [dict get $tab dataset_id]
                    set rows [datasetField $target row_count 0]
                    if {$target ni [datasetRegistryIds] || ![string is entier -strict $rows] || $rows==0 || [catch {sessionInspectionDatasetLocation $target}]} continue
                }
                set normalized [previewDescriptorTabNormalize $tab $previewDir]
                if {$normalized eq {}} continue
                set tabId [dict get $normalized id]
                if {$tabId in $ids} {error {Preview component returned duplicate tab IDs}}
                lappend ids $tabId
                dict set normalized component_id $id
                dict set normalized role [expr {![dict get $context core_specialized] && [dict get $info view_role] eq {primary} && [dict get $info match_strength] eq {specialized} && [datasetPublicationV2DictDefault $tab role primary] eq {primary} ? {primary} : {complementary}}]
                lappend contribution $normalized
            }
            if {![_datasetPreviewProviderContextCurrent $datasetId $context $identity]} {error {Dataset or Session changed during Preview contribution}}
            if {![moduleIsEnabled $id]} {error {Preview component was disabled during its callback}}
            if {[_datasetPreviewProviderDescriptor $id] ne $declaration || [_datasetPreviewProviderMatch $datasetId $declaration] eq {} || [dict get [datasetPreviewProviderInfo $id] pending_version] ne {}} {error {Preview component compatibility changed during its callback}}
            lappend tabs {*}$contribution
            if {[llength $contribution]} {lappend successful $id}
        } message]} {
            lappend diagnostics "$id: [string range $message 0 511]"
        }
        if {![_datasetPreviewProviderContextCurrent $datasetId $context $identity]} {
            return [dict create tabs {} diagnostics [concat $diagnostics [list "$id: Dataset or Session changed; refresh Preview"]]]
        }
    }
    return [dict create tabs $tabs diagnostics $diagnostics selection [datasetPreviewSelection $datasetId $successful]]
}
