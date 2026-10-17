# SPDX-License-Identifier: GPL-3.0-or-later
# Configuration owns command schemas and effective keys. Window adapters hold
# callbacks only; all persisted values use the existing scoped Configuration API.
namespace eval ::GX::ViewerCommands {
    variable catalogs {}
    variable windows {}
}

proc ::GX::viewerShortcutNormalize {value} {
    set value [string trim $value]
    if {$value eq {}} {return {}}
    set parts [split $value +];set key [lindex $parts end];set modifiers [lrange $parts 0 end-1]
    foreach modifier $modifiers {
        if {$modifier ni {Ctrl Shift}} {error {Use Ctrl and/or Shift; Alt and platform combinations are reserved.}}
    }
    if {[regexp {^[A-Z]$} $key]} {lappend modifiers Shift;set key [string tolower $key]}
    if {![regexp {^([a-z0-9]|Delete|F([2-9]|1[0-2]))$} $key]} {
        error {Use a letter/digit, Delete or F2–F12. Editing/navigation keys, F1 and OS combinations are reserved.}
    }
    set normalized {}
    foreach modifier {Ctrl Shift} {if {$modifier in $modifiers} {lappend normalized $modifier}}
    lappend normalized $key;set normalized [join $normalized +]
    if {$normalized in {Ctrl+a Ctrl+c Ctrl+x Ctrl+v Ctrl+Shift+a Ctrl+Shift+c Ctrl+Shift+x Ctrl+Shift+v Ctrl+q Ctrl+w}} {
        error {That shortcut is reserved for standard text, clipboard or application operations.}
    }
    return $normalized
}

proc ::GX::viewerCommandCatalogRegister {module commands {configurationId {}} {moduleKey shortcuts}} {
    variable ::GX::ViewerCommands::catalogs
    if {![regexp {^[a-z][a-zA-Z0-9_.-]*$} $module] || [catch {dict size $commands}] || $commands eq {}} {error {Invalid Viewer command catalog}}
    if {$configurationId eq {}} {set configurationId module.$module.configuration.$moduleKey}
    set normalized {}
    dict for {id descriptor} $commands {
        if {![regexp {^[a-z][a-zA-Z0-9_.-]*$} $id] || ![dict exists $descriptor label]} {error {Commands require stable IDs and labels}}
        dict set descriptor default [viewerShortcutNormalize [datasetPublicationV2DictDefault $descriptor default {}]]
        dict set descriptor scope [datasetPublicationV2DictDefault $descriptor scope viewer]
        dict set normalized $id $descriptor
    }
    set previous [datasetPublicationV2DictDefault $catalogs $module {}]
    dict set catalogs $module [dict create commands $normalized field $configurationId]
    try {
        viewerShortcutsValidate $module {}
        configurationRegister $configurationId [dict create group Modules label {Command shortcuts} type string default {} scope module \
            module_id $module module_key $moduleKey module_type string scopes {user session} application immediate \
            validator [list ::GX::viewerShortcutsValidate $module] structured_fields [list ::GX::viewerShortcutFields $module] \
            description {Scoped Viewer command keys; empty disables a key. Changes update menus and bindings together.}]
    } on error {message options} {
        if {$previous eq {}} {dict unset catalogs $module} else {dict set catalogs $module $previous}
        return -options $options $message
    }
    return $configurationId
}

