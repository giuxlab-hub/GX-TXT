# SPDX-License-Identifier: GPL-3.0-or-later
# Configuration owns command schemas and effective keys. Window adapters hold
# callbacks only; all persisted values use the existing scoped Configuration API.
namespace eval ::GX::ViewerCommands {
    variable catalogs {}
    variable windows {}
    variable checked
}

proc ::GX::viewerShortcutNormalize {value {clipboardOperation {}}} {
    if {$clipboardOperation ni {{} copy cut paste select_all}} {error {Unknown standard clipboard operation.}}
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
        set standard [dict get {copy Ctrl+c cut Ctrl+x paste Ctrl+v select_all Ctrl+a {} {}} $clipboardOperation]
        if {$normalized ne $standard} {error {That shortcut is reserved for standard text, clipboard or application operations.}}
    }
    return $normalized
}

proc ::GX::viewerCommandCatalogRegister {module commands {configurationId {}} {moduleKey shortcuts} {ownerModule {}}} {
    variable ::GX::ViewerCommands::catalogs
    if {![regexp {^[a-z][a-zA-Z0-9_.-]*$} $module] || [catch {dict size $commands}] || $commands eq {}} {error {Invalid Viewer command catalog}}
    if {$ownerModule eq {framework} && ![string match framework.* $module]} {error {Framework command catalogs require a framework.* logical identity.}}
    if {$ownerModule ni {{} framework} && [moduleField $ownerModule descriptor {}] eq {}} {error "Viewer command owner '$ownerModule' is not installed"}
    if {$ownerModule eq {}} {set ownerModule $module}
    if {$configurationId eq {}} {set configurationId module.$module.configuration.$moduleKey}
    set normalized {}
    dict for {id descriptor} $commands {
        if {![regexp {^[a-z][a-zA-Z0-9_.-]*$} $id] || ![dict exists $descriptor label]} {error {Commands require stable IDs and labels}}
        dict set descriptor default [viewerShortcutNormalize [datasetPublicationV2DictDefault $descriptor default {}] [datasetPublicationV2DictDefault $descriptor clipboard_operation {}]]
        dict set descriptor scope [datasetPublicationV2DictDefault $descriptor scope viewer]
        dict set normalized $id $descriptor
    }
    set previous [datasetPublicationV2DictDefault $catalogs $module {}]
    dict set catalogs $module [dict create commands $normalized field $configurationId owner_module $ownerModule module_key $moduleKey]
    try {
        viewerShortcutsValidate $module {}
        set fieldDescriptor [dict create group Modules label {Command shortcuts} type string default {} scope module \
            module_id $ownerModule module_key $moduleKey module_type string scopes {user session} application immediate \
            validator [list ::GX::viewerShortcutsValidate $module] structured_fields [list ::GX::viewerShortcutFields $module] \
            description {Scoped command keys; empty disables a key. Changes update menus and bindings together.}]
        if {$ownerModule eq {framework}} {set fieldDescriptor [dict remove $fieldDescriptor module_id module_key module_type];dict set fieldDescriptor scope user;dict set fieldDescriptor scopes user;dict set fieldDescriptor group General}
        configurationRegister $configurationId $fieldDescriptor
    } on error {message options} {
        if {$previous eq {}} {dict unset catalogs $module} else {dict set catalogs $module $previous}
        return -options $options $message
    }
    return $configurationId
}

