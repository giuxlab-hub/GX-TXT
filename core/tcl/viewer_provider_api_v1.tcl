# SPDX-License-Identifier: GPL-3.0-or-later
# Renderer-agnostic, multi-layer Viewer Provider API v1.
namespace eval ::GX {
    variable viewerProviderApiVersion 1
    variable viewerScene
    variable viewerLayer
    variable viewerAttribute
    variable viewerBackend
    array set viewerScene {}
    array set viewerLayer {}
    array set viewerAttribute {}
    array set viewerBackend {}
}

proc ::GX::viewerIdValid {id} {
    return [regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $id]
}
proc ::GX::viewerProviderIds {moduleId} {
    variable moduleCatalog
    if {![info exists moduleCatalog($moduleId,dict)]} {return {}}
    set d $moduleCatalog($moduleId,dict)
    set version [descriptorValue $d viewers api_version ""]
    if {$version eq ""} {return {}}
    if {$version ne "1"} {error "$moduleId: unsupported Viewer Provider API version $version"}
    set out [splitList [descriptorValue $d viewers ids ""]]
    foreach id $out {
        if {![viewerIdValid $id]} {error "$moduleId: invalid viewer ID $id"}
        if {[descriptorValue $d "viewer.$id" backend ""] eq ""} {error "$moduleId/$id: backend is required"}
        set activationApi [string trim [descriptorValue $d "viewer.$id" activation_api ""]]
        set backendScript [string trim [descriptorValue $d "viewer.$id" backend_script ""]]
        if {$activationApi ne "" && $backendScript ne ""} {
            error "$moduleId/$id: use activation_api or backend_script, not both"
        }
        if {$activationApi ne "" && $activationApi ni [splitList [descriptorValue $d public_apis ids ""]]} {
            error "$moduleId/$id: activation_api '$activationApi' is not declared by the module"
        }
    }
    return $out
}
proc ::GX::viewerProviderDefinition {moduleId viewerId {includeDisabled 0}} {
    variable moduleCatalog
    if {[lsearch -exact [viewerProviderIds $moduleId] $viewerId] < 0} {error "Unknown Viewer Provider $moduleId/$viewerId"}
    if {!$includeDisabled && ![viewerProviderEnabled $moduleId $viewerId]} {return {}}
    set d $moduleCatalog($moduleId,dict)
    set out [dict create module_id $moduleId viewer_id $viewerId]
    foreach f {name backend activation_api backend_script supported_primitives artifact_formats capabilities short_title semantic_group group_title icon} {
        dict set out $f [descriptorValue $d "viewer.$viewerId" $f ""]
    }
    foreach {field fallback} [list short_title [dict get $out name] semantic_group other group_title {Other Viewers}] {if {[dict get $out $field] eq {}} {dict set out $field $fallback}}
    dict set out enabled [viewerProviderEnabled $moduleId $viewerId]
    dict set out icon_path [viewerProviderIconPath $moduleId [dict get $out icon]]
    dict set out availability_reason [expr {[dict get $out enabled]?"Available":"Presentation disabled"}]
    return $out
}
proc ::GX::viewerProviderList {} {
    variable moduleOrder
    set out {}
    foreach module $moduleOrder {
        foreach id [viewerProviderIds $module] {if {[viewerProviderEnabled $module $id]} {lappend out [viewerProviderDefinition $module $id]}}
    }
    return $out
}
proc ::GX::viewerRequireProvider {moduleId viewerId} {
    if {[lsearch -exact [viewerProviderIds $moduleId] $viewerId] < 0} {error "Unknown Viewer Provider $moduleId/$viewerId"}
}
proc ::GX::viewerTriple {value name} {
    set parts [split $value {;}]
    if {[llength $parts] != 3} {error "$name must contain three semicolon-separated numbers"}
    foreach n $parts {
        if {![string is double -strict $n] || [catch {expr {abs(double($n)) < Inf}} ok] || !$ok} {error "$name must be finite"}
    }
    return $value
}
proc ::GX::viewerSceneDefaults {} {
    return [dict create camera_position {0;0;1} camera_target {0;0;0} camera_up {0;1;0} \
        projection perspective navigation_cube_visible 1 orthographic_height 0 near_clip 0 far_clip 0 clipping_planes "" scene_mode automatic \
        background_rgb {0.12;0.14;0.18} background_bottom_rgb {0.04;0.05;0.08} \
        background_gradient 0 lighting 1 lighting_ambient 0.25 \
        lighting_diffuse 0.8 lighting_specular 0.2 \
        lighting_direction {-0.4;-0.5;-1} lighting_color {1;1;1} lighting_intensity 1 \
        lighting_lights "" \
        clip_box "" marker_definitions "" measurement_definitions "" curve_definitions "" \
        timeline_definitions "" active_timeline_id "" field_definitions "" \
        axes_world 0 axes_local_layer "" axes_reference_marker "" axes_size_pixels 72 orientation_indicator_visible 0 \
        working_plane_origin {0;0;0} working_plane_normal {0;0;1} \
        working_plane_u_axis {1;0;0} working_plane_visible 0]
}
proc ::GX::viewerSceneSet {moduleId viewerId fields} {
    variable viewerScene
    set d [viewerSceneValidate $moduleId $viewerId $fields]
    set viewerScene($moduleId,$viewerId) $d
    return $d
}
proc ::GX::viewerSceneValidate {moduleId viewerId fields} {
    viewerRequireProvider $moduleId $viewerId
    set d [dict merge [viewerSceneDefaults] $fields]
    foreach k [dict keys $d] {if {$k ni {camera_position camera_target camera_up projection navigation_cube_visible orthographic_height near_clip far_clip clipping_planes clip_box marker_definitions measurement_definitions curve_definitions timeline_definitions active_timeline_id field_definitions axes_world axes_local_layer axes_reference_marker axes_size_pixels orientation_indicator_visible scene_mode background_rgb background_bottom_rgb background_gradient lighting lighting_ambient lighting_diffuse lighting_specular lighting_direction lighting_color lighting_intensity lighting_lights working_plane_origin working_plane_normal working_plane_u_axis working_plane_visible}} {error "Unknown scene field $k"}}
    set timelineIds {}
    if {[llength [dict get $d timeline_definitions]] > 16} {error "Too many timelines"}
    foreach timeline [dict get $d timeline_definitions] {
        if {[catch {dict size $timeline}]} {error "Timeline definition must be a dictionary"}
        foreach key {id unit times tracks current_frame current_time range_first range_last rate loop state} {
            if {![dict exists $timeline $key]} {error "Timeline definition missing $key"}
        }
        set id [dict get $timeline id]
        if {![viewerIdValid $id] || $id in $timelineIds} {error "Timeline IDs must be unique"}
        lappend timelineIds $id
        set times [dict get $timeline times]
        if {[llength $times] < 1 || [llength $times] > 256} {error "Timeline requires 1..256 times"}
        set previous -Inf
        foreach time $times {
            if {![string is double -strict $time] || ![expr {abs(double($time)) < Inf && $time > $previous}]} {
                error "Timeline times must increase and be finite"}
            set previous $time
        }
        set last [expr {[llength $times]-1}]
        foreach key {current_frame range_first range_last} {
            set n [dict get $timeline $key]
            if {![string is integer -strict $n] || $n < 0 || $n > $last} {error "Timeline $key is out of range"}
        }
        if {[dict get $timeline range_first] > [dict get $timeline range_last]} {error "Timeline playback range is reversed"}
        set currentTime [dict get $timeline current_time]
        if {![string is double -strict $currentTime] ||
            ![expr {abs(double($currentTime)) < Inf}] ||
            $currentTime < [lindex $times 0] || $currentTime > [lindex $times end]} {
            error "Timeline current time is outside its samples"
        }
        set nearest 0
        set nearestDistance Inf
        for {set i 0} {$i < [llength $times]} {incr i} {
            set distance [expr {abs(double($currentTime)-double([lindex $times $i]))}]
            if {$distance < $nearestDistance} {set nearest $i;set nearestDistance $distance}
        }
        if {[dict get $timeline current_frame] != $nearest} {
            error "Timeline current frame/time conflict: frame [dict get $timeline current_frame] is not nearest to time $currentTime"
        }
        if {[dict get $timeline loop] ni {once loop ping_pong} || [dict get $timeline state] ni {stopped paused playing}} {
            error "Timeline playback mode is invalid"}
        if {[dict get $timeline state] eq "playing" &&
            ([dict get $timeline current_frame] < [dict get $timeline range_first] ||
             [dict get $timeline current_frame] > [dict get $timeline range_last])} {
            error "Playing timeline current frame is outside playback range"
        }
        set rate [dict get $timeline rate]
        if {![string is double -strict $rate] || ![expr {abs(double($rate)) < Inf && $rate > 0 && $rate <= 10000}]} {
            error "Timeline rate is invalid"}
        if {[llength [dict get $timeline tracks]] > 64} {error "Too many timeline tracks"}
        set trackIds {}
        foreach track [dict get $timeline tracks] {
            if {[catch {dict size $track}] || ![dict exists $track id] || ![dict exists $track frames]} {error "Invalid timeline track"}
            set trackId [dict get $track id]
            if {![viewerIdValid $trackId] || $trackId in $trackIds} {error "Timeline track IDs must be unique"}
            lappend trackIds $trackId
            if {[llength [dict get $track frames]] != [llength $times]} {error "Timeline track frame count differs from times"}
            foreach layerId [dict get $track frames] {if {$layerId ne "" && ![viewerIdValid $layerId]} {error "Timeline frame layer ID is invalid"}}
        }
    }
    if {[dict get $d active_timeline_id] ne "" && [dict get $d active_timeline_id] ni $timelineIds} {
        error "Active timeline is missing"}
    if {[llength [dict get $d field_definitions]] > 128} {error "Too many field definitions"}
    set fieldIds {}
    foreach definition [dict get $d field_definitions] {
        if {[catch {dict size $definition}] || ![dict exists $definition id] || ![dict exists $definition kind]} {error "Invalid field definition"}
        set id [dict get $definition id]
        if {![viewerIdValid $id] || $id in $fieldIds} {error "Field definition IDs must be unique"}
        lappend fieldIds $id
        if {[dict get $definition kind] ni {lines pathlines slice isosurface}} {error "Unknown field definition kind"}
    }
    if {[dict get $d scene_mode] ni {automatic scientific}} {error "Invalid scene_mode"}
    foreach f {orthographic_height near_clip far_clip} {
        set value [dict get $d $f]
        if {![string is double -strict $value]||![expr {abs(double($value))<Inf}]||$value<0} {error "Invalid physical camera extent $f"}
    }
    if {([dict get $d near_clip]!=0||[dict get $d far_clip]!=0)&&([dict get $d near_clip]<=0||[dict get $d far_clip]<=[dict get $d near_clip])} {error "Invalid camera clipping interval"}
    foreach f {camera_position camera_target camera_up} {viewerTriple [dict get $d $f] $f}
    foreach f {working_plane_origin working_plane_normal working_plane_u_axis} {viewerTriple [dict get $d $f] $f}
    if {[dict get $d navigation_cube_visible] ni {0 1}} {error "Navigation cube visibility must be 0 or 1"}
    if {[dict get $d working_plane_visible] ni {0 1}} {error "Working plane visibility must be 0 or 1"}
    if {[dict get $d axes_world] ni {0 1}} {error "World axes visibility must be 0 or 1"}
    if {[dict get $d orientation_indicator_visible] ni {0 1}} {error "Orientation indicator visibility must be 0 or 1"}
    if {[dict get $d axes_local_layer] ne "" && ![viewerIdValid [dict get $d axes_local_layer]]} {error "Local axes layer ID is invalid"}
    if {![string is double -strict [dict get $d axes_size_pixels]] || [dict get $d axes_size_pixels] < 12 || [dict get $d axes_size_pixels] > 256} {error "Axes size must be 12..256 pixels"}
    foreach f {working_plane_normal working_plane_u_axis} {
        lassign [split [dict get $d $f] {;}] x y z
        if {[expr {double($x)**2+double($y)**2+double($z)**2}] == 0} {error "$f must be nonzero"}
    }
    lassign [split [dict get $d working_plane_normal] {;}] nx ny nz
    lassign [split [dict get $d working_plane_u_axis] {;}] ux uy uz
    set cx [expr {$ny*$uz-$nz*$uy}]
    set cy [expr {$nz*$ux-$nx*$uz}]
    set cz [expr {$nx*$uy-$ny*$ux}]
    if {[expr {$cx*$cx+$cy*$cy+$cz*$cz}] < 1e-20} {error "Working plane U axis must not be parallel to its normal"}
    if {[dict get $d camera_position] eq [dict get $d camera_target]} {error "Camera position and target must differ"}
    set up [split [dict get $d camera_up] {;}]
    if {[expr {double([lindex $up 0])**2+double([lindex $up 1])**2+double([lindex $up 2])**2}] == 0} {error "Camera up vector cannot be zero"}
    if {[dict get $d projection] ni {orthographic perspective}} {error "Invalid projection"}
    foreach field {lighting background_gradient} {if {[dict get $d $field] ni {0 1}} {error "$field must be 0 or 1"}}
    foreach field {background_rgb background_bottom_rgb lighting_color} {
        viewerTriple [dict get $d $field] $field
        foreach component [split [dict get $d $field] {;}] {
            if {$component < 0 || $component > 1} {error "$field components must be between 0 and 1"}
        }
    }
    viewerTriple [dict get $d lighting_direction] lighting_direction
    foreach field {lighting_ambient lighting_diffuse lighting_specular lighting_intensity} {
        set value [dict get $d $field]
        if {![string is double -strict $value] || [catch {expr {abs(double($value)) < Inf && $value >= 0 && $value <= 1}} valid] || !$valid} {error "$field must be between 0 and 1"}
    }
    if {[dict get $d lighting_lights] ne ""} {
        set lights [split [dict get $d lighting_lights] {;}]
        if {[llength $lights] < 1 || [llength $lights] > 4} {error "lighting_lights requires 1..4 lights"}
        foreach light $lights {
            set values [split $light ,]
            if {[llength $values] != 7} {error "Each directional light needs dx,dy,dz,r,g,b,intensity"}
            foreach value $values {if {![string is double -strict $value] || [catch {expr {abs(double($value)) < Inf}} valid] || !$valid} {error "Directional lights must be finite"}}
            foreach value [lrange $values 3 6] {if {$value < 0 || $value > 1} {error "Directional light color/intensity must be between 0 and 1"}}
        }
    }
    if {[dict get $d clip_box] ne ""} {
        set box [split [dict get $d clip_box] {;}]
        if {[llength $box] != 6} {error "clip_box must have minx;miny;minz;maxx;maxy;maxz"}
        foreach value $box {if {![string is double -strict $value] || [catch {expr {abs(double($value)) < Inf}} valid] || !$valid} {error "clip_box must be finite"}}
        for {set axis 0} {$axis < 3} {incr axis} {
            if {[lindex $box $axis] >= [lindex $box [expr {$axis+3}]]} {error "clip_box minima must precede maxima"}
        }
    }
    set markerIds {}
    set markerDefinitions [dict get $d marker_definitions]
    if {[llength $markerDefinitions] > 256} {error "Too many scene markers"}
    foreach marker $markerDefinitions {
        if {[catch {dict size $marker}]} {error "Marker definition must be a dictionary"}
        foreach field {id layer_id occurrence_index local_point kind size_pixels color visible} {
            if {![dict exists $marker $field]} {error "Marker definition missing $field"}
        }
        set id [dict get $marker id]
        if {![viewerIdValid $id] || $id in $markerIds} {error "Marker IDs must be unique"}
        lappend markerIds $id
        if {![viewerIdValid [dict get $marker layer_id]]} {error "Marker layer ID is invalid"}
        if {![string is integer -strict [dict get $marker occurrence_index]] || [dict get $marker occurrence_index] < 0} {error "Marker occurrence index is invalid"}
        viewerTriple [dict get $marker local_point] marker_local_point
        viewerTriple [dict get $marker color] marker_color
        if {[dict get $marker kind] ni {point cross normal tangent}} {error "Marker kind is invalid"}
        if {[dict get $marker visible] ni {0 1}} {error "Marker visibility is invalid"}
        set size [dict get $marker size_pixels]
        if {![string is double -strict $size] || $size <= 0 || $size > 64} {error "Marker size must be in (0,64]"}
    }
    if {[dict get $d axes_reference_marker] ne "" && [dict get $d axes_reference_marker] ni $markerIds} {error "Reference axes marker is missing"}
    set measureIds {}
    set measureDefinitions [dict get $d measurement_definitions]
    if {[llength $measureDefinitions] > 128} {error "Too many scene measurements"}
    foreach measurement $measureDefinitions {
        if {[catch {dict size $measurement}]} {error "Measurement definition must be a dictionary"}
        foreach field {id kind marker_a marker_b visible show_value color size_pixels line_width} {
            if {![dict exists $measurement $field]} {error "Measurement definition missing $field"}
        }
        set id [dict get $measurement id]
        if {![viewerIdValid $id] || $id in $measureIds} {error "Measurement IDs must be unique"}
        lappend measureIds $id
        if {[dict get $measurement marker_a] ni $markerIds || [dict get $measurement marker_b] ni $markerIds} {error "Measurement references an unknown marker"}
        if {[dict get $measurement kind] ni {distance delta_x delta_y delta_z angle}} {error "Measurement kind is invalid"}
        if {[dict get $measurement kind] eq "angle" && (![dict exists $measurement marker_c] || [dict get $measurement marker_c] ni $markerIds)} {error "Angle measurement needs a third marker"}
        foreach field {visible show_value} {if {[dict get $measurement $field] ni {0 1}} {error "Measurement $field is invalid"}}
        viewerTriple [dict get $measurement color] measurement_color
        foreach field {size_pixels line_width} {
            set value [dict get $measurement $field]
            if {![string is double -strict $value] || $value <= 0 || $value > 64} {error "Measurement $field must be in (0,64]"}
        }
    }
    set curveIds {}
    set curves [dict get $d curve_definitions]
    if {[llength $curves] > 128} {error "Too many derived curves"}
    foreach curve $curves {
        if {[catch {dict size $curve}]} {error "Curve definition must be a dictionary"}
        foreach field {id kind source_layer occurrence_index origin normal u_axis visible color line_width opacity join_tolerance} {
            if {![dict exists $curve $field]} {error "Curve definition missing $field"}
        }
        set id [dict get $curve id]
        if {![viewerIdValid $id] || $id in $curveIds} {error "Curve IDs must be unique"}
        lappend curveIds $id
        if {[dict get $curve kind] ni {section profile projection}} {error "Curve kind is invalid"}
        if {![viewerIdValid [dict get $curve source_layer]]} {error "Curve source layer is invalid"}
        if {![string is integer -strict [dict get $curve occurrence_index]] || [dict get $curve occurrence_index] < 0} {error "Curve source occurrence is invalid"}
        foreach field {origin normal u_axis color} {viewerTriple [dict get $curve $field] $field}
        if {[dict get $curve visible] ni {0 1}} {error "Curve visibility is invalid"}
        foreach field {line_width opacity join_tolerance} {
            set value [dict get $curve $field]
            if {![string is double -strict $value] || [catch {expr {abs(double($value)) < Inf}} valid] || !$valid} {error "Curve $field must be finite"}
        }
        if {[dict get $curve line_width] <= 0 || [dict get $curve opacity] < 0 || [dict get $curve opacity] > 1 || [dict get $curve join_tolerance] <= 0} {error "Curve style/tolerance is out of range"}
    }
    set clips [dict get $d clipping_planes]
    set provider [viewerProviderDefinition $moduleId $viewerId]
    if {$provider eq ""} {error "Viewer Provider module is disabled"}
    set capabilities [splitList [dict get $provider capabilities]]
    if {[llength $capabilities] && "camera" ni $capabilities} {
        set base [viewerSceneDefaults]
        foreach f {camera_position camera_target camera_up projection} {
            if {[dict get $d $f] ne [dict get $base $f]} {error "Viewer backend does not declare camera control"}
        }
    }
    if {$clips ne "" && [llength $capabilities] && "clipping" ni $capabilities} {error "Viewer backend does not declare clipping"}
    if {$clips ne ""} {
        foreach plane [split $clips {;}] {
            set nums [split $plane ,]
            if {[llength $nums] != 4} {error "Clipping plane requires nx,ny,nz,d"}
            foreach n $nums {if {![string is double -strict $n] || [catch {expr {abs(double($n)) < Inf}} ok] || !$ok} {error "Clipping plane must be finite"}}
            if {[expr {double([lindex $nums 0])**2+double([lindex $nums 1])**2+double([lindex $nums 2])**2}] == 0} {error "Clipping plane normal cannot be zero"}
        }
    }
    return $d
}
proc ::GX::viewerSceneGet {moduleId viewerId} {
    variable viewerScene
    viewerRequireProvider $moduleId $viewerId
    if {[info exists viewerScene($moduleId,$viewerId)]} {return $viewerScene($moduleId,$viewerId)}
    return [viewerSceneDefaults]
}

