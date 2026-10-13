# SPDX-License-Identifier: GPL-3.0-or-later
# Document-owned integration of existing Native3D/Native2D authorities.
namespace eval ::GX::PlanarGeometry {variable edits {};variable serial 0}
proc ::GX::native3DPlanarApiInfo {} {
    return {api_id NATIVE_3D_GEOMETRY_API_v1 extension planar_workflow operations {create list show focus edit_begin edit_accept edit_cancel} working_units explicit frame right_handed projection orthogonal_source_boundary reverse_mapping new_curve_on_plane max_contours 4096 max_points 1000000 reference_pixels_max 4096}
}
proc ::GX::_native3DPlanarOwner {document} {
    set owner [interactiveDocumentRead $document]
    if {[dict get $owner format] ne "gxtxt.native3d.planar"} {error {Document is not a Native3D planar workflow}}
    return $owner
}
proc ::GX::_native3DPlanarXY {reference} {
    set count [dict get $reference metadata point_count]
    if {$count>1000000||[dict get $reference size_bytes]!=16*$count} {error {Invalid planar resource shape}}
    set bytes {};set reader [interactiveDocumentResourceOpenReader $reference]
    try {while 1 {set chunk [interactiveDocumentResourceNext $reader];append bytes [dict get $chunk bytes];if {[dict get $chunk eof]} break}} finally {interactiveDocumentResourceCloseReader $reader}
    binary scan $bytes q* numbers
    set points {};foreach {x y} $numbers {lappend points [list $x $y]};return $points
}
proc ::GX::_native3DPlanarProfile {scene profile unit mode} {
    set resource [native3DGeometryProfileResources $scene $profile]
    set definitions {};set index 0
    foreach contour [dict get $resource contours] {
        set points [_native3DPlanarXY [dict get $contour xy_resource]]
        dict set definitions ${mode}_[incr index] [dict create name "$mode $index" definition [dict create family path controls $points closed [dict get $contour closed]] units [list $unit $unit] provenance [dict create operation $mode source_contour [expr {$index-1}] approximation piecewise_linear]]
    }
    return [dict create definitions $definitions contours $resource view_resource [native3DGeometryProfileViewResource $scene $profile]]
}
proc ::GX::native3DPlanarList {} {
    set result {};foreach record [interactiveDocumentList] {if {[dict get $record format] eq "gxtxt.native3d.planar"} {lappend result $record}};return $result
}
proc ::GX::native3DPlanarCreate {sourcePath unit plane tolerance {options {}}} {
    unitRegistryConversionPlan $unit m
    if {![string is double -strict $tolerance]||$tolerance<=0||$tolerance>=Inf} {error {Declare a positive finite section tolerance}}
    set format [string trimleft [string tolower [file extension $sourcePath]] .]
    if {$format ni {vtp stl obj step stp}} {error {Choose VTP, STL, OBJ or STEP geometry}}
    if {$format eq "stp"} {set format step}
    set previousView [viewerSceneGet viewer.engine_3d engine_3d];set previousLayers {}
    foreach id [viewerLayerIds viewer.engine_3d engine_3d] {dict set previousLayers $id [viewerLayerGet viewer.engine_3d engine_3d $id]}
    set owner [interactiveDocumentCreate viewer.engine_3d engine_3d gxtxt.native3d.planar 1 [dict create status preparing]]
    set document [dict get $owner id];set scene {}
    try {
        set scale [expr {[unitRegistryIntrinsicScale $unit]/[unitRegistryIntrinsicScale mm]}]
        set source [interactiveDocumentResourceImportNumeric $document $sourcePath [dict create format native3d.$format.v1 working_unit $unit millimeters_per_working_unit $scale]]
        set scene [native3DGeometryOpen $document]
        set object [native3DGeometryCall $scene [expr {$format eq "step"?"load_step":$format eq "vtp"?"load_scientific":"load_mesh"}] [dict create resource $source]]
        set normalized [native3DGeometryCall $scene plane_frame [dict create plane $plane]]
        dict set normalized working_unit $unit;dict set normalized orientation right_handed
        set request [dict create object_token [dict get $object object_token] plane $normalized tolerance $tolerance]
        set section [native3DGeometryCall $scene section_profile $request]
        set sectionData [_native3DPlanarProfile $scene [dict get $section profile_token] $unit section]
        set projectionRequest $request
        if {$format eq "step"} {
            if {![dict exists $options tessellation]} {error {CAD reference projection requires an explicit tessellation policy: linear_deflection angular_deflection weld_tolerance max_triangles max_output_bytes}}
            set mesh [native3DGeometryCall $scene mesh [dict merge [dict get $options tessellation] [dict create object_token [dict get $object object_token]]]]
            dict set projectionRequest object_token [dict get $mesh object_token]
        }
        if {[catch {set projection [native3DGeometryCall $scene projection_profile $projectionRequest]} message errorOptions]} {
            if {![string match {*Boundary projection needs 1..4096 actual source boundary contours*} $message]} {return -options $errorOptions $message}
            set projectionData [dict create definitions {} policy orthogonal_full_surface editable_boundary unavailable reason $message]
        } else {set projectionData [_native3DPlanarProfile $scene [dict get $projection profile_token] $unit projection]}
        set projected [native3DGeometryCall $scene project $projectionRequest]
        dict set projectionData surface_resource [native3DGeometryExportResource $scene [dict get $projected object_token] vtp $scale]
        dict set projectionData diagnostics {depth discarded overlaps preserved_not_merged topology may_overlap_or_degenerate inverse unavailable}
        if {$format eq "step"} {dict set projectionData tessellation [dict get $options tessellation]}
        set payload [dict create schema gxtxt.native3d.planar version 1 source_resource $source source_geometry $object source_name [file tail $sourcePath] color_array [datasetPublicationV2DictDefault $options color_array {}] working_unit $unit plane $normalized tolerance $tolerance section $sectionData projection $projectionData accepted {} presentation [dict create reference_opacity .45 reference_visible 1] provenance [dict create source_sha256 [dict get $source sha256] operation section_and_orthogonal_boundary_projection original_preserved 1 approximation piecewise_linear lost_depth 1 reverse_mapping new_planar_curve source_document $document]]
        # Worker tokens are process-local, never part of the saved scientific model.
        dict set payload provenance origin [_originCreate derived_geometry [dict create source_origin [_originUnknown] source_sha256 [dict get $source sha256] session_origin [sessionOriginRead]]]
        dict unset payload source_geometry object_token
        native3DGeometryCheckpoint $scene $payload
        native3DGeometryClose $scene;set scene {}
        native3DPlanarShow $document source
        set reference [_native3DPlanarReference $document $options]
        set owner [_native3DPlanarOwner $document];set payload [dict get $owner payload];dict set payload reference $reference
        interactiveDocumentUpdate $document $payload
        native3DPlanarShow $document all
        return $document
    } on error {message options} {
        if {$scene ne {}} {catch {native3DGeometryClose $scene}}
        catch {interactiveDocumentDelete $document}
        foreach id [viewerLayerIds viewer.engine_3d engine_3d] {if {[string match "${document}_*" $id]} {viewerLayerRemove viewer.engine_3d engine_3d $id}}
        dict for {id layer} $previousLayers {viewerLayerSet viewer.engine_3d engine_3d $id $layer}
        viewerSceneSet viewer.engine_3d engine_3d $previousView
        return -options $options $message
    }
}
proc ::GX::_native3DPlanarArtifact {resource} {
    interactiveDocumentResourceInfo $resource
    set extension [lindex [split [dict get $resource metadata format] .] 1]
    set relative [file join viewer_artifacts "[dict get $resource sha256].$extension"]
    set path [file join $::GX::currentSession $relative]
    if {![file exists $path]} {
        file mkdir [file dirname $path];set staged "$path.[pid].tmp";set reader [interactiveDocumentResourceOpenReader $resource];set f [open $staged wb]
        try {while 1 {set chunk [interactiveDocumentResourceNext $reader];puts -nonewline $f [dict get $chunk bytes];if {[dict get $chunk eof]} break}} finally {close $f;interactiveDocumentResourceCloseReader $reader}
        file rename -- $staged $path
    }
    viewerArtifactRegister $relative
    return $relative
}
proc ::GX::native3DPlanarShow {document {mode all}} {
    if {$mode ni {all source section projection accepted reference}} {error {Unknown planar presentation}}
    set payload [dict get [_native3DPlanarOwner $document] payload];set plane [dict get $payload plane]
    set module viewer.engine_3d;set provider engine_3d
    set resources [dict create source [dict get $payload source_resource] section [dict get $payload section view_resource]]
    if {[dict exists $payload projection view_resource]} {dict set resources projection [dict get $payload projection view_resource]}
    if {$mode eq "projection"} {dict set resources projected_surface [dict get $payload projection surface_resource]}
    if {[dict get $payload accepted] ne {}} {dict set resources accepted [dict get $payload accepted view_resource]}
    foreach existing [viewerLayerIds $module $provider] {viewerLayerSet $module $provider $existing [dict merge [viewerLayerGet $module $provider $existing] {visible 0}]}
    dict for {name resource} $resources {
        set path [_native3DPlanarArtifact $resource];set ext [string trimleft [file extension $path] .]
        set visible [expr {$name eq "source"||$mode eq "all"||$mode eq $name||$name eq "projected_surface"}]
        set color [dict get {source {0.5;0.7;0.9} section {1;0.25;0.1} projection {0.1;0.9;0.4} projected_surface {0.2;0.8;0.4} accepted {1;0.1;0.8}} $name]
        viewerLayerSet $module $provider ${document}_$name [dict create kind [expr {$name in {source projected_surface}?"surface":"trajectory"}] color_array [expr {$name eq "source"?[datasetPublicationV2DictDefault $payload color_array {}]:{}}] scalar_coloring [expr {$name eq "source"&&[datasetPublicationV2DictDefault $payload color_array {}] ne {}}] source_mode artifact resource_path $path sha256 [dict get $resource sha256] format $ext format_version 1 visible $visible base_color $color opacity [expr {$name eq "source"&&$mode ni {source reference}?.5:1}] line_width 3]
    }
    set fields [dict create working_plane_visible [expr {$mode ne "source"}] working_plane_origin [join [dict get $plane origin] {;}] working_plane_normal [join [dict get $plane normal] {;}] working_plane_u_axis [join [dict get $plane u_axis] {;}]]
    if {$mode eq "reference"} {set fields [dict merge $fields [dict get $payload reference camera] {navigation_cube_visible 0}]} else {
        set fields [dict merge $fields {projection perspective orthographic_height 0 near_clip 0 far_clip 0 camera_position {0;0;1} camera_target {0;0;0} camera_up {0;1;0} navigation_cube_visible 0}]
    }
    viewerSceneSet $module $provider [dict merge [viewerSceneGet $module $provider] $fields]
    viewerOpen $module $provider
    ::GX::Engine3D::configureHost $module $provider [dict create selection [list ::GX::native3DPlanarGuiSelection $document]]
    return $document
}
proc ::GX::_native3DPlanarReference {document options} {
    set payload [dict get [_native3DPlanarOwner $document] payload];set plane [dict get $payload plane]
    set width [datasetPublicationV2DictDefault $options width 1024];set height [datasetPublicationV2DictDefault $options height 768]
    foreach value [list $width $height] {if {![string is integer -strict $value]||$value<16||$value>4096} {error {Raster dimensions must be 16..4096}}}
    set scene [native3DGeometryOpen $document]
    try {
        lassign [dict get $payload source_geometry bounds_min] x0 y0 z0;lassign [dict get $payload source_geometry bounds_max] x1 y1 z1
        set corners {};foreach x [list $x0 $x1] {foreach y [list $y0 $y1] {foreach z [list $z0 $z1] {lappend corners [list $x $y $z]}}}
        set local [dict get [native3DGeometryCall $scene plane_frame [dict create plane $plane direction to_plane points $corners]] points]
        set us {};set vs {};set depths {};foreach p $local {lassign $p u v d;lappend us $u;lappend vs $v;lappend depths $d}
        set u0 [tcl::mathfunc::min {*}$us];set u1 [tcl::mathfunc::max {*}$us];set v0 [tcl::mathfunc::min {*}$vs];set v1 [tcl::mathfunc::max {*}$vs]
        set physicalHeight [expr {1.1*max($v1-$v0,($u1-$u0)*$height/double($width))}]
        if {$physicalHeight<=0} {error {Degenerate reference extent}}
        set physicalWidth [expr {$physicalHeight*$width/double($height)}];set u [expr {($u0+$u1)/2}];set v [expr {($v0+$v1)/2}]
        set distance [expr {max(abs([tcl::mathfunc::min {*}$depths]),abs([tcl::mathfunc::max {*}$depths]))+2*$physicalHeight}]
        set locations [dict get [native3DGeometryCall $scene plane_frame [dict create plane $plane direction to_world points [list [list $u $v 0] [list $u $v $distance]]]] points]
        set camera [dict create projection orthographic orthographic_height $physicalHeight camera_target [join [lindex $locations 0] {;}] camera_position [join [lindex $locations 1] {;}] camera_up [join [dict get $plane v_axis] {;}] near_clip [expr {$physicalHeight*1e-5}] far_clip [expr {4*$distance}]]
    } finally {native3DGeometryClose $scene}
    viewerSceneSet viewer.engine_3d engine_3d [dict merge [viewerSceneGet viewer.engine_3d engine_3d] $camera [dict create working_plane_visible 0 axes_world 0 navigation_cube_visible 0]]
    viewerOpen viewer.engine_3d engine_3d
    set f [file tempfile path];close $f;file delete -- $path
    try {
        ::GX::Engine3D::screenshot $path $width $height
        set resource [interactiveDocumentResourceImportNumeric $document $path [dict create format image.raster source_sha256 [dict get $payload source_resource sha256] operation orthographic_reference origin [_scientificResourceOrigin $document derived_reference_image]]]
    } finally {file delete -force -- $path}
    set scale [expr {$physicalHeight/$height}];set lower [list [expr {$u-$physicalWidth/2}] [expr {$v-$physicalHeight/2}]]
    return [dict create resource $resource width $width height $height plane $plane working_unit [dict get $payload working_unit] scale $scale translation $lower camera $camera pixel_convention bottom_left_pixel_edges viewing_side positive_normal clipping all_source_bounds source_sha256 [dict get $payload source_resource sha256]]
}
proc ::GX::native3DPlanarEditBegin {document mode} {
    variable ::GX::PlanarGeometry::edits;variable ::GX::PlanarGeometry::serial
    if {$mode ni {section projection}} {error {Choose section or projection}}
    set owner [_native3DPlanarOwner $document]
    if {[dict size [dict get $owner payload $mode definitions]]==0} {error {This projection has no editable source boundary; the complete projected surface remains available in the modern Viewer}}
    set token "planar-edit#[pid]-[incr serial]"
    set context [dict create document_id $document revision [dict get $owner revision] generation [dict get $owner generation] sha256 [dict get $owner sha256] session_token [interactiveDocumentSessionToken] mode $mode]
    dict set edits $token $context
    return [dict create token $token context $context payload [dict get $owner payload]]
}
proc ::GX::native3DPlanarEditCancel {token} {
    variable ::GX::PlanarGeometry::edits
    if {![dict exists $edits $token]} {error {Unknown or closed planar edit}}
    dict unset edits $token
    return cancelled
}
proc ::GX::native3DPlanarEditAccept {token definitions unit presentation} {
    variable ::GX::PlanarGeometry::edits
    if {![dict exists $edits $token]} {error {Unknown or closed planar edit}}
    set context [dict get $edits $token];set document [dict get $context document_id]
    _geometryExchangeOwner $document
    set owner [_native3DPlanarOwner $document]
    foreach key {revision generation sha256} {if {[dict get $owner $key] ne [dict get $context $key]} {error {Source changed during editing; cancel and reopen the current source}}}
    if {[dict get $context session_token] ne [interactiveDocumentSessionToken]} {error {Edit belongs to another Session lifetime}}
    set payload [dict get $owner payload]
    if {$unit ne [dict get $payload working_unit]} {error {Edit units differ from the working plane; convert explicitly before editing}}
    if {[dict size $definitions]<1||[dict size $definitions]>4096} {error {Accepted result requires 1..4096 curves}}
    interactiveDocumentResourceInfo [dict get $payload source_resource]
    native2DEnsure
    set native [::GX::Native2D::core scene];set scene {};set contours {}
    try {
        set scene [native3DGeometryOpen $document]
        dict for {id record} $definitions {
            if {[dict get $record units] ne [list $unit $unit]} {error "Curve $id has incompatible units"}
            set definition [dict get $record definition]
            set object [::GX::Native2D::core sketch_create $native $definition 257]
            set points [::GX::Native2D::core points $native $object]
            # Native2D displays a closed path with its initial vertex repeated;
            # Native3D stores closure separately. Preserve every unique vertex.
            if {[datasetPublicationV2DictDefault $definition closed 0] && [lindex $points 0] eq [lindex $points end]} {set points [lrange $points 0 end-1]}
            set writer [interactiveDocumentResourceOpenWriter $document [dict create format native2d.float64_xy_le_v1 point_count [llength $points]]]
            try {interactiveDocumentResourceAppend $writer [binary format q* [concat {*}$points]];set resource [interactiveDocumentResourceFinalize $writer]} on error {m o} {catch {interactiveDocumentResourceAbort $writer};return -options $o $m}
            lappend contours [dict create xy_resource $resource closed [datasetPublicationV2DictDefault $definition closed 0]]
        }
        set profile [native3DGeometryCall $scene profile [dict create contours $contours plane [dict get $payload plane] tolerance [dict get $payload tolerance]]]
        set result [native3DGeometryProfileViewResource $scene [dict get $profile profile_token]]
        dict set payload accepted [dict create definitions $definitions view_resource $result contours $contours operation new_curve_on_working_plane source_revision [dict get $owner revision] source_sha256 [dict get $payload source_resource sha256] approximation {piecewise_linear_paths_exact other_retained_families_sampled_257}]
        foreach key {reference_opacity reference_visible} {if {![dict exists $presentation $key]} {error "Missing presentation $key"}}
        set opacity [dict get $presentation reference_opacity]
        if {![string is double -strict $opacity] || !($opacity>=0&&$opacity<=1) || ![string is boolean -strict [dict get $presentation reference_visible]]} {error {Invalid reference presentation}}
        dict set payload accepted origin [_originCreate derived_geometry [dict create source_origin [dict get $payload provenance origin] source_sha256 [dict get $payload source_resource sha256] source_revision [dict get $owner revision]]]
        dict set payload presentation $presentation
        # Revalidate after worker callbacks and resource staging, then one owner commit.
        if {[interactiveDocumentRead $document] ne $owner} {error {Source changed during derivation}}
        native3DGeometryCheckpoint $scene $payload
        dict unset edits $token
        return [dict create document_id $document status accepted result $result]
    } on error {m o} {catch {interactiveDocumentResourceCollect $document};return -options $o $m} finally {
        if {$scene ne {}} {catch {native3DGeometryClose $scene}}
        ::GX::Native2D::core destroy $native
    }
}
