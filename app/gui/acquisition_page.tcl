# SPDX-License-Identifier: GPL-3.0-or-later
# One native primary menu in the established Session identity row. General
# commands keep their existing owners; this component stores only view flags.
proc ::GX::acquisitionPrimaryMenuCreate {bar} {
    set button $bar.acquisition
    if {[winfo exists $button]} return
    # Tk8.6's native MenuFind/Alt/F10 traversal owns classic Menubuttons;
    # use that maintained owner rather than a separate shortcut registry.
    menubutton $button -text Acquisition -underline 0 -menu $button.menu -font TkMenuFont -relief flat -padx 6 -pady 4
    menu $button.menu -tearoff 0 -postcommand ::GX::acquisitionPrimaryMenuPost
    $button.menu add checkbutton -label {Importer options} -variable ::GX::ui(acquisitionOptionsShown) -command ::GX::acquisitionOptionsToggle
    $button.menu add separator
    foreach {label operation} {{Importer Builder…} builder {Contracts…} contracts {Refresh importers} refresh} {
        $button.menu add command -label $label -command [list ::GX::acquisitionPrimaryAction $operation]
    }
    $button.menu add separator
    foreach {label operation} {{Current importer Help} help {About current importer} about} {
        $button.menu add command -label $label -command [list ::GX::acquisitionPrimaryAction $operation]
    }
    pack $button -side left -padx 3 -before $bar.loadedSession
    acquisitionOptionsVisibility
}
proc ::GX::acquisitionPrimaryBusy {} {
    return [expr {([info exists ::GX::acquisitionHandlerAsyncActive] && $::GX::acquisitionHandlerAsyncActive) ||
        ($::GX::currentSession ne {} && [acquisitionHandlerAuthorityBusy $::GX::currentSession])}]
}
proc ::GX::acquisitionPrimaryMenuPost {} {
    set menu .top.sessionbar.acquisition.menu
    if {![winfo exists $menu]} return
    set busy [acquisitionPrimaryBusy]
    foreach label {{Importer Builder…} {Contracts…} {Refresh importers} {Importer options}} {$menu entryconfigure $label -state [expr {$busy?{disabled}:{normal}}]}
    set info [acquisitionImporterInfo $::GX::importerChoice]
    $menu entryconfigure {About current importer} -state [expr {$info eq {}?{disabled}:{normal}}]
    $menu entryconfigure {Current importer Help} -state [expr {$info ne {} && [acquisitionBrowserHelpReference $info] ne {}?{normal}:{disabled}}]
    acquisitionOptionsVisibility
}
proc ::GX::acquisitionPrimaryAction {operation} {
    if {$operation in {builder contracts refresh} && [acquisitionPrimaryBusy]} {return 0}
    switch -- $operation {
        builder {importerBuilderDialog}
        contracts {contractRegistryDialog}
        refresh {acquisitionBrowserReload}
        help - about {
            set info [acquisitionImporterInfo $::GX::importerChoice]
            if {$info eq {}} {return 0}
            acquisitionImporterInfoAction $info $operation .
        }
        default {error {Unknown Acquisition primary command}}
    }
}
proc ::GX::acquisitionOptionsCollapsible {} {
    set module $::GX::cfg(acquisition_module)
    # Ordinary file recipes/native file profiles may collapse. Existing Tcl
    # instrument controls retain their visible default without vendor tests.
    return [expr {[importerBuilderSelectedId] ne {} || $module eq {acq.generic_csv} ||
        ([acquisitionHandlerSectionField $module runtime {}] eq {managed_cpp} && [acquisitionHandlerModuleSupportsBatch $module])}]
}
proc ::GX::acquisitionOptionsVisibility {} {
    variable ui
    if {![info exists ui(acquisitionOptionsPreferred)]} {set ui(acquisitionOptionsPreferred) 0}
    set ui(acquisitionOptionsShown) [expr {![acquisitionOptionsCollapsible] || $ui(acquisitionOptionsPreferred)}]
    set frame .top.nb.acq.cfg
    if {![winfo exists $frame]} return
    if {$ui(acquisitionOptionsShown)} {grid $frame} else {grid remove $frame}
    set description .top.nb.acq.heading.description;set steps .top.nb.acq.heading.steps
    if {[winfo exists $description]} {
        if {$ui(acquisitionOptionsShown)} {pack $description -before $steps -anchor w -fill x -pady 3} else {pack forget $description}
    }
}
proc ::GX::acquisitionOptionsToggle {} {
    variable ui
    if {[acquisitionPrimaryBusy]} {acquisitionOptionsVisibility;return}
    if {[acquisitionOptionsCollapsible]} {set ui(acquisitionOptionsPreferred) $ui(acquisitionOptionsShown)}
    .top.nb select .top.nb.acq
    acquisitionOptionsVisibility
    if {!$ui(acquisitionOptionsShown) && [winfo exists .top.nb.acq.batch.bar.add]} {after idle [list ::GX::_uiFieldMappedFocus .top.nb.acq .top.nb.acq.batch.bar.add 0 .top.nb.acq]}
}
proc ::GX::acquisitionHeadingLayout {width} {
    set wrap [expr {max(200,$width-12)}]
    foreach child {steps} {
        set label .top.nb.acq.heading.$child
        if {![winfo exists $label]} continue
        # These labels fill their allocated row. Their wrapped text must not
        # feed that allocation back as a new natural horizontal request: the
        # hidden page otherwise repeatedly resizes the enclosing Notebook.
        if {[$label cget -width] ne {1}} {$label configure -width 1}
        if {[$label cget -wraplength]!=$wrap} {$label configure -wraplength $wrap}
    }
}
# Bound only the existing Acquisition options projection, leaving Pending
# imports real space. Values remain in moduleCfg and the shared scrolling owner
# supplies wheel/focus navigation; no configuration is copied into a new store.
proc ::GX::acquisitionOptionsViewportLayout {width height} {
    set frame .top.nb.acq.cfg
    if {![winfo exists $frame] || $height<2} return
    set desired [expr {max(104,min(200,int($height*0.23)))}]
    if {[$frame cget -height]!=$desired} {$frame configure -height $desired}
}
proc ::GX::acquisitionOptionsFieldsLayout {box width} {
    if {![winfo exists $box] || $width<2} return
    # Long descriptor labels must wrap within the available field column rather
    # than starving their adjacent entry. This applies to all Acquisition modules.
    set wrap [expr {max(100,int(($width-24)*0.43))}]
    grid columnconfigure $box 0 -weight 2 -uniform acquisition_option_columns
    grid columnconfigure $box 1 -weight 3 -uniform acquisition_option_columns
    foreach child [winfo children $box] {
        if {[winfo class $child] eq {TLabel}} {
            $child configure -width 1 -wraplength [expr {$width<680 ? max(100,$width-24) : $wrap}] -justify left -anchor w
            grid configure $child -sticky ew
        } elseif {[winfo class $child] in {TEntry TCombobox TSpinbox}} {
            $child configure -width 12
        }
        # Reflow existing descriptor label/value pairs at narrow widths. Genuine
        # controls and names remain intact, including their native Tab order.
        if {[regexp {\.([lw])([0-9]+)$} $child -> part row]} {
            if {$width<680} {
                grid configure $child -row [expr {2*$row+($part eq {w})}] -column 0 -columnspan 2 -sticky ew
            } else {
                grid configure $child -row $row -column [expr {$part eq {w}}] -columnspan 1 -sticky ew
            }
        }
    }
}
proc ::GX::acquisitionBrowserToolsLayout {frame width} {
    if {![winfo exists $frame] || $width<2} return
    # The enclosing importer column supplies the width. Keep wrapping's natural
    # width out of that column's request while retaining its actual row height.
    # The existing UI Field owner still chooses and places every control.
    grid propagate $frame 0
    set layout [uiFieldControlsLayout $frame $width]
    set height [dict get $layout height]
    if {[$frame cget -height]!=$height} {$frame configure -height $height}
}
proc ::GX::acquisitionQueueToolbarLayout {} {
    set bar .top.nb.acq.batch.bar
    if {![winfo exists $bar]} return
    set hint .top.nb.acq.batch.note
    set compact {Review sources before import.}
    if {[winfo exists $hint] && [$hint cget -text] ne $compact} {
        native2DViewportTooltip $hint [$hint cget -text]
        $hint configure -text $compact
    }
    foreach {name caption detail} {
        multi {Add files…} {Add multiple source files to the pending queue}
        importCurrent Import {Import enabled pending sources into the current Session}
        storageLabel RAW: {Original source storage policy; source bytes are never rewritten}
        copy Copy {Copy original RAW into the Session}
        reference Reference {Keep and reference the original RAW source}
        folder {Folder…} {Add matching files from a folder when supported by this importer}
    } {
        if {[winfo exists $bar.$name] && [$bar.$name cget -text] ne $caption} {
            $bar.$name configure -text $caption
            native2DViewportTooltip $bar.$name $detail
        }
    }
    # The same catalog action is already in the importer browser. Constructor
    # paths may still have this old duplicate packed when Describe first runs.
    if {[winfo exists $bar.contracts]} {pack forget $bar.contracts;grid remove $bar.contracts}
    set children [lmap child [winfo children $bar] {if {[string match *.contracts $child]} continue;set child}]
    foreach child $children {if {[winfo class $child] eq {TButton}} {$child configure -width -1}}
    uiFieldControlsLayout $bar [winfo width $bar] $children
}
proc ::GX::acquisitionQueueFieldSee {content widget} {
    set viewport .top.nb.acq.batch.c
    if {![winfo exists $viewport] || ![winfo exists $widget] || ![string match $content.* $widget]} return
    uiFieldScrollSee $viewport $content $widget
    set x [expr {[winfo rootx $widget]-[winfo rootx $content]}]
    set left [$viewport canvasx 0];set right [$viewport canvasx [winfo width $viewport]]
    if {$x<$left || $x+[winfo width $widget]>$right} {$viewport xview moveto [expr {max(0,($x-4)/double(max(1,[winfo reqwidth $content])))}]}
}
proc ::GX::acquisitionQueueLayout {p} {
    if {!$::GX::interactiveImportQueue} return
    set viewport .top.nb.acq.batch.c
    set disposal [list ::GX::_uiFieldScrollAreaDispose $viewport $p [winfo toplevel $viewport] %W]
    if {$disposal ni [split [bind $viewport <Destroy>] \n]} {uiFieldScrollAreaAttach $viewport $p}
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
        foreach {key label r c} {source {Source file} 0 0 dataset {Dataset ID} 1 0 contract {Proposed contract} 1 2 custom {Custom contract} 2 0} {
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
        # Use each action's actual label instead of the theme's common button
        # width; three generous fixed widths needlessly hide Remove at font18.
        foreach action {prev vars rm} {$p.$action$i configure -width 0}
        foreach widget [list $p.use$i $p.prev$i $p.vars$i $p.rm$i $p.status$i] {
            grid forget $widget
            pack $widget -in $row.actions -side left -padx 3 -pady 3
        }
        $p.use$i configure -text {Include}
        grid $row.actions -row 4 -column 0 -columnspan 4 -sticky ew
        native2DViewportTooltip $p.kind$i {Proposed output contract. The source and importer determine actual published contracts; this choice does not convert units or shape. Inspect the source before choosing among a profile's multiple outputs.}
        # These existing controls keep their public widget paths. Their
        # geometry containers are younger descendants of the same parent;
        # raise the siblings above those container backgrounds explicitly.
        foreach key {use path browse id kind other delim head status prev vars rm} {
            if {[winfo exists $p.$key$i]} {
                raise $p.$key$i
                bind $p.$key$i <FocusIn> [list ::GX::acquisitionQueueFieldSee $p %W]
            }
        }
    }
}
proc ::GX::acquisitionBrowserStyle {} {
    _uiFieldTreeFontRows .top.nb.acq.browser.tree GXAcquisition.Treeview
}
proc ::GX::acquisitionBrowserBuild {} {
    set f .top.nb.acq.browser
    ttk::labelframe $f -text {Acquisition importers}
    grid $f -row 0 -column 1 -rowspan 3 -sticky nsew -padx {5 8} -pady 5
    grid columnconfigure $f 0 -weight 1;grid rowconfigure $f 4 -weight 1
    # Builder, Contracts and Refresh live in the primary Acquisition menu.
    ttk::label $f.searchLabel -text {Find importer (name, type or stable ID)} -width 1 -wraplength 300
    set ::GX::ui(acquisitionSearch) {}
    ttk::entry $f.search -textvariable ::GX::ui(acquisitionSearch)
    bind $f.search <KeyRelease> ::GX::acquisitionBrowserRefresh
    grid $f.searchLabel -row 1 -column 0 -columnspan 2 -sticky ew -padx 5
    grid $f.search -row 2 -column 0 -columnspan 2 -sticky ew -padx 5 -pady 3
    ttk::frame $f.navigation -width 1
    foreach {key label state} {expand Expand 1 collapse Collapse 0} {
        ttk::button $f.navigation.$key -text $label -width -1 -command [list ::GX::acquisitionBrowserExpand $state]
        pack $f.navigation.$key -side left -padx 2
    }
    grid $f.navigation -row 3 -column 0 -columnspan 2 -sticky ew -padx 3 -pady 3
    bind $f.navigation <Configure> {::GX::acquisitionBrowserToolsLayout %W %w}
    ttk::treeview $f.tree -show tree -selectmode browse
    acquisitionBrowserStyle
    bind $f.tree <<ThemeChanged>> +::GX::acquisitionBrowserStyle
    $f.tree column #0 -width 300 -minwidth 180
    ttk::scrollbar $f.sy -command [list $f.tree yview]
    $f.tree configure -yscrollcommand [list $f.sy set]
    grid $f.tree -row 4 -column 0 -sticky nsew;grid $f.sy -row 4 -column 1 -sticky ns
    ttk::label $f.count -textvariable ::GX::ui(acquisitionCount) -width 1 -wraplength 300
    grid $f.count -row 5 -column 0 -columnspan 2 -sticky ew -padx 5 -pady 4
    bind $f.tree <<TreeviewSelect>> ::GX::acquisitionBrowserSelected
    bind $f.tree <Button-3> {::GX::acquisitionBrowserContext %W %x %y;break}
    bind $f.tree <Menu> {::GX::acquisitionBrowserContextKeyboard %W;break}
    bind $f.tree <Shift-F10> {::GX::acquisitionBrowserContextKeyboard %W;break}
    acquisitionBrowserRefresh
}
proc ::GX::acquisitionBrowserRowInfo {tree row} {
    if {$row eq {} || ![winfo exists $tree] || ![$tree exists $row] || [string match group:* $row]} {return {}}
    return [acquisitionImporterInfo $row]
}
proc ::GX::acquisitionImporterInfo {row} {
    if {[string match builder.* $row]} {
        if {[catch {set definition [importerBuilderGet [string range $row 8 end]]}]} {return {}}
        return [dict create id $row name [dict get $definition name] description [dict get $definition description] \
            version [datasetPublicationV2DictDefault $definition version {}] module {}]
    }
    if {[moduleField $row kind {}] ne {acquisition}} {return {}}
    return [dict create id $row name [moduleField $row name $row] description [moduleField $row description {}] \
        version [moduleField $row version {}] module $row]
}
proc ::GX::acquisitionBrowserHelpReference {info} {
    set module [dict get $info module]
    if {$module eq {}} {return {}}
    documentationBrowserRefresh
    # Prefer the declared user guide (including an illustrated HTML tutorial),
    # while retaining the same existing manual/reference host for all formats.
    foreach kind {guide html_manual manual quick_start} {
        if {![catch {set entry [documentationBrowserResolve module:$module:$kind]}]} {return $entry}
    }
    return {}
}
proc ::GX::acquisitionBrowserContextKeyboard {tree} {
    set row [$tree focus]
    if {[acquisitionBrowserRowInfo $tree $row] eq {}} {return}
    $tree see $row
    set box [$tree bbox $row]
    if {![llength $box]} {return}
    lassign $box x y width height
    acquisitionBrowserContext $tree [expr {$x+min(24,$width/2)}] [expr {$y+$height/2}] 1
}
proc ::GX::acquisitionBrowserContext {tree x y {keyboard 0}} {
    set menu [winfo parent $tree].context
    if {[winfo exists $menu]} {$menu unpost}
    set row [$tree identify row $x $y]
    set info [acquisitionBrowserRowInfo $tree $row]
    if {$info eq {}} {return}
    if {![winfo exists $menu]} {menu $menu -tearoff 0}
    $menu delete 0 end
    foreach {label operation} {{Select for acquisition} select Help help About about} {
        $menu add command -label $label -command [list ::GX::acquisitionBrowserContextAction $tree $row $operation]
    }
    if {[acquisitionBrowserHelpReference $info] eq {}} {$menu entryconfigure Help -state disabled}
    # Posting consults the row under the pointer without selecting it. Only the
    # explicit Select command enters the established Treeview selection owner.
    set point [list [expr {[winfo rootx $tree]+$x}] [expr {[winfo rooty $tree]+$y}]]
    if {$keyboard} {tk_popup $menu {*}$point 0} else {tk_popup $menu {*}$point}
}
proc ::GX::acquisitionBrowserContextAction {tree row operation} {
    set info [acquisitionBrowserRowInfo $tree $row]
    if {$info eq {}} {return 0}
    switch -- $operation {
        select {
            $tree selection set $row
            $tree focus $row
            acquisitionBrowserSelected
        }
        help - about {return [acquisitionImporterInfoAction $info $operation [winfo toplevel $tree]]}
        default {error {Unknown acquisition context action}}
    }
    return 1
}
proc ::GX::acquisitionImporterInfoAction {info operation parent} {
    if {$operation eq {help}} {
        set entry [acquisitionBrowserHelpReference $info]
        if {$entry eq {}} {return 0}
        documentationBrowserOpenReferenceWindow [dict get $entry path] [dict get $info module] $parent
    } elseif {$operation eq {about}} {
        set version [dict get $info version];if {$version eq {}} {set version {Not declared}}
        tk_messageBox -parent $parent -title {About acquisition importer} -type ok -icon info \
            -message "[dict get $info name]\nID: [dict get $info id]\nVersion: $version\n\n[dict get $info description]"
    } else {error {Unknown Acquisition information command}}
    return 1
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
    # Compact descriptive projection only; About/Help retain the full identity
    # and the existing tooltip receives the exact current descriptor text.
    set ui(acquisitionDescriptionCompact) [lindex [split $ui(acquisitionDescription) \n] 0]
    if {[winfo exists .top.nb.acq.heading.description]} {
        native2DViewportTooltip .top.nb.acq.heading.description $ui(acquisitionDescription)
        native2DViewportTooltip .top.nb.acq.heading.name $ui(acquisitionDescription)
    }
    # Construction still packs its final folder button after first Describe;
    # only reflow here once that existing constructor has completed.
    if {[winfo exists .top.nb.acq.batch.bar.folder]} {acquisitionQueueToolbarLayout}
    acquisitionOptionsVisibility
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
