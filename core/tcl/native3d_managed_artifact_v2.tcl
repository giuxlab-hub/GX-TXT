# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only presentation of a live process-owned temporary artifact. No Session,
# Dataset, Workspace, scene persistence or new rendering/storage authority.
proc ::GX::_native3DManagedArtifactIdentity {source} {
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Managed artifact binding requires the trusted user/admin host}}
    foreach field {kind module provider allocation_id path sha256 format source_identity} {if {![dict exists $source $field]} {error "Managed artifact binding requires '$field'"}}
    foreach field [dict keys $source] {if {$field ni {kind module provider allocation_id path sha256 format source_identity layer view}} {error "Unsupported managed artifact field '$field'"}}
    set allocation [resourceManagementInspect [dict get $source allocation_id]]
    if {![dict get $allocation managed] || [dict get $allocation kind] ne {directory} || [dict get $allocation owner_pid]!=[pid] || ![dict get $allocation owner_alive] || [dict get $allocation released] || [dict get $allocation removed]} {error {Managed artifact requires a live directory allocation owned by this host process}}
    set root [file normalize [dict get $allocation path]]
    file lstat $root status
    if {$status(type) ne {directory} || [list $status(dev) $status(ino)] ne [dict get $allocation identity]} {error {Managed artifact allocation identity changed}}
    set raw [dict get $source path]
    if {[file pathtype $raw] ne {absolute}} {error {Managed artifact path must be absolute within its allocation}}
    if {[regexp {(^|/)\.\.?(/|$)} $raw]} {error {Managed artifact paths must be canonical without dot components}}
    set path [file normalize $raw]
    if {![string match "$root/*" $path]} {error {Managed artifact escapes its allocation}}
    set probe $raw
    while {1} {
        file lstat $probe status
        if {$status(type) eq {link}} {error {Managed artifact paths cannot contain symlinks}}
        set parent [file dirname $probe]
        if {$parent eq $probe} break
        set probe $parent
    }
    set probe $path
    while {1} {
        file lstat $probe status
        if {$status(type) eq {link}} {error {Managed artifact paths cannot contain symlinks}}
        if {$probe eq $root} break
        set probe [file dirname $probe]
    }
    file lstat $path status
    if {$status(type) ne {file} || $status(nlink)!=1 || $status(size)<1 || $status(size)>16777216} {error {Managed artifact requires one regular file of at most16 MiB}}
    set sha [string tolower [dict get $source sha256]]
    if {![regexp {^[0-9a-f]{64}$} $sha] || [sha256File $path] ne $sha} {error {Managed artifact SHA-256 changed}}
    if {[dict get $source format] ni {vtp vtu vti stl obj}} {error {Managed artifact requires an existing native geometry format}}
    set identity [dict get $source source_identity]
    if {[catch {dict size $identity}] || [dict size $identity]>4} {error {Managed artifact source identity must be a bounded dictionary}}
    foreach field {api_id reference sha256} {if {![dict exists $identity $field]} {error "Managed artifact source identity requires '$field'"}}
    dict for {key value} $identity {
        if {$key ni {api_id reference sha256 revision} || [string length $value]>512 || [regexp {[\x00\r\n]} $value]} {error {Invalid managed artifact source attribution}}
    }
    if {![regexp {^[A-Z][A-Z0-9_]*_v[0-9]+$} [dict get $identity api_id]] || ![regexp {^[0-9a-fA-F]{64}$} [dict get $identity sha256]] || [dict get $identity reference] eq {}} {error {Invalid managed artifact source API/reference/SHA}}
    return [dict create allocation_id [dict get $allocation id] root $root allocation_identity [dict get $allocation identity] path $path sha256 $sha source_identity $identity]
}
proc ::GX::_native3DManagedArtifactScene {source} {
    set identity [_native3DManagedArtifactIdentity $source]
    set module [dict get $source module];set provider [dict get $source provider]
    set presentation [datasetPublicationV2DictDefault $source layer {}]
    foreach field [dict keys $presentation] {if {$field ni {scalar_array scalar_coloring colormap scalar_range color_array representation base_color line_width point_size opacity visible}} {error "Unsupported managed artifact presentation '$field'"}}
    set layer [viewerLayerPrepare $module $provider managed_artifact [dict merge $presentation [dict create \
        kind surface source_mode artifact resource_path [dict get $identity path] sha256 [dict get $identity sha256] \
        format [dict get $source format] format_version 1]] [dict create temporary_root [dict get $identity root]]]
    dict set layer absolute_path [dict get $identity path]
    set fields [datasetPublicationV2DictDefault $source view {}]
    foreach field [dict keys $fields] {
        if {$field ni {camera_position camera_target camera_up projection orthographic_height near_clip far_clip axes_world orientation_indicator_visible navigation_cube_visible background_rgb background_bottom_rgb background_gradient lighting lighting_ambient lighting_diffuse lighting_specular lighting_direction lighting_color lighting_intensity}} {error "Unsupported managed artifact view '$field'"}
    }
    set view [viewerSceneValidate $module $provider $fields]
    set attribution [dict get $identity source_identity]
    set caption "Managed source geometry · display only · [dict get $attribution reference]"
    set scene [dict create layers [dict create managed_artifact $layer] view $view caption $caption source_identity $attribution publication 0]
    return [dict create scene [native3DScenePrepare $scene] identity $identity]
}
