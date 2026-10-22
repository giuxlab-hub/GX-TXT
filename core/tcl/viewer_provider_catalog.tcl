# SPDX-License-Identifier: GPL-3.0-or-later
# Presentation fields live in the existing Viewer descriptors/Configuration.
proc ::GX::viewerProviderEnabled {module viewer} {
    viewerRequireProvider $module $viewer
    set key viewers.launcher.m[binary encode hex [encoding convertto utf-8 $module]]_v[binary encode hex [encoding convertto utf-8 $viewer]]
    if {![dict exists [configurationFields] $key]} {
        set d $::GX::moduleCatalog($module,dict)
        set name [descriptorValue $d viewer.$viewer short_title [descriptorValue $d viewer.$viewer name $viewer]]
        configurationRegister $key [dict create group Viewers label "Enable $name Viewer" type boolean default 1 scope user]
    }
    return [configurationGet $key]
}
proc ::GX::viewerProviderSetEnabled {module viewer value} {
    uiFieldNormalize {type boolean} $value
    viewerProviderEnabled $module $viewer
    if {$value} {foreach dependency [splitList [moduleField $module depends {}]] {if {[moduleField $dependency descriptor {}] eq {}} {error "Viewer requires the missing module '$dependency'"}}}
    set key viewers.launcher.m[binary encode hex [encoding convertto utf-8 $module]]_v[binary encode hex [encoding convertto utf-8 $viewer]]
    configurationSet $key $value;configurationSave
    if {[llength [info commands winfo]] && [llength [info commands ::GX::viewerGuiRefresh]]} {viewerGuiRefresh}
    return [dict create module_id $module viewer_id $viewer enabled [expr {!!$value}] application next_open service_enabled [moduleIsEnabled $module] active_workspaces preserved]
}
proc ::GX::viewerProviderIconPath {module relative} {
    if {$relative eq {}} {return {}}
    if {[file pathtype $relative] ne "relative" || ".." in [file split $relative] || [file extension $relative] ne ".png"} {error {Viewer icon must be a module-relative PNG without traversal}}
    set root [file normalize [file dirname [moduleField $module descriptor]]]
    set path [file normalize [file join $root $relative]]
    if {![string match "$root/*" $path] || ![file isfile $path] || [file type $path] eq "link" || [file size $path]>2097152} {error {Viewer icon is missing, unsafe or exceeds 2 MiB}}
    return $path
}
proc ::GX::viewerProviderCatalog {{includeReplaced 0}} {
    uiFieldNormalize {type boolean} $includeReplaced
    set result {}
    foreach module $::GX::moduleOrder {
        foreach viewer [viewerProviderIds $module] {
            set definition [viewerProviderDefinition $module $viewer 1]
            set replacement [dict get $definition catalog_replacement]
            if {!$includeReplaced && $replacement ne {}} {
                if {![regexp {^(viewer\.[a-z0-9_]+)/([a-z][a-z0-9_]*)$} $replacement -> targetModule targetViewer] || $replacement eq "$module/$viewer"} {error {Catalog replacement must name a different registered Viewer module/provider}}
                if {[info exists ::GX::moduleCatalog($targetModule,dict)] && $targetViewer in [viewerProviderIds $targetModule] && [viewerProviderEnabled $targetModule $targetViewer]} continue
            }
            lappend result $definition
        }
    }
    return $result
}
