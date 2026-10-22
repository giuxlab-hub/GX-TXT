# SPDX-License-Identifier: GPL-3.0-or-later
# Compatibility facade retained when the existing HTML Viewer is rebuilt with
# the official C++ Workspace. The shared document owner remains authoritative.
namespace eval ::GX::HTMLViewer {}
proc ::GX::HTMLViewer::apiInfo {} {return [dict create api_id HTML_VIEWER_API_v1 api_version 1 native_renderer C scripts inactive external_resources inactive text_zoom {50 300 25} text_zoom_scope widget legacy_render_scope inert_run_model interactive [interactiveInfo]]}
proc ::GX::HTMLViewer::render {source} {return [::GX::documentRenderModel html $source]}
proc ::GX::HTMLViewer::open {{context {}}} {
    if {![::GX::viewerProviderEnabled viewer.html html]} {error {HTML Viewer presentation is disabled; its public rendering API remains available}}
    if {[dict exists $context dataset_id] && [::GX::datasetDocumentKind [dict get $context dataset_id]] ne {html}} {error {The Dataset is not an HTML document}}
    return [::GX::viewerOpen viewer.html html $context]
}

# Additive host-only interactive presentation; never Script/author SDK admission.
namespace eval ::GX::HTMLViewer {
    variable instances; if {![info exists instances]} {set instances {}}
    variable serial; if {![info exists serial]} {set serial 0}
    variable commandSerial; if {![info exists commandSerial]} {set commandSerial 0}
    variable terminalOrder; if {![info exists terminalOrder]} {set terminalOrder {}}
}
proc ::GX::HTMLViewer::_error {code message} {return -code error -errorcode [list GX HTML $code] $message}
proc ::GX::HTMLViewer::_keys {value required optional} {
    if {[catch {dict size $value}]} {_error INVALID_ARGUMENT {Expected an option dictionary.}}
    foreach key [dict keys $value] {if {$key ni [concat $required $optional]} {_error INVALID_ARGUMENT {Unknown HTML option.}}}
    foreach key $required {if {![dict exists $value $key]} {_error INVALID_ARGUMENT {A required HTML option is missing.}}}
}
proc ::GX::HTMLViewer::interactiveInfo {} {
    set result [dict create api_id HTML_VIEWER_API_v1 interactive_api_version 1 available 0 backend qt6_webengine engine_version {} abi gxtxt.html_runtime.v1 platform x11 capabilities {} verified_capabilities {} reason RUNTIME_UNAVAILABLE]
    if {![info exists ::GX::scriptDir]} {return $result}
    set root [file join $::GX::scriptDir core nativegui document]
    set binary [file join $root gxtxt_html_runtime];set metadata $binary.info
    if {![file isfile $binary] || ![file executable $binary] || [file type $binary] ne {file} || ![file isfile $metadata] || [file type $metadata] ne {file} || [file size $metadata]>4096} {return $result}
    if {[catch {
        set fd [::open $metadata r];try {set build [read $fd 4097]} finally {close $fd}
        if {[dict get $build schema] ne {gxtxt.html_runtime.build.v1} || [dict get $build abi] ne {gxtxt.html_runtime.v1} || ![regexp {^6\.[0-9]+\.[0-9]+$} [dict get $build qt_version]] || [::GX::sha256File $binary] ne [dict get $build binary_sha256]} {error {Runtime receipt mismatch.}}
    }]} {dict set result reason RUNTIME_IDENTITY_MISMATCH;return $result}
    dict set result engine_version [dict get $build qt_version]
    foreach command {::GX::scriptJobAsync ::GX::scriptJobRequestSend ::GX::scriptJobRequestDrain ::GX::scriptJobRequestCancel} {
        if {![llength [info commands $command]]} {dict set result reason MANAGED_DUPLEX_UNAVAILABLE;return $result}
    }
    if {![llength [info commands winfo]] || ![llength [info commands tk]]} {dict set result reason TK_UNAVAILABLE;return $result}
    if {[tk windowingsystem] ne {x11}} {dict set result reason PLATFORM_UNSUPPORTED;return $result}
    foreach key {QTWEBENGINE_DISABLE_SANDBOX QTWEBENGINE_REMOTE_DEBUGGING QTWEBENGINE_CHROMIUM_FLAGS} {
        if {[info exists ::env($key)] && ($key ne {QTWEBENGINE_CHROMIUM_FLAGS} || $::env($key) ne {})} {dict set result reason SANDBOX_UNAVAILABLE;return $result}
    }
    dict set result available 1;dict set result reason {}
    dict set result capabilities {css javascript dom svg canvas local_assets navigation selection copy zoom}
    dict set result admission_scope prebuilt_identity_and_host_capability
    dict set result rendering_verified 0;dict set result media_status unverified_client_identity
    return $result
}
proc ::GX::HTMLViewer::_get {handle} {
    variable instances
    if {![dict exists $instances $handle]} {_error UNKNOWN_HANDLE {Unknown HTML presentation.}}
    return [dict get $instances $handle]
}
# A terminal receipt is retained only after the managed owner has completed.
# Stale/closing state alone never releases authority over the native window.
proc ::GX::HTMLViewer::_terminal {instance} {
    return [expr {[dict get $instance managed_request] eq {} && [dict get $instance state] in {closed stale unavailable}}]
}
proc ::GX::HTMLViewer::_parentAvailable {windowId} {
    variable instances
    dict for {id record} $instances {
        if {[dict get $record window_id] eq $windowId && ![_terminal $record]} {_error HOST_IN_USE {This native Frame still owns an HTML presentation.}}
    }
}
proc ::GX::HTMLViewer::_unbind {handle} {
    set instance [_get $handle];set parent [dict get $instance parent];set tag [dict get $instance bindtag]
    if {$tag eq {} || ![llength [info commands winfo]] || ![llength [info commands bind]]} return
    if {[winfo exists $parent] && [winfo id $parent] eq [dict get $instance window_id]} {
        set tags [bindtags $parent];set at [lsearch -exact $tags $tag]
        if {$at>=0} {bindtags $parent [lreplace $tags $at $at]}
    }
    foreach sequence [bind $tag] {bind $tag $sequence {}}
}
proc ::GX::HTMLViewer::_retire {handle} {
    variable instances;variable terminalOrder
    set instance [_get $handle]
    if {![_terminal $instance]} {_error RUNTIME_ACTIVE {The managed HTML process has not completed.}}
    _unbind $handle
    _releaseAllocations $handle
    set pendingLoad [dict get $instance pending_load]
    if {$pendingLoad ne {} && [dict get $pendingLoad allocation] ne {}} {catch {::GX::documentInteractiveAllocationRelease [dict get $pendingLoad allocation]}}
    # Keep the small public terminal receipt, not private paths/Session stamps,
    # pending source metadata, controls or allocation dictionaries.
    foreach key {binding allocations pending pending_load desired_size last_resize bindtag timer watcher} {dict set instances $handle $key {}}
    if {[lsearch -exact $terminalOrder $handle]<0} {lappend terminalOrder $handle}
    while {[llength $terminalOrder]>64} {
        set oldest [lindex $terminalOrder 0];set terminalOrder [lrange $terminalOrder 1 end]
        if {[dict exists $instances $oldest] && [_terminal [dict get $instances $oldest]]} {dict unset instances $oldest}
    }
}
proc ::GX::HTMLViewer::_receipt {handle} {
    set instance [_get $handle];set result [dict create schema gxtxt.html_presentation.v1 handle $handle]
    foreach key {generation state purpose source zoom_percent can_back can_forward title status last_error request_id completed_request_id} {dict set result $key [dict get $instance $key]}
    return $result
}
proc ::GX::HTMLViewer::_notify {handle} {
    variable instances
    if {![dict exists $instances $handle]} return
    set instance [dict get $instances $handle];set parent [dict get $instance parent]
    if {![llength [info commands winfo]]} return
    if {[winfo exists $parent] && [winfo id $parent] eq [dict get $instance window_id]} {
        event generate $parent <<GXHTMLChanged>> -when tail -data [dict create handle $handle generation [dict get $instance generation] state [dict get $instance state] receipt [_receipt $handle]]
    }
}
proc ::GX::HTMLViewer::_bindingCheck {purpose source bound} {
    if {$purpose eq {dataset}} {
        if {[::GX::interactiveDocumentSessionToken] ne [dict get $bound snapshot session]} {_error SESSION_CHANGED {Session changed; reopen this HTML Dataset.}}
        if {[::GX::documentInteractiveDatasetSnapshot [dict get $source dataset_id]] ne [dict get $bound snapshot]} {_error SOURCE_CHANGED {HTML Dataset identity changed; reopen it.}}
    } else {
        set entry [::GX::documentationBrowserResolve [dict get $source document_id]]
        if {[dict get $entry source_sha256] ne [dict get $source source_sha256] || [dict get $entry path] ne [dict get $bound path]} {_error SOURCE_CHANGED {Documentation changed; reopen it.}}
    }
}
proc ::GX::HTMLViewer::_guard {handle {sourceCheck 0}} {
    set instance [_get $handle];set parent [dict get $instance parent]
    if {![winfo exists $parent] || [winfo id $parent] ne [dict get $instance window_id]} {_error HOST_GONE {The HTML parent closed or was replaced.}}
    if {[dict get $instance state] in {closing closed stale} || [_terminal $instance]} {_error HOST_GONE {Reopen the HTML presentation.}}
    if {$sourceCheck && [dict get $instance source] ne {}} {
        if {[catch {_bindingCheck [dict get $instance purpose] [dict get $instance source] [dict get $instance binding]} message options]} {
            set code [lindex [::GX::datasetPublicationV2DictDefault $options -errorcode {}] 2]
            if {$code ni {SESSION_CHANGED SOURCE_CHANGED}} {set code SOURCE_CHANGED}
            _stale $handle $code
            _error $code {HTML source changed; reopen the document.}
        }
    }
    return $instance
}
proc ::GX::HTMLViewer::_jsonString {value} {
    set result {"}
    foreach character [split $value {}] {
        scan $character %c code
        if {$code==34 || $code==92} {append result [format %c 92] $character
        } elseif {$code<32} {append result [format {\u%04x} $code]
        } else {append result $character}
    }
    append result {"};return $result
}
proc ::GX::HTMLViewer::_encode {message} {
    set fields {}
    dict for {key value} $message {
        if {$key in {generation width height percent}} {
            if {![string is integer -strict $value]} {_error INVALID_ARGUMENT {Expected an integer HTML control.}}
            set encoded $value
        } elseif {$key eq {value}} {set encoded [expr {$value?{true}:{false}}]
        } else {set encoded [_jsonString $value]}
        lappend fields "[_jsonString $key]:$encoded"
    }
    set result \{[join $fields ,]\}
    if {[string bytelength $result]>16384} {_error INVALID_ARGUMENT {HTML control frame exceeds16KiB.}}
    return $result
}
proc ::GX::HTMLViewer::_send {handle message} {
    variable instances;variable commandSerial
    set instance [_get $handle]
    if {[dict get $instance managed_request] eq {}} {_error RUNTIME_UNAVAILABLE {HTML runtime is not running.}}
    if {[dict size [dict get $instance pending]]>=16} {_error NAVIGATION_BUSY {Wait for pending HTML controls.}}
    set request html-[incr commandSerial]
    dict set message request_id $request
    ::GX::scriptJobRequestSend [dict get $instance managed_request] [_encode $message]
    dict set instances $handle pending $request [dict get $message op]
    dict set instances $handle request_id $request
    return $request
}
proc ::GX::HTMLViewer::attach {parent {options {}}} {
    variable instances;variable serial
    _keys $options {purpose} {zoom_percent}
    set purpose [dict get $options purpose]
    if {$purpose ni {dataset documentation}} {_error INVALID_ARGUMENT {HTML purpose must be dataset or documentation.}}
    set zoom [::GX::datasetPublicationV2DictDefault $options zoom_percent 100]
    if {![string is integer -strict $zoom] || $zoom<50 || $zoom>300 || $zoom%25} {_error INVALID_ARGUMENT {HTML zoom must be50..300 in25 percent steps.}}
    set info [interactiveInfo]
    if {![dict get $info available]} {_error [dict get $info reason] {The precompiled shared HTML runtime is unavailable.}}
    if {![winfo exists $parent] || [winfo class $parent] ni {Frame TFrame}} {_error INVALID_ARGUMENT {HTML requires an existing owned Frame.}}
    set windowId [winfo id $parent]
    _parentAvailable $windowId
    set handle html-host-[incr serial]-[clock clicks]
    set tag GXHTML:$handle
    dict set instances $handle [dict create parent $parent window_id $windowId bindtag $tag purpose $purpose generation 0 state starting source {} binding {} allocations {} zoom_percent $zoom can_back 0 can_forward 0 title {HTML document} status {Starting HTML document} last_error {} request_id {} completed_request_id {} managed_request {} pending {} pending_load {} desired_size {} last_resize {} timer {} watcher {}]
    bindtags $parent [linsert [bindtags $parent] 1 $tag]
    bind $tag <Destroy> [list ::GX::HTMLViewer::_destroyed $handle %W]
    bind $tag <Configure> [list ::GX::HTMLViewer::_resize $handle %W %w %h]
    bind $tag <Map> [list ::GX::HTMLViewer::_visibility $handle %W 1]
    bind $tag <Unmap> [list ::GX::HTMLViewer::_visibility $handle %W 0]
    try {
        set binary [file join $::GX::scriptDir core nativegui document gxtxt_html_runtime]
        set command [list $binary --parent-window [dict get $instances $handle window_id] --tcl]
        set request [::GX::scriptJobAsync $command {} [list ::GX::HTMLViewer::_ended $handle] [dict create duplex 1 max_bytes 16384 process_group 1 ui_lifetime 1 label {Shared HTML runtime}]]
        dict set instances $handle managed_request $request
        _send $handle [dict create op zoom percent $zoom]
        _resize $handle $parent [winfo width $parent] [winfo height $parent]
        dict set instances $handle timer [after 20 [list ::GX::HTMLViewer::_poll $handle]]
        dict set instances $handle watcher [after 1000 [list ::GX::HTMLViewer::_watch $handle]]
    } on error {message context} {catch {detach $handle};return -options $context $message}
    return [_receipt $handle]
}
proc ::GX::HTMLViewer::load {handle source} {
    variable instances
    set instance [_guard $handle]
    if {[dict get $instance pending_load] ne {}} {_error NAVIGATION_BUSY {Wait for HTML source admission.}}
    _keys $source {kind} {dataset_id document_id}
    set kind [dict get $source kind]
    if {$kind ne [dict get $instance purpose] || ($kind eq {dataset} && ![dict exists $source dataset_id]) || ($kind eq {documentation} && ![dict exists $source document_id])} {_error SOURCE_KIND {HTML source does not match the owning presentation.}}
    try {
        if {$kind eq {dataset}} {
            _keys $source {kind dataset_id} {}
            set binding [::GX::documentInteractiveDatasetSource [dict get $source dataset_id]]
            set public [dict get $binding source];set root [dict get $binding asset_root];set relative [dict get $binding relative]
            set allocation [dict get $binding allocation]
        } else {
            _keys $source {kind document_id} {}
            set binding [::GX::documentationBrowserResolve [dict get $source document_id]]
            if {[dict get $binding format] ne {html}} {_error SOURCE_KIND {Interactive HTML requires an indexed HTML document.}}
            set public [dict create kind documentation document_id [dict get $source document_id] module_id [dict get $binding owner] source_sha256 [dict get $binding source_sha256]]
            set root [dict get $binding asset_root]
            set relative [string range [dict get $binding path] [expr {[string length $root]+1}] end]
            set allocation {}
        }
    } on error {message options} {
        set code [::GX::datasetPublicationV2DictDefault $options -errorcode {}]
        if {[lrange $code 0 1] eq {GX HTML}} {return -options $options $message}
        _error SOURCE_UNAVAILABLE {The requested HTML source is unavailable.}
    }
    set generation [expr {[dict get $instance generation]+1}]
    set sourceId [expr {$kind eq {dataset}?[dict get $source dataset_id]:[dict get $source document_id]}]
    try {
        _send $handle [dict create op visible value 0]
        set request [_send $handle [dict create op load generation $generation root $root relative $relative sha256 [dict get $public source_sha256] source_id $sourceId media youtube]]
    } on error {message options} {if {$allocation ne {}} {catch {::GX::documentInteractiveAllocationRelease $allocation}};return -options $options $message}
    # Commit public source identity only on the native source-admission receipt.
    # A rejected native admission cannot relabel pixels from the prior source.
    dict set instances $handle pending_load [dict create generation $generation request_id $request source $public binding $binding allocation $allocation]
    dict set instances $handle state loading;dict set instances $handle status {Loading HTML document};dict set instances $handle last_error {}
    dict set instances $handle load_request $request
    _notify $handle
    return [_receipt $handle]
}
proc ::GX::HTMLViewer::_navigationMessage {request} {
    _keys $request {action} {target percent text}
    set action [dict get $request action]
    set message [dict create op $action]
    if {$action in {back forward home reload stop}} {_keys $request {action} {}
    } elseif {$action eq {relative}} {
        _keys $request {action target} {};set target [dict get $request target]
        if {$target eq {} || [string bytelength $target]>2048 || [regexp {[:?\\\x00\r\n]} $target] || [string match {/*} $target] || [string match {*%*} $target]} {_error INVALID_ARGUMENT {Expected bounded package-relative navigation.}}
        set path [lindex [split $target #] 0]
        foreach part [split $path /] {if {$path ne {} && $part in {{} . ..}} {_error INVALID_ARGUMENT {Unsafe package-relative navigation.}}}
        dict set message target $target
    } elseif {$action eq {zoom}} {
        _keys $request {action percent} {};set percent [dict get $request percent]
        if {![string is integer -strict $percent] || $percent<50 || $percent>300 || $percent%25} {_error INVALID_ARGUMENT {HTML zoom must be50..300 in25 percent steps.}}
        dict set message percent $percent
    } elseif {$action eq {find}} {
        _keys $request {action text} {};set text [dict get $request text]
        if {[string bytelength $text]>1024 || [string first \x00 $text]>=0} {_error INVALID_ARGUMENT {Find text is oversized or contains NUL.}}
        dict set message text $text
    } else {_error INVALID_ARGUMENT {Unsupported HTML navigation operation.}}
    return $message
}
proc ::GX::HTMLViewer::navigate {handle request} {
    _guard $handle 1
    _send $handle [_navigationMessage $request]
    return [_receipt $handle]
}
proc ::GX::HTMLViewer::inspect {handle} {if {![_terminal [_get $handle]]} {_guard $handle 1};return [_receipt $handle]}
proc ::GX::HTMLViewer::_releaseAllocations {handle {beforeGeneration {}}} {
    variable instances
    if {![dict exists $instances $handle]} return
    dict for {generation allocation} [dict get $instances $handle allocations] {
        if {$beforeGeneration eq {} || $generation<$beforeGeneration} {
            catch {::GX::documentInteractiveAllocationRelease $allocation}
            dict unset instances $handle allocations $generation
        }
    }
}
proc ::GX::HTMLViewer::_accept {handle line} {
    variable instances
    if {![string match {GXHTML1 *} $line]} return
    set frame [string range $line 8 end]
    if {[string bytelength $frame]>16384 || [catch {dict size $frame}] || ![dict exists $frame schema] || [dict get $frame schema] ne {gxtxt.html_runtime.v1}} {_error RUNTIME_PROTOCOL {Invalid bounded HTML runtime receipt.}}
    set instance [_get $handle]
    foreach key {event state generation source_id source_sha256 request_id zoom_percent can_back can_forward} {if {![dict exists $frame $key]} {_error RUNTIME_PROTOCOL {Incomplete HTML runtime receipt.}}}
    set generation [dict get $frame generation]
    if {![string is integer -strict $generation]} {_error RUNTIME_PROTOCOL {Invalid HTML source generation.}}
    set event [dict get $frame event];set request [dict get $frame request_id]
    set pendingLoad [dict get $instance pending_load]
    if {$pendingLoad ne {}} {
        if {$request eq [dict get $pendingLoad request_id] && $event eq {accepted} && $generation==[dict get $pendingLoad generation]} {
            set public [dict get $pendingLoad source]
            set id [expr {[dict get $public kind] eq {dataset}?[dict get $public dataset_id]:[dict get $public document_id]}]
            if {[dict get $frame source_id] ne $id || [dict get $frame source_sha256] ne [dict get $public source_sha256]} {_error RUNTIME_PROTOCOL {Native HTML admission identity mismatch.}}
            if {[catch {_bindingCheck [dict get $instance purpose] $public [dict get $pendingLoad binding]} message options]} {
                set code [lindex [::GX::datasetPublicationV2DictDefault $options -errorcode {}] 2]
                if {$code ni {SESSION_CHANGED SOURCE_CHANGED}} {set code SOURCE_CHANGED}
                _stale $handle $code;return
            }
            dict set instances $handle generation $generation
            dict set instances $handle source $public;dict set instances $handle binding [dict get $pendingLoad binding]
            dict set instances $handle pending [dict create $request load]
            set allocation [dict get $pendingLoad allocation]
            if {$allocation ne {}} {dict set instances $handle allocations $generation $allocation}
            if {[dict exists $pendingLoad binding title]} {dict set instances $handle title [string range [dict get $pendingLoad binding title] 0 255]}
            dict set instances $handle pending_load {}
            _send $handle [dict create op visible value [winfo ismapped [dict get $instances $handle parent]]]
            set instance [_get $handle]
        } elseif {$request eq [dict get $pendingLoad request_id] && $event eq {error}} {
            if {[dict get $pendingLoad allocation] ne {}} {catch {::GX::documentInteractiveAllocationRelease [dict get $pendingLoad allocation]}}
            dict set instances $handle pending_load {}
            if {[dict exists $instances $handle pending $request]} {dict unset instances $handle pending $request}
            dict set instances $handle completed_request_id $request
            dict set instances $handle state unavailable;dict set instances $handle status {The requested HTML source was not admitted}
            dict set instances $handle last_error [dict create code [string range [::GX::datasetPublicationV2DictDefault $frame code SOURCE_UNAVAILABLE] 0 63] message {The requested HTML source was not admitted.}]
            _notify $handle;return
        } else {
            # Older source/layout messages may drain before source admission.
            if {[dict exists $instances $handle pending $request]} {dict unset instances $handle pending $request}
            return
        }
    }
    if {$generation<[dict get $instance generation]} return
    if {$generation!=[dict get $instance generation]} {_error RUNTIME_PROTOCOL {Unexpected HTML source generation.}}
    if {[dict get $instance source] ne {}} {
        set source [dict get $instance source]
        set id [expr {[dict get $source kind] eq {dataset}?[dict get $source dataset_id]:[dict get $source document_id]}]
        if {[dict get $frame source_id] ne $id || [dict get $frame source_sha256] ne [dict get $source source_sha256]} {_error RUNTIME_PROTOCOL {HTML source receipt does not match its owner.}}
    }
    set state [dict get $frame state]
    if {$state ni {empty loading ready unavailable closed}} {_error RUNTIME_PROTOCOL {Unknown HTML runtime state.}}
    if {$event eq {external_link_requested}} {
        _guard $handle 1
        if {![dict exists $frame url] || [string bytelength [dict get $frame url]]>2048 || ![regexp {^https?://} [dict get $frame url]]} {_error RUNTIME_PROTOCOL {Invalid external HTML link request.}}
        ::GX::markupOpenWebLink [dict get $frame url]
        return
    }
    if {$event eq {policy_notice}} return
    foreach key {zoom_percent can_back can_forward} {
        set value [dict get $frame $key]
        if {![string is integer -strict $value] || ($key eq {zoom_percent} && ($value<50 || $value>300 || $value%25)) || ($key ne {zoom_percent} && $value ni {0 1})} {_error RUNTIME_PROTOCOL {Invalid HTML presentation scalar.}}
    }
    if {[dict exists $frame navigation_pending] && [dict get $frame navigation_pending] ni {0 1}} {_error RUNTIME_PROTOCOL {Invalid navigation state.}}
    dict set instances $handle state $state
    foreach key {zoom_percent can_back can_forward} {dict set instances $handle $key [dict get $frame $key]}
    if {$state eq {ready}} {dict set instances $handle status {HTML document ready};dict set instances $handle last_error {}}
    if {$event in {error asset_error}} {
        set code [::GX::datasetPublicationV2DictDefault $frame code RUNTIME_ERROR]
        dict set instances $handle last_error [dict create code [string range $code 0 63] message {HTML content or runtime is unavailable.}]
        dict set instances $handle status {HTML content or runtime is unavailable}
    }
    if {$request ne {} && [dict exists $instances $handle pending $request]} {
        set pending [dict get $instances $handle pending $request]
        set terminal [expr {$event in {ready error closed}}]
        if {$event eq {accepted} && $pending ni {load back forward home reload relative}} {set terminal 1}
        if {$event eq {accepted} && [dict exists $frame navigation_pending] && ![dict get $frame navigation_pending] && $pending ne {load}} {set terminal 1}
        if {$terminal} {dict unset instances $handle pending $request;dict set instances $handle completed_request_id $request}
        if {$event eq {accepted} && $pending eq {load}} {_releaseAllocations $handle $generation}
    }
    _notify $handle
}
proc ::GX::HTMLViewer::_poll {handle} {
    variable instances
    if {![dict exists $instances $handle] || [dict get $instances $handle managed_request] eq {}} return
    dict set instances $handle timer {}
    if {[catch {
        set result [::GX::scriptJobRequestDrain [dict get $instances $handle managed_request] 16]
        if {![dict exists $instances $handle]} return
        foreach line [dict get $result messages] {_accept $handle $line}
    }]} {_stale $handle RUNTIME_PROTOCOL;return}
    if {[dict exists $instances $handle] && [dict get $instances $handle managed_request] ne {}} {
        if {![dict get $result active]} {_ended $handle {};return}
        if {[dict get $result cancelled] ne {}} {_stale $handle RUNTIME_EXITED;return}
    }
    if {[dict exists $instances $handle] && [dict get $instances $handle managed_request] ne {}} {
        set current [dict get $instances $handle]
        if {[dict get $current desired_size] ne {}} {lassign [dict get $current desired_size] width height;_resize $handle [dict get $current parent] $width $height}
        dict set instances $handle timer [after 20 [list ::GX::HTMLViewer::_poll $handle]]
    }
}
proc ::GX::HTMLViewer::_watch {handle} {
    variable instances
    if {![dict exists $instances $handle] || [dict get $instances $handle state] in {closing closed stale}} return
    dict set instances $handle watcher {}
    if {[catch {_guard $handle 1} reason options]} {
        set code [lindex [::GX::datasetPublicationV2DictDefault $options -errorcode {GX HTML SOURCE_CHANGED}] 2]
        _stale $handle $code;return
    }
    dict set instances $handle watcher [after 1000 [list ::GX::HTMLViewer::_watch $handle]]
}
proc ::GX::HTMLViewer::_stale {handle code} {
    variable instances
    if {![dict exists $instances $handle]} return
    catch {detach $handle}
    dict set instances $handle state stale;dict set instances $handle status {HTML source or host changed; reopen it}
    dict set instances $handle last_error [dict create code $code message {HTML source or host changed; reopen it.}]
    catch {_notify $handle}
}
proc ::GX::HTMLViewer::_ended {handle response} {
    variable instances
    if {![dict exists $instances $handle]} return
    foreach key {timer watcher} {if {[dict get $instances $handle $key] ne {}} {after cancel [dict get $instances $handle $key];dict set instances $handle $key {}}}
    dict set instances $handle managed_request {}
    if {[dict get $instances $handle state] ni {closing closed stale}} {
        dict set instances $handle state unavailable;dict set instances $handle status {HTML runtime closed; reopen the document}
        dict set instances $handle last_error [dict create code RUNTIME_EXITED message {HTML runtime closed; reopen the document.}]
    } elseif {[dict get $instances $handle state] eq {closing}} {dict set instances $handle state closed}
    _retire $handle
    catch {_notify $handle}
}
proc ::GX::HTMLViewer::detach {handle} {
    variable instances
    set instance [_get $handle]
    if {[dict get $instance state] in {closing stale} || ([dict get $instance state] eq {closed} && [_terminal $instance])} {return [_receipt $handle]}
    dict set instances $handle state closing
    foreach key {timer watcher} {if {[dict get $instance $key] ne {}} {after cancel [dict get $instance $key];dict set instances $handle $key {}}}
    _unbind $handle
    set request [dict get $instance managed_request]
    if {$request ne {}} {catch {::GX::scriptJobRequestCancel $request closed}
    } else {dict set instances $handle state closed;_retire $handle}
    return [_receipt $handle]
}
proc ::GX::HTMLViewer::_destroyed {handle actual} {
    if {![catch {_get $handle} instance] && $actual eq [dict get $instance parent]} {catch {detach $handle}}
}
proc ::GX::HTMLViewer::_resize {handle actual width height} {
    variable instances
    if {[catch {_get $handle} instance] || $actual ne [dict get $instance parent] || [dict get $instance state] in {closing closed stale}} return
    if {$width<=0 || $height<=0 || $width>16384 || $height>16384} return
    set size [list $width $height];dict set instances $handle desired_size $size
    if {$size eq [dict get $instance last_resize]} return
    # A saturated control queue keeps the newest geometry for the next drain.
    if {![catch {_send $handle [dict create op resize width $width height $height]}]} {dict set instances $handle last_resize $size}
}
proc ::GX::HTMLViewer::_visibility {handle actual visible} {
    if {[catch {_get $handle} instance] || $actual ne [dict get $instance parent] || [dict get $instance state] in {closing closed stale}} return
    catch {_send $handle [dict create op visible value $visible]}
}
