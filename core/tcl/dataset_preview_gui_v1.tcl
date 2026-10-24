# SPDX-License-Identifier: GPL-3.0-or-later
# Optional PREVIEW_COMPONENT_GUI_API_v1 host adapter. UI Field, shared icons,
# ViewportHost and Plot retain widget, asset and scientific presentation authority.
namespace eval ::GX::PreviewGui {variable mounts {};variable serial 0;variable values}
proc ::GX::datasetPreviewGuiApiInfo {} {
    return [dict create api_id PREVIEW_COMPONENT_GUI_API_v1 api_version 1 host_only 1 opt_in preview_provider.gui_api_version=1 tab_kind gui callbacks {guiMount guiDispose} operations {datasetPreviewGuiContext datasetPreviewGuiControlCreate datasetPreviewGuiControlGet datasetPreviewGuiControlSet datasetPreviewGuiControlConfigure datasetPreviewGuiControlState datasetPreviewGuiPanelCreate datasetPreviewGuiPanelShow datasetPreviewGuiView} owners {UI_FIELD_API_v1 VIEWER_GUI_HOST_API_v1 NATIVE2D_VIEWPORT_HOST_v1 PLOT_DATASET_API_v4}]
}
proc ::GX::_datasetPreviewGuiRequire {host} {
    variable ::GX::PreviewGui::mounts
    if {![dict exists $mounts $host]} {error {Preview GUI mount has closed}}
    set record [dict get $mounts $host]
    set id [dict get $record module]
    if {[catch {
        set root [dict get $record root]
        if {![winfo exists $root] || [winfo id $root] ne [dict get $record window_id] || ![moduleIsEnabled $id] || [dict exists $::GX::pluginRuntimePending $id]} {error stale}
        if {![_datasetPreviewProviderContextCurrent [dict get $record dataset] [dict get $record context] [dict get $record identity]]} {error stale}
        if {[sha256File [moduleField $id descriptor]] ne [dict get $record descriptor_sha256]} {error stale}
        if {![uplevel #0 [dict get $record guard]]} {error stale}
    }]} {
        _datasetPreviewGuiDispose $host {Dataset, Session, package or Preview changed}
        error {Preview GUI belongs to a previous or disabled component; refresh Preview}
    }
    return $record
}
proc ::GX::datasetPreviewGuiContext {host} {return [dict get [_datasetPreviewGuiRequire $host] context]}
proc ::GX::_datasetPreviewGuiMount {module dataset parent representation plot guard} {
    variable ::GX::PreviewGui::mounts;variable ::GX::PreviewGui::serial
    if {[llength [info commands ::tk]]==0 || [_datasetPreviewNativeWorker]} {error {Preview GUI requires the Tk host, never the native worker}}
    set declaration [_datasetPreviewProviderDescriptor $module]
    if {[dict get $declaration gui_api_version]!=1 || ![moduleIsEnabled $module]} {error {Preview component has not opted into the GUI API}}
    modulePublicApiActivate $module PREVIEW_COMPONENT_GUI_API_v1
    set ns [descriptorValue [moduleField $module dict] public_api.PREVIEW_COMPONENT_GUI_API_v1 namespace {}]
    foreach command {guiMount guiDispose} {if {![llength [info commands ${ns}::$command]]} {error "Preview GUI requires ${ns}::$command"}}
    if {[dict size $mounts]>=128} {error {Too many live Preview GUI panes}}
    set host preview-gui#[incr serial]
    set context [_datasetPreviewProviderContext $dataset $representation]
    if {$plot ne {} && [catch {::GX::PlotDatasetAPIv4::widgetReceipt $plot}]} {set plot {}}
    dict set context gui_api PREVIEW_COMPONENT_GUI_API_v1
    dict set context component_id $module
    dict set context viewport_available [expr {$plot ne {}}]
    dict set mounts $host [dict create module $module dataset $dataset root $parent window_id [winfo id $parent] context $context identity [datasetViewerScientificIdentity $dataset] descriptor_sha256 [sha256File [moduleField $module descriptor]] guard $guard namespace $ns plot $plot controls {} panels {}]
    bind $parent <Destroy> +[list ::GX::_datasetPreviewGuiDestroyed $host $parent %W]
    set trace [list ::GX::_datasetPreviewGuiChanged $host]
    trace add variable ::GX::currentSession {write unset} $trace
    dict set mounts $host session_trace $trace
    dict set mounts $host subscription [datasetCatalogSubscribe [list ::GX::_datasetPreviewGuiChanged $host]]
    grid columnconfigure $parent 0 -weight 1
    try {
        _datasetPreviewGuiRequire $host
        _datasetPrivateWithModule $module [list ${ns}::guiMount $host $context]
        _datasetPreviewGuiRequire $host
    } on error {message options} {
        _datasetPreviewGuiDispose $host {Mount failed}
        return -options $options $message
    }
    return $host
}
proc ::GX::_datasetPreviewGuiDestroyed {host parent actual} {
    if {$parent eq $actual} {_datasetPreviewGuiDispose $host {Preview pane closed or replaced}}
}
proc ::GX::_datasetPreviewGuiChanged {host args} {catch {_datasetPreviewGuiRequire $host}}
proc ::GX::datasetPreviewGuiRefresh {} {
    foreach host [dict keys $::GX::PreviewGui::mounts] {_datasetPreviewGuiChanged $host}
}
proc ::GX::datasetPreviewGuiRelease {} {
    foreach host [dict keys $::GX::PreviewGui::mounts] {_datasetPreviewGuiDispose $host {Preview closed or replaced}}
}
proc ::GX::_datasetPreviewGuiDispose {host reason} {
    variable ::GX::PreviewGui::mounts
    if {![dict exists $mounts $host]} return
    set record [dict get $mounts $host]
    dict unset mounts $host
    if {[dict exists $record subscription]} {datasetCatalogUnsubscribe [dict get $record subscription]}
    if {[dict exists $record session_trace]} {trace remove variable ::GX::currentSession {write unset} [dict get $record session_trace]}
    # GUI disposal is notification, not another authority to publish data or
    # resurrect widgets. Invalidate the handle before calling module code.
    set command [dict get $record namespace]::guiDispose
    if {[llength [info commands $command]] && [catch {_datasetPrivateWithModule [dict get $record module] [list $command $host [dict get $record context] $reason]} message]} {
        puts stderr "Preview GUI disposal: $message"
    }
    dict for {id panel} [dict get $record panels] {native2DViewportPanelDestroy [dict get $panel viewport] [dict get $panel panel_id]}
    dict for {id control} [dict get $record controls] {
        set widget [dict get $control widget]
        if {[winfo exists $widget]} {destroy $widget}
        unset -nocomplain ::GX::PreviewGui::values($host,$id)
    }
}
proc ::GX::_datasetPreviewGuiId {id} {
    if {![regexp {^[a-z][a-z0-9_]{0,47}$} $id]} {error {Use a stable lowercase Preview control ID}}
}
proc ::GX::_datasetPreviewGuiControl {host id} {
    set record [_datasetPreviewGuiRequire $host]
    if {![dict exists $record controls $id]} {error {Unknown Preview GUI control}}
    set control [dict get $record controls $id]
    if {![winfo exists [dict get $control widget]]} {error {Preview GUI control has closed}}
    return $control
}
proc ::GX::_datasetPreviewGuiIconProperties {type properties icons} {
    set id [datasetPublicationV2DictDefault $properties icon {}]
    if {$id eq {}} {
        foreach key {icon_disabled icon_hover icon_selected} {if {[datasetPublicationV2DictDefault $properties $key {}] ne {}} {error {Icon variants require a normal icon}}}
        return
    }
    if {$type ni {action label status checkbutton toggle}} {error {This UI Field component does not support icons}}
    if {$type ni {checkbutton toggle} && [datasetPublicationV2DictDefault $properties icon_selected {}] ne {}} {error {Selected icons require a control with boolean selection semantics}}
    set presentation {}
    foreach key {icon icon_disabled icon_hover icon_selected presentation icon_position icon_size icon_spacing} {if {[dict exists $properties $key]} {dict set presentation $key [dict get $properties $key]}}
    _viewerGuiCommandIconsValidate command_toolbar [dict create actions icon command_icons [dict create icon $presentation]] $icons
    set label [string trim [datasetPublicationV2DictDefault $properties label {}]]
    if {$label eq {}} {set label [string trim [datasetPublicationV2DictDefault $properties text {}]]}
    if {[datasetPublicationV2DictDefault $properties presentation icon_text] eq {icon_only} && $label eq {} && [string trim [datasetPublicationV2DictDefault $properties tooltip {}]] eq {}} {error {Icon-only controls require an accessible label or tooltip}}
}
proc ::GX::_datasetPreviewGuiIconApply {control} {
    set widget [dict get $control widget];set type [dict get $control type];set p [dict get $control properties]
    if {$type eq {toggle}} {append widget .entry}
    set icon [datasetPublicationV2DictDefault $p icon {}]
    if {$icon ne {}} {uiFieldIconApply $widget $p [dict get $control icons $icon] [dict get $control icons]}
    if {$type in {action label status checkbutton toggle}} {
        set tip [datasetPublicationV2DictDefault $p tooltip {}]
        if {$tip eq {} && [datasetPublicationV2DictDefault $p presentation icon_text] eq {icon_only}} {set tip [datasetPublicationV2DictDefault $p label [datasetPublicationV2DictDefault $p text {}]]}
        # Use the existing tooltip owner with one replaceable bindtag, including
        # text+icon labels. Reconfiguring presentation must not accumulate binds.
        set tag GXPreviewTooltip$widget
        if {$tag ni [bindtags $widget]} {bindtags $widget [linsert [bindtags $widget] 0 $tag]}
        if {$type eq {action}} {bind $widget <Enter> {};bind $widget <Leave> {}}
        bind $tag <Enter> [list ::GX::native2DViewportTooltipShow $widget $tip]
        bind $tag <Leave> [list ::GX::native2DViewportTooltipHide $widget]
        bind $tag <Destroy> [list ::GX::_datasetPreviewGuiTooltipDispose $tag]
    }
}
proc ::GX::_datasetPreviewGuiTooltipDispose {tag} {foreach event [bind $tag] {bind $tag $event {}}}
proc ::GX::datasetPreviewGuiControlCreate {host id type properties {options {}}} {
    variable ::GX::PreviewGui::mounts
    set record [_datasetPreviewGuiRequire $host]
    _datasetPreviewGuiId $id
    if {[dict exists $record controls $id] || [dict exists $record panels $id]} {error {Preview GUI ID already exists}}
    if {![dict exists [uiFieldComponentCapabilities] $type]} {error {Unknown UI Field component}}
    foreach key [dict keys $options] {if {$key ni {parent layout callback icons command_icons}} {error {Unknown Preview control option}}}
    set parentId [datasetPublicationV2DictDefault $options parent {}]
    set parent [dict get $record root];set parentType panel;set icons {};set commandIcons {}
    if {$parentId ne {}} {
        if {[dict exists $record panels $parentId]} {set parent [dict get $record panels $parentId body]} else {
            set container [_datasetPreviewGuiControl $host $parentId]
            set parentType [dict get $container type]
            if {$parentType ni {panel section tabs tab splitter}} {error {Parent is not a UI Field container}}
            set parent [dict get $container widget];set icons [dict get $container icons];set commandIcons [dict get $container command_icons]
        }
    }
    if {[dict exists $options icons]} {set icons [viewerGuiIconsValidate [dict get $options icons]]}
    if {[dict exists $commandIcons $id]} {set properties [dict merge [dict get $commandIcons $id] $properties]}
    _datasetPreviewGuiIconProperties $type $properties $icons
    set commandIcons [datasetPublicationV2DictDefault $options command_icons {}]
    if {$commandIcons ne {}} {
        if {$type ne {panel}} {error {command_icons belongs to a UI Field toolbar panel}}
        _viewerGuiCommandIconsValidate command_toolbar [dict create actions [dict keys $commandIcons] command_icons $commandIcons] $icons
    }
    set widget $parent.$id
    set variable ::GX::PreviewGui::values($host,$id)
    set $variable [datasetPublicationV2DictDefault $properties default [expr {$type in {checkbutton toggle} ? 0 : {}}]]
    set control [dict create widget $widget type $type properties $properties icons $icons command_icons $commandIcons callback [datasetPublicationV2DictDefault $options callback {}]]
    try {
        uiFieldComponentCreate $widget $type $properties $variable [list ::GX::_datasetPreviewGuiDispatch $host $id]
        _datasetPreviewGuiIconApply $control
        if {$parentType in {tabs splitter}} {
            if {$parentType eq {tabs}} {$parent add $widget -text [datasetPublicationV2DictDefault $properties title $id]} else {$parent add $widget -weight 1}
        } else {uiFieldComponentLayout $widget $parent [datasetPublicationV2DictDefault $options layout {}]}
        dict set mounts $host controls $id $control
    } on error {message opts} {
        if {[winfo exists $widget]} {destroy $widget}
        unset -nocomplain $variable
        return -options $opts $message
    }
    return $widget
}
proc ::GX::_datasetPreviewGuiDispatch {host id args} {
    if {[catch {set control [_datasetPreviewGuiControl $host $id]}]} return
    set widget [dict get $control widget]
    if {[dict get $control type] in {toggle field choice dataset_selector}} {append widget .entry}
    if {[winfo class $widget] ni {Listbox Text} && [$widget instate disabled]} return
    set callback [dict get $control callback]
    if {$callback eq {}} return
    set value {};catch {set value [datasetPreviewGuiControlGet $host $id]}
    set event [dict create control_id $id type [dict get $control type] event [expr {[dict get $control type] eq {action} ? {invoke} : {changed}}] value $value]
    set module [dict get [_datasetPreviewGuiRequire $host] module]
    if {[catch {_datasetPrivateWithModule $module [list {*}$callback $host $event]} message]} {datasetPreviewLiveSetStatus "$module controls: $message"}
}
proc ::GX::datasetPreviewGuiControlGet {host id} {
    set control [_datasetPreviewGuiControl $host $id]
    return [uiFieldComponentRead [dict get $control widget] [dict get $control type]]
}
proc ::GX::datasetPreviewGuiControlSet {host id value} {
    set control [_datasetPreviewGuiControl $host $id]
    set type [dict get $control type];set widget [dict get $control widget]
    switch $type {
        checkbutton - toggle {if {![string is boolean -strict $value]} {error {Boolean control requires a boolean}};set ::GX::PreviewGui::values($host,$id) [expr {!!$value}]}
        field - choice {
            set value [uiFieldNormalize [dict get $::GX::UiField::widgets $widget descriptor] $value]
            set ::GX::PreviewGui::values($host,$id) $value
        }
        combobox - entry - dataset_selector - progress {set ::GX::PreviewGui::values($host,$id) $value}
        list {uiFieldComponentItemsSet $widget list $value}
        label - status {$widget configure -text $value}
        default {error {This control has no writable public value}}
    }
    return $value
}
proc ::GX::datasetPreviewGuiControlConfigure {host id properties} {
    variable ::GX::PreviewGui::mounts
    set control [_datasetPreviewGuiControl $host $id]
    foreach key [dict keys $properties] {if {$key ni {label text tooltip icon icon_disabled icon_hover icon_selected presentation icon_position icon_size icon_spacing}} {error {Use ControlSet/ControlState for values and state; configure only presentation}}
    }
    set merged [dict merge [dict get $control properties] $properties]
    set type [dict get $control type];set widget [dict get $control widget]
    _datasetPreviewGuiIconProperties $type $merged [dict get $control icons]
    if {[dict exists $properties label]} {
        if {$type in {action checkbutton}} {$widget configure -text [dict get $properties label]} elseif {[winfo exists $widget.caption]} {$widget.caption configure -text [dict get $properties label]}
    }
    if {[dict exists $properties text] && $type in {label status}} {$widget configure -text [dict get $properties text]}
    dict set control properties $merged
    if {[datasetPublicationV2DictDefault $merged icon {}] eq {} && $type in {action label status checkbutton toggle}} {
        set target $widget;if {$type eq {toggle}} {append target .entry}
        $target configure -image {} -compound none
        catch {dict unset ::GX::ViewerGui::iconBindings $target}
    }
    _datasetPreviewGuiIconApply $control
    dict set mounts $host controls $id $control
    return $widget
}
proc ::GX::datasetPreviewGuiControlState {host id {state {}}} {
    set control [_datasetPreviewGuiControl $host $id]
    set type [dict get $control type];set widget [dict get $control widget]
    if {$type in {toggle field choice dataset_selector}} {append widget .entry}
    if {$type in {panel section tabs tab splitter log list table}} {error {State applies to scalar/ttk controls}}
    dict for {key value} $state {
        if {$key ni {enabled selected} || ![string is boolean -strict $value]} {error {Expected enabled/selected boolean state}}
        if {$key eq {selected} && $type ni {checkbutton toggle}} {error {Selection belongs to boolean controls}}
    }
    if {[dict exists $state enabled]} {
        if {$type in {field entry choice combobox toggle checkbutton dataset_selector}} {uiFieldComponentEnabled [dict get $control widget] $type [dict get $state enabled]
        } else {$widget state [expr {[dict get $state enabled] ? {!disabled} : {disabled}}]}
    }
    if {[dict exists $state selected]} {datasetPreviewGuiControlSet $host $id [dict get $state selected]}
    return [dict create enabled [expr {![$widget instate disabled]}] selected [expr {$type in {checkbutton toggle} && [datasetPreviewGuiControlGet $host $id]}]]
}
proc ::GX::datasetPreviewGuiPanelCreate {host id title {anchor top-right} {options {}}} {
    variable ::GX::PreviewGui::mounts
    set record [_datasetPreviewGuiRequire $host];_datasetPreviewGuiId $id
    if {[dict exists $record panels $id] || [dict exists $record controls $id]} {error {Preview GUI ID already exists}}
    set plot [dict get $record plot]
    if {$plot eq {} || ![winfo exists $plot]} {error {This Preview has no supported Plot v4 viewport}}
    foreach key [dict keys $options] {if {$key ni {margin orientation priority max_width max_height min_width close scroll}} {error {Unknown shared viewport panel option}}}
    set viewport [::GX::PlotDatasetAPIv4::widgetChrome $plot]
    set panelId preview_gui_[string range $host 12 end]_$id
    set body [native2DViewportPanelCreate $viewport $panelId $title $anchor $options]
    dict set mounts $host panels $id [dict create viewport $viewport panel_id $panelId body $body]
    return $id
}
proc ::GX::datasetPreviewGuiPanelShow {host id visible} {
    set record [_datasetPreviewGuiRequire $host]
    if {![string is boolean -strict $visible] || ![dict exists $record panels $id]} {error {Expected an existing panel and boolean visibility}}
    set panel [dict get $record panels $id]
    native2DViewportPanelShow [dict get $panel viewport] [dict get $panel panel_id] $visible
}
proc ::GX::datasetPreviewGuiView {host operation} {
    set record [_datasetPreviewGuiRequire $host]
    set plot [dict get $record plot]
    if {$plot eq {} || $operation ni {fit zoom_in zoom_out}} {error {Expected an available Plot viewport and fit/zoom_in/zoom_out}}
    if {$operation eq {fit}} {return [::GX::PlotDatasetAPIv4::widgetView $plot fit]}
    set factor [expr {$operation eq {zoom_in} ? 1.25 : .8}]
    foreach axis [dict get [::GX::PlotDatasetAPIv4::widgetReceipt $plot] axes] {
        if {[dict get $axis axis] eq {x}} {::GX::PlotDatasetAPIv4::widgetView $plot zoom [dict get $axis panel_id] $factor .5 .5}
    }
}
