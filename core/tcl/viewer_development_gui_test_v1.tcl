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
    return [dict create status attached project $project module $module snapshot $snapshot actions {open workspace_open workspace_save workspace_review workspace_upgrade status close capture capture_verify capture_preview resize label label_apply label_close click choice text tab pointer plot_pointer key property wire_route properties_commit properties_close}]
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
proc ::GX::_viewerDevelopmentGuiClick {widget} {
    if {![winfo exists $widget] || ![winfo ismapped $widget]} {error {Declared control is not visible; select its tab first}}
    set top [winfo toplevel $widget];raise $top;update idletasks
    exec xdotool windowfocus --sync [winfo id $top]
    # The shared inspector scrolls focused controls into view. Settle that
    # ordinary focus behavior before locating the native click, so a press
    # cannot move its own target out from under the matching release.
    focus -force $widget;update
    after 120 [list set ::GX::ViewerDevelopment::guiInputReady 1];vwait ::GX::ViewerDevelopment::guiInputReady;update
    set x [expr {[winfo rootx $widget]+[winfo width $widget]/2}];set y [expr {[winfo rooty $widget]+[winfo height $widget]/2}]
    set hit [winfo containing -displayof $widget $x $y]
    if {$hit ne $widget && ![string match "$widget.*" $hit]} {error {Declared control is clipped or occluded; show it before clicking}}
    exec xdotool mousemove $x $y
    update;exec xdotool mousedown 1;update;exec xdotool mouseup 1;update
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
proc ::GX::_viewerDevelopmentGuiType {widget value} {
    if {![winfo exists $widget] || ![winfo ismapped $widget]} {error {Declared entry is not visible}}
    focus -force $widget;update
    exec xdotool key Home shift+End BackSpace
    exec xdotool type --clearmodifiers -- $value
    exec xdotool key Tab;update
}
proc ::GX::_viewerDevelopmentGuiAction {project connection request} {
    set attached [dict get $::GX::ViewerDevelopment::guiTests $project]
    if {[dict get $request connection] ne $connection || [dict get $attached session] ne $::GX::currentSession || [dict get $attached session_token] ne [interactiveDocumentSessionToken] || ![viewerGuiTestFixtureValidate {} [dict get $attached fixture_options]] || [dict get $request snapshot] ne [dict get $attached snapshot] || [_viewerDevelopmentSnapshot $project] ne [dict get $attached snapshot]} {error {GUI attachment source, Session lifetime or private fixture changed; reattach explicitly}}
    set operation [dict get $request operation]
    set shapes [dict create open {} status {} close {} capture {} capture_verify {capture_id} capture_preview {capture_id} click {component} choice {component value} text {component value} tab {component} pointer {component x y phase} plot_pointer {component x y} key {component key} property {component field value} properties_commit {component} properties_close {component}]
    dict set shapes label {component field value};dict set shapes label_apply component;dict set shapes label_close component
    dict set shapes wire_route {component command}
    if {$operation eq {wire_route} && [dict exists $request command] && [dict get $request command] eq {select}} {dict set shapes wire_route {component command index}}
    dict set shapes resize {width height}
    dict set shapes workspace_open {workspace_id}
    dict set shapes workspace_save {}
    dict set shapes workspace_review {workspace_id}
    dict set shapes workspace_upgrade {review_id}
    if {$operation eq {plot_pointer} && [dict exists $request phase]} {dict set shapes plot_pointer {component x y phase}}
    if {$operation eq {capture} && [dict exists $request component] && [dict exists $request dialog]} {dict set shapes capture {component dialog}}
    if {![dict exists $shapes $operation] || [lsort [dict keys $request]] ne [lsort [concat {operation request_id connection snapshot} [dict get $shapes $operation]]]} {error {Unknown or unbounded GUI action}}
    foreach key {component value field key phase command} {if {[dict exists $request $key] && ([string bytelength [dict get $request $key]]>4096 || [string first \x00 [dict get $request $key]]>=0)} {error {GUI action text exceeds bounds}}}
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
            click {
                if {$type eq {action}} {
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
            choice {if {$type ni {choice combobox dataset_selector}} {error {Choice requires a declared native selector}};_viewerDevelopmentGuiChoose $widget.entry [dict get $request value] $w}
            text {if {$type ni {entry field}} {error {Text requires a declared field}};_viewerDevelopmentGuiType $widget.entry [dict get $request value]}
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
                set captureWindow [_viewerDevelopmentGuiOwnedDialog $w $id [dict get $request dialog]]
            }
            key {
                set key [dict get $request key]
                if {$type eq {plot}} {
                    if {$key ne {Escape}} {error {Declared Plot keyboard input permits Escape only}}
                    set target $widget.plot
                    if {![winfo exists $target] || ![winfo ismapped $target]} {error {Bind and show the declared Plot before clearing its source cursor}}
                } elseif {$type eq {native2d} && [dict exists [dict get $component properties] diagram_catalog]} {
                    if {$key ni {Escape Delete BackSpace r w j p f ctrl+z ctrl+y}} {error {Key is outside the native schematic contract}}
                    set target $widget.diagram.canvas
                    if {![winfo ismapped $target]} {error {Select the schematic tab before keyboard input}}
                } else {error {Keyboard input requires a declared bound Plot or diagram viewport}}
                raise $w;exec xdotool windowfocus --sync [winfo id $w];update
                set x [expr {[winfo rootx $target]+[winfo width $target]/2}];set y [expr {[winfo rooty $target]+[winfo height $target]/2}]
                if {[winfo containing -displayof $target $x $y] ne $target} {error {Declared keyboard viewport is clipped or occluded}}
                focus -force $target;exec xdotool key --clearmodifiers $key;update
            }
            pointer - property - properties_commit - properties_close - wire_route - label - label_apply - label_close {
                if {$type ne {native2d} || ![dict exists [dict get $component properties] diagram_catalog]} {error {Schematic input requires a declared diagram viewport}}
                set viewport $widget.diagram;set canvas $viewport.canvas
                if {![winfo ismapped $canvas]} {error {Select the schematic tab before pointer input}}
                if {$operation eq {pointer}} {
                    foreach key {x y} {set v [uiFieldNormalize {type number min -1000000 max 1000000} [dict get $request $key]];dict set request $key $v}
                    set phase [dict get $request phase]
                    if {$phase ni {click double press move release}} {error {Unsupported pointer phase}}
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
        if {![info exists captureWindow]} {set captureWindow $w}
        set path [file join [_viewerDevelopmentGuiFolder $project] capture-[dict get $request request_id].png]
        raise $captureWindow;update idletasks
        set channel [open [list | import -screen -window [wm frame $captureWindow] png:-] rb]
        try {set bytes [read $channel 33554433]} finally {close $channel}
        if {[string length $bytes]>33554432} {error {Native capture exceeds32MiB}}
        resourceLifecycleWriteBytes $path $bytes
        dict set result screenshot $path;dict set result screenshot_sha256 [sha256File $path]
        dict set result geometry [winfo geometry $w]
        if {$captureWindow ne $w} {dict set result geometry [winfo geometry $captureWindow];dict set result capture_target [dict get $request dialog]}
        set captures [datasetPublicationV2DictDefault [dict get $::GX::ViewerDevelopment::guiTests $project] captures {}]
        if {[dict size $captures]>=128} {dict unset captures [lindex [dict keys $captures] 0]}
        dict set captures [dict get $request request_id] [dict create operation capture source_snapshot [dict get $attached snapshot] screenshot $path screenshot_sha256 [dict get $result screenshot_sha256] session $::GX::currentSession geometry [dict get $result geometry]]
        dict set ::GX::ViewerDevelopment::guiTests $project captures $captures
    }
    return $result
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
