# SPDX-License-Identifier: GPL-3.0-or-later
# Origins extend the one canonical metadata resource, never a parallel store.
proc ::GX::datasetMetadataAuthorizeContributors {session id modules expectedRevision} {
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Only the user/host may authorize metadata contributors}}
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetMetadataAuthorizeContributors $session $id $modules $expectedRevision]}
    if {[datasetRevisionToken $id $session] ne $expectedRevision} {error {Dataset revision changed before contributor authorization}}
    foreach module $modules {if {[moduleField $module descriptor {}] eq {}} {error "Unknown contributor '$module'"}}
    _datasetFrameworkMetadataUpdate $session $id [dict create metadata_contributors [lsort -unique $modules]]
}
proc ::GX::_datasetMetadataRequireContributor {session module id} {
    if {![catch {_datasetNamespaceRequireModuleWrite $session $module $id} assigned]} {return $assigned}
    set private [datasetPrivateMetadataRead $session $id]
    if {$module ni [datasetPublicationV2DictDefault $private _gxtxt.framework.metadata_contributors {}]} {error "Module '$module' is not authorized to contribute metadata to '$id'"}
}
proc ::GX::_datasetMetadataOriginRecord {session id owner keys {before {}}} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::_datasetMetadataOriginRecord $session $id $owner $keys $before]}
    if {$owner ni {User System} && (![string match module:* $owner] || [moduleField [string range $owner 7 end] descriptor {}] eq {})} {error {Invalid authenticated metadata actor}}
    set md [_datasetMetadataReadAll $session $id]
    set origins [datasetPublicationV2DictDefault $md _gxtxt.framework.metadata_origins {}]
    foreach key $keys {
        if {[_datasetMetadataReserved $key] || ![dict exists $md $key]} continue
        set digest [datasetStorageSha256Text $session [dict get $md $key]]
        if {[dict exists $origins $key] && [dict get $origins $key value_sha256] eq $digest} continue
        set creator $owner;set revision 1
        if {[dict exists $before $key]} {
            # Historical/unverified values have no trustworthy original actor.
            set creator Unclassified
            if {[dict exists $origins $key] && [dict get $origins $key value_sha256] eq [datasetStorageSha256Text $session [dict get $before $key]]} {
                set prior [dict get $origins $key]
                set creator [datasetPublicationV2DictDefault $prior original_contributor [dict get $prior owner]]
                set revision [expr {[datasetPublicationV2DictDefault $prior revision 0]+1}]
            }
        }
        dict set origins $key [dict create schema_version 2 owner $owner original_contributor $creator last_contributor $owner revision $revision value_sha256 $digest]
    }
    dict for {key record} $origins {if {![dict exists $md $key]} {dict unset origins $key}}
    _datasetFrameworkMetadataUpdate $session $id [dict create metadata_origins $origins]
}
proc ::GX::datasetMetadataGroups {session id {relation all}} {
    if {$relation ni {all original last}} {error {Metadata grouping relation must be all, original or last}}
    set md [_datasetMetadataReadAll $session $id]
    set origins [datasetPublicationV2DictDefault $md _gxtxt.framework.metadata_origins {}]
    set groups {}
    dict for {key value} $md {
        set owners {Unclassified}
        if {[_datasetMetadataReserved $key]} {
            if {[regexp {^_gxtxt\.module\.m([0-9a-f]+)\.} $key -> encoded] && ![catch {set module [encoding convertfrom utf-8 [binary decode hex $encoded]]}]} {set owners [list module:$module]} else {continue}
        } elseif {[dict exists $origins $key] && ![catch {
            set record [dict get $origins $key]
            if {[dict get $record value_sha256] ne [datasetStorageSha256Text $session $value]} {error {Changed attribution}}
            set last [datasetPublicationV2DictDefault $record last_contributor [dict get $record owner]]
            set original [datasetPublicationV2DictDefault $record original_contributor [dict get $record owner]]
            foreach actor [list $original $last] {if {$actor ni {User System Unclassified} && ![string match module:* $actor]} {error {Invalid historical contributor}}}
            switch $relation {original {set owners [list $original]} last {set owners [list $last]} all {set owners [lsort -unique [list $original $last]]}}
        }]} {}
        foreach owner $owners {dict set groups $owner $key $value}
    }
    return $groups
}
proc ::GX::datasetMetadataGroupLabel {group} {
    if {![string match module:* $group]} {return $group}
    set id [string range $group 7 end]
    return [moduleField $id name $id]
}
proc ::GX::datasetMetadataUserFields {session id} {return [datasetPublicationV2DictDefault [datasetMetadataGroups $session $id original] User {}]}
proc ::GX::datasetMetadataContributors {session id} {
    set md [_datasetMetadataReadAll $session $id];set result {}
    set origins [datasetPublicationV2DictDefault $md _gxtxt.framework.metadata_origins {}]
    dict for {key value} $md {
        if {[_datasetMetadataReserved $key]} continue
        set record [dict create original_contributor Unclassified last_contributor Unclassified verified 0]
        if {[dict exists $origins $key] && [dict get $origins $key value_sha256] eq [datasetStorageSha256Text $session $value]} {
            set record [dict get $origins $key]
            dict set record original_contributor [datasetPublicationV2DictDefault $record original_contributor [dict get $record owner]]
            dict set record last_contributor [datasetPublicationV2DictDefault $record last_contributor [dict get $record owner]]
            dict set record verified 1
        }
        dict set result $key $record
    }
    return $result
}
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
    if {![dict exists $groups User] && [dict size $groups] && [array names ui metadataGroup,*] eq {metadataGroup,User}} {set ui(metadataGroup,[lindex [dict keys $groups] 0]) 1}
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
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode datasetId
    set contributors [datasetMetadataContributors $::GX::currentSession $datasetId]
    set attribution {}
    if {[dict exists $contributors $key]} {set record [dict get $contributors $key];set attribution "Original: [dict get $record original_contributor]; latest: [dict get $record last_contributor]"}
    ttk::label $w.label -text "[datasetMetadataGroupLabel $group] — $key (read-only) $attribution";pack $w.label -anchor w -padx 8 -pady 6
    text $w.value -wrap word -width 85 -height 22 -yscrollcommand [list $w.scroll set]
    ttk::scrollbar $w.scroll -command [list $w.value yview]
    pack $w.scroll -side right -fill y;pack $w.value -fill both -expand 1
    $w.value insert 1.0 $value;$w.value configure -state disabled
    ttk::button $w.copy -text {Copy full value} -command [list ::GX::datasetMetadataCopyValue $value]
    pack $w.copy -anchor e -padx 8 -pady 6
}
proc ::GX::datasetMetadataCopyValue {value} {clipboard clear;clipboard append $value}
