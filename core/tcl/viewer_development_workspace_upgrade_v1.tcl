# SPDX-License-Identifier: GPL-3.0-or-later
# Explicit reviewed copy in existing Development/Workspace owners. Never relax
# ordinary exact-snapshot opening or evaluate authored migration code.
namespace eval ::GX::ViewerDevelopment {variable workspaceReviews {};variable reviewSerial 0;variable reviewResponses}
proc ::GX::_viewerDevelopmentWorkspaceStamp {workspace} {
    set stamp {};foreach key {id generation revision sha256} {dict set stamp $key [dict get $workspace $key]};return $stamp
}
proc ::GX::_viewerDevelopmentWorkspaceSources {payload {current 1}} {
    set sources {}
    set declared {};foreach component [dict get $payload design components] {dict set declared [dict get $component id] $component}
    if {[dict exists $payload bindings]} {
        dict for {component binding} [dict get $payload bindings] {
            if {[dict get $binding kind] ne {diagram}} continue
            set id [dict get $binding document_id]
            set saved [dict get $binding document_receipt]
            if {$current} {set actual [native2DGeometryDiagramRead $id]} else {set actual [dict replace $saved payload [dict get $binding payload]]}
            if {[dict get $saved id] ne $id || [dict get $actual module_id] ne [dict get $payload design module_id] || [dict get $actual provider_id] ne [dict get $payload design provider_id] || ![dict exists $declared $component] || [dict get $declared $component type] ne {native2d} || [dict get $actual payload catalog] ne [dict get $declared $component properties diagram_catalog] || [dict get $binding payload] ne [dict get $actual payload]} {error {Workspace diagram identity, catalog, owner or payload differs from its canonical source}}
            foreach key {generation revision sha256} {if {[dict get $saved $key] ne [dict get $actual $key]} {error {Workspace scientific source is stale; review its matching source before upgrading}}}
            dict set sources $id [_viewerDevelopmentWorkspaceStamp $actual]
        }
    }
    foreach field {scientific_jobs scientific_campaigns} {
        if {![dict exists $payload domain_state $field]} continue
        dict for {form record} [dict get $payload domain_state $field] {
            if {![dict exists $declared $form] || [dict get $declared $form type] ne {section} || ![dict exists $declared $form properties scientific_provider]} {error {Scientific state names an undeclared Scientific form}}
            set records [list $record]
            if {$field eq {scientific_campaigns}} {dict for {case job} [dict get $record jobs] {lappend records $job}}
            set index -1
            foreach item $records {
                incr index
                if {($field ne {scientific_campaigns} || $index>0) && [dict get $item provider_id] ne [dict get $declared $form properties scientific_provider]} {error {Scientific Job provider differs from its declared form}}
                set guard [dict get $item source_guard];set id [dict get $guard document_id]
                if {![dict exists $sources $id]} {error {Scientific provenance is not bound to its original source}}
                if {![string is entier -strict [dict get $guard revision]] || [dict get $guard revision]<1 || ![regexp {^[0-9a-f]{64}$} [dict get $guard sha256]]} {error {Malformed scientific source provenance}}
                set keys [expr {$current?{generation revision sha256}:{generation}}]
                foreach key $keys {if {[dict get $guard $key] ne [dict get $sources $id $key]} {error {Scientific campaign/source provenance differs}}}
            }
        }
    }
    return $sources
}
proc ::GX::_viewerDevelopmentWorkspaceStateUpgrade {state prior report design} {
    viewerGuiDesignStateValidate $state
    # A previously undeclared cache must never become visible scientific text
    # just because an explicit upgrade adds its first Netlist declaration.
    foreach form [datasetPublicationV2DictDefault $report new_netlist_forms {}] {
        if {[dict exists $state domain_state scientific_netlists $form]} {error {Retained History contains a netlist cache absent from its saved declaration}}
    }
    set declared {};foreach component [dict get $design components] {dict set declared [dict get $component id] $component}
    if {[dict exists $state domain_state scientific_netlists]} {
        foreach form [dict keys [dict get $state domain_state scientific_netlists]] {
            if {![dict exists $declared $form] || [dict get $declared $form type] ne {section} || ![dict exists $declared $form properties scientific_netlist]} {error {Retained netlist cache names an undeclared saved Scientific inspection form}}
        }
    }
    foreach field {values choices visibility bindings} {
        if {![dict exists $state $field]} continue
        foreach id [dict keys [dict get $state $field]] {if {![dict exists $declared $id] || $id in [dict get $report appended_components]} {error {Retained state names an undeclared or newly appended component}}}
    }
    _viewerDevelopmentWorkspaceSources [dict replace $state design $design] 0
    if {[dict exists $state bindings]} {
        dict for {id binding} [dict get $state bindings] {
            switch -- [dict get $binding kind] {
                diagram {
                    if {[dict get $declared $id type] ne {native2d} || [dict get $binding document_id] ne [dict get $binding document_receipt id] || [dict get $binding payload catalog] ne [dict get $declared $id properties diagram_catalog]} {error {Retained diagram binding does not match its declared component}}
                    native2DGeometryDiagramValidate [dict get $binding payload]
                }
                plot {
                    if {[dict get $declared $id type] ne {plot}} {error {Retained Plot binding does not match its declared component}}
                    modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4;::GX::PlotDatasetAPIv4::validateSpec [dict get $binding spec]
                }
                default {error {Retained state uses a binding outside this reviewed electrical/Plot upgrade}}
            }
        }
    }
    if {[dict exists $state domain_state restricted_cpp]} {
        set cpp [dict get $state domain_state restricted_cpp]
        if {[dict get $cpp snapshot] ne [dict get $prior snapshot] || [dict get $cpp callback_contract] ne [dict get $report prior_callback_contract]} {error {History contains a different restricted source contract}}
        viewerDevelopmentStateJson [dict get $cpp state]
        dict set cpp snapshot [dict get $report source_snapshot]
        dict set cpp callback_contract [dict get $report new_callback_contract]
        dict set state domain_state restricted_cpp $cpp
    }
    dict for {id value} [dict get $report new_defaults] {
        if {[dict exists $state values $id]} {error {A new control collides with retained state}}
        dict set state values $id $value
    }
    dict for {id value} [datasetPublicationV2DictDefault $report new_visibility_defaults {}] {
        if {![dict exists $state visibility $id]} {dict set state visibility $id $value}
    }
    return $state
}
proc ::GX::_viewerDevelopmentWorkspacePayloadUpgrade {payload report design} {
    set prior [dict get $payload domain_state restricted_cpp]
    set result [_viewerDevelopmentWorkspaceStateUpgrade $payload $prior $report $design]
    dict set result design $design
    if {[dict exists $payload history]} {
        set old [dict get $payload history];set owner [dict get $design module_id]
        scientificRecipeHostRegister $owner [dict create capture ::GX::viewerGuiDesignCapture validate ::GX::viewerGuiDesignHistoryValidate replay ::GX::scientificHistoryState]
        scientificHistoryValidate $owner $old
        set before [dict get $old base]
        set converted [_viewerDevelopmentWorkspaceStateUpgrade $before $prior $report $design]
        set history [dict replace $old base $converted steps {}]
        foreach step [dict get $old steps] {
            set next [scientificRecipeApplyPatch $before [dict get $step patch]]
            set upgraded [_viewerDevelopmentWorkspaceStateUpgrade $next $prior $report $design]
            set count [llength [dict get $history steps]]
            set semantic [dict remove $step patch]
            set history [scientificRecipeAppend $history $converted $upgraded $semantic]
            # Preserve even a legitimate empty retained step and its metadata.
            if {[llength [dict get $history steps]]==$count} {dict lappend history steps [dict replace $step patch {}]}
            set before $next;set converted $upgraded
        }
        if {[llength [dict get $history steps]]!=[llength [dict get $old steps]]} {error {History step count changed}}
        scientificHistoryValidate $owner $history
        dict set result history $history
    }
    return $result
}
proc ::GX::viewerDevelopmentWorkspaceReview {project id callback} {
    if {![interactiveDocumentIdValid $id]} {error {Use a canonical current-Session Workspace identity}}
    set project [file normalize $project];set snapshot [_viewerDevelopmentSnapshot $project]
    set workspace [sessionWorkspaceGet $id];set payload [dict get $workspace payload]
    if {![dict exists [interactiveDocumentRead $id] payload workspace_metadata]} {error {Promote this legacy document explicitly to a named canonical Workspace before reviewing an upgrade}}
    set design [viewerGuiDesignRead [file join $project design.gxtxt-viewer]]
    if {[dict get $workspace schema] ne {gxtxt.viewer_interface_state.v1} || [dict get $workspace module_id] ne [dict get $design module_id] || [dict get $payload design provider_id] ne [dict get $design provider_id]} {error {Workspace belongs to another module, provider or schema}}
    set cpp [dict get $payload domain_state restricted_cpp]
    viewerDevelopmentStateJson [dict get $cpp state]
    set sources [_viewerDevelopmentWorkspaceSources $payload]
    if {![llength [info commands ::GX::ScientificTransportv1::_escape]]} {modulePublicApiActivate math.numeric NUMERIC_API_v1}
    set parts {};foreach {key value} [list saved_design [dict get $payload design] saved_snapshot [dict get $cpp snapshot] callback_contract [dict get $cpp callback_contract]] {lappend parts "\"$key\":[::GX::ScientificTransportv1::_escape $value]"}
    set context [dict create project $project workspace_id $id snapshot $snapshot stamp [_viewerDevelopmentWorkspaceStamp $workspace] session $::GX::currentSession token [interactiveDocumentSessionToken] sources $sources design $design]
    return [viewerDevelopmentRequest workspace_upgrade_review $project [list ::GX::_viewerDevelopmentWorkspaceReviewed $context $callback] [dict create request_json \{[join $parts ,]\}]]
}
proc ::GX::_viewerDevelopmentWorkspaceReviewGuard {review} {
    if {[dict get $review session] ne $::GX::currentSession || [dict get $review token] ne [interactiveDocumentSessionToken] || [dict get $review snapshot] ne [_viewerDevelopmentSnapshot [dict get $review project]]} {error {Session lifetime or project changed; review again}}
    set workspace [sessionWorkspaceGet [dict get $review workspace_id]]
    if {[_viewerDevelopmentWorkspaceStamp $workspace] ne [dict get $review stamp] || [_viewerDevelopmentWorkspaceSources [dict get $workspace payload]] ne [dict get $review sources]} {error {Workspace or scientific source changed; review again}}
    return $workspace
}
proc ::GX::_viewerDevelopmentWorkspaceReviewed {context callback response} {
    if {[dict get $response ok]} {
        if {[catch {
            set workspace [_viewerDevelopmentWorkspaceReviewGuard $context]
            set report [dict get $response result]
            if {[dict get $report status] ne {REVIEWED_INERT_ADDITIVE_UPGRADE} || [dict get $report source_snapshot] ne [dict get $context snapshot]} {error {Upgrade review did not prove the current project}}
            _viewerDevelopmentWorkspacePayloadUpgrade [dict get $workspace payload] $report [dict get $context design]
            dict for {old saved} $::GX::ViewerDevelopment::workspaceReviews {
                if {[dict get $saved token] ne [dict get $context token] || ([dict get $saved project] eq [dict get $context project] && [dict get $saved workspace_id] eq [dict get $context workspace_id])} {dict unset ::GX::ViewerDevelopment::workspaceReviews $old}
            }
            if {[dict size $::GX::ViewerDevelopment::workspaceReviews]>=8} {error {Too many outstanding Workspace reviews; close or apply an existing review}}
            set id [format review-%x-%x [pid] [clock microseconds]]
            dict set context report $report
            dict set ::GX::ViewerDevelopment::workspaceReviews $id $context
            dict set response result review_id $id
            dict set response result workspace_id [dict get $context workspace_id]
        } message]} {set response [dict create ok 0 code WORKSPACE_UPGRADE_DENIED error $message]}
    }
    uplevel #0 [list {*}$callback $response]
}
proc ::GX::viewerDevelopmentWorkspaceUpgrade {project reviewId} {
    if {![dict exists $::GX::ViewerDevelopment::workspaceReviews $reviewId]} {error {Use a live review issued by this Development Workspace}}
    set review [dict get $::GX::ViewerDevelopment::workspaceReviews $reviewId]
    if {[file normalize $project] ne [dict get $review project]} {error {Review belongs to another developer project}}
    set workspace [_viewerDevelopmentWorkspaceReviewGuard $review]
    set payload [_viewerDevelopmentWorkspacePayloadUpgrade [dict get $workspace payload] [dict get $review report] [dict get $review design]]
    set created {}
    try {
        # Normal Workspace duplication preserves notes, preview and every nested
        # managed resource. Export adds a managed archive to the original's
        # resource store; its canonical payload/revision remains unchanged.
        set resource [sessionWorkspaceExport [dict get $workspace id]]
        _viewerDevelopmentWorkspaceReviewGuard $review
        set name [sessionWorkspaceAvailableName "[string range [dict get $workspace name] 0 110] · upgraded"]
        set duplicate [sessionWorkspaceImport $resource $name];set created [dict get $duplicate id]
        # Transform the imported payload so copied resources retain new ownership.
        set payload [_viewerDevelopmentWorkspacePayloadUpgrade [dict get $duplicate payload] [dict get $review report] [dict get $review design]]
        sessionWorkspaceUpdate $created $payload
        sessionWorkspaceValidate $created
        _viewerDevelopmentWorkspaceReviewGuard $review
        dict unset ::GX::ViewerDevelopment::workspaceReviews $reviewId
        return [dict create status UPGRADED_COPY workspace_id $created original_workspace_id [dict get $workspace id] original_stamp [dict get $review stamp] source_snapshot [dict get $review snapshot] source_documents [dict get $review sources] resource_policy canonical_Workspace_export_import]
    } on error {message options} {
        if {$created ne {} && [interactiveDocumentExists $created]} {catch {sessionWorkspaceDelete $created}}
        return -options $options $message
    }
}
proc ::GX::_viewerDevelopmentWorkspaceReviewReady {id response} {set ::GX::ViewerDevelopment::reviewResponses($id) $response}
proc ::GX::viewerDevelopmentWorkspaceReviewWait {project workspace} {
    set id [incr ::GX::ViewerDevelopment::reviewSerial]
    viewerDevelopmentWorkspaceReview $project $workspace [list ::GX::_viewerDevelopmentWorkspaceReviewReady $id]
    try {vwait ::GX::ViewerDevelopment::reviewResponses($id);set response $::GX::ViewerDevelopment::reviewResponses($id)} finally {unset -nocomplain ::GX::ViewerDevelopment::reviewResponses($id)}
    if {![dict get $response ok]} {error [dict get $response error]}
    return [dict get $response result]
}
