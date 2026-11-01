# SPDX-License-Identifier: GPL-3.0-or-later
# Browser projection of the canonical catalog. Tree selection is only a visual
# highlight; explicit glyph activation changes the existing inspection choice.
proc ::GX::datasetPresentationDeferWhenBusy {callback} {
    variable currentSession;variable ui
    if {$currentSession eq {} || ![llength [info commands ::GX::acquisitionHandlerAuthorityBusy]] || ![acquisitionHandlerAuthorityBusy $currentSession]} {return 0}
    dict set ui(datasetAuthorityDeferred) [list $currentSession $callback] 1
    if {![info exists ui(datasetAuthorityDeferredAfter)]} {set ui(datasetAuthorityDeferredAfter) [after 200 ::GX::datasetPresentationDrain]}
    return 1
}
proc ::GX::datasetPresentationDrain {} {
    variable currentSession;variable ui
    unset -nocomplain ui(datasetAuthorityDeferredAfter)
    if {![info exists ui(datasetAuthorityDeferred)]} return
    set queued $ui(datasetAuthorityDeferred);unset ui(datasetAuthorityDeferred)
    if {![winfo exists .top.nb.channels]} return
    dict for {key ignored} $queued {
        lassign $key session callback
        if {$session ne $currentSession} continue
        if {[datasetPresentationDeferWhenBusy $callback]} continue
        uplevel #0 [list {*}$callback]
    }
}
proc ::GX::datasetBrowserNode {kind value} {return $kind:[binary encode hex [encoding convertto utf-8 $value]]}
proc ::GX::datasetBrowserValue {node} {return [encoding convertfrom utf-8 [binary decode hex [string range $node [expr {[string first : $node]+1}] end]]]}
proc ::GX::datasetBrowserToolbarStyle {} {
    # These controls contain fixed 22px glyphs, not text. Keep native focus and
    # theme elements without a large text-font minimum hiding the last icons.
    set iconFont [dict replace [font actual TkDefaultFont] -size 10]
    foreach style {GXDatasetToolbar.TButton GXDatasetToolbar.TMenubutton} {
        ttk::style configure $style -font $iconFont -borderwidth 1 -padding 1
    }
    # An icon-only menu trigger needs the same box as its neighbors. Retain the
    # actual Menubutton class/menu bindings and the theme's native button focus,
    # instead of allocating an extra text-oriented dropdown indicator.
    ttk::style layout GXDatasetToolbar.TMenubutton [ttk::style layout TButton]
    ttk::style configure GXDatasetToolbar.TMenubutton -default disabled
}
proc ::GX::datasetBrowserBuild {} {
    if {[datasetPresentationDeferWhenBusy ::GX::datasetBrowserBuild]} return
    variable ui
    set f .top.nb.channels
    if {![winfo exists $f]} return
    if {![winfo exists $f.browser]} {
        ttk::labelframe $f.browser -text Datasets -width 420
        # Keep the navigator's nominal layout request independent of its
        # scrollable content extent; long identities must not widen the pane.
        pack propagate $f.browser 0
        ttk::frame $f.browser.tools
        pack $f.browser.tools -side top -fill x
        datasetBrowserToolbarStyle
        foreach {key icon command tip} {
            refresh refresh datasetPageForceRefresh {Force resynchronize Dataset catalog and Preview}
            save save datasetPageSaveSchema {Save canonical variable schema}
            open open datasetPreviewOpenCurrent {Open active Dataset}
            edit edit datasetPageContextEdit {Edit the selected Dataset section}
        } {
            ttk::button $f.browser.tools.$key -style GXDatasetToolbar.TButton -default disabled -padding 1 -image [native2DViewportGlyph $icon] -command [list ::GX::datasetPageAction $command]
            pack $f.browser.tools.$key -side left -padx {0 1}
            bind $f.browser.tools.$key <Enter> [list ::GX::native2DViewportTooltipShow %W $tip]
            bind $f.browser.tools.$key <Leave> {catch {destroy .gxViewportTip}}
        }
        pack forget $f.bar.refresh $f.bar.save
        ttk::menubutton $f.browser.tools.print -style GXDatasetToolbar.TMenubutton -padding 1 -image [native2DViewportGlyph print] -menu $f.browser.tools.print.menu
        menu $f.browser.tools.print.menu -tearoff 0
        foreach {format label} {print {Print current view…} text {Export current view as text…} pdf {Save current view as PDF…}} {
            $f.browser.tools.print.menu add command -label $label -command [list ::GX::datasetPageAction datasetPageExportCurrent $format]
        }
        pack $f.browser.tools.print -side left -padx {0 1}
        bind $f.browser.tools.print <Enter> {::GX::native2DViewportTooltipShow %W {Print / Export current Dataset view}}
        bind $f.browser.tools.print <Leave> {catch {destroy .gxViewportTip}}
        ttk::button $f.browser.manage -style GXDatasetToolbar.TButton -default disabled -padding 1 -image [native2DViewportGlyph namespace] -command ::GX::datasetNamespaceManagerOpen
        pack $f.browser.manage -in $f.browser.tools -side left -padx {0 1} -before $f.browser.tools.open
        bind $f.browser.manage <Enter> {::GX::native2DViewportTooltipShow %W {Manage Dataset namespaces}}
        bind $f.browser.manage <Leave> {catch {destroy .gxViewportTip}}
        ttk::button $f.browser.tools.actions -style GXDatasetToolbar.TButton -default disabled -padding 1 -image [native2DViewportGlyph panel] -command ::GX::datasetPageActionsPopup
        pack $f.browser.tools.actions -side left -padx {0 1}
        bind $f.browser.tools.actions <Enter> {::GX::native2DViewportTooltipShow %W {Dataset actions}}
        bind $f.browser.tools.actions <Leave> {catch {destroy .gxViewportTip}}
        ttk::style configure GXDatasetCurrent.TLabel -wraplength 220 -justify left
        ttk::label $f.browser.current -text {Current: base} -width 1 -anchor w -style GXDatasetCurrent.TLabel
        pack $f.browser.current -side top -fill x -padx 3 -pady 3
        ttk::treeview $f.browser.tree -show tree -selectmode browse -height 20
        # Use the existing shared row metrics while the tree is empty, keeping
        # Dataset identity, glyph activation and declared column policy intact.
        uiFieldInspectionColumnsFit $f.browser.tree
        ttk::scrollbar $f.browser.scroll -command [list $f.browser.tree yview]
        ttk::scrollbar $f.browser.horizontal -orient horizontal -command [list $f.browser.tree xview]
        $f.browser.tree configure -yscrollcommand [list $f.browser.scroll set]
        $f.browser.tree configure -xscrollcommand [list $f.browser.horizontal set]
        $f.browser.tree column #0 -width 420 -minwidth 260 -stretch 0
        pack $f.browser.horizontal -side bottom -fill x
        pack $f.browser.scroll -side right -fill y
        pack $f.browser.tree -fill both -expand 1
        bind $f.browser.tree <Button-1> [list ::GX::datasetBrowserClick %x %y]
        bind $f.browser.tree <B1-Motion> [list ::GX::datasetBrowserGroupDragMotion %x %y]
        bind $f.browser.tree <ButtonRelease-1> [list ::GX::datasetBrowserGroupDragFinish %x %y]
        bind $f.browser.tree <Escape> +::GX::datasetBrowserGroupDragCancel
        bind $f.browser.tree <Unmap> +::GX::datasetBrowserGroupDragCancel
        bind $f.browser.tree <Destroy> +::GX::datasetBrowserGroupDragCancel
        bind $f.browser.tree <Button-3> [list ::GX::datasetBrowserContext %x %y %X %Y]
        foreach event {<Map> <Configure> <<ThemeChanged>>} {bind $f.browser.tree $event +::GX::datasetBrowserLayout}
    }
    # The navigator stays beside the persistent content views on every update.
    grid columnconfigure $f 0 -weight 3
    grid columnconfigure $f 2 -weight 1 -minsize 240
    grid columnconfigure $f 3 -weight 0
    grid $f.browser -row 0 -column 2 -sticky nsew -padx {8 6} -pady 4
    if {[winfo exists $f.bar]} {grid remove $f.bar $f.summary}
    if {[winfo exists $f.summary]} {$f.summary configure -wraplength 850}
    datasetBrowserRefresh
    set token [dict get [datasetCatalogSnapshot] session_token]
    if {![info exists ui(datasetBrowserCatalogToken)]||$ui(datasetBrowserCatalogToken) ne $token} {
        if {[info exists ui(datasetBrowserSubscription)]} {datasetCatalogUnsubscribe $ui(datasetBrowserSubscription)}
        set ui(datasetBrowserSubscription) [datasetCatalogSubscribe ::GX::datasetBrowserCatalogChanged]
        set ui(datasetBrowserCatalogToken) $token
    }
}
proc ::GX::datasetBrowserLayout {} {
    variable ui
    set tree .top.nb.channels.browser.tree
    if {![winfo exists $tree]} return
    set signature [list [font actual TkDefaultFont] [font actual TkHeadingFont] [ttk::style theme use] [winfo width $tree]]
    if {[info exists ui(datasetBrowserLayoutKey)] && $ui(datasetBrowserLayoutKey) eq $signature} return
    # InspectionColumns owns the bounded recursive text/indent measurement and
    # row style. A stable signature avoids ThemeChanged/style feedback loops.
    set ui(datasetBrowserLayoutKey) $signature
    datasetBrowserToolbarStyle
    uiFieldInspectionColumnsSchedule $tree {recursive 1}
    ttk::style configure GXDatasetCurrent.TLabel -wraplength [expr {max(100,[winfo width $tree]-20)}]
}
proc ::GX::datasetBrowserActiveRefresh {} {
    if {[datasetPresentationDeferWhenBusy ::GX::datasetBrowserActiveRefresh]} return
    variable currentSession
    if {![winfo exists .top.nb.channels.browser.current]} return
    datasetPreviewUpdateOpenButton
    if {$currentSession eq {}} {
        .top.nb.channels.browser.manage state disabled
        .top.nb.channels.browser.current configure -text "No Session\nActive Dataset: None"
        return
    }
    .top.nb.channels.browser.manage state !disabled
    if {$currentSession ne {}} {
        .top.nb.channels.browser.current state !disabled
        lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode active
        .top.nb.channels.browser.current configure -text "Current: [datasetNamespaceCurrentGet]\nActive Dataset: [expr {$mode eq {imported} ? $active : {None}}]"
    }
 }
