# GX-TXT Graph Notes and Graph Metadata APIs v1.
# Stable graph identity resolves Session-owned Markdown and metadata resources.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX {
    variable graphNotesApiVersion 1
    variable graphMetadataApiVersion 1
    variable graphResourceRefs
    array set graphResourceRefs {}
}

proc ::GX::graphResourceRef {reference} {
    if {[catch {dict size $reference}]} {error "Graph reference must be a dictionary"}
    set kind [expr {[dict exists $reference kind] ? [dict get $reference kind] : "provider"}]
    if {$kind eq "provider"} {
        foreach field {module_id graph_id} {
            if {![dict exists $reference $field] || [dict get $reference $field] eq ""} {error "Graph reference requires $field"}
        }
        set mid [dict get $reference module_id];set gid [dict get $reference graph_id]
        set vid [expr {[dict exists $reference variant_id] ? [dict get $reference variant_id] : ""}]
        graphAxisAddress $mid $gid $vid
        return [dict create kind provider module_id $mid graph_id $gid variant_id $vid]
    }
    if {$kind eq "clone"} {
        set id [expr {[dict exists $reference clone_id] ? [dict get $reference clone_id] : ""}]
        if {![regexp {^c[0-9]{6}$} $id]} {error "Invalid Clone ID"}
        set path [file join [::GX::PlotClone::root] $id graph.png]
        if {[::GX::PlotClone::infoForPath $path] eq ""} {error "Unknown Session Clone '$id'"}
        return [dict create kind clone clone_id $id]
    }
    error "Graph reference kind must be provider or clone"
}
proc ::GX::graphResourceRefForPath {path} {
    if {[::GX::PlotClone::infoForPath $path] ne ""} {
        return [dict create kind clone clone_id [file tail [file dirname $path]]]
    }
    set identity [graphUseIdentityForPath $path]
    if {[llength $identity] != 3} {error "Selected image has no stable graph identity"}
    lassign $identity mid gid vid
    return [dict create kind provider module_id $mid graph_id $gid variant_id $vid]
}
proc ::GX::graphNotesOpenForPath {path} {
    set ref [graphResourceRefForPath $path]
    if {[dict get $ref kind] eq "clone"} {
        set title "Graph Notes — Clone [dict get $ref clone_id]"
    } else {
        set label [expr {[dict get $ref variant_id] eq "" ? "base graph" : "Variant [dict get $ref variant_id]"}]
        set title "Graph Notes — [dict get $ref graph_id] ($label)"
    }
    return [openMarkupEditor $title [graphNotesRead $ref] [list ::GX::graphNotesWrite $ref]]
}
proc ::GX::graphNotesOpenCurrent {} {
    set path [currentGraphPath]
    if {$path eq ""} {error "Select a graph first"}
    return [graphNotesOpenForPath $path]
}
proc ::GX::graphResourceKey {reference} {
    set ref [graphResourceRef $reference]
    if {[dict get $ref kind] eq "clone"} {return "clone,[dict get $ref clone_id]"}
    return "provider,[dict get $ref module_id],[dict get $ref graph_id],[dict get $ref variant_id]"
}
proc ::GX::graphResourceRelativePath {reference type} {
    # A stored reference can outlive a disabled provider. Its identifiers are
    # still safe path components, even when the graph is not currently live.
    set ref $reference
    if {[catch {dict size $ref}]} {error "Graph reference must be a dictionary"}
    set kind [dict get $ref kind]
    if {$kind eq "clone"} {
        if {![dict exists $ref clone_id] || ![regexp {^c[0-9]{6}$} [dict get $ref clone_id]]} {error "Invalid Clone ID"}
    } elseif {$kind eq "provider"} {
        foreach field {module_id graph_id} {
            if {![dict exists $ref $field] || ![regexp {^[A-Za-z0-9_.-]+$} [dict get $ref $field]]} {error "Invalid graph $field"}
        }
        if {[dict exists $ref variant_id] && [dict get $ref variant_id] ne "" &&
            ![regexp {^[A-Za-z0-9_.-]+$} [dict get $ref variant_id]]} {error "Invalid Variant ID"}
    } else {error "Unknown graph reference kind"}
    if {$type ni {note metadata}} {error "Unknown graph resource type"}
    set root [expr {$type eq "note" ? "notes" : "metadata"}]
    set file [expr {$type eq "note" ? "notes.md" : "metadata.ini"}]
    if {$kind eq "clone"} {
        return [file join $root graphs clones [dict get $ref clone_id] $file]
    }
    set mid [datasetNoteStem [dict get $ref module_id]]
    set gid [datasetNoteStem [dict get $ref graph_id]]
    set vid [expr {[dict exists $ref variant_id] ? [dict get $ref variant_id] : ""}]
    if {$vid eq ""} {return [file join $root graphs $mid $gid base $file]}
    return [file join $root graphs $mid $gid variants [datasetNoteStem $vid] $file]
}
proc ::GX::graphResourcePath {reference type} {
    if {$::GX::currentSession eq "" || ![file isdirectory $::GX::currentSession]} {error "Open a Session first"}
    return [file join $::GX::currentSession [graphResourceRelativePath $reference $type]]
}
proc ::GX::graphResourceTrack {reference type {present 1}} {
    variable graphResourceRefs
    set ref [graphResourceRef $reference]
    set key "[graphResourceKey $ref],$type"
    if {$present} {set graphResourceRefs($key) $ref} else {catch {unset graphResourceRefs($key)}}
}

