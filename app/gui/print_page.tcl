# SPDX-License-Identifier: GPL-3.0-or-later
# The existing main Print / PDF page. No separate Print Viewer or window.
proc ::GX::buildPrintPage {} {
    variable cfg;variable ui
    printStudioInit
    set f .top.nb.print
    ttk::frame $f.menurow;pack $f.menurow -fill x
    set catalog [printStudioCommandCatalog];set handlers {}
    dict for {id descriptor} $catalog {dict set handlers $id [dict create command [list ::GX::printStudioInvoke $id] enabled [list ::GX::printStudioEnabled $id]]}
    viewerCommandCatalogRegister framework.print_studio $catalog printing.shortcuts shortcuts framework
    viewerCommandsAttach $f framework.print_studio $handlers ::GX::printStudioScopeActive {} {session_scoped 0}
    foreach {name label actions} {
        file File {new open save - export open_pdf - print setup}
        edit Edit {add legacy - remove duplicate up down - undo redo}
        view View {previous next - fit_page fit_width zoom_in zoom_out - browser log}
        layout Layout {setup}
        help Help {help}
    } {
        ttk::menubutton $f.menurow.$name -text $label -menu $f.menurow.$name.menu
        viewerGuiMenuMount $f $f.menurow.$name.menu $actions
        pack $f.menurow.$name -side left
    }
    ttk::frame $f.tools;pack $f.tools -fill x
    viewerCommandToolbarCreate $f $f.tools {add preview cancel_document export print fit_page fit_width previous next zoom_in zoom_out log}
    ttk::frame $f.status;pack $f.status -side bottom -fill x
    ttk::label $f.status.document -textvariable ::GX::ui(printStatus) -anchor w -wraplength 850
    ttk::label $f.status.cups -textvariable ::GX::ui(cupsStatus) -anchor w -wraplength 850
    pack $f.status.document $f.status.cups -fill x -padx 5 -pady 2
    ttk::panedwindow $f.vertical -orient vertical;pack $f.vertical -fill both -expand 1
    ttk::panedwindow $f.vertical.main -orient horizontal;$f.vertical add $f.vertical.main -weight 1
    set main $f.vertical.main
    ttk::frame $main.preview;ttk::notebook $main.dock -width 350
    $main add $main.preview -weight 1;$main add $main.dock -weight 0
    set ui(printDock) $main.dock
    ttk::frame $main.preview.navigation;pack $main.preview.navigation -fill x
    ttk::label $main.preview.navigation.page -text Page
    ttk::spinbox $main.preview.navigation.number -from 1 -to 1 -width 5 -textvariable ::GX::PrintStudio::state(currentPage) -command ::GX::printStudioPageShow
    ttk::label $main.preview.navigation.total -textvariable ::GX::PrintStudio::state(pageCount)
    ttk::label $main.preview.navigation.status -textvariable ::GX::PrintStudio::state(documentStatus) -anchor w
    pack $main.preview.navigation.page $main.preview.navigation.number $main.preview.navigation.total -side left -padx 3
    pack $main.preview.navigation.status -side left -fill x -expand 1 -padx 8
    bind $main.preview.navigation.number <Return> ::GX::printStudioPageShow
    set ui(printPageNumber) $main.preview.navigation.number
    ttk::frame $main.preview.pages;pack $main.preview.pages -side left -fill y
    ttk::treeview $main.preview.pages.tree -show tree -height 5
    $main.preview.pages.tree column #0 -width 105 -minwidth 45 -stretch 0
    ttk::scrollbar $main.preview.pages.scroll -command [list $main.preview.pages.tree yview]
    $main.preview.pages.tree configure -yscrollcommand [list $main.preview.pages.scroll set]
    pack $main.preview.pages.scroll -side right -fill y
    pack $main.preview.pages.tree -fill y -expand 1
    ttk::style configure PrintPages.Treeview -rowheight 140
    $main.preview.pages.tree configure -style PrintPages.Treeview
    set ui(printPages) $main.preview.pages.tree
    bind $ui(printPages) <<TreeviewSelect>> ::GX::printStudioPageSelected
    ttk::frame $main.preview.viewport;pack $main.preview.viewport -fill both -expand 1
    canvas $main.preview.viewport.canvas -background #66717c -highlightthickness 0 -width 700 -height 580 -xscrollincrement 20 -yscrollincrement 20
    ttk::scrollbar $main.preview.viewport.y -command [list $main.preview.viewport.canvas yview]
    ttk::scrollbar $main.preview.viewport.x -orient horizontal -command [list $main.preview.viewport.canvas xview]
    $main.preview.viewport.canvas configure -yscrollcommand [list $main.preview.viewport.y set] -xscrollcommand [list $main.preview.viewport.x set]
    grid $main.preview.viewport.canvas -row 0 -column 0 -sticky nsew
    grid $main.preview.viewport.y -row 0 -column 1 -sticky ns
    grid $main.preview.viewport.x -row 1 -column 0 -sticky ew
    grid rowconfigure $main.preview.viewport 0 -weight 1;grid columnconfigure $main.preview.viewport 0 -weight 1
    set ui(printPageCanvas) $main.preview.viewport.canvas
    $ui(printPageCanvas) create text 30 30 -anchor nw -width 550 -fill white -font TkHeadingFont -text {No assembled document. Add content, then Update Preview.}
    bind $ui(printPageCanvas) <ButtonPress-1> {%W scan mark %x %y;focus %W}
    bind $ui(printPageCanvas) <B1-Motion> {%W scan dragto %x %y 1}
    bind $ui(printPageCanvas) <Button-4> {%W yview scroll -3 units}
    bind $ui(printPageCanvas) <Button-5> {%W yview scroll 3 units}
    bind $ui(printPageCanvas) <Configure> ::GX::printStudioPageResize
    foreach {id title} {content Content document Document setup {Page setup} printer {Printer / Export}} {ttk::frame $main.dock.$id -padding 6;$main.dock add $main.dock.$id -text $title}
    set ui(printDocumentTab) $main.dock.document;set ui(printSetupTab) $main.dock.setup
    set c [uiFieldScrollableCreate $main.dock.content.form 330];pack $main.dock.content.form -fill both -expand 1
    ttk::frame $c.search;pack $c.search -fill x
    ttk::entry $c.search.query -textvariable ::GX::PrintStudio::state(query)
    ttk::button $c.search.refresh -text Refresh -command {::GX::printStudioCatalogRefresh 1}
    pack $c.search.refresh -side right;pack $c.search.query -fill x -expand 1
    bind $c.search.query <KeyRelease> ::GX::printStudioCatalogSchedule
    ttk::frame $c.list;pack $c.list -fill both -expand 1 -pady 5
    ttk::treeview $c.list.tree -columns {kind} -show {tree headings} -height 8 -selectmode browse
    $c.list.tree heading #0 -text {Session content};$c.list.tree column #0 -width 210 -minwidth 90
    $c.list.tree heading kind -text Kind;$c.list.tree column kind -width 95 -minwidth 60
    ttk::scrollbar $c.list.scroll -command [list $c.list.tree yview];$c.list.tree configure -yscrollcommand [list $c.list.scroll set]
    pack $c.list.scroll -side right -fill y;pack $c.list.tree -fill both -expand 1
    set ui(printContentTree) $c.list.tree
    bind $c.list.tree <<TreeviewSelect>> ::GX::printStudioSourceSelect
    canvas $c.preview -height 165 -width 300 -background white -highlightthickness 1 -highlightbackground #aab0b6
    pack $c.preview -fill x;set ui(printSourceCanvas) $c.preview
    ttk::label $c.previewStatus -textvariable ::GX::PrintStudio::state(sourceStatus) -wraplength 320 -justify left;pack $c.previewStatus -fill x -pady 3
    text $c.summary -height 5 -width 30 -wrap word -state disabled;pack $c.summary -fill x
    set ui(printSourceSummary) $c.summary
    ttk::label $c.representationLabel -text {Print representation};pack $c.representationLabel -anchor w
    ttk::combobox $c.representation -state readonly -textvariable ::GX::PrintStudio::state(representation)
    uiFieldSelectorWithinViewer $c.representation .
    pack $c.representation -fill x;set ui(printRepresentation) $c.representation
    ttk::frame $c.actions;pack $c.actions -fill x -pady 4
    ttk::button $c.actions.add -text {Add selected content} -command {::GX::viewerCommandInvoke .top.nb.print add}
    ttk::button $c.actions.cancel -text {Cancel source Preview} -command ::GX::printStudioSourceCancel
    pack $c.actions.add $c.actions.cancel -fill x
    set d [uiFieldScrollableCreate $main.dock.document.form 330];pack $main.dock.document.form -fill both -expand 1
    ttk::label $d.savedLabel -text {Saved Session composition};pack $d.savedLabel -anchor w
    ttk::combobox $d.saved -state readonly -textvariable ::GX::PrintStudio::state(savedChoice);uiFieldSelectorWithinViewer $d.saved .;pack $d.saved -fill x;set ui(printSaved) $d.saved
    ttk::button $d.open -text {Open selected composition} -command {if {[catch {::GX::printStudioOpenSelected} m]} {set ::GX::ui(printStatus) $m}};pack $d.open -fill x -pady 4
    ttk::treeview $d.queue -columns {kind source} -show {tree headings} -height 8 -selectmode extended
    $d.queue heading #0 -text {Ordered content};$d.queue column #0 -width 170 -minwidth 80
    foreach {id title width} {kind Type 65 source Source 100} {$d.queue heading $id -text $title;$d.queue column $id -width $width -minwidth 50}
    pack $d.queue -fill both -expand 1;set ui(printQueue) $d.queue
    bind $d.queue <<TreeviewSelect>> {::GX::printStudioItemSelected;::GX::viewerGuiActionsRefresh .top.nb.print}
    ttk::frame $d.actions;pack $d.actions -fill x
    foreach {id title} {remove Remove up Up down Down duplicate Duplicate} {ttk::button $d.actions.$id -text $title -command [list ::GX::viewerCommandInvoke $f $id];pack $d.actions.$id -side left}
    foreach {key title} {item_columns {Table Variable IDs (comma-separated)} item_start {First source row (zero-based)} item_count {Explicit row count (maximum 10000)}} {ttk::label $d.l$key -text $title -anchor w;ttk::entry $d.$key -textvariable ::GX::PrintStudio::state($key);pack $d.l$key $d.$key -fill x -pady 2}
    ttk::button $d.apply -text {Apply item columns / range} -command ::GX::printStudioItemApply;pack $d.apply -fill x -pady 4
    set s [uiFieldScrollableCreate $main.dock.setup.form 330];pack $main.dock.setup.form -fill both -expand 1
    foreach {key label type values} {
        print_page {Paper size} choice {A4 A3 LETTER}
        print_orientation Orientation choice {portrait landscape}
        print_rows {Artwork rows per page} integer {}
        print_cols {Artwork columns per page} integer {}
        print_margin_mm {Margin (mm)} number {}
        print_gap_mm {Artwork spacing (mm)} number {}
        print_title {Document title} string {}
        print_captions Captions boolean {}
    } {
        set props [dict create label $label datatype $type default $cfg($key)]
        if {$type eq {choice}} {dict set props choices $values}
        if {$key in {print_rows print_cols}} {dict set props min 1;dict set props max 4}
        if {$key in {print_margin_mm print_gap_mm}} {dict set props min 0;dict set props max 60}
        uiFieldComponentCreate $s.$key field $props ::GX::cfg($key) ::GX::printStudioApplySetup
        pack $s.$key -fill x -pady 3
    }
    set ui(printPaper) $s.print_page.entry
    ttk::label $s.note -text {Tables and text paginate with repeated headers. Artwork uses the selected N-up grid. Changes require an updated document Preview.} -wraplength 320 -justify left;pack $s.note -fill x -pady 6
    set p [uiFieldScrollableCreate $main.dock.printer.form 330];pack $main.dock.printer.form -fill both -expand 1
    ttk::label $p.printerLabel -text {CUPS destination};pack $p.printerLabel -anchor w
    ttk::combobox $p.printer -textvariable ::GX::cfg(print_printer) -state readonly;uiFieldSelectorWithinViewer $p.printer .;pack $p.printer -fill x
    set ui(printerCombo) $p.printer;bind $p.printer <<ComboboxSelected>> ::GX::refreshPrinterOptions
    ttk::frame $p.discovery;pack $p.discovery -fill x -pady 4
    ttk::button $p.discovery.refresh -text {Refresh printers} -command {::GX::discoverPrinters 1}
    ttk::button $p.discovery.cancel -text {Cancel query} -command ::GX::cancelPrinterRequests
    pack $p.discovery.refresh $p.discovery.cancel -side left -padx 2
    ttk::label $p.copiesLabel -text Copies;ttk::spinbox $p.copies -from 1 -to 99 -textvariable ::GX::cfg(print_copies) -width 6;pack $p.copiesLabel $p.copies -fill x -pady 2
    ttk::label $p.duplexLabel -text {Two-sided printing};ttk::combobox $p.duplex -textvariable ::GX::cfg(print_duplex) -values auto -state disabled;uiFieldSelectorWithinViewer $p.duplex .;pack $p.duplexLabel $p.duplex -fill x -pady 2;set ui(printerDuplexCombo) $p.duplex
    ttk::frame $p.capabilities;pack $p.capabilities -fill x -pady 4;set ui(printPrinterGroups) $p.capabilities
    ttk::label $p.pagesLabel -text {Output page range (empty = all)};ttk::entry $p.pages -textvariable ::GX::PrintStudio::state(pages);pack $p.pagesLabel $p.pages -fill x -pady 2
    ttk::button $p.print -text {Print current reviewed PDF} -command {::GX::viewerCommandInvoke .top.nb.print print};pack $p.print -fill x -pady 4
    ttk::frame $p.job;pack $p.job -fill x
    foreach {id label operation} {status {Job status} job_status cancel {Cancel submitted job} cancel_job} {ttk::button $p.job.$id -text $label -command [list ::GX::viewerCommandInvoke $f $operation];pack $p.job.$id -side left -padx 2}
    ttk::button $p.export -text {Save current PDF…} -command {::GX::viewerCommandInvoke .top.nb.print export};pack $p.export -fill x -pady 5
    ttk::label $p.output -textvariable ::GX::PrintStudio::state(outputLabel) -wraplength 315 -justify left;pack $p.output -fill x
    ttk::frame $f.vertical.logs -height 150
    ttk::label $f.vertical.logs.title -text {Document and CUPS diagnostics};pack $f.vertical.logs.title -anchor w
    text $f.vertical.logs.text -height 7 -wrap word -font TkFixedFont -state disabled;pack $f.vertical.logs.text -fill both -expand 1
    set ui(printerOptions) $f.vertical.logs.text
    if {$::GX::PrintStudio::state(logVisible)} {$f.vertical add $f.vertical.logs -weight 0}
    bind $f.vertical <Map> {+::GX::printStudioLogMapped %W}
    bind $f <Map> {+after idle {::GX::printStudioCatalogRefresh;::GX::viewerGuiActionsRefresh .top.nb.print}}
    bind $main <ButtonRelease-1> {+after idle ::GX::printStudioRememberSplit}
    bind $f.vertical <ButtonRelease-1> {+after idle ::GX::printStudioRememberSplit}
    bind $main <Configure> {+::GX::printStudioInitialSplit %W %w}
    printPrinterControlsRefresh
    viewerCommandWidgetsAttach $f [dict create add [list $c.actions.add] remove [list $d.actions.remove] up [list $d.actions.up] down [list $d.actions.down] duplicate [list $d.actions.duplicate] print [list $p.print] export [list $p.export] job_status [list $p.job.status] cancel_job [list $p.job.cancel]]
    printStudioQueueRefresh
}
proc ::GX::printStudioInitialSplit {widget width} {
    if {$widget ne {.top.nb.print.vertical.main} || $width<500 || [info exists ::GX::PrintStudio::state(splitInitialized)]} return
    set ::GX::PrintStudio::state(splitInitialized) 1
    $widget sashpos 0 [expr {max(300,$width-[configurationGet printing.dock_width])}]
}
