# SPDX-License-Identifier: GPL-3.0-or-later
# Declared presentation bindings; the existing Viewer/Layout/Workspace owners
# retain widgets, scientific handles, native frames and persisted visibility.
proc ::GX::viewerGuiDesignVisibilityCommands {design} {
    set result {}
    foreach component [dict get $design components] {
        set p [dict get $component properties];set bindings {}
        if {[dict get $component type] eq {action} && [dict exists $p component_visibility]} {dict set bindings [dict get $p action] [dict get $p component_visibility]}
        if {[dict exists $p visibility_commands]} {set bindings [dict merge $bindings [dict get $p visibility_commands]]}
        dict for {command target} $bindings {
            if {[dict exists $result $command] && [dict get $result $command] ne $target} {error {One visibility command cannot address different components}}
            dict set result $command $target
        }
    }
    return $result
}
proc ::GX::_viewerGuiVisibilityDesignValidate {design} {
    set ids {};foreach component [dict get $design components] {dict set ids [dict get $component id] $component}
    set defaults {}
    foreach component [dict get $design components] {
        set p [dict get $component properties];set type [dict get $component type]
        if {[dict exists $p component_visibility]} {
            if {$type ni {toggle checkbutton action}} {error {Component visibility belongs to an action or boolean control}}
            if {$type in {toggle checkbutton} && (![dict exists $p default] || ![string is boolean -strict [dict get $p default]] || [dict exists $p change_action])} {error {A visibility toggle requires a boolean default and no authored change callback}}
            set target [dict get $p component_visibility]
            if {![dict exists $ids $target] || [dict get $ids $target type] in {menu context_menu command_toolbar history workspace help}} {error {Visibility requires a declared content component}}
            if {$type in {toggle checkbutton}} {
                set value [expr {!![dict get $p default]}]
                if {[dict exists $defaults $target] && [dict get $defaults $target]!=$value} {error {Boolean controls for one visibility target require the same default}}
                dict set defaults $target $value
            }
        }
        if {[dict exists $p visibility_commands]} {
            if {$type ni {menu context_menu command_toolbar}} {error {Checked visibility commands belong to a declared command surface}}
            dict for {command target} [dict get $p visibility_commands] {
                if {$command ni [dict get $p actions] || ![dict exists $ids $target] || [dict get $ids $target type] in {menu context_menu command_toolbar history workspace help}} {error {Checked command must name its own declared action and a content component}}
            }
        }
    }
    dict for {command target} [viewerGuiDesignVisibilityCommands $design] {
        if {$command in {undo redo fit zoom_in zoom_out} || ![dict exists $design handlers $command] || [dict get $design handlers $command effect] ne {presentation}} {error {Visibility commands require a distinct declared presentation handler}}
    }
}
proc ::GX::viewerGuiDesignComponentVisibleGet {window component} {
    if {![viewerGuiDesignGuard $window]} {error {Visibility belongs to a previous Session lifetime}}
    viewerGuiDesignComponent $window $component
    return [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] component_visibility {}] $component 1]
}
proc ::GX::viewerGuiDesignVisibilityChecked {window command} {
    if {![viewerGuiDesignGuard $window]} {return 0}
    set targets [viewerGuiDesignVisibilityCommands [dict get $::GX::ViewerGui::instances $window design]]
    if {![dict exists $targets $command]} {error {Unknown declared visibility command}}
    return [viewerGuiDesignComponentVisibleGet $window [dict get $targets $command]]
}
proc ::GX::_viewerGuiVisibilitySync {window} {
    set prior [dict get $::GX::ViewerGui::instances $window restoring]
    dict set ::GX::ViewerGui::instances $window restoring 1
    try {
        foreach component [dict get $::GX::ViewerGui::instances $window design components] {
            if {[dict get $component type] ni {toggle checkbutton} || ![dict exists $component properties component_visibility]} continue
            set id [dict get $component id];set value [viewerGuiDesignComponentVisibleGet $window [dict get $component properties component_visibility]]
            viewerGuiDesignValueSet $window $id $value
            dict set ::GX::ViewerGui::instances $window committed_values $id $value
        }
    } finally {dict set ::GX::ViewerGui::instances $window restoring $prior}
    viewerCommandMenusRefresh $window
}
proc ::GX::_viewerGuiVisibilityInitialize {window} {
    set defaults [_viewerGuiVisibilityDefaults [dict get $::GX::ViewerGui::instances $window design]]
    # Capture original sibling ordering BEFORE any declared target is hidden.
    dict for {target value} $defaults {
        set widget [dict get $::GX::ViewerGui::instances $window widgets $target]
        dict set ::GX::ViewerGui::instances $window visibility_layouts $target [_viewerGuiVisibilityLayout $widget]
        dict set ::GX::ViewerGui::instances $window component_visibility $target 1
    }
    dict for {target value} $defaults {viewerGuiDesignComponentVisible $window $target $value}
    _viewerGuiVisibilitySync $window
}
proc ::GX::_viewerGuiVisibilityDefaults {design} {
    set defaults {};dict for {command target} [viewerGuiDesignVisibilityCommands $design] {dict set defaults $target 1}
    foreach component [dict get $design components] {if {[dict get $component type] in {toggle checkbutton} && [dict exists $component properties component_visibility]} {dict set defaults [dict get $component properties component_visibility] [expr {!![dict get $component properties default]}]}}
    return $defaults
}
proc ::GX::_viewerGuiVisibilityLayout {widget} {
    set manager [winfo manager $widget]
    switch -- $manager {
        pack {
            set options [pack info $widget];set parent [dict get $options -in];set siblings [pack slaves $parent]
            return [dict create manager pack options $options following [lrange $siblings [expr {[lsearch -exact $siblings $widget]+1}] end]]
        }
        panedwindow - ttk::panedwindow {
            set parent [winfo parent $widget];set panes [$parent panes]
            return [dict create manager $manager following [lrange $panes [expr {[lsearch -exact $panes $widget]+1}] end] options [$parent pane $widget]]
        }
        grid - notebook {return [dict create manager $manager]}
        default {error {Visibility target has no supported declared layout manager}}
    }
}
proc ::GX::_viewerGuiVisibilityRestore {window desired} {
    set prior [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] component_visibility {}]
    set defaults [_viewerGuiVisibilityDefaults [dict get $::GX::ViewerGui::instances $window design]]
    dict for {id visible} $prior {
        if {![dict exists $desired $id] && [dict exists $::GX::ViewerGui::instances $window widgets $id]} {viewerGuiDesignComponentVisible $window $id [datasetPublicationV2DictDefault $defaults $id 1]}
    }
    dict for {id visible} $desired {if {[dict exists $::GX::ViewerGui::instances $window widgets $id]} {viewerGuiDesignComponentVisible $window $id $visible}}
}
proc ::GX::_viewerGuiComponentVisibilityApply {window component visible} {
    if {![viewerGuiDesignGuard $window] || [dict get $::GX::ViewerGui::instances $window mode] eq {observed}} {error {This Viewer cannot change presentation visibility}}
    set definition [viewerGuiDesignComponent $window $component]
    if {[dict get $definition type] in {menu context_menu command_toolbar history workspace help}} {error {Select a declared content component}}
    if {![string is boolean -strict $visible]} {error {Visibility must be boolean}}
    set visible [expr {!!$visible}]
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component]
    set prior [viewerGuiDesignComponentVisibleGet $window $component]
    if {$visible==$prior && [dict exists $::GX::ViewerGui::instances $window component_visibility $component]} {return $visible}
    set manager [winfo manager $widget]
    set saved [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] visibility_layouts {}] $component {}]
    if {$saved ne {}} {set manager [dict get $saved manager]}
    switch -- $manager {
        grid {set saved [dict create manager grid];if {$visible} {grid $widget} else {grid remove $widget}}
        pack {
            if {$saved eq {}} {
                set options [pack info $widget];set parent [dict get $options -in];set siblings [pack slaves $parent];set index [lsearch -exact $siblings $widget]
                set saved [dict create manager pack options $options following [lrange $siblings [expr {$index+1}] end]]
            }
            if {$visible} {
                set options [dict get $saved options]
                foreach next [dict get $saved following] {if {[winfo exists $next] && [winfo manager $next] eq {pack}} {dict set options -before $next;break}}
                pack $widget {*}$options
            } else {pack forget $widget}
        }
        notebook {
            set saved [dict create manager notebook]
            set parent [winfo parent $widget]
            if {$visible} {$parent add $widget} else {$parent hide $widget}
        }
        panedwindow - ttk::panedwindow {
            set parent [winfo parent $widget]
            if {$saved eq {}} {set panes [$parent panes];set saved [dict create manager $manager following [lrange $panes [expr {[lsearch -exact $panes $widget]+1}] end] options [$parent pane $widget]]}
            if {$visible} {
                set position end;foreach next [dict get $saved following] {if {$next in [$parent panes]} {set position $next;break}}
                $parent insert $position $widget {*}[dict get $saved options]
            } else {$parent forget $widget}
        }
        default {error {Component is not managed by a supported grid, pack, notebook or split-pane owner}}
    }
    if {$saved ne {}} {dict set ::GX::ViewerGui::instances $window visibility_layouts $component $saved}
    if {!$visible} {set focused [focus];if {$focused eq $widget || [string match "$widget.*" $focused]} {focus $window}}
    dict set ::GX::ViewerGui::instances $window component_visibility $component $visible
    _viewerGuiVisibilitySync $window
    return $visible
}
