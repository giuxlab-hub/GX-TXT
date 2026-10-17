# GX-TXT Preview Descriptor API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Host-independent preview contract for sources/datasets that must not be
# rendered as raw text. Plugins produce metadata and/or a visual artifact;
# the framework owns temporary preview storage and host rendering.

namespace eval ::GX {
    variable previewDescriptorApiVersion 1
    variable previewArtifactImages
    array unset previewArtifactImages *
}

proc ::GX::previewDescriptorCreateTempDir {} {
    set ch [file tempfile tmp]
    close $ch
    file delete -force -- $tmp
    append tmp ".d"
    file mkdir $tmp
    return [file normalize $tmp]
}

proc ::GX::previewDescriptorCleanupDir {dir} {
    if {[string trim $dir] eq ""} { return }
    catch {file delete -force -- $dir}
}

proc ::GX::previewDescriptorKinds {raw} {
    set s [string tolower [string trim $raw]]
    if {$s eq "" || $s eq "legacy"} { return {} }
    if {$s eq "none"} { return [list none] }
    if {$s eq "both"} { return [list metadata artifact] }
    set s [string map {"," " " ";" " " "+" " " "|" " "} $s]
    set out {}
    foreach k [split $s] {
        set k [string trim $k]
        if {$k eq ""} continue
        if {$k ni {metadata artifact}} { error "Unsupported preview_kind '$k'. Expected metadata, artifact, metadata+artifact, both or none." }
        if {[lsearch -exact $out $k] < 0} { lappend out $k }
    }
    return $out
}

proc ::GX::previewDescriptorSafeArtifact {artifact previewDir} {
    if {[catch {dict size $artifact}]} { error "preview_artifact must be a dict." }
    foreach key {path media_type} {
        if {![dict exists $artifact $key] || [string trim [dict get $artifact $key]] eq ""} { error "preview_artifact.$key is required." }
    }
    if {[string trim $previewDir] eq ""} { error "An artifact preview requires the framework-provided preview_dir." }
    set root [file normalize $previewDir]
    set p [string trim [dict get $artifact path]]
    if {[file pathtype $p] eq "absolute"} { set abs [file normalize $p] } else { set abs [file normalize [file join $root $p]] }
    if {$abs ne $root && [string first "$root/" "$abs"] != 0} { error "Preview artifact escapes preview_dir: $p" }
    if {![file isfile $abs]} { error "Preview artifact does not exist: $abs" }
    set mt [string trim [dict get $artifact media_type]]
    if {[string first "/" $mt] < 1 || [regexp {[\r\n]} $mt]} { error "Invalid preview artifact media_type '$mt'." }
    set label [expr {[dict exists $artifact label] ? [dict get $artifact label] : "Preview artifact"}]
    return [dict create path $abs media_type $mt label $label]
}

proc ::GX::previewDescriptorNormalize {result previewDir} {
    if {[catch {dict size $result}]} { error "Preview descriptor source must be a dict." }
    set rawKind [expr {[dict exists $result preview_kind] ? [dict get $result preview_kind] : ""}]
    set kinds [previewDescriptorKinds $rawKind]

    set pmeta [dict create]
    if {[dict exists $result preview_metadata]} {
        set pmeta [dict get $result preview_metadata]
        if {[catch {dict size $pmeta}]} { error "preview_metadata must be a dict of label/value pairs." }
        if {[lsearch -exact $kinds metadata] < 0 && $rawKind eq ""} { lappend kinds metadata }
    } elseif {[dict exists $result metadata] && ![catch {dict size [dict get $result metadata]}] && [dict size [dict get $result metadata]]} {
        set pmeta [dict get $result metadata]
        if {[dict exists $result source_kind] && [dict get $result source_kind] eq "binary" && $rawKind eq ""} { lappend kinds metadata }
    }

    set artifact [dict create]
    if {[dict exists $result preview_artifact]} {
        set artifact [previewDescriptorSafeArtifact [dict get $result preview_artifact] $previewDir]
        if {[lsearch -exact $kinds artifact] < 0 && $rawKind eq ""} { lappend kinds artifact }
    } elseif {[dict exists $result preview_path] || [dict exists $result preview_media_type]} {
        set a [dict create]
        if {[dict exists $result preview_path]} { dict set a path [dict get $result preview_path] }
        if {[dict exists $result preview_media_type]} { dict set a media_type [dict get $result preview_media_type] }
        if {[dict exists $result preview_label]} { dict set a label [dict get $result preview_label] }
        set artifact [previewDescriptorSafeArtifact $a $previewDir]
        if {[lsearch -exact $kinds artifact] < 0 && $rawKind eq ""} { lappend kinds artifact }
    }

    if {[lsearch -exact $kinds metadata] >= 0 && ![dict size $pmeta]} {
        # Empty metadata is valid; it simply renders no rows.
    }
    if {[lsearch -exact $kinds artifact] >= 0 && ![dict size $artifact]} { error "preview_kind requests artifact but no preview_artifact was returned." }
    return [dict create api_version 1 kinds [lsort -unique $kinds] metadata $pmeta artifact $artifact]
}

proc ::GX::previewDescriptorClearWidgetArtifact {w} {
    if {[winfo exists $w.source_surface]} {destroy $w.source_surface}
    variable previewArtifactImages
    if {[info exists previewArtifactImages($w)]} {
        catch {image delete $previewArtifactImages($w)}
        unset previewArtifactImages($w)
    }
}

proc ::GX::previewDescriptorRenderTextWidget {w descriptor} {
    variable previewArtifactImages
    set kinds [dict get $descriptor kinds]
    if {[lsearch -exact $kinds none] >= 0} { return }
    if {[lsearch -exact $kinds metadata] >= 0} {
        set md [dict get $descriptor metadata]
        if {[dict size $md]} {
            $w insert end "\nPREVIEW METADATA\n================\n"
            dict for {k v} $md { $w insert end [format "%-24s %s\n" $k $v] }
        }
    }
    if {[lsearch -exact $kinds artifact] >= 0} {
        set a [dict get $descriptor artifact]
        set path [dict get $a path]
        set mt [dict get $a media_type]
        set label [dict get $a label]
        $w insert end "\nPREVIEW ARTIFACT\n================\n$label\nMedia type: $mt\n"
        if {[llength [info commands image]]} {
            if {[catch {set img [image create photo -file $path]} err]} {
                $w insert end "Artifact: $path\nHost renderer could not display this artifact: $err\n"
            } else {
                previewDescriptorClearWidgetArtifact $w
                set previewArtifactImages($w) $img
                $w image create end -image $img
                $w insert end "\n"
            }
        } else {
            $w insert end "Artifact: $path\nThis host has no inline image renderer.\n"
        }
    }
}
