# SPDX-License-Identifier: GPL-3.0-or-later
# Appearance is a field in the existing object style and destination History.
proc ::GX::Workbench3D::textureAssign {object resource placement} {
    variable document;variable model;variable module;variable provider;variable scene
    ::GX::native3DGeometrySceneInfo $scene
    if {![dict exists $model objects $object]||[dict get $model objects $object locked]} {error {Select an unlocked owned solid or mesh}}
    if {[dict get $placement working_unit] ne [dict get $model working_unit]} {error {Texture placement must use the actual Workbench working unit}}
    set before $model;set source $resource
    try {
        set owned [planarCopyResource $resource]
        dict set placement mapping [dict merge [::GX::datasetPublicationV2DictDefault $placement mapping {}] [dict create source_resource $source target_working_unit [dict get $model working_unit] target_physical_width [dict get $placement width] target_physical_height [dict get $placement height] mapping_policy explicit_decorative_resize]]
        set descriptor [::GX::native3DLayerTextureBind $module $provider $object $owned $placement]
        dict set model objects $object style texture $descriptor
        commit $before planar_texture [dict create placement [dict remove $descriptor resource] resource_sha256 [dict get $owned sha256]] [list $object] [list $object]
    } on error {message options} {
        set model $before;catch {refresh};catch {::GX::interactiveDocumentResourceCollect $document};return -options $options $message
    }
    ::GX::Engine3D::rerender
    return $descriptor
}
proc ::GX::Workbench3D::textureForm {} {
    variable document;variable model;variable panel
    set object [selected];set pick [::GX::Engine3D::latestPick]
    if {![dict exists $pick hit]||![dict get $pick hit]||[dict get $pick layer_id] ne $object||![dict exists $pick viewport_xy]} {error {Click the target planar face in the rendered view first}}
    set resources {};set choices {}
    foreach owner [::GX::interactiveDocumentList] {
        foreach resource [::GX::interactiveDocumentResourceReferences [dict get [::GX::interactiveDocumentRead [dict get $owner id]] payload]] {
            if {[dict get $resource size_bytes]<33||[dict get $resource size_bytes]>134217728} continue
            set header [::GX::interactiveDocumentResourceReadChunk $resource 0 33]
            if {[binary encode hex [string range $header 0 7]] ne {89504e470d0a1a0a}||[string range $header 12 15] ne {IHDR}} continue
            binary scan [string range $header 24 25] cu2 pixel;if {[lindex $pixel 1]!=6} continue
            binary scan [string range $header 16 23] Iu2 dimensions
            set label "[dict get $owner id] / [string range [dict get $resource sha256] 0 11] / [join $dimensions x] RGBA"
            dict set resources $label $resource;if {$label ni $choices} {lappend choices $label}
        }
    }
    if {$choices eq {}} {error {No retained managed RGBA PNG is available in this Session; retain an extracted/composited image first}}
    set unit [dict get $model working_unit]
    set fields [dict create image [dict create type choice label {Managed RGBA image} values $choices] width [dict create type number label "Image width ($unit), explicit decorative resize" min 0] height [dict create type number label "Image height ($unit), explicit decorative resize" min 0] rotation_radians [dict create type number label {Rotation around source-face normal (radians)}] flip_u {type boolean label {Flip image U}} flip_v {type boolean label {Flip image V}}]
    set capture [dict create owner [::GX::interactiveDocumentRead $document] object $object pick $pick render_generation $::GX::Engine3D::renderGeneration viewport [::GX::Engine3D::hostViewportSize] resources $resources]
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.texture {Managed image on picked planar face} $fields [dict create image [lindex $choices 0] width 1 height 1 rotation_radians 0 flip_u 0 flip_v 0] [list ::GX::Workbench3D::textureFormApply $capture] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::textureFormApply {capture values} {
    variable document;variable model;variable busy
    if {$busy} {error {Finish the current Workbench operation first}}
    set busy 1
    try {
    if {[::GX::interactiveDocumentRead $document] ne [dict get $capture owner]||$::GX::Engine3D::renderGeneration!=[dict get $capture render_generation]||[::GX::Engine3D::hostViewportSize] ne [dict get $capture viewport]} {error {Source geometry or rendered view changed; close this form and pick the current face again}}
    set resource [dict get $capture resources [dict get $values image]];lassign [dict get $capture pick viewport_xy] x y
    set anchor [::GX::native3DLayerTextureAnchor $resource $x $y [dict get $values width] [dict get $values height]]
    if {[::GX::interactiveDocumentRead $document] ne [dict get $capture owner]} {error {The original3D Workspace changed while resolving its source face}}
    if {[dict get $anchor layer_id] ne [dict get $capture object]} {error {The selected face no longer belongs to the captured body}}
    set placement [dict merge [dict remove $values image] $anchor [dict create working_unit [dict get $model working_unit]]]
    dict unset placement layer_id;dict set placement local_anchor [join [dict get $placement local_anchor] {;}]
    textureAssign [dict get $capture object] $resource $placement
    } finally {set busy 0}
}
proc ::GX::Workbench3D::textureClear {} {
    variable model
    set object [selected]
    if {[dict get $model objects $object locked]} {error {Selected object is locked}}
    if {![dict exists $model objects $object style texture]} return
    set before $model;dict unset model objects $object style texture
    commit $before remove_planar_texture {} [list $object] [list $object]
    ::GX::Engine3D::rerender
}