proc ::GX::datasetBrowserRefresh {} {
    if {[datasetPresentationDeferWhenBusy ::GX::datasetBrowserRefresh]} return
    datasetBrowserActiveRefresh
    variable currentSession
    variable ui
    set tree .top.nb.channels.browser.tree
    if {![winfo exists $tree]} return
    set snapshot [datasetCatalogSnapshot]
    set namespaces [expr {$currentSession eq {}?{}:[datasetNamespaceList]}]
    set pending {}
    foreach choice [datasetInspectionChoices] {if {[string match "Pending:*" $choice]} {lappend pending $choice}}
    set inputPath [expr {[info exists ::GX::cfg(input_csv)]?$::GX::cfg(input_csv):{}}]
    set single [expr {[file isfile $inputPath]?[datasetInspectionSingleChoice]:{}}]
    set projection [list $single $inputPath $pending [dict get $snapshot session_token] $namespaces [dict get $snapshot datasets] [dict get $snapshot dataset_groups]]
    # Activation changes content, not the catalog. Preserve browser rows,
    # expansion, focus and scroll until its canonical projection changes.
    if {[info exists ui(datasetBrowserProjection)]&&$ui(datasetBrowserProjection) eq $projection} {datasetBrowserLayout;return}
    set ui(datasetBrowserProjection) $projection
    set scroll [lindex [$tree yview] 0]
    set highlighted [lindex [$tree selection] 0]
    set opened {}
    foreach node [$tree children {}] {datasetBrowserRememberOpen $tree $node opened}
    $tree delete [$tree children {}]
    if {$single ne {}} {$tree insert {} end -id [datasetBrowserNode single $single] -text $single -image [native2DViewportGlyph select 18] -tags single}
    if {$currentSession eq {}} {.top.nb.channels.browser.current configure -text "No Session\nActive Dataset: None";unset -nocomplain ui(datasetBrowserLayoutKey);datasetBrowserLayout;return}
    .top.nb.channels.browser.current state !disabled
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode active
    .top.nb.channels.browser.current configure -text "Current: [datasetNamespaceCurrentGet]\nActive Dataset: [expr {$mode eq {imported} ? $active : {None}}]"
    foreach namespace $namespaces {
        set parent {};set parts {}
        foreach part [split $namespace /] {
            lappend parts $part;set id [datasetBrowserNode namespace [join $parts /]]
            if {![$tree exists $id]} {$tree insert $parent end -id $id -text $part -tags namespace -open 1}
            set parent $id
        }
    }
    set grouped {};set roles {}
    foreach group [dict get $snapshot dataset_groups] {
        set groupId [dict get $group group_id]
        set parent [datasetBrowserNode namespace [dict get $group namespace]]
        set node [datasetBrowserNode group $groupId]
        if {![$tree exists $parent]} continue
        $tree insert $parent end -id $node -text "[dict get $group display_name] ([llength [dict get $group members]])" -tags group -open 1
        foreach member [dict get $group members] {dict set grouped [dict get $member dataset_id] $node;dict set roles [dict get $member dataset_id] [dict get $member role]}
    }
    foreach dataset [dict get $snapshot datasets] {
        set id [dict get $dataset dataset_id];set parent [datasetBrowserNode namespace [dict get $dataset namespace]]
        set label $id
        if {[dict exists $grouped $id]} {set parent [dict get $grouped $id];set label "$id — [dict get $roles $id]"}
        $tree insert $parent end -id [datasetBrowserNode dataset $id] -text $label -image [native2DViewportGlyph select 18] -tags dataset
    }
    foreach choice $pending {
        $tree insert [datasetBrowserNode namespace pending] end -id [datasetBrowserNode pending $choice] -text [string range $choice 9 end] -image [native2DViewportGlyph select 18] -tags pending
    }
    $tree yview moveto $scroll
    dict for {node open} $opened {if {[$tree exists $node]} {$tree item $node -open $open}}
    if {$highlighted ne {}&&[$tree exists $highlighted]} {$tree selection set $highlighted}
    unset -nocomplain ui(datasetBrowserLayoutKey)
    datasetBrowserLayout
}
proc ::GX::datasetBrowserRememberOpen {tree node resultName} {
    upvar 1 $resultName result
    dict set result $node [$tree item $node -open]
    foreach child [$tree children $node] {datasetBrowserRememberOpen $tree $child result}
}
proc ::GX::datasetBrowserActivate {id} {
    variable variableDatasetChoice
    set choice [datasetInspectionImportedChoice $id]
    if {$choice eq $variableDatasetChoice} return
    if {![datasetPageCanSwitch $choice]} return
    set variableDatasetChoice $choice
    refreshNativeVariablesGui
    catch {refreshCsvPreview}
}
proc ::GX::datasetBrowserClick {x y} {
    set tree .top.nb.channels.browser.tree
    set node [$tree identify row $x $y]
    datasetBrowserGroupDragStart $x $y
    # The small pointer glyph is the sole browser activation target. Ordinary
    # row clicks and expansion remain pure browsing operations.
    if {([string match pending:* $node] || [string match single:* $node])&&[$tree identify element $x $y] eq "image"} {
        set choice [datasetBrowserValue $node]
        if {[datasetPageCanSwitch $choice]} {set ::GX::variableDatasetChoice $choice;refreshNativeVariablesGui;refreshCsvPreview}
    }
    if {[string match dataset:* $node]&&[$tree identify element $x $y] eq "image"} {
        datasetBrowserActivate [datasetBrowserValue $node]
    }
}
proc ::GX::datasetBrowserGroupDragCancel {} {
    variable ui
    if {![info exists ui(datasetBrowserGroupDrag)]} return
    set tree .top.nb.channels.browser.tree
    if {[winfo exists $tree]} {$tree configure -cursor [dict get $ui(datasetBrowserGroupDrag) cursor]}
    unset ui(datasetBrowserGroupDrag)
}
proc ::GX::datasetBrowserGroupDragStart {x y} {
    variable ui
    datasetBrowserGroupDragCancel
    set tree .top.nb.channels.browser.tree
    set node [$tree identify row $x $y]
    # A disclosure click only expands/collapses. Scientific activation stays
    # on the existing Dataset glyph; this gesture concerns the Group row only.
    if {![string match group:* $node] || [string match *indicator* [$tree identify element $x $y]]} return
    set session [sessionInspectionCurrentSession]
    if {$session eq {}} return
    if {[catch {
        set group [datasetGroupGet $session [datasetBrowserValue $node]]
        set token [interactiveDocumentSessionToken]
    } message]} {tk_messageBox -parent .top -icon error -title {Dataset Group move} -message $message;return}
    set ui(datasetBrowserGroupDrag) [dict create session $session token $token \
        group_id [dict get $group group_id] revision [dict get $group revision] \
        label [dict get $group display_name] count [llength [dict get $group members]] \
        x $x y $y cursor [$tree cget -cursor]]
}
proc ::GX::datasetBrowserGroupDragMotion {x y} {
    variable ui
    if {![info exists ui(datasetBrowserGroupDrag)]} return
    set gesture $ui(datasetBrowserGroupDrag)
    if {[sessionInspectionCurrentSession] ne [dict get $gesture session] || \
        [catch {interactiveDocumentSessionToken} token] || $token ne [dict get $gesture token]} {
        datasetBrowserGroupDragCancel;return
    }
    if {abs($x-[dict get $gesture x])+abs($y-[dict get $gesture y])>=8} {
        .top.nb.channels.browser.tree configure -cursor fleur
    }
}
proc ::GX::datasetBrowserGroupDragFinish {x y} {
    variable ui
    if {![info exists ui(datasetBrowserGroupDrag)]} return
    set gesture $ui(datasetBrowserGroupDrag)
    datasetBrowserGroupDragCancel
    if {abs($x-[dict get $gesture x])+abs($y-[dict get $gesture y])<8} return
    set tree .top.nb.channels.browser.tree
    if {![winfo exists $tree]} return
    set node [$tree identify row $x $y]
    if {![string match namespace:* $node]} return
    set namespace [datasetBrowserValue $node]
    set code [catch {
        set session [dict get $gesture session]
        if {$session ne [sessionInspectionCurrentSession] || [interactiveDocumentSessionToken] ne [dict get $gesture token]} {error {Session changed during Group drag; select the Group again.}}
        set group [datasetGroupGet $session [dict get $gesture group_id]]
        if {[dict get $group revision] != [dict get $gesture revision]} {error {Dataset Group changed during drag; reload before moving it.}}
        if {$namespace ni [datasetNamespaceList]} {error {Destination namespace changed; select it again.}}
        if {$namespace eq [dict get $group namespace]} return
        if {[tk_messageBox -parent .top -title {Move whole Dataset Group} -type yesno -default no \
            -message "Move '[dict get $gesture label]' and all [dict get $gesture count] member Datasets to '$namespace'?\nDataset IDs and scientific data remain unchanged."] ne {yes}} return
        # The modal review may run other events. Recheck lifetime before using
        # the existing revision-checked, atomic Namespace/Group authority.
        if {$session ne [sessionInspectionCurrentSession] || [interactiveDocumentSessionToken] ne [dict get $gesture token]} {error {Session changed during Group review; select the Group again.}}
        if {$namespace ni [datasetNamespaceList]} {error {Destination namespace changed; select it again.}}
        datasetGroupMove $session [dict get $gesture group_id] $namespace [dict get $gesture revision]
        datasetBrowserRefresh;datasetNamespaceManagerRefresh
    } message options]
    if {$code == 2} return
    if {$code} {
        tk_messageBox -parent .top -icon error -title {Dataset Group move} -message $message
    }
}
proc ::GX::datasetBrowserCatalogChanged {receipt} {
    variable ui
    lappend ui(datasetBrowserReceipts) $receipt
    if {![info exists ui(datasetBrowserAfter)]} {set ui(datasetBrowserAfter) [after idle ::GX::datasetBrowserCatalogDrain]}
}
proc ::GX::datasetBrowserCatalogRefresh {receipt} {
    variable ui;variable variableDatasetChoice
    unset -nocomplain ui(datasetBrowserAfter)
    if {![winfo exists .top.nb.channels.browser.tree]} return
    lassign [datasetInspectionParseChoice $variableDatasetChoice] mode selected
    foreach pair [dict get $receipt renames] {
        lassign $pair before after
        if {$mode eq "imported"&&$selected eq $before} {
            set token [dict get $receipt session_token]
            if {[info exists ui(previewCleared)] && $ui(previewCleared) eq [list $token $variableDatasetChoice]} {set ui(previewCleared) [list $token [datasetInspectionImportedChoice $after]]}
            if {[info exists ui(previewMap,id)] && $ui(previewMap,id) eq [list $token $before]} {set ui(previewMap,id) [list $token $after]}
            set variableDatasetChoice [datasetInspectionImportedChoice $after];refreshNativeVariablesGui;return
        }
    }
    if {$mode eq "imported"&&$selected in [dict get $receipt deleted]} {refreshDatasetInspectionChoices;refreshNativeVariablesGui;return}
    if {$mode eq "imported" && ($selected in [dict get $receipt dataset_ids] || [dict get $receipt change_kind] eq "session")} {
        refreshNativeVariablesGui
    } else {datasetBrowserBuild;refreshCsvPreview}
}
proc ::GX::datasetBrowserContext {x y X Y} {
    set tree .top.nb.channels.browser.tree;set node [$tree identify row $x $y]
    if {$node eq {}} return
    $tree selection set $node
    set value [datasetBrowserValue $node]
    set menu .top.datasetBrowserMenu
    if {[winfo exists $menu]} {destroy $menu}
    menu $menu -tearoff 0
    if {[string match dataset:* $node]} {
        $menu add command -label {Activate Dataset} -command [list ::GX::datasetBrowserActivate $value]
        $menu add command -label Preview -command [list ::GX::datasetInspectionPreviewFromVariables $value]
        if {[datasetField $value contract [datasetField $value kind {}]] eq {molecular.structure}} {
            $menu add command -label {Open in Molecule Viewer} -state [expr {[_datasetViewerMoleculeAvailable $value]?{normal}:{disabled}}] -command [list ::GX::datasetPageAction datasetViewerOpenMolecule $value]
        }
        $menu add command -label {Metadata…} -command [list ::GX::datasetMetadataEditorOpen $value]
        $menu add command -label {Notes…} -command [list ::GX::datasetNotesOpen $value]
        $menu add separator
        $menu add command -label {Move to namespace…} -command [list ::GX::datasetBrowserMoveDialog $value]
        $menu add command -label {Create namespace and move…} -command [list ::GX::datasetBrowserMoveDialog $value 1]
        if {[datasetGroupForDataset $::GX::currentSession $value] ne {}} {
            $menu add command -label {Detach this member from Group…} -command [list ::GX::datasetBrowserGroupDetach $value]
        }
        $menu add separator
        $menu add command -label {Rename Dataset…} -command [list ::GX::datasetRenameSelectedFromGui $value]
        $menu add command -label {Delete Dataset…} -command [list ::GX::datasetDeleteSelectedFromGui $value]
        $menu add command -label {Export Dataset ZIP…} -command [list ::GX::portableResourceGuiExportDataset $value]
    } elseif {[string match group:* $node]} {
        $menu add command -label {Inspect Group…} -command [list ::GX::datasetBrowserGroupInspect $value]
        $menu add command -label {Move whole Group…} -command [list ::GX::datasetBrowserGroupMoveDialog $value]
        $menu add command -label {Export Group ZIP…} -command [list ::GX::portableResourceGuiExportGroup $value]
        $menu add separator
        $menu add command -label {Ungroup (keep Datasets)…} -command [list ::GX::datasetBrowserGroupUngroup $value]
    } elseif {[string match pending:* $node]} {
        $menu add command -label {Preview Pending source} -command [list ::GX::datasetPageActivatePending $value]
        $menu add command -label {Import required before move or rename} -state disabled
    } else {
        $menu add command -label {Set as current namespace} -command [list ::GX::datasetBrowserCurrentApply [dict create namespace $value]]
        $menu add command -label {Create namespace…} -command [list ::GX::datasetBrowserCreateDialog $value]
        $menu add command -label {Import Dataset Group ZIP…} -command [list ::GX::portableResourceGuiImport dataset_group]
    }
    ::GX::uiMenuPopup $menu $X $Y
}
proc ::GX::datasetBrowserMoveDialog {id {create 0}} {
    variable currentSession
    set groupId [datasetGroupForDataset $currentSession $id]
    if {$groupId ne {}} {return [datasetBrowserGroupMoveDialog $groupId]}
    set title [expr {$create?"Create namespace and move Dataset $id":"Move Dataset $id — ID and references stay unchanged"}]
    ::GX::uiFieldFormCreate .datasetNamespaceMove $title {namespace {type string required 1 label Namespace}} [dict create namespace [datasetNamespaceGet $currentSession $id]] [list ::GX::datasetBrowserMoveApply $currentSession $id $create] .top
}
proc ::GX::datasetBrowserGroupMoveDialog {groupId} {
    set session [sessionInspectionCurrentSession]
    set group [datasetGroupGet $session $groupId]
    uiFieldFormCreate .datasetGroupMove "Move whole Group — [dict get $group display_name]" \
        {namespace {type string required 1 label Namespace}} [dict create namespace [dict get $group namespace]] \
        [list ::GX::datasetBrowserGroupMoveApply $session $groupId [dict get $group revision]] .top
}
proc ::GX::datasetBrowserGroupCreateDialog {} {
    variable ui
    set session [_datasetGroupRequireAdmin [sessionInspectionCurrentSession]]
    set w .datasetGroupCreate
    if {[winfo exists $w]} {raise $w;return}
    set token [interactiveDocumentSessionToken]
    set snapshots {};set records {}
    foreach id [datasetRegistryIds] {
        if {[datasetGroupForDataset $session $id] ne {}} continue
        dict set snapshots $id [datasetRevisionToken $id $session]
        lappend records [list $id [datasetField $id contract [datasetField $id kind {}]] [datasetNamespaceGet $session $id] [datasetField $id producer_module [datasetField $id source_module {}]]]
    }
    if {$records eq {}} {error {No ungrouped canonical Datasets are available in this Session}}
    toplevel $w;wm title $w {Create Dataset Group};wm transient $w .top
    uiFieldWindowFit $w 980 680
    foreach {key value} {id {} name {} contract scientific.dataset_group primary {} role scientific.output required 1} {set ui(groupCreate,$key) $value}
    ttk::label $w.info -text {Select 1–64 canonical Datasets from one namespace. Grouping keeps their IDs and scientific payloads.} -wraplength 900 -justify left
    grid $w.info -row 0 -column 0 -columnspan 2 -sticky ew -padx 12 -pady 8
    ttk::frame $w.fields
    set row 0
    foreach {key label} {id {Group ID} name {Display name} contract {Group contract}} {
        ttk::label $w.fields.l$key -text $label
        ttk::entry $w.fields.$key -textvariable ::GX::ui(groupCreate,$key)
        grid $w.fields.l$key -row $row -column 0 -sticky w -padx {0 8} -pady 3
        grid $w.fields.$key -row $row -column 1 -sticky ew -pady 3
        incr row
    }
    grid columnconfigure $w.fields 1 -weight 1
    grid $w.fields -row 1 -column 0 -columnspan 2 -sticky ew -padx 12
    ttk::frame $w.list
    ttk::treeview $w.list.tree -columns {contract namespace producer role required} -show {tree headings} -selectmode extended -height 7
    $w.list.tree heading #0 -text {Dataset ID};$w.list.tree column #0 -width 180 -stretch 0
    foreach {key label width} {contract Contract 180 namespace Namespace 180 producer Producer 200 role Role 180 required Required 90} {
        $w.list.tree heading $key -text $label;$w.list.tree column $key -width $width -stretch 0
    }
    ttk::scrollbar $w.list.v -orient vertical -command [list $w.list.tree yview]
    ttk::scrollbar $w.list.h -orient horizontal -command [list $w.list.tree xview]
    $w.list.tree configure -yscrollcommand [list $w.list.v set] -xscrollcommand [list $w.list.h set]
    grid $w.list.tree -row 0 -column 0 -sticky nsew;grid $w.list.v -row 0 -column 1 -sticky ns;grid $w.list.h -row 1 -column 0 -sticky ew
    grid rowconfigure $w.list 0 -weight 1;grid columnconfigure $w.list 0 -weight 1
    foreach record $records {lassign $record id contract namespace producer;$w.list.tree insert {} end -id $id -text $id -values [list $contract $namespace $producer scientific.output 1]}
    uiFieldInspectionColumnsFit $w.list.tree
    bind $w.list.tree <<TreeviewSelect>> [list ::GX::datasetBrowserGroupCreateSelection $w]
    grid $w.list -row 2 -column 0 -columnspan 2 -sticky nsew -padx 12 -pady 8
    ttk::frame $w.roles
    ttk::label $w.roles.label -text {Selected member role}
    ttk::entry $w.roles.role -textvariable ::GX::ui(groupCreate,role)
    ttk::checkbutton $w.roles.required -text Required -variable ::GX::ui(groupCreate,required)
    ttk::button $w.roles.apply -text {Apply to selected} -command [list ::GX::datasetPageAction datasetBrowserGroupCreateRoles $w]
    grid $w.roles.label -row 0 -column 0 -sticky w -padx {0 8};grid $w.roles.role -row 0 -column 1 -sticky ew
    grid $w.roles.required -row 1 -column 0 -sticky w;grid $w.roles.apply -row 1 -column 1 -sticky e -pady 4;grid columnconfigure $w.roles 1 -weight 1
    grid $w.roles -row 3 -column 0 -columnspan 2 -sticky ew -padx 12
    ttk::label $w.primaryLabel -text {Primary Dataset}
    ttk::combobox $w.primary -state readonly -textvariable ::GX::ui(groupCreate,primary)
    grid $w.primaryLabel -row 4 -column 0 -sticky w -padx 12 -pady 4;grid $w.primary -row 4 -column 1 -sticky ew -padx 12 -pady 4
    ttk::frame $w.buttons
    ttk::button $w.buttons.cancel -text Cancel -command [list destroy $w]
    ttk::button $w.buttons.create -text {Review and create…} -command [list ::GX::datasetPageAction datasetBrowserGroupCreateApply $w $session $token $snapshots]
    pack $w.buttons.cancel $w.buttons.create -side left -padx 6 -pady 8
    grid $w.buttons -row 5 -column 0 -columnspan 2 -sticky e -padx 6
    grid columnconfigure $w 1 -weight 1;grid rowconfigure $w 2 -weight 1
    focus $w.fields.id
}
proc ::GX::datasetBrowserGroupCreateSelection {w} {
    variable ui
    set ids [$w.list.tree selection]
    $w.primary configure -values $ids
    if {$ui(groupCreate,primary) ni $ids} {set ui(groupCreate,primary) [lindex $ids 0]}
}
proc ::GX::datasetBrowserGroupCreateRoles {w} {
    variable ui
    if {![regexp {^[A-Za-z][A-Za-z0-9_.-]{0,127}$} $ui(groupCreate,role)]} {error {Use a qualified member role, such as scientific.output}}
    foreach id [$w.list.tree selection] {$w.list.tree set $id role $ui(groupCreate,role);$w.list.tree set $id required $ui(groupCreate,required)}
}
proc ::GX::datasetBrowserGroupCreateApply {w session token snapshots} {
    variable ui
    if {$session ne [sessionInspectionCurrentSession] || $token ne [interactiveDocumentSessionToken]} {error {Session changed; reopen Create Dataset Group}}
    set members {};set revisions {};set lines {}
    foreach id [$w.list.tree selection] {
        set role [$w.list.tree set $id role];set required [$w.list.tree set $id required]
        lappend members [dict create dataset_id $id role $role required $required contract [$w.list.tree set $id contract]]
        dict set revisions $id [dict get $snapshots $id]
        lappend lines "$id — $role; required=$required\n[$w.list.tree set $id contract] · [$w.list.tree set $id namespace] · [$w.list.tree set $id producer]"
    }
    set definition [dict create group_id $ui(groupCreate,id) display_name $ui(groupCreate,name) group_contract $ui(groupCreate,contract) primary_dataset_id $ui(groupCreate,primary) members $members]
    set review [dict create schema gxtxt.dataset_group_review.v1 session_token $token producer_module {} dataset_revisions $revisions]
    _datasetGroupReviewCheck $session $definition $review
    set text "Create '$ui(groupCreate,name)'?\nGroup ID: $ui(groupCreate,id)\nContract: $ui(groupCreate,contract)\nPrimary: $ui(groupCreate,primary)\n\nCreating this Group explicitly authorizes grouping the selected Datasets listed below. Their IDs and scientific payloads remain unchanged.\n\n[join $lines \n\n]"
    if {![datasetBrowserGroupReviewDialog $w $text]} return
    datasetGroupHostCreateV1 $session $definition $review
    destroy $w
    datasetBrowserRefresh
    datasetNamespaceManagerRefresh
}
proc ::GX::datasetBrowserGroupReviewDialog {parent text {confirm 1}} {
    variable ui
    set w [expr {$confirm?{.datasetGroupReview}:{.datasetGroupInspect}}]
    if {[winfo exists $w]} {raise $w;return 0}
    set ui(groupReviewAccepted,$w) 0
    uiFieldDialogCreate $w $parent [expr {$confirm?{Review Dataset Group}:{Dataset Group}}] 900x540
    uiFieldWindowFit $w 900 540
    text $w.text -wrap word -font TkDefaultFont -width 64 -height 14 -padx 12 -pady 10 -yscrollcommand [list $w.scroll set]
    ttk::scrollbar $w.scroll -orient vertical -command [list $w.text yview]
    $w.text insert end $text;$w.text configure -state disabled
    grid $w.text -row 0 -column 0 -sticky nsew;grid $w.scroll -row 0 -column 1 -sticky ns
    ttk::frame $w.buttons
    ttk::button $w.buttons.cancel -text [expr {$confirm?{Cancel}:{Close}}] -command [list ::GX::uiFieldDialogClose $w]
    bind $w.buttons.cancel <Return> [list ::GX::uiFieldDialogClose $w]
    pack $w.buttons.cancel -side left -padx 6 -pady 8
    if {$confirm} {
        ttk::button $w.buttons.create -text {Create Group} -command [list ::GX::datasetBrowserGroupReviewAccept $w]
        bind $w.buttons.create <Return> [list ::GX::datasetBrowserGroupReviewAccept $w]
        pack $w.buttons.create -side left -padx 6 -pady 8
    }
    grid $w.buttons -row 1 -column 0 -columnspan 2 -sticky e -padx 6
    grid columnconfigure $w 0 -weight 1;grid rowconfigure $w 0 -weight 1
    uiFieldDialogPresent $w $w.buttons.cancel 1
    tkwait window $w
    set accepted $ui(groupReviewAccepted,$w)
    unset ui(groupReviewAccepted,$w)
    return $accepted
}
proc ::GX::datasetBrowserGroupReviewAccept {w} {
    set ::GX::ui(groupReviewAccepted,$w) 1
    uiFieldDialogClose $w
}
proc ::GX::datasetBrowserGroupMoveApply {session groupId revision values} {
    if {$session ne [sessionInspectionCurrentSession]} {error {Session changed; reopen the Group dialog}}
    datasetGroupMove $session $groupId [dict get $values namespace] $revision
    datasetBrowserRefresh
    datasetNamespaceManagerRefresh
}
proc ::GX::datasetBrowserGroupInspect {groupId} {
    set group [datasetGroupGet [sessionInspectionCurrentSession] $groupId]
    set text "[dict get $group display_name]\nID: $groupId\nContract: [dict get $group group_contract]\nNamespace: [dict get $group namespace]\nRevision: [dict get $group revision]\nStatus: [dict get $group status]\n"
    foreach member [dict get $group members] {append text "\n[dict get $member dataset_id] — [dict get $member role]\n[dict get $member contract]\nSHA256 [dict get $member canonical_sha256]\n"}
    if {[dict get $group issues] ne {}} {append text "\nIssues: [dict get $group issues]"}
    datasetBrowserGroupReviewDialog .top $text 0
}
proc ::GX::datasetBrowserGroupUngroup {groupId} {
    set session [sessionInspectionCurrentSession]
    set group [datasetGroupGet $session $groupId]
    if {[tk_messageBox -parent .top -title {Ungroup Datasets} -type yesno -default no \
        -message "Remove Group '[dict get $group display_name]'? Every scientific Dataset is kept."] ne {yes}} return
    if {$session ne [sessionInspectionCurrentSession]} {error {Session changed; reopen the Group action}}
    datasetGroupUngroup $session $groupId [dict get $group revision]
    datasetBrowserRefresh
    datasetNamespaceManagerRefresh
}
proc ::GX::datasetBrowserGroupDetach {datasetId} {
    set session [sessionInspectionCurrentSession]
    set groupId [datasetGroupForDataset $session $datasetId]
    if {$groupId eq {}} {error {Dataset no longer belongs to a Group}}
    set group [datasetGroupGet $session $groupId]
    if {[tk_messageBox -parent .top -title {Detach Dataset member} -type yesno -default no \
        -message "Detach '$datasetId' from '[dict get $group display_name]'? Its data and Namespace stay intact; it can then move independently."] ne {yes}} return
    if {$session ne [sessionInspectionCurrentSession]} {error {Session changed; reopen the Group action}}
    datasetGroupDetach $session $groupId $datasetId [dict get $group revision]
    datasetBrowserRefresh
    datasetNamespaceManagerRefresh
}
proc ::GX::datasetBrowserMoveApply {session id create values} {
    if {$session ne [sessionInspectionCurrentSession]} {error {Session changed; reopen the namespace dialog.}}
    if {$create} {datasetNamespaceCreate $session [dict get $values namespace]}
    datasetNamespaceSet $session $id [dict get $values namespace]
    datasetBrowserRefresh
    datasetNamespaceManagerRefresh
}
proc ::GX::datasetBrowserCreateDialog {{parent {}}} {
    if {$::GX::currentSession eq {}} {error {Open a Session first.}}
    set proposed [expr {$parent eq {}?{}:"$parent/new"}]
    ::GX::uiFieldFormCreate .datasetNamespaceCreate {Create Dataset namespace} {namespace {type string required 1 label Namespace}} [dict create namespace $proposed] ::GX::datasetBrowserCreateApply .top
}
proc ::GX::datasetBrowserCreateApply {values} {
    datasetNamespaceCreate [sessionInspectionCurrentSession] [dict get $values namespace]
    datasetBrowserRefresh
    datasetNamespaceManagerRefresh
}
proc ::GX::datasetBrowserCurrentDialog {} {
    if {$::GX::currentSession eq {}} {error {Open a Session first.}}
    ::GX::uiFieldFormCreate .datasetNamespaceCurrent {Current Dataset namespace} {namespace {type string required 1 label Namespace}} [dict create namespace [datasetNamespaceCurrentGet]] ::GX::datasetBrowserCurrentApply .top
}
proc ::GX::datasetBrowserCurrentApply {values} {
    datasetNamespaceCurrentSet [sessionInspectionCurrentSession] [dict get $values namespace]
    datasetBrowserRefresh
    datasetNamespaceManagerRefresh
}
proc ::GX::datasetNamespaceManagerOpen {} {
    if {$::GX::currentSession eq {}} {error {Open a Session first.}}
    set w .datasetNamespaceManager
    if {[winfo exists $w]} {raise $w;focus $w.tree;return $w}
    toplevel $w;wm title $w {Dataset namespace manager};wm transient $w .top
    wm geometry $w 640x540
    ttk::frame $w.bar;pack $w.bar -side top -fill x -padx 8 -pady 8
    ttk::button $w.bar.create -text {Create namespace…} -command ::GX::datasetBrowserCreateDialog
    ttk::button $w.bar.current -text {Set current} -command ::GX::datasetNamespaceManagerCurrent
    ttk::button $w.bar.move -text {Move Dataset…} -command ::GX::datasetNamespaceManagerMove
    ttk::button $w.bar.migrate -text {Migrate legacy…} -command ::GX::datasetNamespaceMigrationDialog
    bind $w.bar <Configure> [list ::GX::uiFieldControlsLayout $w.bar %w]
    uiFieldControlsLayout $w.bar 640
    ttk::treeview $w.tree -show tree -selectmode browse
    uiFieldInspectionColumnsFit $w.tree
    ttk::scrollbar $w.scroll -command [list $w.tree yview]
    $w.tree configure -yscrollcommand [list $w.scroll set]
    pack $w.scroll -side right -fill y
    pack $w.tree -side top -fill both -expand 1 -padx {8 0}
    ttk::label $w.status -text {Select a namespace or Dataset. Drag a Dataset onto a namespace to move it.} -wraplength 610
    pack $w.status -side bottom -fill x -padx 8 -pady 7
    bind $w.tree <<TreeviewSelect>> ::GX::datasetNamespaceManagerInspect
    bind $w.tree <ButtonPress-1> [list ::GX::datasetNamespaceManagerDragStart %x %y]
    bind $w.tree <B1-Motion> [list ::GX::datasetNamespaceManagerDragMotion %x %y]
    bind $w.tree <ButtonRelease-1> [list ::GX::datasetNamespaceManagerDragFinish %x %y]
    datasetNamespaceManagerRefresh
    return $w
}
proc ::GX::datasetNamespaceManagerRefresh {} {
    set w .datasetNamespaceManager
    if {![winfo exists $w.tree]} return
    set tree $w.tree;set selected [lindex [$tree selection] 0]
    set opened {};foreach node [$tree children {}] {datasetBrowserRememberOpen $tree $node opened}
    $tree delete [$tree children {}]
    # Namespace management contains canonical registered Datasets only. The
    # separate browser owns the optional noncanonical single-input projection.
    if {$::GX::currentSession eq {}} {$w.status configure -text {Open a Session to manage Dataset namespaces.};return}
    set current [datasetNamespaceCurrentGet]
    foreach namespace [datasetNamespaceList] {
        set parent {};set parts {}
        foreach part [split $namespace /] {
            lappend parts $part;set id [datasetBrowserNode namespace [join $parts /]]
            if {![$tree exists $id]} {$tree insert $parent end -id $id -text $part -tags namespace -open 1}
            set parent $id
        }
    }
    foreach dataset [dict get [datasetCatalogSnapshot] datasets] {
        set id [dict get $dataset dataset_id];set parent [datasetBrowserNode namespace [dict get $dataset namespace]]
        $tree insert $parent end -id [datasetBrowserNode dataset $id] -text $id -tags dataset
    }
    dict for {node open} $opened {if {[$tree exists $node]} {$tree item $node -open $open}}
    if {$selected ne {}&&[$tree exists $selected]} {$tree selection set $selected}
    $w.status configure -text "Current namespace: $current. Drag a Dataset row onto a namespace to move it; its ID stays unchanged."
}
proc ::GX::datasetNamespaceManagerSelected {} {
    set tree .datasetNamespaceManager.tree
    set node [lindex [$tree selection] 0]
    if {$node eq {}} {error {Select a namespace or Dataset first.}}
    return $node
}
proc ::GX::datasetNamespaceManagerInspect {} {
    set w .datasetNamespaceManager;set node [lindex [$w.tree selection] 0]
    if {$node eq {}} return
    if {[string match namespace:* $node]} {
        set namespace [datasetBrowserValue $node]
        set count [llength [$w.tree children $node]]
        $w.status configure -text "Namespace $namespace — $count direct child item(s). Current: [datasetNamespaceCurrentGet]."
    } else {
        set id [datasetBrowserValue $node]
        $w.status configure -text "Dataset $id belongs to [datasetNamespaceGet [sessionInspectionCurrentSession] $id]. Drag it onto a namespace to move it; its ID stays unchanged."
    }
}
proc ::GX::datasetNamespaceManagerCurrent {} {
    set node [datasetNamespaceManagerSelected]
    if {[string match dataset:* $node]} {set node [.datasetNamespaceManager.tree parent $node]}
    datasetNamespaceCurrentSet [sessionInspectionCurrentSession] [datasetBrowserValue $node]
    datasetBrowserRefresh;datasetNamespaceManagerRefresh
}
proc ::GX::datasetNamespaceManagerMove {} {
    set node [datasetNamespaceManagerSelected]
    if {![string match dataset:* $node]} {error {Select a Dataset to move.}}
    datasetBrowserMoveDialog [datasetBrowserValue $node]
}
proc ::GX::datasetNamespaceManagerDragStart {x y} {
    variable ui
    set tree .datasetNamespaceManager.tree;set node [$tree identify row $x $y]
    unset -nocomplain ui(datasetNamespaceDrag)
    if {[string match dataset:* $node]} {set ui(datasetNamespaceDrag) [list [sessionInspectionCurrentSession] [datasetBrowserValue $node] $x $y]}
}
proc ::GX::datasetNamespaceManagerDragMotion {x y} {
    variable ui
    if {![info exists ui(datasetNamespaceDrag)]} return
    set node [.datasetNamespaceManager.tree identify row $x $y]
    if {[string match dataset:* $node]} {set node [.datasetNamespaceManager.tree parent $node]}
    if {[string match namespace:* $node]} {.datasetNamespaceManager.status configure -text "Drop to move [lindex $ui(datasetNamespaceDrag) 1] into [datasetBrowserValue $node]."}
}
proc ::GX::datasetNamespaceManagerDragFinish {x y} {
    variable ui
    if {![info exists ui(datasetNamespaceDrag)]} return
    lassign $ui(datasetNamespaceDrag) session id startX startY
    unset ui(datasetNamespaceDrag)
    if {abs($x-$startX)+abs($y-$startY)<8} return
    set tree .datasetNamespaceManager.tree;set node [$tree identify row $x $y]
    if {[string match dataset:* $node]} {set node [$tree parent $node]}
    if {![string match namespace:* $node]} return
    if {[catch {
        if {$session ne [sessionInspectionCurrentSession]} {error {Session changed during drag.}}
        datasetNamespaceSet $session $id [datasetBrowserValue $node]
        datasetBrowserRefresh;datasetNamespaceManagerRefresh
    } message]} {tk_messageBox -parent .datasetNamespaceManager -icon error -message $message}
}

