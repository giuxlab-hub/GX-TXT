# Native Tk smoke test under xvfb. No live GX-TXT Session is mutated.
# SPDX-License-Identifier: GPL-3.0-or-later
set root [file normalize [file join [file dirname [info script]] ..]]
set magick [expr {[info exists ::env(GXTXT_TEST_MAGICK)] ? $::env(GXTXT_TEST_MAGICK) : [auto_execok magick]}]
if {$magick eq ""} {puts stderr {SKIP: magick unavailable}; exit 77}
set ch [file tempfile tmp]; close $ch; file delete -- $tmp; file mkdir $tmp
set ::testMagick $magick
set ::testDir $tmp
exec $magick -size 80x70 gradient:red-blue [file join $tmp rgb.png]
namespace eval ::GX {
    proc viewerBackendRegister {name cmd} {set ::GX::backend($name) $cmd}
    proc runtimeToolRequired {n} {return $::testMagick}
    proc configurationTempDirectory {} {return $::testDir}
    proc sessionInspectionCurrentSession {} {return $::testDir}
    proc sessionInspectionDatasetIds {args} {return {rgb}}
    proc sessionInspectionDataset {id args} {return [dict create contract image.raster format png media_type image/png]}
    proc sessionInspectionDatasetPayload {id args} {
        set p [file join $::testDir rgb.png]
        return [dict create path $p sha256 [lindex [exec sha256sum -- $p] 0]]
    }
    proc sha256File {p} {return [lindex [exec sha256sum -- $p] 0]}
    proc contractSatisfies {given needed} {expr {$given eq $needed}}
    proc datasetMetadataRead {s id} {return [dict create instrument {GUI test}]}
    proc interactiveDocumentSessionToken {} {return tkn}
    # Isolated stub for the canonical Workspace API: no actual Session writes.
    variable siiWorkspace [dict create]
    variable siiWorkspaceNext 0
    proc sessionWorkspaceCreate {provider name payload} {
        set id "sii-test-[incr ::GX::siiWorkspaceNext]"
        dict set ::GX::siiWorkspace $id [dict create workspace_id $id name $name provider_id $provider payload $payload]
        return [dict get $::GX::siiWorkspace $id]
    }
    proc sessionWorkspaceGet {id} {return [dict get $::GX::siiWorkspace $id]}
    proc sessionWorkspaceUpdate {id payload} {
        dict set ::GX::siiWorkspace $id payload $payload
        return [sessionWorkspaceGet $id]
    }
    proc sessionWorkspaceDelete {id} {dict unset ::GX::siiWorkspace $id;return 1}
    proc sessionWorkspaceRename {id name} {dict set ::GX::siiWorkspace $id name $name;return [sessionWorkspaceGet $id]}
    proc sessionWorkspaceViewerTitlesRefresh {} {return}

