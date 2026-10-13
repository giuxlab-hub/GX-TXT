# SPDX-License-Identifier: GPL-3.0-or-later
# Native process adapter for Viewer Provider API v1.
namespace eval ::GX::Native3D {
    variable worker ""
    variable host ""
    variable hostCommand {}
    variable hostReady 0
    variable hostSoftware 0
    variable hostRetried 0
    variable hostGraphicsFailure 0
    variable hostStartupCommands {}
    variable hostQuitAcknowledged 0
    variable source ""
    variable session ""
    variable portable 0
    variable expectedSha ""
    variable cacheKey ""
    variable sourceSha ""
    variable status idle
    variable progress ""
    variable selection ""
    variable documentId ""
    variable requestedLod auto
    variable displayMode surface
    variable projection perspective
    variable visible 1
    variable opacity 1.0
    variable lighting 1
    variable backgroundRgb {0.12;0.14;0.18}
    variable clippingEnabled 0
    variable clippingAxis z
    variable clippingFraction 0.5
    variable renderMode ""
    variable capabilitiesEvent ""
    variable benchmarkEvent ""
    variable benchmarkSequenceEvent ""
    variable screenshotEvent ""
    variable layerEvents [dict create]
    variable selectedScientificLayer ""
    variable selectedScientificVisible 1
    variable selectedScientificOpacity 1.0
    variable assemblyObjectIds {}
    variable selectedAssemblyObject ""
    variable selectedAssemblyVisible 1
    variable selectedCellId ""
    variable patternEvents [dict create]
    variable patternPending [dict create]
    variable repeatProposalEvent ""
    variable repeatReadyEvent ""
    variable repeatPending [dict create]
    variable repeatStatus "No repeat proposal."
    variable patternRadius 1.0
    variable patternLayout rectangular
    variable patternPlacementPath ""
    variable patternCountX 10
    variable patternCountY 10
    variable patternStepX 1.0
    variable patternStepY 1.0
    variable scientificPath ""
    variable scientificScalar ""
    variable scientificVector ""
    variable scientificDataset ""
    variable scientificX ""
    variable scientificY ""
    variable scientificZ ""
    variable scientificDatasetScalar ""
    variable scientificVx ""
    variable scientificVy ""
    variable scientificVz ""
    variable hostEventsRaw {}
    variable workingPlane [dict create]
    variable pendingWorkingPlaneEchoes {}
    variable interactionSubscribers {}
    variable latestPick [dict create]
    variable operationStartedMs 0
    variable previewReadyMs 0
    variable cacheReadyMs 0
    variable cacheHitMs 0
    variable firstInteractiveMs 0
    variable workerPeakMiB 0
    variable portableChoice 0
    variable cancelStage ""
    variable selectedDatasetId ""
    variable datasetChoice ""
    variable datasetScalar ""
    variable datasetIsovalues ""
    variable datasetScalarRange ""
    variable sourceType "Imported 3D Dataset"
    variable plotChoice ""
    variable plotSources [dict create]
    variable representationChoice ""
    variable plotSourceLabel ""
    variable plotVariantLabel ""
    variable plotSyncStatus ""
    variable sceneOnly 0
    variable pendingScene [dict create]
    variable sceneRestoring 0
}

proc ::GX::Native3D::root {} {
    return [file dirname [::GX::moduleField viewer.native_3d descriptor]]
}

proc ::GX::Native3D::binary {name} {
    set suffix [expr {$::tcl_platform(platform) eq "windows" ? ".exe" : ""}]
    set path [file join [root] bin "${name}${suffix}"]
    if {![file isfile $path]} { error "Native 3D runtime is missing: $path" }
    return $path
}

proc ::GX::Native3D::cacheRoot {} {
    set path [file join [::GX::configurationCacheDirectory] native3d]
    file mkdir $path
    return $path
}

proc ::GX::Native3D::hostEnvironment {{software 0}} {
    set result [dict create GX3D_GPU_BUDGET_MIB [gpuBudgetMiB]]
    if {$::tcl_platform(platform) ne "windows" &&
        ($software || ([info exists ::env(GXTXT_NATIVE3D_SOFTWARE)] &&
        [string tolower [string trim $::env(GXTXT_NATIVE3D_SOFTWARE)]] in {1 true yes on}))} {
        dict set result LIBGL_ALWAYS_SOFTWARE 1
        # An inherited indirect-GLX setting can prevent local Mesa from
        # creating a usable context over X11 forwarding.
        dict set result LIBGL_ALWAYS_INDIRECT 0
        dict set result MESA_LOADER_DRIVER_OVERRIDE llvmpipe
        dict set result GALLIUM_DRIVER llvmpipe
    }
    return $result
}

proc ::GX::Native3D::startHost {command {software 0} {retry 0}} {
    variable host
    variable hostCommand
    variable hostReady
    variable hostSoftware
    variable hostRetried
    variable hostGraphicsFailure
    variable hostStartupCommands
    variable hostQuitAcknowledged
    set hostCommand $command
    set hostReady 0
    set hostGraphicsFailure 0
    set hostQuitAcknowledged 0
    if {!$retry} {
        set hostRetried 0
        set hostStartupCommands {}
    }
    set hostSoftware [expr {$software || ([info exists ::env(GXTXT_NATIVE3D_SOFTWARE)] &&
        [string tolower [string trim $::env(GXTXT_NATIVE3D_SOFTWARE)]] in {1 true yes on})}]
    # Capture graphics initialization diagnostics from VTK/Mesa as well as the
    # normal JSON protocol.  The child is still the production renderer.
    set host [processOpen [concat $command [list 2>@1]] r+ [hostEnvironment $hostSoftware]]
    fileevent $host readable ::GX::Native3D::hostReadable
    return $host
}

proc ::GX::Native3D::processOpen {command mode {extraEnvironment {}}} {
    set library [file join [root] lib]
    set key [expr {$::tcl_platform(platform) eq "windows" ? "PATH" : "LD_LIBRARY_PATH"}]
    set separator [expr {$::tcl_platform(platform) eq "windows" ? ";" : ":"}]
    set old [expr {[info exists ::env($key)] ? $::env($key) : ""}]
    set ::env($key) "$library$separator$old"
    set previous [dict create]
    dict for {name value} $extraEnvironment {
        if {[info exists ::env($name)]} {
            dict set previous $name [list present $::env($name)]
        } else {
            dict set previous $name [list absent]
        }
        set ::env($name) $value
    }
    try {
        set channel [open "|$command" $mode]
    } finally {
        set ::env($key) $old
        dict for {name saved} $previous {
            if {[lindex $saved 0] eq "present"} {
                set ::env($name) [lindex $saved 1]
            } else {
                unset -nocomplain ::env($name)
            }
        }
    }
    fconfigure $channel -blocking 0 -buffering line -encoding utf-8 -translation lf
    return $channel
}