proc ::GX::graphNotesInfo {reference} {
    set ref [graphResourceRef $reference]
    set path [graphResourcePath $ref note]
    return [dict create reference $ref exists [file isfile $path] updated_at [expr {[file isfile $path] ? [file mtime $path] : ""}] format gx-markup-v1]
}
proc ::GX::graphNotesExists {reference} {return [dict get [graphNotesInfo $reference] exists]}
proc ::GX::graphNotesRead {reference} {
    set ref [graphResourceRef $reference]
    return [noteReadUtf8 [graphResourcePath $ref note]]
}
proc ::GX::graphNotesWrite {reference markdown} {
    set ref [graphResourceRef $reference]
    if {[catch {encoding convertto utf-8 $markdown}]} {error "Graph note must be UTF-8 text"}
    noteWriteUtf8 [graphResourcePath $ref note] $markdown
    graphResourceTrack $ref note
    catch {refreshManifestPreview}
    catch {sessionFileExplorerPopulate}
    return [graphNotesInfo $ref]
}
proc ::GX::graphNotesClear {reference} {
    set ref [graphResourceRef $reference]
    set path [graphResourcePath $ref note]
    if {[file isfile $path]} {file delete -- $path}
    graphResourceTrack $ref note 0
    catch {refreshManifestPreview}
    return [graphNotesInfo $ref]
}

proc ::GX::graphMetadataInfo {reference} {
    set ref [graphResourceRef $reference]
    set path [graphResourcePath $ref metadata]
    return [dict create reference $ref exists [file isfile $path] updated_at [expr {[file isfile $path] ? [file mtime $path] : ""}] api_version 1]
}
proc ::GX::graphMetadataRead {reference} {
    set ref [graphResourceRef $reference]
    set path [graphResourcePath $ref metadata]
    if {![file isfile $path]} {return [dict create]}
    set parsed [parseIni $path]
    set result [dict create]
    foreach key [dict keys $parsed] {
        if {[string first "metadata." $key] != 0} continue
        set name [string range $key 9 end]
        _datasetMetadataValidateKey $name
        dict set result $name [dict get $parsed $key]
    }
    return $result
}
proc ::GX::graphMetadataWrite {reference metadata} {
    set ref [graphResourceRef $reference]
    if {[catch {dict size $metadata}]} {error "Graph metadata must be a dictionary"}
    dict for {key value} $metadata {
        _datasetMetadataValidateKey $key
        if {[regexp {[\r\n]} $value]} {error "Graph metadata values must be single-line UTF-8 text"}
    }
    set path [graphResourcePath $ref metadata]
    file mkdir [file dirname $path]
    set tmp "$path.tmp.[pid].[clock clicks]"
    set fd [open $tmp w]
    try {
        fconfigure $fd -encoding utf-8 -translation lf
        puts $fd "; GX-TXT Graph Metadata API v1\n\[graph_metadata\]"
        putKV $fd api_version 1
        putKV $fd kind [dict get $ref kind]
        puts $fd "\n\[metadata\]"
        foreach key [lsort -dictionary [dict keys $metadata]] {putKV $fd $key [dict get $metadata $key]}
    } finally {close $fd}
    file rename -force -- $tmp $path
    graphResourceTrack $ref metadata
    catch {refreshManifestPreview}
    return [graphMetadataRead $ref]
}
proc ::GX::graphMetadataUpdate {reference changes} {
    if {[catch {dict size $changes}]} {error "Graph metadata changes must be a dictionary"}
    return [graphMetadataWrite $reference [dict merge [graphMetadataRead $reference] $changes]]
}
proc ::GX::graphMetadataUnset {reference keys} {
    set data [graphMetadataRead $reference]
    foreach key $keys {if {[dict exists $data $key]} {dict unset data $key}}
    return [graphMetadataWrite $reference $data]
}
proc ::GX::graphResourceCopy {source target} {
    set source [graphResourceRef $source];set target [graphResourceRef $target]
    foreach type {note metadata} {
        set path [graphResourcePath $source $type]
        if {![file isfile $path]} continue
        set destination [graphResourcePath $target $type]
        file mkdir [file dirname $destination]
        file copy -force -- $path $destination
        graphResourceTrack $target $type
    }
}
proc ::GX::graphResourceDelete {reference} {
    set ref [graphResourceRef $reference]
    foreach type {note metadata} {
        set path [graphResourcePath $ref $type]
        if {[file isfile $path]} {file delete -- $path}
        graphResourceTrack $ref $type 0
    }
}