    proc interactiveDocumentList {args} {return {}}
    proc interactiveDocumentCreate {args} {return [dict create id test-doc]}
    proc interactiveDocumentRead {id} {return [dict create module_id viewer.scientific_image_inspector provider_id scientific_image_inspector]}
    proc interactiveDocumentUpdate {args} {return [dict create id test-doc]}
    proc documentationBrowserOpenModule {id} {return}
}
# For a genuine Native2D GUI test point GXTXT_TEST_CORE_DIR to a read-only
# extracted GX-TXT core, containing tcl/ and native2d/bin/. No installation.
if {[info exists ::env(GXTXT_TEST_CORE_DIR)]} {
    set core $::env(GXTXT_TEST_CORE_DIR)
    set ::GX::scriptDir [file dirname $core]
    proc ::GX::datasetPublicationV2DictDefault {d k fallback} {expr {[dict exists $d $k] ? [dict get $d $k] : $fallback}}
    proc ::GX::uiFieldColorFromRGBA {color} {
        lassign $color r g b a
        return [dict create rgb [format "#%02X%02X%02X" [expr {int($r*255)}] [expr {int($g*255)}] [expr {int($b*255)}]]]
    }
    proc ::GX::uiFieldColorComposite {fg bg} {return $fg}
    proc ::GX::standardConfigWidget {args} {}
    proc ::GX::writeStandardRuntimeConfig {args} {}
    source [file join $core tcl ui_field_api_v1.tcl]
    source [file join $core tcl native2d_presentation_v1.tcl]
    source [file join $core tcl native2d_host_v1.tcl]
    source [file join $core tcl native2d_preview_v1.tcl]
    source [file join $core tcl native2d_viewport_host_v1.tcl]
} else {
    namespace eval ::GX {
        proc native2DEnsure {} {error {Set GXTXT_TEST_CORE_DIR to run Native2D GUI integration}}
    }
}
set status 0
try {
    source [file join $root api workspace_provider.tcl]
    source [file join $root api scientific_image_inspector_api_v1.tcl]
    source [file join $root runtime gui.tcl]
    proc ::GX::SII::guiError {msg} {error "GUI error: $msg :: $::errorInfo"}
    # No automatic source selection. A new Viewer is empty even if Registry
    # supplies images; opening a Workspace or choosing a Dataset is explicit.
    set w [::GX::SII::dispatch open [dict create open_context {}]]
    update
    if {![winfo exists $w]} {error {Viewer not opened}}
    if {$::GX::SII::ui(sourceId) ne {} || [info exists ::GX::SII::ui(originalFile)]} {
        error {New Viewer automatically opened a Dataset}
    }
    if {[$w.head.ds cget -values] ne {rgb}} {error {Available Dataset was not listed}}
    if {[llength $::GX::SII::ui(historyTimeline)]} {error {Blank Viewer has unexpected history}}
    ::GX::SII::showAbout
    if {![winfo exists $w.about] || [$w.about.version cget -text] ne {Version 0.4.1}} {
        error {Help About does not identify plugin version}
    }
    destroy $w.about
    # Explicitly select the Dataset after the empty startup.
    set ::GX::SII::ui(sourceId) rgb
    ::GX::SII::loadSource
    update
    if {$::GX::SII::ui(sourceId) ne "rgb"} {error {Explicit source selection failed}}
    if {[llength $::GX::SII::ui(historyTimeline)] != 1} {error {Expected an original history entry}}
    # Genuine Native2D reproduction of the user's trace. A zero-length line
    # is invalid in the C engine; it must not poison any subsequent redraw.
    set scene $::GX::SII::ui(native-original)
    if {![catch {::GX::Native2D::core sketch_create $scene [dict create family line controls {{20 20} {20 20}}] 257}]} {
        error {Native2D unexpectedly accepted a degenerate line}
    }
    set bad [dict create id ann900 name {Legacy zero arrow} kind arrow x1 20 y1 20 x2 20 y2 20 color #FFCC00 stroke 4]
    set good [dict create id ann901 name {Good arrow} kind arrow x1 10 y1 15 x2 60 y2 50 color #FFCC00 stroke 4]
    set ::GX::SII::ui(annotations) [list $bad $good]
    ::GX::SII::nativeDrawAnnotations
    if {[llength $::GX::SII::ui(annotations)] != 2} {error {Recovery must never delete legacy Workspace objects}}
    if {[dict exists $::GX::SII::ui(nativeAnnotationMap) ann900] || ![dict exists $::GX::SII::ui(nativeAnnotationMap) ann901]} {
        error {Invalid annotation poisoned valid Native2D objects}
    }
    if {![string match {*ann900*} $::GX::SII::ui(status)]} {error {Object-specific diagnostic missing}}
    if {[catch {::GX::SII::nativeZoom original 0.8} message]} {error "Zoom poisoned by legacy annotation: $message"}
    if {[catch {::GX::SII::annotationSelectMode object} message]} {error "Selection poisoned by legacy annotation: $message"}
    # A zero-displacement mouse gesture must be rejected before appending a
    # new annotation or creating an unrepairable History entry.
    set ::GX::SII::ui(annotations) {}
    set ::GX::SII::ui(selectedAnnotationIds) {}
    set ::GX::SII::ui(annotationActiveId) {}
    ::GX::SII::nativeDrawAnnotations
    ::GX::SII::annotationChooseTool Arrow
    set iw [dict get $::GX::SII::ui(workingInfo) width]
    set ih [dict get $::GX::SII::ui(workingInfo) height]
    lassign [::GX::Native2D::core device $scene [list [expr {$iw/2.0}] [expr {$ih/2.0}]]] cx cy
    set cx [expr {int(round($cx))}];set cy [expr {int(round($cy))}]
    ::GX::SII::canvasStart $cx $cy
    ::GX::SII::canvasCommit $cx $cy
    if {[llength $::GX::SII::ui(annotations)] || [llength $::GX::SII::ui(historyTimeline)] != 1} {
        error {Degenerate pointer gesture changed recipe/History}
    }
    if {![string match {*zero-length*} $::GX::SII::ui(status)]} {
        error {Zero-length gesture does not explain the rejection}
    }
    # After rejection, next valid arrow must work without reloading the Viewer.
    lassign [::GX::Native2D::core device $scene [list 15 15]] x0 y0
    lassign [::GX::Native2D::core device $scene [list 60 55]] x1 y1
    ::GX::SII::canvasStart [expr {int($x0)}] [expr {int($y0)}]
    ::GX::SII::canvasCommit [expr {int($x1)}] [expr {int($y1)}]
    if {[llength $::GX::SII::ui(annotations)] != 1} {error {Could not recover from rejected arrow gesture}}
    ::GX::SII::historyStripReset
    set ::GX::SII::ui(annotations) {}
    set ::GX::SII::ui(selectedAnnotationIds) {}
    set ::GX::SII::ui(annotationActiveId) {}
    ::GX::SII::nativeDrawAnnotations
    ::GX::SII::historyStripReset
    ::GX::SII::annotationMode 0
    if {[llength $::GX::SII::ui(historyTimeline)] != 1} {error {History did not reset in isolated regression}}
    # dev-037: the viewer itself, not the GX-TXT root, owns tooltip geometry.
    set toolbar [::GX::native2DViewportPanelWidget $w.layout.main.panes.original.canvas controls]
    set selectButton $toolbar.body.select
    if {[string first {::GX::SII::tooltipSchedule} [bind $selectButton <Enter>]]<0} {
        error {Tooltip still uses unscoped CORE root window}
    }
    if {[winfo class $w.strip.choice] ne {TMenubutton}} {
        error {Description / History selector may drop below the desktop}
    }
    if {[string first {::GX::SII::historyChoicePopup} [bind $w.strip.choice <Button-1>]]<0} {
        error {Description / History popup lacks upward placement}
    }
    # CORE's previous action dispatcher triggers a redundant redraw whenever
    # the annotation creation menu opens. A rejected tool must not escape to
    # GX-TXT's application-wide Tcl background-error dialog.
    rename ::GX::SII::annotationShapeMenu ::GX::SII::originalShapeMenu
    proc ::GX::SII::annotationShapeMenu {} {error {invalid input}}
    if {[catch {$toolbar.body.panel invoke} rejected]} {
        error "Toolbar exposed an unhandled Tcl error: $rejected"
    }
    if {![string match {*invalid input*} $::GX::SII::ui(status)]} {
        error {A rejected tool was not reported in the Viewer status}
    }
    rename ::GX::SII::annotationShapeMenu {}
    rename ::GX::SII::originalShapeMenu ::GX::SII::annotationShapeMenu
    $toolbar.body.select invoke
    # Check the actual Tk binding, not only direct Tcl procedure calls.
    set ::regressionBackgroundErrors {}
    proc bgerror {msg} {lappend ::regressionBackgroundErrors $msg}
    rename ::GX::SII::canvasStart ::GX::SII::originalCanvasStart
    proc ::GX::SII::canvasStart {args} {error {invalid input}}
    event generate $w.layout.main.panes.original.canvas <ButtonPress-1> -x 150 -y 130
    update
    if {[llength $::regressionBackgroundErrors]} {error {Canvas click escaped to Tcl bgerror}}
    if {![string match {*invalid input*} $::GX::SII::ui(status)]} {
        error {Rejected canvas input had no inline diagnostic}
    }
    rename ::GX::SII::canvasStart {}
    rename ::GX::SII::originalCanvasStart ::GX::SII::canvasStart
    unset ::regressionBackgroundErrors
    ::GX::SII::historyChoicePopup
    update idletasks
    if {[winfo ismapped $w.strip.choice.menu] &&
        [winfo rooty $w.strip.choice.menu] > [winfo rooty $w.strip.choice]} {
        error {History choice popup opened below its bottom-edge control}
    }
    catch {$w.strip.choice.menu unpost}
    ::GX::SII::annotationSelectMode object
    set ctrl [::GX::native2DViewportPanelWidget $w.layout.main.panes.original.canvas controls]
    if {![$ctrl.body.select instate selected] || [$ctrl.body.transform instate selected]} {
        error {Select toolbar state is not exclusive}
    }
    ::GX::SII::annotationTransformStart translate
    if {[$ctrl.body.select instate selected] || ![$ctrl.body.transform instate selected]} {
        error {Transform toolbar state is not exclusive}
    }
    ::GX::SII::annotationMode 0
    if {![file isfile $::GX::SII::ui(preview-original)]} {error {Missing original preview}}
    set tree $w.layout.inspector.tabs.simple.advanced.operations.catalog
    $tree selection set gamma
    ::GX::SII::selectOperation
    set ::GX::SII::ui(param-gamma) 1.3
    ::GX::SII::addStep
    if {[llength $::GX::SII::ui(steps)] != 0 || !$::GX::SII::ui(pending)} {error {Candidate was applied without user approval}}
    if {[llength [$w.layout.main.panes panes]] != 2} {error {Adjustment preview should open the right-hand pane}}
    ::GX::SII::acceptPreview
    if {[llength $::GX::SII::ui(steps)] != 1 || $::GX::SII::ui(pending)} {error {Candidate approval failed}}
    if {[llength $::GX::SII::ui(historyTimeline)] < 2} {error {Accepted operation missing from History strip}}
    set ::GX::SII::ui(historyStripView) History
    ::GX::SII::historyStripSwitch
    if {![llength [$w.strip.timeline find all]]} {error {History timeline did not draw}}
    set before [dict get $::GX::siiWorkspace $::GX::SII::ui(documentId) payload]
    ::GX::SII::historyBrowse 0
    if {!$::GX::SII::ui(historyBrowsing) || [llength $::GX::SII::ui(steps)] != 0} {
        error {Read-only history inspection did not restore the earlier visual state}
    }
    if {$before ne [dict get $::GX::siiWorkspace $::GX::SII::ui(documentId) payload]} {
        error {History inspection modified authoritative Workspace storage}
    }
    ::GX::SII::historyBrowse [expr {[llength $::GX::SII::ui(historyTimeline)]-1}]
    if {$::GX::SII::ui(historyBrowsing) || [llength $::GX::SII::ui(steps)] != 1} {
        error {Could not return to live editing from History}
    }
    # History's right-click invokes the same guarded path as the Tk binding.
    set rootx [expr {[winfo rootx $w.strip.timeline]+15}]
    set rooty [expr {[winfo rooty $w.strip.timeline]+12}]
    if {[catch {::GX::SII::historyStripContext 15 12 $rootx $rooty} message]} {
        error "History context click failed: $message"
    }
    catch {$w.strip.menu unpost}
    # Explicit tool selection from a historical inspection returns to the
    # latest mutable state, preserving every existing step.
    ::GX::SII::historyBrowse 0
    if {!$::GX::SII::ui(historyBrowsing)} {error {History prerequisite failed}}
    set historyCount [llength $::GX::SII::ui(historyTimeline)]
    ::GX::SII::annotationChooseTool Arrow
    if {$::GX::SII::ui(historyBrowsing) || !$::GX::SII::ui(annotating) ||
        $::GX::SII::ui(annotationTool) ne {Arrow} ||
        [llength $::GX::SII::ui(historyTimeline)] != $historyCount} {
        error {Drawing tool did not exit read-only History safely}
    }
    ::GX::SII::annotationMode 0
    set savedId $::GX::SII::ui(documentId)
    set savedTimeline [llength $::GX::SII::ui(historyTimeline)]
    ::GX::SII::workspaceOpen [dict create workspace_id $savedId]
    if {[llength $::GX::SII::ui(historyTimeline)] != $savedTimeline} {
        error {Workspace reopened without its persistent visual history}
    }
    set ::GX::SII::ui(historyStripView) Description
    ::GX::SII::historyStripSwitch
    if {[llength [$w.layout.main.panes panes]] != 1} {error {Approval should restore one working canvas}}
    ::GX::SII::openManual
    if {![winfo exists $w.manual]} {error {F1 viewer manual is not a standalone window}}
    if {![winfo exists $w.manual.search.query] || ![winfo exists $w.manual.search.next]} {
        error {Full Viewer manual does not have its independent Find controls}
    }
    set ::GX::SII::ui(manualQuery) {Five-minute start}
    ::GX::SII::manualFindNext
    if {![llength [$w.manual.body.text tag ranges manual_hit]]} {
        error {Manual search could not find a documented workflow}
    }
    destroy $w.manual
    if {[lsearch -exact [lmap i {0 1 2 3} {catch {$w.menu.file entrycget $i -label} label; set label}] {Export File...}] >= 0} {error {Direct file export is still exposed}}
    ::GX::SII::undo
    if {[llength $::GX::SII::ui(steps)] != 0} {error {Undo failed}}
    ::GX::SII::redo
    if {[llength $::GX::SII::ui(steps)] != 1} {error {Redo failed}}
    ::GX::SII::toggleCompare
    # Restore Original resets pixel recipe and overlays without touching source.
    ::GX::SII::annotationMode 1
    set ::GX::SII::ui(annotationTool) Text
    set ::GX::SII::ui(annotation-text) SourceNote
    set ih [dict get $::GX::SII::ui(workingInfo) height]
    lassign [::GX::Native2D::core device $::GX::SII::ui(native-original) [list 22 [expr {$ih-20}]]] ax ay
    ::GX::SII::canvasStart [expr {int($ax)}] [expr {int($ay)}]
    ::GX::SII::canvasCommit [expr {int($ax)}] [expr {int($ay)}]
    if {![info exists ::GX::SII::ui(inlineWidget)]} {error {Text editor did not open on canvas}}
    set textEditor $::GX::SII::ui(inlineWidget).edit
    $textEditor delete 1.0 end
    $textEditor insert 1.0 SourceNote
    ::GX::SII::annotationInlineApply
    if {![llength $::GX::SII::ui(annotations)]} {error {Source image annotation not created}}
    ::GX::SII::reset
    if {[llength $::GX::SII::ui(steps)] || [llength $::GX::SII::ui(annotations)]} {error {Restore original should clear edits}}
    ::GX::SII::undo
    if {![llength $::GX::SII::ui(steps)] || ![llength $::GX::SII::ui(annotations)]} {error {Reset undo did not restore image/annotations}}
    if {[::GX::SII::analysisFile] ne $::GX::SII::ui(workingFile)} {error {Working analysis target is incorrect}}
    set ::GX::SII::ui(target) Source
    if {[::GX::SII::analysisFile] ne $::GX::SII::ui(originalFile)} {error {Source analysis target is incorrect}}
    set ::GX::SII::ui(target) Working
    ::GX::SII::computeStats
    ::GX::SII::computeHistogram
    ::GX::SII::computePalette
    ::GX::SII::channelPreview
    ::GX::SII::guiClose
    puts {GUI TEST PASSED: native Tk, source, previews, catalog form, Undo/Redo}
} on error {message options} {
    puts stderr "GUI TEST FAILED: $message\n[dict get $options -errorinfo]"
    set status 1
} finally {
    catch {destroy .}
    file delete -force -- $tmp
}
exit $status