proc ::GX::viewerArtifactResolve {relative expectedSha} {
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} {error "Viewer artifact requires an open session"}
    if {$relative eq "" || [file pathtype $relative] ne "relative" || [regexp {[
]} $relative]} {error "Viewer artifact path must be session-relative"}
    set root [file normalize $currentSession]
    set path [file normalize [file join $root $relative]]
    if {![string match "$root/*" $path]} {error "Viewer artifact escapes session"}
    # Reject symlink components: lexical normalization alone cannot prevent
    # a link inside the session from referring to an outside file.
    set rel [string range $path [expr {[string length $root]+1}] end]
    set probe $root
    foreach component [file split $rel] {
        set probe [file join $probe $component]
        if {[file exists $probe] && [file type $probe] eq "link"} {error "Viewer artifact symlinks are not allowed"}
    }
    if {![file isfile $path]} {error "Viewer artifact does not exist: $relative"}
    if {![regexp {^[0-9a-fA-F]{64}$} $expectedSha]} {error "Viewer artifact requires SHA-256"}
    set actual [sha256File $path]
    if {![string equal -nocase $actual $expectedSha]} {error "Viewer artifact SHA-256 mismatch"}
    return $path
}
proc ::GX::viewerArtifactRegister {relative} {
    variable currentSession
    if {$currentSession eq ""} {error "Viewer artifact requires an open session"}
    set root [file normalize $currentSession]
    set path [file normalize [file join $root $relative]]
    if {![string match "$root/*" $path] || ![file isfile $path]} {error "Viewer artifact must be an existing session file"}
    set rel [string range $path [expr {[string length $root]+1}] end]
    set probe $root
    foreach component [file split $rel] {
        set probe [file join $probe $component]
        if {[file exists $probe] && [file type $probe] eq "link"} {error "Viewer artifact symlinks are not allowed"}
    }
    set sha [sha256File $path]
    viewerArtifactResolve $relative $sha
    return [dict create resource_path $relative sha256 $sha]
}
proc ::GX::viewerDatasetVariableCheck {datasetId variableId} {
    if {$variableId eq ""} {return}
    set v [datasetVariableById $datasetId $variableId]
    if {![dict get $v enabled]} {error "Viewer cannot bind Use=no variable $variableId"}
}

