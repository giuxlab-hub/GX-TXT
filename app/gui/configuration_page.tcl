# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX { variable configurationUi;variable configurationGuiEditors {} }

# Public GUI navigation: Configuration owns its pages and native widgets.
# Callers request a finite page, never pass widget paths or Runtime values.
proc ::GX::configurationOpenPage page {
    if {$page ni {storage runtime computation execution libraries scripts viewers modules}} {error {Unknown Configuration page}}
    set notebook .top.nb.configuration.sections
    if {![llength [info commands winfo]] || ![winfo exists $notebook.$page]} {error {Open the main GX-TXT interface before opening a Configuration page}}
    .top.nb select .top.nb.configuration
    $notebook select $notebook.$page
    raise .
    return [dict create status opened page $page owner CONFIGURATION_API_v1]
}

proc ::GX::buildConfigurationPage {} {
    scientificExecutionNodesInit
    datasetPreviewCacheInit
    variable configurationUi
    variable configurationGuiEditors
    # Only fields projected by real editors supply drafts to the central Save.
    # Other owners may update hidden values after this page was constructed.
    set configurationGuiEditors {}
    set f .top.nb.configuration
    ttk::notebook $f.sections
    pack $f.sections -fill both -expand 1 -padx 8 -pady 8
    foreach group {Storage Runtime Computation Execution Libraries Scripts Viewers Modules} {
        set name [string tolower $group]
        ttk::frame $f.sections.$name
        $f.sections add $f.sections.$name -text $group
        grid columnconfigure $f.sections.$name 1 -weight 1
    }
    set row [dict create]
    dict for {id field} [configurationFields] {
        if {[string match {viewers.native3d.*} $id]} continue
        if {[string match {viewers.launcher.*} $id] || [string match execution.* $id]} continue
        if {[dict exists $field module_id]} continue
        set group [dict get $field group]
        if {$group ni {Storage Runtime Computation Execution Libraries Scripts Viewers Modules}} continue
        set section $f.sections.[string tolower $group]
        set i [expr {[dict exists $row $group] ? [dict get $row $group] : 0}]
        dict set row $group [expr {$i + 1}]
        set widgetId [string map {. _ - _} $id]
        set configurationUi($id) [configurationGet $id]
        if {$id eq "features.script_workspace"} {
            # Preserve the existing preference; check and label stay aligned.
            ttk::checkbutton $section.value_$widgetId -text [dict get $field label] -variable ::GX::configurationUi($id)
            grid $section.value_$widgetId -row $i -column 0 -columnspan 2 -sticky w -padx 8 -pady 5
            dict set configurationGuiEditors $id $section.value_$widgetId
            continue
        }
        ttk::label $section.label_$widgetId -text [dict get $field label]
        if {[dict get $field type] in {boolean integer double number choice color}} {
            uiFieldCreate $section.value_$widgetId $field ::GX::configurationUi($id)
        } else {
            ttk::entry $section.value_$widgetId -textvariable ::GX::configurationUi($id) -width 52
        }
        if {[dict get $field scope] in {framework runtime session}} {
            $section.value_$widgetId configure -state readonly
        }
        grid $section.label_$widgetId -row $i -column 0 -sticky e -padx 8 -pady 5
        grid $section.value_$widgetId -row $i -column 1 -sticky ew -padx 8 -pady 5
        if {[dict get $field scope] in {user module} && ![datasetPublicationV2DictDefault $field readonly 0]} {
            dict set configurationGuiEditors $id $section.value_$widgetId
        }
        if {$id eq "plugins.package_chooser_directory"} {
            ttk::button $section.browse_$widgetId -text Browse… -command ::GX::configurationGuiPluginDirectory
            grid $section.browse_$widgetId -row $i -column 2 -padx 4 -pady 5
        }
        if {[string match {runtime.*} $id] && $id ni {runtime.markdown_viewer runtime.html_viewer}} {
            set tool [string range $id 8 end]
            ttk::button $section.detect_$widgetId -text Detect -command [list ::GX::configurationGuiDetect $tool]
            grid $section.detect_$widgetId -row $i -column 2 -padx 4 -pady 5
            ttk::button $section.test_$widgetId -text Test -command [list ::GX::configurationGuiTestTool $tool]
            grid $section.test_$widgetId -row $i -column 3 -padx 4 -pady 5
        }
    }
    ttk::label $f.sections.storage.explain -text "These are user defaults. An applied Storage Profile can override the Session root and export directory; its effective values are shown below. Existing Sessions remain where they are." -wraplength 760 -justify left
    grid $f.sections.storage.explain -row [dict get $row Storage] -column 0 -columnspan 2 -sticky w -padx 8 -pady 7
    set configurationUi(libraries.registry_path) "Registry: [file join $configurationUi(libraries.scientific_root) registry.json]"
    ttk::label $f.sections.libraries.registry -textvariable ::GX::configurationUi(libraries.registry_path) -wraplength 760 -justify left
    grid $f.sections.libraries.registry -row [dict get $row Libraries] -column 0 -columnspan 2 -sticky w -padx 8 -pady 7
    ttk::button $f.sections.libraries.open -text {Open Libraries…} -command [list ::GX::viewerGuiDispatch open viewer.scientific_library_workspace scientific_library_workspace]
    grid $f.sections.libraries.open -row [expr {[dict get $row Libraries]+1}] -column 0 -columnspan 2 -sticky w -padx 8 -pady 7
    ttk::label $f.sections.scripts.explain -text "This path contains registered reusable scripts. Session-owned script snapshots remain inside each Session." -wraplength 760 -justify left
    grid $f.sections.scripts.explain -row [dict get $row Scripts] -column 0 -columnspan 2 -sticky w -padx 8 -pady 7
    pythonEnvironmentPanelBuild $f.sections.scripts [expr {[dict get $row Scripts]+1}]
    latexEnvironmentPanelBuild $f.sections.scripts [expr {[dict get $row Scripts]+2}]
    # Both read-only inventories own scrollable trees. Share the available
    # height so their controls remain reachable in a short Configuration page.
    foreach offset {1 2} {
        grid rowconfigure $f.sections.scripts [expr {[dict get $row Scripts]+$offset}] -weight 1
    }
    ttk::label $f.sections.viewers.explain -text "Per Dataset contract/type: auto, internal, system, gxtxt:module-id/viewer-id, or an external command argv prefix. Binary Datasets keep an internal inspection fallback." -wraplength 780 -justify left
    grid $f.sections.viewers.explain -row [dict get $row Viewers] -column 0 -columnspan 2 -sticky w -padx 8 -pady 7
    set section $f.sections.viewers
    ttk::notebook $section.native3dTabs
    ttk::frame $section.native3dTabs.graphics
    $section.native3dTabs add $section.native3dTabs.graphics -text "Native 3D graphics / performance"
    grid $section.native3dTabs -row [expr {[dict get $row Viewers]+1}] -column 0 -columnspan 4 -sticky ew -padx 8 -pady 7
    set panel $section.native3dTabs.graphics
    foreach {key choices} {
        preset {Low Medium High Ultra Custom}
        execution {Auto Hardware Software}
        normal_quality {Preview Low Medium High Full}
        interaction_lod {Off On}
        interaction_quality {Preview Low Medium High}
        msaa {Off 2x 4x 8x}
        transparency {Standard {Depth peeling}}
        shadow_rendering {Off {Opaque objects only} {Opaque and translucent objects}}
    } {dict set native3dChoices $key $choices}
    set keys {preset execution normal_quality interaction_lod interaction_quality msaa transparency shadow_rendering \
        export_supersampling display_triangle_budget gpu_budget_mib worker_rss_budget_mib worker_address_space_budget_mib}
    set index 0
    foreach key $keys {
        set id viewers.native3d.$key
        set configurationUi($id) [configurationGet $id]
        set field [dict get [configurationFields] $id]
        set gridRow [expr {$index % 7}]
        set gridColumn [expr {2*($index/7)}]
        ttk::label $panel.label_$key -text [dict get $field label]
        if {[dict exists $native3dChoices $key]} {
            set choiceWidth [expr {$key eq "shadow_rendering" ? 36 : 20}]
            ttk::combobox $panel.value_$key -textvariable ::GX::configurationUi($id) \
                -values [dict get $native3dChoices $key] -state readonly -width $choiceWidth
        } else {
            ttk::entry $panel.value_$key -textvariable ::GX::configurationUi($id) -width 22
        }
        grid $panel.label_$key -row $gridRow -column $gridColumn -sticky e -padx 8 -pady 4
        grid $panel.value_$key -row $gridRow -column [expr {$gridColumn+1}] -sticky ew -padx 8 -pady 4
        dict set configurationGuiEditors $id $panel.value_$key
        incr index
    }
    grid columnconfigure $panel 1 -weight 1
    grid columnconfigure $panel 3 -weight 1
    set configurationUi(native3d_guard) 0
    trace add variable ::GX::configurationUi(viewers.native3d.preset) write ::GX::configurationGuiNative3DPresetChanged
    foreach key {normal_quality interaction_lod interaction_quality msaa transparency shadow_rendering display_triangle_budget} {
        trace add variable ::GX::configurationUi(viewers.native3d.$key) write ::GX::configurationGuiNative3DFieldChanged
    }
    set configurationUi(native3d_health) "Save settings, then Check Native 3D runtime to inspect the effective renderer/device."
    ttk::button $panel.native3dCheck -text "Check Native 3D runtime" -command ::GX::configurationGuiCheckNative3D
    ttk::label $panel.native3dStatus -textvariable ::GX::configurationUi(native3d_health) -wraplength 780 -justify left
    grid $panel.native3dCheck -row 7 -column 0 -columnspan 2 -sticky w -padx 8 -pady 7
    grid $panel.native3dStatus -row 7 -column 2 -columnspan 2 -sticky ew -padx 8 -pady 7
    configurationModulesBuild $f.sections.modules [expr {[dict exists $row Modules] ? [dict get $row Modules] : 0}]
    scientificExecutionNodeManagerBuild $f.sections.execution
    cacheStoragePanelBuild $f.sections
    ttk::frame $f.actions
    ttk::button $f.actions.save -text "Save user defaults" -command ::GX::configurationGuiSave
    ttk::label $f.actions.status -textvariable ::GX::configurationUi(status) -anchor w
    set configurationUi(status) "Session settings remain in each Session manifest. Runtime state is not saved here."
    pack $f.actions.save -side left -padx 5
    pack $f.actions.status -side left -fill x -expand 1 -padx 8
    pack $f.actions -side bottom -fill x -padx 8 -pady {0 8} -before $f.sections
}

