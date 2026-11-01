# SPDX-License-Identifier: GPL-3.0-or-later
# Typed archive/lifecycle adapter. Filtering, search, classification and display
# policy belong to the authored C++ Viewer; no arbitrary file/Tcl access is given.
namespace eval ::GX::ViewerDiagnostics {variable forms {}}
proc ::GX::_viewerDiagnosticsForm {window component} {
    if {![viewerGuiDesignGuard $window]} {error {Diagnostics Viewer lifetime ended}}
    set definition [viewerGuiDesignComponent $window $component]
    set props [dict get $definition properties]
    if {[dict get $definition type] ne {section} || [datasetPublicationV2DictDefault $props diagnostics_owner {}] ne {stderr}} {error {Declare an STDERR consultation form}}
    foreach key {diagnostics_log diagnostics_records diagnostics_status diagnostics_changed} {dict get $props $key}
    return $props
}
proc ::GX::_viewerDiagnosticsJsonString {value} {viewerDevelopmentJsonString $value}
proc ::GX::_viewerDiagnosticsStatusJson {status} {
    set fields {}
    dict for {key value} $status {
        if {$key in {config counters generation_counters}} continue
        # String values remain strings; only documented integral counters are
        # numbers. Native origin information is never inferred from messages.
        if {[string is entier -strict $value]} {set encoded $value} else {set encoded [viewerDevelopmentJsonString $value]}
        lappend fields "[viewerDevelopmentJsonString $key]:$encoded"
    }
    if {$::GX::StderrDiagnostics::applyError ne {}} {lappend fields "\"configuration_error\":[viewerDevelopmentJsonString $::GX::StderrDiagnostics::applyError]"}
    return \{[join $fields ,]\}
}
proc ::GX::_viewerDiagnosticsResultJson {operation result} {
    if {$operation in {status changed}} {return [_viewerDiagnosticsStatusJson $result]}
    set fields {}
    dict for {key value} $result {
        if {$key eq {records}} {
            set rows {};foreach record $value {lappend rows [dict get $record raw_json]}
            set encoded \[[join $rows ,]\]
        } elseif {$key eq {files}} {
            set rows {};foreach file $value {lappend rows [_viewerDiagnosticsStatusJson $file]}
            set encoded \[[join $rows ,]\]
        } elseif {$key eq {config}} {
            # Metadata has a bounded file count. It is consultation metadata,
            # not a grant to open those paths from authored code.
            set encoded [viewerDevelopmentJsonString $value]
        } elseif {$key in {cursor path error state message status}} {set encoded [viewerDevelopmentJsonString $value]
        } elseif {[string is entier -strict $value]} {set encoded $value
        } else {set encoded [viewerDevelopmentJsonString $value]}
        lappend fields "[viewerDevelopmentJsonString $key]:$encoded"
    }
    return \{[join $fields ,]\}
}
proc ::GX::_viewerDiagnosticsDeliver {window form operation request result} {
    variable ::GX::ViewerDiagnostics::forms
    if {![dict exists $::GX::ViewerDevelopment::windows $window] || ![winfo exists $window]} return
    set key [list $window $form]
    set data [format {{"operation":%s,"request_id":%s,"result":%s}} [viewerDevelopmentJsonString $operation] [viewerDevelopmentJsonString $request] [_viewerDiagnosticsResultJson $operation $result]]
    if {[string length [encoding convertto utf-8 $data]]>1048576} {error {Diagnostic response exceeds the public Viewer event budget}}
    set row [datasetPublicationV2DictDefault $forms $key [dict create queue {}]]
    if {$operation eq {changed}} {
        # One latest status is enough while an export chooser or native event
        # owns the GUI. Archive completions retain their separate ordered queue.
        dict set row changed $data
    } else {
        if {[llength [dict get $row queue]]>=8} {error {Diagnostics delivery queue is full; pause or cancel outstanding requests}}
        dict lappend row queue $data
    }
    dict set forms $key $row
    if {![dict exists $forms $key delivery]} {dict set forms $key delivery [after idle [list ::GX::_viewerDiagnosticsDispatch $window $form]]}
}
proc ::GX::_viewerDiagnosticsDispatch {window form} {
    variable ::GX::ViewerDiagnostics::forms
    set key [list $window $form]
    if {![dict exists $forms $key]} return
    catch {dict unset forms $key delivery}
    if {![dict exists $::GX::ViewerDevelopment::windows $window] || ![viewerGuiDesignGuard $window]} {_viewerDiagnosticsDispose $window;return}
    set record [dict get $::GX::ViewerDevelopment::windows $window]
    if {[dict get $record busy] ne {} || [dict get $record status] eq {RUNNING}} {
        # The event owner resumes queued delivery on completion. No retry poll
        # runs while a native callback or export chooser occupies that owner.
        return
    }
    if {[dict get $record status] in {FAILED SOURCE_CHANGED TIMED_OUT}} {_viewerDiagnosticsDispose $window;return}
    set queue [datasetPublicationV2DictDefault [dict get $forms $key] queue {}]
    if {$queue ne {}} {
        set data [lindex $queue 0]
        dict set forms $key queue [lrange $queue 1 end]
    } elseif {[dict exists $forms $key changed]} {
        set data [dict get $forms $key changed]
        dict unset forms $key changed
    } else {return}
    dict set ::GX::ViewerDevelopment::windows $window event_data $data
    set props [_viewerDiagnosticsForm $window $form]
    viewerDevelopmentInvoke $window [dict get $props diagnostics_changed]
    if {[dict exists $forms $key] && ![dict exists $forms $key delivery] && ([dict get $forms $key queue] ne {} || [dict exists $forms $key changed])} {dict set forms $key delivery [after idle [list ::GX::_viewerDiagnosticsDispatch $window $form]]}
}
proc ::GX::_viewerDiagnosticsResume {window} {
    variable ::GX::ViewerDiagnostics::forms
    dict for {key row} $forms {
        if {[lindex $key 0] ne $window || [dict exists $row delivery]} continue
        if {[datasetPublicationV2DictDefault $row queue {}] ne {} || [dict exists $row changed]} {
            dict set forms $key delivery [after idle [list ::GX::_viewerDiagnosticsDispatch $window [lindex $key 1]]]
        }
    }
}
proc ::GX::_viewerDiagnosticsChanged {window form status} {
    variable ::GX::ViewerDiagnostics::forms
    if {![viewerGuiDesignGuard $window]} {_viewerDiagnosticsDispose $window;return}
    set key [list $window $form]
    set signature {};foreach field {state generation written_records dropped_records last_error} {lappend signature [datasetPublicationV2DictDefault $status $field {}]}
    if {[datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $forms $key {}] signature {}] eq $signature} return
    dict set forms $key signature $signature
    _viewerDiagnosticsDeliver $window $form changed {} $status
}
proc ::GX::_viewerDiagnosticsPoll {window form operation token} {
    variable ::GX::ViewerDiagnostics::forms
    set key [list $window $form]
    if {![dict exists $forms $key]} {catch {stderrDiagnostics cancel $token};after 0 [list ::GX::_viewerDiagnosticsReap $token];return}
    if {![viewerGuiDesignGuard $window]} {_viewerDiagnosticsDispose $window;return}
    catch {dict unset forms $key poll}
    set receipt [stderrDiagnostics request $token]
    if {[dict get $receipt state] eq {pending}} {dict set forms $key poll [after 20 [list ::GX::_viewerDiagnosticsPoll $window $form $operation $token]];return}
    catch {dict unset forms $key request}
    set client [datasetPublicationV2DictDefault [dict get $forms $key] client_id {}]
    catch {dict unset forms $key client_id}
    if {[dict get $receipt state] eq {error}} {_viewerDiagnosticsDeliver $window $form error $client $receipt;return}
    if {[dict get $receipt state] eq {cancelled}} {_viewerDiagnosticsDeliver $window $form $operation $client {status cancelled};return}
    set result [dict get $receipt result]
    if {$operation eq {read}} {
        set records [datasetPublicationV2DictDefault [dict get $forms $key] records {}]
        foreach record [dict get $result records] {dict set records [dict get $record record_id] [dict get $record payload]}
        set size 0;set kept {}
        foreach id [lreverse [dict keys $records]] {
            set payload [dict get $records $id]
            if {[dict size $kept]>=1024 || $size+[string length $payload]>2097152} break
            dict set kept $id $payload;incr size [string length $payload]
        }
        set ordered {};foreach id [lreverse [dict keys $kept]] {dict set ordered $id [dict get $kept $id]}
        dict set forms $key records $ordered
    }
    if {$operation eq {copy}} {
        set bytes {};foreach record [dict get $result records] {append bytes [dict get $record payload]}
        clipboard clear -displayof $window;clipboard append -displayof $window [encoding convertfrom utf-8 $bytes]
        set result [dict create status copied records [llength [dict get $result records]]]
    }
    _viewerDiagnosticsDeliver $window $form $operation $client $result
}
proc ::GX::viewerGuiDesignDiagnosticsCommand {window form value} {
    variable ::GX::ViewerDiagnostics::forms
    set props [_viewerDiagnosticsForm $window $form]
    set key [list $window $form];set operation [dict get $value command];set args [dict get $value request]
    if {![dict exists $forms $key]} {dict set forms $key [dict create queue {}]}
    switch -- $operation {
        info - status {_viewerDiagnosticsDeliver $window $form $operation [datasetPublicationV2DictDefault $args request_id {}] [stderrDiagnostics $operation]}
        subscribe {
            if {![dict exists $forms $key subscription]} {dict set forms $key subscription [stderrDiagnostics subscribe [list ::GX::_viewerDiagnosticsChanged $window $form]]}
            _viewerDiagnosticsChanged $window $form [stderrDiagnostics status]
        }
        unsubscribe {
            if {[dict exists $forms $key subscription]} {stderrDiagnostics unsubscribe [dict get $forms $key subscription];dict unset forms $key subscription}
        }
        cancel {
            if {[dict exists $forms $key request]} {stderrDiagnostics cancel [dict get $forms $key request]}
        }
        read - meta - export - copy {
            if {[dict exists $forms $key request]} {
                _viewerDiagnosticsDeliver $window $form error [datasetPublicationV2DictDefault $args request_id {}] {state error error_code REQUEST_PENDING message {An archive request is already pending}}
                return [dict create status busy message {An archive request is already pending}]
            }
            if {$operation eq {meta}} {set token [stderrDiagnostics meta]
            } elseif {$operation eq {export}} {
                set destination [tk_getSaveFile -parent $window -title {Export selected STDERR diagnostic records} -defaultextension .jsonl -filetypes {{{Diagnostic records} {.jsonl}} {{All files} *}}]
                if {$destination eq {}} {_viewerDiagnosticsDeliver $window $form export [datasetPublicationV2DictDefault $args request_id {}] {status cancelled};return}
                set selection [dict remove $args request_id follow]
                set token [stderrDiagnostics export $selection $destination]
            } elseif {$operation eq {copy}} {
                # Selection-specific native archive reads preserve exact stable
                # identity. No filesystem path is supplied by the Viewer.
                if {![dict exists $args record_ids]} {error {Copy requires selected retained record identities}}
                set records [datasetPublicationV2DictDefault [dict get $forms $key] records {}]
                set bytes {}
                foreach id [dict get $args record_ids] {
                    if {![dict exists $records $id]} {error {Selected record is outside the bounded displayed pages; refresh its page before copying}}
                    append bytes [dict get $records $id]
                    if {[string length $bytes]>2097152} {error {Clipboard selection exceeds 2 MiB}}
                }
                clipboard clear -displayof $window;clipboard append -displayof $window [encoding convertfrom utf-8 $bytes]
                _viewerDiagnosticsDeliver $window $form copy [datasetPublicationV2DictDefault $args request_id {}] [dict create status copied records [llength [dict get $args record_ids]]]
                return
            } else {set token [stderrDiagnostics read [datasetPublicationV2DictDefault $args cursor {}] [datasetPublicationV2DictDefault $args limit 100] [datasetPublicationV2DictDefault $args max_bytes 524288]]}
            dict set forms $key request $token
            dict set forms $key client_id [datasetPublicationV2DictDefault $args request_id {}]
            dict set forms $key poll [after 0 [list ::GX::_viewerDiagnosticsPoll $window $form $operation $token]]
        }
        default {error {Unsupported bounded diagnostic consultation command}}
    }
}
proc ::GX::_viewerDiagnosticsDispose {window} {
    variable ::GX::ViewerDiagnostics::forms
    dict for {key row} $forms {
        if {[lindex $key 0] ne $window} continue
        foreach timer {poll delivery} {if {[dict exists $row $timer]} {after cancel [dict get $row $timer]}}
        if {[dict exists $row subscription]} {stderrDiagnostics unsubscribe [dict get $row subscription]}
        if {[dict exists $row request]} {set token [dict get $row request];stderrDiagnostics cancel $token;after 0 [list ::GX::_viewerDiagnosticsReap $token]}
        dict unset forms $key
    }
}
proc ::GX::_viewerDiagnosticsReap {token} {
    if {[catch {stderrDiagnostics request $token} receipt]} return
    if {[dict get $receipt state] eq {pending}} {after 20 [list ::GX::_viewerDiagnosticsReap $token]}
}
proc ::GX::viewerGuiDesignTextRuns {window component value} {
    if {![viewerGuiDesignGuard $window] || [dict get [viewerGuiDesignComponent $window $component] type] ne {log}} {error {Styled output requires a declared read-only log}}
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component]
    set palette [sourceSurfacePalette]
    $widget configure -state normal -background [dict get $palette background] -foreground [dict get $palette foreground] -selectbackground [dict get $palette selection]
    foreach {style key} {normal foreground muted comment info bridge warning number error breakpoint heading keyword match keyword} {$widget tag configure $style -foreground [dict get $palette $key]}
    if {[datasetPublicationV2DictDefault $value replace 0]} {$widget delete 1.0 end}
    foreach run [dict get $value runs] {$widget insert end [dict get $run text] [datasetPublicationV2DictDefault $run style normal]}
    # Viewer text is bounded independently of the rotated archive.
    if {[$widget count -chars 1.0 end]>1048576} {$widget delete 1.0 {end - 1048576 chars}}
    $widget configure -state disabled
    if {[datasetPublicationV2DictDefault $value autoscroll 1]} {$widget see end}
}