proc ::GX::datasetPageActionsPopup {} {
    set w .top.nb.channels.browser.tools.actions
    set menu .top.nb.channels.bar.actionsMenu
    if {![winfo exists $w] || ![winfo exists $menu]} return
    uiMenuPopup $menu [winfo rootx $w] [expr {[winfo rooty $w]+[winfo height $w]}]
}
proc ::GX::datasetPageSaveSchema {} {
    .top.nb.channels.bar.save invoke
}
proc ::GX::datasetPageActivatePending {choice} {
    if {![datasetPageCanSwitch $choice]} return
    set ::GX::variableDatasetChoice $choice
    refreshNativeVariablesGui
    .top.nb select .top.nb.channels
    .top.nb.channels.views select .top.nb.channels.views.preview
    refreshCsvPreview
}
proc ::GX::datasetNamespaceMigrationDialog {} {
    set plan [datasetNamespaceMigrationPlan]
    if {![dict size [dict get $plan datasets]]&&![dict size [dict get $plan manifest_fields]]} {
        .datasetNamespaceManager.status configure -text {No legacy current namespace needs migration. Missing metadata already resolves to base without source writes.};return
    }
    set archive [tk_getSaveFile -parent .datasetNamespaceManager -title {Backup before migrating current to base} -defaultextension .gxtxt-session.zip]
    if {$archive eq {}} return
    if {[catch {set result [datasetNamespaceMigrate $::GX::currentSession $archive]} message]} {tk_messageBox -parent .datasetNamespaceManager -icon error -message $message;return}
    datasetNamespaceManagerRefresh;datasetBrowserRefresh
    .datasetNamespaceManager.status configure -text "Migration complete. Reversible Session backup: [dict get $result backup_archive]"
}
