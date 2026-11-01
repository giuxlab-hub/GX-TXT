# SPDX-License-Identifier: GPL-3.0-or-later
# Source-note hooks subordinate to the existing Script Registry/Project owner.
proc ::GX::_scriptAuthoringPointer {metadata} {
    return [expr {[dict exists $metadata source_authoring_v1] ? [dict get $metadata source_authoring_v1] : {}}]
}
proc ::GX::_scriptAuthoringPointerValidate {pointer} {
    if {$pointer eq {}} return
    if {[catch {dict size $pointer}] || [lsort [dict keys $pointer]] ne {owner_key revision schema} ||
        [dict get $pointer schema] ni {gxtxt.source_authoring.v1 gxtxt.source_authoring.v2} || ![regexp {^[a-f0-9]{32}$} [dict get $pointer owner_key]] ||
        ![regexp {^[a-f0-9]{64}$} [dict get $pointer revision]]} {error {Invalid Script source-authoring pointer}}
}
proc ::GX::_scriptAuthoringFiles {metadata {code {}} {sources {}}} {
    set language [string tolower [dict get $metadata language]];set result {}
    if {[dict get $metadata kind] eq {project}} {
        if {$sources ne {}} {dict for {name source} $sources {dict set result $name [dict create language $language source_sha256 [scriptRegistryHashBytes [encoding convertto utf-8 $source]]]}
        } else {dict for {name record} [dict get $metadata project_files] {dict set result $name [dict create language $language source_sha256 [dict get $record sha256]]}}
    } else {
        set hash [expr {$code eq {} ? [dict get $metadata sha256] : [scriptRegistryHashBytes [encoding convertto utf-8 $code]]}]
        dict set result [scriptRegistrySourceName [dict get $metadata language]] [dict create language $language source_sha256 $hash]
    }
    return $result
}
proc ::GX::_scriptAuthoringCall {root request} {
    set fields {}
    dict for {key value} $request {
        switch -- $key {
            source_files - source_descriptors {
                set items {};dict for {name descriptor} $value {
                    lappend items "[viewerDevelopmentJsonString $name]:\{\"language\":[viewerDevelopmentJsonString [dict get $descriptor language]],\"source_sha256\":[viewerDevelopmentJsonString [dict get $descriptor source_sha256]]\}"
                };set encoded "\{[join $items ,]\}"
            }
            reference - renames {
                set items {};dict for {name item} $value {lappend items "[viewerDevelopmentJsonString $name]:[viewerDevelopmentJsonString $item]"};set encoded "\{[join $items ,]\}"
            }
            asset_plan {
                if {[lsort [dict keys $value]] ne {directory index_sha256 index_size} || ![string is integer -strict [dict get $value index_size]]} {error {Consumed internal asset plan required}}
                set encoded "\{\"directory\":[viewerDevelopmentJsonString [dict get $value directory]],\"index_sha256\":[viewerDevelopmentJsonString [dict get $value index_sha256]],\"index_size\":[dict get $value index_size]\}"
            }
            start - count {
                if {![string is integer -strict $value] || $value<0} {error {Integer asset range required}}
                set encoded $value
            }
            default {set encoded [viewerDevelopmentJsonString $value]}
        }
        lappend fields "[viewerDevelopmentJsonString $key]:$encoded"
    }
    return [exec {*}[scriptProjectCommand authoring $root] << "\{[join $fields ,]\}"]
}
proc ::GX::_scriptAuthoringRead {metadata {session {}}} {
    set pointer [_scriptAuthoringPointer $metadata]
    if {$pointer ne {}} {_scriptAuthoringCall [scriptRegistryPath [dict get $metadata scope] [dict get $metadata id] $session] [dict create operation validate pointer $pointer]}
}
proc ::GX::_scriptAuthoringStage {target pending metadata descriptors {renames {}}} {
    set pointer [_scriptAuthoringPointer $metadata]
    if {$pointer eq {}} {return {}}
    set result [_scriptAuthoringCall $pending [dict create operation sync pointer $pointer source_root $target source_files $descriptors renames $renames]]
    return [dict get $result pointer]
}
proc ::GX::_scriptAuthoringClone {source target metadata {session {}}} {
    set pointer [_scriptAuthoringPointer $source]
    if {$pointer eq {}} {return $metadata}
    set result [_scriptAuthoringCall [scriptRegistryPath [dict get $metadata scope] [dict get $metadata id] $session] [dict create operation clone pointer $pointer source_root $target source_files [_scriptAuthoringFiles $metadata]]]
    dict set metadata source_authoring_v1 [dict get $result pointer]
    dict incr metadata revision
    if {[dict get $metadata kind] eq {project}} {scriptRegistryWrite $metadata {} $session
    } else {
        set stream [open [dict get $metadata source_path] rb];try {set code [encoding convertfrom utf-8 [read $stream]]} finally {close $stream}
        scriptRegistryWrite $metadata $code $session
    }
    return [scriptRegistryRead [dict get $metadata scope] [dict get $metadata id] $session]
}
proc ::GX::_scriptAuthoringLockPath {metadata {session {}}} {
    set root [scriptRegistryPath [dict get $metadata scope] [dict get $metadata id] $session]
    return [expr {[dict get $metadata kind] eq {project} ? [file join $root .project-write-lock] : [file join [file dirname $root] .[dict get $metadata id].registry-lock]}]
}
# Explicit host-only Save As boundary. The normal source owner created target
# code already; this operation never saves source buffers or grants Dataset edits.
proc ::GX::scriptRegistryCopyAuthoring {sourceReference targetReference expectedSourceSha expectedTargetSha {options {}}} {
    if {[catch {dict size $options}]} {error {Source authoring copy options must be a dictionary}}
    foreach key [dict keys $options] {if {$key ni {expected_source_owner_revision expected_target_owner_revision expected_authoring_revision}} {error {Unknown source authoring copy option}}}
    foreach hash [list $expectedSourceSha $expectedTargetSha] {if {![regexp {^[a-f0-9]{64}$} $hash]} {error {Exact source and target code SHA required}}}
    set source [scriptRegistryDescribe $sourceReference];set target [scriptRegistryDescribe $targetReference]
    set sourceRoot [scriptRegistryPath [dict get $source scope] [dict get $source id]]
    set targetRoot [scriptRegistryPath [dict get $target scope] [dict get $target id]]
    if {[file normalize $sourceRoot] eq [file normalize $targetRoot]} {error {Source authoring copy requires a distinct new target}}
    set handles {}
    try {
        foreach lock [lsort -unique [list [_scriptAuthoringLockPath $source] [_scriptAuthoringLockPath $target]]] {
            if {[catch {set handle [open $lock {WRONLY CREAT EXCL}]}]} {error {Another source owner update is in progress}}
            lappend handles [list $lock $handle]
        }
        set currentSource [scriptRegistryDescribe $sourceReference];set currentTarget [scriptRegistryDescribe $targetReference]
        foreach tuple [list [list source $source $currentSource $expectedSourceSha] [list target $target $currentTarget $expectedTargetSha]] {
            lassign $tuple role before current expected
            if {[dict get $current sha256] ne $expected || [dict get $current revision] ne [dict get $before revision] || [_scriptAuthoringPointer $current] ne [_scriptAuthoringPointer $before]} {error "The $role source owner changed before copying notes"}
            set revisionKey expected_${role}_owner_revision
            if {[dict exists $options $revisionKey] && [dict get $options $revisionKey] ne [dict get $current revision]} {error "The $role metadata revision changed before copying notes"}
        }
        set source $currentSource;set target $currentTarget
        set pointer [_scriptAuthoringPointer $source]
        set authoringRevision [expr {$pointer eq {} ? {} : [dict get $pointer revision]}]
        if {[dict exists $options expected_authoring_revision] && [dict get $options expected_authoring_revision] ne $authoringRevision} {error {Source note snapshot changed before copying}}
        if {[dict get $source kind] ne [dict get $target kind] || [dict get $source language] ne [dict get $target language]} {error {Source and target copy must use the same source kind and language}}
        if {[dict get $target revision]!=1 || [_scriptAuthoringPointer $target] ne {} || [file exists [file join $targetRoot authoring]]} {error {Copy target must be an ordinary new record without notes}}
        set actualNames [lsort [lmap path [glob -nocomplain -directory $targetRoot * .*] {set name [file tail $path];if {$name in {. ..}} continue;set name}]]
        set expectedNames [expr {[dict get $target kind] eq {project} ? {.project-write-lock project-revisions script.ini} : [lsort [list script.ini [scriptRegistrySourceName [dict get $target language]]]]}]
        if {$actualNames ne $expectedNames} {error {New copy target has unexpected owner content; preserve and review it}}
        set originalDescriptors [_scriptAuthoringFiles $source];set targetDescriptors [_scriptAuthoringFiles $target]
        if {[lsort [dict keys $originalDescriptors]] ne [lsort [dict keys $targetDescriptors]]} {error {Source and target copy require identical relative source files}}
        set sourceIniSha [scriptRegistryHash [file join $sourceRoot script.ini]]
        set receipt [dict create status NO_NOTES source_reference $sourceReference target_reference $targetReference \
            source_sha256 $expectedSourceSha target_sha256 $expectedTargetSha source_owner_revision [dict get $source revision] \
            target_owner_revision [dict get $target revision] owner_key {} authoring_revision {} files {} source_unchanged 1 target_code_unchanged 1]
        if {$pointer eq {}} {return $receipt}
        set inventory [_scriptAuthoringCall $sourceRoot [dict create operation validate pointer $pointer]]
        if {![dict get $inventory note_count]} {return $receipt}
        set result [_scriptAuthoringCall $targetRoot [dict create operation copy pointer $pointer source_root $sourceRoot source_files $targetDescriptors source_descriptors $originalDescriptors]]
        if {[scriptRegistryHash [file join $sourceRoot script.ini]] ne $sourceIniSha || [dict get [scriptRegistryDescribe $sourceReference] sha256] ne $expectedSourceSha} {error {Original source changed while preparing note copy; new target remains reviewable}}
        set check [scriptRegistryDescribe $targetReference]
        if {[dict get $check revision] ne [dict get $target revision] || [dict get $check sha256] ne $expectedTargetSha || [_scriptAuthoringPointer $check] ne {}} {error {New target changed before note commit; source buffers remain untouched}}
        dict set target source_authoring_v1 [dict get $result pointer];dict incr target revision
        if {[dict get $target kind] eq {project}} {scriptRegistryWrite $target {}
        } else {
            set stream [open [dict get $target source_path] rb];try {set raw [read $stream]} finally {close $stream}
            if {[scriptRegistryHashBytes $raw] ne $expectedTargetSha} {error {New target code changed before note commit}}
            scriptRegistryWrite $target [encoding convertfrom utf-8 $raw]
        }
        set target [scriptRegistryDescribe $targetReference]
        if {[dict get $target sha256] ne $expectedTargetSha || [scriptRegistryHash [file join $sourceRoot script.ini]] ne $sourceIniSha || [dict get [scriptRegistryDescribe $sourceReference] sha256] ne $expectedSourceSha} {error {Source/copy preservation failed; target remains a reviewable new record}}
        set next [_scriptAuthoringPointer $target]
        return [dict replace $receipt status COPIED target_owner_revision [dict get $target revision] owner_key [dict get $next owner_key] authoring_revision [dict get $next revision] files [dict get $result files]]
    } finally {foreach item [lreverse $handles] {lassign $item lock handle;close $handle;file delete -- $lock}}
}
proc ::GX::scriptSourceNoteOwner {operation reference {request {}}} {
    if {$operation ni {describe read_local write_local ensure_identity asset_read}} {error {Unknown Script source-note operation}}
    if {[catch {dict size $reference}] || ![dict exists $reference reference] || ![dict exists $reference relative]} {error {Qualified Script reference and relative source file required}}
    foreach key [dict keys $reference] {if {$key ni {reference relative owner_key file_key expected_source_sha256}} {error {Unknown source-note reference field}}}
    set requestFields [expr {$operation eq {asset_read} ? {name start count expected_authoring_revision expected_owner_revision expected_asset_sha256} : {text expected_authoring_revision expected_owner_revision}}]
    if {$operation eq {write_local}} {lappend requestFields asset_plan}
    foreach key [dict keys $request] {if {$key ni $requestFields} {error {Unknown source-note request field}}}
    if {$operation eq {asset_read}} {
        foreach key $requestFields {if {![dict exists $request $key]} {error {Pinned source asset request required}}}
        if {![string is integer -strict [dict get $request start]] || [dict get $request start]<0 || ![string is integer -strict [dict get $request count]] || [dict get $request count]<1 || [dict get $request count]>1048576} {error {Bounded source asset range required}}
    }
    set qualified [dict get $reference reference];set m [scriptRegistryDescribe $qualified]
    set mutate [expr {$operation in {write_local ensure_identity}}]
    set dir [scriptRegistryPath [dict get $m scope] [dict get $m id]]
    set lock [expr {[dict get $m kind] eq {project} ? [file join $dir .project-write-lock] : [file join [file dirname $dir] .[dict get $m id].registry-lock]}]
    set handle {}
    if {$mutate} {
        if {![dict exists $request expected_authoring_revision]} {error {Expected authoring revision required}}
        if {[catch {set handle [open $lock {WRONLY CREAT EXCL}]}]} {error {Another source-owner update is in progress}}
    }
    try {
        set m [scriptRegistryDescribe $qualified]
        if {($mutate || $operation eq {asset_read}) && [dict exists $request expected_owner_revision] && [dict get $request expected_owner_revision] ne [dict get $m revision]} {error {Source owner metadata changed}}
        set arguments [dict create operation [expr {$mutate ? {prepare} : {read}}] pointer [_scriptAuthoringPointer $m] source_files [_scriptAuthoringFiles $m] reference $reference]
        if {$mutate} {dict set arguments expected_authoring_revision [dict get $request expected_authoring_revision]}
        if {$operation eq {write_local}} {
            if {![dict exists $request text]} {error {Note text required}}
            dict set arguments note_base64 [binary encode base64 -maxlen 0 [encoding convertto utf-8 [dict get $request text]]]
            if {[dict exists $request asset_plan]} {
                if {![llength [info commands ::GX::sourceNoteAssetPlanConsume]]} {error {Core source asset admission unavailable}}
                set current [scriptSourceNoteOwner read_local $reference]
                set top [dict create owner [dict get $current owner] reference $reference]
                dict set arguments asset_plan [::GX::sourceNoteAssetPlanConsume [dict get $request asset_plan] $current $top]
            }
        }
        if {$operation eq {asset_read}} {
            dict set arguments operation asset_read
            foreach key {name start count expected_authoring_revision expected_asset_sha256} {dict set arguments $key [dict get $request $key]}
            set result [_scriptAuthoringCall $dir $arguments]
            set check [scriptRegistryDescribe $qualified]
            if {[dict get $check revision] ne [dict get $m revision] || [_scriptAuthoringPointer $check] ne [_scriptAuthoringPointer $m]} {error {Source owner changed during asset read}}
            return $result
        }
        set result [_scriptAuthoringCall $dir $arguments]
        if {$mutate && [dict get $result pointer] ne [_scriptAuthoringPointer $m]} {
            dict set m source_authoring_v1 [dict get $result pointer];dict incr m revision
            if {[dict get $m kind] eq {project}} {scriptRegistryWrite $m {}
            } else {
                set stream [open [dict get $m source_path] rb];try {set code [encoding convertfrom utf-8 [read $stream]]} finally {close $stream}
                scriptRegistryWrite $m $code
            }
            set m [scriptRegistryDescribe $qualified]
        }
        set relative [dict get $result relative]
        if {[dict get $m kind] eq {project}} {set path [file join [dict get $m project_root] {*}[split $relative /]]
        } else {set path [dict get $m source_path]}
        if {[scriptRegistryHash $path] ne [dict get $result source_sha256]} {error {Source changed during note resolution}}
        if {[file type $path] eq {link} || [file size $path]>4194304} {error {Source must be an ordinary bounded file}}
        set stream [open $path rb];try {set sourceBytes [read $stream]} finally {close $stream}
        if {[scriptRegistryHashBytes $sourceBytes] ne [dict get $result source_sha256]} {error {Source changed during note read}}
        set source [encoding convertfrom utf-8 $sourceBytes]
        if {[encoding convertto utf-8 $source] ne $sourceBytes} {error {Source is not valid UTF-8}}
        set text [encoding convertfrom utf-8 [binary decode base64 [dict get $result note_base64]]]
        dict unset result note_base64;dict unset result pointer
        return [dict merge $result [dict create owner [expr {[dict get $m language] eq {Python}?{python_script}:{octave_script}}] text $text source $source source_revision [dict get $m sha256] owner_revision [dict get $m revision] reference $qualified]]
    } finally {if {$handle ne {}} {close $handle;file delete -- $lock}}
}
