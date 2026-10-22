# SPDX-License-Identifier: GPL-3.0-or-later
# Optional project-scoped native testing in the existing Development owner.
# No authored code, widget path, command, destination path or module is accepted.
namespace eval ::GX::ViewerDevelopment {variable guiTests;if {![info exists guiTests]} {set guiTests {}}}
proc ::GX::_viewerDevelopmentGuiFolder {project} {
    foreach path [list $project [file join $project derived] [file join $project derived gui-test]] {
        if {[file exists $path] && ([file type $path] eq {link} || ![file isdirectory $path])} {error {GUI test directory must be an ordinary project directory}}
    }
    set folder [file join $project derived gui-test];file mkdir $folder
    return $folder
}
proc ::GX::viewerDevelopmentGuiTestAttach {project} {
    if {$::GX::currentSession eq {}} {error {Open a scientific Session before attaching native GUI testing}}
    set project [file normalize $project]
    set snapshot [_viewerDevelopmentSnapshot $project]
    set design [viewerGuiDesignRead [file join $project design.gxtxt-viewer]]
    # Reuse the existing GUI laboratory private-fixture policy. The author CLI
    # cannot nominate a Session/root or create this trusted test designation.
    set fixtureRoot [file dirname [file normalize $::GX::currentSession]];set fixtureOptions {}
    for {set n 0} {$n<16} {incr n} {
        set candidate [dict create fixture_root $fixtureRoot permitted_commands [dict keys [dict get $design handlers]]]
        if {[viewerGuiTestFixtureValidate {} $candidate]} {set fixtureOptions $candidate;break}
        set parent [file dirname $fixtureRoot];if {$parent eq $fixtureRoot} break
        set fixtureRoot $parent
    }
    if {$fixtureOptions eq {}} {error {Native GUI testing requires a Session under an explicitly marked private GUI laboratory fixture root (.gxtxt-gui-test-fixture); original user Sessions are not test fixtures}}
    set module [dict get $design module_id];set provider [dict get $design provider_id]
    if {![pluginRegistryIsManaged $module] || {RESTRICTED_VIEWER_CLIENT_API_v1} ni [modulePublicApiIds $module]} {error {Install the assigned restricted Viewer normally before attaching its native tests}}
    set root [file dirname [moduleField $module descriptor]]
    if {[_viewerDevelopmentSnapshot [file join $root source]] ne $snapshot} {error {Installed Viewer source differs from this author project}}
    set folder [_viewerDevelopmentGuiFolder $project]
    if {[dict exists $::GX::ViewerDevelopment::guiTests $project]} {viewerDevelopmentGuiTestDetach $project}
    set connection [format gui-%x-%x [pid] [clock microseconds]]
    dict set ::GX::ViewerDevelopment::guiTests $project [dict create connection $connection snapshot $snapshot module $module provider $provider window {} pressed 0 session $::GX::currentSession session_token [interactiveDocumentSessionToken] fixture_options $fixtureOptions]
    resourceLifecycleWriteBytes [file join $folder connection.tcldict] [encoding convertto utf-8 [dict create connection $connection snapshot $snapshot module $module provider $provider session $::GX::currentSession]]
    after 100 [list ::GX::_viewerDevelopmentGuiPoll $project $connection]
    return [dict create status attached project $project module $module snapshot $snapshot actions {open workspace_open workspace_save workspace_review workspace_upgrade status close capture capture_verify capture_preview resize label label_apply label_close click choice list_select table_select table_scroll table_copy table_page text source_text source_replace tab pointer plot_pointer key document_find document_pointer document_zoom pdf_control pdf_pointer pdf_key pdf_resize pdf_close property wire_route properties_commit properties_close}]
}
proc ::GX::viewerDevelopmentGuiTestDetach {project} {
    set project [file normalize $project]
    if {[dict exists $::GX::ViewerDevelopment::guiTests $project]} {
        if {[dict get $::GX::ViewerDevelopment::guiTests $project pressed]} {catch {exec xdotool mouseup [dict get $::GX::ViewerDevelopment::guiTests $project pressed]}}
        set w [dict get $::GX::ViewerDevelopment::guiTests $project window]
        if {$w ne {} && [winfo exists $w]} {destroy $w}
        dict unset ::GX::ViewerDevelopment::guiTests $project
    }
    set path [file join [_viewerDevelopmentGuiFolder $project] connection.tcldict]
    if {[file exists $path] && [file type $path] eq {file}} {file delete $path}
    return detached
}
proc ::GX::_viewerDevelopmentGuiPoll {project connection} {
    if {![dict exists $::GX::ViewerDevelopment::guiTests $project] || [dict get $::GX::ViewerDevelopment::guiTests $project connection] ne $connection} return
    set folder [_viewerDevelopmentGuiFolder $project];set path [file join $folder request.tcldict]
    if {[file exists $path]} {
        set request {};set requestId {}
        if {[catch {
            file lstat $path st
            if {$st(type) ne {file} || $st(nlink)!=1 || $st(size)>16384} {error {GUI test request must be an ordinary bounded file}}
            set f [open $path rb];try {set request [encoding convertfrom utf-8 [read $f 16385]]} finally {close $f}
            file delete $path
            set requestId [dict get $request request_id]
            if {![regexp {^[0-9a-f]{32}$} $requestId]} {error {Invalid GUI request identity}}
            set result [_viewerDevelopmentGuiAction $project $connection $request]
            set response [dict create ok 1 request_id $requestId result $result]
        } message options]} {
            if {[dict get $::GX::ViewerDevelopment::guiTests $project pressed]} {catch {exec xdotool mouseup [dict get $::GX::ViewerDevelopment::guiTests $project pressed]};dict set ::GX::ViewerDevelopment::guiTests $project pressed 0}
            set response [dict create ok 0 request_id $requestId error $message code GUI_TEST_DENIED]
        }
        if {$requestId ne {} && [regexp {^[0-9a-f]{32}$} $requestId]} {
            catch {resourceLifecycleWriteBytes [file join $folder response-$requestId.tcldict] [encoding convertto utf-8 $response]}
        }
    }
    after 100 [list ::GX::_viewerDevelopmentGuiPoll $project $connection]
}
proc ::GX::_viewerDevelopmentGuiClick {widget {guard {}}} {
    if {![winfo exists $widget] || ![winfo ismapped $widget]} {error {Declared control is not visible; select its tab first}}
    set top [winfo toplevel $widget];raise $top;update idletasks
    exec xdotool windowfocus --sync [winfo id $top]
    # The shared inspector scrolls focused controls into view. Settle that
    # ordinary focus behavior before locating the native click, so a press
    # cannot move its own target out from under the matching release.
    focus -force $widget;update
    after 120 [list set ::GX::ViewerDevelopment::guiInputReady 1];vwait ::GX::ViewerDevelopment::guiInputReady;update
    if {$guard ne {}} {{*}$guard}
    set x [expr {[winfo rootx $widget]+[winfo width $widget]/2}];set y [expr {[winfo rooty $widget]+[winfo height $widget]/2}]
    set hit [winfo containing -displayof $widget $x $y]
    if {$hit ne $widget && ![string match "$widget.*" $hit]} {error {Declared control is clipped or occluded; show it before clicking}}
    exec xdotool mousemove $x $y
    update;if {$guard ne {}} {{*}$guard};exec xdotool mousedown 1;update;exec xdotool mouseup 1;update
}
proc ::GX::_viewerDevelopmentGuiChoose {widget value top} {
    _viewerDevelopmentGuiClick $widget
    after 150 [list set ::GX::ViewerDevelopment::guiChoiceReady 1];vwait ::GX::ViewerDevelopment::guiChoiceReady
    set popup [_uiFieldSelectorPanel $widget $top].options
    if {[winfo exists $popup]} {
        set n [lsearch -exact [$popup get 0 end] $value]
        if {$n<0} {error {Requested value is absent from current native choices}}
        $popup see $n;update idletasks;lassign [$popup bbox $n] x y width height
        exec xdotool mousemove [expr {[winfo rootx $popup]+20}] [expr {[winfo rooty $popup]+$y+$height/2}] click 1
    } else {
        set n [lsearch -exact [$widget cget -values] $value]
        if {$n<0} {error {Requested value is absent from current native choices}}
        exec xdotool key Home
        for {set i 0} {$i<$n} {incr i} {exec xdotool key Down}
        exec xdotool key Return
    }
    update
    if {[$widget get] ne $value} {error {Native selector did not accept the requested choice}}
}
proc ::GX::_viewerDevelopmentGuiType {widget value {guard {}}} {
    if {![winfo exists $widget] || ![winfo ismapped $widget]} {error {Declared entry is not visible}}
    focus -force $widget;update
    if {$guard ne {}} {{*}$guard}
    exec xdotool key Home shift+End BackSpace
    exec xdotool type --clearmodifiers -- $value
    exec xdotool key Tab;update
}
proc ::GX::_viewerDevelopmentGuiTableTarget {window component} {
    if {![viewerGuiDesignGuard $window]} {error {Session changed; reopen the declared table}}
    set definition [viewerGuiDesignComponent $window $component]
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component]
    if {[dict get $definition type] eq {table}} {
        return [dict create kind table parent $widget tree [uiFieldComponentTableWidget $widget]]
    }
    if {[dict get $definition type] ne {document} || [dict get $definition properties kind] ne {table}} {error {Table input requires a declared read-only table or table document}}
    set binding [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window bindings] $component {}]
    if {![dict exists $binding dataset_id] || [dict get $binding kind] ne {document} || [dict get $binding content_kind] ne {table}} {error {Bind a canonical Dataset before using the table document}}
    _viewerGuiDocumentBindingCheck $definition $binding
    set parent $widget.table
    set receipt [datasetPreviewTableInspect $parent]
    if {[dict get $receipt status] ne {ready} || [dict get $receipt dataset_id] ne [dict get $binding dataset_id]} {error {Table consultation source changed; rebind explicitly}}
    return [dict create kind document parent $parent tree $parent.tree dataset_id [dict get $receipt dataset_id] source_sha256 [dict get $binding source_sha256] source_stamp [dict get $binding stamp]]
}
proc ::GX::_viewerDevelopmentGuiTableCurrent {window component expected} {
    if {[_viewerDevelopmentGuiTableTarget $window $component] ne $expected} {error {Table source changed while settling input; no input sent}}
}
# Observe the existing copy owner during one real key event. This does not
# invoke copying or change the clipboard, selection or scientific source.
proc ::GX::_viewerDevelopmentGuiTableCopyObserved {tree variable command code result operation} {
    if {[lindex $command 1] eq $tree && [info exists $variable]} {
        set $variable [dict create code $code result $result]
    }
}
proc ::GX::_viewerDevelopmentGuiTableCopy {window component target} {
    variable ::GX::ViewerDevelopment::guiCopySerial
    if {![info exists guiCopySerial]} {set guiCopySerial 0}
    set tree [dict get $target tree]
    set before [uiFieldComponentTableRead $tree 1]
    if {![llength [dict get $before rows]]} {error {Select an actual native table row before copying}}
    set variable ::GX::ViewerDevelopment::guiCopyObserved[incr guiCopySerial]
    set $variable {}
    set observer [list ::GX::_viewerDevelopmentGuiTableCopyObserved $tree $variable]
    try {
        trace add execution ::GX::uiFieldComponentTableCopy leave $observer
        _viewerDevelopmentGuiTableCurrent $window $component $target
        exec xdotool key --clearmodifiers ctrl+c;update
        set observed [set $variable]
    } finally {
        trace remove execution ::GX::uiFieldComponentTableCopy leave $observer
        unset -nocomplain $variable
    }
    _viewerDevelopmentGuiTableCurrent $window $component $target
    if {$observed eq {} || [dict get $observed code]!=0 || ![string is integer -strict [dict get $observed result]] || [dict get $observed result]!=[llength [dict get $before rows]]} {
        error {Native table did not complete copying the current selected rows; retained clipboard is not a copy result}
    }
    if {[uiFieldComponentTableRead $tree 1] ne $before} {error {Table selection or values changed during native copy}}
    set lines {}
    foreach row [dict get $before rows] {
        set cells {};foreach cell $row {lappend cells [string map [list \t { } \r { } \n { }] $cell]}
        lappend lines [join $cells \t]
    }
    set copied [clipboard get -displayof $tree]
    if {$copied ne [join $lines \n]} {error {Clipboard differs from the current selected table values}}
    set probe [dict create selection [dict get $before selection] clipboard_text [string range $copied 0 4095] clipboard_characters [string length $copied] clipboard_utf8_bytes [string bytelength $copied] presentation_bounded 1 copy_service_observed 1 copied_rows [dict get $observed result]]
    if {[dict get $target kind] eq {document}} {dict set probe selected_source_rows [dict get [datasetPreviewTableInspect [dict get $target parent]] selected_source_rows]}
    return $probe
}
proc ::GX::_viewerDevelopmentGuiTablePage {window component command {row {}}} {
    set target [_viewerDevelopmentGuiTableTarget $window $component]
    if {[dict get $target kind] ne {document}} {error {Paging requires a declared table document}}
    set parent [dict get $target parent];set before [datasetPreviewTableInspect $parent]
    if {$command ni {previous next first last goto schema}} {error {Table paging command must be previous, next, first, last, goto or schema}}
    set guard [list ::GX::_viewerDevelopmentGuiTableCurrent $window $component $target]
    if {$command in {first last goto}} {
        if {$command eq {first}} {set row 1}
        if {$command eq {last}} {
            set row [dict get $before row_count]
            if {$row<1} {error {Last source row requires a known nonempty Dataset}}
        }
        if {[string bytelength $row]>32 || ![regexp {^[+-]?[0-9]+$} $row]} {error {Enter a bounded integer source-row literal}}
        _viewerDevelopmentGuiType $parent.nav.row $row $guard
        set button $parent.nav.go
    } else {set button $parent.nav.$command}
    if {![winfo exists $button] || [$button instate disabled]} {error {Requested table navigation is unavailable at this page}}
    _viewerDevelopmentGuiClick $button $guard
    return [dict create command $command before $before after [datasetPreviewTableInspect $parent] status_text [$parent.status cget -text]]
}
proc ::GX::_viewerDevelopmentGuiTeXSource {window component {expected {}}} {
    set definition [viewerGuiDesignComponent $window $component]
    if {[dict get $definition type] ne {document} || [dict get $definition properties kind] ne {tex}} {error {Source input requires a declared TeX source document}}
    set form {}
    foreach c [dict get $::GX::ViewerGui::instances $window design components] {
        if {[datasetPublicationV2DictDefault [dict get $c properties] tex_source {}] eq $component} {set form [dict get $c id];break}
    }
    if {$form eq {}} {error {Source input requires its complete declared article form}}
    set article [_viewerGuiTeXCurrent $window $form]
    set target [dict get [_viewerGuiTeXRecord $window $form] source_widget]
    if {![winfo exists $target] || ![winfo ismapped $target] || [$target cget -state] ne {normal}} {error {Show the editable current article source before native input}}
    set current [dict create target $target identity [_viewerGuiTeXStamp $article]]
    if {$expected ne {} && $current ne $expected} {error {Article changed while settling native source input; no input sent}}
    return $current
}
proc ::GX::_viewerDevelopmentGuiAction {project connection request} {
    set attached [dict get $::GX::ViewerDevelopment::guiTests $project]
    if {[dict get $request connection] ne $connection || [dict get $attached session] ne $::GX::currentSession || [dict get $attached session_token] ne [interactiveDocumentSessionToken] || ![viewerGuiTestFixtureValidate {} [dict get $attached fixture_options]] || [dict get $request snapshot] ne [dict get $attached snapshot] || [_viewerDevelopmentSnapshot $project] ne [dict get $attached snapshot]} {error {GUI attachment source, Session lifetime or private fixture changed; reattach explicitly}}
    set operation [dict get $request operation]
    set shapes [dict create open {} status {} close {} capture {} capture_verify {capture_id} capture_preview {capture_id} click {component} choice {component value} text {component value} tab {component} pointer {component x y phase} plot_pointer {component x y} key {component key} property {component field value} properties_commit {component} properties_close {component}]
    dict set shapes label {component field value};dict set shapes label_apply component;dict set shapes label_close component
    dict set shapes wire_route {component command}
    dict set shapes list_select {component index}
    dict set shapes table_select {component index}
    dict set shapes table_scroll {component axis direction}
    dict set shapes table_copy {component}
    dict set shapes table_page {component command}
    if {$operation eq {table_page} && [dict exists $request command] && [dict get $request command] eq {goto}} {dict set shapes table_page {component command row}}
    if {$operation eq {wire_route} && [dict exists $request command] && [dict get $request command] eq {select}} {dict set shapes wire_route {component command index}}
    dict set shapes resize {width height}
    dict set shapes workspace_open {workspace_id}
    dict set shapes workspace_save {}
    dict set shapes workspace_review {workspace_id}
    dict set shapes workspace_upgrade {review_id}
    dict set shapes document_find {component value direction}
    dict set shapes source_text {component value}
    dict set shapes source_replace {component query replacement scope}
    dict set shapes document_pointer {component x y phase}
    dict set shapes document_zoom {component value}
    dict set shapes pdf_control {component command}
    dict set shapes pdf_pointer {component x y phase}
    dict set shapes pdf_key {component key}
    dict set shapes pdf_resize {component width height}
    dict set shapes pdf_close {component}
    if {$operation eq {plot_pointer} && [dict exists $request phase]} {dict set shapes plot_pointer {component x y phase}}
    if {$operation eq {capture} && [dict exists $request component] && [dict exists $request dialog]} {dict set shapes capture {component dialog}}
    if {![dict exists $shapes $operation] || [lsort [dict keys $request]] ne [lsort [concat {operation request_id connection snapshot} [dict get $shapes $operation]]]} {error {Unknown or unbounded GUI action}}
    foreach key {component value field key phase command query replacement scope} {if {[dict exists $request $key] && ([string bytelength [dict get $request $key]]>4096 || [string first \x00 [dict get $request $key]]>=0)} {error {GUI action text exceeds bounds}}}
    if {$operation eq {document_find} && [regexp {[\x00-\x1f\x7f]} [dict get $request value]]} {error {Native Find accepts a single-line literal query without control characters}}
    if {$operation eq {source_replace} && ([dict get $request scope] ni {current all} || [dict get $request query] eq {} || [regexp {[\x00-\x1f\x7f]} "[dict get $request query][dict get $request replacement]"])} {error {Native Replace requires a nonempty single-line query, literal single-line replacement and scope current|all}}
    if {$operation eq {wire_route}} {
        if {[dict get $request command] ni {select add replace remove up down}} {error {Unknown typed wire bend action}}
        if {[dict get $request command] eq {select} && (![string is integer -strict [dict get $request index]] || [dict get $request index]<0 || [dict get $request index]>=128)} {error {Wire bend index must be0..127}}
    }
    set w [dict get $attached window]
    if {$operation in {workspace_review workspace_upgrade}} {
        if {$w ne {} && [winfo exists $w]} {error {Close the attached Viewer before reviewing or upgrading a saved Workspace}}
        if {$operation eq {workspace_review}} {return [viewerDevelopmentWorkspaceReviewWait $project [dict get $request workspace_id]]}
        return [viewerDevelopmentWorkspaceUpgrade $project [dict get $request review_id]]
    }
    if {$operation in {open workspace_open}} {
        if {$w ne {} && [winfo exists $w]} {error {Close the existing attached Viewer first}}
        if {$operation eq {workspace_open}} {
            set id [dict get $request workspace_id]
            if {![interactiveDocumentIdValid $id] || [string length $id]>128} {error {Use a canonical current-Session Workspace identity}}
            # Resolve only through the Session's canonical Workspace inventory.
            # A GUI-test grant is deliberately exact-snapshot, unlike normal
            # interactive Workspace upgrade compatibility. No path, provider,
            # module, external window or author-supplied factory is accepted.
            set workspace [sessionWorkspaceGet $id]
            set payload [dict get $workspace payload]
            if {[dict get $workspace module_id] ne [dict get $attached module] || [dict get $workspace schema] ne {gxtxt.viewer_interface_state.v1} || ![dict exists $payload design] || [dict get $payload design module_id] ne [dict get $attached module] || [dict get $payload design provider_id] ne [dict get $attached provider] || ![dict exists $payload domain_state restricted_cpp snapshot] || [dict get $payload domain_state restricted_cpp snapshot] ne [dict get $attached snapshot]} {error {Workspace does not belong to this exact installed project snapshot}}
            dict for {other instance} $::GX::ViewerGui::instances {
                if {[dict get $instance workspace_id] eq $id && [winfo exists $other]} {error {This Workspace is already open; close its existing window first}}
            }
            # The existing registered factory retains validation, source/state
            # compatibility, resource ownership and compiled runtime admission.
            set w [sessionWorkspaceOpen $id]
        } else {
            set w [viewerOpen [dict get $attached module] [dict get $attached provider]]
        }
        dict set ::GX::ViewerDevelopment::guiTests $project window $w
    } elseif {$w eq {} || ![winfo exists $w] || ![dict exists $::GX::ViewerDevelopment::windows $w]} {error {Open the assigned installed Viewer first}}
    if {$operation eq {close}} {
        if {[dict get $attached pressed]} {catch {exec xdotool mouseup [dict get $attached pressed]};dict set ::GX::ViewerDevelopment::guiTests $project pressed 0}
        destroy $w;dict set ::GX::ViewerDevelopment::guiTests $project window {};return [dict create status CLOSED]
    }
    if {$operation in {capture_verify capture_preview}} {
        set id [dict get $request capture_id]
        if {![regexp {^[0-9a-f]{32}$} $id] || ![dict exists $attached captures $id]} {error {Capture was not issued by this live source-bound GUI attachment}}
        set captured [dict get $attached captures $id]
        set path [dict get $captured screenshot];file lstat $path st
        if {$st(type) ne {file} || $st(nlink)!=1 || $st(size)>8388608 || [sha256File $path] ne [dict get $captured screenshot_sha256]} {error {Issued native capture bytes changed or exceed the manual image limit}}
        return [dict merge $captured [dict create operation $operation]]
    }
    set runtime [dict get $::GX::ViewerDevelopment::windows $w]
    if {[dict get $attached pressed]==2 && $operation ni {status capture capture_verify capture_preview close plot_pointer}} {error {Finish the owned Plot pan before other native input}}
    if {$operation ni {status capture open workspace_open} && ([dict get $runtime busy] ne {} || [dict get $runtime status] in {VALIDATING RUNNING})} {error {Wait for the actual compiled event to finish}}
    if {$operation eq {workspace_save}} {
        if {[dict get $attached pressed]} {error {Finish the owned pointer gesture before saving}}
        if {![dict exists $::GX::ViewerGui::instances $w workspace_provider] || ![dict exists $::GX::ViewerGui::instances $w workspace_callbacks]} {error {Declare the ordinary Session Workspace lifecycle before saving}}
        # Same public Save owner as the mounted Workspace menu. The caller
        # cannot supply a target ID, title, path, payload or foreign window.
        set instance [dict get $::GX::ViewerGui::instances $w]
        sessionWorkspaceViewerAction [dict get $instance workspace_provider] [dict get $instance workspace_callbacks] $w save propagate
        set savedId [viewerGuiDesignCurrent $w]
        set savedWorkspace [sessionWorkspaceGet $savedId]
    }
    if {$operation eq {resize}} {
        set width [dict get $request width];set height [dict get $request height]
        if {![string is integer -strict $width] || ![string is integer -strict $height] || $width<640 || $width>min(1880,[winfo screenwidth $w]-40) || $height<480 || $height>min(1100,[winfo screenheight $w]-100)} {error {Requested Viewer size exceeds bounded client pixels or available display}}
        # Tk's winfo id is its content child, without WM_NORMAL_HINTS. Use the
        # same native window-manager owner as Viewer/UI Field geometry, rather
        # than treating that child as a foreign application's client wrapper.
        wm geometry $w ${width}x${height}
        after 150 [list set ::GX::ViewerDevelopment::guiResizeReady 1];vwait ::GX::ViewerDevelopment::guiResizeReady;update
        if {[winfo width $w]!=$width || [winfo height $w]!=$height} {error {Native window manager did not commit the requested client size}}
    }
    if {[dict exists $request component]} {
        set id [dict get $request component]
        set component [viewerGuiDesignComponent $w $id]
        set type [dict get $component type]
        set widget [dict get $::GX::ViewerGui::instances $w widgets $id]
        switch -- $operation {
            pdf_control - pdf_pointer - pdf_key - pdf_resize - pdf_close {
                set pdf [_viewerDevelopmentGuiPdfTarget $w $id]
                set native [dict get $pdf window_id]
                exec xdotool windowraise $native windowfocus --sync $native
                if {$operation eq {pdf_control}} {
                    set command [dict get $request command]
                    if {$command ni {previous next zoom_out zoom_in fit_page fit_width}} {error {Unknown native PDF control}}
                    set control [dict get $pdf controls $command]
                    if {![dict get $control mapped] || ![dict get $control enabled]} {error {Requested PDF control is not currently enabled and visible}}
                    lassign [dict get $control rectangle] x y width height
                    exec xdotool mousemove [expr {$x+$width/2}] [expr {$y+$height/2}] click 1
                } elseif {$operation eq {pdf_resize}} {
                    foreach {axis low high} {width 640 1880 height 480 1100} {
                        set value [dict get $request $axis]
                        if {![string is integer -strict $value] || $value<$low || $value>$high} {error {PDF window size exceeds the admitted client bounds}}
                    }
                    # Tk's content XID has no WM hints; its actual X parent is
                    # the managed client. wm frame identifies WM decoration,
                    # which is a different window and also has no size hints.
                    set hierarchy [exec env LC_ALL=C xwininfo -id $native -tree]
                    if {![regexp {Parent window id: (0x[0-9a-fA-F]+)} $hierarchy -> client]} {error {Owned PDF window manager client is unavailable}}
                    set hints [exec env LC_ALL=C xprop -id $client WM_NORMAL_HINTS WM_STATE]
                    if {[string first {WM_STATE(WM_STATE)} $hints]<0 || [string first {WM_NORMAL_HINTS(WM_SIZE_HINTS)} $hints]<0} {error {Owned PDF parent is not a managed window client}}
                    exec xdotool windowsize --sync $client [dict get $request width] [dict get $request height]
                } elseif {$operation eq {pdf_close}} {
                    exec xdotool key --clearmodifiers alt+F4
                } elseif {$operation eq {pdf_key}} {
                    set key [dict get $request key]
                    if {$key ni {Left Right Up Down Tab shift+Tab}} {error {PDF native keys scroll or change focus only}}
                    lassign [dict get $pdf canvas rectangle] x y width height
                    exec xdotool mousemove [expr {$x+$width/2}] [expr {$y+$height/2}] click 1 key $key
                } else {
                    set phase [dict get $request phase]
                    if {$phase ni {click press move release wheel_up wheel_down}} {error {Unknown PDF pointer phase}}
                    foreach axis {x y} {set $axis [uiFieldNormalize {type number min 0 max 1} [dict get $request $axis]]}
                    lassign [dict get $pdf canvas rectangle] left top width height
                    exec xdotool mousemove [expr {$left+1+int($x*max(0,$width-3))}] [expr {$top+1+int($y*max(0,$height-3))}]
                    switch $phase {
                        click {exec xdotool click 1}
                        press {if {[dict get $attached pressed]} {error {Finish the current owned gesture first}};exec xdotool mousedown 1;dict set ::GX::ViewerDevelopment::guiTests $project pressed 1;dict set ::GX::ViewerDevelopment::guiTests $project pressed_component $id}
                        move - release {
                            if {[dict get $attached pressed]!=1 || ![dict exists $attached pressed_component] || [dict get $attached pressed_component] ne $id} {error {Start a pan on this owned PDF before moving/releasing}}
                            if {$phase eq {release}} {exec xdotool mouseup 1;dict set ::GX::ViewerDevelopment::guiTests $project pressed 0}
                        }
                        wheel_up {exec xdotool click 4}
                        wheel_down {exec xdotool click 5}
                    }
                }
                after 250 [list set ::GX::ViewerDevelopment::guiPdfReady 1];vwait ::GX::ViewerDevelopment::guiPdfReady;update
            }
            click {
                if {$type eq {document} && [dict get $component properties kind] in {html code}} {
                    set target [expr {[dict get $component properties kind] eq {html}?"$widget.content":"$widget.source.text"}]
                    _viewerDevelopmentGuiClick $target
                } elseif {$type eq {action}} {
                    if {[dict get $component properties action] ni [dict get $attached fixture_options permitted_commands]} {error {Action is outside the private GUI fixture command grant}}
                    _viewerDevelopmentGuiClick $widget
                } elseif {$type in {toggle checkbutton}} {
                    if {[dict exists $component properties change_action] && [dict get $component properties change_action] ni [dict get $attached fixture_options permitted_commands]} {error {Boolean change action is outside the private GUI fixture command grant}}
                    set control [expr {$type eq {toggle} ? "$widget.entry" : $widget}]
                    if {![winfo exists $control] || [winfo class $control] ne {TCheckbutton}} {error {Declared boolean has no native checkbutton}}
                    if {[$control instate disabled]} {error {Declared boolean control is disabled}}
                    _viewerDevelopmentGuiClick $control
                } else {error {Click requires a declared action or native toggle/checkbutton}}
            }
            choice {if {$type ni {choice combobox dataset_selector}} {error {Choice requires a declared native selector}};set control [expr {$type eq {combobox}?$widget:"$widget.entry"}];_viewerDevelopmentGuiChoose $control [dict get $request value] $w}
            text {if {$type ni {entry field}} {error {Text requires a declared field}};set control [expr {$type eq {entry}?$widget:"$widget.entry"}];_viewerDevelopmentGuiType $control [dict get $request value]}
            source_text {
                set texInput [_viewerDevelopmentGuiTeXSource $w $id];set target [dict get $texInput target]
                # Ordinary typing at the live caret/selection. No source setter,
                # canonical Save, hidden selection replacement or build occurs.
                raise $w;exec xdotool windowfocus --sync [winfo id $w];update
                set x [expr {[winfo rootx $target]+[winfo width $target]/2}];set y [expr {[winfo rooty $target]+[winfo height $target]/2}]
                if {[winfo containing -displayof $target $x $y] ne $target} {error {Declared source is clipped or occluded}}
                focus -force $target;update
                if {[focus] ne $target} {error {Declared source did not retain native typing focus}}
                _viewerDevelopmentGuiTeXSource $w $id $texInput
                exec xdotool type --clearmodifiers --delay 1 -- [dict get $request value];update
            }
            source_replace {
                set texInput [_viewerDevelopmentGuiTeXSource $w $id];set target [dict get $texInput target]
                set surface [sourceSurfaceParent $target];set original [sourceSurfaceGet $target]
                set guard [list ::GX::_viewerDevelopmentGuiTeXSource $w $id $texInput]
                set query $surface.find.query;set replacement $surface.find.replace.value
                set button $surface.find.replace.[dict get $request scope]
                foreach control [list $query $replacement $button] {
                    if {![winfo exists $control] || ![winfo ismapped $control] || [$control instate disabled]} {error {Show enabled native Find/Replace controls before replacement}}
                }
                _viewerDevelopmentGuiType $query [dict get $request query] $guard
                _viewerDevelopmentGuiClick $surface.find.next $guard
                _viewerDevelopmentGuiType $replacement [dict get $request replacement] $guard
                {*}$guard
                if {[sourceSurfaceGet $target] ne $original} {error {Source changed while entering the Find/Replace fields; no replacement clicked}}
                _viewerDevelopmentGuiClick $button $guard
            }
            table_page {set probe [_viewerDevelopmentGuiTablePage $w $id [dict get $request command] [datasetPublicationV2DictDefault $request row {}]]}
            table_scroll - table_select - table_copy {
                set tableTarget [_viewerDevelopmentGuiTableTarget $w $id]
                set tableParent [dict get $tableTarget parent];set tree [dict get $tableTarget tree]
                if {![winfo ismapped $tree]} {error {Show the declared table before native input}}
                raise $w;focus -force $tree;update
                _viewerDevelopmentGuiTableCurrent $w $id $tableTarget
                if {$operation eq {table_scroll}} {
                    set axis [dict get $request axis];set direction [dict get $request direction]
                    if {$axis ni {x y} || $direction ni {backward forward}} {error {Table scroll uses axis x|y and direction backward|forward}}
                    set bar $tableParent.[expr {$axis eq {x}?{horizontal}:{vertical}}]
                    if {![winfo exists $bar] || ![winfo ismapped $bar]} {error {Declare and show the requested native table scrollbar}}
                    set length [expr {$axis eq {x}?[winfo width $bar]:[winfo height $bar]}]
                    set cross [expr {$axis eq {x}?[winfo height $bar]:[winfo width $bar]}]
                    set found 0
                    for {set offset 2} {$offset<min(30,$length/2)} {incr offset 2} {
                        set along [expr {$direction eq {backward}?$offset:$length-1-$offset}]
                        set px [expr {$axis eq {x}?$along:$cross/2}];set py [expr {$axis eq {y}?$along:$cross/2}]
                        set element [$bar identify $px $py]
                        if {[string match *arrow $element]} {set found 1;break}
                    }
                    if {!$found} {error {The active theme exposes no visible native scrollbar arrow}}
                    set sx [expr {[winfo rootx $bar]+$px}];set sy [expr {[winfo rooty $bar]+$py}]
                    if {[winfo containing -displayof $bar $sx $sy] ne $bar} {error {Requested native scrollbar arrow is occluded}}
                    set before [$tree ${axis}view]
                    exec xdotool mousemove $sx $sy click 1;update
                    set probe [dict create axis $axis direction $direction element $element actual_pointer [list $sx $sy] before $before after [$tree ${axis}view]]
                } elseif {$operation eq {table_select}} {
                    set index [dict get $request index];set items [$tree children {}]
                    if {![string is integer -strict $index] || $index<0 || $index>=1000 || $index>=[llength $items]} {error {Select an existing native table row0..999}}
                    set item [lindex $items $index];$tree see $item;update
                    _viewerDevelopmentGuiTableCurrent $w $id $tableTarget
                    set box [$tree bbox $item];if {[llength $box]!=4} {error {Requested table row is clipped}}
                    lassign $box x y width height
                    set px [expr {max(3,min([winfo width $tree]-4,$x+min(30,$width/2)))}];set py [expr {$y+$height/2}]
                    set sx [expr {[winfo rootx $tree]+$px}];set sy [expr {[winfo rooty $tree]+$py}]
                    if {[$tree identify row $px $py] ne $item || [winfo containing -displayof $tree $sx $sy] ne $tree} {error {Actual native table row is occluded}}
                    exec xdotool mousemove $sx $sy click 1;update
                    if {[$tree selection] ne [list $item]} {error {Actual native table selection differs}}
                    set probe [dict create row_index $index values [$tree item $item -values] actual_pointer [list $sx $sy] selection [$tree selection]]
                } else {
                    set probe [_viewerDevelopmentGuiTableCopy $w $id $tableTarget]
                }
            }
            list_select {
                if {$type ne {list} || ![winfo exists $widget] || [winfo class $widget] ne {Listbox} || ![winfo ismapped $widget]} {error {List selection requires a visible declared native list}}
                if {[dict exists $component properties change_action] && [dict get $component properties change_action] ni [dict get $attached fixture_options permitted_commands]} {error {List change action is outside the private GUI fixture command grant}}
                set index [dict get $request index]
                if {![string is integer -strict $index] || $index<0 || $index>=1000 || $index>=[$widget size]} {error {Select an existing native list row0..999}}
                raise $w;exec xdotool windowfocus --sync [winfo id $w];update
                $widget see $index;update
                set box [$widget bbox $index];if {$box eq {}} {error {Requested native list row is clipped}}
                lassign $box x y width height
                set px [expr {max(3,min([winfo width $widget]-4,$x+min(30,$width/2)))}];set py [expr {$y+$height/2}]
                set sx [expr {[winfo rootx $widget]+$px}];set sy [expr {[winfo rooty $widget]+$py}]
                if {[$widget nearest $py]!=$index || [winfo containing -displayof $widget $sx $sy] ne $widget} {error {Actual native list row is occluded}}
                exec xdotool mousemove $sx $sy click 1;update
                if {[$widget curselection] ne [list $index]} {error {Actual native list selection differs}}
                set probe [dict create row_index $index label [$widget get $index] actual_pointer [list $sx $sy] selection [$widget curselection]]
            }
            document_find {
                if {$type ne {document} || [dict get $component properties kind] ni {code tex} || ![winfo exists $widget.source.find.query]} {error {Find requires a declared code or TeX source document}}
                set guard {}
                if {[dict get $component properties kind] eq {tex}} {set texInput [_viewerDevelopmentGuiTeXSource $w $id];set guard [list ::GX::_viewerDevelopmentGuiTeXSource $w $id $texInput]}
                if {[dict get $request direction] ni {forward backward}} {error {Invalid source search direction}}
                _viewerDevelopmentGuiType $widget.source.find.query [dict get $request value] $guard
                if {$guard ne {}} {{*}$guard}
                _viewerDevelopmentGuiClick $widget.source.find.[expr {[dict get $request direction] eq {forward} ? {next} : {previous}}]
            }
            document_zoom {
                if {$type ne {document} || [dict get $component properties kind] ne {html}} {error {Zoom controls require a bound HTML document}}
                set action [dict get $request value]
                if {$action ni {in out reset}} {error {Document zoom must be in, out or reset}}
                set button $widget.zoom.[dict get {in larger out smaller reset reset} $action]
                if {![winfo exists $button]} {error {Bind the HTML document before using its zoom controls}}
                _viewerDevelopmentGuiClick $button
            }
            tab {
                if {$type ne {tab}} {error {Select a declared tab}}
                set parent [dict get $::GX::ViewerGui::instances $w widgets [dict get $component parent]]
                set wanted [lsearch -exact [$parent tabs] $widget];set found 0
                raise $w;exec xdotool windowfocus --sync [winfo id $w];update
                # A long page can scroll its notebook header above the shared
                # inspector viewport. Focus uses the ordinary UI Field owner to
                # reveal that header before calculating any desktop position.
                focus -force $parent;update
                after 120 [list set ::GX::ViewerDevelopment::guiTabReady 1];vwait ::GX::ViewerDevelopment::guiTabReady;update
                for {set x 6} {$x<[winfo width $parent]} {incr x 4} {
                    if {[$parent identify tab $x 10] eq $wanted} {
                        set px [expr {[winfo rootx $parent]+$x}];set py [expr {[winfo rooty $parent]+10}]
                        if {[winfo containing -displayof $parent $px $py] ne $parent} {error {Requested tab header is clipped or occluded}}
                        exec xdotool mousemove $px $py click 1;update
                        if {[$parent select] ne $widget} {error {Native tab selection did not commit}}
                        set found 1;break
                    }
                }
                if {!$found} {error {Requested tab is outside the visible notebook}}
            }
            plot_pointer {
                if {$type ne {plot}} {error {Plot pointer requires a declared canonical Plot}}
                set plot $widget.plot
                if {![winfo exists $plot] || ![winfo ismapped $plot]} {error {Bind and show the declared Plot before probing}}
                set x [uiFieldNormalize {type number min 0 max 1} [dict get $request x]]
                set y [uiFieldNormalize {type number min 0 max 1} [dict get $request y]]
                set px [expr {int($x*([winfo width $plot]-1))}];set py [expr {int($y*([winfo height $plot]-1))}]
                raise $w;exec xdotool windowfocus --sync [winfo id $w]
                update
                set screenX [expr {[winfo rootx $plot]+$px}];set screenY [expr {[winfo rooty $plot]+$py}]
                if {[winfo containing -displayof $plot $screenX $screenY] ne $plot} {error {Declared Plot pointer is clipped or occluded}}
                set phase [datasetPublicationV2DictDefault $request phase click]
                if {$phase ni {click double wheel_up wheel_down press move release}} {error {Unsupported bounded Plot gesture}}
                set pressed [dict get $::GX::ViewerDevelopment::guiTests $project pressed]
                if {$phase in {move release} && ($pressed!=2 || [datasetPublicationV2DictDefault [dict get $::GX::ViewerDevelopment::guiTests $project] pressed_component {}] ne $id)} {error {Start a middle-button pan on this declared Plot before moving or releasing}}
                if {$phase ni {move release} && $pressed} {error {Release the current owned pointer gesture first}}
                exec xdotool mousemove $screenX $screenY;update
                switch $phase {
                    click {exec xdotool click 1}
                    double {exec xdotool click --repeat 2 --delay 100 1}
                    wheel_up {exec xdotool click 4}
                    wheel_down {exec xdotool click 5}
                    press {exec xdotool mousedown 2;dict set ::GX::ViewerDevelopment::guiTests $project pressed 2;dict set ::GX::ViewerDevelopment::guiTests $project pressed_component $id}
                    release {exec xdotool mouseup 2;dict set ::GX::ViewerDevelopment::guiTests $project pressed 0}
                }
                update
                if {$phase eq {click}} {set probe [viewerGuiDesignPlotProbe $w $id $px $py]}
            }
            capture {
                if {[dict get $request dialog] eq {pdf_reader}} {
                    set pdf [_viewerDevelopmentGuiPdfTarget $w $id]
                    set captureNative [dict get $pdf frame_id]
                    set captureGeometry [dict get $pdf geometry]
                    exec xdotool windowraise [dict get $pdf window_id]
                } else {set captureWindow [_viewerDevelopmentGuiOwnedDialog $w $id [dict get $request dialog]]}
            }
            key {
                set key [dict get $request key]
                if {$key eq {PageDown}} {set key Page_Down} elseif {$key eq {PageUp}} {set key Page_Up}
                if {$type eq {plot}} {
                    if {$key ne {Escape}} {error {Declared Plot keyboard input permits Escape only}}
                    set target $widget.plot
                    if {![winfo exists $target] || ![winfo ismapped $target]} {error {Bind and show the declared Plot before clearing its source cursor}}
                } elseif {$type eq {document} && [dict get $component properties kind] eq {tex}} {
                    if {$key ni {Escape Delete BackSpace Return ctrl+z ctrl+y ctrl+f ctrl+h F3 shift+F3 ctrl+a ctrl+c Home End ctrl+Home ctrl+End Page_Up Page_Down Up Down Left Right Tab shift+Tab}} {error {Key is outside the editable source contract}}
                    set texInput [_viewerDevelopmentGuiTeXSource $w $id];set target [dict get $texInput target]
                } elseif {$type eq {document} && [dict get $component properties kind] in {code html}} {
                    if {$key ni {Escape ctrl+f F3 shift+F3 ctrl+a ctrl+c ctrl+plus ctrl+equal ctrl+minus ctrl+0 Home End ctrl+Home ctrl+End Page_Up Page_Down Up Down Left Right Tab shift+Tab}} {error {Read-only source input cannot edit or execute}}
                    if {$key in {ctrl+plus ctrl+equal ctrl+minus ctrl+0} && [dict get $component properties kind] ne {html}} {error {Text zoom keys belong to the rendered HTML contract}}
                    set target [expr {[dict get $component properties kind] eq {html}?"$widget.content":"$widget.source.text"}]
                    if {![winfo exists $target] || ![winfo ismapped $target]} {error {Bind and show the code document before keyboard input}}
                } elseif {$type eq {native2d} && [dict exists [dict get $component properties] diagram_catalog]} {
                    if {$key ni {Escape Delete BackSpace r w j p f ctrl+z ctrl+y}} {error {Key is outside the native schematic contract}}
                    set target $widget.diagram.canvas
                    if {![winfo ismapped $target]} {error {Select the schematic tab before keyboard input}}
                } else {error {Keyboard input requires a declared bound Plot or diagram viewport}}
                raise $w;exec xdotool windowfocus --sync [winfo id $w];update
                if {$type eq {document} && [dict get $component properties kind] eq {tex}} {_viewerDevelopmentGuiTeXSource $w $id $texInput}
                set x [expr {[winfo rootx $target]+[winfo width $target]/2}];set y [expr {[winfo rooty $target]+[winfo height $target]/2}]
                if {[winfo containing -displayof $target $x $y] ne $target} {error {Declared keyboard viewport is clipped or occluded}}
                # --clearmodifiers also releases held mouse buttons, committing
                # a drag before Escape reaches the actual viewport binding.
                focus -force $target;exec xdotool key $key;update
                if {$type eq {document} && $key eq {ctrl+c}} {
                    set copied [dict create status no_selected_text]
                    if {[llength [$target tag ranges sel]]} {
                        set selected [$target get sel.first sel.last]
                        set clipboard [clipboard get -displayof $target]
                        set bytes [encoding convertto utf-8 $clipboard]
                        dict set copied status copied
                        dict set copied matches_selection [expr {$clipboard eq $selected}]
                        dict set copied characters [string length $clipboard]
                        dict set copied utf8_bytes [string length $bytes]
                        dict set copied sha256 [datasetStorageSha256Text $::GX::currentSession $clipboard]
                        dict set copied text_prefix [string range $clipboard 0 16383]
                        dict set copied complete [expr {[string length $clipboard]<=16384}]
                    }
                }
            }
            document_pointer {
                if {$type ne {document} || [dict get $component properties kind] ni {html code tex}} {error {Document pointer requires a declared HTML, code or TeX component}}
                if {[dict get $component properties kind] eq {tex}} {set texInput [_viewerDevelopmentGuiTeXSource $w $id];set target [dict get $texInput target]} else {set target [expr {[dict get $component properties kind] eq {html}?"$widget.content":"$widget.source.text"}]}
                if {![winfo exists $target] || ![winfo ismapped $target]} {error {Bind and show the document first}}
                set phase [dict get $request phase]
                if {$phase ni {click wheel_up wheel_down}} {error {Read-only document pointer permits click or wheel only}}
                foreach axis {x y} {set $axis [uiFieldNormalize {type number min 0 max 1} [dict get $request $axis]]}
                set px [expr {[winfo rootx $target]+1+int($x*max(0,[winfo width $target]-3))}]
                set py [expr {[winfo rooty $target]+1+int($y*max(0,[winfo height $target]-3))}]
                raise $w;update
                if {[dict get $component properties kind] eq {tex}} {_viewerDevelopmentGuiTeXSource $w $id $texInput}
                if {[winfo containing -displayof $target $px $py] ne $target} {error {Document pointer target is clipped or occluded}}
                exec xdotool windowfocus --sync [winfo id $w]
                exec xdotool mousemove $px $py click [dict get {click 1 wheel_up 4 wheel_down 5} $phase]
                update
            }
            pointer - property - properties_commit - properties_close - wire_route - label - label_apply - label_close {
                if {$type ne {native2d} || ![dict exists [dict get $component properties] diagram_catalog]} {error {Schematic input requires a declared diagram viewport}}
                set viewport $widget.diagram;set canvas $viewport.canvas
                if {![winfo ismapped $canvas]} {error {Select the schematic tab before pointer input}}
                if {$operation eq {pointer}} {
                    foreach key {x y} {set v [uiFieldNormalize {type number min -1000000 max 1000000} [dict get $request $key]];dict set request $key $v}
                    set phase [dict get $request phase]
                    if {$phase ni {click double press move release wheel_up wheel_down}} {error {Unsupported pointer phase}}
                    set token [dict get $::GX::Native2DDiagram::viewports $viewport projection scene_token]
                    lassign [dict get [native2DGeometryCall $token world_to_device [dict create point [list [dict get $request x] [dict get $request y]]]] point] x y
                    if {$x<0 || $y<0 || $x>=[winfo width $canvas] || $y>=[winfo height $canvas]} {error {Pointer lies outside the assigned native viewport}}
                    raise $w;exec xdotool windowfocus --sync [winfo id $w]
                    exec xdotool mousemove [expr {int([winfo rootx $canvas]+$x)}] [expr {int([winfo rooty $canvas]+$y)}];update
                    switch -- $phase {
                        click {exec xdotool click 1}
                        double {exec xdotool click --repeat 2 --delay 100 1}
                        press {exec xdotool mousedown 1;dict set ::GX::ViewerDevelopment::guiTests $project pressed 1}
                        release {exec xdotool mouseup 1;dict set ::GX::ViewerDevelopment::guiTests $project pressed 0}
                        wheel_up {exec xdotool click 4}
                        wheel_down {exec xdotool click 5}
                    }
                } elseif {$operation in {label label_apply label_close}} {
                    set dialog [_viewerDevelopmentGuiOwnedDialog $w $id net_label]
                    switch $operation {
                        label {if {[dict get $request field] ne {name}} {error {Net label popup exposes only its typed name field}};_viewerDevelopmentGuiType $dialog.value [dict get $request value]}
                        label_apply {_viewerDevelopmentGuiClick $dialog.apply}
                        label_close {_viewerDevelopmentGuiClick $dialog.cancel}
                    }
                } else {
                    set dialog [_viewerDevelopmentGuiOwnedDialog $w $id properties]
                    if {![winfo exists $dialog]} {error {Open the selected symbol properties through the actual GUI first}}
                    switch -- $operation {
                        wire_route {
                            if {![info exists ::GX::Native2DDiagram::field($viewport,properties_kind)] || $::GX::Native2DDiagram::field($viewport,properties_kind) ne {wire}} {error {Open selected wire Properties first}}
                            set fields $::GX::Native2DDiagram::field($viewport,properties_fields)
                            set command [dict get $request command]
                            if {$command eq {select}} {
                                set tree $fields.points.tree;set index [dict get $request index]
                                set items [$tree children {}]
                                if {$index>=[llength $items]} {error {Bend index is absent from the actual route editor}}
                                set item [lindex $items $index];$tree see $item
                                focus -force $tree;update
                                set box [$tree bbox $item]
                                if {[llength $box]!=4} {error {Requested bend is not visible}}
                                lassign $box x y width height
                                set px [expr {[winfo rootx $tree]+$x+min(24,$width/2)}];set py [expr {[winfo rooty $tree]+$y+$height/2}]
                                if {[winfo containing -displayof $tree $px $py] ne $tree} {error {Requested bend is clipped or occluded}}
                                raise $dialog;exec xdotool windowfocus --sync [winfo id $dialog]
                                exec xdotool mousemove $px $py click 1;update
                                if {[$tree selection] ne $item} {error {Native bend selection did not commit}}
                            } else {
                                if {[$fields.actions.$command instate disabled]} {error {Wire bend action is disabled for the current selection}}
                                _viewerDevelopmentGuiClick $fields.actions.$command
                            }
                        }
                        properties_commit {_viewerDevelopmentGuiClick $dialog.buttons.apply}
                        properties_close {_viewerDevelopmentGuiClick $dialog.buttons.close}
                        property {
                            set field [dict get $request field]
                            if {![regexp {^[a-z][a-z0-9_]{0,31}$} $field]} {error {Invalid typed symbol attribute}}
                            set fields $dialog.fields
                            if {[info exists ::GX::Native2DDiagram::field($viewport,properties_fields)]} {set fields $::GX::Native2DDiagram::field($viewport,properties_fields)}
                            set entry $fields.f$field.entry
                            if {![winfo exists $entry]} {error {Attribute is absent from the actual symbol properties}}
                            if {[winfo class $entry] eq {TCombobox}} {_viewerDevelopmentGuiChoose $entry [dict get $request value] $dialog} else {_viewerDevelopmentGuiType $entry [dict get $request value]}
                        }
                    }
                }
            }
        }
        after 100 [list set ::GX::ViewerDevelopment::guiInputReady 1];vwait ::GX::ViewerDevelopment::guiInputReady;update
    }
    set result [dict create operation $operation source_snapshot [dict get $attached snapshot] session $::GX::currentSession status [dict get $::GX::ViewerDevelopment::windows $w status] busy [expr {[dict get $::GX::ViewerDevelopment::windows $w busy] ne {}}] native_input xdotool_assigned_window]
    if {$operation eq {resize}} {dict set result geometry [winfo geometry $w];dict set result native_input Tk_native_window_manager}
    if {$operation in {status capture}} {dict set result native_input read_only_or_capture}
    if {$operation eq {workspace_open}} {dict set result native_input registered_Session_Workspace_factory;dict set result workspace_id [dict get $request workspace_id]}
    if {$operation eq {workspace_save}} {dict set result native_input assigned_Viewer_Session_Workspace_save_owner;dict set result workspace_id $savedId;dict set result workspace_stamp [_viewerDevelopmentWorkspaceStamp $savedWorkspace]}
    if {[dict get $result status] eq {FAILED} && [dict exists $::GX::ViewerDevelopment::windows $w last_result]} {
        set failure [dict get $::GX::ViewerDevelopment::windows $w last_result]
        if {[dict exists $failure host_error]} {dict set result host_error [string range [dict get $failure host_error] 0 8191]}
        if {![dict get $failure ok]} {
            dict set result host_error [string range [dict get $failure error] 0 8191]
            if {[dict exists $failure code]} {dict set result error_code [dict get $failure code]}
        }
    }
    if {[info exists probe]} {dict set result native_probe $probe}
    if {[info exists copied]} {dict set result clipboard_receipt $copied}
    if {[dict exists $::GX::ViewerGui::instances $w]} {
        dict set result values [viewerGuiDesignValues $w]
        set capture [viewerGuiDesignCapture $w]
        dict set result bindings [dict get $capture bindings]
        dict set result choices [dict get $capture choices]
        dict set result domain_state [viewerGuiDesignContextGet $w]
        dict set result workspace_id [viewerGuiDesignCurrent $w]
        set readOnly {};set catalogs {};set endpoints {};set plots {};set properties {}
        foreach definition [dict get $::GX::ViewerGui::instances $w design components] {
            set id [dict get $definition id];set type [dict get $definition type]
            set widget [dict get $::GX::ViewerGui::instances $w widgets $id]
            if {$type in {choice dataset_selector combobox}} {
                set choiceWidget [expr {$type eq {combobox}?$widget:"$widget.entry"}]
                if {[winfo exists $choiceWidget]} {dict set result choices $id [$choiceWidget cget -values]}
            }
            if {$type eq {list} && [winfo exists $widget]} {
                set shown {};foreach label [$widget get 0 999] {lappend shown [string range $label 0 255]}
                dict set result lists $id [dict create count [$widget size] shown $shown selection [$widget curselection]]
            }
            if {$type eq {table} && [winfo exists $widget]} {
                set tree [uiFieldComponentTableWidget $widget]
                set rowIds [$tree children {}];set rows {}
                foreach row [lrange $rowIds 0 49] {set cells {};foreach value [$tree item $row -values] {lappend cells [string range $value 0 1023]};lappend rows $cells}
                dict set result tables $id [dict create columns [$tree cget -columns] count [llength $rowIds] shown $rows selection [$tree selection] scrollbars [datasetPublicationV2DictDefault [dict get $definition properties] scrollbars none] xview [$tree xview] yview [$tree yview]]
            }
            if {$type eq {section} && [datasetPublicationV2DictDefault [dict get $definition properties] catalog_owner {}] eq {scientific_libraries}} {
                set state [viewerGuiDesignCatalogDescribe $w $id];set summary {}
                foreach key {owner presentation_only generation selected request} {dict set summary $key [dict get $state $key]}
                set caps {};dict for {key value} [dict get $state capabilities] {dict set caps $key [string range $value 0 4095]};dict set summary capabilities $caps
                set page [dict get $state page];catch {dict unset page records};dict set summary page $page
                dict set summary entry_count [llength [dict get $state entries]]
                set action [dict get $state last_action]
                if {$action ne {}} {
                    if {[dict exists $action result]} {
                        set raw [dict get $action result];set projection {}
                        dict for {key value} $raw {dict set projection $key [string range $value 0 4095]}
                        dict set action result $projection
                        dict set action result_presentation_bounded 1
                    }
                    dict set summary last_action $action
                }
                dict set result library_catalogs $id $summary
            }
            if {$type eq {document} && [dict get $definition properties kind] in {html code tex}} {
                set kind [dict get $definition properties kind]
                set target [expr {$kind eq {html}?"$widget.content":"$widget.source.text"}]
                if {[winfo exists $target]} {
                    dict set result document_receipts $id [dict create content_kind $kind state [$target cget -state] text_prefix [$target get 1.0 {1.0 + 16384 chars}] characters [$target count -chars 1.0 end-1c] yview [$target yview] xview [$target xview] visible_first [$target index @0,0] visible_last [$target index @[winfo width $target],[winfo height $target]] mapped [winfo ismapped $target] dimensions [list [winfo width $target] [winfo height $target]]]
                    dict set result document_receipts $id actual_font [font actual [$target cget -font]]
                    dict set result document_receipts $id selection [$target tag ranges sel]
                    dict set result document_receipts $id insertion [$target index insert]
                    if {$kind in {code tex}} {dict set result document_receipts $id find_result [sourceSurfaceFindInspect $target]}
                    if {[winfo exists $widget.zoom.level]} {dict set result document_receipts $id zoom_level [$widget.zoom.level cget -text]}
                }
            }
            if {$type eq {document} && [dict get $definition properties kind] eq {pdf}} {dict set result document_receipts $id [viewerGuiDesignDocumentInspect $w $id]}
            if {$type eq {document} && [dict get $definition properties kind] eq {table} && [winfo exists $widget.table.tree]} {
                if {[catch {_viewerDevelopmentGuiTableTarget $w $id} tableError]} {
                    dict set result document_receipts $id [dict create content_kind table status unavailable reason $tableError]
                } else {
                    dict set result document_receipts $id [dict merge [datasetPreviewTableInspect $widget.table] [dict create content_kind table]]
                }
            }
            if {$type eq {plot} && [winfo exists $widget.plot]} {
                if {[catch {viewerGuiDesignPlotReceipt $w $id} plotReceipt]} {dict set plots $id error $plotReceipt} else {dict set plots $id $plotReceipt}
            }
            if {$type in {label status log} && [winfo exists $widget]} {
                if {$type eq {log}} {set text [$widget get 1.0 16385.0]} else {set text [$widget cget -text]}
                dict set readOnly $id [string range $text 0 16383]
            }
            if {$type eq {native2d} && [dict exists $definition properties diagram_catalog]} {
                set viewport $widget.diagram
                if {![catch {_viewerDevelopmentGuiOwnedDialog $w $id properties} dialog] && [info exists ::GX::Native2DDiagram::field($viewport,properties_kind)] && $::GX::Native2DDiagram::field($viewport,properties_kind) eq {wire}} {
                    set fields $::GX::Native2DDiagram::field($viewport,properties_fields)
                    set tree $fields.points.tree;set values {}
                    foreach key {start end point_x point_y} {dict set values $key [$fields.f$key.entry get]}
                    set record [dict create kind wire wire_id $::GX::Native2DDiagram::field($viewport,wire_id) source $::GX::Native2DDiagram::field($viewport,wire_source) values $values endpoint_choices [$fields.fstart.entry cget -values] route $::GX::Native2DDiagram::field($viewport,wire_route) selected_index [lsearch -exact [$tree children {}] [lindex [$tree selection] 0]] error [$dialog.error cget -text]]
                    dict set properties $id $record
                }
                set catalog [dict get $definition properties diagram_catalog]
                dict set catalogs $id [native2DGeometryDiagramCatalog $catalog]
                if {[dict exists $capture bindings $id payload]} {
                    set payload [dict get $capture bindings $id payload]
                    dict for {object item} [dict get $payload components] {
                        dict for {pin offset} [dict get [native2DGeometryDiagramCatalog $catalog] symbols [dict get $item kind] pins] {
                            dict set endpoints $id [list $object $pin] [native2DGeometryDiagramEndpoint $payload [list $object $pin]]
                        }
                    }
                    dict for {object item} [dict get $payload junctions] {dict set endpoints $id [list $object] [native2DGeometryDiagramEndpoint $payload [list $object]]}
                }
            }
        }
        dict set result read_only $readOnly;dict set result diagram_catalogs $catalogs;dict set result diagram_endpoints $endpoints;dict set result plot_receipts $plots
        dict set result properties $properties
        if {[dict exists $::GX::ScientificHistory::viewers $w]} {
            set history [scientificHistoryViewerRecord $w]
            dict set result history [dict create cursor [dict get $history cursor] step_count [llength [dict get $history steps]]]
        }
    }
    if {$operation eq {capture}} {
        if {![info exists captureNative]} {
            if {![info exists captureWindow]} {set captureWindow $w}
            raise $captureWindow;update idletasks
            set captureNative [wm frame $captureWindow]
            set captureGeometry [winfo geometry $captureWindow]
        }
        set path [file join [_viewerDevelopmentGuiFolder $project] capture-[dict get $request request_id].png]
        set channel [open [list | import -screen -window $captureNative png:-] rb]
        try {set bytes [read $channel 33554433]} finally {close $channel}
        if {[string length $bytes]>33554432} {error {Native capture exceeds32MiB}}
        resourceLifecycleWriteBytes $path $bytes
        dict set result screenshot $path;dict set result screenshot_sha256 [sha256File $path]
        dict set result geometry $captureGeometry
        if {[dict exists $request dialog]} {dict set result capture_target [dict get $request dialog]}
        set captures [datasetPublicationV2DictDefault [dict get $::GX::ViewerDevelopment::guiTests $project] captures {}]
        if {[dict size $captures]>=128} {dict unset captures [lindex [dict keys $captures] 0]}
        dict set captures [dict get $request request_id] [dict create operation capture source_snapshot [dict get $attached snapshot] screenshot $path screenshot_sha256 [dict get $result screenshot_sha256] session $::GX::currentSession geometry [dict get $result geometry]]
        dict set ::GX::ViewerDevelopment::guiTests $project captures $captures
    }
    return $result
}
proc ::GX::_viewerDevelopmentGuiPdfTarget {window component} {
    set public [viewerGuiDesignDocumentInspect $window $component]
    if {[dict get $public state] ni {ready unavailable} || ![dict exists $::GX::ViewerGui::instances $window document_readers $component]} {error {Wait for the current source-bound PDF reader}}
    set owner [dict get $::GX::ViewerGui::instances $window document_readers $component]
    set native $::GX::DatasetViewer::state($owner,mediaReceipt)
    if {![dict exists $native window_id] || ![dict get $native mapped] || ![dict get $native canvas mapped]} {error {Owned PDF reader is not visible}}
    return $native
}
proc ::GX::_viewerDevelopmentGuiOwnedDialog {window component kind} {
    set definition [viewerGuiDesignComponent $window $component]
    if {[dict get $definition type] ne {native2d} || ![dict exists $definition properties diagram_catalog]} {error {Dialog requires a declared schematic component}}
    set viewport [dict get $::GX::ViewerGui::instances $window widgets $component].diagram
    if {![dict exists $::GX::Native2DDiagram::viewports $viewport] || [dict get $::GX::Native2DDiagram::viewports $viewport document] ne [dict get $::GX::ViewerGui::instances $window bindings $component document_id]} {error {Schematic dialog source binding differs}}
    switch $kind {net_label {set dialog $viewport.netlabel} properties {set dialog $viewport.properties} default {error {Unknown owned schematic dialog}}}
    if {![winfo exists $dialog] || ![winfo ismapped $dialog] || [winfo class $dialog] ne {Toplevel} || [wm transient $dialog] ne $window} {error {Open the actual owned schematic dialog first}}
    return $dialog
}