proc ::GX::configurationGuiPluginDirectory {} {
    set initial [pluginInstallInitialDirectory $::GX::configurationUi(plugins.package_chooser_directory)]
    set directory [tk_chooseDirectory -title {Default plugin package directory} -initialdir $initial -mustexist 1]
    if {$directory ne {}} {set ::GX::configurationUi(plugins.package_chooser_directory) $directory}
}

proc ::GX::configurationGuiNative3DPresetChanged {name element operation} {
    variable configurationUi
    if {$configurationUi(native3d_guard)} return
    set preset $configurationUi(viewers.native3d.preset)
    if {$preset eq "Custom"} return
    set configurationUi(native3d_guard) 1
    try {
        dict for {key value} [native3dGraphicsPresetFields $preset] {
            set configurationUi(viewers.native3d.$key) $value
        }
    } finally {set configurationUi(native3d_guard) 0}
}

proc ::GX::configurationGuiNative3DFieldChanged {name element operation} {
    variable configurationUi
    if {$configurationUi(native3d_guard)} return
    set candidate $::GX::configurationValues
    foreach key {normal_quality interaction_lod interaction_quality msaa transparency shadow_rendering display_triangle_budget} {
        dict set candidate viewers.native3d.$key $configurationUi(viewers.native3d.$key)
    }
    set configurationUi(native3d_guard) 1
    try {set configurationUi(viewers.native3d.preset) [native3dGraphicsPresetDetect $candidate]} \
        finally {set configurationUi(native3d_guard) 0}
}

