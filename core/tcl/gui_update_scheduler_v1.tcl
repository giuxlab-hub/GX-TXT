# SPDX-License-Identifier: GPL-3.0-or-later
# Opt-in host scheduling only. Callers retain input, model and rendering ownership.
namespace eval ::GX::GuiUpdateScheduler {variable instances;variable serial 0}
proc ::GX::guiUpdateSchedulerApiInfo {} {
    return [dict create api_id GUI_UPDATE_SCHEDULER_API_v1 api_version 1 host_only 1 operations {guiUpdateSchedulerCreate guiUpdateSchedulerConfigure guiUpdateSchedulerRequest guiUpdateSchedulerFlush guiUpdateSchedulerFinish guiUpdateSchedulerCancel guiUpdateSchedulerDispose guiUpdateSchedulerDescribe}]
}
proc ::GX::GuiUpdateScheduler::options {base changes} {
    dict for {key value} $changes {
        if {![dict exists $base $key]} {error "Unknown GUI scheduling option '$key'"}
        dict set base $key $value
    }
    if {[dict get $base policy] ni {coalesced adaptive}} {error {Scheduling policy must be coalesced or adaptive}}
    foreach key {normal_ms adaptive_ms activity_window_ms quiet_ms} {
        set value [dict get $base $key]
        if {![string is integer -strict $value] || $value<1 || $value>60000} {error "$key must be 1..60000 milliseconds"}
    }
    set count [dict get $base rapid_count]
    if {![string is integer -strict $count] || $count<2 || $count>512} {error {rapid_count must be 2..512}}
    if {[dict get $base adaptive_ms]<[dict get $base normal_ms]} {error {adaptive_ms must be at least normal_ms}}
    foreach key {guard error_callback} {llength [dict get $base $key]}
    return $base
}
proc ::GX::GuiUpdateScheduler::get {id} {
    variable instances
    if {![info exists instances($id)]} {error "Unknown GUI update scheduler '$id'"}
    return $instances($id)
}
proc ::GX::guiUpdateSchedulerCreate {owner callback {options {}}} {
    package require Tk
    if {![winfo exists $owner]} {error {GUI scheduler needs an existing owner widget}}
    if {![llength $callback]} {error {GUI scheduler needs an update callback prefix}}
    set config [::GX::GuiUpdateScheduler::options [dict create policy coalesced normal_ms 16 adaptive_ms 100 activity_window_ms 80 rapid_count 8 quiet_ms 80 guard {} error_callback {}] $options]
    set id gui-update[incr ::GX::GuiUpdateScheduler::serial]
    set tag GXGuiUpdate:$id
    set ::GX::GuiUpdateScheduler::instances($id) [dict create owner $owner incarnation [winfo id $owner] tag $tag callback $callback config $config frame {} quiet {} pending 0 running 0 force 0 mode normal activity {} last_update {} requests 0 updates 0 failures 0 mode_changes 0 last_error {}]
    bindtags $owner [concat [bindtags $owner] [list $tag]]
    bind $tag <Destroy> [list ::GX::GuiUpdateScheduler::destroyed $id %W]
    return $id
}
proc ::GX::GuiUpdateScheduler::destroyed {id widget} {
    variable instances
    if {[info exists instances($id)] && [dict get $instances($id) owner] eq $widget} {::GX::guiUpdateSchedulerDispose $id}
}
proc ::GX::GuiUpdateScheduler::valid {id} {
    variable instances
    if {![info exists instances($id)]} {return 0}
    set s $instances($id);set owner [dict get $s owner]
    set valid [expr {[winfo exists $owner] && [winfo id $owner] eq [dict get $s incarnation]}]
    set guard [dict get $s config guard]
    if {$valid && $guard ne {}} {
        if {[catch {uplevel #0 $guard} allowed] || ![string is boolean -strict $allowed] || !$allowed} {set valid 0}
    }
    if {!$valid} {::GX::guiUpdateSchedulerDispose $id}
    return [expr {$valid && [info exists instances($id)]}]
}
proc ::GX::GuiUpdateScheduler::cancelTimer {id key} {
    variable instances
    set timer [dict get $instances($id) $key]
    if {$timer ne {}} {after cancel $timer;dict set instances($id) $key {}}
}
proc ::GX::GuiUpdateScheduler::normal {id} {
    variable instances
    cancelTimer $id quiet
    if {[dict get $instances($id) mode] ne {normal}} {dict incr instances($id) mode_changes}
    dict set instances($id) mode normal
    dict set instances($id) activity {}
}
proc ::GX::GuiUpdateScheduler::arm {id} {
    variable instances
    set s $instances($id)
    if {![dict get $s pending] || [dict get $s running] || [dict get $s frame] ne {}} return
    set delay [dict get $s config normal_ms]
    if {[dict get $s force]} {
        set delay 0
    } elseif {[dict get $s mode] eq {reduced} && [dict get $s last_update] ne {}} {
        set delay [expr {max(0,[dict get $s last_update]+[dict get $s config adaptive_ms]-[clock clicks -milliseconds])}]
    }
    dict set instances($id) frame [after $delay [list ::GX::GuiUpdateScheduler::dispatch $id]]
}
proc ::GX::guiUpdateSchedulerConfigure {id options} {
    set s [::GX::GuiUpdateScheduler::get $id]
    set config [::GX::GuiUpdateScheduler::options [dict get $s config] $options]
    ::GX::GuiUpdateScheduler::cancelTimer $id frame
    ::GX::GuiUpdateScheduler::normal $id
    dict set ::GX::GuiUpdateScheduler::instances($id) config $config
    ::GX::GuiUpdateScheduler::arm $id
    return $config
}
proc ::GX::guiUpdateSchedulerRequest {id {activity auto}} {
    ::GX::GuiUpdateScheduler::get $id
    if {$activity ni {auto normal intensive}} {error {Activity must be auto, normal or intensive}}
    if {![::GX::GuiUpdateScheduler::valid $id]} {return 0}
    upvar #0 ::GX::GuiUpdateScheduler::instances($id) s
    dict incr s requests;dict set s pending 1
    if {$activity eq {normal}} {::GX::GuiUpdateScheduler::normal $id}
    if {[dict get $s config policy] eq {adaptive} && $activity ne {normal}} {
        set now [clock clicks -milliseconds];set times {}
        foreach t [dict get $s activity] {if {$now-$t<=[dict get $s config activity_window_ms]} {lappend times $t}}
        lappend times $now
        set count [dict get $s config rapid_count]
        dict set s activity [lrange $times end-[expr {$count-1}] end]
        if {$activity eq {intensive} || [llength $times]>=$count} {
            if {[dict get $s mode] ne {reduced}} {
                dict set s mode reduced;dict incr s mode_changes
                ::GX::GuiUpdateScheduler::cancelTimer $id frame
            }
            ::GX::GuiUpdateScheduler::cancelTimer $id quiet
            dict set s quiet [after [dict get $s config quiet_ms] [list ::GX::GuiUpdateScheduler::settled $id]]
        }
    }
    ::GX::GuiUpdateScheduler::arm $id
    return 1
}
proc ::GX::GuiUpdateScheduler::settled {id} {
    variable instances
    if {![info exists instances($id)]} return
    dict set instances($id) quiet {}
    ::GX::guiUpdateSchedulerFinish $id
}
proc ::GX::GuiUpdateScheduler::dispatch {id} {
    variable instances
    if {![valid $id]} return
    cancelTimer $id frame
    if {[dict get $instances($id) running] || ![dict get $instances($id) pending]} return
    dict set instances($id) pending 0
    dict set instances($id) force 0
    dict set instances($id) running 1
    dict set instances($id) last_update [clock clicks -milliseconds]
    dict incr instances($id) updates
    set callback [dict get $instances($id) callback]
    set code [catch {uplevel #0 $callback} message opts]
    if {![info exists instances($id)]} {
        if {$code} {return -options $opts $message}
        return
    }
    dict set instances($id) running 0
    if {$code} {
        dict incr instances($id) failures
        dict set instances($id) last_error $message
        ::GX::guiUpdateSchedulerCancel $id
        set handler [dict get $instances($id) config error_callback]
        if {$handler ne {}} {uplevel #0 [list {*}$handler $id $message $opts];return}
        return -options $opts $message
    }
    arm $id
}
proc ::GX::guiUpdateSchedulerFlush {id} {
    ::GX::GuiUpdateScheduler::get $id
    if {![::GX::GuiUpdateScheduler::valid $id]} {return 0}
    if {![dict get $::GX::GuiUpdateScheduler::instances($id) pending]} {return 0}
    dict set ::GX::GuiUpdateScheduler::instances($id) force 1
    if {[dict get $::GX::GuiUpdateScheduler::instances($id) running]} {return 1}
    ::GX::GuiUpdateScheduler::dispatch $id
    return 1
}
proc ::GX::guiUpdateSchedulerFinish {id} {
    ::GX::GuiUpdateScheduler::get $id
    ::GX::GuiUpdateScheduler::normal $id
    return [::GX::guiUpdateSchedulerFlush $id]
}
proc ::GX::guiUpdateSchedulerCancel {id} {
    if {![info exists ::GX::GuiUpdateScheduler::instances($id)]} return
    ::GX::GuiUpdateScheduler::cancelTimer $id frame
    ::GX::GuiUpdateScheduler::normal $id
    dict set ::GX::GuiUpdateScheduler::instances($id) pending 0
    dict set ::GX::GuiUpdateScheduler::instances($id) force 0
}
proc ::GX::guiUpdateSchedulerDispose {id} {
    if {![info exists ::GX::GuiUpdateScheduler::instances($id)]} return
    set s $::GX::GuiUpdateScheduler::instances($id)
    ::GX::guiUpdateSchedulerCancel $id
    set owner [dict get $s owner];set tag [dict get $s tag]
    if {[winfo exists $owner]} {
        set tags [bindtags $owner];set index [lsearch -exact $tags $tag]
        if {$index>=0} {bindtags $owner [lreplace $tags $index $index]}
    }
    bind $tag <Destroy> {}
    unset ::GX::GuiUpdateScheduler::instances($id)
}
proc ::GX::guiUpdateSchedulerDescribe {id} {
    return [dict remove [::GX::GuiUpdateScheduler::get $id] frame quiet tag activity callback incarnation]
}
