# SPDX-License-Identifier: GPL-3.0-or-later
# The existing3D Workspace owner alone commits accepted profiles and History.
proc ::GX::Workbench3D::planarEditSelected {mode} {
    variable document;variable scene;variable model;variable tokens;variable guiHost;variable planarHosts
    if {$mode ni {section projection}} {error {Choose section or projection}}
    set id [selected]
    if {![dict exists $model objects $id]} {error {Select one actual3D body}}
    checkpoint
    set origin [::GX::native3DPlanarOriginReceipt $document $id]
    set destinationHost {}
    if {$guiHost ne {} && [dict get $guiHost document_id] eq $document &&
        [dict get $guiHost generation] eq [dict get $origin generation] &&
        [dict get $guiHost session_token] eq [::GX::interactiveDocumentSessionToken] &&
        [winfo exists [dict get $guiHost parent]] &&
        [winfo id [dict get $guiHost parent]] eq [dict get $guiHost incarnation] &&
        $::GX::Engine3D::window eq "[dict get $guiHost parent].native3d"} {
        set destinationHost $guiHost
    }
    set object [dict get $tokens $id];set derived {}
    try {
        if {[dict get $model objects $id kind] eq "brep"} {
            set mesh [call mesh [dict create object_token $object linear_deflection .01 angular_deflection .3 weld_tolerance 1e-8 max_triangles 1000000 max_output_bytes 134217728]]
            set derived [dict get $mesh object_token];set object $derived
        }
        set resource [::GX::native3DGeometryExportResource $scene $object vtp [millimeters]]
        set path [file join $::GX::currentSession [::GX::_native3DPlanarArtifact $resource]]
        set plane [dict create origin [split $::GX::Engine3D::planeOrigin {;}] normal [split $::GX::Engine3D::planeNormal {;}] u_axis [split $::GX::Engine3D::planeU {;}]]
        ::GX::native3DPlanarOriginValidate $origin
    } finally {if {$derived ne {}} {call delete [dict create object_token $derived]}}
    set planar [::GX::native3DPlanarCreate $path [dict get $model working_unit] $plane 1e-8 [dict create origin_workspace $origin mode $mode]]
    if {$destinationHost ne {}} {dict set planarHosts $planar $destinationHost}
    set ::GX::PlanarGUI::document $planar
    return [::GX::viewerOpen viewer.curve_workbench curve_workbench [dict create workspace_id new workspace_name "3D $document $mode" planar_document $planar planar_mode $mode]]
}
proc ::GX::Workbench3D::_planarRestoreHost {planar destination generation} {
    variable planarHosts;variable document;variable scene;variable module;variable provider
    if {![dict exists $planarHosts $planar]} {return [dict create status not_requested]}
    set host [dict get $planarHosts $planar];set parent [dict get $host parent]
    # A closed/recreated component or a new Session is never a return target.
    if {[dict get $host session_token] ne [::GX::interactiveDocumentSessionToken] ||
        [dict get $host document_id] ne $destination || [dict get $host generation] ne $generation ||
        ![winfo exists $parent] || [winfo id $parent] ne [dict get $host incarnation]} {
        dict unset planarHosts $planar
        return [dict create status expired]
    }
    # Acceptance has already activated exactly this canonical owner. Do not
    # replace another active editor or bypass its normal owner/lifetime checks.
    if {$scene eq {} || $document ne $destination ||
        [::GX::Engine3D::ownerModule] ne $module || [::GX::Engine3D::ownerProvider] ne $provider ||
        [dict get [::GX::interactiveDocumentRead $destination] generation] ne $generation} {
        error {The accepted planar destination is not the active 3D owner; reopen it explicitly}
    }
    set mounted [guiMount $parent [dict create workspace_id $destination]]
    pack $mounted -fill both -expand 1
    guiPresentationChanged
    return [dict create status restored parent $parent]
}
proc ::GX::Workbench3D::planarCopyResource {reference} {
    variable document
    set reader [::GX::interactiveDocumentResourceOpenReader $reference];set writer {}
    try {
        set writer [::GX::interactiveDocumentResourceOpenWriter $document [dict get $reference metadata]]
        while 1 {set part [::GX::interactiveDocumentResourceNext $reader];::GX::interactiveDocumentResourceAppend $writer [dict get $part bytes];if {[dict get $part eof]} break}
        set result [::GX::interactiveDocumentResourceFinalize $writer];set writer {};return $result
    } finally {::GX::interactiveDocumentResourceCloseReader $reader;if {$writer ne {}} {::GX::interactiveDocumentResourceAbort $writer}}
}
proc ::GX::Workbench3D::planarAcceptResult {planar origin accepted} {
    variable document;variable model;variable scene;variable profileTokens;variable profile
    if {[dict get $origin session_origin] ne [::GX::sessionOriginRead] || [dict get $origin plane] ne [dict get $accepted plane]} {error {Planar return Session or working-plane frame changed}}
    set destination [dict get $origin document_id]
    set signature [::GX::datasetStorageSha256Text $::GX::currentSession $accepted]
    # Retry after an interrupted presentation acknowledgement is idempotent.
    set owner [::GX::interactiveDocumentRead $destination]
    if {[dict get $owner generation] ne [dict get $origin generation]} {error {Originating3D Workspace was replaced}}
    dict for {id prior} [dict get $owner payload model profiles] {
        if {[::GX::datasetPublicationV2DictDefault $prior planar_result_sha256 {}] eq $signature && [::GX::datasetPublicationV2DictDefault $prior source_planar_document {}] eq $planar} {
            activateDocument [dict create workspace_id $destination]
            set presentation [_planarRestoreHost $planar $destination [dict get $origin generation]]
            return [dict create status already_committed document_id $destination profile_id $id planar_document_id $planar presentation $presentation]
        }
    }
    ::GX::native3DPlanarOriginValidate $origin
    activateDocument [dict create workspace_id $destination]
    ::GX::native3DPlanarOriginValidate $origin
    if {[dict get $model working_unit] ne [dict get $accepted working_unit]} {error {Accepted planar unit does not match originating3D Workspace}}
    set before $model;set native {};set result {}
    try {
        set contours {};foreach contour [dict get $accepted contours] {dict set contour xy_resource [planarCopyResource [dict get $contour xy_resource]];lappend contours $contour}
        set receipt [call profile [dict create contours $contours plane [dict get $accepted plane] tolerance [dict get $accepted tolerance]]];set native [dict get $receipt profile_token]
        set view [::GX::native3DGeometryProfileViewResource $scene $native]
        set result [nextId next_profile profile]
        dict set model profiles $result [dict create name {Accepted planar edit} contours $contours plane [dict get $accepted plane] tolerance [dict get $accepted tolerance] working_unit [dict get $accepted working_unit] definitions [dict get $accepted definitions] display_geometry $view source_kind retained_planar_edit source_object_id [dict get $origin object_id] source_geometry [dict get $before objects [dict get $origin object_id] geometry] source_bindings {} source_planar_document $planar planar_result_sha256 $signature origin_workspace $origin provenance [dict get $accepted provenance]]
        dict set profileTokens $result $native;set profile $result
        ::GX::native3DPlanarOriginValidate $origin
        commit $before planar_edit_return [dict create origin $origin planar_document $planar accepted_sha256 $signature] [list [dict get $origin object_id]] [list $result]
    } on error {message opts} {
        set model $before
        if {$result ne {}&&[dict exists $profileTokens $result]} {dict unset profileTokens $result}
        if {$native ne {}} {catch {call profile_delete [dict create profile_token $native]}}
        catch {::GX::interactiveDocumentResourceCollect $document}
        return -options $opts $message
    }
    ::GX::Engine3D::rerender
    set presentation [_planarRestoreHost $planar $destination [dict get $origin generation]]
    return [dict create status committed document_id $document profile_id $result planar_document_id $planar transaction_scope destination_owner_only original_body_preserved 1 presentation $presentation]
}
