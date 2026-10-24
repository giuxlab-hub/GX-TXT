# SPDX-License-Identifier: GPL-3.0-or-later
# Optional native backend of the existing Preview/Curve Source owners. Ordinary
# Module catalog/lifecycle remain authoritative; no installed provider registry.
proc ::GX::datasetPreviewNativeEnsure {} {
    if {[llength [info commands ::gx::native2d::_preview_provider]]} {return 1}
    if {$::tcl_platform(os) ne {Linux} || $::tcl_platform(machine) ni {x86_64 amd64}} {return 0}
    set library [file join $::GX::scriptDir core native2d bin gxpreviewprovider.so]
    if {![file isfile $library]} {return 0}
    native2DEnsure
    load $library Gxpreviewprovider
    return 1
}
proc ::GX::_datasetPreviewNativeWorker {} {
    expr {[info exists ::env(GXTXT_PREVIEW_WORKER)] && $::env(GXTXT_PREVIEW_WORKER) eq {1} &&
        [info exists ::argv0] && $::argv0 eq {__gxtxt_preview_worker__} &&
        [llength [info commands ::GXPreviewWorker::originalPuts]] &&
        ![llength [info commands ::tk]]}
}
proc ::GX::_datasetPreviewNativeAssets {id} {
    set declaration [_datasetPreviewProviderDescriptor $id]
    set descriptor [moduleField $id descriptor {}]
    if {[parseIni $descriptor] ne [moduleField $id dict {}]} {error {Preview descriptor changed since Module discovery}}
    set root [file normalize [file dirname $descriptor]]
    foreach key {native_library gui_design} digest {native_sha256 gui_design_sha256} {
        set current $root
        foreach component [split [dict get $declaration $key] /] {
            set current [file join $current $component]
            file lstat $current entry
            if {$entry(type) eq {link}} {error {Preview provider assets must not be symlinks}}
        }
        if {![file isfile $current] || ![file readable $current] || [sha256File $current] ne [dict get $declaration $digest]} {error "Preview provider $key bytes differ from its installed declaration"}
        dict set declaration ${key}_path $current
    }
    viewerGuiDesignRead [dict get $declaration gui_design_path]
    set generation [scan [string range [sha256File $descriptor] 0 14] %x]
    dict set declaration generation $generation
    dict set declaration version [moduleField $id version {}]
    return $declaration
}
proc ::GX::datasetPreviewNativeIdentity {datasetId} {
    set identity {}
    set library [file join $::GX::scriptDir core native2d bin gxpreviewprovider.so]
    if {[file isfile $library]} {lappend identity bridge [sha256File $library]}
    set actual [datasetField $datasetId contract [datasetField $datasetId kind]]
    foreach id [lsort $::GX::moduleOrder] {
        if {[moduleField $id kind {}] ne {preview} || ![moduleIsEnabled $id]} continue
        if {[catch {set declaration [_datasetPreviewProviderDescriptor $id]}] ||
            [dict exists $declaration profile] && [dict get $declaration profile] eq {presentation}} continue
        if {![contractSatisfiesAny $actual [dict get $declaration dataset_contracts]]} continue
        set bytes invalid
        catch {set bytes [_datasetPreviewNativeAssets $id]}
        lappend identity $id $declaration $bytes [dict exists $::GX::pluginRuntimePending $id]
    }
    return $identity
}
proc ::GX::_pluginPreviewProviderState {id} {
    set version [moduleField $id version {}]
    set active [datasetPublicationV2DictDefault $::GX::pluginRuntimeLoaded $id {}]
    set pending [datasetPublicationV2DictDefault $::GX::pluginRuntimePending $id {}]
    if {$pending ne {}} {set pending [dict get $pending version]}
    set generation 0;catch {set generation [dict get [_datasetPreviewNativeAssets $id] generation]}
    return [dict create schema gxtxt.preview_package_state.v1 component_id $id installed_version $version enabled [moduleIsEnabled $id] generation $generation active_version $active pending_version $pending admission {}]
}
proc ::GX::_datasetPreviewNativeBinding {id} {
    pluginRuntimeGuardNewLoad $id
    if {![moduleIsEnabled $id]} {error {Preview component is disabled}}
    set declaration [_datasetPreviewNativeAssets $id]
    if {![datasetPreviewNativeEnsure]} {error {Native Preview provider adapter is unavailable}}
    set host [::gx::native2d::_preview_provider info]
    foreach key {native_abi native_platform native_layout_id} {
        if {[dict get $declaration $key] ne [dict get $host $key]} {error {Native Preview provider ABI/platform/layout mismatch}}
    }
    set binding [dict create component_id $id version [dict get $declaration version] generation [dict get $declaration generation] host_build_id [dict get $host native_build_id]]
    foreach key {native_abi native_platform native_layout_id native_build_id native_sha256 gui_design_sha256} {dict set binding $key [dict get $declaration $key]}
    return $binding
}
proc ::GX::_pluginPreviewProviderAdmit {binding} {
    if {![_datasetPreviewNativeWorker]} {error {Native Preview admission requires the fixed managed worker}}
    set id [dict get $binding component_id]
    if {[_datasetPreviewNativeBinding $id] ne [dict remove $binding requested_capability]} {error {Preview package changed before admission}}
    set declaration [_datasetPreviewNativeAssets $id]
    set capabilities [dict get $binding requested_capability]
    if {![llength $capabilities] || [llength [lsort -unique $capabilities]]!=[llength $capabilities]} {error {Invalid Preview invocation capabilities}}
    foreach capability $capabilities {
        if {$capability ni {grouped_curves bounded_array_plane raster_overlay} || $capability ni [dict get $declaration capabilities]} {error {Undeclared Preview invocation capability}}
    }
    if {{raster_overlay} in $capabilities && {grouped_curves} ni $capabilities} {error {Raster overlay requires the grouped-curve owner plan}}
    set fingerprint [datasetStorageSha256Text $::GX::currentSession [list $binding [dict get $declaration capabilities]]]
    set lease [dict merge $binding [dict create schema gxtxt.preview_native_lease.v1 native_path [dict get $declaration native_library_path] lease_id "preview-[pid]-[clock clicks]" fingerprint $fingerprint verified_capabilities $capabilities]]
    # Reuse the existing transient lifecycle receipt rather than another package
    # registry. Active native leases conservatively retain normal restart rules.
    if {![dict exists $::GX::pluginRuntimeReceipts $id]} {dict set ::GX::pluginRuntimeReceipts $id [pluginRuntimeInfo $id]}
    dict set ::GX::pluginRuntimeReceipts $id preview_leases [dict get $lease lease_id] $lease
    return $lease
}
proc ::GX::_pluginPreviewProviderNoteLoaded {lease} {
    set id [dict get $lease component_id];set token [dict get $lease lease_id]
    if {![dict exists $::GX::pluginRuntimeReceipts $id preview_leases $token] ||
        [dict get $::GX::pluginRuntimeReceipts $id preview_leases $token] ne $lease} {error {Unknown Preview native lease}}
    pluginRuntimeNoteLoaded $id
}
proc ::GX::_pluginPreviewProviderRetire {lease reason} {
    set id [dict get $lease component_id];set token [dict get $lease lease_id]
    if {![dict exists $::GX::pluginRuntimeReceipts $id preview_leases $token] ||
        [dict get $::GX::pluginRuntimeReceipts $id preview_leases $token] ne $lease} {error {Unknown Preview retirement lease}}
    dict unset ::GX::pluginRuntimeReceipts $id preview_leases $token
}
proc ::GX::_datasetPreviewNativeSource {id key} {
    return [dict create session $::GX::currentSession session_origin [sessionOriginRead $::GX::currentSession] session_token [interactiveDocumentSessionToken] source [_curveSourceIdentity $::GX::currentSession $id] coordinate_context [datasetCoordinateRead $::GX::currentSession $id] cache_key $key]
}
proc ::GX::_datasetPreviewNativeCandidate {id capability {preferred {}}} {
    set selection [datasetPreviewProviderSelect $id $capability $preferred]
    if {[dict get $selection status] eq {candidate}} {return [dict get $selection component_id]}
    return {}
}
proc ::GX::datasetPreviewNativeOverlayPlan {id} {
    if {![_datasetPreviewNativeWorker]} {return {}}
    if {[catch {
        set manifest [datasetPreviewCurveManifest $id]
        if {$manifest eq {} || ![dict get $manifest raster_points_available]} {return {}}
        set candidate [_datasetPreviewNativeCandidate $id {grouped_curves raster_overlay}]
        if {$candidate eq {}} {return {}}
        _datasetPreviewNativeBinding $candidate
        set columns [dict get $manifest columns]
        foreach role {curve_key curve_name point_order raster_x raster_y} {dict get $columns $role}
    }]} {return {}}
    return [dict create candidate $candidate columns $columns raster 1]
}
proc ::GX::datasetPreviewNativeBatch {operation args} {
    if {$operation eq {begin}} {
        lassign $args config id options
        set failure {}
        if {[_datasetPreviewNativeWorker]} {
            if {[catch {set candidate [_datasetPreviewNativeCandidate $id [expr {[dict exists $options overlay] ? {grouped_curves raster_overlay} : {grouped_curves}}] [datasetPublicationV2DictDefault $options primary_component {}]]} failure]} {set candidate {}}
            if {$candidate ne {}} {
                set token {}
                if {![catch {
                    set binding [_datasetPreviewNativeBinding $candidate]
                    dict set binding requested_capability [expr {[dict exists $options overlay] ? {grouped_curves raster_overlay} : {grouped_curves}}]
                    set key [datasetPublicationV2DictDefault $options cache_key {}]
                    set source [_datasetPreviewNativeSource $id $key]
                    set limits [dict create max_native_bytes 0 max_input_rows 9223372036854775807 max_text_bytes 67108864 max_chunk_rows 4096 max_selected_rows 2000000 max_retained_row_capacity 4000000]
                    set context [dict create schema gxtxt.preview_native_invocation.v1 mode grouped_curves dataset_id $id source_receipt $source provider_binding $binding contracts [list [datasetField $id contract [datasetField $id kind]]] dataset_kind [datasetField $id kind] limits $limits batch_config $config coordinate_context [dict get $source coordinate_context]]
                    if {[dict exists $options overlay]} {
                        set overlay [dict get $options overlay]
                        dict set context overlay [dict create enabled 1 columns [dict get $overlay columns] raster 1 filters [dict get $config filters]]
                        dict set context limits max_unique_raster_points 65536
                    }
                    set token [::gx::native2d::_preview_provider open $context]
                    ::gx::native2d::_preview_provider admit $token $binding
                } failure]} {return [dict create backend native token $token id $id binding $binding source $source overlay [datasetPublicationV2DictDefault $options overlay {}] filters [dict get $config filters]]}
                if {$token ne {}} {::gx::native2d::_preview_provider close $token}
            }
        }
        return [dict create backend core token [::gx::native2d::_preview_batch begin $config] diagnostic $failure]
    }
    lassign $args handle columns
    set token [dict get $handle token]
    if {[dict get $handle backend] eq {core}} {
        switch -- $operation {
            push {return [::gx::native2d::_preview_batch push $token $columns]}
            finish {return [::gx::native2d::_preview_batch finish $token]}
            finish_overlay {return [dict create series [::gx::native2d::_preview_batch finish $token] overlay {}]}
            inspect {return [dict merge [::gx::native2d::_preview_batch inspect $token] [dict create backend core fallback_reason [dict get $handle diagnostic]]]}
            destroy {return [::gx::native2d::_preview_batch destroy $token]}
        }
    } else {
        switch -- $operation {
            push {return [::gx::native2d::_preview_provider push $token $columns]}
            finish - finish_overlay {
                ::gx::native2d::_preview_provider seal $token
                set result [::gx::native2d::_preview_provider result $token]
                if {[_datasetPreviewNativeSource [dict get $handle id] [dict get $handle source cache_key]] ne [dict get $handle source] ||
                    [_datasetPreviewNativeBinding [dict get $handle binding component_id]] ne [dict remove [dict get $handle binding] requested_capability]} {error {Preview source, Session, coordinates or provider changed before result admission}}
                if {$operation eq {finish_overlay}} {
                    set receipt [datasetPreviewNativeBatch inspect $handle]
                    set overlay [dict create dataset_id [dict get $handle id] columns [dict get $handle overlay columns] raster 1 filters [dict get $handle filters] result [dict get $result overlay] native_provider $receipt]
                    return [dict create series [dict get $result native_series] overlay $overlay]
                }
                return [dict get $result native_series]
            }
            inspect {return [dict create status prepared backend native component_id [dict get $handle binding component_id] binding [dict get $handle binding] receipt [::gx::native2d::_preview_provider inspect $token]]}
            destroy {return [::gx::native2d::_preview_provider close $token]}
        }
    }
    error {Unknown Preview native batch operation}
}
proc ::GX::datasetPreviewNativeReceiptCurrent {id receipt} {
    if {[catch {
        if {[dict get $receipt status] ne {prepared}} {error stale}
        set binding [dict get $receipt binding]
        if {[dict remove $binding requested_capability] ne [_datasetPreviewNativeBinding [dict get $receipt component_id]]} {error stale}
        set observed [dict get $receipt receipt]
        if {![dict get $observed admitted] || ![dict get $observed sealed] || [dict get $observed failed]} {error stale}
        set source [dict get $observed source_receipt]
        if {[dict remove $source session_token] ne [dict remove [_datasetPreviewNativeSource $id [dict get $source cache_key]] session_token]} {error stale}
    }]} {return 0}
    return 1
}
proc ::GX::datasetPreviewNativePlane {id variable starts counts column nx ny output {preferred {}}} {
    if {![_datasetPreviewNativeWorker]} {return [::gx::native2d::_preview_plane $column $nx $ny]}
    if {[catch {set candidate [_datasetPreviewNativeCandidate $id bounded_array_plane $preferred]}]} {set candidate {}}
    if {$candidate eq {}} {return [::gx::native2d::_preview_plane $column $nx $ny]}
    set token {};set result {};set nativeReceipt {}
    try {
        if {[catch {
            set binding [_datasetPreviewNativeBinding $candidate]
            dict set binding requested_capability bounded_array_plane
            set source [_datasetPreviewNativeSource $id [file tail [file dirname $output]]]
            set limits [dict create max_native_bytes 0 max_input_rows 16384 max_text_bytes 67108864 max_rgb_bytes 806400]
            set plan [dict create variable_id [dict get $variable variable_id] starts $starts counts $counts storage_order last_dimension_fastest max_output_width 640 max_output_height 420]
            set context [dict create schema gxtxt.preview_native_invocation.v1 mode bounded_array_plane dataset_id $id source_receipt $source provider_binding $binding contracts [list [datasetField $id contract [datasetField $id kind]]] dataset_kind [datasetField $id kind] limits $limits plane $plan]
            set token [::gx::native2d::_preview_provider open $context]
            ::gx::native2d::_preview_provider admit $token $binding
            ::gx::native2d::_preview_provider push $token [dict create [dict get $variable variable_id] $column]
            ::gx::native2d::_preview_provider seal $token
            set result [::gx::native2d::_preview_provider result $token]
            if {[_datasetPreviewNativeSource $id [dict get $source cache_key]] ne $source || [_datasetPreviewNativeBinding $candidate] ne [dict remove $binding requested_capability]} {error {Preview plane source, Session, coordinates or provider changed}}
            set nativeReceipt [dict create status prepared backend native component_id $candidate binding $binding receipt [::gx::native2d::_preview_provider inspect $token]]
        } message]} {
            # Existing plane owner remains the generic fallback; no new decoder,
            # interpolation, numeric comparison or renderer is introduced.
            set result {}
        }
    } finally {if {$token ne {}} {::gx::native2d::_preview_provider close $token}}
    if {$result eq {}} {return [::gx::native2d::_preview_plane $column $nx $ny]}
    return [dict merge [dict get $result plane] [dict create native_provider $nativeReceipt]]
}