proc ::GX::Native3D::eventValue {line field} {
    set pattern [format {"%s":"([^"]*)"} $field]
    if {[regexp -- $pattern $line -> value]} { return $value }
    return ""
}
proc ::GX::Native3D::eventNumber {line field} {
    set pattern [format {"%s":(-?[0-9]+)} $field]
    if {[regexp -- $pattern $line -> value]} {return $value}
    return ""
}
proc ::GX::Native3D::eventVector {line field} {
    set pattern [format {"%s":\[([^]]+)\]} $field]
    if {![regexp -- $pattern $line -> values]} { return {} }
    set result {}
    foreach value [split $values ,] {
        set value [string trim $value]
        if {![string is double -strict $value]} { return {} }
        lappend result [expr {double($value)}]
    }
    return $result
}
proc ::GX::Native3D::subscribeInteraction {callback} {
    variable interactionSubscribers
    if {[llength $callback] == 0} {error "Interaction callback is required"}
    if {$callback ni $interactionSubscribers} {lappend interactionSubscribers $callback}
}
proc ::GX::Native3D::unsubscribeInteraction {callback} {
    variable interactionSubscribers
    set index [lsearch -exact $interactionSubscribers $callback]
    if {$index >= 0} {set interactionSubscribers [lreplace $interactionSubscribers $index $index]}
}
proc ::GX::Native3D::notifyInteraction {event} {
    variable interactionSubscribers
    foreach callback $interactionSubscribers {
        if {[catch {uplevel #0 [list {*}$callback $event]} problem]} {
            set ::GX::Native3D::progress "Native interaction callback failed: $problem"
        }
    }
}
proc ::GX::Native3D::setWorkingPlane {origin normal uAxis {visible 1}} {
    variable workingPlane
    foreach {name value} [list origin $origin normal $normal u_axis $uAxis] {
        if {[llength $value] != 3} {error "Working plane $name must have three coordinates"}
        foreach coordinate $value {if {![string is double -strict $coordinate]} {error "Working plane $name must be numeric"}}
    }
    if {$visible ni {0 1}} {error "Working plane visibility must be 0 or 1"}
    set workingPlane [dict create origin $origin normal $normal u_axis $uAxis visible $visible]
    if {$::GX::Native3D::host ne "" && $::GX::Native3D::status eq "interactive"} {
        queueWorkingPlaneEcho $workingPlane
        send "WORKING_PLANE [join [concat $origin $normal $uAxis [list $visible]] { }]"
    }
    return $workingPlane
}
proc ::GX::Native3D::queueWorkingPlaneEcho {plane} {
    variable pendingWorkingPlaneEchoes
    lappend pendingWorkingPlaneEchoes $plane
    if {[llength $pendingWorkingPlaneEchoes] > 32} {
        set pendingWorkingPlaneEchoes [lrange $pendingWorkingPlaneEchoes end-31 end]
    }
}
proc ::GX::Native3D::consumeWorkingPlaneEcho {plane} {
    variable pendingWorkingPlaneEchoes
    set index 0
    foreach expected $pendingWorkingPlaneEchoes {
        set equal [expr {[dict get $expected visible] == [dict get $plane visible]}]
        foreach key {origin normal u_axis} {
            for {set i 0} {$i < 3} {incr i} {
                if {abs([lindex [dict get $expected $key] $i]-[lindex [dict get $plane $key] $i]) > 1e-4} {set equal 0}
            }
        }
        if {$equal} {
            set pendingWorkingPlaneEchoes [lreplace $pendingWorkingPlaneEchoes 0 $index]
            return 1
        }
        incr index
    }
    return 0
}
proc ::GX::Native3D::workingPlane {} {return $::GX::Native3D::workingPlane}
proc ::GX::Native3D::latestPick {} {return $::GX::Native3D::latestPick}

proc ::GX::Native3D::panelScrollRegion {w} {
    if {![winfo exists $w.viewport] || ![winfo exists $w.body]} return
    $w.viewport configure -scrollregion [list 0 0 [winfo reqwidth $w.body] [winfo reqheight $w.body]]
}

proc ::GX::Native3D::refreshCancelAction {} {
    if {![llength [info commands winfo]]} return
    if {![winfo exists .gxNative3D.body.actions.cancel]} return
    .gxNative3D.body.actions.cancel configure -state [expr {
        $::GX::Native3D::worker ne "" && $::GX::Native3D::status ne "cancelled" ? "normal" : "disabled"
    }]
}

proc ::GX::Native3D::panel {} {
    if {![llength [info commands toplevel]]} return
    set w .gxNative3D
    if {[winfo exists $w]} { wm deiconify $w; raise $w; return }
    toplevel $w
    wm title $w "GX-TXT Native 3D Viewer"
    wm geometry $w 1100x760
    wm minsize $w 700 400
    canvas $w.viewport -highlightthickness 0 -borderwidth 0
    ttk::scrollbar $w.yscroll -orient vertical -command [list $w.viewport yview]
    ttk::scrollbar $w.xscroll -orient horizontal -command [list $w.viewport xview]
    $w.viewport configure -yscrollcommand [list $w.yscroll set] \
        -xscrollcommand [list $w.xscroll set]
    grid $w.viewport -row 0 -column 0 -sticky nsew
    grid $w.yscroll -row 0 -column 1 -sticky ns
    grid $w.xscroll -row 1 -column 0 -sticky ew
    grid rowconfigure $w 0 -weight 1
    grid columnconfigure $w 0 -weight 1
    ttk::frame $w.body -padding 10
    $w.viewport create window 0 0 -window $w.body -anchor nw
    bind $w.body <Configure> [list ::GX::Native3D::panelScrollRegion $w]
    ttk::label $w.body.title -text "Native 3D Viewer" -font {TkDefaultFont 12 bold}
    ttk::label $w.body.sourceTypeLabel -text "Source type"
    ttk::combobox $w.body.sourceType -state readonly -width 28 \
        -values {{Imported 3D Dataset} {Plot Dataset 3D graph}} \
        -textvariable ::GX::Native3D::sourceType
    bind $w.body.sourceType <<ComboboxSelected>> ::GX::Native3D::sourceTypeSelected
    ttk::label $w.body.datasetLabel -text "Imported 3D Dataset"
    ttk::combobox $w.body.dataset -state readonly -width 48 -textvariable ::GX::Native3D::datasetChoice
    bind $w.body.dataset <<ComboboxSelected>> ::GX::Native3D::refreshVtiControls
    ttk::button $w.body.openDataset -text "Render Dataset" -command ::GX::Native3D::openChosenDataset
    ttk::button $w.body.refreshDatasets -text "Refresh Datasets" -command ::GX::Native3D::refreshDatasets
    ttk::label $w.body.scalarLabel -text "VTI scalar array"
    ttk::entry $w.body.scalar -textvariable ::GX::Native3D::datasetScalar -width 32
    ttk::label $w.body.isoLabel -text "VTI isovalues (semicolon-separated)"
    ttk::entry $w.body.isovalues -textvariable ::GX::Native3D::datasetIsovalues -width 32
    ttk::label $w.body.isoHelp -text "An isovalue is a scalar field value whose equal-value surface will be drawn. Enter one or more values separated by semicolons; choose values from your field's range." -wraplength 760 -justify left
    ttk::label $w.body.scalarRange -textvariable ::GX::Native3D::datasetScalarRange -wraplength 760 -justify left
    ttk::button $w.body.open -text "Open external model (compatibility)..." -command ::GX::Native3D::choose
    ttk::checkbutton $w.body.portable -text "Copy original into this Session (portable)" -variable ::GX::Native3D::portableChoice
    pack $w.body.title $w.body.sourceTypeLabel $w.body.sourceType \
        $w.body.datasetLabel $w.body.dataset $w.body.scalarLabel \
        $w.body.scalar $w.body.isoLabel $w.body.isovalues $w.body.isoHelp $w.body.scalarRange $w.body.openDataset \
        $w.body.refreshDatasets $w.body.open $w.body.portable -anchor w -pady 3
    refreshDatasets
    ttk::labelframe $w.body.plotSource -text "Plot Dataset 3D graph"
    ttk::combobox $w.body.plotSource.graph -state readonly -width 48 \
        -textvariable ::GX::Native3D::plotChoice
    ttk::button $w.body.plotSource.refresh -text "Refresh graphs" -command ::GX::Native3D::refreshPlotSources
    ttk::button $w.body.plotSource.create -text "Create interactive view" -command ::GX::Native3D::openChosenPlot
    ttk::combobox $w.body.plotSource.representation -state readonly -width 18 \
        -textvariable ::GX::Native3D::representationChoice
    bind $w.body.plotSource.representation <<ComboboxSelected>> ::GX::Native3D::representationSelected
    ttk::button $w.body.plotSource.activate -text "Open view" -command ::GX::Native3D::openChosenRepresentation
    ttk::button $w.body.plotSource.sync -text "Sync" -command ::GX::Native3D::syncChosenRepresentation
    ttk::label $w.body.plotSource.source -textvariable ::GX::Native3D::plotSourceLabel
    ttk::label $w.body.plotSource.variant -textvariable ::GX::Native3D::plotVariantLabel
    ttk::label $w.body.plotSource.status -textvariable ::GX::Native3D::plotSyncStatus
    pack $w.body.plotSource.graph $w.body.plotSource.refresh $w.body.plotSource.create \
        $w.body.plotSource.representation $w.body.plotSource.activate $w.body.plotSource.sync \
        $w.body.plotSource.source $w.body.plotSource.variant $w.body.plotSource.status \
        -side left -padx 3
    pack $w.body.plotSource -fill x -pady 3
    refreshPlotSources
    refreshRepresentations
    sourceTypeSelected
    ttk::frame $w.body.camera
    pack $w.body.camera -fill x -pady 4
    foreach {label command} {
        Fit FIT Reset RESET Front {PRESET front} Back {PRESET back}
        Left {PRESET left} Right {PRESET right} Top {PRESET top} Bottom {PRESET bottom}
    } {
        set widget [string tolower $label]
        ttk::button $w.body.camera.$widget -text $label -command [list ::GX::Native3D::cameraPreset [string tolower $label]]
        pack $w.body.camera.$widget -side left -padx 2
    }
    foreach {label command} {← {ARROW left} ↑ {ARROW up} ↓ {ARROW down} → {ARROW right}} {
        set widget arrow_[string map {← left ↑ up ↓ down → right} $label]
        ttk::button $w.body.camera.$widget -text $label -command [list ::GX::Native3D::rotateView [lindex $command 1]]
        pack $w.body.camera.$widget -side left -padx 2
    }
    ttk::frame $w.body.view
    pack $w.body.view -fill x -pady 4
    ttk::label $w.body.view.lodLabel -text "LOD"
    ttk::combobox $w.body.view.lod -values {auto preview low medium high full} -state readonly -textvariable ::GX::Native3D::requestedLod -width 10
    bind $w.body.view.lod <<ComboboxSelected>> {::GX::Native3D::setLod $::GX::Native3D::requestedLod}
    ttk::label $w.body.view.modeLabel -text "Display"
    ttk::combobox $w.body.view.mode -values {surface wireframe surface_edges} -state readonly -textvariable ::GX::Native3D::displayMode -width 14
    bind $w.body.view.mode <<ComboboxSelected>> {::GX::Native3D::setDisplayMode $::GX::Native3D::displayMode}
    ttk::label $w.body.view.projLabel -text "Projection"
    ttk::combobox $w.body.view.proj -values {perspective orthographic} -state readonly -textvariable ::GX::Native3D::projection -width 14
    bind $w.body.view.proj <<ComboboxSelected>> {::GX::Native3D::setProjection $::GX::Native3D::projection}
    ttk::checkbutton $w.body.view.visible -text Visible -variable ::GX::Native3D::visible \
        -command {::GX::Native3D::setVisible $::GX::Native3D::visible}
    pack $w.body.view.lodLabel $w.body.view.lod $w.body.view.modeLabel $w.body.view.mode \
        $w.body.view.projLabel $w.body.view.proj $w.body.view.visible -side left -padx 4
    ttk::frame $w.body.opacity
    ttk::label $w.body.opacity.label -text "Opacity"
    ttk::scale $w.body.opacity.scale -from 0 -to 1 -orient horizontal -length 230 \
        -variable ::GX::Native3D::opacity -command ::GX::Native3D::setOpacity
    pack $w.body.opacity.label $w.body.opacity.scale -side left -padx 4
    pack $w.body.opacity -fill x -pady 2
    ttk::frame $w.body.appearance
    ttk::checkbutton $w.body.appearance.lighting -text "Lighting" -variable ::GX::Native3D::lighting \
        -command {::GX::Native3D::setLighting $::GX::Native3D::lighting}
    ttk::button $w.body.appearance.background -text "Background..." -command ::GX::Native3D::chooseBackground
    pack $w.body.appearance.lighting $w.body.appearance.background -side left -padx 4
    pack $w.body.appearance -fill x -pady 2
    ttk::frame $w.body.clip
    ttk::checkbutton $w.body.clip.enabled -text "Clip model" -variable ::GX::Native3D::clippingEnabled \
        -command ::GX::Native3D::clipChanged
    ttk::combobox $w.body.clip.axis -values {x y z} -state readonly -width 3 \
        -textvariable ::GX::Native3D::clippingAxis
    bind $w.body.clip.axis <<ComboboxSelected>> ::GX::Native3D::clipChanged
    ttk::scale $w.body.clip.position -from 0 -to 1 -orient horizontal -length 230 \
        -variable ::GX::Native3D::clippingFraction -command ::GX::Native3D::clipChanged
    pack $w.body.clip.enabled $w.body.clip.axis $w.body.clip.position -side left -padx 4
    pack $w.body.clip -fill x -pady 2
    ttk::labelframe $w.body.scientific -text "Scientific VTU layers from this Session"
    pack $w.body.scientific -fill x -pady 4
    listbox $w.body.scientific.layers -height 3 -exportselection 0
    bind $w.body.scientific.layers <<ListboxSelect>> ::GX::Native3D::scientificLayerSelected
    ttk::button $w.body.scientific.add -text "Add Session VTU..." -command ::GX::Native3D::chooseVtu
    ttk::button $w.body.scientific.dataset -text "Add Dataset points..." -command ::GX::Native3D::chooseDatasetPoints
    ttk::button $w.body.scientific.pattern -text "Pattern selected cell..." -command ::GX::Native3D::choosePatternRegion
    ttk::checkbutton $w.body.scientific.visible -text "Selected layer visible" \
        -variable ::GX::Native3D::selectedScientificVisible -command ::GX::Native3D::setScientificVisibility
    ttk::button $w.body.scientific.remove -text "Remove selected layer" -command ::GX::Native3D::removeScientificLayer
    ttk::entry $w.body.scientific.opacity -textvariable ::GX::Native3D::selectedScientificOpacity -width 5
    ttk::button $w.body.scientific.applyOpacity -text "Set opacity" -command ::GX::Native3D::setScientificOpacity
    pack $w.body.scientific.layers -side left -fill x -expand 1 -padx 4 -pady 3
    pack $w.body.scientific.add $w.body.scientific.dataset $w.body.scientific.pattern $w.body.scientific.visible \
        $w.body.scientific.opacity $w.body.scientific.applyOpacity $w.body.scientific.remove \
        -side left -padx 4
    refreshScientificLayers
    ttk::labelframe $w.body.assembly -text "STEP assembly parts"
    pack $w.body.assembly -fill x -pady 3
    listbox $w.body.assembly.parts -height 2 -exportselection 0
    bind $w.body.assembly.parts <<ListboxSelect>> ::GX::Native3D::assemblyObjectSelected
    ttk::checkbutton $w.body.assembly.visible -text "Selected part visible" \
        -variable ::GX::Native3D::selectedAssemblyVisible -command ::GX::Native3D::setAssemblyVisibility
    pack $w.body.assembly.parts -side left -fill x -expand 1 -padx 4
    pack $w.body.assembly.visible -side left -padx 4
    ttk::labelframe $w.body.repeats -text "Mesh repeated components"
    pack $w.body.repeats -fill x -pady 3
    ttk::button $w.body.repeats.propose -text "Find matches for selected cell" -command ::GX::Native3D::proposeRepeats
    ttk::button $w.body.repeats.accept -text "Accept matches" -command ::GX::Native3D::acceptRepeats
    ttk::button $w.body.repeats.reject -text "Reject" -command ::GX::Native3D::rejectRepeats
    ttk::label $w.body.repeats.status -textvariable ::GX::Native3D::repeatStatus -wraplength 350
    pack $w.body.repeats.propose $w.body.repeats.accept $w.body.repeats.reject \
        $w.body.repeats.status -side left -padx 4
    ttk::frame $w.body.actions
    pack $w.body.actions -fill x -pady 6
    ttk::button $w.body.actions.cancel -text "Cancel preprocessing" -state disabled -command ::GX::Native3D::cancel
    ttk::button $w.body.actions.screenshot -text "Save view PNG..." -command ::GX::Native3D::saveScreenshot
    ttk::button $w.body.actions.hide -text "Hide control panel" -command [list wm withdraw $w]
    pack $w.body.actions.cancel $w.body.actions.screenshot $w.body.actions.hide -side left -padx 4
    ttk::label $w.body.status -textvariable ::GX::Native3D::progress -wraplength 740 -justify left
    ttk::label $w.body.selection -textvariable ::GX::Native3D::selection -wraplength 740 -justify left
    pack $w.body.status $w.body.selection -anchor w -fill x -pady 3
}

proc ::GX::Native3D::choose {} {
    if {$::GX::currentSession eq ""} { error "Open a Session before using the Native 3D Viewer." }
    set path [tk_getOpenFile -title "Open 3D model" -filetypes {{{3D models} {.stl .obj .step .stp}} {{All files} *}}]
    if {$path ne ""} { openSource $path $::GX::Native3D::portableChoice }
}

proc ::GX::Native3D::compatibleDatasetIds {} {
    if {$::GX::currentSession eq ""} { return {} }
    set ids {}
    foreach id [::GX::sessionInspectionDatasetIds] {
        set record [::GX::sessionInspectionDataset $id]
        if {![dict exists $record format]} continue
        set format [string tolower [dict get $record format]]
        if {$format in {stl obj step stp vtu vtp vti}} { lappend ids $id }
    }
    return $ids
}

proc ::GX::Native3D::refreshDatasets {} {
    variable datasetChoice
    set ids [compatibleDatasetIds]
    if {[winfo exists .gxNative3D.body.dataset]} {
        .gxNative3D.body.dataset configure -values $ids
        .gxNative3D.body.openDataset configure -state [expr {[llength $ids] ? "normal" : "disabled"}]
    }
    if {$datasetChoice ni $ids} { set datasetChoice [expr {[llength $ids] ? [lindex $ids 0] : ""}] }
    refreshVtiControls
    return $ids
}

proc ::GX::Native3D::refreshVtiControls {} {
    variable datasetChoice
    variable datasetScalarRange
    set w .gxNative3D.body
    if {![winfo exists $w]} return
    set format ""
    if {$datasetChoice ne "" && ![catch {set record [::GX::sessionInspectionDataset $datasetChoice]}]} {
        set format [string tolower [dict get $record format]]
    }
    set relevant [expr {$format eq "vti" && $::GX::Native3D::sourceType ne "Plot Dataset 3D graph"}]
    foreach name {scalarLabel scalar isoLabel isovalues isoHelp scalarRange} {
        if {$relevant} {pack $w.$name -anchor w -pady 3 -before $w.openDataset} else {pack forget $w.$name}
    }
    set datasetScalarRange ""
    if {$relevant} {
        set md {}
        catch {set md [::GX::datasetMetadataRead $::GX::currentSession $datasetChoice]}
        foreach key {vti.scalar_range scalar.range scalar_range} {
            if {[dict exists $md $key]} {set datasetScalarRange "Recorded scalar range: [dict get $md $key]"; break}
            if {[dict exists $record $key]} {set datasetScalarRange "Recorded scalar range: [dict get $record $key]"; break}
        }
        if {$datasetScalarRange eq ""} {set datasetScalarRange "Scalar range is not recorded for this Dataset."}
    }
}

proc ::GX::Native3D::sourceTypeSelected {} {
    set w .gxNative3D.body
    if {![winfo exists $w]} return
    set plotting [expr {$::GX::Native3D::sourceType eq "Plot Dataset 3D graph"}]
    foreach widget {datasetLabel dataset openDataset refreshDatasets} {
        if {$plotting} {pack forget $w.$widget} else {pack $w.$widget -anchor w -pady 3}
    }
    refreshVtiControls
    if {$plotting} {pack $w.plotSource -fill x -pady 3} else {pack forget $w.plotSource}
}

proc ::GX::Native3D::refreshPlotSources {} {
    variable plotSources
    variable plotChoice
    set plotSources [dict create]
    if {$::GX::currentSession ne ""} {
        ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
        foreach ref [::GX::PlotDatasetAPIv3::interactiveSources] {
            set label "[dict get $ref graph_id] / [dict get $ref variant_id]"
            dict set plotSources $label $ref
        }
    }
    set labels [lsort -dictionary [dict keys $plotSources]]
    if {[winfo exists .gxNative3D.body.plotSource.graph]} {
        .gxNative3D.body.plotSource.graph configure -values $labels
        .gxNative3D.body.plotSource.create configure -state [expr {[llength $labels] ? "normal" : "disabled"}]
    }
    if {$plotChoice ni $labels} {set plotChoice [expr {[llength $labels] ? [lindex $labels 0] : ""}]}
    return $labels
}

proc ::GX::Native3D::openChosenPlot {} {
    variable plotChoice
    variable plotSources
    if {![dict exists $plotSources $plotChoice]} {error "Select a persistent Plot Dataset 3D graph/Variant."}
    set scene [::GX::PlotDatasetAPIv3::openInteractive [dict get $plotSources $plotChoice]]
    set ::GX::Native3D::representationChoice [dict get $scene representation_id]
    refreshRepresentations
    return $scene
}

proc ::GX::Native3D::refreshRepresentations {} {
    variable representationChoice
    if {$::GX::currentSession eq ""} {set rows {}} else {
        ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
        set rows [::GX::PlotDatasetAPIv3::interactiveRepresentations]
    }
    set ids {}
    foreach row $rows {lappend ids [dict get $row id]}
    if {[winfo exists .gxNative3D.body.plotSource.representation]} {
        .gxNative3D.body.plotSource.representation configure -values $ids
        foreach action {activate sync} {
            .gxNative3D.body.plotSource.$action configure -state [expr {[llength $ids] ? "normal" : "disabled"}]
        }
    }
    if {$representationChoice ni $ids} {set representationChoice [expr {[llength $ids] ? [lindex $ids end] : ""}]}
    representationSelected
    return $rows
}

proc ::GX::Native3D::representationSelected {} {
    variable representationChoice
    set ::GX::Native3D::plotSourceLabel "Source: —"
    set ::GX::Native3D::plotVariantLabel "Variant: —"
    set ::GX::Native3D::plotSyncStatus "Status: —"
    if {$representationChoice eq ""} return
    foreach row [::GX::PlotDatasetAPIv3::interactiveRepresentations] {
        if {[dict get $row id] ne $representationChoice} continue
        set ref [dict get $row plot_ref]
        set ::GX::Native3D::plotSourceLabel "Source: [dict get $ref graph_id]"
        set ::GX::Native3D::plotVariantLabel "Variant: [dict get $ref variant_id]"
        set ::GX::Native3D::plotSyncStatus "Status: [dict get $row status]"
        return
    }
}

proc ::GX::Native3D::openChosenRepresentation {} {
    set id $::GX::Native3D::representationChoice
    if {$id eq ""} {error "Select an interactive representation."}
    set result [::GX::PlotDatasetAPIv3::activateInteractive $id]
    ::GX::viewerOpen viewer.native_3d native_3d [dict create scene_only 1]
    representationSelected
    return $result
}

proc ::GX::Native3D::syncChosenRepresentation {} {
    set id $::GX::Native3D::representationChoice
    if {$id eq ""} {error "Select an interactive representation."}
    set result [::GX::PlotDatasetAPIv3::syncInteractive $id]
    refreshRepresentations
    return $result
}

proc ::GX::Native3D::openChosenDataset {} {
    variable datasetChoice
    if {$datasetChoice eq ""} { error "This Session has no imported 3D Dataset." }
    return [openDataset $datasetChoice $::GX::Native3D::datasetScalar $::GX::Native3D::datasetIsovalues]
}

proc ::GX::Native3D::openDataset {datasetId {scalar ""} {isovalues ""}} {
    variable selectedDatasetId
    variable documentId
    if {$datasetId ni [compatibleDatasetIds]} { error "Dataset '$datasetId' is not a compatible imported 3D Dataset." }
    set payload [::GX::sessionInspectionDatasetPayload $datasetId]
    set selectedDatasetId $datasetId
    set documentId ""
    if {[dict get $payload format] in {vtu vtp vti}} {
        set format [dict get $payload format]
        if {$format eq "vti" && ($scalar eq "" || $isovalues eq "")} {
            error "A VTI scalar grid requires a scalar array and at least one isovalue."
        }
        foreach layer [::GX::viewerLayerIds viewer.native_3d native_3d] {
            ::GX::viewerLayerRemove viewer.native_3d native_3d $layer
        }
        set layerId "dataset_[string map {. _ - _} $datasetId]"
        ::GX::viewerLayerSet viewer.native_3d native_3d $layerId [dict create \
            kind [expr {$format eq "vti" ? "isosurface" : "surface"}] \
            source_mode dataset dataset_id $datasetId format $format \
            scalar_array $scalar isovalues $isovalues \
            source_dataset_id $datasetId source_dataset_sha256 [dict get $payload sha256]]
        ::GX::viewerSceneSet viewer.native_3d native_3d [dict create scene_mode scientific]
        ::GX::sessionPersistenceCommit
        return [::GX::viewerOpen viewer.native_3d native_3d [dict create scene_only 1]]
    }
    ::GX::viewerSceneSet viewer.native_3d native_3d [dict create scene_mode automatic]
    # The canonical Dataset remains authoritative; the worker only builds a
    # derived display cache from the validated Session payload.
    return [openSource [dict get $payload path] 0 [dict get $payload sha256] $datasetId]
}

proc ::GX::Native3D::chooseVtu {} {
    if {$::GX::Native3D::documentId eq "" || $::GX::currentSession ne $::GX::Native3D::session} {
        error "Open a native 3D model in this Session before adding a scientific layer."
    }
    set path [tk_getOpenFile -title "Choose a VTU result in this Session" \
        -initialdir $::GX::currentSession -filetypes {{{VTU result} {.vtu}}}]
    if {$path eq ""} return
    set ::GX::Native3D::scientificPath $path
    set ::GX::Native3D::scientificScalar ""
    set ::GX::Native3D::scientificVector ""
    set w .gxNative3DScientific
    if {[winfo exists $w]} { destroy $w }
    toplevel $w
    wm title $w "Add scientific VTU layer"
    ttk::label $w.path -text $path -wraplength 540
    ttk::label $w.scalarLabel -text "Scalar array (optional):"
    ttk::entry $w.scalar -textvariable ::GX::Native3D::scientificScalar -width 36
    ttk::label $w.vectorLabel -text "Three-component vector array (optional):"
    ttk::entry $w.vector -textvariable ::GX::Native3D::scientificVector -width 36
    ttk::button $w.add -text "Add layer" -command ::GX::Native3D::confirmVtu
    ttk::button $w.cancel -text Cancel -command [list destroy $w]
    pack $w.path $w.scalarLabel $w.scalar $w.vectorLabel $w.vector $w.add $w.cancel \
        -anchor w -padx 12 -pady 4
}

proc ::GX::Native3D::confirmVtu {} {
    if {[catch {addVtuArtifact $::GX::Native3D::scientificPath \
        $::GX::Native3D::scientificScalar $::GX::Native3D::scientificVector} problem]} {
        tk_messageBox -icon error -title "Scientific VTU layer" -message $problem
        return
    }
    destroy .gxNative3DScientific
    refreshScientificLayers
}

proc ::GX::Native3D::chooseDatasetPoints {} {
    if {$::GX::Native3D::documentId eq "" || $::GX::currentSession ne $::GX::Native3D::session} {
        error "Open a native 3D model in this Session before adding Dataset points."
    }
    set ids {}
    foreach id [::GX::sessionInspectionDatasetIds] {
        if {[dict get [::GX::sessionInspectionDataset $id] format] eq "csv"} {lappend ids $id}
    }
    if {![llength $ids]} {error "This Session has no canonical CSV Dataset."}
    set w .gxNative3DDataset
    if {[winfo exists $w]} {destroy $w}
    set ::GX::Native3D::scientificDataset [lindex $ids 0]
    foreach field {scientificX scientificY scientificZ scientificDatasetScalar scientificVx scientificVy scientificVz} {
        set ::GX::Native3D::$field ""
    }
    toplevel $w
    wm title $w "Add Dataset points"
    ttk::label $w.info -text "Select stable variable IDs for X, Y, Z and optional scalar/vector fields."
    pack $w.info -anchor w -padx 10 -pady 5
    ttk::combobox $w.dataset -values $ids -state readonly -textvariable ::GX::Native3D::scientificDataset
    bind $w.dataset <<ComboboxSelected>> ::GX::Native3D::datasetPointVariables
    pack $w.dataset -anchor w -padx 10 -pady 3
    foreach {field label} {scientificX X scientificY Y scientificZ Z scientificDatasetScalar {Scalar (optional)} scientificVx {Vector X (optional)} scientificVy {Vector Y (optional)} scientificVz {Vector Z (optional)}} {
        ttk::frame $w.$field
        ttk::label $w.$field.label -text $label -width 22
        ttk::combobox $w.$field.value -textvariable ::GX::Native3D::$field -state readonly -width 30
        pack $w.$field.label $w.$field.value -side left -padx 3
        pack $w.$field -anchor w -padx 10 -pady 2
    }
    datasetPointVariables
    ttk::button $w.add -text "Add points" -command ::GX::Native3D::confirmDatasetPoints
    ttk::button $w.cancel -text Cancel -command [list destroy $w]
    pack $w.add $w.cancel -anchor w -padx 10 -pady 4
}

proc ::GX::Native3D::datasetPointVariables {} {
    set ids {}
    foreach variable [::GX::datasetVariableSchemaV3 $::GX::Native3D::scientificDataset] {
        if {[dict get $variable enabled] && [dict get $variable value_kind] ne "text" &&
            [dict get $variable rank] == 1} {lappend ids [dict get $variable variable_id]}
    }
    set w .gxNative3DDataset
    foreach field {scientificX scientificY scientificZ scientificDatasetScalar scientificVx scientificVy scientificVz} {
        $w.$field.value configure -values [concat {{}} $ids]
        if {[set ::GX::Native3D::$field] ni $ids} {set ::GX::Native3D::$field ""}
    }
}

proc ::GX::Native3D::confirmDatasetPoints {} {
    if {[catch {addDatasetPoints $::GX::Native3D::scientificDataset \
        $::GX::Native3D::scientificX $::GX::Native3D::scientificY $::GX::Native3D::scientificZ \
        $::GX::Native3D::scientificDatasetScalar \
        [list $::GX::Native3D::scientificVx $::GX::Native3D::scientificVy $::GX::Native3D::scientificVz]} problem]} {
        tk_messageBox -icon error -title "Dataset point layer" -message $problem
        return
    }
    destroy .gxNative3DDataset
    refreshScientificLayers
}

proc ::GX::Native3D::choosePatternRegion {} {
    if {$::GX::Native3D::selectedCellId eq ""} {
        error "At Full LOD, click a source mesh cell in the native window first."
    }
    set w .gxNative3DPattern
    if {[winfo exists $w]} {destroy $w}
    toplevel $w
    wm title $w "Pattern a selected mesh patch"
    ttk::label $w.info -text "Source cell $::GX::Native3D::selectedCellId. Radius selects a local patch; placements reuse it without changing the source model. Circular uses rings/positions and radius/angle steps. Explicit uses a Session CSV with an x,y,z header." -wraplength 520
    pack $w.info -anchor w -padx 10 -pady 5
    ttk::frame $w.layout
    ttk::label $w.layout.label -text "Placement layout" -width 28
    ttk::combobox $w.layout.value -textvariable ::GX::Native3D::patternLayout \
        -values {rectangular linear circular explicit} -state readonly -width 15
    pack $w.layout.label $w.layout.value -side left -padx 3
    pack $w.layout -anchor w -padx 10 -pady 2
    foreach {field label} {patternRadius {Patch radius (model units)} patternCountX {Columns} patternCountY {Rows} patternStepX {X spacing} patternStepY {Y spacing}} {
        ttk::frame $w.$field
        ttk::label $w.$field.label -text $label -width 28
        ttk::entry $w.$field.value -textvariable ::GX::Native3D::$field -width 15
        pack $w.$field.label $w.$field.value -side left -padx 3
        pack $w.$field -anchor w -padx 10 -pady 2
    }
    ttk::frame $w.placements
    ttk::entry $w.placements.path -textvariable ::GX::Native3D::patternPlacementPath -width 45
    ttk::button $w.placements.browse -text "Session CSV..." -command {
        set chosen [tk_getOpenFile -title "Choose Session placement CSV" \
            -initialdir $::GX::currentSession -filetypes {{{CSV placements} {.csv}}}]
        if {$chosen ne ""} {set ::GX::Native3D::patternPlacementPath $chosen}
    }
    pack $w.placements.path $w.placements.browse -side left -padx 3
    pack $w.placements -anchor w -padx 10 -pady 2
    ttk::button $w.add -text "Create display pattern" -command ::GX::Native3D::confirmPatternRegion
    ttk::button $w.cancel -text Cancel -command [list destroy $w]
    pack $w.add $w.cancel -anchor w -padx 10 -pady 4
}

proc ::GX::Native3D::confirmPatternRegion {} {
    set countX $::GX::Native3D::patternCountX
    set countY $::GX::Native3D::patternCountY
    if {$::GX::Native3D::patternLayout eq "explicit"} {set countX 1; set countY 1}
    if {[catch {addPatternRegion $::GX::Native3D::selectedCellId \
        $::GX::Native3D::patternRadius $countX $countY \
        $::GX::Native3D::patternStepX $::GX::Native3D::patternStepY \
        $::GX::Native3D::patternLayout $::GX::Native3D::patternPlacementPath} problem]} {
        tk_messageBox -icon error -title "Display pattern" -message $problem
        return
    }
    destroy .gxNative3DPattern
}

proc ::GX::Native3D::sendPatternRegion {id details} {
    set layout [expr {[dict exists $details layout] ? [dict get $details layout] : "rectangular"}]
    set command "ADD_PATTERN_REGION $id [dict get $details source_cell] [dict get $details radius] \
        [dict get $details count_x] [dict get $details count_y] \
        [dict get $details step_x] [dict get $details step_y] $layout"
    if {$layout eq "explicit"} {
        set verified [::GX::viewerArtifactResolve [dict get $details placement_path] \
            [dict get $details placement_sha256]]
        append command " [::binary encode hex [encoding convertto utf-8 $verified]]"
    }
    send $command
}

proc ::GX::Native3D::addPatternRegion {cell radius countX countY stepX stepY {layout rectangular} {placementsPath ""}} {
    if {$::GX::Native3D::documentId eq "" || $::GX::currentSession ne $::GX::Native3D::session ||
        $::GX::Native3D::host eq ""} {error "Open a Native 3D model in a Session first."}
    if {![string is integer -strict $cell] || $cell < 0 ||
        ![string is integer -strict $countX] || ![string is integer -strict $countY] ||
        $countX < 1 || $countY < 1 || $countX*$countY > 1000000} {
        error "Pattern needs a source cell and 1..1,000,000 grid placements."
    }
    foreach value [list $radius $stepX $stepY] {
        if {![string is double -strict $value] ||
            [catch {expr {abs(double($value)) < Inf}} finite] || !$finite || $value == 0} {
            error "Pattern radius and spacing must be finite and nonzero."
        }
    }
    if {$radius <= 0} {error "Pattern patch radius must be positive."}
    if {$layout ni {rectangular linear circular explicit} ||
        ($layout eq "linear" && $countY != 1)} {
        error "Choose rectangular, linear (one row), circular or explicit placement."
    }
    if {[dict size $::GX::Native3D::patternPending]} {
        error "Wait for the current display pattern before adding another."
    }
    set id [format "pattern_%x" [clock microseconds]]
    set details [dict create source_cell $cell radius $radius count_x $countX count_y $countY \
        step_x $stepX step_y $stepY layout $layout visible 1 opacity 1.0]
    if {$layout eq "explicit"} {
        set path [file normalize $placementsPath]
        set root [file normalize $::GX::Native3D::session]
        if {$countX != 1 || $countY != 1 || ![string match "$root/*" $path] ||
            ![file isfile $path] || [string tolower [file extension $path]] ne ".csv"} {
            error "Choose a placement CSV already stored in this Session; explicit counts must be 1."
        }
        set relative [string range $path [expr {[string length $root]+1}] end]
        set artifact [::GX::viewerArtifactRegister $relative]
        dict set details placement_path $relative
        dict set details placement_sha256 [dict get $artifact sha256]
    }
    set ::GX::Native3D::patternPending [dict create id $id details $details \
        document_id $::GX::Native3D::documentId session $::GX::Native3D::session]
    set ::GX::Native3D::requestedLod full
    if {[catch {
        send {LOD full}
        sendPatternRegion $id $details
    } problem options]} {
        set ::GX::Native3D::patternPending [dict create]
        return -options $options $problem
    }
    return $id
}

proc ::GX::Native3D::patternReady {id} {
    set pending $::GX::Native3D::patternPending
    if {![dict size $pending] || [dict get $pending id] ne $id} return
    set ::GX::Native3D::patternPending [dict create]
    if {$::GX::currentSession ne [dict get $pending session] ||
        $::GX::Native3D::documentId ne [dict get $pending document_id]} return
    set state [dict get [::GX::interactiveDocumentRead [dict get $pending document_id]] payload]
    dict set state pattern_regions $id [dict get $pending details]
    ::GX::interactiveDocumentUpdate [dict get $pending document_id] $state
    ::GX::sessionPersistenceCommit
    refreshScientificLayers
}

proc ::GX::Native3D::proposeRepeats {} {
    if {$::GX::Native3D::host eq "" || $::GX::Native3D::selectedCellId eq "" ||
        $::GX::Native3D::documentId eq "" || $::GX::currentSession ne $::GX::Native3D::session} {
        error "Open a mesh in a Session and pick one component cell first."
    }
    set ::GX::Native3D::repeatProposalEvent ""
    set ::GX::Native3D::repeatStatus "Finding matching connected components..."
    set ::GX::Native3D::requestedLod full
    send {LOD full}
    send "PROPOSE_REPEATS $::GX::Native3D::selectedCellId"
}

proc ::GX::Native3D::acceptRepeats {} {
    set event $::GX::Native3D::repeatProposalEvent
    if {$event eq "" || [dict size $::GX::Native3D::repeatPending]} {
        error "Wait for a repeat proposal before accepting matches."
    }
    set cell [eventNumber $event source_cell]
    set ::GX::Native3D::repeatPending [dict create source_cell $cell \
        document_id $::GX::Native3D::documentId session $::GX::Native3D::session]
    if {[catch {send {ACCEPT_REPEATS}} problem options]} {
        set ::GX::Native3D::repeatPending [dict create]
        return -options $options $problem
    }
}

proc ::GX::Native3D::rejectRepeats {} {
    if {$::GX::Native3D::repeatProposalEvent eq ""} return
    send {REJECT_REPEATS}
    set ::GX::Native3D::repeatProposalEvent ""
    set ::GX::Native3D::repeatStatus "Repeat proposal rejected."
}

proc ::GX::Native3D::repeatReady {line} {
    set ::GX::Native3D::repeatReadyEvent $line
    set ::GX::Native3D::repeatStatus "[eventNumber $line instances] matched components use one representative mesh."
    set pending $::GX::Native3D::repeatPending
    set ::GX::Native3D::repeatPending [dict create]
    if {![dict size $pending] ||
        $::GX::currentSession ne [dict get $pending session] ||
        $::GX::Native3D::documentId ne [dict get $pending document_id]} return
    set state [dict get [::GX::interactiveDocumentRead [dict get $pending document_id]] payload]
    dict set state repeat_component [dict create source_cell [dict get $pending source_cell] \
        instances [eventNumber $line instances] prototype_triangles [eventNumber $line prototype_triangles]]
    ::GX::interactiveDocumentUpdate [dict get $pending document_id] $state
    ::GX::sessionPersistenceCommit
}

proc ::GX::Native3D::scientificLayerIds {state} {
    set ids {}
    foreach section {vtu_layers dataset_layers pattern_regions} {
        if {[dict exists $state $section]} {lappend ids {*}[dict keys [dict get $state $section]]}
    }
    return $ids
}

proc ::GX::Native3D::scientificLayerSection {state id} {
    foreach section {vtu_layers dataset_layers pattern_regions} {
        if {[dict exists $state $section $id]} {return $section}
    }
    error "Selected scientific layer is unavailable."
}

proc ::GX::Native3D::refreshScientificLayers {} {
    set w .gxNative3D.body.scientific.layers
    if {![winfo exists $w]} return
    $w delete 0 end
    if {$::GX::Native3D::documentId eq ""} return
    if {[catch {set saved [dict get [::GX::interactiveDocumentRead \
        $::GX::Native3D::documentId] payload]}]} return
    foreach id [scientificLayerIds $saved] {
        set section [scientificLayerSection $saved $id]
        set details [dict get $saved $section $id]
        set label [expr {$section eq "vtu_layers" ? [file tail [dict get $details resource_path]] :
            ($section eq "dataset_layers" ? [dict get $details dataset_id] : "Pattern from cell [dict get $details source_cell]")}]
        append label " ($id)"
        $w insert end $label
    }
}

proc ::GX::Native3D::scientificLayerSelected {} {
    set w .gxNative3D.body.scientific.layers
    set selection [$w curselection]
    if {![llength $selection]} { set ::GX::Native3D::selectedScientificLayer ""; return }
    set saved [dict get [::GX::interactiveDocumentRead $::GX::Native3D::documentId] payload]
    set ids [scientificLayerIds $saved]
    set id [lindex $ids [lindex $selection 0]]
    set ::GX::Native3D::selectedScientificLayer $id
    set details [dict get $saved [scientificLayerSection $saved $id] $id]
    set ::GX::Native3D::selectedScientificVisible [expr {![dict exists $details visible] || [dict get $details visible]}]
    set ::GX::Native3D::selectedScientificOpacity [expr {[dict exists $details opacity] ? [dict get $details opacity] : 1.0}]
}

proc ::GX::Native3D::setScientificVisibility {} {
    set id $::GX::Native3D::selectedScientificLayer
    if {$id eq ""} return
    set saved [dict get [::GX::interactiveDocumentRead $::GX::Native3D::documentId] payload]
    set section [scientificLayerSection $saved $id]
    dict set saved $section $id visible $::GX::Native3D::selectedScientificVisible
    ::GX::interactiveDocumentUpdate $::GX::Native3D::documentId $saved
    ::GX::sessionPersistenceCommit
    send "LAYER_VISIBLE $id $::GX::Native3D::selectedScientificVisible"
}

proc ::GX::Native3D::setScientificOpacity {} {
    set id $::GX::Native3D::selectedScientificLayer
    if {$id eq ""} return
    set opacity $::GX::Native3D::selectedScientificOpacity
    if {![string is double -strict $opacity] ||
        [catch {expr {double($opacity) >= 0 && double($opacity) <= 1 && abs(double($opacity)) < Inf}} valid] || !$valid} {
        error "Scientific layer opacity must be between 0 and 1."
    }
    set saved [dict get [::GX::interactiveDocumentRead $::GX::Native3D::documentId] payload]
    set section [scientificLayerSection $saved $id]
    dict set saved $section $id opacity $opacity
    if {$section ne "pattern_regions"} {
        set layer [::GX::viewerLayerGet viewer.native_3d native_3d $id]
        dict set layer opacity $opacity
        ::GX::viewerLayerSet viewer.native_3d native_3d $id $layer
    }
    ::GX::interactiveDocumentUpdate $::GX::Native3D::documentId $saved
    ::GX::sessionPersistenceCommit
    send "LAYER_OPACITY $id [format %.3f $opacity]"
}

proc ::GX::Native3D::removeScientificLayer {} {
    set id $::GX::Native3D::selectedScientificLayer
    if {$id eq ""} return
    set saved [dict get [::GX::interactiveDocumentRead $::GX::Native3D::documentId] payload]
    set section [scientificLayerSection $saved $id]
    dict unset saved $section $id
    ::GX::interactiveDocumentUpdate $::GX::Native3D::documentId $saved
    ::GX::viewerLayerRemove viewer.native_3d native_3d $id
    ::GX::sessionPersistenceCommit
    send "LAYER_REMOVE $id"
    set ::GX::Native3D::selectedScientificLayer ""
    refreshScientificLayers
}

proc ::GX::Native3D::assemblyObjectSelected {} {
    set w .gxNative3D.body.assembly.parts
    set selection [$w curselection]
    if {![llength $selection]} {set ::GX::Native3D::selectedAssemblyObject ""; return}
    set index [lindex $::GX::Native3D::assemblyObjectIds [lindex $selection 0]]
    set ::GX::Native3D::selectedAssemblyObject $index
    set saved [dict get [::GX::interactiveDocumentRead $::GX::Native3D::documentId] payload]
    set ::GX::Native3D::selectedAssemblyVisible [expr {
        ![dict exists $saved object_visibility $index] || [dict get $saved object_visibility $index]
    }]
}

proc ::GX::Native3D::setAssemblyVisibility {} {
    set index $::GX::Native3D::selectedAssemblyObject
    if {$index eq ""} return
    if {$index ni $::GX::Native3D::assemblyObjectIds} {error "Selected assembly part is unavailable."}
    set saved [dict get [::GX::interactiveDocumentRead $::GX::Native3D::documentId] payload]
    dict set saved object_visibility $index $::GX::Native3D::selectedAssemblyVisible
    ::GX::interactiveDocumentUpdate $::GX::Native3D::documentId $saved
    ::GX::sessionPersistenceCommit
    send "OBJECT_VISIBLE $index $::GX::Native3D::selectedAssemblyVisible"
}

proc ::GX::Native3D::setOpacity {value} {
    if {![string is double -strict $value] || $value < 0 || $value > 1} {error "Opacity must be between 0 and 1"}
    set ::GX::Native3D::opacity $value
    send "OPACITY [format %.3f $value]"
}

proc ::GX::Native3D::chooseBackground {} {
    set hex "#"
    foreach channel [split $::GX::Native3D::backgroundRgb {;}] {
        append hex [format %02x [expr {int(round(255.0 * $channel))}]]
    }
    set chosen [tk_chooseColor -title "Native viewer background" -initialcolor $hex]
    if {![regexp {^#[0-9a-fA-F]{6}$} $chosen]} return
    set components {}
    foreach offset {1 3 5} {
        scan [string range $chosen $offset [expr {$offset + 1}]] %x byte
        lappend components [format %.6f [expr {$byte / 255.0}]]
    }
    set ::GX::Native3D::backgroundRgb [join $components {;}]
    setBackground [join $components {;}]
}

proc ::GX::Native3D::clipChanged {args} {
    if {$::GX::Native3D::host eq ""} return
    if {!$::GX::Native3D::clippingEnabled} { send {CLIP OFF}; return }
    send "CLIP $::GX::Native3D::clippingAxis [format %.3f $::GX::Native3D::clippingFraction]"
}

proc ::GX::Native3D::saveScreenshot {} {
    if {$::GX::Native3D::host eq ""} { error "Open a 3D model before saving its view." }
    set path [tk_getSaveFile -title "Save native 3D view" -defaultextension .png \
        -filetypes {{{PNG image} {.png}}}]
    if {$path ne ""} { screenshot $path }
}

proc ::GX::Native3D::sendVtuLayer {layerId details} {
    if {$::GX::Native3D::host eq ""} { error "Open a 3D model before adding a scientific layer." }
    set relative [dict get $details resource_path]
    set verified [::GX::viewerArtifactResolve $relative [dict get $details sha256]]
    set pathHex [::binary encode hex [encoding convertto utf-8 $verified]]
    set scalar [dict get $details scalar_array]
    set vector [dict get $details vector_array]
    set scalarHex [expr {$scalar eq "" ? "-" : [::binary encode hex [encoding convertto utf-8 $scalar]]}]
    set vectorHex [expr {$vector eq "" ? "-" : [::binary encode hex [encoding convertto utf-8 $vector]]}]
    send "ADD_VTU $layerId $pathHex $scalarHex $vectorHex"
}

proc ::GX::Native3D::addVtuArtifact {path {scalarArray ""} {vectorArray ""}} {
    variable documentId
    variable session
    if {$documentId eq "" || $::GX::currentSession ne $session || $::GX::Native3D::host eq ""} {
        error "Open a Native 3D Viewer in a Session before adding a scientific layer."
    }
    set path [file normalize $path]
    set root [file normalize $session]
    if {![string match "$root/*" $path] || ![file isfile $path] ||
        [string tolower [file extension $path]] ne ".vtu"} {
        error "Choose an existing VTU result already stored inside this Session."
    }
    foreach name [list $scalarArray $vectorArray] {
        if {[regexp {[\r\n\x00]} $name] || [string length $name] > 256} {
            error "Scientific array names must be single-line and at most 256 characters."
        }
    }
    set relative [string range $path [expr {[string length $root] + 1}] end]
    set artifact [::GX::viewerArtifactRegister $relative]
    set layerId [format "vtu_%x" [clock microseconds]]
    set details [dict create resource_path $relative sha256 [dict get $artifact sha256] \
        scalar_array $scalarArray vector_array $vectorArray visible 1 opacity 1.0]
    set oldState [dict get [::GX::interactiveDocumentRead $documentId] payload]
    set state $oldState
    dict set state vtu_layers $layerId $details
    try {
        ::GX::viewerLayerSet viewer.native_3d native_3d $layerId [dict create \
            kind surface source_mode artifact resource_path $relative \
            sha256 [dict get $artifact sha256] format vtu format_version 1]
        foreach {kind name} [list scalar $scalarArray vector $vectorArray] {
            if {$name eq ""} continue
            ::GX::viewerAttributeSet viewer.native_3d native_3d $layerId $kind [dict create \
                kind $kind resource_path $relative sha256 [dict get $artifact sha256] \
                format vtu format_version 1]
        }
        ::GX::interactiveDocumentUpdate $documentId $state
        ::GX::sessionPersistenceCommit
        sendVtuLayer $layerId $details
    } on error {problem options} {
        ::GX::viewerLayerRemove viewer.native_3d native_3d $layerId
        catch {::GX::interactiveDocumentUpdate $documentId $oldState}
        catch {::GX::sessionPersistenceCommit}
        return -options $options $problem
    }
    return $layerId
}

proc ::GX::Native3D::sendDatasetLayer {layerId details {primitive points}} {
    if {$::GX::Native3D::host eq ""} {error "Open a 3D model before adding Dataset points."}
    set dataset [dict get $details dataset_id]
    set payload [::GX::sessionInspectionDatasetPayload $dataset]
    if {[dict get $payload format] ne "csv"} {
        error "Native Dataset points require a canonical CSV Dataset."
    }
    set path [dict get $payload path]
    if {![string equal -nocase [dict get $payload sha256] [dict get $details sha256]]} {
        error "Native Dataset point source is missing or has changed."
    }
    set columns {}
    foreach variable [concat [dict get $details coordinates] \
        [list [dict get $details scalar_variable]] [dict get $details vector_variables]] {
        if {$variable eq ""} {lappend columns 0; continue}
        set record [::GX::datasetVariableV3ById $dataset $variable]
        if {![dict get $record enabled] || [dict get $record rank] != 1} {
            error "Dataset variable $variable is disabled or not a one-dimensional column."
        }
        set column [dict get $record source_column]
        if {![string is integer -strict $column] || $column < 1 || $column > 4096} {
            error "Dataset variable $variable has no valid canonical CSV column."
        }
        lappend columns $column
    }
    set pathHex [::binary encode hex [encoding convertto utf-8 $path]]
    send "ADD_DATASET_POINTS $layerId $pathHex [join $columns { }] $primitive"
}

proc ::GX::Native3D::addDatasetPoints {dataset x y z {scalar ""} {vectors {"" "" ""}}} {
    variable documentId
    variable session
    if {$documentId eq "" || $::GX::currentSession ne $session || $::GX::Native3D::host eq ""} {
        error "Open a Native 3D Viewer in a Session before adding Dataset points."
    }
    if {[catch {set payload [::GX::sessionInspectionDatasetPayload $dataset]}] ||
        [dict get $payload format] ne "csv"} {
        error "Choose a canonical CSV Dataset in the current Session."
    }
    if {[llength $vectors] != 3} {error "Vector fields require three variable IDs."}
    if {([lindex $vectors 0] eq "") != ([lindex $vectors 1] eq "") ||
        ([lindex $vectors 0] eq "") != ([lindex $vectors 2] eq "")} {
        error "Select all three vector components or none."
    }
    foreach variable [concat [list $x $y $z $scalar] $vectors] {
        if {$variable eq ""} continue
        set record [::GX::datasetVariableV3ById $dataset $variable]
        if {![dict get $record enabled] || [dict get $record rank] != 1 ||
            [dict get $record value_kind] eq "text"} {
            error "Dataset variable $variable must be an enabled numeric column."
        }
    }
    if {$x eq "" || $y eq "" || $z eq ""} {error "Select X, Y and Z Dataset variables."}
    set path [dict get $payload path]
    set layerId [format "dataset_%x" [clock microseconds]]
    set details [dict create dataset_id $dataset sha256 [dict get $payload sha256] \
        coordinates [list $x $y $z] scalar_variable $scalar vector_variables $vectors visible 1 opacity 1.0]
    set oldState [dict get [::GX::interactiveDocumentRead $documentId] payload]
    set state $oldState
    dict set state dataset_layers $layerId $details
    try {
        ::GX::viewerLayerSet viewer.native_3d native_3d $layerId [dict create \
            kind points source_mode dataset dataset_id $dataset x_variable_id $x \
            y_variable_id $y z_variable_id $z]
        if {$scalar ne ""} {
            ::GX::viewerAttributeSet viewer.native_3d native_3d $layerId scalar \
                [dict create kind scalar variable_ids $scalar]
        }
        if {[lindex $vectors 0] ne ""} {
            ::GX::viewerAttributeSet viewer.native_3d native_3d $layerId vector \
                [dict create kind vector variable_ids [join $vectors {;}]]
        }
        ::GX::interactiveDocumentUpdate $documentId $state
        ::GX::sessionPersistenceCommit
        sendDatasetLayer $layerId $details
    } on error {problem options} {
        ::GX::viewerLayerRemove viewer.native_3d native_3d $layerId
        catch {::GX::interactiveDocumentUpdate $documentId $oldState}
        catch {::GX::sessionPersistenceCommit}
        return -options $options $problem
    }
    refreshScientificLayers
    return $layerId
}

proc ::GX::Native3D::chooseRelink {savedId expected mode} {
    set path [tk_getOpenFile -title "Locate the original 3D model" \
        -filetypes {{{3D models} {.stl .obj .step .stp}} {{All files} *}}]
    if {$path ne ""} { relinkSource $savedId $path $expected $mode }
}

proc ::GX::Native3D::relinkSource {savedId path expected mode} {
    variable documentId
    if {$mode ni {external_reference session_artifact}} { error "Unknown native 3D source mode." }
    set saved [dict get [::GX::interactiveDocumentRead $savedId] payload]
    if {[dict get $saved source_sha256] ne $expected || [dict get $saved source_mode] ne $mode} {
        error "Native 3D relink request does not match the saved viewer document."
    }
    set documentId $savedId
    return [openSource $path [expr {$mode eq "session_artifact"}] $expected]
}

proc ::GX::Native3D::openSource {path {makePortable 0} {expected ""} {datasetId ""}} {
    variable worker
    variable source
    variable session
    variable portable
    variable expectedSha
    variable status
    variable progress
    variable cacheKey
    variable sourceSha
    variable documentId
    variable cancelStage
    variable selectedDatasetId
    set ::GX::Native3D::sceneOnly 0
    set ::GX::Native3D::repeatProposalEvent ""
    set ::GX::Native3D::repeatReadyEvent ""
    set ::GX::Native3D::repeatPending [dict create]
    set ::GX::Native3D::repeatStatus "No repeat proposal."
    set ::GX::Native3D::patternPending [dict create]
    if {$worker ne ""} { error "A Native 3D preprocessing job is already running." }
    if {$::GX::currentSession eq "" || ![file isdirectory $::GX::currentSession]} {
        error "Open a Session before using the Native 3D Viewer."
    }
    set path [file normalize $path]
    if {![file isfile $path]} { error "The 3D source does not exist: $path" }
    if {[string tolower [file extension $path]] ni {.stl .obj .step .stp}} {
        error "Choose an STL, OBJ or STEP model."
    }
    if {[regexp {[\r\n]} $path]} { error "3D source path may not contain a line break." }
    if {$expected ne "" && ![regexp {^[0-9a-fA-F]{64}$} $expected]} { error "Invalid expected 3D source hash." }
    if {$datasetId ne ""} {
        set payload [::GX::sessionInspectionDatasetPayload $datasetId]
        if {[dict get $payload path] ne $path ||
            ![string equal -nocase [dict get $payload sha256] $expected]} {
            error "Dataset '$datasetId' no longer matches its selected payload."
        }
    }
    set selectedDatasetId $datasetId
    set source $path
    set session [file normalize $::GX::currentSession]
    set portable [expr {$makePortable ? 1 : 0}]
    set expectedSha [string tolower $expected]
    set cacheKey ""
    set sourceSha ""
    set cancelStage ""
    set ::GX::Native3D::renderMode ""
    set ::GX::Native3D::capabilitiesEvent ""
    set ::GX::Native3D::benchmarkEvent ""
    set ::GX::Native3D::screenshotEvent ""
    set ::GX::Native3D::hostEventsRaw {}
    set ::GX::Native3D::operationStartedMs [clock milliseconds]
    set ::GX::Native3D::previewReadyMs 0
    set ::GX::Native3D::cacheReadyMs 0
    set ::GX::Native3D::cacheHitMs 0
    set ::GX::Native3D::firstInteractiveMs 0
    set ::GX::Native3D::workerPeakMiB 0
    if {$expected eq ""} { set documentId "" }
    set progress "Reading source and preparing display cache..."
    set status running
    panel
    set command [list [binary gx3d-worker] $source [cacheRoot]]
    if {$portable} { lappend command [file join $session resources native3d] }
    set budget [expr {[info exists ::GX::moduleCfg(viewer.native_3d,memory_budget_mib)] ? $::GX::moduleCfg(viewer.native_3d,memory_budget_mib) : 4096}]
    set worker [processOpen $command r [dict create GX3D_MEMORY_BUDGET_MIB $budget]]
    refreshCancelAction
    fileevent $worker readable ::GX::Native3D::workerReadable
    return $worker
}

proc ::GX::Native3D::openScene {scene} {
    variable host
    variable worker
    variable session
    variable sceneOnly
    variable pendingScene
    variable sceneRestoring
    variable documentId
    if {$::GX::currentSession eq ""} {error "A Session is required for a scientific 3D scene."}
    if {$worker ne ""} {error "A Native 3D preprocessing job is still running."}
    if {$host ne ""} {
        set previous $host
        fileevent $previous readable {}
        catch {puts $previous QUIT; flush $previous}
        catch {close $previous}
        set host ""
    }
    set documentId ""
    set session [file normalize $::GX::currentSession]
    set sceneOnly 1
    set sceneRestoring 1
    set pendingScene $scene
    set ::GX::Native3D::layerEvents [dict create]
    set ::GX::Native3D::status running
    set ::GX::Native3D::progress "Opening scientific 3D scene..."
    panel
    startHost [list [binary gx3d-host] --scene]
    return $host
}

proc ::GX::Native3D::renderSceneLayers {} {
    variable pendingScene
    variable sceneRestoring
    set layers [dict get $pendingScene layers]
    set ordered {}
    dict for {id layer} $layers {lappend ordered [list [dict get $layer layer_order] $id]}
    foreach item [lsort -integer -index 0 $ordered] {
        set id [lindex $item 1]
        set layer [dict get $layers $id]
        set path [expr {[dict get $layer source_mode] eq "dataset" ?
            [dict get $layer dataset_path] : [dict get $layer absolute_path]}]
        set format [string tolower [string range [file extension $path] 1 end]]
        if {$format in {vtu vtp vti}} {
            set scalar [dict get $layer scalar_array]
            set scalarHex "-"
            if {$scalar ne ""} {set scalarHex [::binary encode hex [encoding convertto utf-8 $scalar]]}
            set vector [dict get $layer vector_array]
            set vectorHex "-"
            if {$vector ne ""} {set vectorHex [::binary encode hex [encoding convertto utf-8 $vector]]}
            set pathHex [::binary encode hex [encoding convertto utf-8 $path]]
            set levels [expr {[dict get $layer isovalues] eq "" ? "-" :
                [join [split [dict get $layer isovalues] {;}] ,]}]
            set radius [dict get $layer radius_array]
            set radiusHex "-"
            if {$radius ne ""} {set radiusHex [::binary encode hex [encoding convertto utf-8 $radius]]}
            send "ADD_SCIENTIFIC $id $pathHex [dict get $layer kind] $scalarHex $vectorHex $levels $radiusHex [dict get $layer tube_radius]"
        } elseif {$format eq "csv" && [dict get $layer kind] in {points trajectory}} {
            set dataset [dict get $layer dataset_id]
            set coords [list [dict get $layer x_variable_id] [dict get $layer y_variable_id] [dict get $layer z_variable_id]]
            set scalar ""
            if {[dict exists $layer attributes scalar]} {
                set scalar [lindex [split [dict get $layer attributes scalar variable_ids] {;}] 0]
            }
            sendDatasetLayer $id [dict create dataset_id $dataset \
                sha256 [dict get [::GX::sessionInspectionDatasetPayload $dataset] sha256] \
                coordinates $coords scalar_variable $scalar vector_variables {"" "" ""}] \
                [dict get $layer kind]
        } else {error "Native scene cannot render $format [dict get $layer kind] layer '$id'."}
        if {![dict get $layer visible]} {send "LAYER_VISIBLE $id 0"}
        if {[dict get $layer opacity] != 1} {send "LAYER_OPACITY $id [dict get $layer opacity]"}
        if {[dict get $layer representation] ne "surface"} {
            send "LAYER_MODE $id [dict get $layer representation]"
        }
    }
    set view [dict get $pendingScene view]
    send "BACKGROUND [join [split [dict get $view background_rgb] {;}] { }]"
    send "LIGHTING [dict get $view lighting]"
    send "PROJECTION [dict get $view projection]"
    if {[dict get $view clipping_planes] ne ""} {
        set plane [lindex [split [dict get $view clipping_planes] {;}] 0]
        send "CLIP_PLANE [join [split $plane ,] { }]"
    }
    if {[dict get $view camera_position] ne {0;0;1} || [dict get $view camera_target] ne {0;0;0}} {
        set camera {}
        foreach field {camera_position camera_target camera_up} {
            lappend camera {*}[split [dict get $view $field] {;}]
        }
        lappend camera 1 30 [dict get $view projection]
        send "SET_CAMERA [join $camera { }]"
    }
    set sceneRestoring 0
}

proc ::GX::Native3D::recordSource {} {
    variable source
    variable session
    variable portable
    variable cacheKey
    variable sourceSha
    variable documentId
    variable requestedLod
    variable selectedDatasetId
    if {$::GX::currentSession ne $session} return
    set format [string tolower [string range [file extension $source] 1 end]]
    if {$selectedDatasetId ne ""} {
        set payload [::GX::sessionInspectionDatasetPayload $selectedDatasetId]
        if {[dict get $payload path] ne $source ||
            ![string equal -nocase [dict get $payload sha256] $sourceSha]} {
            error "Dataset '$selectedDatasetId' changed during 3D preprocessing."
        }
        set relative [dict get $payload relative_path]
        set artifactFormat [dict get $payload format]
        set mode dataset
    } elseif {$portable} {
        set relative [file join resources native3d $sourceSha [file tail $source]]
        set artifact [::GX::viewerArtifactRegister $relative]
        set artifactFormat $format
        set mode session_artifact
    } else {
        set relative [file join resources native3d "$sourceSha.ref"]
        set ref [file join $session $relative]
        file mkdir [file dirname $ref]
        set f [open $ref w]
        fconfigure $f -encoding utf-8 -translation lf
        try {
            puts $f "GX-TXT external 3D source reference v1"
            ::GX::putKV $f sha256 $sourceSha
            ::GX::putKV $f size_bytes [file size $source]
            ::GX::putKV $f format $format
            ::GX::putKV $f path_hint $source
        } finally { close $f }
        set artifact [::GX::viewerArtifactRegister $relative]
        set artifactFormat gxtxt.external_3d_reference
        set mode external_reference
    }
    set state [dict create viewer_id native_3d source_mode $mode source_dataset_id $selectedDatasetId source_path_hint $source \
        source_resource $relative source_sha256 $sourceSha source_size [file size $source] \
        source_format $format cache_key $cacheKey cache_format_version 1 \
        requested_lod $requestedLod automatic_interaction_lod 1 \
        camera_position {} camera_target {} camera_up {} \
        projection $::GX::Native3D::projection parallel_scale {} view_angle_deg {} \
        display_mode $::GX::Native3D::displayMode \
        visible 1 opacity $::GX::Native3D::opacity \
        lighting $::GX::Native3D::lighting background_rgb $::GX::Native3D::backgroundRgb \
        clipping_enabled 0 clipping_axis z clipping_fraction 0.5 \
        notes "" imported_at [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]]
    dict set state vtu_layers [dict create]
    set item [::GX::interactiveDocumentCreate viewer.native_3d native_3d \
        gxtxt.native3d.viewer_state 1.0 $state]
    set documentId [dict get $item id]
    set layerId "mesh_[string range $sourceSha 0 15]"
    if {$mode eq "dataset"} {
        ::GX::viewerLayerSet viewer.native_3d native_3d $layerId [dict create \
            kind triangle_mesh source_mode dataset dataset_id $selectedDatasetId format $artifactFormat]
    } else {
        ::GX::viewerLayerSet viewer.native_3d native_3d $layerId [dict create \
            kind triangle_mesh source_mode artifact resource_path $relative \
            sha256 [dict get $artifact sha256] format $artifactFormat format_version 1]
    }
    ::GX::sessionPersistenceCommit
}

proc ::GX::Native3D::workerReadable {} {
    variable worker
    variable status
    variable progress
    variable sourceSha
    variable cacheKey
    variable expectedSha
    variable session
    variable documentId
    if {$worker eq ""} return
    while {[gets $worker line] >= 0} {
        if {$status in {cancelled failed}} continue
        set event [eventValue $line event]
        switch -- $event {
            portable_progress { set progress "Copying original model into Session..." }
            portable_ready { set progress "Portable source verified; preparing display cache..." }
            start - cache_hit {
                set sourceSha [eventValue $line sha256]
                set cacheKey [eventValue $line key]
                if {$expectedSha ne "" && $sourceSha ne $expectedSha} {
                    set progress "The source hash differs from the Session reference. Select the matching original model."
                    cancel
                    set status failed
                    set progress "The source hash differs from the Session reference. Select the matching original model."
                    return
                }
                if {$event eq "cache_hit"} {
                    set ::GX::Native3D::cacheHitMs [clock milliseconds]
                    set progress "Reusing display cache."
                    set status ready
                    if {[catch {
                        if {$documentId eq ""} { recordSource } else { updateRelink }
                        openHost
                    } problem]} { set status failed; set progress "Native viewer failed: $problem" }
                }
            }
            parsed { set progress "Source model parsed; generating display levels..." }
            step_phase {
                set progress "STEP: [eventValue $line phase]..."
            }
            lod_ready {
                set lod [eventValue $line lod]
                set progress "Display level ready: $lod"
            }
            preview_ready {
                if {$::GX::Native3D::previewReadyMs == 0} {
                    set ::GX::Native3D::previewReadyMs [clock milliseconds]
                }
                set stage [eventValue $line cache_dir]
                set progress "Opening first usable preview while higher display levels are prepared..."
                if {[catch {openPreviewHost $stage} problem]} {
                    set progress "Preview unavailable; continuing cache preparation: $problem"
                }
            }
            complete {
                if {[regexp {"peak_rss_mib":([-+0-9.eE]+)} $line -> peak]} {
                    set ::GX::Native3D::workerPeakMiB $peak
                }
                set ::GX::Native3D::cacheReadyMs [clock milliseconds]
                set status ready
                set progress "Display cache ready. Opening native viewer..."
                if {[catch {
                    if {$documentId eq ""} { recordSource } else { updateRelink }
                    openHost
                } problem]} { set status failed; set progress "Native viewer failed: $problem" }
            }
            error {
                if {$status ni {cancelled failed}} {
                    set status failed
                    set progress "Native preprocessing failed: $line"
                }
            }
        }
    }
    if {[eof $worker]} {
        fileevent $worker readable {}
        set result [catch {close $worker} reason]
        set worker ""
        refreshCancelAction
        cleanupCancelledStage
        if {$status eq "running"} {
            set status failed
            set progress "Native preprocessing ended before the display cache was ready: $reason"
        }
    }
}

proc ::GX::Native3D::updateRelink {} {
    variable source
    variable session
    variable portable
    variable sourceSha
    variable cacheKey
    variable documentId
    variable selectedDatasetId
    if {$documentId eq "" || $::GX::currentSession ne $session} { error "Native 3D relink has no active Session document." }
    set state [dict get [::GX::interactiveDocumentRead $documentId] payload]
    if {[dict get $state source_sha256] ne $sourceSha} { error "Relocated source failed the saved SHA-256 check." }
    if {[dict get $state source_mode] eq "dataset"} {
        set selectedDatasetId [dict get $state source_dataset_id]
        set payload [::GX::sessionInspectionDatasetPayload $selectedDatasetId]
        if {![string equal -nocase [dict get $payload sha256] $sourceSha] ||
            [dict get $payload path] ne $source} {
            error "Dataset '$selectedDatasetId' changed or is missing."
        }
        dict set state cache_key $cacheKey
        ::GX::interactiveDocumentUpdate $documentId $state
        ::GX::viewerLayerSet viewer.native_3d native_3d "mesh_[string range $sourceSha 0 15]" \
            [dict create kind triangle_mesh source_mode dataset dataset_id $selectedDatasetId \
                format [dict get $payload format]]
        ::GX::sessionPersistenceCommit
        return
    } elseif {$portable} {
        set relative [file join resources native3d $sourceSha [file tail $source]]
        set format [string tolower [string range [file extension $source] 1 end]]
    } else {
        set relative [dict get $state source_resource]
        set format gxtxt.external_3d_reference
        set reference [file join $session $relative]
        set f [open $reference w]
        fconfigure $f -encoding utf-8 -translation lf
        try {
            puts $f "GX-TXT external 3D source reference v1"
            ::GX::putKV $f sha256 $sourceSha
            ::GX::putKV $f size_bytes [file size $source]
            ::GX::putKV $f format [dict get $state source_format]
            ::GX::putKV $f path_hint $source
        } finally { close $f }
    }
    set artifact [::GX::viewerArtifactRegister $relative]
    dict set state source_path_hint $source
    dict set state source_resource $relative
    dict set state source_size [file size $source]
    dict set state cache_key $cacheKey
    ::GX::interactiveDocumentUpdate $documentId $state
    set layerId "mesh_[string range $sourceSha 0 15]"
    ::GX::viewerLayerSet viewer.native_3d native_3d $layerId [dict create \
        kind triangle_mesh source_mode artifact resource_path $relative \
        sha256 [dict get $artifact sha256] format $format format_version 1]
    ::GX::sessionPersistenceCommit
}

proc ::GX::Native3D::cleanupCancelledStage {} {
    variable cancelStage
    if {$cancelStage eq ""} return
    set cache [file normalize [cacheRoot]]
    set target [file normalize $cancelStage]
    if {[string first "$cache/" "$target/"] != 0} {
        set cancelStage ""
        error "Cancelled native cache stage is outside the configured cache."
    }
    if {[file exists $target]} { file delete -force -- $target }
    set cancelStage ""
}

proc ::GX::Native3D::openPreviewHost {stage} {
    variable host
    variable session
    if {$::GX::currentSession ne $session || $host ne ""} return
    if {![file isfile [file join $stage preview.ready]]} { error "Native preview is incomplete." }
    startHost [list [binary gx3d-host] $stage preview]
}

proc ::GX::Native3D::openHost {} {
    variable host
    variable cacheKey
    variable session
    variable requestedLod
    variable documentId
    if {$::GX::currentSession ne $session || $cacheKey eq ""} return
    if {$host ne ""} {
        set previous $host
        fileevent $previous readable {}
        catch {puts $previous QUIT; flush $previous}
        catch {close $previous}
        set host ""
    }
    set ::GX::Native3D::pendingWorkingPlaneEchoes {}
    set ::GX::Native3D::assemblyObjectIds {}
    if {[winfo exists .gxNative3D.body.assembly.parts]} {
        .gxNative3D.body.assembly.parts delete 0 end
    }
    set cache [file join [cacheRoot] $cacheKey]
    if {![file isfile [file join $cache manifest.json]]} {
        error "Native display cache is incomplete."
    }
    set lod [expr {$requestedLod eq "auto" ? [recommendedLod $cache] : $requestedLod}]
    startHost [list [binary gx3d-host] $cache $lod]
    if {$documentId ne ""} {
        set saved [dict get [::GX::interactiveDocumentRead $documentId] payload]
        if {[dict exists $saved visible]} { set ::GX::Native3D::visible [dict get $saved visible] }
        if {[dict exists $saved opacity]} { set ::GX::Native3D::opacity [dict get $saved opacity] }
        if {[dict exists $saved lighting]} { set ::GX::Native3D::lighting [dict get $saved lighting] }
        if {[dict exists $saved background_rgb]} { set ::GX::Native3D::backgroundRgb [dict get $saved background_rgb] }
        if {[dict exists $saved clipping_enabled]} { set ::GX::Native3D::clippingEnabled [dict get $saved clipping_enabled] }
        if {[dict exists $saved clipping_axis]} { set ::GX::Native3D::clippingAxis [dict get $saved clipping_axis] }
        if {[dict exists $saved clipping_fraction]} { set ::GX::Native3D::clippingFraction [dict get $saved clipping_fraction] }
        foreach {field verb} {display_mode MODE projection PROJECTION visible VISIBLE opacity OPACITY} {
            if {[dict exists $saved $field]} { send "$verb [dict get $saved $field]" }
        }
        if {[dict exists $saved lighting]} { send "LIGHTING [dict get $saved lighting]" }
        if {[dict exists $saved background_rgb]} {
            send "BACKGROUND [join [split [dict get $saved background_rgb] {;}] { }]"
        }
        if {$::GX::Native3D::clippingEnabled} { clipChanged }
        set legacyPlaceholder [expr {
            [dict get $saved camera_position] eq {0;0;1} &&
            [dict get $saved camera_target] eq {0;0;0} &&
            [dict get $saved parallel_scale] eq {1}
        }]
        if {!$legacyPlaceholder && [dict get $saved camera_position] ne "" &&
            [dict get $saved camera_target] ne "" && [dict get $saved camera_up] ne "" &&
            [dict get $saved parallel_scale] ne "" && [dict get $saved view_angle_deg] ne ""} {
            set camera {}
            foreach field {camera_position camera_target camera_up} {
                foreach component [split [dict get $saved $field] {;}] { lappend camera $component }
            }
            lappend camera [dict get $saved parallel_scale] [dict get $saved view_angle_deg] \
                [dict get $saved projection]
            send "SET_CAMERA [join $camera { }]"
        }
        if {[dict exists $saved vtu_layers]} {
            dict for {layerId details} [dict get $saved vtu_layers] {
                sendVtuLayer $layerId $details
                if {[dict exists $details visible] && ![dict get $details visible]} {
                    send "LAYER_VISIBLE $layerId 0"
                }
                if {[dict exists $details opacity] && [dict get $details opacity] != 1.0} {
                    send "LAYER_OPACITY $layerId [format %.3f [dict get $details opacity]]"
                }
            }
        }
        if {[dict exists $saved dataset_layers]} {
            dict for {layerId details} [dict get $saved dataset_layers] {
                sendDatasetLayer $layerId $details
                if {[dict exists $details visible] && ![dict get $details visible]} {
                    send "LAYER_VISIBLE $layerId 0"
                }
                if {[dict exists $details opacity] && [dict get $details opacity] != 1.0} {
                    send "LAYER_OPACITY $layerId [format %.3f [dict get $details opacity]]"
                }
            }
        }
        if {[dict exists $saved pattern_regions]} {
            send {LOD full}
            dict for {id details} [dict get $saved pattern_regions] {
                sendPatternRegion $id $details
                if {[dict exists $details visible] && ![dict get $details visible]} {
                    send "LAYER_VISIBLE $id 0"
                }
                if {[dict exists $details opacity] && [dict get $details opacity] != 1.0} {
                    send "LAYER_OPACITY $id [format %.3f [dict get $details opacity]]"
                }
            }
        }
        if {[dict exists $saved repeat_component]} {
            send {LOD full}
            send "APPLY_REPEATS [dict get $saved repeat_component source_cell]"
        }
        if {[dict exists $saved object_visibility]} {
            dict for {index visible} [dict get $saved object_visibility] {
                if {!$visible} {send "OBJECT_VISIBLE $index 0"}
            }
        }
        refreshScientificLayers
    }
}

proc ::GX::Native3D::gpuBudgetMiB {} {
    set value [expr {[info exists ::GX::moduleCfg(viewer.native_3d,interactive_gpu_budget_mib)] ? \
        $::GX::moduleCfg(viewer.native_3d,interactive_gpu_budget_mib) : 1024}]
    if {![string is integer -strict $value] || $value < 16 || $value > 1048576} {
        error "Native 3D display memory budget must be 16..1048576 MiB."
    }
    return $value
}

proc ::GX::Native3D::recommendedLod {cache} {
    set budget [expr {[info exists ::GX::moduleCfg(viewer.native_3d,interactive_triangle_budget)] ? $::GX::moduleCfg(viewer.native_3d,interactive_triangle_budget) : 1000000}]
    set bytesLimit [expr {[gpuBudgetMiB] * 1024 * 1024 / 4}]
    set f [open [file join $cache manifest.json] r]
    try { set manifest [read $f] } finally { close $f }
    foreach level {full high medium low preview} {
        set pattern [format {"name":"%s","file":"([^"]+)","triangles":([0-9]+)} $level]
        if {![regexp -- $pattern $manifest -> file triangles] || $triangles > $budget} continue
        if {$file eq "instanced"} {
            set bytes [file size [file join $cache step_instances.gx3di]]
            foreach chunk [glob -nocomplain -directory $cache "prototype_*_lod_${level}.gx3d"] {
                incr bytes [file size $chunk]
            }
        } else {
            set bytes [file size [file join $cache $file]]
        }
        if {$bytes <= $bytesLimit} { return $level }
    }
    return preview
}

proc ::GX::Native3D::hostReadable {} {
    variable host
    variable hostCommand
    variable hostReady
    variable hostSoftware
    variable hostRetried
    variable hostGraphicsFailure
    variable hostStartupCommands
    variable hostQuitAcknowledged
    variable status
    variable progress
    variable selection
    variable renderMode
    variable capabilitiesEvent
    variable benchmarkEvent
    variable benchmarkSequenceEvent
    variable screenshotEvent
    if {$host eq ""} return
    while {[gets $host line] >= 0} {
        lappend ::GX::Native3D::hostEventsRaw $line
        if {[llength $::GX::Native3D::hostEventsRaw] > 100} {
            set ::GX::Native3D::hostEventsRaw [lrange $::GX::Native3D::hostEventsRaw end-99 end]
        }
        if {!$hostReady && [regexp -nocase -- {OpenGL|GLX|vtkXOpenGLRenderWindow|Mesa.*(failed|error)|context.*(fail|creat)|failed.*context} $line]} {
            set hostGraphicsFailure 1
        }
        if {$status in {cancelled failed}} continue
        set event [eventValue $line event]
        switch -- $event {
            interactive {
                set hostReady 1
                set hostStartupCommands {}
                if {$::GX::Native3D::firstInteractiveMs == 0} {
                    set ::GX::Native3D::firstInteractiveMs [clock milliseconds]
                }
                set status interactive
                set renderMode [eventValue $line render_mode]
                set progress [expr {$hostSoftware ?
                    "Native viewer ready with Mesa llvmpipe software rendering. Use the model window to rotate, pan, zoom and pick." :
                    "Native viewer ready. Use the model window to rotate, pan, zoom and pick."}]
                if {[dict size $::GX::Native3D::workingPlane]} {
                    set plane $::GX::Native3D::workingPlane
                    queueWorkingPlaneEcho $plane
                    send "WORKING_PLANE [join [concat [dict get $plane origin] [dict get $plane normal] [dict get $plane u_axis] [list [dict get $plane visible]]] { }]"
                }
                if {$::GX::Native3D::sceneOnly} {
                    if {[catch {renderSceneLayers} problem]} {
                        set status failed
                        set progress "Scientific scene failed: $problem"
                    }
                }
            }
            lod { set progress "Displaying [eventValue $line name] LOD." }
            capabilities { set capabilitiesEvent $line }
            benchmark { set benchmarkEvent $line }
            benchmark_sequence { set benchmarkSequenceEvent $line }
            screenshot { set screenshotEvent $line }
            layer_ready { dict set ::GX::Native3D::layerEvents [eventValue $line id] $line }
            pattern_ready {
                set patternId [eventValue $line id]
                dict set ::GX::Native3D::patternEvents $patternId $line
                patternReady $patternId
            }
            repeat_proposal {
                set ::GX::Native3D::repeatProposalEvent $line
                set ::GX::Native3D::repeatStatus "[eventNumber $line matches] rigid matches proposed. Accept or reject."
            }
            repeat_ready { repeatReady $line }
            repeat_rejected { set ::GX::Native3D::repeatStatus "Repeat proposal rejected." }
            assembly_object {
                if {[regexp {"index":([0-9]+),"instances":([0-9]+)} $line -> index count]} {
                    lappend ::GX::Native3D::assemblyObjectIds $index
                    if {[winfo exists .gxNative3D.body.assembly.parts]} {
                        .gxNative3D.body.assembly.parts insert end "Part $index ($count instances)"
                    }
                }
            }
            pick {
                if {[regexp {"cell_id":([0-9]+)} $line -> cell]} {
                    set ::GX::Native3D::selectedCellId $cell
                    set selection "Selected source cell: $cell"
                }
                set picked [dict create event pick position [eventVector $line position] normal [eventVector $line normal] cell_id [eventNumber $line cell_id] point_id [eventNumber $line point_id] source [eventValue $line source]]
                set ::GX::Native3D::latestPick $picked
                notifyInteraction $picked
            }
            plane {
                set plane [dict create event plane origin [eventVector $line origin] normal [eventVector $line normal] u_axis [eventVector $line u_axis] visible [eventNumber $line visible]]
                if {![consumeWorkingPlaneEcho $plane]} {
                    set ::GX::Native3D::workingPlane [dict remove $plane event]
                    notifyInteraction $plane
                }
            }
            camera { saveCamera $line }
            error {
                set ::GX::Native3D::patternPending [dict create]
                set ::GX::Native3D::repeatPending [dict create]
                set progress "Native viewer error: $line"
                if {$::GX::Native3D::sceneOnly} {set status failed}
                set ::GX::Native3D::repeatStatus $progress
            }
            quit_ack {
                set hostQuitAcknowledged 1
                if {$status ni {cancelled failed}} { set status closed }
            }
            closed {
                set hostQuitAcknowledged 1
                if {$status ni {cancelled failed}} {set status closed}
            }
        }
    }
    if {[eof $host]} {
        fileevent $host readable {}
        set closeFailed [catch {close $host} closeReason]
        set host ""
        if {!$hostReady && $hostGraphicsFailure && !$hostSoftware && !$hostRetried &&
            $::tcl_platform(platform) ne "windows" && $status ne "cancelled"} {
            set hostRetried 1
            lappend ::GX::Native3D::hostEventsRaw "Automatic software retry after graphics initialization failure: $closeReason"
            set progress "Native 3D graphics initialization failed; retrying once with Mesa llvmpipe software rendering."
            set status running
            if {[catch {
                startHost $hostCommand 1 1
                foreach command $hostStartupCommands {puts $host $command}
                flush $host
            } retryReason]} {
                set status failed
                set progress "Native 3D software rendering retry failed: $retryReason"
            }
            return
        }
        if {!$hostReady && $status ni {cancelled closed}} {
            set status failed
            set progress "Native 3D renderer exited before it became interactive: $closeReason"
        } elseif {$hostReady && !$hostQuitAcknowledged && $status ne "cancelled"} {
            set status failed
            set progress "Native 3D renderer exited unexpectedly after interactive startup: $closeReason"
        } elseif {$status eq "interactive"} {
            set status closed
            set progress "Native viewer closed."
        }
    }
}

proc ::GX::Native3D::saveCamera {line} {
    variable documentId
    variable session
    if {$::GX::currentSession ne $session ||
        ($documentId eq "" && (!$::GX::Native3D::sceneOnly || $::GX::Native3D::sceneRestoring))} return
    foreach {field pattern} {
        camera_position {"position":\[([^]]+)\]}
        camera_target {"target":\[([^]]+)\]}
        camera_up {"up":\[([^]]+)\]}
    } {
        if {![regexp -- $pattern $line -> value]} return
        set values [split $value ,]
        if {[llength $values] != 3} return
        set $field [join $values {;}]
    }
    set projection [eventValue $line projection]
    if {$projection ni {perspective orthographic}} return
    foreach field {parallel_scale view_angle_deg} {
        set pattern [format {"%s":([-+0-9.eE]+)} $field]
        if {![regexp -- $pattern $line -> value] || ![string is double -strict $value] || $value <= 0} return
        set $field $value
    }
    if {$documentId ne ""} {
        set state [dict get [::GX::interactiveDocumentRead $documentId] payload]
        foreach field {camera_position camera_target camera_up projection parallel_scale view_angle_deg} {
            dict set state $field [set $field]
        }
        ::GX::interactiveDocumentUpdate $documentId $state
    }
    ::GX::viewerSceneSet viewer.native_3d native_3d [dict merge \
        [::GX::viewerSceneGet viewer.native_3d native_3d] [dict create \
        camera_position $camera_position camera_target $camera_target \
        camera_up $camera_up projection $projection]]
    ::GX::sessionPersistenceCommit
}

proc ::GX::Native3D::send {command} {
    variable host
    if {$host eq ""} return
    if {[regexp {[\r\n]} $command]} { error "Native viewer command must be one line." }
    set words [split $command]
    if {[lindex $words 0] eq "LIGHTING" &&
        ([llength $words] != 2 || [lindex $words 1] ni {0 1})} {
        error "Native lighting must be 0 or 1."
    }
    if {[lindex $words 0] eq "BACKGROUND"} {
        if {[llength $words] != 4} { error "Native background needs three color values." }
        foreach value [lrange $words 1 3] {
            if {![string is double -strict $value] ||
                [catch {expr {double($value) >= 0 && double($value) <= 1}} valid] || !$valid} {
                error "Native background colors must be between 0 and 1."
            }
        }
    }
    set actual $command
    if {$command eq "LOD auto"} {
        set actual "LOD [recommendedLod [file join [cacheRoot] $::GX::Native3D::cacheKey]]"
    }
    if {!$::GX::Native3D::hostReady} {lappend ::GX::Native3D::hostStartupCommands $actual}
    puts $host $actual
    flush $host
    if {$::GX::Native3D::documentId ne "" && $::GX::currentSession eq $::GX::Native3D::session} {
        set field ""
        switch -- [lindex $words 0] {
            LOD { set field requested_lod }
            MODE { set field display_mode }
            PROJECTION { set field projection }
            VISIBLE { set field visible }
            OPACITY { set field opacity }
            LIGHTING { set field lighting; set ::GX::Native3D::lighting [lindex $words 1] }
        }
        if {$field ne "" && [llength $words] == 2} {
            set state [dict get [::GX::interactiveDocumentRead $::GX::Native3D::documentId] payload]
            dict set state $field [lindex $words 1]
            ::GX::interactiveDocumentUpdate $::GX::Native3D::documentId $state
        } elseif {[lindex $words 0] eq "CLIP" && [llength $words] in {2 3}} {
            set state [dict get [::GX::interactiveDocumentRead $::GX::Native3D::documentId] payload]
            if {[lindex $words 1] eq "OFF"} {
                dict set state clipping_enabled 0
            } else {
                dict set state clipping_enabled 1
                dict set state clipping_axis [lindex $words 1]
                dict set state clipping_fraction [lindex $words 2]
            }
            ::GX::interactiveDocumentUpdate $::GX::Native3D::documentId $state
        } elseif {[lindex $words 0] eq "BACKGROUND" && [llength $words] == 4} {
            set ::GX::Native3D::backgroundRgb [join [lrange $words 1 3] {;}]
            set state [dict get [::GX::interactiveDocumentRead $::GX::Native3D::documentId] payload]
            dict set state background_rgb $::GX::Native3D::backgroundRgb
            ::GX::interactiveDocumentUpdate $::GX::Native3D::documentId $state
        }
    }
}

# Stable module-facing operations. The command-string transport above is
# private to this adapter; callers use Viewer Provider state where available.
proc ::GX::Native3D::cameraPreset {preset} {
    if {$preset ni {fit reset front back left right top bottom}} {error "Unknown camera preset '$preset'"}
    if {$preset eq "fit"} {send FIT} elseif {$preset eq "reset"} {send RESET} else {send "PRESET $preset"}
}
proc ::GX::Native3D::rotateView {direction} {
    if {$direction ni {left right up down}} {error "Unknown rotation direction '$direction'"}
    send "ARROW $direction"
}
proc ::GX::Native3D::setLod {level} {
    if {$level ni {auto preview low medium high full}} {error "Unknown LOD '$level'"}
    set ::GX::Native3D::requestedLod $level
    send "LOD $level"
}
proc ::GX::Native3D::setVisible {state} {
    if {$state ni {0 1}} {error "Visibility must be 0 or 1"}
    set ::GX::Native3D::visible $state
    send "VISIBLE $state"
}
proc ::GX::Native3D::setDisplayMode {mode} {
    if {$mode ni {surface wireframe surface_edges}} {error "Unknown display mode '$mode'"}
    set ::GX::Native3D::displayMode $mode
    send "MODE $mode"
}
proc ::GX::Native3D::setProjection {projection} {
    if {$projection ni {perspective orthographic}} {error "Invalid projection '$projection'"}
    set ::GX::Native3D::projection $projection
    ::GX::viewerSceneSet viewer.native_3d native_3d [dict replace \
        [::GX::viewerSceneGet viewer.native_3d native_3d] projection $projection]
    send "PROJECTION $projection"
    ::GX::sessionPersistenceCommit
}
proc ::GX::Native3D::setCamera {position target up {projection ""}} {
    set view [::GX::viewerSceneGet viewer.native_3d native_3d]
    dict set view camera_position $position
    dict set view camera_target $target
    dict set view camera_up $up
    if {$projection ne ""} {dict set view projection $projection}
    set view [::GX::viewerSceneSet viewer.native_3d native_3d $view]
    set numbers {}
    foreach field {camera_position camera_target camera_up} {lappend numbers {*}[split [dict get $view $field] {;}]}
    send "SET_CAMERA [join $numbers { }] 1 30 [dict get $view projection]"
    ::GX::sessionPersistenceCommit
    return $view
}
proc ::GX::Native3D::setLighting {state} {
    if {$state ni {0 1}} {error "Lighting must be 0 or 1"}
    ::GX::viewerSceneSet viewer.native_3d native_3d [dict replace \
        [::GX::viewerSceneGet viewer.native_3d native_3d] lighting $state]
    send "LIGHTING $state"
    ::GX::sessionPersistenceCommit
}
proc ::GX::Native3D::setBackground {rgb} {
    ::GX::viewerSceneSet viewer.native_3d native_3d [dict replace \
        [::GX::viewerSceneGet viewer.native_3d native_3d] background_rgb $rgb]
    set ::GX::Native3D::backgroundRgb $rgb
    send "BACKGROUND [join [split $rgb {;}] { }]"
    ::GX::sessionPersistenceCommit
}
proc ::GX::Native3D::setClippingPlanes {planes} {
    if {$planes ne "" && [llength [split $planes {;}]] != 1} {
        error "Native 3D supports one clipping plane"
    }
    set view [::GX::viewerSceneSet viewer.native_3d native_3d [dict replace \
        [::GX::viewerSceneGet viewer.native_3d native_3d] clipping_planes $planes]]
    if {$planes eq ""} {send {CLIP OFF}} else {
        send "CLIP_PLANE [join [split $planes ,] { }]"
    }
    ::GX::sessionPersistenceCommit
    return $view
}
proc ::GX::Native3D::setLayerPresentation {layerId fields} {
    set allowed {visible opacity representation layer_order scalar_array vector_array colormap scalar_range isovalues radius_array tube_radius}
    foreach key [dict keys $fields] {if {$key ni $allowed} {error "Unsupported layer presentation field '$key'"}}
    set layer [::GX::viewerLayerGet viewer.native_3d native_3d $layerId]
    set updated [::GX::viewerLayerSet viewer.native_3d native_3d $layerId [dict merge $layer $fields]]
    if {[dict exists $fields visible]} {send "LAYER_VISIBLE $layerId [dict get $updated visible]"}
    if {[dict exists $fields opacity]} {send "LAYER_OPACITY $layerId [dict get $updated opacity]"}
    if {[dict exists $fields representation]} {send "LAYER_MODE $layerId [dict get $updated representation]"}
    foreach key [dict keys $fields] {
        if {$key ni {visible opacity representation}} {
            ::GX::viewerRerender viewer.native_3d native_3d
            break
        }
    }
    ::GX::sessionPersistenceCommit
    return $updated
}
proc ::GX::Native3D::removeLayer {layerId} {
    ::GX::viewerLayerRemove viewer.native_3d native_3d $layerId
    send "LAYER_REMOVE $layerId"
    ::GX::sessionPersistenceCommit
}
proc ::GX::Native3D::screenshot {path} {
    if {[file extension $path] ne ".png" || ![file isdirectory [file dirname $path]]} {
        error "Screenshot requires a PNG path in an existing directory"
    }
    send "SCREENSHOT $path"
    return $path
}
proc ::GX::Native3D::refreshScene {} {::GX::viewerRerender viewer.native_3d native_3d}
proc ::GX::Native3D::closeViewer {} {send QUIT}
proc ::GX::Native3D::openExternalModel {path {copyIntoSession 0}} {
    if {$copyIntoSession ni {0 1}} {error "copyIntoSession must be 0 or 1"}
    tailcall ::GX::Native3D::openSource $path $copyIntoSession
}
proc ::GX::Native3D::verifySourceIdentity {} {
    return [::GX::viewerSceneResolve viewer.native_3d native_3d]
}

proc ::GX::Native3D::cancel {} {
    variable worker
    variable status
    variable progress
    variable cacheKey
    variable cancelStage
    variable host
    if {$worker eq ""} return
    set status cancelled
    set progress "Cancelling native preprocessing..."
    refreshCancelAction
    if {$cacheKey ne ""} {
        set processes [pid $worker]
        if {[llength $processes]} {
            set cancelStage [file join [cacheRoot] ".$cacheKey.tmp-[lindex $processes 0]"]
        }
    }
    if {$host ne ""} { catch {send QUIT} }
    foreach process [pid $worker] {
        if {$::tcl_platform(platform) eq "windows"} {
            catch {exec taskkill /PID $process /T /F}
        } else {
            catch {exec kill -TERM -- $process}
            after 2500 [list ::GX::Native3D::forceCancel $worker $process]
        }
    }
}

proc ::GX::Native3D::forceCancel {channel process} {
    variable worker
    if {$worker ne $channel || $worker eq ""} return
    if {$process ni [pid $worker]} return
    if {$::tcl_platform(platform) eq "windows"} {
        catch {exec taskkill /PID $process /T /F}
    } else {
        catch {exec kill -KILL -- $process}
    }
}

proc ::GX::Native3D::backend {action scene} {
    if {$::GX::currentSession eq ""} { error "Open a Session before using the Native 3D Viewer." }
    panel
    if {$action eq "open" && [dict exists $scene open_context dataset_id]} {
        return [openDataset [dict get $scene open_context dataset_id]]
    }
    if {[dict get $scene view scene_mode] eq "scientific" ||
        ([dict exists $scene open_context scene_only] && [dict get $scene open_context scene_only])} {
        return [openScene $scene]
    }
    if {[dict size [dict get $scene layers]] && ![llength [::GX::interactiveDocumentList viewer.native_3d native_3d]]} {
        return [openScene $scene]
    }
    if {$action eq "open" && [dict exists $scene open_context source_path]} {
        return [openSource [dict get $scene open_context source_path] 0]
    }
    set docs [::GX::interactiveDocumentList viewer.native_3d native_3d]
    if {[llength $docs]} {
        set recent [lindex $docs end]
        set saved [dict get [::GX::interactiveDocumentRead [dict get $recent id]] payload]
        if {[dict get $saved source_mode] eq "dataset"} {
            set datasetId [dict get $saved source_dataset_id]
            set payload [::GX::sessionInspectionDatasetPayload $datasetId]
            if {![string equal -nocase [dict get $payload sha256] [dict get $saved source_sha256]]} {
                error "Dataset '$datasetId' changed since this 3D scene was saved."
            }
            set path [dict get $payload path]
        } elseif {[dict get $saved source_mode] eq "session_artifact"} {
            set path [file join $::GX::currentSession [dict get $saved source_resource]]
            ::GX::viewerArtifactResolve [dict get $saved source_resource] [dict get $saved source_sha256]
        } else {
            set path [dict get $saved source_path_hint]
        }
        if {[file isfile $path]} {
            set ::GX::Native3D::documentId [dict get $recent id]
            return [openSource $path [expr {[dict get $saved source_mode] eq "session_artifact"}] \
                [dict get $saved source_sha256] \
                [expr {[dict get $saved source_mode] eq "dataset" ? [dict get $saved source_dataset_id] : ""}]]
        }
        set ::GX::Native3D::progress "The original model is missing. Locate the matching source model to relink it."
        return ""
    }
    set ::GX::Native3D::progress "Select an imported 3D Dataset from this Session."
    return ""
}

::GX::viewerBackendRegister gx3d_native_host ::GX::Native3D::backend
