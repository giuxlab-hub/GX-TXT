# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::acquisitionHeadingLayout {width} {
    foreach child {description steps} {.top.nb.acq.heading.$child configure -wraplength [expr {max(200,$width-12)}]}
}
proc ::GX::acquisitionQueueToolbarLayout {} {
    set bar .top.nb.acq.batch.bar
    if {![winfo exists $bar]} return
    set children [lmap child [winfo children $bar] {if {[string match *.contracts $child]} continue;set child}]
    uiFieldControlsLayout $bar [winfo width $bar] $children
}
proc ::GX::acquisitionQueueLayout {p} {
    if {!$::GX::interactiveImportQueue} return
    foreach child [winfo children $p] {if {[regexp {\.h[0-9]+$} $child]} {destroy $child}}
    for {set col 0} {$col<12} {incr col} {grid columnconfigure $p $col -weight 0 -minsize 0}
    grid columnconfigure $p 0 -weight 1
    if {!$::GX::genericCsvBatchCount} {
        ttk::label $p.empty -text {Add source files, review their Preview and Variables, then import into the current Session.} -wraplength 480 -justify left
        grid $p.empty -row 0 -column 0 -sticky nw -padx 8 -pady 12
    }
    for {set i 1} {$i<=$::GX::genericCsvBatchCount} {incr i} {
        set row $p.row$i
        ttk::labelframe $row -text "Pending source $i" -padding 5
        grid $row -row $i -column 0 -sticky ew -padx 3 -pady 4
        grid columnconfigure $row 1 -weight 1
        foreach {key label r c} {source {Source file} 0 0 dataset {Dataset ID} 1 0 contract Contract 1 2 custom {Custom contract} 2 0} {
            ttk::label $row.$key -text $label
            grid $row.$key -row $r -column $c -sticky w -padx 3 -pady 3
        }
        $p.path$i configure -width 16;$p.id$i configure -width 16
        $p.kind$i configure -width 16;$p.other$i configure -width 16
        grid $p.path$i -in $row -row 0 -column 1 -columnspan 2 -sticky ew
        grid $p.browse$i -in $row -row 0 -column 3 -sticky e
        grid $p.id$i -in $row -row 1 -column 1 -sticky ew
        grid $p.kind$i -in $row -row 1 -column 3 -sticky ew
        grid $p.other$i -in $row -row 2 -column 1 -columnspan 3 -sticky ew
        if {[winfo exists $p.delim$i]} {
            ttk::frame $row.csv
            ttk::label $row.csv.delimiter -text Delimiter
            ttk::label $row.csv.header -text {Header rows}
            pack $row.csv.delimiter -side left -padx 3
            pack $p.delim$i -in $row.csv -side left -padx 3
            pack $row.csv.header -side left -padx 3
            pack $p.head$i -in $row.csv -side left -padx 3
            grid $row.csv -row 3 -column 0 -columnspan 4 -sticky ew
        }
        ttk::frame $row.actions
        foreach widget [list $p.use$i $p.prev$i $p.vars$i $p.rm$i $p.status$i] {
            grid forget $widget
            pack $widget -in $row.actions -side left -padx 3 -pady 3
        }
        $p.use$i configure -text {Include}
        grid $row.actions -row 4 -column 0 -columnspan 4 -sticky ew
        # These existing controls keep their public widget paths. Their
        # geometry containers are younger descendants of the same parent;
        # raise the siblings above those container backgrounds explicitly.
        foreach key {use path browse id kind other delim head status prev vars rm} {
            if {[winfo exists $p.$key$i]} {raise $p.$key$i}
        }
    }
}
proc ::GX::acquisitionBrowserBuild {} {
    set f .top.nb.acq.browser
    ttk::labelframe $f -text {Acquisition importers}
    grid $f -row 0 -column 1 -rowspan 3 -sticky nsew -padx {5 8} -pady 5
    grid columnconfigure $f 0 -weight 1;grid rowconfigure $f 4 -weight 1
    ttk::frame $f.options
    foreach {key label command tip} {
        builder {Importer Builder…} importerBuilderDialog {Create or edit reusable CSV import definitions}
        contracts {Contracts…} contractRegistryDialog {Inspect the shared Dataset contract registry}
        refresh {Refresh} acquisitionBrowserReload {Reload installed provider metadata and custom importer definitions}
    } {
        ttk::button $f.options.$key -text $label -command [list ::GX::$command]
        pack $f.options.$key -side left -padx 2
        native2DViewportTooltip $f.options.$key $tip
    }
    grid $f.options -row 0 -column 0 -columnspan 2 -sticky ew -padx 3 -pady 4
    bind $f.options <Configure> {::GX::uiFieldControlsLayout %W %w}
    ttk::label $f.searchLabel -text {Find importer (name, type or stable ID)}
    set ::GX::ui(acquisitionSearch) {}
    ttk::entry $f.search -textvariable ::GX::ui(acquisitionSearch)
    bind $f.search <KeyRelease> ::GX::acquisitionBrowserRefresh
    grid $f.searchLabel -row 1 -column 0 -sticky w -padx 5
    grid $f.search -row 2 -column 0 -columnspan 2 -sticky ew -padx 5 -pady 3
    ttk::frame $f.navigation
    foreach {key label state} {expand {Expand all} 1 collapse {Collapse all} 0} {
        ttk::button $f.navigation.$key -text $label -command [list ::GX::acquisitionBrowserExpand $state]
        pack $f.navigation.$key -side left -padx 2
    }
    grid $f.navigation -row 3 -column 0 -columnspan 2 -sticky ew -padx 3 -pady 3
    ttk::treeview $f.tree -show tree -selectmode browse
    $f.tree column #0 -width 300 -minwidth 180
    ttk::scrollbar $f.sy -command [list $f.tree yview]
    $f.tree configure -yscrollcommand [list $f.sy set]
    grid $f.tree -row 4 -column 0 -sticky nsew;grid $f.sy -row 4 -column 1 -sticky ns
    ttk::label $f.count -textvariable ::GX::ui(acquisitionCount)
    grid $f.count -row 5 -column 0 -columnspan 2 -sticky w -padx 5 -pady 4
    bind $f.tree <<TreeviewSelect>> ::GX::acquisitionBrowserSelected
    acquisitionBrowserRefresh
}
proc ::GX::acquisitionBrowserReload {} {
    loadModuleCatalog
    importerBuilderRefreshSelector
    refreshModuleCatalog
}
proc ::GX::acquisitionBrowserExpand {open} {
    foreach group [.top.nb.acq.browser.tree children {}] {.top.nb.acq.browser.tree item $group -open $open}
}
proc ::GX::acquisitionBrowserRefresh {} {
    variable ui
    set tree .top.nb.acq.browser.tree
    if {![winfo exists $tree]} return
    set query [string tolower [string trim $ui(acquisitionSearch)]]
    set expanded {};foreach node [$tree children {}] {dict set expanded $node [$tree item $node -open]}
    $tree delete [$tree children {}]
    set records {}
    foreach id $::GX::moduleOrder {
        if {[moduleField $id kind] ne "acquisition"} continue
        lappend records [list [moduleField $id group General] $id [moduleField $id name $id] [moduleField $id description]]
    }
    foreach id [lsort -dictionary [dict keys $::GX::importerBuilderDefinitions]] {
        set definition [importerBuilderGet $id]
        lappend records [list {Custom importers} builder.$id [dict get $definition name] [dict get $definition description]]
    }
    set total [llength $records];set visible 0
    foreach record [lsort -dictionary -index 0 $records] {
        lassign $record group id name description
        if {$query ne {} && [string first $query [string tolower "$id $name $group $description"]]<0} continue
        set parent group:[binary encode hex [encoding convertto utf-8 $group]]
        if {![$tree exists $parent]} {$tree insert {} end -id $parent -text $group -open [datasetPublicationV2DictDefault $expanded $parent 1]}
        $tree insert $parent end -id $id -text $name
        incr visible
    }
    set ui(acquisitionCount) "$visible of $total importers · ALWAYS available"
    if {[info exists ::GX::importerChoice] && [$tree exists $::GX::importerChoice]} {
        $tree selection set $::GX::importerChoice
        $tree see $::GX::importerChoice
    }
}
proc ::GX::acquisitionBrowserSelected {} {
    set choice [lindex [.top.nb.acq.browser.tree selection] 0]
    if {$choice eq {} || [string match group:* $choice] || $choice eq $::GX::importerChoice} return
    set ::GX::importerChoice $choice
    importerSelectionChanged
}
proc ::GX::acquisitionBrowserDescribe {} {
    variable ui
    set builder [importerBuilderSelectedId]
    if {$builder ne {}} {
        set d [importerBuilderGet $builder]
        set ui(acquisitionName) [dict get $d name]
        set ui(acquisitionDescription) "[dict get $d description] · Custom CSV definition"
    } else {
        set id $::GX::cfg(acquisition_module)
        set ui(acquisitionName) [moduleField $id name $id]
        set ui(acquisitionDescription) "[moduleField $id description]\n$id · ALWAYS · [moduleField $id group]"
    }
}
proc ::GX::buildAcquisitionPage {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable ui
    variable version
    # Acquisition tab
    set f .top.nb.acq
    grid columnconfigure $f 1 -weight 1
    ttk::label $f.l0 -text "Acquisition CSV"
    ttk::entry $f.e0 -textvariable ::GX::cfg(input_csv)
    ttk::button $f.b0 -text "Sfoglia..." -command ::GX::chooseInput
    ttk::button $f.p0 -text "Preview" -command {::GX::refreshCsvPreview; .top.nb select .top.nb.preview}
    grid $f.l0 -row 0 -column 0 -sticky e -padx 5 -pady 4
    grid $f.e0 -row 0 -column 1 -sticky ew -padx 5 -pady 4
    grid $f.b0 -row 0 -column 2 -padx 5 -pady 4
    grid $f.p0 -row 0 -column 3 -padx 5 -pady 4

    ttk::label $f.l1 -text "Session root"
    ttk::entry $f.e1 -textvariable ::GX::cfg(output_root)
    ttk::button $f.b1 -text "Sfoglia..." -command ::GX::chooseOutput
    grid $f.l1 -row 1 -column 0 -sticky e -padx 5 -pady 4
    grid $f.e1 -row 1 -column 1 -sticky ew -padx 5 -pady 4
    grid $f.b1 -row 1 -column 2 -padx 5 -pady 4
    ttk::button $f.openSession -text "Open existing session..." -command ::GX::chooseSession
    grid $f.openSession -row 1 -column 3 -padx 5 -pady 4

    addLabeledEntry $f 2 "New session name (optional)" ::GX::cfg(session_name)
    ttk::label $f.sessionHelp -text "PHASE 1 creates a NEW session folder under Session root. To resume existing data and analyses, use Open existing session... or the Session bar at the top." -wraplength 1050 -justify left -foreground #444444
    grid $f.sessionHelp -row 3 -column 0 -columnspan 4 -sticky ew -padx 5 -pady {2 7}

    ttk::label $f.l3 -text "Parser"
    ttk::combobox $f.e3 -textvariable ::GX::cfg(parser) -state readonly \
        -values {rigol_ds1000z generic_sequence generic_time}
    grid $f.l3 -row 4 -column 0 -sticky e -padx 5 -pady 4
    grid $f.e3 -row 4 -column 1 -sticky w -padx 5 -pady 4

    ttk::label $f.l4 -text "Delimitatore"
    ttk::combobox $f.e4 -textvariable ::GX::cfg(delimiter) -values {"," ";" tab} -width 12
    grid $f.l4 -row 5 -column 0 -sticky e -padx 5 -pady 4
    grid $f.e4 -row 5 -column 1 -sticky w -padx 5 -pady 4

    addLabeledEntry $f 6 "Header rows" ::GX::cfg(header_lines) 12
    addLabeledEntry $f 7 "Sequence column" ::GX::cfg(sequence_col) 12
    addLabeledEntry $f 8 "Time column" ::GX::cfg(time_col) 12
    addLabeledEntry $f 9 {tStart manuale [s]} ::GX::cfg(manual_tstart) 18
    addLabeledEntry $f 10 {dt manuale [s]} ::GX::cfg(manual_dt) 18

    ttk::checkbutton $f.c10 -text "Generate 2-column Rigol split (sequence + signal)" -variable ::GX::cfg(make_rigol_split)
    ttk::checkbutton $f.c11 -text "Also generate canonical CSV (time_s + voltage_V)" -variable ::GX::cfg(make_canonical_split)
    ttk::checkbutton $f.c12 -text "Create symbolic link to RAW file in session" -variable ::GX::cfg(link_raw)
    ttk::checkbutton $f.c13 -text "Copy RAW file into session (large files!)" -variable ::GX::cfg(copy_raw)
    grid $f.c10 -row 11 -column 1 -columnspan 2 -sticky w -padx 5 -pady 3
    grid $f.c11 -row 12 -column 1 -columnspan 2 -sticky w -padx 5 -pady 3
    grid $f.c12 -row 13 -column 1 -columnspan 2 -sticky w -padx 5 -pady 3
    grid $f.c13 -row 14 -column 1 -columnspan 2 -sticky w -padx 5 -pady 3

    ttk::separator $f.sep -orient horizontal
    grid $f.sep -row 15 -column 0 -columnspan 3 -sticky ew -pady 8
    addLabeledEntry $f 16 "Octave command" ::GX::cfg(octave_cmd)
    ttk::label $f.workerl -text "Worker .m"
    ttk::entry $f.workere -textvariable ::GX::cfg(worker_file)
    ttk::button $f.workerb -text "Sfoglia..." -command ::GX::chooseWorker
    grid $f.workerl -row 17 -column 0 -sticky e -padx 5 -pady 4
    grid $f.workere -row 17 -column 1 -sticky ew -padx 5 -pady 4
    grid $f.workerb -row 17 -column 2 -padx 5 -pady 4
    addLabeledEntry $f 18 "Per-channel hook (optional)" ::GX::cfg(post_per_channel)
    ttk::label $f.help -text "Token hook: {FILE} {NAME} {SCOPE} {SESSION} {MANIFEST}" -foreground #555555
    grid $f.help -row 19 -column 1 -columnspan 2 -sticky w -padx 5
    ttk::separator $f.sep2 -orient horizontal
    grid $f.sep2 -row 20 -column 0 -columnspan 4 -sticky ew -pady 8
    addLabeledEntry $f 21 "Available CPU / threads" ::GX::cfg(cpu_count) 12
    addLabeledEntry $f 22 "CSV rows per block" ::GX::cfg(chunk_rows) 14
    addLabeledEntry $f 23 "Preview data rows" ::GX::cfg(preview_lines) 12
    addLabeledEntry $f 24 "Raw fields per record (0=auto)" ::GX::cfg(raw_fields) 12
    addLabeledEntry $f 25 "Trailing fields to ignore" ::GX::cfg(drop_trailing_fields) 12
    ttk::checkbutton $f.c25 -text "Strict Sequence check (step +1)" -variable ::GX::cfg(strict_sequence)
    grid $f.c25 -row 26 -column 1 -columnspan 2 -sticky w -padx 5 -pady 3

}