proc ::GX::viewerLayerPrepare {moduleId viewerId layerId fields {resourceContext {}}} {
    variable viewerLayer
    viewerRequireProvider $moduleId $viewerId
    if {![viewerIdValid $layerId]} {error "Invalid viewer layer ID"}
    set defaults [dict create kind "" source_mode "" dataset_id "" resource_path "" sha256 "" format "" format_version "" source_path_hint "" x_variable_id "" y_variable_id "" z_variable_id "" visible 1 opacity 1 colormap "" scalar_range "" color_array "" scalar_array "" vector_array "" radius_array "" opacity_array "" tube_radius 0 isovalues "" volume_transfer "" volume_sample_distance 0.05 layer_order 0 source_dataset_id "" source_dataset_sha256 "" source_update_policy strict representation surface base_color {0.78;0.82;0.9} line_width 1 point_size 4 backface_culling 0 scalar_coloring 0 local_transform "" texture {}]
    set d [dict merge $defaults $fields]
    foreach k [dict keys $d] {if {![dict exists $defaults $k]} {error "Unknown viewer layer field $k"}}
    if {[dict get $d texture] ne {}} {native3DLayerTextureValidate [dict get $d texture] $d}
    set kind [dict get $d kind]
    if {$kind ni {points surface triangle_mesh trajectory geometry isosurface volume}} {error "Unknown viewer layer kind $kind"}
    set declared [viewerProviderDefinition $moduleId $viewerId]
    if {$declared eq ""} {error "Viewer Provider module is disabled"}
    set supported [splitList [dict get $declared supported_primitives]]
    if {[llength $supported] && $kind ni $supported} {error "Provider does not support $kind"}
    set capabilities [splitList [dict get $declared capabilities]]
    if {[llength $capabilities] && $layerId ni [viewerLayerIds $moduleId $viewerId] && [llength [viewerLayerIds $moduleId $viewerId]] && "multilayer" ni $capabilities} {error "Viewer backend does not declare multilayer"}
    if {[llength $capabilities] && [dict get $d opacity] != 1 && "opacity" ni $capabilities} {error "Viewer backend does not declare opacity"}
    if {[llength $capabilities] && ([dict get $d scalar_range] ne "" || [dict get $d colormap] ne "") && "scalar" ni $capabilities} {error "Viewer backend does not declare scalar display"}
    if {[dict get $d source_mode] ni {dataset artifact}} {error "Viewer layer source_mode must be dataset or artifact"}
    if {[dict get $d source_mode] eq "artifact"} {
        if {$resourceContext eq {}} {
            viewerArtifactResolve [dict get $d resource_path] [dict get $d sha256]
        } else {
            if {[dict keys $resourceContext] ne {temporary_root}} {error {Invalid temporary layer resource context}}
            set root [file normalize [dict get $resourceContext temporary_root]]
            set path [file normalize [dict get $d resource_path]]
            if {![file isdirectory $root]||![string match "$root/*" $path]||![file isfile $path]||[file type $path] ne {file}||[sha256File $path] ne [dict get $d sha256]} {error {Temporary native layer resource failed containment or SHA validation}}
            set probe $path
            while {$probe ne $root} {if {[file type $probe] eq {link}} {error {Temporary native layer resource cannot contain symlinks}};set probe [file dirname $probe]}
        }
        if {[dict get $d format] eq "" || [dict get $d format_version] eq ""} {error "Artifact format and version are required"}
        set formats [splitList [dict get $declared artifact_formats]]
        if {[llength $formats] && [dict get $d format] ni $formats} {error "Provider does not support artifact format"}
    } else {
        set dataset [dict get $d dataset_id]
        if {$dataset eq ""} {error "Viewer layer requires an existing dataset ID"}
        set payload [sessionInspectionDatasetPayload $dataset]
        foreach axis {x y z} {viewerDatasetVariableCheck $dataset [dict get $d [set axis]_variable_id]}
        if {[dict get $payload format] eq "csv" && $kind in {points trajectory} &&
            ([dict get $d x_variable_id] eq "" || [dict get $d y_variable_id] eq "" || [dict get $d z_variable_id] eq "")} {
            error "$kind requires X/Y/Z stable variable IDs"
        }
    }
    if {[dict get $d visible] ni {0 1}} {error "visible must be 0 or 1"}
    if {![string is integer -strict [dict get $d layer_order]]} {error "layer_order must be an integer"}
    if {[dict get $d representation] ni {surface wireframe surface_edges points}} {error "Invalid layer representation"}
    viewerTriple [dict get $d base_color] base_color
    foreach value [split [dict get $d base_color] {;}] {if {$value < 0 || $value > 1} {error "base_color components must be between 0 and 1"}}
    foreach field {line_width point_size} {
        set value [dict get $d $field]
        if {![string is double -strict $value] || [catch {expr {abs(double($value)) < Inf && $value > 0 && $value <= 64}} valid] || !$valid} {error "$field must be in (0,64]"}
    }
    foreach field {backface_culling scalar_coloring} {if {[dict get $d $field] ni {0 1}} {error "$field must be 0 or 1"}}
    if {[dict get $d local_transform] ne ""} {
        set matrix [split [dict get $d local_transform] {;}]
        if {[llength $matrix] != 16} {error "local_transform requires 16 column-major values"}
        foreach value $matrix {
            if {![string is double -strict $value] || [catch {expr {abs(double($value)) < Inf}} valid] || !$valid} {error "local_transform must be finite"}
        }
        foreach {index expected} {3 0 7 0 11 0 15 1} {
            if {[expr {abs(double([lindex $matrix $index])-$expected)}] > 1e-9} {error "local_transform must be affine"}
        }
    }
    if {[dict get $d source_update_policy] ni {strict snapshot}} {error "Invalid source update policy"}
    if {[dict get $d source_update_policy] eq "snapshot" && [dict get $d source_mode] ne "artifact"} {
        error "Snapshot source policy requires a Session artifact"
    }
    if {[dict get $d source_dataset_id] ne "" && [dict get $d source_update_policy] eq "strict"} {
        set source [sessionInspectionDatasetPayload [dict get $d source_dataset_id]]
        if {![string equal -nocase [dict get $source sha256] [dict get $d source_dataset_sha256]]} {
            error "Viewer source Dataset '[dict get $d source_dataset_id]' changed since scene construction"
        }
    }
    foreach field {color_array scalar_array vector_array radius_array opacity_array} {
        if {[string length [dict get $d $field]] > 256 || [regexp {[\r\n\x00]} [dict get $d $field]]} {
            error "$field must be a single-line scientific array name up to 256 characters"
        }
    }
    set tubeRadius [dict get $d tube_radius]
    if {![string is double -strict $tubeRadius] ||
        [catch {expr {abs(double($tubeRadius)) < Inf && double($tubeRadius) >= 0}} valid] || !$valid} {
        error "tube_radius must be finite and nonnegative"
    }
    if {$kind eq "isosurface"} {
        if {[dict get $d scalar_array] eq "" || [dict get $d isovalues] eq ""} {
            error "Isosurface requires scalar_array and isovalues"
        }
        set levels [split [dict get $d isovalues] {;}]
        if {[llength $levels] < 1 || [llength $levels] > 32} {error "Isosurface requires 1..32 values"}
        foreach level $levels {
            if {![string is double -strict $level] ||
                [catch {expr {abs(double($level)) < Inf}} finite] || !$finite} {
                error "Isosurface values must be finite"
            }
        }
    }
    if {$kind eq "volume"} {
        if {[dict get $d source_mode] ne "artifact" || [dict get $d format] ne "vti" ||
            [dict get $d scalar_array] eq ""} {error "Volume requires a VTI artifact and scalar_array"}
        set transfer [split [dict get $d volume_transfer] {;}]
        if {[llength $transfer] < 2 || [llength $transfer] > 16} {error "Volume requires 2..16 transfer points"}
        set previous -Inf
        foreach point $transfer {
            set components [split $point {,}]
            if {[llength $components] != 5} {error "Volume transfer point needs scalar,R,G,B,opacity"}
            foreach value $components {
                if {![string is double -strict $value] ||
                    [catch {expr {abs(double($value)) < Inf}} finite] || !$finite} {
                    error "Volume transfer values must be finite"
                }
            }
            set scalar [lindex $components 0]
            if {$scalar <= $previous} {error "Volume transfer scalars must increase"}
            foreach value [lrange $components 1 end] {
                if {$value < 0 || $value > 1} {error "Volume transfer color and opacity must be in \[0,1\]"}
            }
            set previous $scalar
        }
        set distance [dict get $d volume_sample_distance]
        if {![string is double -strict $distance] ||
            [catch {expr {abs(double($distance)) < Inf && double($distance) > 0}} valid] || !$valid} {
            error "Volume sample distance must be positive and finite"
        }
    }
    set opacity [dict get $d opacity]
    if {![string is double -strict $opacity] || [catch {expr {double($opacity)>=0 && double($opacity)<=1}} ok] || !$ok} {error "opacity must be between 0 and 1"}
    set range [dict get $d scalar_range]
    if {$range ne ""} {
        set r [split $range {;}]
        if {[llength $r] != 2 || ![string is double -strict [lindex $r 0]] || ![string is double -strict [lindex $r 1]]} {error "scalar_range must be finite min;max with min < max"}
        if {[catch {expr {abs(double([lindex $r 0])) < Inf && abs(double([lindex $r 1])) < Inf && double([lindex $r 0]) < double([lindex $r 1])}} valid] || !$valid} {error "scalar_range must be finite min;max with min < max"}
    }
    foreach v [dict values $d] {if {[regexp {[
]} $v]} {error "Viewer layer fields must be single-line"}}
    return $d
}
proc ::GX::viewerLayerSet {moduleId viewerId layerId fields} {
    variable viewerLayer
    set d [viewerLayerPrepare $moduleId $viewerId $layerId $fields]
    set viewerLayer($moduleId,$viewerId,$layerId) $d
    return $d
}
proc ::GX::viewerLayerGet {moduleId viewerId layerId} {
    variable viewerLayer
    if {![info exists viewerLayer($moduleId,$viewerId,$layerId)]} {error "Unknown viewer layer $layerId"}
    return $viewerLayer($moduleId,$viewerId,$layerId)
}
proc ::GX::viewerLayerIds {moduleId viewerId} {
    variable viewerLayer
    set out {}
    foreach key [array names viewerLayer "$moduleId,$viewerId,*"] {lappend out [string range $key [string length "$moduleId,$viewerId,"] end]}
    return [lsort $out]
}
proc ::GX::viewerLayerRemove {moduleId viewerId layerId} {
    variable viewerLayer
    variable viewerAttribute
    catch {unset viewerLayer($moduleId,$viewerId,$layerId)}
    array unset viewerAttribute "$moduleId,$viewerId,$layerId,*"
}
proc ::GX::viewerAttributeSet {moduleId viewerId layerId attributeId fields} {
    variable viewerAttribute
    set layer [viewerLayerGet $moduleId $viewerId $layerId]
    if {![viewerIdValid $attributeId]} {error "Invalid viewer attribute ID"}
    set defaults [dict create kind "" variable_ids "" unit "" semantic_role "" resource_path "" sha256 "" format "" format_version ""]
    set d [dict merge $defaults $fields]
    foreach k [dict keys $d] {if {![dict exists $defaults $k]} {error "Unknown viewer attribute field $k"}}
    set kind [dict get $d kind]
    if {$kind ni {scalar vector}} {error "Attribute kind must be scalar or vector"}
    set provider [viewerProviderDefinition $moduleId $viewerId]
    if {$provider eq ""} {error "Viewer Provider module is disabled"}
    set capabilities [splitList [dict get $provider capabilities]]
    if {[llength $capabilities] && $kind ni $capabilities} {error "Viewer backend does not declare $kind attributes"}
    set ids [splitList [dict get $d variable_ids]]
    if {[dict get $layer source_mode] eq "dataset"} {
        if {[llength $ids] != [expr {$kind eq "scalar" ? 1 : 3}]} {error "$kind attribute requires stable variable IDs"}
        foreach id $ids {viewerDatasetVariableCheck [dict get $layer dataset_id] $id}
    } else {
        if {[dict get $d resource_path] eq ""} {error "Artifact layer attribute requires a resource"}
        viewerArtifactResolve [dict get $d resource_path] [dict get $d sha256]
        if {[dict get $d format] eq "" || [dict get $d format_version] eq ""} {error "Attribute artifact format/version required"}
        if {[llength $ids]} {error "Artifact attribute cannot bind dataset variable IDs"}
    }
    if {[regexp {[
]} [dict values $d]]} {error "Viewer attribute fields must be single-line"}
    # semantic_role is a registry key, not a CFD-specific CORE enum.
    set viewerAttribute($moduleId,$viewerId,$layerId,$attributeId) $d
    return $d
}
proc ::GX::viewerAttributeRemove {moduleId viewerId layerId attributeId} {
    variable viewerAttribute
    catch {unset viewerAttribute($moduleId,$viewerId,$layerId,$attributeId)}
}
proc ::GX::viewerAttributeIds {moduleId viewerId layerId} {
    variable viewerAttribute
    set out {}
    foreach key [array names viewerAttribute "$moduleId,$viewerId,$layerId,*"] {lappend out [string range $key [string length "$moduleId,$viewerId,$layerId,"] end]}
    return [lsort $out]
}
proc ::GX::viewerSceneResolve {moduleId viewerId} {
    variable viewerAttribute
    set provider [viewerProviderDefinition $moduleId $viewerId]
    if {$provider eq ""} {error "Viewer Provider module is disabled"}
    set layers {}
    foreach layerId [viewerLayerIds $moduleId $viewerId] {
        set layer [viewerLayerSet $moduleId $viewerId $layerId [viewerLayerGet $moduleId $viewerId $layerId]]
        if {[dict get $layer source_mode] eq "artifact"} {
            dict set layer absolute_path [viewerArtifactResolve [dict get $layer resource_path] [dict get $layer sha256]]
        } else {
            set ds [dict get $layer dataset_id]
            foreach axis {x y z} {viewerDatasetVariableCheck $ds [dict get $layer [set axis]_variable_id]}
            dict set layer dataset_path [dict get [sessionInspectionDatasetPayload $ds] path]
        }
        set attrs {}
        foreach attr [viewerAttributeIds $moduleId $viewerId $layerId] {
            set a [viewerAttributeSet $moduleId $viewerId $layerId $attr $viewerAttribute($moduleId,$viewerId,$layerId,$attr)]
            if {[dict get $a resource_path] ne ""} {dict set a absolute_path [viewerArtifactResolve [dict get $a resource_path] [dict get $a sha256]]}
            set role [dict get $a semantic_role]
            if {$role ne ""} {
                set definition [semanticRegistryDefinition $role]
                dict set a semantic_registry_available [expr {$definition ne "" ? 1 : 0}]
                if {$definition ne ""} {dict set a semantic_label [dict get $definition label]}
            }
            dict set attrs $attr $a
        }
        dict set layer attributes $attrs
        dict set layers $layerId $layer
    }
    return [dict create provider $provider view [viewerSceneSet $moduleId $viewerId [viewerSceneGet $moduleId $viewerId]] layers $layers]
}
proc ::GX::viewerBackendRegister {backendId commandPrefix} {
    variable viewerBackend
    if {![viewerIdValid $backendId] || ![llength $commandPrefix]} {error "Invalid viewer backend registration"}
    set viewerBackend($backendId) $commandPrefix
}
proc ::GX::viewerBackendScriptPath {moduleId relative} {
    if {$relative eq "" || [file pathtype $relative] ne "relative" ||
        [file extension $relative] ne ".tcl" || [regexp {[\r\n\x00]} $relative]} {
        error "$moduleId: backend_script must be a relative Tcl file"
    }
    if {[lsearch -exact [file split $relative] ..] >= 0} {
        error "$moduleId: backend_script cannot traverse outside its module"
    }
    set descriptor [moduleField $moduleId descriptor ""]
    if {$descriptor eq ""} { error "$moduleId: module descriptor is unavailable" }
    set root [file normalize [file dirname $descriptor]]
    set path [file normalize [file join $root $relative]]
    if {![string match "$root/*" $path] || ![file isfile $path]} {
        error "$moduleId: backend_script is missing or outside its module"
    }
    set probe $root
    foreach component [file split $relative] {
        set probe [file join $probe $component]
        if {[file type $probe] eq "link"} { error "$moduleId: backend_script symlinks are not allowed" }
    }
    return $path
}
proc ::GX::viewerBackendEnsure {moduleId viewerId} {
    variable viewerBackend
    pluginRuntimeTryPending $moduleId
    set provider [viewerProviderDefinition $moduleId $viewerId]
    if {$provider eq ""} { error "Viewer Provider module is disabled" }
    set backend [dict get $provider backend]
    if {[info exists viewerBackend($backend)]} {pluginRuntimeNoteLoaded $moduleId; return $viewerBackend($backend) }
    pluginRuntimeGuardNewLoad $moduleId
    set activationApi [string trim [dict get $provider activation_api]]
    set backendScript [string trim [dict get $provider backend_script]]
    if {$activationApi ne ""} {
        if {![llength [info commands ::GX::modulePublicApiActivate]]} {
            error "Viewer backend $backend activation requires the CORE public-API activation service"
        }
        if {[catch {modulePublicApiActivate $moduleId $activationApi} err opts]} {
            return -options $opts "Viewer backend $backend activation through $moduleId/$activationApi failed: $err"
        }
    } elseif {$backendScript ne ""} {
        set path [viewerBackendScriptPath $moduleId $backendScript]
        if {[catch {source $path} err opts]} {
            return -options $opts "Viewer backend $backend activation through $moduleId/$backendScript failed: $err"
        }
    }
    if {![info exists viewerBackend($backend)]} {
        if {$activationApi ne ""} {
            error "Viewer backend $backend is unavailable after activating $moduleId/$activationApi"
        }
        if {$backendScript ne ""} {
            error "Viewer backend $backend is unavailable after loading $moduleId/$backendScript"
        }
        error "Viewer backend $backend is unavailable"
    }
    pluginRuntimeNoteLoaded $moduleId
    return $viewerBackend($backend)
}
proc ::GX::viewerOpen {moduleId viewerId {context {}}} {
    if {![viewerProviderEnabled $moduleId $viewerId]} {error {This Viewer is disabled in Configuration → Modules → Viewers. Existing Workspaces and scientific services are preserved.}}
    if {[catch {dict size $context}]} { error "Viewer open context must be a dictionary" }
    set command [viewerBackendEnsure $moduleId $viewerId]
    set scene [viewerSceneResolve $moduleId $viewerId]
    dict set scene open_context $context
    dict set scene dataset_private_context [_datasetPrivateModuleContext $moduleId]
    set result [_datasetPrivateWithModule $moduleId $command open $scene]
    if {[llength [info commands documentationBrowserAttachViewerHelp]]} {documentationBrowserAttachViewerHelp $moduleId $viewerId $result}
    return $result
}
proc ::GX::viewerRerender {moduleId viewerId} {
    if {![viewerProviderEnabled $moduleId $viewerId]} {error {Viewer presentation is disabled}}
    set command [viewerBackendEnsure $moduleId $viewerId]
    set scene [viewerSceneResolve $moduleId $viewerId]
    return [{*}$command rerender $scene]
}

