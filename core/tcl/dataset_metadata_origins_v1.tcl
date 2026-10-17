# SPDX-License-Identifier: GPL-3.0-or-later
# Origins extend the one canonical metadata resource, never a parallel store.
proc ::GX::_datasetMetadataOriginRecord {session id owner keys} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::_datasetMetadataOriginRecord $session $id $owner $keys]}
    set md [_datasetMetadataReadAll $session $id]
    set origins [datasetPublicationV2DictDefault $md _gxtxt.framework.metadata_origins {}]
    foreach key $keys {
        if {[_datasetMetadataReserved $key] || ![dict exists $md $key]} continue
        set digest [datasetStorageSha256Text $session [dict get $md $key]]
        # Publication commonly carries forward pre-existing annotations. Their
        # unchanged values retain the original User attribution.
        if {$owner ne "User" && [dict exists $origins $key] && [dict get $origins $key owner] eq "User" && [dict get $origins $key value_sha256] eq $digest} continue
        dict set origins $key [dict create owner $owner value_sha256 $digest]
    }
    dict for {key record} $origins {if {![dict exists $md $key]} {dict unset origins $key}}
    _datasetFrameworkMetadataUpdate $session $id [dict create metadata_origins $origins]
}
proc ::GX::datasetMetadataGroups {session id} {
    set md [_datasetMetadataReadAll $session $id]
    set origins [datasetPublicationV2DictDefault $md _gxtxt.framework.metadata_origins {}]
    set groups [dict create User {}]
    dict for {key value} $md {
        set owner Unclassified
        if {[_datasetMetadataReserved $key]} {
            if {[regexp {^_gxtxt\.module\.m([0-9a-f]+)\.} $key -> encoded] && ![catch {set module [encoding convertfrom utf-8 [binary decode hex $encoded]]}]} {
                set owner module:$module
            } else {continue}
        } elseif {[dict exists $origins $key] && ![catch {
            set record [dict get $origins $key]
            if {[dict get $record value_sha256] ne [datasetStorageSha256Text $session $value]} {error {Changed attribution}}
            set recorded [dict get $record owner]
            if {$recorded eq "User" || [string match module:* $recorded]} {set owner $recorded}
        }]} {}
        dict set groups $owner $key $value
    }
    return $groups
}
proc ::GX::datasetMetadataGroupLabel {group} {
    if {![string match module:* $group]} {return $group}
    set id [string range $group 7 end]
    return [moduleField $id name $id]
}
proc ::GX::datasetMetadataUserFields {session id} {return [dict get [datasetMetadataGroups $session $id] User]}
proc ::GX::_datasetMetadataUserSave {session id user} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::_datasetMetadataUserSave $session $id $user]}
    set before [datasetMetadataRead $session $id]
    set owned [datasetMetadataUserFields $session $id]
    dict for {key value} $user {
        _datasetMetadataUserKey $key
        if {[dict exists $before $key] && ![dict exists $owned $key]} {error "Metadata '$key' is producer-owned or unclassified and is read-only in this editor."}
    }
    set merged $before
    foreach key [dict keys $owned] {dict unset merged $key}
    set merged [dict merge $merged $user]
    datasetMetadataWrite $session $id $merged
    _datasetMetadataOriginRecord $session $id User [dict keys $user]
}
proc ::GX::datasetMetadataBoundedValue {value} {
    set preview [string map [list "\n" { ↵ } "\r" {}] [string range $value 0 179]]
    if {[string length $value]>180} {append preview {… (double-click for full value)}}
    return $preview
}
proc ::GX::datasetMetadataPageRefresh {id} {
    variable ui
    set f .top.nb.channels.metadata
    set identity [list [interactiveDocumentSessionToken] $id]
    if {![info exists ui(metadataGroups,identity)] || $ui(metadataGroups,identity) ne $identity} {
        set ui(metadataGroups,identity) $identity
        array unset ui metadataGroup,*
        set ui(metadataGroup,User) 1
    }
    set groups [datasetMetadataGroups $::GX::currentSession $id]
    if {![winfo exists $f.groups]} {ttk::frame $f.groups;pack $f.groups -after $f.head -fill x}
    foreach child [winfo children $f.groups] {destroy $child}
    set i 0
    dict for {group fields} $groups {
        if {![info exists ui(metadataGroup,$group)]} {set ui(metadataGroup,$group) 0}
        ttk::checkbutton $f.groups.g$i -text [datasetMetadataGroupLabel $group] -variable ::GX::ui(metadataGroup,$group) -command [list ::GX::datasetMetadataPageRefresh $id]
        pack $f.groups.g$i -side left -padx 5
        incr i
    }
    $f.table delete [$f.table children {}]
    set ui(metadataGroups,values) {}
    dict for {group fields} $groups {
        if {!$ui(metadataGroup,$group)} continue
        dict for {key value} $fields {
            set item [$f.table insert {} end -values [list $key [datasetMetadataBoundedValue $value]]]
            dict set ui(metadataGroups,values) $item [list $key $value $group]
        }
    }
    bind $f.table <Double-1> ::GX::datasetMetadataInspectSelected
}
proc ::GX::datasetMetadataInspectSelected {} {
    variable ui
    set tree .top.nb.channels.metadata.table
    set item [lindex [$tree selection] 0]
    if {![dict exists $ui(metadataGroups,values) $item]} return
    lassign [dict get $ui(metadataGroups,values) $item] key value group
    set w .gxMetadataValue;catch {destroy $w};toplevel $w;wm title $w "Metadata — $key"
    ttk::label $w.label -text "[datasetMetadataGroupLabel $group] — $key (read-only)";pack $w.label -anchor w -padx 8 -pady 6
    text $w.value -wrap word -width 85 -height 22 -yscrollcommand [list $w.scroll set]
    ttk::scrollbar $w.scroll -command [list $w.value yview]
    pack $w.scroll -side right -fill y;pack $w.value -fill both -expand 1
    $w.value insert 1.0 $value;$w.value configure -state disabled
    ttk::button $w.copy -text {Copy full value} -command [list ::GX::datasetMetadataCopyValue $value]
    pack $w.copy -anchor e -padx 8 -pady 6
}
proc ::GX::datasetMetadataCopyValue {value} {clipboard clear;clipboard append $value}
