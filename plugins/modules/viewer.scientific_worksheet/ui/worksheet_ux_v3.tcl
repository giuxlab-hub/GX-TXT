# Scientific Worksheet visual and interaction refinements.
# SPDX-License-Identifier: GPL-3.0-or-later
# This plugin-local file is sourced after the stable workbook implementation.

namespace eval ::GX::ScientificWorksheet {
    variable uxGridPending
    variable uxActiveRow
}

foreach method {open _uiRefresh _uiSelect _uiSetSelection _uiImportDialog _uiFunctionBrowser _uiFunctionSearch _uiApplyFunctionDialog _uiPlotDialog _uiPlotAction _uiTabs _uiRecalculateMode} {
    rename ::GX::ScientificWorksheet::$method ::GX::ScientificWorksheet::_ux_previous_$method
}

proc ::GX::ScientificWorksheet::_uxButton {parent name label source} {
    ttk::button $parent.$name -text $label -command [list $source invoke]
    pack $parent.$name -side left -padx {0 5} -pady 3
}

proc ::GX::ScientificWorksheet::_uxToolbar {w} {
    variable ui
    pack forget $w.toolbar $w.actions $w.extra
    ttk::frame $w.ux -padding {8 5 8 4}
    pack $w.ux -before $w.formula -fill x

    ttk::frame $w.ux.heading
    pack $w.ux.heading -fill x -pady {0 5}
    ttk::label $w.ux.heading.title -text "Scientific Worksheet" -style GXWorksheetTitle.TLabel
    ttk::label $w.ux.heading.subtitle -text "Session workbook · Dataset snapshots stay linked to their sources" -style GXWorksheetHint.TLabel
    pack $w.ux.heading.title -side left
    pack $w.ux.heading.subtitle -side right

    ttk::frame $w.ux.primary
    ttk::frame $w.ux.secondary
    ttk::frame $w.ux.tertiary
    pack $w.ux.primary $w.ux.secondary -fill x
    foreach {group caption} {file Workbook data Data science Analyze edit Edit calculate Calculate} {
        set row [expr {$group in {file data science} ? "primary" : "secondary"}]
        ttk::labelframe $w.ux.$row.$group -text $caption -padding {6 1 1 2}
        pack $w.ux.$row.$group -side left -padx {0 7} -pady 1
    }
    _uxButton $w.ux.primary.file save "Save" $w.toolbar.save
    _uxButton $w.ux.primary.file load "Open…" $w.toolbar.load
    _uxButton $w.ux.primary.data import "Bind Dataset…" $w.toolbar.import
    _uxButton $w.ux.primary.data names "Columns / Ranges…" $w.toolbar.names
    _uxButton $w.ux.primary.data sort "Sort / Filter…" $w.actions.sort
    _uxButton $w.ux.primary.data convert "Convert Unit…" $w.actions.convert
    _uxButton $w.ux.primary.science functions "Functions…" $w.toolbar.functions
    _uxButton $w.ux.primary.science plot "Plot / Publish…" $w.toolbar.plot

    foreach {name label source} {
        undo Undo actions.undo redo Redo actions.redo
        filldown "Fill Down" actions.filldown fillright "Fill Right" actions.fillright
        clear Clear actions.clear inspect "Inspect Cell" toolbar.inspect
    } {
        _uxButton $w.ux.secondary.edit $name $label $w.$source
    }
    _uxButton $w.ux.secondary.calculate mode "Mode: [dict get $ui($w,book) options calculation_mode]" $w.extra.mode
    _uxButton $w.ux.secondary.calculate selection "Selection" $w.extra.selection
    _uxButton $w.ux.secondary.calculate sheet "Sheet" $w.extra.sheet
    _uxButton $w.ux.secondary.calculate workbook "Workbook" $w.extra.workbook
    ttk::labelframe $w.ux.tertiary.calculate -text Calculate -padding {6 1 1 2}
    foreach {name label source} {
        mode "Mode: automatic" extra.mode selection Selection extra.selection
        sheet Sheet extra.sheet workbook Workbook extra.workbook
    } {
    _uxButton $w.ux.tertiary.calculate $name $label $w.$source
    }
    pack $w.ux.tertiary.calculate -side left -padx {0 7} -pady 1
    ttk::labelframe $w.ux.tertiary.science -text Analyze -padding {6 1 1 2}
    _uxButton $w.ux.tertiary.science functions "Functions…" $w.toolbar.functions
    _uxButton $w.ux.tertiary.science plot "Plot / Publish…" $w.toolbar.plot

    ttk::style configure GXWorksheetTitle.TLabel -font {TkDefaultFont 12 bold} -foreground "#183f5a"
    ttk::style configure GXWorksheetHint.TLabel -foreground "#536879"
    ttk::style configure GXWorksheetName.TLabel -font {TkDefaultFont 10 bold} -foreground "#1b5c84"
    ttk::style configure GXWorksheetGrid.Treeview -background white -fieldbackground white -foreground "#253747" -rowheight 23
    ttk::style configure GXWorksheetGrid.Treeview.Heading -font {TkDefaultFont 9 bold} -foreground "#234c65"
    $w.grid.table configure -style GXWorksheetGrid.Treeview
    $w.grid.table tag configure ux_active_row -background "#edf6fc"
    $w.grid.table tag configure ux_error_row -foreground "#a43232"
    $w.grid.table column row -anchor e -width 52 -stretch 0
    foreach col {A B C D E F G H I J K L} {$w.grid.table column $col -anchor w}

    $w.formula.active configure -style GXWorksheetName.TLabel -anchor center -width 7
    ttk::label $w.formula.fx -text "fx" -style GXWorksheetName.TLabel
    pack $w.formula.fx -before $w.formula.entry -side left -padx {0 8}
    $w.formula.apply configure -text "Apply Formula"
    ttk::button $w.formula.pick -text "Pick Reference" -command [list $w.extra.pick invoke]
    pack $w.formula.pick -side right -padx {4 0}
    pack configure $w.formula -padx 8 -pady {2 3}

    $w.footer.status configure -wraplength 720 -justify left
    ttk::label $w.footer.help -text "Double-click or F2 to edit · drag to select · Ctrl+C / Ctrl+V" -style GXWorksheetHint.TLabel
    pack $w.footer.help -side right -padx 8

    bind $w.grid.table <Configure> +[list ::GX::ScientificWorksheet::_uxScheduleGrid $w]
    bind $w.grid.sx <B1-Motion> +[list ::GX::ScientificWorksheet::_uxScheduleGrid $w]
    bind $w.grid.sx <ButtonRelease-1> +[list ::GX::ScientificWorksheet::_uxScheduleGrid $w]
    bind $w.grid.table <ButtonRelease-1> +[list ::GX::ScientificWorksheet::_uxScheduleGrid $w]
    bind $w <Configure> +[list ::GX::ScientificWorksheet::_uxResponsive $w]
    after idle [list ::GX::ScientificWorksheet::_uxResponsive $w]
}

