# SPDX-License-Identifier: GPL-3.0-or-later
# CORE owns active History and hook scheduling. Tcl objects never cross threads.
namespace eval ::GX::HistoryService {variable barriers {};variable requests {};variable serial 0;variable failures {}}
proc ::GX::_historyNativeRequire {} {
    if {![llength [info commands ::GX::historyNative]]} {
        load [file join $::GX::scriptDir core history libgxtxt_history[info sharedlibextension]] Gxtxt_history
    }
}
proc ::GX::_historyHandle {window} {return [dict get $::GX::ScientificHistory::viewers $window handle]}
proc ::GX::scientificHistoryViewerStatus {window} {
    set status [historyNative status [_historyHandle $window]]
    if {[dict exists $::GX::ScientificHistory::viewers $window last_hook_error]} {dict set status hook_failed 1;dict set status hook_error [dict get $::GX::ScientificHistory::viewers $window last_hook_error]}
    if {[dict exists $::GX::ScientificHistory::viewers $window last_auxiliary_error]} {dict set status auxiliary_failed 1;dict set status auxiliary_error [dict get $::GX::ScientificHistory::viewers $window last_auxiliary_error]}
    return $status
}
proc ::GX::scientificHistoryViewerSummary {window} {
    return [dict get $::GX::ScientificHistory::viewers $window record]
}
proc ::GX::scientificHistoryViewerStateAt {window index} {
    _scientificHistoryGuard $window
    return [historyNative state [_historyHandle $window] $index]
}
proc ::GX::scientificHistoryViewerOperation {window index} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    if {[dict get $adapter token] ne [interactiveDocumentSessionToken]} {error {Session changed; reopen this Workspace}}
    return [historyNative entry [dict get $adapter handle] $index]
}
proc ::GX::_historyRestoreAuxiliary {window auxiliary} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    if {![dict exists $adapter callbacks restore_aux]} return
    set restoring [dict get $adapter restoring]
    dict set ::GX::ScientificHistory::viewers $window restoring 1
    try {uplevel #0 [list {*}[dict get $adapter callbacks restore_aux] $auxiliary]} finally {
        if {[dict exists $::GX::ScientificHistory::viewers $window]} {dict set ::GX::ScientificHistory::viewers $window restoring $restoring}
    }
}
proc ::GX::scientificHistoryViewerAuxiliary {window args} {
    if {[llength $args]>1} {error {Usage: scientificHistoryViewerAuxiliary window ?dictionary?}}
    set adapter [dict get $::GX::ScientificHistory::viewers $window];set h [dict get $adapter handle]
    if {$args eq {}} {return [historyNative auxiliary $h]}
    set old [historyNative auxiliary $h]
    try {
        _scientificHistoryGuard $window
        if {[dict get $adapter browsing] || [dict get $adapter restoring]} {error {Finish History browsing or restoration before recording presentation state}}
        set before [dict get [historyNative status $h] revision]
        set receipt [historyNative auxiliary $h [lindex $args 0]]
    } on error {message options} {
        set receipt [historyNative status $h]
        dict set receipt accepted 0;dict set receipt stage auxiliary;dict set receipt error $message
        dict set receipt auxiliary_failed 1;dict set receipt scientific_state_retained 1
        dict set ::GX::ScientificHistory::viewers $window last_auxiliary_error $message
        if {[catch {_historyRestoreAuxiliary $window $old} rollback]} {dict set receipt rollback_error $rollback}
        if {[dict exists $adapter callbacks error]} {catch {uplevel #0 [list {*}[dict get $adapter callbacks error] $receipt]}}
        return $receipt
    }
    if {[dict get $receipt revision]!=$before} {
        dict set ::GX::ScientificHistory::viewers $window accepted_revision [dict get $receipt revision]
        dict set ::GX::ScientificHistory::viewers $window dirty 1
        if {[dict exists $::GX::ScientificHistory::viewers $window discard_on_close]} {dict unset ::GX::ScientificHistory::viewers $window discard_on_close}
        _historyMonitorSchedule $window
    }
    if {[dict exists $::GX::ScientificHistory::viewers $window last_auxiliary_error]} {dict unset ::GX::ScientificHistory::viewers $window last_auxiliary_error}
    return $receipt
}
proc ::GX::_historySyncAuxiliary {window mode} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    if {![dict exists $adapter callbacks capture_aux] || $mode ni [datasetPublicationV2DictDefault [dict get $adapter callbacks] auxiliary_sync_modes {append undo redo branch seek clear}]} return
    if {[catch {
        set auxiliary [uplevel #0 [dict get $adapter callbacks capture_aux]]
        scientificHistoryViewerAuxiliary $window $auxiliary
    } message]} {_historyHookWarning $window $message}
}
proc ::GX::_historyPresentationRow {window row {semantic {}}} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    if {[dict exists $adapter callbacks describe]} {
        set context [dict merge $semantic $row]
        if {[dict exists $semantic patch]} {dict set context patch [dict get $semantic patch]}
        if {[catch {set overrides [uplevel #0 [list {*}[dict get $adapter callbacks describe] $context]];dict size $overrides} message]} {_historyHookWarning $window $message;return $row}
        dict for {field value} $overrides {
            if {$field ni {description kind group group_id group_label}} {_historyHookWarning $window {History description hook may only change presentation metadata};return $row}
            dict set row $field $value
        }
    }
    return $row
}
proc ::GX::scientificHistoryViewerContextAction {window action {payload {}}} {
    set adapter [_scientificHistoryGuard $window]
    if {[dict exists $adapter hook_pending]} {error {Finish or cancel the pending History hook first}}
    if {![dict exists $adapter callbacks context_action]} {error {History owner has no domain context action hook}}
    try {
        return [uplevel #0 [list {*}[dict get $adapter callbacks context_action] $action $payload]]
    } on error {message options} {
        set receipt [dict create status failed accepted 0 error $message action $action]
        if {[dict exists $adapter callbacks error]} {
            uplevel #0 [list {*}[dict get $adapter callbacks error] $receipt]
            return $receipt
        }
        return -options $options $message
    }
}
proc ::GX::scientificHistoryViewerRestoreContext {window} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    return [dict create mode [datasetPublicationV2DictDefault $adapter restore_mode none] cursor [dict get $adapter browse_cursor] browsing [dict get $adapter browsing]]
}
proc ::GX::_historyRestore {window snapshot mode} {
    set wasRestoring [dict get $::GX::ScientificHistory::viewers $window restoring]
    dict set ::GX::ScientificHistory::viewers $window restoring 1
    dict set ::GX::ScientificHistory::viewers $window restore_mode $mode
    set callback [dict get $::GX::ScientificHistory::viewers $window callbacks restore]
    try {
        uplevel #0 [list {*}$callback $snapshot]
        if {$mode in {recovery latest}} {_historyRestoreAuxiliary $window [historyNative auxiliary [_historyHandle $window]]}
    } finally {
        dict unset ::GX::ScientificHistory::viewers $window restore_mode
        dict set ::GX::ScientificHistory::viewers $window restoring $wasRestoring
    }
}
proc ::GX::scientificHistoryViewerGroupExpand {window first} {
    set expanded [datasetPublicationV2DictDefault [dict get $::GX::ScientificHistory::viewers $window] expanded_groups {}]
    set at [lsearch -exact $expanded $first]
    if {$at<0} {lappend expanded $first} else {set expanded [lreplace $expanded $at $at]}
    dict set ::GX::ScientificHistory::viewers $window expanded_groups $expanded
    _historyRefreshSchedule $window
}
proc ::GX::_historyEntries {window} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    set record [dict get $adapter record]
    set grouped [scientificHistoryGroupedEntries $record [dict get $adapter strip_settings grouped]]
    set expanded [datasetPublicationV2DictDefault $adapter expanded_groups {}]
    if {$expanded eq {}} {return $grouped}
    set individual [scientificHistoryGroupedEntries $record 0];set result {}
    foreach row $grouped {
        if {[dict get $row first] in $expanded} {lappend result {*}[lrange $individual [dict get $row first] [dict get $row last]]} else {lappend result $row}
    }
    return $result
}
proc ::GX::_historyIdentity {owner document {channel {}}} {
    set root [_interactiveDocumentRequireSession];file stat $root st
    set identity [list $root $st(dev) $st(ino) $owner]
    if {$document ne {}} {
        set registry [_interactiveDocumentRegistryRead $root]
        if {![dict exists $registry $document]} {error {History Document owner is unavailable}}
        set item [dict get $registry $document]
        if {[dict get $item module_id] ne $owner} {error {History Document belongs to a different module}}
        lappend identity $document [dict get $item generation] [dict get $item provider_id]
    }
    if {$channel ne {}} {lappend identity channel $channel}
    return $identity
}
proc ::GX::_historyOpen {window owner record document {options {}}} {
    _historyNativeRequire
    set root [_interactiveDocumentRequireSession]
    set channel [datasetPublicationV2DictDefault $options channel {}]
    set auxiliary [datasetPublicationV2DictDefault $options auxiliary {}]
    if {$channel ne {} && ![regexp {^[A-Za-z][A-Za-z0-9_]{0,63}$} $channel]} {error {Invalid CORE History channel}}
    set identity [_historyIdentity $owner $document $channel]
    set directory [file join $root metadata history]
    if {$document eq {}} {
        set path [file join $directory drafts "[pid]-[clock microseconds]-[incr ::GX::HistoryService::serial].gxh"]
        lappend identity draft [file tail $path]
        set drafts [scientificHistoryDrafts $owner $channel]
        if {$drafts ne {}} {
            set draft [lindex $drafts 0]
            set choice [_historyRecoveryChoice $window $options {Recover unsaved History} {A verified unsaved History draft remains in this Session. Yes: recover the latest draft. No: archive the draft and start this new Workspace. Cancel: leave it unchanged.}]
            if {$choice eq {cancel}} {error {Unsaved History recovery cancelled}}
            set previous [file join $directory drafts [dict get $draft id]]
            if {$choice eq {yes}} {
                set path $previous;set record [dict get $draft record]
                set auxiliary [dict get $draft auxiliary]
                set identity [_historyIdentity $owner {} $channel];lappend identity draft [file tail $path]
            } else {_historyRetirePath $previous discarded}
        }
    } else {set path [file join $directory "$document[expr {$channel eq {} ? {} : ".$channel"}].gxh"]}
    # Refuse symlink ownership transitions before the native O_NOFOLLOW/open lock.
    set current $root
    foreach part [file split [string range $path [expr {[string length $root]+1}] end]] {
        set current [file join $current $part]
        if {![catch {file lstat $current state}] && $state(type) eq {link}} {error {History symlinks are forbidden}}
    }
    file mkdir [file dirname $path]
    if {[file exists $path] || [file exists "$path.checkpoint"]} {
        set recovered [historyNative recover $path $identity]
        if {![dict exists $options capture_aux] && ![dict exists $options auxiliary]} {set auxiliary [dict get $recovered auxiliary]}
        if {[dict get $recovered record] ne $record || [dict get $recovered auxiliary] ne $auxiliary} {
            set choice [_historyRecoveryChoice $window $options {Recover History} {A verified native History journal contains state different from the saved Document. Yes: recover the journal. No: retain the saved Document and archive the journal. Cancel: leave both unchanged.}]
            if {$choice eq {cancel}} {error {History recovery cancelled; saved Document and journal preserved}}
            if {$choice eq {yes}} {set record [dict get $recovered record];set auxiliary [dict get $recovered auxiliary]} else {
                set suffix ".retired-[clock microseconds]"
                foreach candidate [list $path "$path.checkpoint"] {if {[file exists $candidate]} {file rename -- $candidate "$candidate$suffix"}}
            }
        }
    }
    return [list [historyNative open $owner $record $path $identity $auxiliary] $path]
}
proc ::GX::_historyAccepted {window receipt {semantic {}}} {
    if {[dict exists $::GX::ScientificHistory::viewers $window accepted_revision] && [dict get $::GX::ScientificHistory::viewers $window accepted_revision]==[dict get $receipt revision]} {return $receipt}
    dict set ::GX::ScientificHistory::viewers $window accepted_revision [dict get $receipt revision]
    set h [_historyHandle $window]
    set prior [dict get $::GX::ScientificHistory::viewers $window record]
    set count [dict get $receipt count]
    set old [llength [dict get $prior steps]]
    if {$count<$old} {dict set prior steps [lrange [dict get $prior steps] 0 [expr {$count-1}]]}
    foreach row [historyNative rows $h $old [expr {max(0,$count-$old)}]] {
        dict lappend prior steps [_historyPresentationRow $window $row $semantic]
    }
    dict set prior cursor [dict get $receipt cursor]
    dict set ::GX::ScientificHistory::viewers $window record $prior
    dict set ::GX::ScientificHistory::viewers $window browse_cursor [dict get $receipt cursor]
    dict set ::GX::ScientificHistory::viewers $window browsing 0
    dict set ::GX::ScientificHistory::viewers $window dirty 1
    if {[dict exists $::GX::ScientificHistory::viewers $window discard_on_close]} {dict unset ::GX::ScientificHistory::viewers $window discard_on_close}
    set callbacks [dict get $::GX::ScientificHistory::viewers $window callbacks]
    if {[dict exists $callbacks accepted] && [catch {uplevel #0 [list {*}[dict get $callbacks accepted] $receipt]} message]} {_historyHookWarning $window $message}
    _historyMonitorSchedule $window
    _historyRefreshSchedule $window
    if {[dict exists $::GX::ScientificHistory::viewers $window last_hook_error]} {dict set receipt hook_failed 1;dict set receipt hook_error [dict get $::GX::ScientificHistory::viewers $window last_hook_error]}
    return $receipt
}
proc ::GX::_historyRefreshSchedule {window} {
    if {![dict exists $::GX::ScientificHistory::viewers $window refresh_timer]} {
        dict set ::GX::ScientificHistory::viewers $window refresh_timer [after 0 [list ::GX::_historyRefresh $window]]
    }
}
proc ::GX::_historyRefresh {window} {
    if {![dict exists $::GX::ScientificHistory::viewers $window]} return
    dict unset ::GX::ScientificHistory::viewers $window refresh_timer
    scientificHistoryViewerRefresh $window
}
proc ::GX::_historyMonitorSchedule {window} {
    if {![dict exists $::GX::ScientificHistory::viewers $window persistence_timer]} {
        dict set ::GX::ScientificHistory::viewers $window persistence_timer [after 100 [list ::GX::_historyMonitor $window]]
    }
}
proc ::GX::_historyMonitor {window} {
    if {![dict exists $::GX::ScientificHistory::viewers $window]} return
    dict unset ::GX::ScientificHistory::viewers $window persistence_timer
    set status [scientificHistoryViewerStatus $window]
    if {[dict get $status failed]} {
        dict set ::GX::HistoryService::failures $window $status
        set callbacks [dict get $::GX::ScientificHistory::viewers $window callbacks]
        if {[dict exists $callbacks error]} {uplevel #0 [list {*}[dict get $callbacks error] $status]}
        if {[llength [info commands winfo]] && [winfo exists $window]} {event generate $window <<HistoryPersistenceFailed>> -data $status}
        return
    }
    if {[dict get $status pending]} {_historyMonitorSchedule $window}
}
# Fast submission returns an explicit acceptance receipt. The legacy Changed API
# retains its complete-record return contract as an explicit compatibility read.
proc ::GX::scientificHistoryViewerRecordOperation {window description {snapshot @gxtxt.history.capture}} {
    set adapter [_scientificHistoryGuard $window]
    if {[dict get $adapter restoring]} {return [scientificHistoryViewerStatus $window]}
    if {[dict get $adapter browsing]} {error {History browsing is read-only}}
    if {[dict exists $adapter hook_pending]} {error {A History preparation hook is still pending}}
    if {$snapshot eq {@gxtxt.history.capture}} {set snapshot [uplevel #0 [dict get $adapter callbacks capture]]}
    set before [historyNative state [dict get $adapter handle]]
    try {set receipt [historyNative append [dict get $adapter handle] $snapshot $description]} on error {message options} {
        dict set ::GX::ScientificHistory::viewers $window restoring 1
        try {_historyRestore $window $before rollback} finally {dict set ::GX::ScientificHistory::viewers $window restoring 0}
        return -options $options $message
    }
    dict set receipt transition append
    set receipt [_historyAccepted $window $receipt]
    dict set receipt scientific_revision [dict get $receipt revision]
    _historySyncAuxiliary $window append
    return [dict merge $receipt [scientificHistoryViewerStatus $window]]
}
proc ::GX::scientificHistoryViewerSubmitPatch {window patch description {semantic {}}} {
    if {[catch {dict size $semantic}]} {error {History semantic operation must be an inert dictionary}}
    if {[dict exists $semantic api_id] && [dict get $semantic api_id] ni {SCIENTIFIC_RECIPE_API_v1 NATIVE_2D_GEOMETRY_API_v1 NATIVE_3D_GEOMETRY_API_v1}} {error {Unsupported History operation API}}
    if {[dict exists $semantic api_version] && [dict get $semantic api_version] ne {1}} {error {Unsupported History operation API version}}
    set adapter [_scientificHistoryGuard $window]
    if {[dict get $adapter browsing] || [dict get $adapter restoring] || [dict exists $adapter hook_pending]} {error {History is not editable}}
    set receipt [historyNative appendPatch [dict get $adapter handle] $patch $description $semantic]
    dict set receipt transition append
    set receipt [_historyAccepted $window $receipt $semantic]
    dict set receipt scientific_revision [dict get $receipt revision]
    _historySyncAuxiliary $window append
    return [dict merge $receipt [scientificHistoryViewerStatus $window]]
}
proc ::GX::scientificHistoryViewerFlush {window {timeout 30000} {project 1}} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    if {[dict exists $adapter hook_pending]} {error {Finish or cancel the pending History hook before Save or Close}}
    if {$project && [dict get $adapter browsing]} {error {Return to latest before projecting or saving History}}
    set h [dict get $adapter handle]
    historyNative flush $h $timeout
    if {$project && [dict get $adapter dirty]} {
        set document [dict get $adapter document_id]
        set key [list [dict get $adapter session] $document]
        if {![dict exists $::GX::HistoryService::barriers $key]} {
            dict set ::GX::HistoryService::barriers $key 1
            try {
                _scientificHistoryGuard $window
                uplevel #0 [list {*}[dict get $adapter callbacks commit] [historyNative record $h]]
                dict set ::GX::ScientificHistory::viewers $window dirty 0
            } finally {dict unset ::GX::HistoryService::barriers $key}
        }
    }
    return [historyNative status $h]
}
proc ::GX::_historyDocumentBarrier {document} {
    if {![info exists ::GX::ScientificHistory::viewers] || $::GX::currentSession eq {}} return
    set key [list [file normalize $::GX::currentSession] $document]
    if {[dict exists $::GX::HistoryService::barriers $key]} return
    dict for {window adapter} $::GX::ScientificHistory::viewers {
        if {[dict get $adapter document_id] eq $document && [dict get $adapter session] eq [lindex $key 0] && [dict get $adapter dirty]} {
            scientificHistoryViewerFlush $window
        }
    }
}
proc ::GX::scientificHistoryViewerBindDocument {window document} {
    set adapter [_scientificHistoryGuard $window]
    if {[dict get $adapter document_id] eq $document} return
    set record [historyNative record [dict get $adapter handle]]
    set callbacks [dict get $adapter callbacks];dict set callbacks auxiliary [historyNative auxiliary [dict get $adapter handle]]
    lassign [_historyOpen $window [dict get $adapter owner] $record $document $callbacks] h path
    try {historyNative close [dict get $adapter handle]} on error {message options} {
        historyNative close $h
        return -options $options $message
    }
    dict set ::GX::ScientificHistory::viewers $window handle $h
    dict set ::GX::ScientificHistory::viewers $window path $path
    dict set ::GX::ScientificHistory::viewers $window document_id $document
    dict set ::GX::ScientificHistory::viewers $window document_generation [dict get [interactiveDocumentMetadata $document] generation]
    dict set ::GX::ScientificHistory::viewers $window accepted_revision [dict get [historyNative status $h] revision]
    if {[dict get $adapter document_id] eq {}} {_historyRetirePath [dict get $adapter path] bound}
}
# Optional asynchronous preparation contract. Hooks run on the interpreter's
# owning thread and must return promptly; independently owned work may complete
# later with scientificHistoryHookComplete. CORE owns token, ordering and cancel.
proc ::GX::scientificHistoryViewerRequest {window input description completion} {
    set adapter [_scientificHistoryGuard $window]
    if {[dict exists $adapter hook_pending]} {error {A History hook is already pending}}
    if {![dict exists $adapter callbacks prepare_async]} {error {History host has no asynchronous preparation hook}}
    set token "history-hook#[incr ::GX::HistoryService::serial]"
    dict set ::GX::HistoryService::requests $token [dict create window $window input $input description $description completion $completion revision [dict get [scientificHistoryViewerStatus $window] revision] token [dict get $adapter token]]
    dict set ::GX::ScientificHistory::viewers $window hook_pending $token
    after 0 [list ::GX::_historyHookStart $token]
    return [dict create status pending token $token]
}
proc ::GX::_historyHookStart {token} {
    if {![dict exists $::GX::HistoryService::requests $token]} return
    set request [dict get $::GX::HistoryService::requests $token];set w [dict get $request window]
    if {[catch {
        set adapter [_scientificHistoryGuard $w]
        uplevel #0 [list {*}[dict get $adapter callbacks prepare_async] $token [dict get $request input]]
    } message]} {scientificHistoryHookComplete $token failed $message}
}
proc ::GX::scientificHistoryHookComplete {token status data} {
    if {![dict exists $::GX::HistoryService::requests $token]} {return [dict create status cancelled]}
    set request [dict get $::GX::HistoryService::requests $token];dict unset ::GX::HistoryService::requests $token
    set w [dict get $request window]
    if {![dict exists $::GX::ScientificHistory::viewers $w]} {return [dict create status cancelled]}
    dict unset ::GX::ScientificHistory::viewers $w hook_pending
    if {$status eq {ok}} {
        if {[catch {
            _scientificHistoryGuard $w
            if {[dict get [scientificHistoryViewerStatus $w] revision] != [dict get $request revision]} {error {History changed while preparation was pending}}
            set result [scientificHistoryViewerRecordOperation $w [dict get $request description] $data]
        } message]} {set result [dict create status failed error $message]}
    } else {set result [dict create status $status error $data]}
    if {[dict get $request completion] ne {}} {uplevel #0 [list {*}[dict get $request completion] $result]}
    return $result
}
proc ::GX::scientificHistoryHookCancel {window} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    if {![dict exists $adapter hook_pending]} return
    set token [dict get $adapter hook_pending]
    if {[dict exists $adapter callbacks cancel]} {uplevel #0 [list {*}[dict get $adapter callbacks cancel] $token]}
    return [scientificHistoryHookComplete $token cancelled {History preparation cancelled}]
}
proc ::GX::scientificHistoryFlushAll {} {
    dict for {window adapter} $::GX::ScientificHistory::viewers {
        set project [expr {[dict get $adapter token] eq $::GX::DocumentSessionScope::token}]
        scientificHistoryViewerFlush $window 30000 $project
    }
}
proc ::GX::scientificHistoryPopup {window menu x y} {
    set window [_historyDialogParent $window]
    update idletasks
    set left [winfo rootx $window];set top [winfo rooty $window]
    set width [winfo reqwidth $menu];set height [winfo reqheight $menu]
    set x [expr {max($left,min($x,$left+[winfo width $window]-$width))}]
    # History controls sit near the bottom of a Viewer: post upward and keep
    # the popup inside this application window, including multi-monitor setups.
    set y [expr {max($top,min($y-$height,$top+[winfo height $window]-$height))}]
    tk_popup $menu $x $y
}
proc ::GX::_historyResourceReferences {} {
    set result {};set active {}
    dict for {key failure} $::GX::HistoryService::failures {
        if {![catch {dict get $failure handle} handle] && [dict get $failure session] eq [_interactiveDocumentRequireSession]} {lappend result [historyNative record $handle] [historyNative auxiliary $handle]}
    }
    dict for {window adapter} $::GX::ScientificHistory::viewers {
        if {[dict get $adapter session] ne [_interactiveDocumentRequireSession]} continue
        lappend active [dict get $adapter document_id]
        lappend result [historyNative record [dict get $adapter handle]] [historyNative auxiliary [dict get $adapter handle]]
    }
    set seen {}
    foreach item [interactiveDocumentList] {
        set document [dict get $item id]
        set directory [file join [_interactiveDocumentRequireSession] metadata history]
        foreach path [glob -nocomplain -directory $directory "$document.gxh" "$document.*.gxh" "$document.gxh.checkpoint" "$document.*.gxh.checkpoint"] {
            if {[string match *.checkpoint $path]} {set path [string range $path 0 end-11]}
            if {$path in $seen} continue
            lappend seen $path
            set live 0
            dict for {window adapter} $::GX::ScientificHistory::viewers {if {[dict get $adapter path] eq $path} {set live 1;break}}
            if {$live} continue
            set tail [file tail $path];set channel {}
            set middle [string range $tail [expr {[string length $document]+1}] end-4]
            if {$tail ne "$document.gxh"} {set channel $middle}
            _historyNativeRequire
            set recovered [historyNative recover $path [_historyIdentity [dict get $item module_id] $document $channel]]
            lappend result [dict get $recovered record] [dict get $recovered auxiliary]
        }
    }
    return $result
}
proc ::GX::_historyWorkspaceSave {context} {
    set window [dict get $context parent]
    if {[dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerFlush $window}
    set result [uplevel #0 [dict get $context callbacks save]]
    if {[dict exists $::GX::ScientificHistory::viewers $window]} {
        set document [_workspaceHostCurrent $context]
        if {$document ne {}} {scientificHistoryViewerBindDocument $window $document}
        scientificHistoryViewerFlush $window
    }
    return $result
}
proc ::GX::_historyRetirePath {path reason} {
    set suffix ".$reason-[clock microseconds]"
    foreach candidate [list $path "$path.checkpoint"] {if {[file exists $candidate]} {file rename -- $candidate "$candidate$suffix"}}
}
proc ::GX::scientificHistoryDrafts {owner {channel {}}} {
    _historyNativeRequire
    set directory [file join [_interactiveDocumentRequireSession] metadata history drafts]
    set result {};set paths {}
    foreach path [glob -nocomplain -directory $directory *.gxh *.gxh.checkpoint] {
        if {[string match *.checkpoint $path]} {set path [string range $path 0 end-11]}
        if {$path in $paths} continue
        lappend paths $path
        set identity [_historyIdentity $owner {} $channel];lappend identity draft [file tail $path]
        if {[catch {set recovered [historyNative recover $path $identity]} message]} {
            if {![string match {*owner*} $message] && ![string match {*active writer*} $message] && ![string match {*identity*} $message]} {
                dict set ::GX::HistoryService::failures [file tail $path] $message
                return -code error -errorcode {GX HISTORY DRAFT_CORRUPT} "Unsaved History draft [file tail $path] cannot be verified: $message"
            }
            continue
        }
        lappend result [dict create id [file tail $path] modified [file mtime "$path.checkpoint"] record [dict get $recovered record] auxiliary [dict get $recovered auxiliary] revision [dict get $recovered revision]]
        if {[llength $result]>32} {
            set ranked [lsort -decreasing -integer -index 1 [lmap item $result {list [dict get $item id] [dict get $item modified] $item}]]
            set result [lmap row [lrange $ranked 0 31] {lindex $row 2}]
        }
    }
    set sorted [lsort -decreasing -integer -index 1 [lmap item $result {list [dict get $item id] [dict get $item modified] $item}]]
    return [lmap row $sorted {lindex $row 2}]
}
proc ::GX::scientificHistoryFailureRecord {key} {
    set failure [dict get $::GX::HistoryService::failures $key]
    return [historyNative record [dict get $failure handle]]
}
proc ::GX::_historyRecoveryChoice {window options title message} {
    if {[dict exists $options recovery_choice]} {
        set choice [dict get $options recovery_choice]
        if {$choice ni {recover saved cancel}} {error {Choose recover, saved or cancel explicitly}}
        return [dict get {recover yes saved no cancel cancel} $choice]
    }
    if {![llength [info commands tk_messageBox]]} {error {History recovery requires an explicit recovery_choice or an owning GUI parent}}
    set parent [datasetPublicationV2DictDefault $options parent $window]
    return [tk_messageBox -parent $parent -type yesnocancel -default cancel -icon warning -title $title -message $message]
}
proc ::GX::scientificHistoryContextAttach {owner callbacks {record {}}} {
    set context "history-context#[incr ::GX::HistoryService::serial]"
    if {![dict exists $callbacks parent]} {dict set callbacks parent .}
    scientificHistoryViewerAttach $context $owner $callbacks $record
    return $context
}
proc ::GX::scientificHistoryContextClose {context {project 1}} {
    scientificHistoryViewerFlush $context 30000 $project
    _scientificHistoryDestroyed $context $context
}
proc ::GX::scientificHistoryViewerDetach {window {project 1}} {
    scientificHistoryContextClose $window $project
}
proc ::GX::scientificHistoryViewerDiscard {window} {
    scientificHistoryHookCancel $window
    set status [scientificHistoryViewerFlush $window 30000 0]
    dict set ::GX::ScientificHistory::viewers $window discard_on_close 1
    return $status
}
proc ::GX::scientificHistoryViewerSeek {window index {restore 1}} {
    if {![string is boolean -strict $restore]} {error {History restoration flag must be boolean}}
    set adapter [_scientificHistoryGuard $window];set h [dict get $adapter handle]
    if {[dict exists $adapter hook_pending]} {error {A History preparation hook is pending}}
    set target [historyNative state $h $index];set previous [historyNative state $h]
    if {!$restore && [uplevel #0 [dict get $adapter callbacks capture]] ne $target} {error {Live scientific state does not match the requested History checkpoint}}
    dict set ::GX::ScientificHistory::viewers $window restoring 1
    try {
        if {$restore} {_historyRestore $window $target seek}
        set receipt [historyNative navigate $h $index]
    } on error {message options} {
        if {$restore} {_historyRestore $window $previous rollback}
        return -options $options $message
    } finally {dict set ::GX::ScientificHistory::viewers $window restoring 0}
    dict set receipt transition seek
    set receipt [_historyAccepted $window $receipt]
    _historySyncAuxiliary $window seek
    return [dict merge $receipt [scientificHistoryViewerStatus $window]]
}
proc ::GX::scientificHistoryViewerReset {window snapshot} {
    set adapter [_scientificHistoryGuard $window]
    set receipt [historyNative clear [dict get $adapter handle] $snapshot]
    dict set ::GX::ScientificHistory::viewers $window record [historyNative summary [dict get $adapter handle]]
    dict set receipt transition reset
    return [_historyAccepted $window $receipt]
}

proc ::GX::_historyDialogParent {window} {
    return [datasetPublicationV2DictDefault [dict get $::GX::ScientificHistory::viewers $window callbacks] parent $window]
}

proc ::GX::scientificHistoryContextSetParent {context parent} {
    if {![winfo exists $parent]} {error {History presentation parent is unavailable}}
    dict set ::GX::ScientificHistory::viewers $context callbacks parent $parent
}

proc ::GX::_historyHookWarning {window message} {
    dict set ::GX::ScientificHistory::viewers $window last_hook_error $message
    set receipt [dict create status callback_failed accepted 1 failed 0 stage callback error $message]
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    if {[dict exists $adapter callbacks error]} {catch {uplevel #0 [list {*}[dict get $adapter callbacks error] $receipt]}}
    if {[llength [info commands winfo]] && [winfo exists [_historyDialogParent $window]]} {catch {event generate [_historyDialogParent $window] <<HistoryHookFailed>> -data $receipt}}
}
