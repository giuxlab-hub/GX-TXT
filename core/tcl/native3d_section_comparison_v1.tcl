# SPDX-License-Identifier: GPL-3.0-or-later
# Native3D sections and Native2D distance geometry share an explicit plane frame.
proc ::GX::_native3DSectionCurve {native contours} {
    set object 0;set priorContour 0
    try {
        foreach contour $contours {
            set reader [interactiveDocumentResourceOpenReader [dict get $contour xy_resource]];set first {};set last {};set firstChunk 1
            try {
                while 1 {
                    set chunk [interactiveDocumentResourceNext $reader];set bytes [dict get $chunk bytes];set n [expr {[string length $bytes]/16}]
                    if {$n} {
                        if {$first eq {}} {set first [string range $bytes 0 15]};set last [string range $bytes end-15 end]
                        set mask [binary format x$n]
                        if {$priorContour&&$firstChunk} {set mask [binary format cx[expr {$n-1}] 1]}
                        set object [::GX::Native2D::core append_binary_xy_gaps $native $object $bytes $mask];set firstChunk 0
                    }
                    if {[dict get $chunk eof]} break
                }
                if {[dict get $contour closed]&&$first ne $last} {set object [::GX::Native2D::core append_binary_xy_gaps $native $object $first [binary format c 0]]}
            } finally {interactiveDocumentResourceCloseReader $reader}
            set priorContour 1
        }
        if {!$object} {error "Section has no finite contour geometry"}
        return $object
    } on error {message options} {if {$object} {::GX::Native2D::core delete $native $object};return -options $options $message}
}
proc ::GX::native3DGeometryCompareSections {token request} {
    set scope [_native3DGeometryRequire $token]
    foreach field {base tool plane tolerance working_unit} {if {![dict exists $request $field]} {error "Section comparison requires $field"}}
    unitRegistryConversionPlan [dict get $request working_unit] mm
    set profiles {};set resources {};set native {};set before [native3DGeometrySceneInfo $token]
    try {
        foreach field {base tool} {
            set receipt [native3DGeometryCall $token section_profile [dict create object_token [dict get $request $field] plane [dict get $request plane] tolerance [dict get $request tolerance]]]
            set profile [dict get $receipt profile_token];lappend profiles $profile
            lappend resources [native3DGeometryProfileResources $token $profile]
        }
        native2DEnsure;set native [::GX::Native2D::core scene]
        set reference [_native3DSectionCurve $native [dict get [lindex $resources 0] contours]]
        set derived [_native3DSectionCurve $native [dict get [lindex $resources 1] contours]]
        set unit [dict get $request working_unit]
        set compared [native2DComparison $native $reference $derived geometry [datasetPublicationV2DictDefault $request sample_budget 257] [list $unit $unit] [list $unit $unit] [dict create producer core.native3d reference [dict get $request base] target [dict get $request tool] coordinate_space section_plane_xy plane [dict get $request plane] section_tolerance [dict get $request tolerance]]]
        if {[native3DGeometrySceneInfo $token] ne $before} {error "Native3D document changed during section comparison"}
        set rows {};set index 0
        foreach row [dict get $compared rows] {lassign $row position signed distance a b;lappend rows [dict create sample_index [incr index] position $position signed_residual $signed distance $distance source $a projected $b]}
        dict set compared rows $rows
        dict set compared coordinate_space section_plane_xy;dict set compared plane [dict get $request plane];dict set compared working_unit [dict get $request working_unit]
        dict set compared tolerance [dict get $request tolerance];dict set compared section_policy native_complete_geometry_chained_contours
        # Opaque temporary profile tokens do not escape as reusable identities.
        dict set compared section_resources [lmap resource $resources {dict remove $resource profile_token}]
        return $compared
    } finally {
        if {$native ne {}} {::GX::Native2D::core destroy $native}
        foreach profile $profiles {native3DGeometryCall $token profile_delete [dict create profile_token $profile]}
    }
}
