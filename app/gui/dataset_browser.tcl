# SPDX-License-Identifier: GPL-3.0-or-later
# Browser projection of the canonical catalog. Tree selection is only a visual
# highlight; explicit glyph activation changes the existing inspection choice.
proc ::GX::datasetBrowserNode {kind value} {return $kind:[binary encode hex [encoding convertto utf-8 $value]]}
proc ::GX::datasetBrowserValue {node} {return [encoding convertfrom utf-8 [binary decode hex [string range $node [expr {[string first : $node]+1}] end]]]}
proc ::GX::datasetBrowserBuild {} {
    variable ui
    set f .top.nb.channels
    if {![winfo exists $f]} return
    if {![winfo exists $f.browser]} {
        ttk::labelframe $f.browser -text Datasets
        ttk::frame $f.browser.tools
        pack $f.browser.tools -side top -fill x
        foreach {key icon command tip} {
            refresh refresh datasetPageForceRefresh {Force resynchronize Dataset catalog and Preview}
            save save datasetPageSaveSchema {Save canonical variable schema}
            open open datasetPreviewOpenCurrent {Open active Dataset}
            edit edit datasetPageContextEdit {Edit the selected Dataset section}
        } {
            ttk::button $f.browser.tools.$key -padding 1 -image [native2DViewportGlyph $icon] -command [list ::GX::datasetPageAction $command]
            pack $f.browser.tools.$key -side left -padx 3
            bind $f.browser.tools.$key <Enter> [list ::GX::native2DViewportTooltipShow %W $tip]
            bind $f.browser.tools.$key <Leave> {catch {destroy .gxViewportTip}}
        }
        pack forget $f.bar.refresh $f.bar.save
        ttk::menubutton $f.browser.tools.print -padding 1 -image [native2DViewportGlyph print] -menu $f.browser.tools.print.menu
        menu $f.browser.tools.print.menu -tearoff 0
        foreach {format label} {print {Print current view…} text {Export current view as text…} pdf {Save current view as PDF…}} {
            $f.browser.tools.print.menu add command -label $label -command [list ::GX::datasetPageAction datasetPageExportCurrent $format]
        }
        pack $f.browser.tools.print -side left -padx 3
        bind $f.browser.tools.print <Enter> {::GX::native2DViewportTooltipShow %W {Print / Export current Dataset view}}
        bind $f.browser.tools.print <Leave> {catch {destroy .gxViewportTip}}
        ttk::button $f.browser.manage -padding 1 -image [native2DViewportGlyph namespace] -command ::GX::datasetNamespaceManagerOpen
        pack $f.browser.manage -in $f.browser.tools -side left -padx 3 -before $f.browser.tools.open
        bind $f.browser.manage <Enter> {::GX::native2DViewportTooltipShow %W {Manage Dataset namespaces}}
        bind $f.browser.manage <Leave> {catch {destroy .gxViewportTip}}
        ttk::button $f.browser.current -text {Current: base} -command ::GX::datasetPageActionsPopup
        pack $f.browser.current -side top -fill x -padx 3 -pady 3
        ttk::treeview $f.browser.tree -show tree -selectmode browse -height 20
        ttk::scrollbar $f.browser.scroll -command [list $f.browser.tree yview]
        $f.browser.tree configure -yscrollcommand [list $f.browser.scroll set]
        $f.browser.tree column #0 -width 260 -minwidth 180
        pack $f.browser.scroll -side right -fill y
        pack $f.browser.tree -fill both -expand 1
        bind $f.browser.tree <Button-1> [list ::GX::datasetBrowserClick %x %y]
        bind $f.browser.tree <Button-3> [list ::GX::datasetBrowserContext %x %y %X %Y]
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
proc ::GX::datasetBrowserActiveRefresh {} {
    variable currentSession
    if {![winfo exists .top.nb.channels.browser.current]} return
    datasetPreviewUpdateOpenButton
    if {$currentSession ne {}} {
        .top.nb.channels.browser.current state !disabled
        lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode active
        .top.nb.channels.browser.current configure -text "Current: [datasetNamespaceCurrentGet]\nActive Dataset: [expr {$mode eq {imported} ? $active : {None}}]"
    }
 }
proc ::GX::datasetBrowserRefresh {} {
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
    set projection [list $single $inputPath $pending [dict get $snapshot session_token] $namespaces [dict get $snapshot datasets]]
    # Activation changes content, not the catalog. Preserve browser rows,
    # expansion, focus and scroll until its canonical projection changes.
    if {[info exists ui(datasetBrowserProjection)]&&$ui(datasetBrowserProjection) eq $projection} return
    set ui(datasetBrowserProjection) $projection
    set scroll [lindex [$tree yview] 0]
    set highlighted [lindex [$tree selection] 0]
    set opened {}
    foreach node [$tree children {}] {datasetBrowserRememberOpen $tree $node opened}
    $tree delete [$tree children {}]
    if {$single ne {}} {$tree insert {} end -id [datasetBrowserNode single $single] -text $single -image [native2DViewportGlyph select 18] -tags single}
    if {$currentSession eq {}} {.top.nb.channels.browser.current configure -text {Current namespace…} -state disabled;return}
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
    foreach dataset [dict get $snapshot datasets] {
        set id [dict get $dataset dataset_id];set parent [datasetBrowserNode namespace [dict get $dataset namespace]]
        $tree insert $parent end -id [datasetBrowserNode dataset $id] -text $id -image [native2DViewportGlyph select 18] -tags dataset
    }
    foreach choice $pending {
        $tree insert [datasetBrowserNode namespace pending] end -id [datasetBrowserNode pending $choice] -text [string range $choice 9 end] -image [native2DViewportGlyph select 18] -tags pending
    }
    $tree yview moveto $scroll
    dict for {node open} $opened {if {[$tree exists $node]} {$tree item $node -open $open}}
    if {$highlighted ne {}&&[$tree exists $highlighted]} {$tree selection set $highlighted}
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
        $menu add separator
        $menu add command -label {Rename Dataset…} -command [list ::GX::datasetRenameSelectedFromGui $value]
        $menu add command -label {Delete Dataset…} -command [list ::GX::datasetDeleteSelectedFromGui $value]
        $menu add command -label {Export Dataset ZIP…} -command [list ::GX::portableResourceGuiExportDataset $value]
    } elseif {[string match pending:* $node]} {
        $menu add command -label {Preview Pending source} -command [list ::GX::datasetPageActivatePending $value]
        $menu add command -label {Import required before move or rename} -state disabled
    } else {
        $menu add command -label {Set as current namespace} -command [list ::GX::datasetBrowserCurrentApply [dict create namespace $value]]
        $menu add command -label {Create namespace…} -command [list ::GX::datasetBrowserCreateDialog $value]
    }
    ::GX::uiMenuPopup $menu $X $Y
}
proc ::GX::datasetBrowserMoveDialog {id {create 0}} {
    variable currentSession
    set title [expr {$create?"Create namespace and move Dataset $id":"Move Dataset $id — ID and references stay unchanged"}]
    ::GX::uiFieldFormCreate .datasetNamespaceMove $title {namespace {type string required 1 label Namespace}} [dict create namespace [datasetNamespaceGet $currentSession $id]] [list ::GX::datasetBrowserMoveApply $currentSession $id $create] .top
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
    pack $w.bar.create $w.bar.current $w.bar.move $w.bar.migrate -side left -padx 4
    ttk::treeview $w.tree -show tree -selectmode browse
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
    if {$single ne {}} {$tree insert {} end -id [datasetBrowserNode single $single] -text $single -image [native2DViewportGlyph select 18] -tags single}
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
    set w .top.nb.channels.browser.current
    tk_popup .top.nb.channels.bar.actionsMenu [winfo rootx $w] [expr {[winfo rooty $w]+[winfo height $w]}]
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
