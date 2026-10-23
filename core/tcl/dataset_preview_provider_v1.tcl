# SPDX-License-Identifier: GPL-3.0-or-later
# Conditional TASK210 development only. MAIN has not wired this candidate into
# startup or adopted its public routes/descriptor. Module/Package/GUI owners
# retain activation, byte admission, lifecycle and Builder authority.
namespace eval ::GX::PreviewProvider {
    variable descriptorKeys {api_version native_abi native_library native_sha256 native_platform native_layout_id native_build_id dataset_contracts capabilities gui_design gui_design_sha256 gui_contract gui_public_api gui_handler_factory}
    variable capabilities {grouped_curves bounded_array_plane raster_overlay}
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
    set prefix preview_provider.
    foreach key [dict keys $data ${prefix}*] {
        if {[string range $key [string length $prefix] end] ni $::GX::PreviewProvider::descriptorKeys} {error {Unknown Preview provider descriptor field}}
    }
    set out [dict create component_id $id]
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
    set gui [dict get $out gui_public_api]
    if {$gui ne {PREVIEW_COMPONENT_GUI_API_v1} || [dict get $out gui_handler_factory] ne {handlers} || $gui ni [splitList [descriptorValue $data public_apis ids {}]]} {error {Preview controlled GUI factory is not declared}}
    set section public_api.$gui
    if {[descriptorValue $data $section api_version {}] ne {1}} {error {Unsupported Preview GUI factory contract}}
    _datasetPreviewProviderRelative [descriptorValue $data $section entrypoint {}]
    if {![regexp {^::GX::[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)*$} [descriptorValue $data $section namespace {}]]} {error {Invalid Preview GUI factory namespace}}
    return $out
}
proc ::GX::_datasetPreviewProviderHostInfo {} {
    # Compiled CORE metadata only; this operation may not dlopen a provider.
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
    set out [dict create component_id $id name [moduleField $id name $id] installed_version [moduleField $id version {}] active_version {} pending_version {} enabled 0 descriptor_valid 0 native_abi {} native_platform {} native_layout_id {} native_build_id {} dataset_contracts {} capabilities {} verified_capabilities {} gui_design_sha256 {} compatibility_status unknown load_status not_checked available 0 admission_fingerprint {} reason {Preview descriptor is invalid}]
    # Reject forbidden Configuration aliases before either activation or package
    # state can interpret an unrelated cfg value as a module boolean.
    if {[catch {set declaration [_datasetPreviewProviderDescriptor $id]} message]} {dict set out reason [string range $message 0 255];return $out}
    dict set out enabled [moduleIsEnabled $id]
    set stateInvalid [catch {set state [_datasetPreviewProviderPackageState $id]}]
    if {!$stateInvalid && $state ne {}} {
        foreach key {active_version pending_version} {dict set out $key [dict get $state $key]}
        if {[dict get $state pending_version] ne {}} {dict set out load_status restart_required}
    }
    dict set out descriptor_valid 1
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
proc ::GX::datasetPreviewProviders {{datasetId {}}} {
    set actual {}
    if {$datasetId ne {}} {
        if {$datasetId ni [datasetRegistryIds]} {_datasetPreviewProviderError INVALID_ARGUMENT {Unknown canonical Dataset}}
        set actual [datasetField $datasetId contract [datasetField $datasetId kind]]
    }
    set out {}
    foreach id $::GX::moduleOrder {
        if {[moduleField $id kind {}] ne {preview}} continue
        set item [datasetPreviewProviderInfo $id]
        if {$datasetId ne {} && (![dict get $item descriptor_valid] || ![contractSatisfiesAny $actual [dict get $item dataset_contracts]])} continue
        lappend out $item
    }
    return $out
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
proc ::GX::datasetPreviewProviderSelect {datasetId {capability standard}} {
    if {$capability ni [linsert $::GX::PreviewProvider::capabilities 0 standard]} {_datasetPreviewProviderError INVALID_ARGUMENT {Unknown Preview capability}}
    if {$datasetId ni [datasetRegistryIds]} {_datasetPreviewProviderError INVALID_ARGUMENT {Unknown canonical Dataset}}
    set requested $capability
    if {$capability eq {standard}} {set capability [_datasetPreviewProviderDefaultCapability $datasetId]}
    set result [dict create status unavailable component_id {} capability $requested admission_required 0 code NO_COMPATIBLE_PROVIDER reason {No compatible enabled native scientific Preview component}]
    if {$capability eq {}} {return $result}
    foreach item [datasetPreviewProviders $datasetId] {
        if {![dict get $item enabled] || [dict get $item compatibility_status] eq {incompatible} || [dict get $item pending_version] ne {} || $capability ni [dict get $item capabilities]} continue
        return [dict create status candidate component_id [dict get $item component_id] capability $capability admission_required [expr {![dict get $item available] || $capability ni [dict get $item verified_capabilities]}] code {} reason {}]
    }
    return $result
}