proc ::GX::manifestStringV2_before_plot_variant {} {
    variable viewerScene; variable viewerLayer; variable viewerAttribute
    set out [::GX::manifestStringV2_before_viewer_provider]
    append out "\n\[viewer_provider_api\]\n"; appendKV out version 1
    set i 0
    foreach key [lsort [array names viewerScene]] {
        incr i; lassign [split $key ,] module viewer
        append out "\n\[viewer_scene.$i\]\n";appendKV out module_id $module;appendKV out viewer_id $viewer
        dict for {f v} $viewerScene($key) {appendKV out $f $v}
    }
    append out "\n\[viewer_scenes\]\n";appendKV out count $i
    set i 0
    foreach key [lsort [array names viewerLayer]] {
        incr i;lassign [split $key ,] module viewer layer
        append out "\n\[viewer_layer.$i\]\n"
        foreach {f v} [concat [list module_id $module viewer_id $viewer layer_id $layer] $viewerLayer($key)] {appendKV out $f $v}
    }
    append out "\n\[viewer_layers\]\n";appendKV out count $i
    set i 0
    foreach key [lsort [array names viewerAttribute]] {
        incr i;lassign [split $key ,] module viewer layer attribute
        append out "\n\[viewer_attribute.$i\]\n"
        foreach {f v} [concat [list module_id $module viewer_id $viewer layer_id $layer attribute_id $attribute] $viewerAttribute($key)] {appendKV out $f $v}
    }
    append out "\n\[viewer_attributes\]\n";appendKV out count $i
    return $out
}
proc ::GX::viewerReadIndexed {ini section fields} {
    set out {}
    set n [expr {[dict exists $ini $section.count] ? [dict get $ini $section.count] : 0}]
    if {![string is integer -strict $n] || $n < 0} {error "Invalid $section count"}
    set singular [string range $section 0 end-1]
    for {set i 1} {$i <= $n} {incr i} {
        set d [dict create]
        foreach f $fields {set k "$singular.$i.$f";if {[dict exists $ini $k]} {dict set d $f [dict get $ini $k]}}
        lappend out $d
    }
    return $out
}
proc ::GX::loadManifestV2_before_plot_variant {path} {
    variable viewerScene; variable viewerLayer; variable viewerAttribute
    array unset viewerScene *;array unset viewerLayer *;array unset viewerAttribute *
    ::GX::loadManifestV2_before_viewer_provider $path
    set ini [parseIni $path]
    foreach d [viewerReadIndexed $ini viewer_scenes {module_id viewer_id camera_position camera_target camera_up projection navigation_cube_visible orthographic_height near_clip far_clip clipping_planes clip_box marker_definitions measurement_definitions curve_definitions timeline_definitions active_timeline_id field_definitions axes_world axes_local_layer axes_reference_marker axes_size_pixels orientation_indicator_visible scene_mode background_rgb background_bottom_rgb background_gradient lighting lighting_ambient lighting_diffuse lighting_specular lighting_direction lighting_color lighting_intensity lighting_lights working_plane_origin working_plane_normal working_plane_u_axis working_plane_visible}] {
        foreach k {module_id viewer_id} {if {![dict exists $d $k]} {error "Incomplete viewer scene"}}
        set module [dict get $d module_id];set viewer [dict get $d viewer_id]
        foreach k {module_id viewer_id} {dict unset d $k}
        set viewerScene($module,$viewer) $d
    }
    foreach d [viewerReadIndexed $ini viewer_layers {module_id viewer_id layer_id kind source_mode dataset_id resource_path sha256 format format_version source_path_hint x_variable_id y_variable_id z_variable_id visible opacity colormap scalar_range color_array scalar_array vector_array radius_array opacity_array tube_radius isovalues volume_transfer volume_sample_distance layer_order source_dataset_id source_dataset_sha256 source_update_policy representation base_color line_width point_size backface_culling scalar_coloring local_transform texture}] {
        foreach k {module_id viewer_id layer_id} {if {![dict exists $d $k]} {error "Incomplete viewer layer"}}
        set module [dict get $d module_id];set viewer [dict get $d viewer_id];set layer [dict get $d layer_id]
        foreach k {module_id viewer_id layer_id} {dict unset d $k}
        set viewerLayer($module,$viewer,$layer) $d
    }
    foreach d [viewerReadIndexed $ini viewer_attributes {module_id viewer_id layer_id attribute_id kind variable_ids unit semantic_role resource_path sha256 format format_version}] {
        foreach k {module_id viewer_id layer_id attribute_id} {if {![dict exists $d $k]} {error "Incomplete viewer attribute"}}
        set module [dict get $d module_id];set viewer [dict get $d viewer_id];set layer [dict get $d layer_id];set attribute [dict get $d attribute_id]
        foreach k {module_id viewer_id layer_id attribute_id} {dict unset d $k}
        set viewerAttribute($module,$viewer,$layer,$attribute) $d
    }
}
proc ::GX::writeStandardRuntimeConfig_before_graph_workflow {moduleId} {
    set path [::GX::writeStandardRuntimeConfig_before_viewer_provider $moduleId]
    set fd [open $path a];fconfigure $fd -encoding utf-8 -translation lf
    set n 0
    foreach viewer [viewerProviderIds $moduleId] {
        if {![moduleIsEnabled $moduleId]} continue
        set scene [viewerSceneResolve $moduleId $viewer]
        incr n;puts $fd "\n\[viewer_runtime.$n\]"
        putKV $fd module_id $moduleId;putKV $fd viewer_id $viewer
        putKV $fd backend [dict get $scene provider backend]
        dict for {f v} [dict get $scene view] {putKV $fd $f $v}
        set layers [dict get $scene layers]
        putKV $fd layer_count [dict size $layers]
        dict for {layerId layer} $layers {
            puts $fd "\n\[viewer_runtime.$n.layer.$layerId\]"
            dict for {f v} $layer {if {$f ne "attributes"} {putKV $fd $f $v}}
            dict for {attrId attr} [dict get $layer attributes] {
                puts $fd "\n\[viewer_runtime.$n.layer.$layerId.attribute.$attrId\]"
                dict for {f v} $attr {putKV $fd $f $v}
            }
        }
    }
    puts $fd "\n\[viewer_runtime\]";putKV $fd api_version 1;putKV $fd count $n
    close $fd
    return $path
}
proc ::GX::defaults_before_plot_variant {} {
    ::GX::defaults_before_viewer_provider
    array unset ::GX::viewerScene *
    array unset ::GX::viewerLayer *
    array unset ::GX::viewerAttribute *
}

# Generic Viewer tab. Providers own their renderer and optional richer UI.
proc ::GX::launchGui_before_plot_variant {} {
    ::GX::launchGui_before_viewer_provider
    if {[winfo exists .top.nb]} {viewerGuiBuild .top.nb}
}