proc ::GX::viewerCommandCatalog {module} {
    return [dict get $::GX::ViewerCommands::catalogs $module commands]
}
proc ::GX::viewerCommandSchemasRestore {} {
    dict for {module record} $::GX::ViewerCommands::catalogs {
        set owner [dict get $record owner_module]
        if {$owner ne {framework} && [moduleField $owner descriptor {}] eq {}} continue
        viewerCommandCatalogRegister $module [dict get $record commands] [dict get $record field] [datasetPublicationV2DictDefault $record module_key shortcuts] $owner
    }
}
proc ::GX::viewerShortcutsValidate {module overrides} {
    if {[catch {dict size $overrides}]} {error {Shortcut settings must be a command-to-key dictionary}}
    set commands [viewerCommandCatalog $module];set used {};set result {}
    foreach id [dict keys $overrides] {if {![dict exists $commands $id]} {error "Unknown Viewer command '$id'"}}
    dict for {id descriptor} $commands {
        set value [viewerShortcutNormalize [datasetPublicationV2DictDefault $overrides $id [dict get $descriptor default]] [datasetPublicationV2DictDefault $descriptor clipboard_operation {}]]
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

proc ::GX::viewerCommandBindingsResolve {module} {
    set field [dict get $::GX::ViewerCommands::catalogs $module field]
    set effective [dict get [configurationResolve $field] effective];set catalog [viewerCommandCatalog $module]
    set current {};set ignored {}
    dict for {id value} $effective {if {[dict exists $catalog $id]} {dict set current $id $value} else {lappend ignored $id}}
    # Preserve obsolete saved preferences, but do not bind commands removed by
    # a new module version or by editing a declarative design. Explicit editing
    # remains strict through viewerShortcutsValidate.
    return [dict create bindings [viewerShortcutsValidate $module $current] ignored $ignored]
}
proc ::GX::viewerCommandsAttach {window module handlers {guard {}} {widgets {}} {options {}}} {
    variable ::GX::ViewerCommands::windows
    if {![winfo exists $window]} {error {Viewer window does not exist}}
    set catalog [viewerCommandCatalog $module]
    foreach id [dict keys $handlers] {
        if {![dict exists $catalog $id] || ![dict exists $handlers $id command]} {error "Invalid Viewer handler '$id'"}
    }
    viewerCommandsDetach $window
    set field [dict get $::GX::ViewerCommands::catalogs $module field]
    set resolved [viewerCommandBindingsResolve $module];set bindings [dict get $resolved bindings]
    set tag GXViewerCommands$window
    foreach key [dict keys $options] {if {$key ne {session_scoped}} {error {Unknown Viewer command scope option.}}}
    set scoped [datasetPublicationV2DictDefault $options session_scoped 1]
    if {![string is boolean -strict $scoped]} {error {Viewer command Session scope must be boolean.}}
    set token {};if {$scoped} {catch {set token [interactiveDocumentSessionToken]}}
    dict set windows $window [dict create module $module owner_module [dict get $::GX::ViewerCommands::catalogs $module owner_module] handlers $handlers guard $guard widgets $widgets bindings $bindings \
        tag $tag menus {} obsolete_shortcut_ids [dict get $resolved ignored] session_token $token subscription [configurationSubscribe [list ::GX::_viewerCommandsChanged $window]]]
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
    array unset ::GX::ViewerCommands::checked $window,*
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
    set catalog [viewerCommandCatalog $module]
    set order [expr {$commandIds eq {}?[dict keys $catalog]:$commandIds}]
    foreach id $order {
        if {![dict exists $catalog $id]} {error "Unknown toolbar command '$id'"}
        set descriptor [dict get $catalog $id]
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
proc ::GX::viewerCommandWidgetsAttach {window mapping} {
    if {![dict exists $::GX::ViewerCommands::windows $window]} {error {Attach the Viewer command host first.}}
    dict for {id widgets} $mapping {
        if {![dict exists $::GX::ViewerCommands::windows $window handlers $id]} {error "Unknown Viewer action '$id'."}
        foreach widget $widgets {if {![winfo exists $widget] || ($widget ne $window && [string first "$window." $widget]!=0)} {error {Command widgets must belong to their Viewer.}}}
    }
    dict set ::GX::ViewerCommands::windows $window command_widgets $mapping
    viewerCommandWidgetsRefresh $window
}
proc ::GX::viewerCommandWidgetsRefresh {window} {
    if {![dict exists $::GX::ViewerCommands::windows $window command_widgets]} return
    dict for {id widgets} [dict get $::GX::ViewerCommands::windows $window command_widgets] {
        set active [expr {[viewerCommandApplicable $window $id] && [viewerCommandEnabled $window $id]}]
        foreach widget $widgets {if {[winfo exists $widget]} {$widget state [expr {$active ? {!disabled} : {disabled}}]}}
    }
}
proc ::GX::viewerCommandToolbarStatesRefresh {window} {
    if {![dict exists $::GX::ViewerCommands::windows $window toolbar]} return
    dict for {id widget} [dict get $::GX::ViewerCommands::windows $window toolbar buttons] {
        if {[winfo exists $widget]} {
            set active [expr {[viewerCommandApplicable $window $id] && [viewerCommandEnabled $window $id]}]
            $widget state [expr {$active ? {!disabled} : {disabled}}]
        }
    }
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
    set observe [expr {[dict exists $::GX::ViewerGui::instances $window mode] && [dict get $::GX::ViewerGui::instances $window mode] eq {observed}}]
    if {$observe} {set correlation [viewerGuiTraceEmit $window $id invoke {status started}];set started [clock microseconds]}
    try {
        if {[dict get $adapter owner_module] eq {framework}} {set result [uplevel #0 [dict get $adapter handlers $id command]]} else {set result [_datasetPrivateWithModule [dict get $adapter owner_module] [list uplevel #0 [dict get $adapter handlers $id command]]]}
    } on error {message options} {
        if {$observe} {viewerGuiTraceEmit $window $id result [dict create status failed message $message elapsed_us [expr {[clock microseconds]-$started}]] $correlation}
        return -options $options $message
    }
    if {$observe} {viewerGuiTraceEmit $window $id result [dict create status [expr {$result eq {0} ? {failed} : {completed}}] elapsed_us [expr {[clock microseconds]-$started}]] $correlation}
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
    set kind command;set options {}
    if {[dict exists $::GX::ViewerCommands::windows $window handlers $id checked]} {
        set kind checkbutton
        set options [list -variable ::GX::ViewerCommands::checked($window,$id)]
    }
    $menu add $kind {*}$options -label [dict get [viewerCommandCatalog $module] $id label] \
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
    # History and field changes already refresh this owner. Update mounted
    # toolbar states too, without triggering another layout/menu refresh.
    viewerCommandToolbarStatesRefresh $window
    dict for {entry id} [dict get $::GX::ViewerCommands::windows $window menus] {
        lassign $entry menu index
        if {![winfo exists $menu]} continue
        if {[dict exists $::GX::ViewerCommands::windows $window handlers $id checked]} {
            set checked 0
            catch {set checked [uplevel #0 [dict get $::GX::ViewerCommands::windows $window handlers $id checked]]}
            set ::GX::ViewerCommands::checked($window,$id) [expr {[string is boolean -strict $checked] && $checked}]
        }
        $menu entryconfigure $index -accelerator [viewerCommandAccelerator $window $id] \
            -state [expr {[viewerCommandApplicable $window $id] && [viewerCommandEnabled $window $id] ? "normal" : "disabled"}]
        if {[dict exists $::GX::ViewerCommands::windows $window menu_icon_bindings $entry]} {
            set icon [dict get $::GX::ViewerCommands::windows $window menu_icon_bindings $entry]
            uiFieldMenuIconApply $menu $index [dict get $icon properties] [dict get $icon asset] [dict get $icon catalog]
        }
    }
    viewerCommandWidgetsRefresh $window
}
proc ::GX::_viewerCommandsChanged {window id} {
    if {![dict exists $::GX::ViewerCommands::windows $window] || ![winfo exists $window]} return
    set adapter [dict get $::GX::ViewerCommands::windows $window]
    viewerCommandWidgetsRefresh $window
    # Session teardown can retire the field before the old window is destroyed.
    if {[dict get $adapter session_token] ne {} && ([catch {interactiveDocumentSessionToken} token] || $token ne [dict get $adapter session_token])} return
    if {![dict exists $::GX::ViewerCommands::catalogs [dict get $adapter module] field]} return
    set field [dict get $::GX::ViewerCommands::catalogs [dict get $adapter module] field]
    if {![dict exists [configurationFields] $field]} return
    if {$id ne {} && $id ne $field} return
    set resolved [viewerCommandBindingsResolve [dict get $adapter module]];set bindings [dict get $resolved bindings]
    dict set ::GX::ViewerCommands::windows $window obsolete_shortcut_ids [dict get $resolved ignored]
    dict set ::GX::ViewerCommands::windows $window bindings $bindings
    viewerCommandMenusRefresh $window
}
