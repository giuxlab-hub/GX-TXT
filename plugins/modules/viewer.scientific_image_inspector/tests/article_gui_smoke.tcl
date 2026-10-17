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
    # GX-TXT Configuration test double retains only the registered User default.
    variable siiSidebarPrefs {simple,figure}
    variable siiCoordinatePref 0
    proc configurationModuleFields {module} {
        if {$module ne {viewer.scientific_image_inspector}} {error {Unknown module}}
        return [dict create modules.scientific_image_inspector.sidebar_tabs [dict create module_key sidebar_tabs] \
            modules.scientific_image_inspector.annotation_coordinates [dict create module_key annotation_coordinates]]
    }
    proc configurationResolve {id} {
        return [dict create effective [expr {[string match *annotation_coordinates $id] ? $::GX::siiCoordinatePref : $::GX::siiSidebarPrefs}]]
    }
    proc configurationScopedValue {id scope} {
        return [expr {[string match *annotation_coordinates $id] ? $::GX::siiCoordinatePref : $::GX::siiSidebarPrefs}]
    }
    proc configurationCommit {changes} {
        foreach change $changes {
            set id [dict get $change id]
            set prior [configurationScopedValue $id user]
            if {[dict get $change expected] ne $prior} {error {Configuration conflict}}
            if {[string match *annotation_coordinates $id]} {
                set ::GX::siiCoordinatePref [dict get $change value]
            } else {set ::GX::siiSidebarPrefs [dict get $change value]}
        }
        return 1
    }

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
    proc ::GX::SII::guiError {msg} {error "GUI error: $msg"}
    set w [::GX::SII::dispatch open [dict create open_context [dict create dataset_id rgb]]]
    update
    if {![winfo exists $w]} {error {Viewer not opened}}
    if {$::GX::SII::ui(sourceId) ne "rgb"} {error {Wrong Dataset}}
    # Basic/Advanced are tool views of one working image and one recipe.
    set editor $w.layout.inspector.tabs.simple
    if {$::GX::SII::ui(editorMode) ne {basic}} {error {Basic Editor is not the default}}
    if {[winfo manager $editor.basic] ne {pack} || [winfo manager $editor.advanced] ne {}} {
        error {Initial Editor should show only Basic tools}
    }
    if {[llength [::GX::SII::basicPresetCatalog]] != 15} {error {Basic Editor lost its task presets}}
    set datasetBefore $::GX::SII::ui(sourceId)
    set stepsBefore $::GX::SII::ui(steps)
    set acceptedBefore $::GX::SII::ui(workingFile)
    ::GX::SII::editorSwitch advanced
    if {$::GX::SII::ui(editorMode) ne {advanced} || [winfo manager $editor.advanced] ne {pack} ||
        [winfo manager $editor.basic] ne {}} {error {Advanced Editor did not replace Basic tools}}
    set catalog $editor.advanced.operations.catalog
    if {[llength [$catalog children {}]] < 60} {error {Advanced Editor catalog is incomplete}}
    ::GX::SII::editorSwitch basic
    if {$::GX::SII::ui(sourceId) ne $datasetBefore || $::GX::SII::ui(steps) ne $stepsBefore ||
        $::GX::SII::ui(workingFile) ne $acceptedBefore || $::GX::SII::ui(pending)} {
        error {Switching editor tools changed the image recipe or unexpectedly started a preview}
    }
    set ::GX::SII::ui(basicPreset) {Microscopy | Gentle sharpening}
    ::GX::SII::presetSelectionChanged
    if {[string first {Unsharp} $::GX::SII::ui(basicPresetOperations)] < 0} {
        error {Preset operation transparency is missing}
    }
    ::GX::SII::previewSelectedPreset
    if {!$::GX::SII::ui(pending) || [llength $::GX::SII::ui(steps)]} {
        error {Preset must create an unaccepted ImageMagick preview, not a committed History step}
    }
    ::GX::SII::discardPreview
    if {$::GX::SII::ui(pending) || [llength $::GX::SII::ui(steps)]} {
        error {Discard preset failed to preserve the recipe}
    }
    puts {PASS: Basic/Advanced one-canvas switch, 15 task presets, unaccepted preview and discard}
    if {![file isfile $::GX::SII::ui(preview-original)]} {error {Missing original preview}}
    # Exercise an actual mouse-wheel event on Native2D and the asynchronous
    # viewport LOD; pixel resampling comes from the source file, not Tk zoom.
    set canvas $w.layout.main.panes.original.canvas
    set scene $::GX::SII::ui(native-original)
    set info $::GX::SII::ui(info)
    lassign [::GX::Native2D::core device $scene [list 0 [dict get $info height]]] x0 y0
    lassign [::GX::Native2D::core device $scene [list [dict get $info width] 0]] x1 y1
    set before [expr {abs($x1-$x0)}]
    event generate $canvas <MouseWheel> -delta 120 -x 170 -y 100
    update
    lassign [::GX::Native2D::core device $scene [list 0 [dict get $info height]]] x0 y0
    lassign [::GX::Native2D::core device $scene [list [dict get $info width] 0]] x1 y1
    set after [expr {abs($x1-$x0)}]
    if {$after <= $before} {error "Mouse wheel did not magnify: $before -> $after"}
    after 1800 {set ::lodTestWait 1}
    vwait ::lodTestWait
    if {![info exists ::GX::SII::ui(lodReady-original)] || ![file isfile $::GX::SII::ui(lodFile-original)]} {
        error {Asynchronous source-backed viewport LOD was not produced}
    }
    # Exactly one sidebar column: no 100-pixel navigator and no hidden Notebook.
    set sidebar $w.layout.inspector
    set content $sidebar.tabs
    set scroll $sidebar.scroll
    if {[winfo exists $sidebar.navigator] || [winfo class $content] eq {TNotebook}} {
        error {The inspector still contains a second navigation column or Notebook}
    }
    if {[llength $::GX::SII::ui(sidebarOrder)] != 2 || \
        $::GX::SII::ui(sidebarOrder) ne {simple figure}} {
        error {Default stacked sidebar must show Editor and Figures}
    }
    if {[winfo manager $content.simple] ne {pack} || [winfo manager $content.figure] ne {pack}} {
        error {Editor and Figures are not simultaneously packed}
    }
    update idletasks
    if {[winfo width $sidebar] > 410} {error {Inspector still wastes too much horizontal space}}
    if {[winfo width $content.simple] < [expr {[winfo width $scroll] - 20}]} {
        error {Visible panels are not using the single column width}
    }
    if {[winfo y $content.figure] <= [winfo y $content.simple]} {
        error {Figures do not appear below Editor}
    }
    lassign [$scroll yview] top bottom
    if {$bottom >= 1.0} {error {Sidebar is not scrollable despite two stacked panels}}
    # Wheel events on a nested control scroll the sidebar, not the image.
    event generate $content.simple.basic.info <MouseWheel> -delta -120
    update
    if {[lindex [$scroll yview] 0] <= $top} {error {Sidebar mouse wheel did not scroll}}
    ::GX::SII::sidebarPreferencesDialog
    set ::GX::SII::ui(pref-analyze) 1
    ::GX::SII::sidebarPreferencesSave
    if {[llength $::GX::SII::ui(sidebarOrder)] != 3 || $::GX::siiSidebarPrefs ne {simple,figure} ||
        "analyze" ni $::GX::SII::ui(sidebarTabs)} {
        error {Sidebar Apply did not update current Workspace without changing global User defaults}
    }
    set workspaceId $::GX::SII::ui(documentId)
    set stored [dict get [::GX::sessionWorkspaceGet $workspaceId] payload]
    if {[dict get $stored sidebar_sections] ne {simple figure analyze}} {
        error {Workspace payload does not contain the applied sidebar layout}
    }
    # Reopening the same Workspace must restore its configuration.
    set ::GX::SII::ui(sidebarTabs) {source}
    ::GX::SII::workspaceOpen [dict create workspace_id $workspaceId]
    if {$::GX::SII::ui(sidebarTabs) ne {simple figure analyze}} {
        error {Workspace-specific sidebar layout was not restored}
    }
    # Default is read-only image inspection: annotation gestures must not
    # be captured. CORE's icon overlay is not a second navigation column.
    if {$::GX::SII::ui(annotating)} {error {Annotation mode should default to off}}
    if {$::GX::SII::ui(showAnnotationCoordinates)} {error {Exact coordinates should be hidden by default}}
    set activePanel $w.layout.inspector.tabs.annotations.position
    if {[winfo manager $activePanel] ne {}} {error {Exact coordinate panel visible by default}}
    set ::GX::SII::ui(showAnnotationCoordinates) 1
    ::GX::SII::annotationCoordinateToggle
    if {$::GX::siiCoordinatePref != 1 || [winfo manager $activePanel] ne "pack"} {
        error {Explicit coordinate option was not saved by CORE Configuration}
    }
    set ::GX::SII::ui(showAnnotationCoordinates) 0
    ::GX::SII::annotationCoordinateToggle
    if {[winfo manager $activePanel] ne {}} {error {Coordinate panel did not hide}}
    set control $canvas
    if {![winfo exists [dict get $::GX::ViewportHost::hosts $control container].controls.body.transform]} {
        error {Native2D toolbar did not provide a Transform / annotation icon}
    }
    set ::GX::SII::ui(sidebarTabs) {simple figure}
    set ::GX::SII::ui(sidebarTemporary) {}
    ::GX::SII::sidebarRefresh
    ::GX::SII::sidebarSelect operations
    if {$::GX::SII::ui(editorMode) ne {advanced} || \
        [winfo manager $content.simple.advanced] ne {pack} || \
        $::GX::siiSidebarPrefs ne {simple,figure}} {
        error {The operation catalog must open within Advanced Editor without changing CORE Configuration}
    }
    set tree $w.layout.inspector.tabs.simple.advanced.operations.catalog
    $tree selection set gamma
    ::GX::SII::selectOperation
    set ::GX::SII::ui(param-gamma) 1.3
    ::GX::SII::addStep
    if {[llength $::GX::SII::ui(steps)] != 0 || !$::GX::SII::ui(pending)} {error {Step should be pending}}
    ::GX::SII::acceptPreview
    if {[llength $::GX::SII::ui(steps)] != 1} {error {Acceptance failed}}
    ::GX::SII::undo
    if {[llength $::GX::SII::ui(steps)] != 0} {error {Undo failed}}
    ::GX::SII::redo
    if {[llength $::GX::SII::ui(steps)] != 1} {error {Redo failed}}
    ::GX::SII::toggleCompare
    ::GX::SII::toggleCompare
    ::GX::SII::computeStats
    ::GX::SII::computeHistogram
    ::GX::SII::computePalette
    ::GX::SII::channelPreview
    # Annotation on the accepted source works without any Figure preview.
    ::GX::SII::annotationMode 1
    set ::GX::SII::ui(annotationTool) Text
    set ::GX::SII::ui(annotation-text) SourceLabel
    set ih [dict get $::GX::SII::ui(workingInfo) height]
    lassign [::GX::Native2D::core device $::GX::SII::ui(native-original) [list 20 [expr {$ih-20}]]] textX textY
    ::GX::SII::canvasStart [expr {int($textX)}] [expr {int($textY)}]
    lassign [::GX::Native2D::core device $::GX::SII::ui(native-original) [list 65 [expr {$ih-58}]]] endX endY
    ::GX::SII::canvasDrag [expr {int($endX)}] [expr {int($endY)}]
    if {![llength [$canvas find withtag sii_text_draft]]} {error {Text drag did not produce a dashed in-image box}}
    ::GX::SII::canvasCommit [expr {int($endX)}] [expr {int($endY)}]
    set e $::GX::SII::ui(inlineWidget).edit
    $e delete 1.0 end
    $e insert 1.0 SourceLabel
    if {![winfo exists $::GX::SII::ui(inlineToolbar).color.swatch]} {error {Framework color chooser swatch is missing}}
    if {[llength [$canvas find withtag sii_text_inline_editor]] < 3} {error {Dashed box and toolbar did not appear on image canvas}}
    if {![llength [::GX::SII::annotationFontOptions]]} {error {Installed ImageMagick fonts were not discovered}}
    set ::GX::SII::ui(inlineSize) 18
    set ::GX::SII::ui(inlineFont) DejaVu-Sans
    set ::GX::SII::ui(inlineUnit) px
    ::GX::SII::annotationInlineLiveStyle
    set ::GX::cfg(analysis_png_dpi) 144
    set ::GX::SII::ui(inlineUnit) pt
    ::GX::SII::annotationInlineUnitChanged
    if {abs($::GX::SII::ui(inlineSize)-9.0)>0.001} {error {px to pt conversion ignored framework output DPI}}
    set ::GX::SII::ui(inlineUnit) px
    ::GX::SII::annotationInlineUnitChanged
    if {abs($::GX::SII::ui(inlineSize)-18.0)>0.001} {error {pt to px conversion lost nominal font size}}
    unset ::GX::cfg(analysis_png_dpi)
    ::GX::SII::annotationInlineApply
    set textObject [lindex $::GX::SII::ui(annotations) 0]
    if {[dict get $textObject size] != 18 || [dict get $textObject font_family] ne {DejaVu-Sans} ||
        [dict get $textObject box_width]<30 || [dict get $textObject box_height]<25 ||
        ![dict exists $textObject font_dpi]} {
        error {On-image font controls were not saved as editable overlay properties}
    }
    puts {PASS: on-canvas dashed text box, CORE color chooser, font selector, unit and size}
    if {[llength $::GX::SII::ui(annotations)] != 1 || $::GX::SII::ui(figurePreviewActive)} {
        error {Annotations should edit the main image without figure preview}
    }
    # Article-editor integration: image panels, actual composite preview,
    # The Operations menu is redundant: Advanced Editor contains the catalog.
    set menuLabels {}
    for {set i 0} {$i<=[$w.menu index end]} {incr i} {if {![catch {$w.menu entrycget $i -label} label]} {lappend menuLabels $label}}
    if {{Operations} in $menuLabels} {error {Redundant top-level Operations menu remains}}
    set ::GX::SII::ui(roi) {10 10 40 30}
    set ::GX::SII::ui(scope) roi
    set testCanvas $w.layout.main.panes.original.canvas
    set state $::GX::SII::ui(native-original)
    lassign [::GX::Native2D::core device $state {20 50}] roiX roiY
    # Native2D world Y is reversed relative to image-pixel Y.
    if {![::GX::SII::roiContainsDevice [expr {int($roiX)}] [expr {int($roiY)}]]} {
        error {ROI context picking ignores Native2D image coordinate mapping}
    }
    rename ::GX::SII::contextPopup ::GX::SII::contextPopup_original
    proc ::GX::SII::contextPopup {m X Y} {return}
    ::GX::SII::roiCanvasContext [expr {int($roiX)}] [expr {int($roiY)}] 200 200
    rename ::GX::SII::contextPopup {}
    rename ::GX::SII::contextPopup_original ::GX::SII::contextPopup
    set roiMenu $testCanvas.roiContext
    if {![winfo exists $roiMenu]} {error {ROI context menu was not created}}
    set categories [$roiMenu entrycget 7 -label]
    if {[$roiMenu index end] < 7} {error {ROI context menu lacks processing categories}}
    # An operation launched via the ROI menu is a candidate, not a Dataset
    # publication or an accepted edit. Only ROI-compatible catalog entries show.
    set opMenu $testCanvas.roiContext.operators
    if {[llength [$opMenu index end]] == 0} {error {ROI operation categories were not populated}}
    set preRoiSteps $::GX::SII::ui(steps)
    ::GX::SII::roiOperationPreview normalize {} $::GX::SII::ui(roi)
    if {!$::GX::SII::ui(pending) || $::GX::SII::ui(steps) ne $preRoiSteps} {
        error "ROI processing did not create a non-destructive preview: $::GX::SII::ui(status) | figure $::GX::SII::ui(figurePreviewActive) | mode $::GX::SII::ui(scope)"
    }
    ::GX::SII::discardPreview
    ::GX::SII::roiClear
    if {$::GX::SII::ui(roi) ne {} || $::GX::SII::ui(scope) ne {all}} {error {Clear ROI failed}}
    # Native2D geometry and one editable vector/text annotation.
    ::GX::SII::addCurrentPanel
    ::GX::SII::addCurrentPanel
    if {[llength $::GX::SII::ui(panels)] != 2} {error {Multi-panel creation failed}}
    set ::GX::SII::ui(figure-width) 620
    set ::GX::SII::ui(figure-height) 420
    ::GX::SII::previewFigure
    if {!$::GX::SII::ui(figurePreviewActive)} {error {Figure preview failed}}
    if {[llength $::GX::SII::ui(imageAnnotations)] != 1 || [llength $::GX::SII::ui(annotations)]} {
        error {Figure mode must have a separate annotation layer from the source image}
    }
    if {[dict get $::GX::SII::ui(workingInfo) width] != 620} {error {Wrong figure preview width}}
    ::GX::SII::annotationMode 1
    set ::GX::SII::ui(annotationTool) Text
    set ::GX::SII::ui(annotation-text) A
    set ih [dict get $::GX::SII::ui(workingInfo) height]
    lassign [::GX::Native2D::core device $::GX::SII::ui(native-original) [list 160 [expr {$ih-160}]]] annX annY
    ::GX::SII::canvasStart [expr {int($annX)}] [expr {int($annY)}]
    ::GX::SII::canvasCommit [expr {int($annX)}] [expr {int($annY)}]
    set e $::GX::SII::ui(inlineWidget).edit
    $e delete 1.0 end
    $e insert 1.0 A
    ::GX::SII::annotationInlineApply
    if {[llength $::GX::SII::ui(annotations)] != 1} {error {Text annotation failed}}
    set ::GX::SII::ui(annotationTool) Arrow
    ::GX::SII::canvasStart [expr {int($annX)}] [expr {int($annY)}]
    lassign [::GX::Native2D::core device $::GX::SII::ui(native-original) [list 260 [expr {$ih-225}]]] annX2 annY2
    ::GX::SII::canvasCommit [expr {int($annX2)}] [expr {int($annY2)}]
    if {[llength $::GX::SII::ui(annotations)] != 2} {error {Native2D arrow annotation failed}}
    ::GX::SII::previewFigure
    if {![file exists $::GX::SII::ui(workingFile)]} {error {Annotated export preview missing}}
    # Switching working mode restores the source annotations separately.
    ::GX::SII::renderImages
    if {$::GX::SII::ui(figurePreviewActive) || [llength $::GX::SII::ui(annotations)] != 1 ||         [llength $::GX::SII::ui(figureAnnotations)] != 2} {
        error {Image/figure annotation state mixed on mode switch}
    }
    ::GX::SII::previewFigure
    if {[llength $::GX::SII::ui(annotations)] != 2} {error {Figure layer was not restored}}
    # A filter request while displaying the composed figure offers a guided
    # switch to source image. The composed panels and overlays must survive.
    rename tk_messageBox sii_test_messagebox
    proc tk_messageBox {args} {return yes}
    set filterStep [dict create op gamma params [dict create gamma 1.1] scope all roi {}]
    set figurePanelsBefore $::GX::SII::ui(panels)
    set figureObjectsBefore $::GX::SII::ui(annotations)
    ::GX::SII::previewSteps [list $filterStep]
    rename tk_messageBox {}
    rename sii_test_messagebox tk_messageBox
    if {$::GX::SII::ui(figurePreviewActive) || !$::GX::SII::ui(pending) ||
        $::GX::SII::ui(panels) ne $figurePanelsBefore ||
        $::GX::SII::ui(figureAnnotations) ne $figureObjectsBefore} {
        error {Figure-to-source guided filter transition lost panels or composition annotations}
    }
    ::GX::SII::discardPreview
    ::GX::SII::previewFigure
    if {[llength $::GX::SII::ui(annotations)] != 2} {error {Figure layers did not survive source editing}}
    # Distinct Session Workspaces must restore their own operation recipes;
    # opening by exact ID must not auto-pick another source-matched document.
    ::GX::SII::saveState
    set firstWorkspace $::GX::SII::ui(documentId)
    set firstSteps $::GX::SII::ui(steps)
    set firstAnnotations $::GX::SII::ui(annotations)
    ::GX::SII::workspaceOpen [dict create workspace_id new workspace_name {Second article figure}]
    if {[llength $::GX::SII::ui(steps)]} {error {New Workspace inherited prior processing}}
    set ::GX::SII::ui(steps) [list [dict create id gamma parameters [dict create value 0.9] scope all]]
    # Keep the second recipe minimal for the identity test.
    set ::GX::SII::ui(steps) {}
    ::GX::SII::saveState
    set secondWorkspace $::GX::SII::ui(documentId)
    if {$secondWorkspace eq $firstWorkspace} {error {New Workspace reused previous identity}}
    ::GX::SII::workspaceOpen [dict create workspace_id $firstWorkspace]
    if {$::GX::SII::ui(documentId) ne $firstWorkspace || $::GX::SII::ui(steps) ne $firstSteps || \
        $::GX::SII::ui(annotations) ne $firstAnnotations} {
        error {Workspace restore did not preserve independently saved processing steps}
    }
    # Native2D retained overlay editing: create, hit-test, move and resize.
    ::GX::SII::renderImages
    ::GX::SII::annotationMode 1
    set ::GX::SII::ui(annotationTool) Rectangle
    set ih [dict get $::GX::SII::ui(workingInfo) height]
    set native $::GX::SII::ui(native-original)
    lassign [::GX::Native2D::core device $native [list 9 [expr {$ih-10}]]] rx1 ry1
    lassign [::GX::Native2D::core device $native [list 35 [expr {$ih-38}]]] rx2 ry2
    ::GX::SII::canvasStart [expr {round($rx1)}] [expr {round($ry1)}]
    ::GX::SII::canvasDrag [expr {round($rx2)}] [expr {round($ry2)}]
    update idletasks
    if {![llength [$canvas find withtag figure_annotation_live]]} {error {Live shape feedback was not drawn while dragging}}
    ::GX::SII::canvasCommit [expr {round($rx2)}] [expr {round($ry2)}]
    set rectangle [lindex $::GX::SII::ui(annotations) end]
    set rid [dict get $rectangle id]
    if {![regexp {^ann[0-9]+$} $rid] || ![llength [$canvas find withtag sii_annotation_$rid]]} {
        error {Retained rectangle has no selectable stable identity}
    }
    set ::GX::SII::ui(annotationTool) Select
    lassign [::GX::Native2D::core device $native [list 20 [expr {$ih-10}]]] hx hy
    if {[llength [::GX::SII::annotationHit [expr {round($hx)}] [expr {round($hy)}]]] != 2} {
        error {Hit test did not find the retained rectangle}
    }
    ::GX::SII::canvasStart [expr {round($hx)}] [expr {round($hy)}]
    lassign [::GX::Native2D::core device $native [list 33 [expr {$ih-22}]]] mx my
    ::GX::SII::canvasDrag [expr {round($mx)}] [expr {round($my)}]
    update idletasks
    if {![llength [$canvas find withtag sii_annotation_$rid]]} {error {Moving shape disappeared from canvas}}
    ::GX::SII::canvasCommit [expr {round($mx)}] [expr {round($my)}]
    set moved [lindex $::GX::SII::ui(annotations) end]
    if {[dict get $moved id] ne $rid || [dict get $moved x1] == [dict get $rectangle x1]} {error {Moved rectangle lost identity or did not move}}
    # Native2D affine rotation, object pivot, and working-mode lifecycle.
    ::GX::SII::annotationSelectIndex [expr {[llength $::GX::SII::ui(annotations)]-1}]
    ::GX::SII::annotationPivotAt [expr {round($mx)}] [expr {round($my)}]
    set pivoted [lindex $::GX::SII::ui(annotations) end]
    if {![dict exists $pivoted pivot_x]} {error {Context pivot was not retained}}
    ::GX::SII::annotationRotateBy 45
    set rotated [lindex $::GX::SII::ui(annotations) end]
    if {[dict get $rotated rotation] != 45 || [dict get $rotated id] ne $rid} {error {Native rotation lost angle or identity}}
    set matrix [::GX::SII::annotationNativeMatrix $rotated $ih]
    if {[lindex $matrix 0] >= 1.0} {error {Native2D affine rotation matrix is identity}}
    set contextMenu [::GX::native2DViewportContextMenu $canvas [dict create entity object] {} \
        [list [list {Rotate} {::GX::SII::annotationRotateArm}]] {}]
    if {![winfo exists $contextMenu] || [$contextMenu type 1] ne "command"} {
        error {Native2D context menu adapter is not functional}
    }
    ::GX::SII::annotationMode 0
    if {$::GX::SII::ui(annotating) || ![llength [$canvas find withtag sii_annotation_$rid]] || [llength [$canvas find withtag figure_annotation_handle]]} {
        error {Finishing annotations should hide handles, not overlays}
    }
    ::GX::SII::annotationMode 1
    if {!$::GX::SII::ui(annotating)} {error {Cannot re-enter annotation editing}}
    # JSON annotation projection is valid JSON, and Workspace and published
    # manifest can expose it without replacing the authoritative Tcl recipe.
    set j [::GX::SII::annotationsJson $::GX::SII::ui(annotations)]
    if {![string match {*"objects"*"id":"ann*} $j]} {error {JSON layer projection is missing IDs}}
    if {[string first {"rotation":45} $j]<0 || [string first {"pivot_x":} $j]<0} {
        error {Rotation and custom pivot missing from JSON API}
    }
    set wsPayload [::GX::SII::workspacePayload]
    if {[dict get $wsPayload annotation_layers_json] ne $j} {error {Workspace JSON overlay projection mismatch}}
    # Strict modal pending adjustment: all editing is frozen until decision.
    set beforeCount [llength $::GX::SII::ui(annotations)]
    ::GX::SII::previewSteps [list [dict create op gamma params {gamma 1.2} scope all]]
    if {$::GX::SII::ui(annotating)} {error {Filter preview did not end annotation mode}}
    if {[$w.menu entrycget Image -state] ne "disabled" || [$w.menu entrycget Workspace -state] ne "disabled"} {
        error {Preview did not lock editing and Workspace menus}
    }
    ::GX::SII::canvasStart [expr {round($hx)}] [expr {round($hy)}]
    if {[llength $::GX::SII::ui(annotations)]!=$beforeCount} {error {Annotation was edited during pending processing}}
    ::GX::SII::undo
    if {!$::GX::SII::ui(pending)} {error {Undo discarded pending preview implicitly}}
    ::GX::SII::discardPreview
    ::GX::SII::annotationMode 1
    ::GX::SII::annotationSelectIndex [expr {[llength $::GX::SII::ui(annotations)]-1}]
    ::GX::SII::annotationRotateBy -45
    ::GX::SII::annotationPivotReset
    # Legacy endpoint resize remains available while drawing-tool mode is active;
    # the normal selected-object transform path uses Native2D.
    set ::GX::SII::ui(annotationTransform) none
    ::GX::SII::nativeDrawAnnotations
    ::GX::SII::annotationSelectIndex [expr {[llength $::GX::SII::ui(annotations)]-1}]
    set active [lindex $::GX::SII::ui(annotations) end]
    lassign [::GX::Native2D::core device $native [list [dict get $active x2] [expr {$ih-[dict get $active y2]}]]] ex ey
    if {[lindex [::GX::SII::annotationHit [expr {round($ex)}] [expr {round($ey)}]] 1] ne {resize}} {
        error {Annotation end handle is not interactive}
    }
    ::GX::SII::canvasStart [expr {round($ex)}] [expr {round($ey)}]
    lassign [::GX::Native2D::core device $native [list 60 [expr {$ih-51}]]] nx ny
    ::GX::SII::canvasDrag [expr {round($nx)}] [expr {round($ny)}]
    ::GX::SII::canvasCommit [expr {round($nx)}] [expr {round($ny)}]
    set resized [lindex $::GX::SII::ui(annotations) end]
    if {[dict get $resized x2] == [dict get $active x2] || [dict get $resized id] ne $rid} {error {Resize did not persist stable object identity}}
    if {[$w.menu entrycget Image -state] ne "normal" || [$w.menu entrycget Workspace -state] ne "normal"} {
        error {Preview lock was not released on Discard}
    }
    # Real Native2D gizmo: use CORE-rendered Free handle and gesture APIs.
    ::GX::SII::annotationTransformStart translate
    ::GX::SII::annotationSelectIndex [expr {[llength $::GX::SII::ui(annotations)]-1}]
    set gizmoCount [llength [$canvas find withtag native_gizmo]]
    ::GX::SII::nativeDrawAnnotations
    ::GX::SII::nativeDrawAnnotations
    if {[llength [$canvas find withtag native_gizmo]] != $gizmoCount} {
        error {Repeated overlay redraw duplicated Native2D pivot/transform gizmo items}
    }
    puts {PASS: Native2D gizmo redraw is idempotent}
    set before [lindex $::GX::SII::ui(annotations) end]
    set selectedHandle {}
    foreach primitive [::GX::Native2D::core render_gizmo $native] {
        if {[dict get $primitive handle] eq "free" && [dict get $primitive kind] eq "box"} {set selectedHandle $primitive;break}
    }
    if {$selectedHandle eq {}} {error {Native2D Free gizmo handle unavailable}}
    lassign [dict get $selectedHandle a] gax gay
    lassign [dict get $selectedHandle b] gbx gby
    set gx [expr {round(($gax+$gbx)/2.0)}]
    set gy [expr {round(($gay+$gby)/2.0)}]
    if {[::GX::Native2D::core gizmo_hit $native [list $gx $gy] 5] ne "free"} {error {Native2D Free hit test failed}}
    ::GX::SII::canvasStart $gx $gy
    if {![info exists ::GX::SII::ui(annotationNativeDrag)]} {error {Native2D manipulation transaction was not started}}
    ::GX::SII::canvasDrag [expr {$gx+35}] [expr {$gy+15}]
    ::GX::SII::canvasCommit [expr {$gx+35}] [expr {$gy+15}]
    set translated [lindex $::GX::SII::ui(annotations) end]
    if {[dict get $translated x1]==[dict get $before x1] || [dict get $translated id] ne [dict get $before id]} {error {Native2D translate failed to update retained annotation}}
    puts {PASS: Native2D real free-handle translation}
    ::GX::SII::annotationTransformStart rotate
    set rotatePrimitive {}
    foreach primitive [::GX::Native2D::core render_gizmo $native] {
        if {[dict get $primitive handle] eq "rotate" && [dict get $primitive kind] eq "circle"} {set rotatePrimitive $primitive;break}
    }
    if {$rotatePrimitive eq {}} {
        foreach primitive [::GX::Native2D::core render_gizmo $native] {
            if {[dict get $primitive handle] eq "rotate"} {set rotatePrimitive $primitive;break}
        }
    }
    if {$rotatePrimitive eq {}} {error {Native2D Rotate handle unavailable}}
    # Rotate with CORE hit test, parameters and drag transaction.
    set rotatePoint {}
    foreach pt [list [dict get $rotatePrimitive a] [dict get $rotatePrimitive b]] {
        lassign $pt ax ay
        if {[::GX::Native2D::core gizmo_hit $native [list [expr {round($ax)}] [expr {round($ay)}]] 5] eq "rotate"} {
            set rotatePoint [list [expr {round($ax)}] [expr {round($ay)}]];break
        }
    }
    if {$rotatePoint eq {}} {error {Native2D Rotate gizmo cannot be hit}}
    lassign $rotatePoint rX rY
    set beforeRotation [dict get [lindex $::GX::SII::ui(annotations) end] rotation]
    ::GX::SII::canvasStart $rX $rY
    ::GX::SII::canvasDrag [expr {$rX+33}] [expr {$rY+28}]
    ::GX::SII::canvasCommit [expr {$rX+33}] [expr {$rY+28}]
    set afterRotation [dict get [lindex $::GX::SII::ui(annotations) end] rotation]
    if {$afterRotation==$beforeRotation} {error {CORE Rotate gizmo did not update annotation model}}
    puts {PASS: Native2D real rotate-handle gesture}
    ::GX::SII::annotationTransformStart translate
    ::GX::SII::annotationSelectIndex [expr {[llength $::GX::SII::ui(annotations)]-1}]
    set pivotPrimitive {}
    foreach primitive [::GX::Native2D::core render_gizmo $native] {
        if {[dict get $primitive handle] eq "pivot"} {set pivotPrimitive $primitive;break}
    }
    if {$pivotPrimitive eq {}} {error {Native2D Pivot handle unavailable}}
    lassign [dict get $pivotPrimitive a] pax pay
    lassign [dict get $pivotPrimitive b] pbx pby
    set pivotX [expr {round(($pax+$pbx)/2.0)}]
    set pivotY [expr {round(($pay+$pby)/2.0)}]
    if {[::GX::Native2D::core gizmo_hit $native [list $pivotX $pivotY] 5] ne "pivot"} {error {CORE Pivot handle not selectable}}
    ::GX::SII::canvasStart $pivotX $pivotY
    ::GX::SII::canvasDrag [expr {$pivotX+18}] [expr {$pivotY-12}]
    ::GX::SII::canvasCommit [expr {$pivotX+18}] [expr {$pivotY-12}]
    set shiftedPivot [lindex $::GX::SII::ui(annotations) end]
    if {![dict exists $shiftedPivot pivot_x] || ![dict exists $shiftedPivot pivot_y]} {error {Native2D pivot did not persist}}
    puts {PASS: Native2D real pivot-handle drag}
    # A separate Native2D View pan icon, distinct from annotation transform.
    ::GX::SII::annotationPanMode
    if {$::GX::SII::ui(annotating) || $::GX::SII::ui(canvasMode) ne {pan}} {error {Pan icon does not switch the pointer controller}}
    set oldPoint [::GX::Native2D::core world $native [list 40 40]]
    ::GX::SII::canvasStart 130 130
    ::GX::SII::canvasDrag 155 139
    ::GX::SII::canvasCommit 155 139
    set newPoint [::GX::Native2D::core world $native [list 40 40]]
    if {$newPoint eq $oldPoint} {error {Native2D Pan mode did not move the view}}
    puts {PASS: Native2D independent pan icon}
    ::GX::SII::annotationMode 1
    ::GX::SII::annotationSelectIndex [expr {[llength $::GX::SII::ui(annotations)]-1}]
    set ::GX::SII::ui(annotationNameInput) {Frame boundary}
    # Name authority is in the recipe; formatting must survive JSON projection.
    set named [lindex $::GX::SII::ui(annotations) end]
    dict set named name {Frame boundary}
    set named [::GX::SII::validateAnnotation $named [dict get $::GX::SII::ui(workingInfo) width] [dict get $::GX::SII::ui(workingInfo) height]]
    lset ::GX::SII::ui(annotations) end $named
    if {[string first {"name":"Frame boundary"} [::GX::SII::annotationsJson $::GX::SII::ui(annotations)]] < 0} {error {Annotation name missing from JSON / manifest projection}}
    puts {PASS: Named object survives JSON projection}
    # New editor contract: the sidebar is optional and the canvas selection
    # remains authoritative when the Annotations panel is not mapped.
    set ::GX::SII::ui(sidebarTabs) {simple figure}
    set ::GX::SII::ui(sidebarTemporary) {}
    ::GX::SII::sidebarRefresh
    ::GX::SII::annotationSelectMode object
    if {[winfo manager $w.layout.inspector.tabs.annotations] ne {}} {
        error {Annotation selection reopened a hidden sidebar section}
    }
    if {[$w.menu index Edit] eq {}} {error {Edit menu missing}}
    set count [llength $::GX::SII::ui(annotations)]
    ::GX::SII::editSelectAll
    if {[llength $::GX::SII::ui(selectedAnnotationIds)] != $count} {
        error {Select All did not select every retained annotation}
    }
    ::GX::SII::editCopy
    if {[llength $::GX::SII::ui(annotationClipboard)] != $count} {error {Annotation copy missing objects}}
    ::GX::SII::editPaste
    if {[llength $::GX::SII::ui(annotations)] != 2*$count} {error {Paste did not duplicate annotations}}
    set allIds [lmap a $::GX::SII::ui(annotations) {dict get $a id}]
    if {[llength [lsort -unique $allIds]] != [llength $allIds]} {error {Paste reused stable object identity}}
    ::GX::SII::editUndo
    if {[llength $::GX::SII::ui(annotations)] != $count} {error {Edit Undo did not restore annotations}}
    ::GX::SII::editSelectNone
    if {[::GX::SII::annotationCurrentIndex] != -1} {error {Select None left an active annotation}}
    # A click on the rendered text (not its sidebar row) must activate it.
    ::GX::SII::annotationSelectMode object
    set selectedByCanvas 0
    set i 0
    foreach a $::GX::SII::ui(annotations) {
        set bbox [$canvas bbox sii_annotation_[dict get $a id]]
        if {[llength $bbox] != 4} {incr i;continue}
        lassign $bbox tx ty ux uy
        foreach pt [list [list [expr {round(($tx+$ux)/2)}] [expr {round(($ty+$uy)/2)}]] \
            [list [expr {round($tx+4)}] [expr {round($ty+4)}]]] {
            lassign $pt px py
            set hit [::GX::SII::annotationHit $px $py]
            if {$hit eq {} || [lindex $hit 0] != $i} continue
            ::GX::SII::canvasStart $px $py
            if {[::GX::SII::annotationCurrentIndex] == $i} {set selectedByCanvas 1}
            ::GX::SII::canvasCommit $px $py
            break
        }
        if {$selectedByCanvas} break
        incr i
    }
    if {!$selectedByCanvas} {error {Select tool could not activate any object directly on canvas}}
    puts {PASS: Select canvas click activates an object with the sidebar hidden}
    puts {PASS: hidden annotation sidebar, independent selection, copy/paste, Edit Undo}
    # Rectangular and polygon selection delegate containment to Native2D.
    set sh [dict get $::GX::SII::ui(workingInfo) height]
    set sw [dict get $::GX::SII::ui(workingInfo) width]
    lassign [::GX::Native2D::core device $native [list -4 [expr {$sh+4}]]] ax ay
    lassign [::GX::Native2D::core device $native [list [expr {$sw+4}] -4]] bx by
    set minx [expr {min($ax,$bx)}];set maxx [expr {max($ax,$bx)}]
    set miny [expr {min($ay,$by)}];set maxy [expr {max($ay,$by)}]
    ::GX::SII::annotationSelectMode window
    ::GX::SII::canvasStart [expr {round($minx)}] [expr {round($miny)}]
    ::GX::SII::canvasDrag [expr {round($maxx)}] [expr {round($maxy)}]
    ::GX::SII::canvasCommit [expr {round($maxx)}] [expr {round($maxy)}]
    if {[llength $::GX::SII::ui(selectedAnnotationIds)] < 1} {error {Native2D rectangular annotation selection failed}}
    ::GX::SII::annotationSelectMode polygon
    foreach pt [list [list $minx $miny] [list $maxx $miny] [list $maxx $maxy] [list $minx $maxy]] {
        lassign $pt px py
        ::GX::SII::canvasStart [expr {round($px)}] [expr {round($py)}]
    }
    ::GX::SII::annotationPolygonFinish
    if {[llength $::GX::SII::ui(selectedAnnotationIds)] < 1} {error {Native2D polygon annotation selection failed}}
    puts {PASS: Native2D Window and Polygon selection}
    # Image-pixel ROI has different semantics from annotation object selection.
    ::GX::SII::annotationSelectMode roi
    if {$::GX::SII::ui(annotating)} {error {Pixel ROI selection retained annotation editing}}
    lassign [::GX::Native2D::core device $native [list 10 [expr {$sh-10}]]] x0 y0
    lassign [::GX::Native2D::core device $native [list 40 [expr {$sh-40}]]] x1 y1
    ::GX::SII::canvasStart [expr {round($x0)}] [expr {round($y0)}]
    ::GX::SII::canvasDrag [expr {round($x1)}] [expr {round($y1)}]
    ::GX::SII::canvasCommit [expr {round($x1)}] [expr {round($y1)}]
    if {$::GX::SII::ui(scope) ne "roi" || [llength $::GX::SII::ui(roi)] != 4} {
        error {Image ROI did not activate ROI-restricted processing scope}
    }
    ::GX::SII::annotationSelectMode object
    puts {PASS: ROI mode selects source pixels, not annotation objects}
    ::GX::SII::viewerSettingsDialog
    set panel $w.viewerSettings.tabs
    if {[llength [$panel tabs]] != 3} {error {Viewer Settings semantic sections are missing}}
    destroy $w.viewerSettings
    puts {PASS: semantic Viewer Settings dialog}
    ::GX::SII::guiClose
    puts {GUI TEST PASSED: Native2D wheel, source-backed LOD, scrollable stacked panels, two independent Workspaces}
} on error {message options} {
    puts stderr "GUI TEST FAILED: $message\n[dict get $options -errorinfo]"
    set status 1
} finally {
    catch {destroy .}
    file delete -force -- $tmp
}
exit $status