proc ::GX::configurationNative3DHealth {} {
    set descriptor [moduleField viewer.native_3d descriptor ""]
    if {$descriptor eq ""} {return "Native 3D Viewer module is not installed."}
    set root [file dirname $descriptor]
    set suffix [expr {$::tcl_platform(platform) eq "windows" ? ".exe" : ""}]
    set files [list [file join $root bin "gx3d-host$suffix"] [file join $root bin "gx3d-worker$suffix"]]
    if {$::tcl_platform(platform) ne "windows"} {lappend files [file join $root lib libgx3d.so]}
    set lines {}
    foreach path $files {
        set name [file tail $path]
        if {![file isfile $path]} {lappend lines "$name: missing ($path)"; continue}
        if {![file executable $path] && $name ne "libgx3d.so"} {lappend lines "$name: not executable"; continue}
        if {$::tcl_platform(platform) ne "windows" && [auto_execok ldd] ne ""} {
            if {[catch {set output [exec ldd $path 2>@1]} reason]} {
                lappend lines "$name: library inspection failed: $reason"
                continue
            }
            set missing {}
            foreach line [split $output "\n"] {
                if {[regexp {^[[:space:]]*([^[:space:]]+)[[:space:]]+=>[[:space:]]+not found} $line -> library]} {lappend missing $library}
            }
            if {[llength $missing]} {lappend lines "$name: missing libraries [join $missing {, }]"} else {lappend lines "$name: shared libraries resolved"}
        } else {
            lappend lines "$name: present; inspect runtime startup on this platform"
        }
    }
    if {$::tcl_platform(platform) ne "windows" && (![info exists ::env(DISPLAY)] || $::env(DISPLAY) eq "")} {
        lappend lines "Display: DISPLAY is unset; interactive host startup needs a display server."
    }
    return [join $lines "\n"]
}