proc ::GX::viewerCommandCatalog {module} {
    return [dict get $::GX::ViewerCommands::catalogs $module commands]
}
proc ::GX::viewerShortcutsValidate {module overrides} {
    if {[catch {dict size $overrides}]} {error {Shortcut settings must be a command-to-key dictionary}}
    set commands [viewerCommandCatalog $module];set used {};set result {}
    foreach id [dict keys $overrides] {if {![dict exists $commands $id]} {error "Unknown Viewer command '$id'"}}
    dict for {id descriptor} $commands {
        set value [viewerShortcutNormalize [datasetPublicationV2DictDefault $overrides $id [dict get $descriptor default]]]
        set scope [dict get $descriptor scope]
        if {$value ne {} && [dict exists $used $scope $value]} {error "Shortcut $value conflicts in scope $scope: [dict get $used $scope $value] and $id. No bindings changed."}
        if {$value ne {}} {dict set used $scope $value $id}
        dict set result $id $value
    }
    return $result
}
proc ::GX::viewerShortcutFields {module} {
    set fields {}
    dict for {id descriptor} [viewerCommandCatalog $module] {
        dict set fields $id [dict create type string label "[dict get $descriptor label] ($id)" default [dict get $descriptor default]]
    }
    return $fields
}

proc ::GX::viewerCommandsAttach {window module handlers {guard {}} {widgets {}}} {
    variable ::GX::ViewerCommands::windows
    if {![winfo exists $window]} {error {Viewer window does not exist}}
    set catalog [viewerCommandCatalog $module]
    foreach id [dict keys $handlers] {
        if {![dict exists $catalog $id] || ![dict exists $handlers $id command]} {error "Invalid Viewer handler '$id'"}
    }
    viewerCommandsDetach $window
    set field [dict get $::GX::ViewerCommands::catalogs $module field]
    set bindings [viewerShortcutsValidate $module [dict get [configurationResolve $field] effective]]
    set tag GXViewerCommands$window
    set token {};catch {set token [interactiveDocumentSessionToken]}
    dict set windows $window [dict create module $module handlers $handlers guard $guard widgets $widgets bindings $bindings \
        tag $tag menus {} session_token $token subscription [configurationSubscribe [list ::GX::_viewerCommandsChanged $window]]]
    bind $tag <KeyPress> [format {if {[::GX::viewerCommandKey %s %%W %%K %%s]} {break}} [list $window]]
    bind $window <Destroy> +[list ::GX::_viewerCommandsDestroyed $window %W]
    bind $window <Map> +[list ::GX::_viewerCommandsMapped $window %W]
    _viewerCommandsInstallTags $window
    return $window
}
proc ::GX::_viewerCommandsDescendants {window} {
    set result [list $window]
    foreach child [winfo children $window] {
        if {[winfo toplevel $child] eq [winfo toplevel $window]} {set result [concat $result [_viewerCommandsDescendants $child]]}
    }
    return $result
}
proc ::GX::_viewerCommandsInstallTags {window} {
    set adapter [dict get $::GX::ViewerCommands::windows $window]
    set widgets [dict get $adapter widgets]
    if {$widgets eq {}} {set widgets [_viewerCommandsDescendants $window]}
    foreach widget $widgets {
        if {![winfo exists $widget]} continue
        set tags [bindtags $widget];set tag [dict get $adapter tag]
        if {$tag ni $tags} {bindtags $widget [linsert $tags 0 $tag]}
    }
}
proc ::GX::_viewerCommandsMapped {window mapped} {
    if {[dict exists $::GX::ViewerCommands::windows $window] && [winfo exists $mapped]} {_viewerCommandsInstallTags $window}
}
proc ::GX::_viewerCommandsDestroyed {window destroyed} {if {$window eq $destroyed} {viewerCommandsDetach $window}}
proc ::GX::viewerCommandsDetach {window} {
    variable ::GX::ViewerCommands::windows
    if {![dict exists $windows $window]} return
    set adapter [dict get $windows $window];set tag [dict get $adapter tag]
    configurationUnsubscribe [dict get $adapter subscription]
    if {[winfo exists $window]} {
        foreach widget [_viewerCommandsDescendants $window] {
            set tags [bindtags $widget];set index [lsearch -exact $tags $tag]
            if {$index>=0} {bindtags $widget [lreplace $tags $index $index]}
        }
    }
    bind $tag <KeyPress> {}
    dict unset windows $window
}
proc ::GX::viewerCommandEnabled {window id} {
    if {![dict exists $::GX::ViewerCommands::windows $window handlers $id] || ![winfo exists $window]} {return 0}
    set adapter [dict get $::GX::ViewerCommands::windows $window]
    if {[dict get $adapter session_token] ne {}} {
        if {[catch {interactiveDocumentSessionToken} token] || $token ne [dict get $adapter session_token]} {return 0}
    }
    foreach predicate [list [dict get $adapter guard] [datasetPublicationV2DictDefault [dict get $adapter handlers $id] enabled {}]] {
        if {$predicate ne {} && ([catch {uplevel #0 $predicate} enabled] || !$enabled)} {return 0}
    }
    return 1
}
proc ::GX::viewerCommandApplicable {window id} {
    if {![dict exists $::GX::ViewerCommands::windows $window handlers $id]} {return 0}
    set callback [datasetPublicationV2DictDefault [dict get $::GX::ViewerCommands::windows $window handlers $id] applicable {}]
    return [expr {$callback eq {} || (![catch {uplevel #0 $callback} result] && $result)}]
}
proc ::GX::viewerCommandToolbarCreate {window frame {commandIds {}}} {
    set module [dict get $::GX::ViewerCommands::windows $window module]
    if {![winfo exists $frame]} {ttk::frame $frame}
    set buttons {};set i 0
    dict for {id descriptor} [viewerCommandCatalog $module] {
        if {$commandIds ne {} && $id ni $commandIds} continue
        set widget $frame.command[incr i]
        set label [datasetPublicationV2DictDefault $descriptor toolbar_label [dict get $descriptor label]]
        ttk::button $widget -text $label -command [list ::GX::viewerCommandInvoke $window $id]
        if {[dict exists $descriptor toolbar_label]} {$widget configure -width [expr {max(2,[string length $label])}]}
        dict set buttons $id $widget
        bind $widget <Enter> [list ::GX::native2DViewportTooltipShow $widget [datasetPublicationV2DictDefault $descriptor tooltip [dict get $descriptor label]]]
        bind $widget <Leave> {catch {destroy .gxViewportTip}}
    }
    dict set ::GX::ViewerCommands::windows $window toolbar [dict create frame $frame buttons $buttons]
    bind $frame <Configure> [list ::GX::viewerCommandToolbarRefresh $window]
    viewerCommandToolbarRefresh $window
    return $frame
}
proc ::GX::viewerCommandToolbarRefresh {window} {
    if {![dict exists $::GX::ViewerCommands::windows $window toolbar]} return
    set toolbar [dict get $::GX::ViewerCommands::windows $window toolbar];set frame [dict get $toolbar frame]
    if {![winfo exists $frame]} return
    set visible {}
    dict for {id widget} [dict get $toolbar buttons] {
        if {[viewerCommandApplicable $window $id]} {lappend visible $widget;$widget state [expr {[viewerCommandEnabled $window $id]?"!disabled":"disabled"}]} else {pack forget $widget;grid remove $widget}
    }
    if {$visible ne {}} {
        set width [winfo width $frame];set layout [uiFieldControlsLayout $frame $width $visible];set height [dict get $layout height]
        if {[datasetPublicationV2DictDefault $toolbar layout_width 0]==$width} {set height [expr {max($height,[datasetPublicationV2DictDefault $toolbar layout_height 0])}]}
        dict set ::GX::ViewerCommands::windows $window toolbar layout_width $width
        dict set ::GX::ViewerCommands::windows $window toolbar layout_height $height
        grid propagate $frame 0
        if {[$frame cget -height]!=$height} {$frame configure -height $height}
    }
    viewerCommandMenusRefresh $window
}
proc ::GX::viewerCommandInvoke {window id} {
    if {![viewerCommandApplicable $window $id] || ![viewerCommandEnabled $window $id]} {return 0}
    set adapter [dict get $::GX::ViewerCommands::windows $window]
    _datasetPrivateWithModule [dict get $adapter module] [list uplevel #0 [dict get $adapter handlers $id command]]
    return 1
}
proc ::GX::viewerCommandKey {window widget key state} {
    if {![dict exists $::GX::ViewerCommands::windows $window] || $state & 0x8 || $state & 0x40} {return 0}
    if {[winfo class $widget] in {Entry TEntry Text TCombobox Spinbox TSpinbox Listbox Menu}} {return 0}
    set chord {};if {$state & 0x4} {lappend chord Ctrl};if {$state & 0x1} {lappend chord Shift}
    if {[string length $key]==1} {set key [string tolower $key]}
    lappend chord $key;set chord [join $chord +]
    set adapter [dict get $::GX::ViewerCommands::windows $window]
    dict for {id binding} [dict get $adapter bindings] {
        if {$binding ne {} && $binding eq $chord && [dict exists $adapter handlers $id]} {
            set descriptor [dict get [viewerCommandCatalog [dict get $adapter module]] $id]
            if {[dict exists $descriptor context] && ![uplevel #0 [list {*}[dict get $descriptor context] $widget]]} continue
            # A matching disabled command still consumes its key, preventing a
            # lower legacy binding from bypassing the same enablement guard.
            viewerCommandInvoke $window $id
            return 1
        }
    }
    return 0
}
proc ::GX::viewerCommandAccelerator {window id} {
    set value [dict get $::GX::ViewerCommands::windows $window bindings $id]
    set parts [split $value +]
    if {[llength $parts] && [string length [lindex $parts end]]==1} {lset parts end [string toupper [lindex $parts end]]}
    return [join $parts +]
}
proc ::GX::viewerCommandMenuAdd {window menu id} {
    set module [dict get $::GX::ViewerCommands::windows $window module]
    $menu add command -label [dict get [viewerCommandCatalog $module] $id label] \
        -command [list ::GX::viewerCommandInvoke $window $id] -accelerator [viewerCommandAccelerator $window $id] \
        -state [expr {[viewerCommandEnabled $window $id] ? "normal" : "disabled"}]
    viewerCommandMenuTrack $window $menu [$menu index end] $id
}
proc ::GX::viewerCommandMenuTrack {window menu index id} {
    dict set ::GX::ViewerCommands::windows $window menus [list $menu $index] $id
    viewerCommandMenusRefresh $window
}
proc ::GX::viewerCommandMenusRefresh {window} {
    if {![dict exists $::GX::ViewerCommands::windows $window]} return
    dict for {entry id} [dict get $::GX::ViewerCommands::windows $window menus] {
        lassign $entry menu index
        if {![winfo exists $menu]} continue
        $menu entryconfigure $index -accelerator [viewerCommandAccelerator $window $id] \
            -state [expr {[viewerCommandEnabled $window $id] ? "normal" : "disabled"}]
    }
}
proc ::GX::_viewerCommandsChanged {window id} {
    if {![dict exists $::GX::ViewerCommands::windows $window] || ![winfo exists $window]} return
    set adapter [dict get $::GX::ViewerCommands::windows $window]
    # Session teardown can retire the field before the old window is destroyed.
    if {[dict get $adapter session_token] ne {} && ([catch {interactiveDocumentSessionToken} token] || $token ne [dict get $adapter session_token])} return
    if {![dict exists $::GX::ViewerCommands::catalogs [dict get $adapter module] field]} return
    set field [dict get $::GX::ViewerCommands::catalogs [dict get $adapter module] field]
    if {![dict exists [configurationFields] $field]} return
    if {$id ne {} && $id ne $field} return
    set bindings [viewerShortcutsValidate [dict get $adapter module] [dict get [configurationResolve $field] effective]]
    dict set ::GX::ViewerCommands::windows $window bindings $bindings
    viewerCommandMenusRefresh $window
}