# Manifest references are an index; Markdown/metadata sidecars remain authority.
rename ::GX::manifestStringV2 ::GX::manifestStringV2_before_graph_resources
proc ::GX::manifestStringV2 {} {
    variable graphResourceRefs
    set out [manifestStringV2_before_graph_resources]
    append out "\n\[dataset_organization\]\n"
    appendKV out current_namespace [datasetNamespaceNormalize $::GX::cfg(dataset_namespace_current)]
    # Empty namespaces belong to the Session Manifest. Dataset metadata keeps
    # only the placement of actual Datasets; no second Dataset registry exists.
    set created [lsort -dictionary -unique $::GX::cfg(dataset_namespace_created)]
    appendKV out namespace_count [llength $created]
    set index 0
    foreach name $created {
        append out "\n\[dataset_namespace.[incr index]\]\n"
        appendKV out name [datasetNamespaceNormalize $name]
        if {[info exists ::GX::cfg(dataset_namespace_shared_inputs)]&&[dict exists $::GX::cfg(dataset_namespace_shared_inputs) $name]} {appendKV out shared_input_producers [join [dict get $::GX::cfg(dataset_namespace_shared_inputs) $name] {;}]}
    }
    foreach type {note metadata} {
        set index 0
        set section [expr {$type eq "note" ? "graph_notes" : "graph_metadata"}]
        foreach key [lsort [array names graphResourceRefs "*,$type"]] {
            set ref $graphResourceRefs($key)
            if {[catch {set relative [graphResourceRelativePath $ref $type]}]} continue
            if {![file isfile [file join $::GX::currentSession $relative]]} continue
            incr index
            append out "\n\[$section.$index\]\n"
            foreach field {kind module_id graph_id variant_id clone_id} {
                appendKV out $field [expr {[dict exists $ref $field] ? [dict get $ref $field] : ""}]
            }
            appendKV out file $relative
        }
        append out "\n\[$section\]\n"
        appendKV out api_version 1
        appendKV out count $index
    }
    return $out
}
rename ::GX::loadManifestV2 ::GX::loadManifestV2_before_graph_resources
proc ::GX::loadManifestV2 {path} {
    variable graphResourceRefs
    array unset graphResourceRefs *
    loadManifestV2_before_graph_resources $path
    set parsed [parseIni $path]
    set ::GX::cfg(dataset_namespace_current) [datasetNamespaceNormalize [datasetPublicationV2DictDefault $parsed dataset_organization.current_namespace base]]
    set ::GX::cfg(dataset_namespace_created) {}
    set count [datasetPublicationV2DictDefault $parsed dataset_organization.namespace_count 0]
    if {![string is integer -strict $count]||$count<0||$count>10000} {error {Invalid Dataset namespace count in Session Manifest}}
    for {set i 1} {$i<=$count} {incr i} {
        set key dataset_namespace.$i.name
        if {![dict exists $parsed $key]} {error "Missing $key in Session Manifest"}
        lappend ::GX::cfg(dataset_namespace_created) [datasetNamespaceNormalize [dict get $parsed $key]]
    }
    set ::GX::cfg(dataset_namespace_created) [lsort -dictionary -unique $::GX::cfg(dataset_namespace_created)]
    set ::GX::cfg(dataset_namespace_shared_inputs) {}
    for {set i 1} {$i<=$count} {incr i} {
        if {[dict exists $parsed dataset_namespace.$i.shared_input_producers]} {dict set ::GX::cfg(dataset_namespace_shared_inputs) [datasetNamespaceNormalize [dict get $parsed dataset_namespace.$i.name]] [splitList [dict get $parsed dataset_namespace.$i.shared_input_producers]]}
    }
    foreach {section type} {graph_notes note graph_metadata metadata} {
        set count [descriptorValue $parsed $section count 0]
        if {![string is integer -strict $count] || $count < 0 || $count > 100000} continue
        for {set i 1} {$i <= $count} {incr i} {
            set prefix "$section.$i"
            set kind [descriptorValue $parsed $prefix kind ""]
            if {$kind eq "clone"} {
                set ref [dict create kind clone clone_id [descriptorValue $parsed $prefix clone_id ""]]
            } elseif {$kind eq "provider"} {
                set ref [dict create kind provider module_id [descriptorValue $parsed $prefix module_id ""] graph_id [descriptorValue $parsed $prefix graph_id ""] variant_id [descriptorValue $parsed $prefix variant_id ""]]
            } else {continue}
            # Keep a reference even while its provider is disabled. Public
            # operations still validate live identity before accessing files.
            if {$kind eq "clone"} {
                set key "clone,[dict get $ref clone_id],$type"
            } else {
                set key "provider,[dict get $ref module_id],[dict get $ref graph_id],[dict get $ref variant_id],$type"
            }
            set graphResourceRefs($key) $ref
        }
    }
}