proc ::GX::configurationGuiCheckNative3D {} {
    variable configurationUi
    if {[catch {set status [configurationNative3DHealth]} reason]} {set status "Native 3D dependency check failed: $reason"}
    if {[llength [info commands ::GX::Engine3D::graphicsCheck]]} {
        if {[catch {set renderer [::GX::Engine3D::graphicsCheck]} reason]} {
            append status "\nGX3DE CORE renderer check failed: $reason"
        } else {
            append status "\nGX3DE CORE: [dict get $renderer backend] / [dict get $renderer execution] / [dict get $renderer device]"
            if {[dict get $renderer driver] ne ""} {append status " / [dict get $renderer driver]"}
            set estimatedMiB [format %.1f [expr {[dict get $renderer gpu_estimated_bytes]/1048576.0}]]
            append status "\nGPU resource estimate: $estimatedMiB MiB ([dict get $renderer gpu_accounting]); measured usage: [dict get $renderer gpu_measured_accounting]"
            if {[dict get $renderer gpu_measured_accounting] eq "measured"} {
                append status " ([format %.1f [expr {[dict get $renderer gpu_measured_bytes]/1048576.0}]] MiB)"
            }
        }
    } else {append status "\nGX3DE CORE Viewer Provider is unavailable."}
    set configurationUi(native3d_health) $status
}

