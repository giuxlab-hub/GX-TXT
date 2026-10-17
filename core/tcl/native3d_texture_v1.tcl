# SPDX-License-Identifier: GPL-3.0-or-later
# Managed decorative appearance through the existing Native3D texture C ABI.
proc ::GX::native3DLayerTextureValidate {descriptor layer} {
    if {[dict get $descriptor schema] ne "gxtxt.native3d.planar_texture.v1"} {error {Unsupported Native3D texture descriptor}}
    foreach key [dict keys $descriptor] {if {$key ni {schema resource source_geometry_sha256 source_triangle occurrence_index local_anchor anchor_u anchor_v width height rotation_radians flip_u flip_v working_unit image_width image_height image_bit_depth mapping provenance}} {error "Unknown Native3D texture field '$key'"}}
    if {[dict get $layer source_mode] ne "artifact" || [dict get $layer sha256] ne [dict get $descriptor source_geometry_sha256]} {error {Texture source geometry changed; explicitly re-anchor it}}
    set resource [dict get $descriptor resource];interactiveDocumentResourceInfo $resource
    if {[dict get $resource size_bytes]<33||[dict get $resource size_bytes]>134217728} {error {Managed PNG texture requires33bytes..128MiB}}
    set header [interactiveDocumentResourceReadChunk $resource 0 33]
    if {[binary encode hex [string range $header 0 7]] ne "89504e470d0a1a0a" || [string range $header 12 15] ne "IHDR"} {error {Managed texture must be a canonical PNG}}
    binary scan [string range $header 16 23] Iu2 dimensions
    binary scan [string range $header 24 25] cu2 pixel
    lassign $dimensions width height;lassign $pixel depth color
    if {$width<1||$height<1||$width>8192||$height>8192||$width*$height>16777216||$color!=6||$depth ni {8 16}} {error {Managed texture requires bounded true RGBA PNG,8/16bit, at most16million pixels}}
    foreach {key value} [list image_width $width image_height $height image_bit_depth $depth] {if {[dict get $descriptor $key]!=$value} {error {Texture image header differs from captured metadata}}}
    if {![string is entier -strict [dict get $descriptor occurrence_index]]||[dict get $descriptor occurrence_index]<0} {error {Texture occurrence must be a nonnegative actual source identity}}
    if {![string is entier -strict [dict get $descriptor source_triangle]]||[dict get $descriptor source_triangle]<0} {error {Texture source triangle must be an actual nonnegative source identity}}
    if {[llength [split [dict get $descriptor local_anchor] {;}]]!=3} {error {Texture requires an object-local XYZ anchor}}
    foreach value [split [dict get $descriptor local_anchor] {;}] {uiFieldNormalize {type number} $value}
    foreach key {anchor_u anchor_v} {uiFieldNormalize {type number min 0 max 1} [dict get $descriptor $key]}
    foreach key {width height} {set value [uiFieldNormalize {type number min 0} [dict get $descriptor $key]];if {$value==0} {error {Texture physical extent must be positive}}}
    uiFieldNormalize {type number} [dict get $descriptor rotation_radians]
    foreach key {flip_u flip_v} {uiFieldNormalize {type boolean} [dict get $descriptor $key]}
    unitRegistryConversionPlan [dict get $descriptor working_unit] mm
    return $descriptor
}
proc ::GX::native3DLayerTextureBind {module provider layer resource placement} {
    if {"managed_planar_texture" ni [::GX::Engine3D::rpc {capabilities}]} {error {The loaded native adapter does not support managed planar textures}}
    set existing [viewerLayerGet $module $provider $layer]
    set header [interactiveDocumentResourceReadChunk $resource 0 33]
    binary scan [string range $header 16 23] Iu2 dimensions;binary scan [string range $header 24 25] cu2 pixel
    lassign $dimensions width height
    set descriptor [dict merge [dict create schema gxtxt.native3d.planar_texture.v1 resource $resource source_geometry_sha256 [dict get $existing sha256] occurrence_index 0 anchor_u .5 anchor_v .5 rotation_radians 0 flip_u 0 flip_v 0 image_width $width image_height $height image_bit_depth [lindex $pixel 0] mapping {} provenance [dict get $resource metadata]] $placement]
    set descriptor [native3DLayerTextureValidate $descriptor $existing]
    viewerLayerSet $module $provider $layer [dict replace $existing texture $descriptor]
    return $descriptor
}
proc ::GX::native3DLayerTextureAnchor {resource x y width height} {
    interactiveDocumentResourceInfo $resource
    set relative [_native3DPlanarArtifact $resource]
    set path [viewerArtifactResolve $relative [dict get $resource sha256]]
    return [::GX::Engine3D::rpc [list texture_anchor $x $y $path $width $height]]
}