proc ::GX::ScientificWorksheet::_uxResponsive {w} {
    if {![winfo exists $w.ux]} return
    if {[winfo width $w] < 1080} {
        if {[winfo manager $w.ux.secondary.calculate] ne ""} {pack forget $w.ux.secondary.calculate}
        if {[winfo manager $w.ux.primary.science] ne ""} {pack forget $w.ux.primary.science}
        if {[winfo manager $w.ux.tertiary] eq ""} {pack $w.ux.tertiary -fill x}
        if {[winfo manager $w.ux.tertiary.science] eq ""} {pack $w.ux.tertiary.science -side left -before $w.ux.tertiary.calculate -padx {0 7} -pady 1}
    } else {
        if {[winfo manager $w.ux.tertiary] ne ""} {pack forget $w.ux.tertiary}
        if {[winfo manager $w.ux.tertiary.science] ne ""} {pack forget $w.ux.tertiary.science}
        if {[winfo manager $w.ux.primary.science] eq ""} {pack $w.ux.primary.science -side left -padx {0 7} -pady 1}
        if {[winfo manager $w.ux.secondary.calculate] eq ""} {
            pack $w.ux.secondary.calculate -side left -padx {0 7} -pady 1
        }
    }
}

proc ::GX::ScientificWorksheet::_uxScheduleGrid {w} {
    variable uxGridPending
    if {![winfo exists $w.grid.table]} return
    if {[info exists uxGridPending($w)] && $uxGridPending($w)} return
    set uxGridPending($w) 1
    after idle [list ::GX::ScientificWorksheet::_uxGridlines $w]
}