proc ::GX::configurationGuiTestTool {tool} {
    variable configurationUi
    if {[catch {configurationValidate runtime.$tool $configurationUi(runtime.$tool)} value]} {
        set configurationUi(status) "$tool: $value"
        return
    }
    set old [configurationGet runtime.$tool]
    try {
        configurationSet runtime.$tool $value
        set result [runtimeToolStatus $tool]
    } finally {
        configurationSet runtime.$tool $old
    }
    set configurationUi(status) [expr {[dict get $result available] ? "$tool: [dict get $result version] ([dict get $result path])" : "$tool: [dict get $result message]"}]
}

proc ::GX::configurationGuiDetect {tool} {
    variable configurationUi
    set detected [runtimeToolDetect $tool]
    if {$detected eq ""} {
        set configurationUi(status) "No $tool executable was detected. Enter its path manually."
    } else {
        set configurationUi(runtime.$tool) $detected
        set configurationUi(status) "$tool detected: $detected"
    }
}

proc ::GX::configurationGuiSave {} {
    variable configurationUi
    variable configurationGuiEditors
    variable configurationValues
    set candidate $configurationValues
    set previous $configurationValues
    if {[catch {
        dict for {id field} [configurationFields] {
            if {[dict get $field scope] in {framework runtime session}} continue
            if {[string match {viewers.launcher.*} $id] || [string match execution.* $id]} {dict set candidate $id [configurationGet $id];continue}
            if {[dict exists $field module_id]} continue
            # An old array entry is not an editor. Retain the authoritative
            # value without revalidating or committing hidden observations.
            if {![dict exists $configurationGuiEditors $id]} continue
            set value [configurationGet $id]
            if {[info exists configurationUi($id)]} {set value $configurationUi($id)}
            if {$id in {ui.theme ui.font_family ui.font_size}} {
                set value $configurationUi(appearance,$id)
                if {$value eq "System/default"} {set value system}
            }
            dict set candidate $id [configurationValidate $id $value]
        }
        if {[dict get $candidate computation.default_workers] > [dict get $candidate computation.max_workers]} {
            error "Default workers cannot exceed maximum workers."
        }
        dict set candidate viewers.native3d.preset [native3dGraphicsPresetDetect $candidate]
        set changes [configurationModulesPending]
        dict for {id field} [configurationFields] {
            if {[dict exists $field module_id] || [dict get $field scope] ni {user module}} continue
            if {[dict get $candidate $id] ne [dict get $previous $id]} {
                lappend changes [dict create id $id scope user value [dict get $candidate $id] expected [dict get $previous $id]]
            }
        }
        configurationCommit $changes
        if {$changes eq {}} {configurationSave}
        configurationModulesSaved
        sourceSurfaceRefreshAll
    } reason]} {
        set configurationValues $previous
        set configurationUi(status) "Configuration was not saved: $reason"
        return
    }
    set configurationUi(status) "Saved user defaults. Theme/fonts: restart GX-TXT. Popup recovery: effective now."
    configurationAppearanceRefresh
    set configurationUi(native3d_guard) 1
    set configurationUi(viewers.native3d.preset) [configurationGet viewers.native3d.preset]
    set configurationUi(native3d_guard) 0
    set configurationUi(libraries.registry_path) "Registry: [file join $configurationUi(libraries.scientific_root) registry.json]"
    if {[llength [info commands _sessionStorageProfileRuntimeRefresh]]} {_sessionStorageProfileRuntimeRefresh}
    if {[llength [info commands workspaceProfilesRefreshGui]]} {workspaceProfilesRefreshGui}
    if {[dict get $previous features.script_workspace] ne [configurationGet features.script_workspace]} {catch {rebuildNativeAnalysisGui}}
}

