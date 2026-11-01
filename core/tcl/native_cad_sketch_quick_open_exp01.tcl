# SPDX-License-Identifier: GPL-3.0-or-later
# Review-only derived Sketch descriptors. Interactive Document remains the only
# persistent scientific authority; a descriptor is never an editing source.
namespace eval ::GX::NativeCadQuickOpen {variable lastError {};variable hits 0;variable misses 0;variable published 0;variable uid {};variable observed {};variable boot {}}
proc ::GX::_nativeCadQuickDigest {text} {
    documentNativeEnsure
    return [::GX::NativeDocument::snapshotCache digest [encoding convertto utf-8 $text]]
}
proc ::GX::_nativeCadQuickRoot {} {
    if {$::GX::NativeCadQuickOpen::uid eq {}} {set ::GX::NativeCadQuickOpen::uid [exec id -u]}
    set session [_interactiveDocumentRequireSession];file stat $session stat
    set key [_nativeCadQuickDigest [list $session $stat(dev) $stat(ino)]]
    set root [file join [configurationCacheDirectory] native-sketch-quick-open-exp01 $key]
    if {![file exists $root]} {file mkdir $root;file attributes $root -permissions 0700}
    file lstat $root info
    if {$info(type) ne {directory} || $info(uid)!=$::GX::NativeCadQuickOpen::uid || ($info(mode)&0022)} {error {Sketch preview cache is not a private owned directory}}
    if {![dict exists $::GX::NativeCadQuickOpen::observed $root]} {
        # Existing resource accounting owns cleanup policy. A registration error
        # cannot turn a valid saved scientific Document into a failed save.
        if {[catch {resourceManagementObserve $root native_sketch_quick_open [dict create category cache_reusable recovery_required 0 retention_seconds 604800 session $::GX::currentSession]} error]} {set ::GX::NativeCadQuickOpen::lastError $error}
        dict set ::GX::NativeCadQuickOpen::observed $root 1
    }
    return $root
}
proc ::GX::_nativeCadQuickAtomic {path value} {
    set temp $path.[pid].[clock clicks].tmp
    set channel [open $temp {WRONLY CREAT EXCL} 0600]
    try {
        fconfigure $channel -encoding utf-8 -translation lf;puts -nonewline $channel $value
        close $channel;set channel {}
        file rename -force -- $temp $path
    } finally {if {$channel ne {}} {catch {close $channel}};if {[file exists $temp]} {file delete -- $temp}}
}
proc ::GX::_nativeCadQuickProcessStamp {process} {
    if {![regexp {^[1-9][0-9]{0,9}$} $process]} {error {Invalid derived-cache publisher identity}}
    set channel [open /proc/$process/stat r]
    try {set text [read $channel 4096]} finally {close $channel}
    if {![regexp {^\d+ \(.*\) (.*)$} $text -> fields]} {error {Cannot inspect derived-cache publisher lifetime}}
    return [lindex $fields 19]
}
proc ::GX::_nativeCadQuickLock {path} {
    if {$::GX::NativeCadQuickOpen::boot eq {}} {set c [open /proc/sys/kernel/random/boot_id];try {set ::GX::NativeCadQuickOpen::boot [string trim [read $c 128]]} finally {close $c}}
    set lifetime [dict create pid [pid] start [_nativeCadQuickProcessStamp [pid]] boot $::GX::NativeCadQuickOpen::boot]
    if {[catch {set channel [open $path {WRONLY CREAT EXCL} 0600]}]} {
        # Recover only an abandoned, owned, regular derived-cache lock. Never
        # take a lock from a live matching process or wait on a scientific Job.
        file lstat $path before
        if {$before(type) ne {file} || $before(uid)!=$::GX::NativeCadQuickOpen::uid || $before(size)>512} {error {Sketch preview publication busy}}
        set channel [open $path r];try {set previous [read $channel 512]} finally {close $channel}
        if {![catch {set old [dict get $previous pid];set stamp [dict get $previous start];set previousBoot [dict get $previous boot];set current [_nativeCadQuickProcessStamp $old]}] && $stamp eq $current && $previousBoot eq $::GX::NativeCadQuickOpen::boot} {error {Sketch preview publication busy}}
        file lstat $path after
        if {$before(ino)!=$after(ino) || $before(ctime)!=$after(ctime)} {error {Sketch preview publisher changed}}
        file delete -- $path
        set channel [open $path {WRONLY CREAT EXCL} 0600]
    }
    try {puts -nonewline $channel $lifetime} finally {close $channel}
}
proc ::GX::_nativeCadQuickRead {path {sha {}}} {
    return [encoding convertfrom utf-8 [dict get [::GX::NativeDocument::snapshotCache read $path $sha] bytes]]
}
proc ::GX::_nativeCadQuickIndex {root} {
    set path [file join $root index.tcldict]
    if {![file exists $path]} {return [dict create schema gxtxt.sketch.quick_open.exp01 entries {}]}
    set index [_nativeCadQuickRead $path]
    if {[dict get $index schema] ne {gxtxt.sketch.quick_open.exp01} || [dict size [dict get $index entries]]>4096} {error {Unsupported Sketch preview index}}
    return $index
}
# A full-bounds Native2D C LOD is a derived presentation, not a sampled exact
# model. It preserves retained polyline corners and uses the existing sampler.
# Curved display is bounded at16384 virtual pixels /65536 points per object.
proc ::GX::_nativeCadSketchQuickGeometry {model authority {targetUnit {}}} {
    native2DEnsure
    set scene [::GX::Native2D::core scene];set ids {};set layers {};set local {};set rows {};set total 0;set overlayRequired 0
    try {
        dict for {key entry} $model {
            if {![string match object/* $key]} continue
            set object [::GX::Native2D::core sketch_create $scene [dict get $entry definition] 257]
            ::GX::Native2D::core object_style $scene $object [dict get $entry style]
            dict set ids [string range $key 7 end] $object
        }
        if {[dict size $ids]} {
            ::GX::Native2D::core aspect $scene auto
            ::GX::Native2D::core view $scene {16384 16384 0 0 0 0 {-1 -1 1 1}}
            ::GX::Native2D::core fit $scene
        }
        set bounds [lindex [::GX::Native2D::core view $scene] 6]
        dict for {logical object} $ids {
            set snapshot [native2DPresentationObjectSnapshot $scene $object 65536]
            if {$snapshot eq {}} continue
            set style [dict get $snapshot style];set ordinal 0
            if {[dict get $style line_style]!=0 || [dict get $style marker]!=0 || [dict get $snapshot kind] ne {curve}} {set overlayRequired 1}
            foreach path [dict get $snapshot paths] {
                set points [::GX::Native2D::core world_points $scene $path]
                if {![llength $points]} continue
                set count [llength $points];incr total $count
                if {$total>1000000 || [llength $rows]>=4096} {error {Sketch preview exceeds its presentation budget}}
                lappend rows [dict create id ${logical}_[incr ordinal] offset [llength $local] count $count style $style]
                lappend local {*}[lmap point $points {concat $point 0}]
            }
        }
    } finally {::GX::Native2D::core destroy $scene}
    set world {}
    for {set i 0} {$i<[llength $local]} {incr i 65536} {
        lappend world {*}[dict get [native3DGeometryCall $authority plane_frame [dict create plane [dict get $model plane] direction to_world points [lrange $local $i [expr {$i+65535}]]]] points]
    }
    if {$targetUnit ne {} && $targetUnit ne [dict get $model working_unit]} {
        set flat {};set coordinates [concat {*}$world]
        for {set i 0} {$i<[llength $coordinates]} {incr i 4095} {lappend flat {*}[unitRegistryConvertCoordinates [dict get $model working_unit] $targetUnit [lrange $coordinates $i [expr {$i+4094}]]]}
        set world {};foreach {x y z} $flat {lappend world [list $x $y $z]}
    }
    set order 0
    foreach row $rows {
        set count [dict get $row count];set offset [dict get $row offset];set style [dict get $row style];set color [dict get $style color]
        set indices {};for {set i 0} {$i<$count} {incr i} {lappend indices $i}
        dict set layers [dict get $row id] [dict create source_mode memory_geometry provenance derived_sketch_lod_exp01 dataset_id {} layer_order [incr order] visible 1 opacity [lindex $color 3] representation wireframe base_color [join [lrange $color 0 2] {;}] line_width [dict get $style line_width] point_size 5 backface_culling 0 scalar_coloring 0 scalar_array {} local_transform {} texture {} vertices [lrange $world $offset [expr {$offset+$count-1}]] polylines [expr {$count>1?[list $indices]:{}}] points [expr {$count==1?{0}:{}}] triangles {}]
    }
    lassign $bounds x0 y0 x1 y1
    set density [expr {min(16384./max(1.e-15,$x1-$x0),16384./max(1.e-15,$y1-$y0))}]
    return [dict create layers $layers local_bounds $bounds pixels_per_unit $density editing_overlay_required $overlayRequired points $total object_count [dict size $ids] quality native_full_bounds_lod_16384]
}
proc ::GX::nativeCadSketchQuickOpenPublish {document {payload {}} {targetUnit {}}} {
    if {![llength [info commands nativeCadSketchDocumentPresentation]]} {source [file join $::GX::scriptDir core tcl native_cad_sketch_v1.tcl]}
    set before [dict get [interactiveDocumentSourceIdentities [list $document]] $document]
    if {[dict get $before format] ne {gxtxt.native_cad_sketch.v1}} {error {Quick-open requires an exact Sketch Document}}
    # Even a caller-supplied saved model must agree with the verified authority.
    set saved [interactiveDocumentReadCached $document]
    if {$payload ne {} && $payload ne [dict get $saved payload]} {error {Sketch preview publication does not match the saved payload}}
    set model [dict get $saved payload model];::GX::NativeCadSketch::validate $model
    if {$targetUnit eq {}} {set targetUnit [dict get $model working_unit]}
    unitRegistryConversionPlan [dict get $model working_unit] $targetUnit
    set authority [native3DGeometryOpen $document]
    try {
        set frame [native3DGeometryCall $authority plane_frame [dict create plane [dict get $model plane]]]
        set geometry [_nativeCadSketchQuickGeometry $model $authority $targetUnit]
    } finally {native3DGeometryClose $authority}
    if {$before ne [dict get [interactiveDocumentSourceIdentities [list $document]] $document]} {error {Sketch changed during preview preparation}}
    set root [_nativeCadQuickRoot];set bytes [dict get $geometry layers]
    if {[string bytelength $bytes]>33554432} {error {Sketch preview asset exceeds32 MiB}}
    set hash [_nativeCadQuickDigest $bytes];set asset $hash.layers
    if {![file exists [file join $root $asset]] || [catch {_nativeCadQuickRead [file join $root $asset] $hash}]} {_nativeCadQuickAtomic [file join $root $asset] $bytes}
    set relationships 0;foreach key [dict keys $model relationship/*] {incr relationships}
    set descriptor [dict create schema gxtxt.sketch.quick_open.exp01 source $before working_unit $targetUnit source_unit [dict get $model working_unit] plane [dict get $model plane] normalized_frame [dict remove $frame points] local_bounds [dict get $geometry local_bounds] pixels_per_unit [dict get $geometry pixels_per_unit] object_count [dict get $geometry object_count] relationship_count $relationships points [dict get $geometry points] quality [dict get $geometry quality] asset $asset asset_sha256 $hash asset_bytes [string bytelength $bytes] exact_edit_source 0]
    dict set descriptor editing_overlay_required [dict get $geometry editing_overlay_required]
    dict set descriptor descriptor_sha256 [_nativeCadQuickDigest $descriptor]
    # A short nonblocking lock coordinates only disposable index publication.
    # A competing publication may be skipped; lookup has a verified fallback.
    set lock [file join $root publish.lock]
    _nativeCadQuickLock $lock
    try {
        if {[catch {set index [_nativeCadQuickIndex $root]}]} {set index [dict create schema gxtxt.sketch.quick_open.exp01 entries {}]}
        dict set index entries $document $targetUnit $descriptor
        # Bounded disk cache: retain at most512 asset files /128 MiB. Eviction
        # removes index references first; absent previews are rebuilt lazily.
        set assets [glob -nocomplain -directory $root *.layers];set used 0;set ordered {}
        foreach path $assets {incr used [file size $path];lappend ordered [list [file mtime $path] $path]}
        foreach row [lsort -integer -index 0 $ordered] {
            if {$used<=134217728 && [llength $assets]<=512} break
            set path [lindex $row 1]
            if {[file tail $path] eq $asset} continue
            incr used -[file size $path];set assets [lsearch -all -inline -not -exact $assets $path]
            dict for {id units} [dict get $index entries] {dict for {unit record} $units {if {[dict get $record asset] eq [file tail $path]} {dict unset index entries $id $unit}}}
            file delete -- $path
        }
        _nativeCadQuickAtomic [file join $root index.tcldict] $index
    } finally {file delete -- $lock}
    incr ::GX::NativeCadQuickOpen::published
    return $descriptor
}
proc ::GX::nativeCadSketchQuickOpenList {documents {targetUnit {}} {rebuild 1}} {
    set sources [interactiveDocumentSourceIdentities $documents];set root [_nativeCadQuickRoot]
    if {[catch {set index [_nativeCadQuickIndex $root]}]} {set index [dict create entries {}]}
    set result {}
    dict for {id source} $sources {
        set descriptor {};set units [datasetPublicationV2DictDefault [dict get $index entries] $id {}]
        if {[catch {dict size $units}]} {set units {}}
        dict for {unit entry} $units {
            if {![catch {
                if {($targetUnit ne {} && $targetUnit ne $unit) || ($targetUnit eq {} && $unit ne [dict get $entry source_unit]) || [dict get $entry source] ne $source || [dict get $entry schema] ne {gxtxt.sketch.quick_open.exp01}} {error stale}
                if {[_nativeCadQuickDigest [dict remove $entry descriptor_sha256]] ne [dict get $entry descriptor_sha256]} {error {Corrupt Sketch descriptor}}
                foreach field {working_unit source_unit plane normalized_frame local_bounds pixels_per_unit editing_overlay_required object_count relationship_count points quality asset asset_sha256 asset_bytes exact_edit_source} {dict get $entry $field}
                if {![regexp {^[a-f0-9]{64}\.layers$} [dict get $entry asset]] || [dict get $entry asset] ne "[dict get $entry asset_sha256].layers" || ![file isfile [file join $root [dict get $entry asset]]] || [dict get $entry exact_edit_source]!=0 || [dict get $entry asset_bytes]>33554432 || [dict get $entry points]>1000000} {error invalid}
            }]} {set descriptor $entry;break}
        }
        if {$descriptor eq {}} {
            incr ::GX::NativeCadQuickOpen::misses
            if {$rebuild} {set descriptor [nativeCadSketchQuickOpenPublish $id {} $targetUnit]} else {set descriptor [dict create source $source unavailable 1]}
        } else {incr ::GX::NativeCadQuickOpen::hits}
        dict set result $id $descriptor
    }
    return $result
}
proc ::GX::nativeCadSketchQuickOpenPresentation {document {targetUnit {}}} {
    if {[catch {set descriptor [dict get [nativeCadSketchQuickOpenList [list $document] $targetUnit] $document]} error]} {
        set ::GX::NativeCadQuickOpen::lastError $error
        return [nativeCadSketchDocumentPresentation $document $targetUnit]
    }
    set root [_nativeCadQuickRoot]
    if {[catch {set layers [_nativeCadQuickRead [file join $root [dict get $descriptor asset]] [dict get $descriptor asset_sha256]]}]} {
        set descriptor [nativeCadSketchQuickOpenPublish $document {} $targetUnit]
        set layers [_nativeCadQuickRead [file join $root [dict get $descriptor asset]] [dict get $descriptor asset_sha256]]
    }
    set source [dict get $descriptor source]
    return [dict create document_id $document generation [dict get $source generation] revision [dict get $source revision] sha256 [dict get $source sha256] session_token [interactiveDocumentSessionToken] working_unit [dict get $descriptor working_unit] layers $layers descriptor $descriptor display_policy resident_native_depth scientific_owner Native2D]
}
proc ::GX::nativeCadSketchQuickOpenStatus {} {
    return [dict create hits $::GX::NativeCadQuickOpen::hits misses $::GX::NativeCadQuickOpen::misses publications $::GX::NativeCadQuickOpen::published last_error $::GX::NativeCadQuickOpen::lastError disk_budget_bytes 134217728 asset_limit 512 payload_cache [interactiveDocumentCacheStatus]]
}