proc ::GX::ScientificWorksheet::_uxGridlines {w} {
    variable uxGridPending
    set uxGridPending($w) 0
    if {![winfo exists $w.grid.table]} return
    foreach child [winfo children $w.grid] {
        if {[string match *.uxline_* $child]} {destroy $child}
    }
    set table $w.grid.table
    set rows [$table children {}]
    set first ""
    set last ""
    foreach row $rows {
        set box [$table bbox $row #1]
        if {![llength $box]} continue
        if {$first eq ""} {set first $row}
        set last $row
    }
    if {$first eq ""} return
    set offsetX [winfo x $table]
    set offsetY [winfo y $table]
    set leftBox [$table bbox $first #1]
    set rightBox [$table bbox $first #13]
    if {![llength $rightBox]} {
        set right [winfo width $table]
    } else {
        set right [expr {[lindex $rightBox 0]+[lindex $rightBox 2]}]
    }
    set right [expr {min($right,[winfo width $table])}]
    set yTop [lindex $leftBox 1]
    set lastBox [$table bbox $last #1]
    set yBottom [expr {[lindex $lastBox 1]+[lindex $lastBox 3]}]
    set color "#dbe5ec"
    set n 0
    foreach row $rows {
        set box [$table bbox $row #1]
        if {![llength $box]} continue
        set y [expr {[lindex $box 1]+[lindex $box 3]-1}]
        frame $w.grid.uxline_h[incr n] -background $color
        place $w.grid.uxline_h$n -x $offsetX -y [expr {$offsetY+$y}] -width $right -height 1
    }
    for {set col 1} {$col <= 13} {incr col} {
        set box [$table bbox $first #$col]
        if {![llength $box]} continue
        set x [expr {[lindex $box 0]+[lindex $box 2]-2}]
        if {$x < 0 || $x > [winfo width $table]} continue
        frame $w.grid.uxline_v$col -background $color
        place $w.grid.uxline_v$col -x [expr {$offsetX+$x}] -y [expr {$offsetY+$yTop}] -width 1 -height [expr {$yBottom-$yTop}]
    }
    _uiDrawSelection $w
}

proc ::GX::ScientificWorksheet::_uxMarkActive {w} {
    variable ui
    variable uxActiveRow
    if {![winfo exists $w.grid.table]} return
    set table $w.grid.table
    if {[info exists uxActiveRow($w)] && [$table exists $uxActiveRow($w)]} {
        set tags [$table item $uxActiveRow($w) -tags]
        set index [lsearch -exact $tags ux_active_row]
        if {$index >= 0} {$table item $uxActiveRow($w) -tags [lreplace $tags $index $index]}
    }
    lassign [_parts $ui($w,active)] column row
    if {[$table exists $row]} {
        $table item $row -tags [lsort -unique [concat [$table item $row -tags] ux_active_row]]
        set uxActiveRow($w) $row
    }
}

proc ::GX::ScientificWorksheet::open {{context {}}} {
    set w [_ux_previous_open $context]
    if {![winfo exists $w.ux]} {
        _uxToolbar $w
        set width [expr {min(1100,max(900,[winfo screenwidth $w]-60))}]
        set height [expr {min(720,max(580,[winfo screenheight $w]-90))}]
        wm geometry $w [format "%dx%d+30+30" $width $height]
    }
    _uxMarkActive $w
    _uxScheduleGrid $w
    return $w
}
proc ::GX::ScientificWorksheet::_uiRefresh {w} {
    _ux_previous__uiRefresh $w
    _uxMarkActive $w
    _uxScheduleGrid $w
}
proc ::GX::ScientificWorksheet::_uiSelect {w} {
    variable ui
    _ux_previous__uiSelect $w
    set address $ui($w,active)
    set ui($w,status) "Active cell $address"
    if {[dict exists $ui($w,book) cells $address lineage]} {
        set lineage [dict get $ui($w,book) cells $address lineage]
        if {[dict exists $lineage dataset_id]} {
            append ui($w,status) " · source [dict get $lineage dataset_id]"
            if {[dict exists $lineage variable_id]} {append ui($w,status) " / [dict get $lineage variable_id]"}
            if {[dict exists $lineage source_row]} {append ui($w,status) " · source row [expr {[dict get $lineage source_row]+1}]"}
        }
    }
    _uxMarkActive $w
}
proc ::GX::ScientificWorksheet::_uiSetSelection {w from to additive} {
    _ux_previous__uiSetSelection $w $from $to $additive
    _uxMarkActive $w
}

proc ::GX::ScientificWorksheet::_uiTabs {w} {
    variable ui
    _ux_previous__uiTabs $w
    if {![winfo exists $w.sheets]} return
    ttk::label $w.sheets.caption -text "SHEETS" -style GXWorksheetHint.TLabel
    pack $w.sheets.caption -side left -before [lindex [winfo children $w.sheets] 0] -padx {4 8}
    foreach name [sheetNames $ui($w,book)] {
        if {$name eq [activeSheet $ui($w,book)]} {
            $w.sheets.s_[string map {" " _} $name] configure -style GXWorksheetActive.TButton
        }
    }
    ttk::style configure GXWorksheetActive.TButton -font {TkDefaultFont 9 bold}
    foreach {name label source} {
        rename "Rename…" actions.rename
        duplicate "Duplicate…" actions.duplicate
        delete "Delete…" actions.delete
    } {
        ttk::button $w.sheets.$name -text $label -command [list $w.$source invoke]
        pack $w.sheets.$name -side right -padx {2 4}
    }
}

proc ::GX::ScientificWorksheet::_uiImportDialog {w} {
    _ux_previous__uiImportDialog $w
    set d $w.import
    foreach child [winfo children $d] {pack forget $child}
    wm title $d "Bind Session Dataset to Worksheet"
    wm geometry $d 640x660
    ttk::label $d.ux_intro -text "Choose a Session Dataset, select variables, then choose where their values begin. Binding copies a snapshot and preserves source row identity." -wraplength 585 -justify left
    pack $d.ux_intro -fill x -padx 12 -pady {10 8}
    $d.l_dataset configure -text "Source Dataset"
    pack $d.l_dataset $d.datasets -fill x -padx 12 -pady {2 1}
    $d.choose configure -text "Variables to bind · Ctrl or Shift selects multiple. IDs, types, and units are shown."
    pack $d.choose -fill x -padx 12 -pady {9 2}
    pack $d.variables -fill both -expand 1 -padx 12
    $d.startlabel configure -text "Destination first column"
    pack $d.startlabel $d.start -fill x -padx 12 -pady {8 1}
    $d.l_first configure -text "Destination first row"
    pack $d.l_first $d.e_first -fill x -padx 12 -pady {4 1}
    $d.l_limit configure -text "Maximum source rows (up to 20,000)"
    pack $d.l_limit $d.e_limit -fill x -padx 12 -pady {4 1}
    $d.l_selection configure -text "Dataset Selection ID (optional)"
    pack $d.l_selection $d.selections -fill x -padx 12 -pady {4 1}
    ttk::button $d.ux_advanced -text "Manual column mapping…" -command [list ::GX::ScientificWorksheet::_uxToggleMapping $d]
    pack $d.ux_advanced -anchor w -padx 12 -pady {8 1}
    $d.l_mappings configure -text "Advanced mapping: A=variable_id B=variable_id"
    $d.go configure -text "Bind Selected Variables"
    pack $d.go -anchor e -padx 12 -pady {5 11}
    if {![llength [::GX::sessionInspectionDatasetIds]]} {
        $d.ux_intro configure -text "This Session has no Dataset to bind. You can still edit Worksheet cells and formulas."
        $d.go configure -state disabled
    }
}
proc ::GX::ScientificWorksheet::_uxToggleMapping {d} {
    if {[winfo manager $d.e_mappings] ne ""} {
        pack forget $d.l_mappings $d.e_mappings
    } else {
        pack $d.l_mappings $d.e_mappings -before $d.go -fill x -padx 12 -pady {2 1}
    }
}
proc ::GX::ScientificWorksheet::_uiRecalculateMode {w} {
    variable ui
    _ux_previous__uiRecalculateMode $w
    set label "Mode: [dict get $ui($w,book) options calculation_mode]"
    foreach widget [list $w.ux.secondary.calculate.mode $w.ux.tertiary.calculate.mode] {
        if {[winfo exists $widget]} {$widget configure -text $label}
    }
}

proc ::GX::ScientificWorksheet::_uiFunctionBrowser {w} {
    _ux_previous__uiFunctionBrowser $w
    set d $w.functions
    wm title $d "Worksheet Function Browser"
    wm geometry $d 900x670
    ttk::label $d.ux_intro -text "Search public scientific operations, inspect arguments, then insert a formula or apply a guided result." -wraplength 850
    pack $d.ux_intro -before $d.search -fill x -padx 10 -pady {8 3}
    ttk::label $d.ux_search -text "Search by operation or subject"
    pack $d.ux_search -before $d.search -anchor w -padx 10
    pack configure $d.search -padx 10 -pady {2 6}
    pack configure $d.tree -padx 10
    pack configure $d.help -padx 10 -pady {6 4}
    ttk::label $d.ux_count -text ""
    pack $d.ux_count -side left -padx 10 -pady 7
    _uiFunctionSearch $w $d
}
proc ::GX::ScientificWorksheet::_uiFunctionSearch {w d} {
    variable ui
    _ux_previous__uiFunctionSearch $w $d
    if {$ui($w,function_query) ne ""} {
        foreach parent [$d.tree children {}] {
            if {![llength [$d.tree children $parent]]} {$d.tree delete [list $parent]}
        }
    }
    if {![winfo exists $d.ux_count]} return
    set count 0
    foreach parent [$d.tree children {}] {incr count [llength [$d.tree children $parent]]}
    $d.ux_count configure -text "$count operations shown"
    $d.tree column #0 -width 315
    $d.tree column api -width 100
    $d.tree column summary -width 430
}
proc ::GX::ScientificWorksheet::_uiApplyFunctionDialog {w browser} {
    _ux_previous__uiApplyFunctionDialog $w $browser
    set d $w.applyfunction
    if {![winfo exists $d]} return
    set count [set ::GX::ScientificWorksheet::ui($w,apply_count)]
    set extra [expr {[winfo exists $d.modelkind] ? 75 : 0}]
    wm geometry $d 650x[expr {min(700,max(365,315+$count*42+$extra))}]
    ttk::label $d.ux_intro -text "Guided operation · provide cells, ranges or literal values. Preview result fields before choosing a destination." -wraplength 610 -justify left
    pack $d.ux_intro -before $d.help -fill x -padx 10 -pady {10 4}
}
proc ::GX::ScientificWorksheet::_uiPlotDialog {w mode} {
    _ux_previous__uiPlotDialog $w $mode
    set d $w.plot
    wm title $d "Plot and Publish Worksheet Results"
    wm geometry $d 515x485
    ttk::label $d.ux_intro -text "Choose Worksheet columns and rows. Preview opens a temporary graph; Publish creates a Session Dataset; Retain also saves a Plot Dataset graph." -wraplength 470 -justify left
    pack $d.ux_intro -before $d.l_x -fill x -padx 10 -pady {9 7}
    foreach key {x y z first last dataset} {
        pack configure $d.l_$key -padx 10 -pady {2 0}
        pack configure $d.e_$key -padx 10 -pady {0 2}
    }
    $d.preview configure -text "Preview Graph"
    $d.publish configure -text "Publish Dataset"
    $d.retain configure -text "Publish + Retain Graph"
}
proc ::GX::ScientificWorksheet::_uiPlotAction {w action} {
    variable ui
    _ux_previous__uiPlotAction $w $action
    if {$action eq "preview" && [winfo exists $w.preview.image]} {
        set ui($w,status) "Temporary Plot Dataset preview opened."
    } elseif {$action in {publish retain} && [lsearch -exact [::GX::sessionInspectionDatasetIds] $ui($w,plot_dataset)] >= 0} {
        set ui($w,status) "Published Dataset $ui($w,plot_dataset) from this Worksheet."
    }
}