# This host-only editor projects Configuration fields; it owns no preferences.
proc ::GX::configurationAppearanceBuild {} {
    variable configurationGuiEditors
    set f .top.nb.configuration.sections.appearance
    ttk::frame $f
    .top.nb.configuration.sections add $f -text Appearance
    canvas $f.canvas -highlightthickness 0 -borderwidth 0
    ttk::scrollbar $f.scroll -command [list $f.canvas yview]
    $f.canvas configure -yscrollcommand [list $f.scroll set]
    pack $f.scroll -side right -fill y
    pack $f.canvas -fill both -expand 1
    set p $f.canvas.content
    ttk::frame $p
    $f.canvas create window 0 0 -window $p -anchor nw -tags content
    bind $f.canvas <Configure> [list ::GX::configurationAppearanceResize $f %w]
    bind $p <Configure> [list ::GX::configurationAppearanceScroll $f]
    foreach {section title} {theme Theme fonts {Fonts and readability} remote {Remote X11 compatibility}} {
        ttk::labelframe $p.$section -text $title -padding 8
        grid columnconfigure $p.$section 1 -weight 1
        pack $p.$section -fill x -padx 8 -pady 5
    }
    foreach {id section row values} [list \
        ui.theme theme 0 [linsert [lsort -dictionary [ttk::style theme names]] 0 System/default] \
        ui.font_family fonts 0 [linsert [lsort -dictionary [font families]] 0 System/default] \
        ui.font_size fonts 1 [linsert {8 9 10 11 12 13 14 16 18 20 22 24} 0 System/default]] {
        set field [dict get [configurationFields] $id]
        set key [string map {. _} $id]
        set ::GX::configurationUi($id) [configurationGet $id]
        set ::GX::configurationUi(appearance,$id) [expr {[configurationGet $id] eq "system" ? "System/default" : [configurationGet $id]}]
        ttk::label $p.$section.label_$key -text [dict get $field label]
        ttk::combobox $p.$section.value_$key -state readonly -values $values \
            -textvariable ::GX::configurationUi(appearance,$id) -width 26
        grid $p.$section.label_$key -row $row -column 0 -sticky w -padx 4 -pady 4
        grid $p.$section.value_$key -row $row -column 1 -sticky ew -padx 4 -pady 4
        dict set configurationGuiEditors $id $p.$section.value_$key
    }
    ttk::label $p.theme.note -text {Themes affect ttk widgets. Classic Tk text/canvas and scientific graphics do not become a complete dark mode. Theme and font changes require restarting GX-TXT after Save.} -justify left
    grid $p.theme.note -row 1 -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
    ttk::label $p.fonts.note -text {System/default preserves interpreter fonts. Family affects proportional named GUI fonts; heading weight and monospace family stay distinct. Size preserves relative named-font sizes (8–24 pt). Explicit private fonts and PDF output fonts are unchanged.} -justify left
    grid $p.fonts.note -row 2 -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
    foreach id {ui.x11_popup_repair_enabled ui.x11_popup_repair_delay_ms} {
        set ::GX::configurationUi($id) [configurationGet $id]
    }
    ttk::checkbutton $p.remote.enabled -text {Enable remote X11 popup recovery} -variable ::GX::configurationUi(ui.x11_popup_repair_enabled)
    grid $p.remote.enabled -row 0 -column 0 -columnspan 2 -sticky w -padx 4 -pady 4
    dict set configurationGuiEditors ui.x11_popup_repair_enabled $p.remote.enabled
    ttk::label $p.remote.label -text {Delay after popup mapping (ms)}
    ttk::spinbox $p.remote.delay -from 25 -to 2000 -increment 25 -width 10 -textvariable ::GX::configurationUi(ui.x11_popup_repair_delay_ms)
    grid $p.remote.label -row 1 -column 0 -sticky w -padx 4 -pady 4
    grid $p.remote.delay -row 1 -column 1 -sticky w -padx 4 -pady 4
    dict set configurationGuiEditors ui.x11_popup_repair_delay_ms $p.remote.delay
    ttk::frame $p.remote.presets
    foreach delay {150 300 500} {
        ttk::button $p.remote.presets.d$delay -text "$delay ms" -command [list set ::GX::configurationUi(ui.x11_popup_repair_delay_ms) $delay]
        pack $p.remote.presets.d$delay -side left -padx 3
    }
    grid $p.remote.presets -row 2 -column 0 -columnspan 2 -sticky w -pady 3
    ttk::label $p.remote.status -textvariable ::GX::configurationUi(appearanceRecovery) -justify left
    grid $p.remote.status -row 3 -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
    ttk::label $p.remote.note -text {After Save, recovery changes apply to future popups immediately. Only the recognized HC-Consult/VcXsrv X11 server is affected. 150 ms is the tested baseline, not a universal minimum; longer is not necessarily better. Disabled means no new damage requests.} -justify left
    grid $p.remote.note -row 4 -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
    ttk::labelframe $p.effective -text {Current effective appearance} -padding 8
    ttk::label $p.effective.values -textvariable ::GX::configurationUi(appearanceEffective) -justify left
    ttk::label $p.effective.warning -textvariable ::GX::configurationUi(appearanceWarning) -justify left
    pack $p.effective.values $p.effective.warning -fill x
    pack $p.effective -fill x -padx 8 -pady 5
    sourceSurfaceAppearanceBuild $p
    # The existing Source Surface owner supplies the palette chooser and typed
    # controls. Saved schemes commit through their own actions, not this draft.
    dict for {id field} [configurationFields] {
        if {[string match source.color.* $id]} {
            dict set configurationGuiEditors $id $p.source.color
        } elseif {[string match source.* $id]} {
            set widget $p.source.v_[string map {. _} $id]
            if {[winfo exists $widget]} {dict set configurationGuiEditors $id $widget}
        }
    }
    ttk::frame $p.actions
    ttk::button $p.actions.revert -text {Revert unsaved appearance} -command [list ::GX::configurationAppearanceReset 0]
    ttk::button $p.actions.defaults -text {Restore appearance defaults} -command [list ::GX::configurationAppearanceReset 1]
    pack $p.actions.revert $p.actions.defaults -side left -padx 4
    pack $p.actions -fill x -padx 8 -pady 5
    bind $p.actions <Configure> [list ::GX::uiFieldControlsLayout $p.actions %w]
    configurationAppearanceRefresh
}
proc ::GX::configurationAppearanceResize {f width} {
    $f.canvas itemconfigure content -width $width
    set p $f.canvas.content
    foreach w [list $p.theme.note $p.fonts.note $p.remote.note $p.remote.status $p.effective.values $p.effective.warning] {
        $w configure -wraplength [expr {max(160,$width-50)}]
    }
}
proc ::GX::configurationAppearanceScroll {f} {$f.canvas configure -scrollregion [$f.canvas bbox all]}
proc ::GX::configurationAppearanceRefresh {} {
    if {![info exists ::GX::ui(appearanceInitialized)]} return
    set ::GX::configurationUi(appearanceEffective) [uiAppearanceEffective]
    set ::GX::configurationUi(appearanceWarning) $::GX::ui(appearanceWarning)
    set ::GX::configurationUi(appearanceRecovery) "Recovery: [uiFieldComboboxStatus]; configured delay [configurationGet ui.x11_popup_repair_delay_ms] ms."
}
proc ::GX::configurationAppearanceReset {defaults} {
    dict for {id field} [configurationFields] {
        if {[dict get $field group] ne "Appearance"} continue
        set value [expr {$defaults ? [dict get $field default] : [configurationGet $id]}]
        set ::GX::configurationUi($id) $value
        if {$id in {ui.theme ui.font_family ui.font_size}} {
            set ::GX::configurationUi(appearance,$id) [expr {$value eq "system" ? "System/default" : $value}]
        }
    }
    set ::GX::configurationUi(status) {Appearance choices updated. Save user defaults to persist; theme/fonts apply after restart.}
}
