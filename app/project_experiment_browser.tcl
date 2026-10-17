# SPDX-License-Identifier: GPL-3.0-or-later
# Presentation only: stable IDs, inspection and transport stay CORE-owned.
namespace eval ::GX {variable projectGuiExperiment {};variable projectGuiInfo {};variable projectGuiRows;variable projectGuiDocuments;variable projectGuiOrder {}}
proc ::GX::projectBrowserExperimentName {eid} {
    set name [projectMembershipField $eid experiment_name {}]
    if {[string trim $name] eq {}} {set name [file tail [projectMembershipField $eid session_path {}]]}
    if {$name eq {}} {set name {Unnamed Session}}
    return $name
}
proc ::GX::projectExperimentNameCompare {a b} {
    set order [string compare -nocase [projectBrowserExperimentName [dict get $a experiment_id]] [projectBrowserExperimentName [dict get $b experiment_id]]]
    if {$order==0} {return [string compare [dict get $a experiment_id] [dict get $b experiment_id]]};return $order
}
proc ::GX::projectBrowserResize {width} {
    set canvas .top.nb.projects.body.right.experiments
    if {![winfo exists $canvas]} return
    $canvas itemconfigure body -width $width
    if {$::GX::projectGuiInfo ne {}} {$canvas itemconfigure body -height [winfo height $canvas]} else {$canvas itemconfigure body -height 0}
    foreach row [winfo children $canvas.content] {if {[winfo exists $row.name]} {$row.name configure -wraplength [expr {max(160,$width-62)}]}}
    $canvas configure -scrollregion [$canvas bbox all]
}
proc ::GX::projectBrowserScroll {} {set c .top.nb.projects.body.right.experiments;if {[winfo exists $c]} {$c configure -scrollregion [$c bbox all]}}
proc ::GX::projectBrowserWheel {delta} {
    if {$::GX::projectGuiInfo eq {}} {.top.nb.projects.body.right.experiments yview scroll [expr {$delta>0 ? -1 : 1}] units}
}
proc ::GX::projectBrowserBindWheel {widget} {
    if {$::GX::projectGuiInfo ne {}} return
    bind $widget <Button-4> {::GX::projectBrowserWheel 1};bind $widget <Button-5> {::GX::projectBrowserWheel -1};bind $widget <MouseWheel> {::GX::projectBrowserWheel %D}
    foreach child [winfo children $widget] {projectBrowserBindWheel $child}
}
proc ::GX::projectGuiChooseExperiment {eid} {
    if {$eid ni $::GX::projectGuiOrder} {set eid {}}
    set ::GX::projectGuiExperiment $eid
    set bg [ttk::style lookup Treeview -background selected #4a6984];set fg [ttk::style lookup Treeview -foreground selected white]
    ttk::style configure GXSelected.TFrame -background $bg
    ttk::style configure GXSelected.TLabel -background $bg -foreground $fg
    foreach id [array names ::GX::projectGuiRows] {
        set row $::GX::projectGuiRows($id);set selected [expr {$id eq $eid}]
        if {[winfo exists $row]} {
            $row configure -style [expr {$selected ? {GXSelected.TFrame} : {TFrame}}]
            foreach child {name state} {$row.$child configure -style [expr {$selected ? {GXSelected.TLabel} : {TLabel}}]}
            set path [projectMembershipField $id session_path]
            $row.state configure -text "[expr {$selected ? {● Selected  } : {○ Select  }}][expr {$path eq $::GX::currentSession ? {• Open Session} : {}}][expr {![file isdirectory $path] ? { • Session unavailable} : {}}]"
            $row.actions configure -style [expr {$selected ? {GXSelected.TFrame} : {TFrame}}]
        }
    }
    set f .top.nb.projects.body.right
    $f.actions.export configure -state [expr {$eid eq {} ? {disabled} : {normal}}]
    $f.status configure -text [expr {$eid eq {} ? {No Experiment selected. Click a name/row, or use Tab then ↑ / ↓. Export uses one selected Session.} : "Selected for Export: [projectBrowserExperimentName $eid]"}]
}
proc ::GX::projectGuiNavigate {eid step} {
    set i [lsearch -exact $::GX::projectGuiOrder $eid];set i [expr {max(0,min([llength $::GX::projectGuiOrder]-1,$i+$step))}]
    set next [lindex $::GX::projectGuiOrder $i];if {$next eq {}} return
    projectGuiChooseExperiment $next;set row $::GX::projectGuiRows($next);focus $row
    set c .top.nb.projects.body.right.experiments;set box [$c bbox all]
    if {$box ne {}} {$c yview moveto [expr {double([winfo y $row])/max(1,[lindex $box 3])}]}
}
rename ::GX::projectGuiShowSelected ::GX::projectGuiShowSelected_before_browser083
proc ::GX::projectGuiShowSelected_browser083 {} {
    set f .top.nb.projects.body.right
    if {![winfo exists $f.experiments.content]} return
    set id [projectGuiSelectedId]
    destroyChildren $f.experiments.content;array unset ::GX::projectGuiRows *
    set ::GX::projectGuiInfo {};set ::GX::projectGuiOrder {}
    grid $f.scroll
    foreach action {edit delete} {.top.nb.projects.toolbar.$action configure -state [expr {$id eq {} || $id eq [projectDefaultId] ? {disabled} : {normal}}]}
    foreach action {select newSession} {.top.nb.projects.toolbar.$action configure -state [expr {$id eq {} ? {disabled} : {normal}}]}
    .top.nb.projects.toolbar.exportProject configure -state [expr {$id eq {} ? {disabled} : {normal}}]
    foreach {group buttons} {projectMenu {new edit delete} sessionsMenu {select newSession} transferMenu {importProject exportProject}} {
        set index 0
        foreach button $buttons {
            .top.nb.projects.toolbar.$group.menu entryconfigure $index -state [.top.nb.projects.toolbar.$button cget -state]
            incr index
        }
    }
    foreach field {name id description notes tags author storage_path created_at updated_at} {
        set value [expr {$id eq {} ? {} : [projectField $id $field]}]
        $f.value_$field configure -text $value
        if {$field eq {notes}} {
            if {$value eq {}} {grid remove $f.label_notes $f.value_notes} else {grid $f.label_notes;grid $f.value_notes}
        }
    }
    $f.actions.import configure -state [expr {$id eq {} ? {disabled} : {normal}}]
    if {$id eq {}} {
        $f.title configure -text {Choose a Project from the left browser}
        $f.subtitle configure -text {Create a Project, or select Default / Unassigned for standalone Sessions.}
    } else {
        $f.title configure -text "Project: [projectField $id name]"
        $f.subtitle configure -text "[llength [projectListExperiments $id]] Experiments • Import adds an external Session here; no Experiment selection required."
        foreach exp [lsort -command ::GX::projectExperimentNameCompare [projectListExperiments $id]] {
            set eid [dict get $exp experiment_id];lappend ::GX::projectGuiOrder $eid
            set row $f.experiments.content.r$eid;set ::GX::projectGuiRows($eid) $row
            ttk::frame $row -padding 7 -takefocus 1
            ttk::label $row.name -text [projectBrowserExperimentName $eid] -font TkHeadingFont -wraplength 650 -justify left
            ttk::label $row.state -text {○ Select}
            pack $row.name $row.state -fill x -anchor w
            ttk::frame $row.actions
            foreach {action label tip} {
                open {↗ Open} {Open this Session through its normal controller}
                rename {✎ Rename} {Change display name; preserve directory, creator and stable ID}
                info {ⓘ Info} {Read scientific facts and Markdown without changing the open Session}
                move {Move to Project…} {Choose another Project without opening or relocating this Session}
                detach {↪ Move to Default} {Change Project membership; keep scientific bytes and directory}
                delete {✕ Delete} {Delete the complete Session after confirmation; retain a recovery copy}
            } {
                if {$action eq {detach} && $id eq [projectDefaultId]} continue
                ttk::button $row.actions.$action -text $label -command [list ::GX::projectGuiRowAction $eid $action]
                pack $row.actions.$action -side left -padx 2 -pady 3
                bind $row.actions.$action <Enter> [list ::GX::plotsToolbarTipSchedule $row.actions.$action $tip]
                bind $row.actions.$action <Leave> ::GX::plotsToolbarTipHide
                bind $row.actions.$action <ButtonPress> ::GX::plotsToolbarTipHide
            }
            pack $row.actions -anchor w
            if {![file isdirectory [dict get $exp session_path]]} {$row.state configure -text {Unavailable Session • Info shows diagnostics}}
            pack $row -fill x -padx 2 -pady 2
            foreach w [list $row $row.name $row.state] {
                bind $w <Button-1> "[list focus $row];[list ::GX::projectGuiChooseExperiment $eid];break"
                bind $w <Double-1> [list ::GX::projectGuiRowAction $eid open]
            }
            bind $row <FocusIn> [list ::GX::projectGuiChooseExperiment $eid]
            bind $row <Up> "[list ::GX::projectGuiNavigate $eid -1];break";bind $row <Down> "[list ::GX::projectGuiNavigate $eid 1];break"
            bind $row <Return> [list ::GX::projectGuiRowAction $eid open];bind $row <space> [list ::GX::projectGuiChooseExperiment $eid]
        }
        if {[llength $::GX::projectGuiOrder]==0} {
            ttk::label $f.experiments.content.empty -text "No Experiments in this Project yet.\nUse New Session here… or Import Experiment… to add one." -justify left
            pack $f.experiments.content.empty -anchor nw -padx 12 -pady 15
        }
    }
    projectGuiChooseExperiment $::GX::projectGuiExperiment
    projectBrowserBindWheel $f.experiments.content;projectBrowserResize [winfo width $f.experiments]
    after idle ::GX::projectBrowserScroll
}
proc ::GX::projectGuiShowSelected {} {projectGuiShowSelected_browser083}
proc ::GX::projectGuiRowAction {eid action} {
    projectGuiChooseExperiment $eid
    set code [catch {
        switch -- $action {
            open {openSessionPath [projectExperimentResolve $eid];.top.nb select .top.nb.sessionfiles}
            rename {projectGuiRenameDialog $eid;return}
            info {projectGuiInfoShow $eid;return}
            move {projectGuiMoveDialog $eid;return}
            detach {
                set prior [projectMembershipField $eid project_id]
                if {$prior eq [projectDefaultId]} return
                projectExperimentReassign $eid [projectEnsureDefault] $prior
            }
            delete {
                set path [projectExperimentResolve $eid]
                set info [resourceLifecycleSessionInspect $path]
                if {[tk_messageBox -icon warning -type yesno -default no -title {Delete Session / Experiment} -message "DELETE the complete Session ‘[projectBrowserExperimentName $eid]’?\n\nIts Datasets, analysis, plots, scripts and documents will be removed from normal navigation. A recovery copy will be retained. External sources remain intact.\n\nThis is deletion, not detachment."] ne {yes}} return
                set deleted [projectExperimentDelete $eid]
                setStatus "Session deleted; recovery copy: [dict get $deleted recovery_path]"
            }
        }
    } err]
    if {$code==1} {workflowNotice {Projects — operation failed} "Action: $action\n\n$err";return}
    if {$code==2} {return}
    projectGuiRefresh
    if {$action eq {delete} && [info exists deleted]} {workflowNotice {Session deleted — recovery retained} "The Session was removed from navigation. Its recovery copy is retained at:\n\n[dict get $deleted recovery_path]" info}
}
proc ::GX::projectGuiMoveDialog {eid} {
    set source [projectMembershipField $eid project_id]
    set path [projectExperimentResolve $eid]
    set choices {};set targets {}
    foreach id [projectIds] {
        if {$id eq $source} continue
        set label "[projectField $id name] ($id)"
        lappend choices $label;dict set targets $label $id
    }
    set w .gxExperimentMove;catch {destroy $w};toplevel $w
    wm title $w {Move Experiment to Project};wm transient $w .
    set ::GX::ui(experimentMoveTarget) [lindex $choices 0]
    ttk::label $w.about -text "Experiment: [projectBrowserExperimentName $eid]\nFrom: [projectField $source name]\nExperiment ID: $eid\n\nChoose its destination Project. The Session directory and scientific data stay unchanged." -wraplength 610 -justify left
    ttk::label $w.label -text {Destination Project:}
    ttk::combobox $w.target -state readonly -values $choices -textvariable ::GX::ui(experimentMoveTarget) -width 65
    ttk::label $w.status -text {} -foreground #a02020 -wraplength 610 -justify left
    ttk::frame $w.buttons
    set commit [list ::GX::projectGuiMoveCommit $w $eid $source $path $::GX::currentSession $targets]
    ttk::button $w.buttons.move -text Move -command $commit -state [expr {[llength $choices] ? {normal} : {disabled}}]
    ttk::button $w.buttons.cancel -text Cancel -command [list destroy $w]
    pack $w.about $w.label $w.target $w.status -fill x -padx 12 -pady 6
    pack $w.buttons.move $w.buttons.cancel -side left -padx 5
    pack $w.buttons -pady 10
    bind $w <Escape> [list destroy $w];bind $w.target <Return> $commit;focus $w.target
}
proc ::GX::projectGuiMoveCommit {w eid source path active targets} {
    if {![winfo exists $w]} return
    set failed [catch {
        if {$::GX::currentSession ne $active} {error {The current Session changed. Reopen Move to Project.}}
        if {[projectExperimentResolve $eid] ne $path} {error {The selected Experiment location changed. Reopen Move to Project.}}
        if {![dict exists $targets $::GX::ui(experimentMoveTarget)]} {error {Choose an available destination Project.}}
        projectExperimentReassign $eid [dict get $targets $::GX::ui(experimentMoveTarget)] $source
    } message]
    if {$failed} {$w.status configure -text $message;return}
    destroy $w;projectGuiRefresh
    setStatus "Experiment moved: [projectBrowserExperimentName $eid]"
}
proc ::GX::projectGuiRenameDialog {eid} {
    projectExperimentResolve $eid
    set ::GX::ui(experimentRename) [projectBrowserExperimentName $eid]
    set w .gxExperimentRename;catch {destroy $w};toplevel $w;wm title $w {Rename Session / Experiment};wm transient $w .
    ttk::label $w.label -text {Display name (directory and stable ID stay unchanged):}
    ttk::entry $w.name -textvariable ::GX::ui(experimentRename) -width 65
    ttk::button $w.save -text Save -command [list ::GX::projectGuiRenameCommit $w $eid]
    ttk::button $w.cancel -text Cancel -command [list destroy $w]
    pack $w.label $w.name -fill x -padx 8 -pady 5;pack $w.save $w.cancel -side left -padx 8 -pady 8
    bind $w.name <Return> [list ::GX::projectGuiRenameCommit $w $eid];bind $w <Escape> [list destroy $w];focus $w.name
}
proc ::GX::projectGuiRenameCommit {w eid} {
    if {[catch {projectExperimentRename $eid $::GX::ui(experimentRename)} err]} {workflowNotice {Rename Experiment — failed} $err error $w;return}
    destroy $w;projectGuiRefresh
}
proc ::GX::projectInfoText {parent content} {
    ttk::frame $parent.panel
    text $parent.panel.text -wrap word -width 50 -height 6 -padx 12 -pady 10 -font TkDefaultFont
    ttk::scrollbar $parent.panel.scroll -command [list $parent.panel.text yview]
    $parent.panel.text configure -yscrollcommand [list $parent.panel.scroll set]
    $parent.panel.text insert end $content;$parent.panel.text configure -state disabled
    pack $parent.panel.scroll -side right -fill y;pack $parent.panel.text -fill both -expand 1
    pack $parent.panel -fill both -expand 1
    return $parent.panel.text
}
proc ::GX::projectGuiInfoShow {eid} {
    projectGuiChooseExperiment $eid;set ::GX::projectGuiInfo $eid
    grid remove .top.nb.projects.body.right.scroll
    set parent .top.nb.projects.body.right.experiments.content
    destroyChildren $parent
    ttk::frame $parent.header
    ttk::button $parent.back -text {← Back to Experiments} -command ::GX::projectGuiShowSelected
    ttk::label $parent.title -text [projectBrowserExperimentName $eid] -font TkHeadingFont -wraplength 600 -justify left
    pack $parent.back -in $parent.header -side left -padx 5 -pady 7
    pack $parent.title -in $parent.header -side left -fill x -expand 1 -padx 8
    pack $parent.header -fill x
    set canvas .top.nb.projects.body.right.experiments;$canvas configure -cursor watch;update idletasks
    try {set failed [catch {set info [projectExperimentInspect $eid]} err]} finally {$canvas configure -cursor {}}
    if {$failed} {
        ttk::label $parent.errorTitle -text {Session inspection unavailable} -font TkHeadingFont
        pack $parent.errorTitle -anchor w -padx 12 -pady 10
        projectInfoText $parent "This Session could not be read. The open Session has not changed.\n\n$err"
        projectBrowserResize [winfo width $canvas];return
    }
    set total 0;dict for {kind count} [dict get $info dataset_counts] {incr total $count}
    set docs [dict get $info markdown_documents];set scripts [dict get $info scripts]
    ttk::label $parent.metrics -text "$total Datasets    •    [llength $scripts] registered scripts    •    [llength $docs] Markdown documents    •    read-only inspection" -anchor w
    pack $parent.metrics -fill x -padx 10 -pady 5
    if {[llength [dict get $info diagnostics]]} {
        ttk::label $parent.warning -text "[llength [dict get $info diagnostics]] resource issue(s) — inspect Datasets and Overview for details." -foreground #9b2424
        pack $parent.warning -fill x -padx 10 -pady 3
    }
    ttk::notebook $parent.pages
    foreach {page label} {overview Overview datasets Datasets modules {Modules & Scripts} documents Documents origin {Origin & Technical}} {
        ttk::frame $parent.pages.$page;$parent.pages add $parent.pages.$page -text $label
    }
    pack $parent.pages -fill both -expand 1 -padx 5 -pady 5
    set summary [dict get $info summary];set origin [dict get $info origin]
    set overview "[projectBrowserExperimentName $eid]\n\nProject: [projectField [dict get $info project_id] name]\n"
    foreach {field label} {experiment_date Date experiment_operator Operator experiment_tags Tags experiment_objective Objective experiment_project {Legacy Project text}} {
        set value [datasetPublicationV2DictDefault $summary $field {}]
        if {[string trim $value] ne {}} {append overview "$label: $value\n"}
    }
    append overview "\nScientific content\n$total registered Datasets\n"
    dict for {kind count} [dict get $info dataset_counts] {append overview "  $kind: $count\n"}
    if {$total==0} {append overview "No scientific Datasets are registered in this Session.\n"}
    append overview "\nDeclared creator: [dict get $origin creator_installation]\nCreation kind: [datasetPublicationV2DictDefault $origin creation_kind unknown]\n\nExplore Datasets for available records, Modules & Scripts for saved settings and use evidence, Documents for rendered notes/manuals, and Origin & Technical for lineage and paths.\n\nDataset presence is checked without hashing large scientific payloads. Payload integrity is verified by the normal scientific/Portable APIs when read or transported.\n"
    if {[llength [dict get $info diagnostics]]} {append overview "\nResources needing attention\n[join [dict get $info diagnostics] \n]"}
    projectInfoText $parent.pages.overview $overview
    set dp $parent.pages.datasets
    ttk::label $dp.caption -text {Registered Dataset records — availability is separate from integrity verification} -anchor w
    pack $dp.caption -fill x -padx 8 -pady 5
    ttk::treeview $dp.tree -columns {name contract format status} -show headings -height 5
    foreach {key label width} {name Dataset 170 contract {Type / contract} 190 format Format 80 status Availability 260} {$dp.tree heading $key -text $label;$dp.tree column $key -width $width -minwidth 70 -stretch 1}
    foreach d [dict get $info datasets] {$dp.tree insert {} end -values [list [dict get $d dataset_id] [datasetPublicationV2DictDefault $d kind unknown] [datasetPublicationV2DictDefault $d format unknown] [dict get $d availability]]}
    ttk::scrollbar $dp.sy -command [list $dp.tree yview];$dp.tree configure -yscrollcommand [list $dp.sy set]
    pack $dp.sy -side right -fill y;pack $dp.tree -fill both -expand 1 -padx 6 -pady 6
    set mp $parent.pages.modules
    set text "MODULE SETTINGS AND EXECUTION EVIDENCE\n\nConfigured = saved module fields. Enabled and Run = saved selections, not proof of execution. Used = Dataset source_module evidence only. Other execution history is unknown.\n\n"
    set mids [lsort -unique [concat [dict get $info configured_modules] [dict get $info enabled_modules] [dict get $info run_modules] [dict get $info used_modules]]]
    foreach mid $mids {
        set statuses {}
        foreach {key label} {configured_modules Configured enabled_modules Enabled run_modules {Selected for Run} used_modules {Used: Dataset source record}} {if {$mid in [dict get $info $key]} {lappend statuses $label}}
        append text "$mid\n  [join $statuses { • }]\n"
    }
    if {[llength $mids]==0} {append text "No saved module settings or Dataset use evidence.\n"}
    append text "\nREGISTERED SESSION SCRIPTS\n"
    foreach script $scripts {append text "[datasetPublicationV2DictDefault $script name [dict get $script id]]\n  [dict get $script id] — [datasetPublicationV2DictDefault $script language unknown]\n"}
    if {[llength $scripts]==0} {append text "No registered Session scripts.\n"}
    projectInfoText $mp $text
    set text "DECLARED ORIGIN\n\nCreator installation: [dict get $origin creator_installation]\nCreation: [datasetPublicationV2DictDefault $origin creation_kind unknown]\nDate: [datasetPublicationV2DictDefault $origin created_at unknown]\n\nForeign creator declarations report lineage; they are not authenticated. Older unrecorded creators stay unknown.\n"
    set po [datasetPublicationV2DictDefault $origin parent {}]
    if {$po ne {}} {append text "\nParent Experiment: [datasetPublicationV2DictDefault $po experiment_id unknown]\nParent creator: [datasetPublicationV2DictDefault $po creator_installation unknown]\n"}
    foreach event [datasetPublicationV2DictDefault $origin events {}] {append text "\n[dict get $event kind] — [dict get $event at]\nInstallation: [dict get $event installation_id]\n"}
    append text "\nTECHNICAL DETAILS\n\nExperiment ID: $eid\nProject ID: [dict get $info project_id]\nSession directory: [dict get $info session_path]\nFramework reader: $::GX::version\n"
    projectInfoText $parent.pages.origin $text
    projectGuiDocumentsBuild $parent.pages.documents $eid $docs
    projectBrowserResize [winfo width $canvas];$canvas yview moveto 0
}
proc ::GX::projectDocumentLabel {doc} {
    set parts [file split [dict get $doc path]]
    set stem [string map {_ { } - { }} [file rootname [file tail [dict get $doc path]]]]
    if {[lrange $parts 0 1] eq {metadata documentation}} {
        set module [lindex $parts 2];set name [moduleField $module name [string totitle [string map {. { } _ { }} $module]]]
        return [list generated "$name — [string totitle $stem]"]
    }
    if {[lindex $parts 0] eq {notes}} {
        set category [expr {[llength $parts]>2 ? [string totitle [lindex $parts 1]] : {Session}}]
        return [list notes "$category — [string totitle $stem]"]
    }
    return [list other [string totitle $stem]]
}
proc ::GX::projectGuiDocumentsBuild {parent eid docs} {
    array unset ::GX::projectGuiDocuments *
    if {[llength $docs]==0} {
        ttk::label $parent.empty -text {No Session Markdown documents} -font TkHeadingFont
        ttk::label $parent.explain -text "This Session contains no .md files. Nothing was created or changed by inspection.\nDatasets, registered scripts and origin remain available in the other sections." -justify left
        pack $parent.empty $parent.explain -anchor nw -padx 15 -pady 12;return
    }
    ttk::panedwindow $parent.split -orient horizontal
    ttk::frame $parent.list;ttk::frame $parent.detail
    $parent.split add $parent.list -weight 1;$parent.split add $parent.detail -weight 3
    pack $parent.split -fill both -expand 1 -padx 5 -pady 5
    ttk::treeview $parent.documents -columns {size} -show {tree headings} -selectmode browse
    $parent.documents heading #0 -text {Notes and documentation};$parent.documents column #0 -width 260 -minwidth 160 -stretch 1
    $parent.documents heading size -text Bytes;$parent.documents column size -width 65 -stretch 0
    ttk::scrollbar $parent.sy -command [list $parent.documents yview];$parent.documents configure -yscrollcommand [list $parent.sy set]
    pack $parent.sy -in $parent.list -side right -fill y;pack $parent.documents -in $parent.list -fill both -expand 1
    foreach {id label} {notes {Session notes} generated {Module documentation / snapshots} other {Other Session documents}} {$parent.documents insert {} end -id $id -text $label -open 1}
    set i 0;set initial {};set first {};set snapshots {}
    foreach doc $docs {
        lassign [projectDocumentLabel $doc] group label
        set id doc[incr i];set ::GX::projectGuiDocuments($id) $doc
        if {$group eq {generated}} {dict incr snapshots $label;append label " — snapshot [dict get $snapshots $label]"}
        $parent.documents insert $group end -id $id -text $label -values [list [dict get $doc size]]
        if {$first eq {}} {set first $id}
        if {$group eq {notes} && [dict get $doc size]>0 && $initial eq {}} {set initial $id}
    }
    ttk::frame $parent.detail.header
    ttk::label $parent.documentTitle -text {Select a document for verified, read-only preview} -font TkHeadingFont -wraplength 400 -width 1
    ttk::button $parent.details -text {Document details…} -command [list ::GX::projectGuiDocumentDetails $parent]
    grid columnconfigure $parent.detail.header 0 -weight 1
    grid $parent.documentTitle -in $parent.detail.header -row 0 -column 0 -sticky ew -padx 5
    grid $parent.details -in $parent.detail.header -row 0 -column 1 -padx 5
    bind $parent.detail.header <Configure> [list ::GX::projectDocumentHeaderResize $parent %w]
    pack $parent.detail.header -fill x -pady 5
    text $parent.preview -wrap word -height 6 -width 30 -state disabled -padx 12 -pady 10 -font TkDefaultFont
    ttk::scrollbar $parent.previewScroll -command [list $parent.preview yview];$parent.preview configure -yscrollcommand [list $parent.previewScroll set]
    pack $parent.previewScroll -in $parent.detail -side right -fill y;pack $parent.preview -in $parent.detail -fill both -expand 1
    bind $parent.documents <<TreeviewSelect>> [list ::GX::projectGuiDocumentPreview $eid]
    if {$initial eq {}} {set initial $first}
    $parent.documents selection set $initial;$parent.documents see $initial
    after idle [list ::GX::projectGuiDocumentPreview $eid]
}
proc ::GX::projectDocumentHeaderResize {parent width} {
    if {[winfo exists $parent.documentTitle]} {$parent.documentTitle configure -wraplength [expr {max(100,$width-160)}]}
}
proc ::GX::projectGuiDocumentPreview {eid} {
    if {$eid ne $::GX::projectGuiInfo} return
    set parent .top.nb.projects.body.right.experiments.content.pages.documents
    if {![winfo exists $parent.documents]} return
    set selected [$parent.documents selection];if {[llength $selected]!=1 || ![info exists ::GX::projectGuiDocuments([lindex $selected 0])]} return
    set doc $::GX::projectGuiDocuments([lindex $selected 0]);lassign [projectDocumentLabel $doc] group title
    $parent.documentTitle configure -text $title
    if {[catch {set content [projectExperimentDocumentRead $eid [dict get $doc path] [dict get $doc sha256]]} err]} {set content "Preview unavailable:\n$err"}
    if {[string trim $content] eq {}} {set content {This Markdown document is empty.}}
    # Reuse the established scientific Markdown renderer, without an editable
    # source view or file execution. The public reader verifies path and SHA.
    markupRenderStringToWidget $parent.preview $content
    $parent.preview configure -state disabled
}
proc ::GX::projectGuiDocumentDetails {parent} {
    set selected [$parent.documents selection];if {[llength $selected]!=1 || ![info exists ::GX::projectGuiDocuments([lindex $selected 0])]} return
    set doc $::GX::projectGuiDocuments([lindex $selected 0])
    workflowNotice {Markdown document — technical details} "Session-relative path:\n[dict get $doc path]\n\nSHA-256:\n[dict get $doc sha256]\n\nBytes: [dict get $doc size]\n\nPreview verifies this content before rendering; no file is executed." info $parent
}
proc ::GX::projectPortableDiagnosticsText {diagnostics} {
    set text {}
    foreach rec [dict get $diagnostics missing_plugins] {append text "Missing module: [dict get $rec id] (package version [dict get $rec required_version]).\n"}
    foreach rec [dict get $diagnostics version_differences] {append text "Module [dict get $rec id]: package version [dict get $rec required_version], installed [dict get $rec installed_version].\n"}
    foreach rec [dict get $diagnostics external_dependencies] {append text "External dependency ([dict get $rec kind]): [dict get $rec path]\n"}
    if {$text eq {}} {return {All recorded module dependencies are available. No unresolved external dependencies.}}
    append text "\nScientific files were preserved. Install or resolve these dependencies before running the affected work."
    return $text
}
proc ::GX::projectGuiImportExperiment {} {
    set id [projectGuiSelectedId]
    if {$id eq {}} return
    set archive [workspaceOpenFile session_open_dir -title {Import Experiment — Portable Session} -filetypes {{{Portable Session ZIP} {.zip}}}]
    if {$archive eq {}} return
    if {[catch {set info [sessionPortableValidate $archive]} err]} {workflowNotice {Import Experiment — invalid package} "Package: $archive\n\n$err\n\nChoose a validated Portable Session ZIP. No Session was imported.";return}
    set ::GX::ui(projectImportName) [dict get $info session_name]
    set ::GX::ui(projectImportArchive) $archive
    set w .gxProjectImport;catch {destroy $w};toplevel $w;wm title $w {Import Experiment into Project};wm transient $w .
    ttk::label $w.label -text "Import into [projectField $id name]. Choose a new directory name; existing Sessions are never overwritten. Scientific IDs/bytes and declared creator are retained; a fresh organizational Experiment ID and receiving event are issued." -wraplength 600
    ttk::entry $w.name -textvariable ::GX::ui(projectImportName) -width 55
    ttk::button $w.import -text Import -command [list ::GX::projectGuiImportCommit $w $id]
    ttk::button $w.cancel -text Cancel -command [list destroy $w]
    pack $w.label $w.name -fill x -padx 8 -pady 5;pack $w.import $w.cancel -side left -padx 8 -pady 8
}
proc ::GX::projectGuiImportCommit {w id} {
    set name [string trim $::GX::ui(projectImportName)]
    if {$name eq {}} {workflowNotice {Import Experiment} {Enter a destination name for the new Session.};return}
    set destination [file join [projectSessionsRoot $id] [sanitize $name]]
    if {[catch {set result [projectImportExperiment $id $::GX::ui(projectImportArchive) $destination]} err]} {workflowNotice {Import Experiment — failed} "Destination: $destination\n\n$err\n\nExisting Sessions are never overwritten. Choose another name or Cancel." error $w;return}
    destroy $w;set ::GX::projectGuiExperiment [dict get $result experiment_id];projectGuiRefresh
    workflowNotice {Experiment imported} "Imported into [projectField $id name].\nSession: [projectBrowserExperimentName [dict get $result experiment_id]]\n\nDependency diagnostics:\n[projectPortableDiagnosticsText [dict get $result diagnostics]]" info
}
proc ::GX::projectGuiExportExperiment {} {
    set eid $::GX::projectGuiExperiment
    if {$eid eq {} || [projectMembershipField $eid project_id] ne [projectGuiSelectedId]} {workflowNotice {Export Experiment} {Select an Experiment row first. Export produces one lossless Portable Session package for that selected Session.} info;return}
    set archive [workspaceSaveFile export_dir -title {Export Experiment — Portable Session} -initialfile [sanitize [projectBrowserExperimentName $eid]].gxtxt-session.zip -defaultextension .zip]
    if {$archive eq {}} return
    if {[catch {set result [projectExportExperiment $eid $archive]} err]} {workflowNotice {Export Experiment — failed} "Session: [projectBrowserExperimentName $eid]\n\n$err";return}
    workflowNotice {Experiment exported} "Session: [projectBrowserExperimentName $eid]\nPortable Session exported losslessly.\n\n[dict get $result archive]\n\nDependency diagnostics:\n[projectPortableDiagnosticsText [sessionPortableDependencyDiagnostics [dict get $result package_info]]]" info
}
proc ::GX::projectGuiOpenExperiment {} {if {$::GX::projectGuiExperiment ne {}} {projectGuiRowAction $::GX::projectGuiExperiment open}}
proc ::GX::projectGuiDetachExperiment {} {if {$::GX::projectGuiExperiment ne {}} {projectGuiRowAction $::GX::projectGuiExperiment detach}}
rename ::GX::projectGuiBuild ::GX::projectGuiBuild_before_browser083
proc ::GX::projectGuiBuild {} {
    projectGuiBuild_before_browser083
    set f .top.nb.projects.body.right
    # Retain the original read-only Project metadata widgets above the browser.
    foreach child {expLabel experiments actions status} {destroy $f.$child}
    foreach r {0 1 2 3 4 5 6 7 8 9 10 11 12 13} {grid rowconfigure $f $r -weight 0}
    grid rowconfigure $f 11 -weight 1;grid columnconfigure $f 0 -weight 0;grid columnconfigure $f 1 -weight 1;grid columnconfigure $f 2 -weight 0
    set r 1
    foreach field {name id description notes tags author storage_path created_at updated_at} {
        grid configure $f.label_$field -row $r
        grid configure $f.value_$field -row $r
        incr r
    }
    .top.nb.projects.body.left.tree column name -width 240
    .top.nb.projects.body.left.tree column updated -width 100
    .top.nb.projects.toolbar.select configure -text {Move open Session here}
    .top.nb.projects.toolbar.newSession configure -text {New Session here…}
    ttk::button .top.nb.projects.toolbar.importProject -text {Import Project…} -command ::GX::projectGuiImportProject
    ttk::button .top.nb.projects.toolbar.exportProject -text {Export Project…} -command ::GX::projectGuiExportProject -state disabled
    set bar .top.nb.projects.toolbar
    # Keep the existing command widgets/controllers; menus invoke those commands.
    foreach button {new edit delete select newSession refresh} {pack forget $bar.$button}
    foreach {group title entries} {
        projectMenu Project {new Create edit Edit delete {Delete Project…}}
        sessionsMenu Sessions {select {Move open Session here} newSession {New Session here…}}
        transferMenu {Import / Export} {importProject {Import Project…} exportProject {Export Project…}}
    } {
        ttk::menubutton $bar.$group -text $title -menu $bar.$group.menu
        menu $bar.$group.menu -tearoff 0
        foreach {button label} $entries {$bar.$group.menu add command -label $label -command [list $bar.$button invoke]}
        pack $bar.$group -side left -padx 3 -pady 4
    }
    pack $bar.refresh -side left -padx 3 -pady 4
    ttk::label $f.title -text {Choose a Project} -font TkHeadingFont -anchor w
    ttk::label $f.subtitle -text {} -anchor w -justify left -wraplength 850
    grid $f.title -row 0 -column 0 -columnspan 3 -sticky ew -padx 8 -pady 5
    grid $f.subtitle -row 10 -column 0 -columnspan 3 -sticky ew -padx 8 -pady 5
    canvas $f.experiments -highlightthickness 0 -yscrollincrement 24
    ttk::frame $f.experiments.content
    $f.experiments create window 0 0 -anchor nw -window $f.experiments.content -tags body
    ttk::scrollbar $f.scroll -command [list $f.experiments yview];$f.experiments configure -yscrollcommand [list $f.scroll set]
    grid $f.experiments -row 11 -column 0 -columnspan 2 -sticky nsew -padx 4;grid $f.scroll -row 11 -column 2 -sticky ns
    ttk::frame $f.actions
    ttk::button $f.actions.import -text {Import Experiment into this Project…} -command ::GX::projectGuiImportExperiment
    ttk::button $f.actions.export -text {Export selected Experiment…} -command ::GX::projectGuiExportExperiment -state disabled
    pack $f.actions.import $f.actions.export -side left -padx 4 -pady 4
    grid $f.actions -row 12 -column 0 -columnspan 3 -sticky ew
    ttk::label $f.status -text {} -anchor w -justify left -wraplength 850
    grid $f.status -row 13 -column 0 -columnspan 3 -sticky ew -padx 8 -pady 4
    bind $f.experiments <Configure> {::GX::projectBrowserResize %w}
    bind $f.experiments.content <Configure> ::GX::projectBrowserScroll
    bind $f.experiments <MouseWheel> {::GX::projectBrowserWheel %D}
    set ::GX::projectBrowserSashInitialized 0
    bind .top.nb.projects.body <Configure> {::GX::projectBrowserInitialSplit %w}
    projectGuiRefresh
}
proc ::GX::projectBrowserInitialSplit {width} {
    if {$::GX::projectBrowserSashInitialized || $width<700} return
    set ::GX::projectBrowserSashInitialized 1
    .top.nb.projects.body sashpos 0 340
}

# Host navigation only; the Session controller keeps its existing open/save flow.
proc ::GX::projectGuiCurrentHome {} {
    set id [projectCurrentId]
    if {$::GX::currentSession eq {} || ![projectExists $id]} {workflowNotice {Project Home} {Open a Session associated with a Project first.} info;return}
    set eid [expr {[info exists ::GX::cfg(experiment_id)] ? $::GX::cfg(experiment_id) : {}}]
    .top.nb select .top.nb.projects
    projectGuiRefresh
    set tree .top.nb.projects.body.left.tree
    $tree selection set $id;$tree focus $id;$tree see $id
    set ::GX::projectGuiExperiment $eid
    projectGuiShowSelected
    after idle [list ::GX::projectGuiNavigate $eid 0]
}
proc ::GX::projectGuiExportProject {} {
    set id [projectGuiSelectedId]
    if {$id eq {}} {workflowNotice {Export Project} {Select the Project to export first.} info;return}
    set archive [workspaceSaveFile export_dir -title {Export complete Project} -initialfile "[sanitize [projectField $id name]].gxtxt-project.zip" -defaultextension .zip -filetypes {{{GX-TXT portable Project} {.zip}} {{All files} *}}]
    if {$archive eq {}} return
    if {[catch {set result [projectPortableExport $id $archive]} err]} {workflowNotice {Project export failed} $err error;return}
    workflowNotice {Project exported} "Complete portable Project saved:\n$archive\n\nExperiments: [dict get $result experiment_count]\nModule snapshots: [dict get $result dependency_count]\nSHA-256: [dict get $result sha256]" info
}
proc ::GX::projectGuiImportProject {} {
    set archive [workspaceOpenFile session_open_dir -title {Import complete Project} -filetypes {{{GX-TXT portable Project} {.zip}} {{All files} *}}]
    if {$archive eq {}} return
    if {[catch {projectPortableValidate $archive} err]} {workflowNotice {Invalid Project package} $err error;return}
    set w .gxProjectPortableImport;catch {destroy $w};toplevel $w;wm title $w {Import Project};wm transient $w .
    set ::GX::ui(projectPortableArchive) $archive;set ::GX::ui(projectPortableName) {}
    ttk::label $w.about -text {Import creates a separate Project with new local identifiers. All source identities and scientific files are retained. Existing Projects and Sessions are preserved. Leave the name blank to use the original name.} -wraplength 520 -justify left
    ttk::label $w.file -text [file tail $archive]
    ttk::label $w.label -text {Project name (optional):}
    ttk::entry $w.name -textvariable ::GX::ui(projectPortableName) -width 48
    ttk::frame $w.buttons
    ttk::button $w.buttons.import -text {Import Project} -command [list ::GX::projectGuiImportProjectCommit $w]
    ttk::button $w.buttons.cancel -text Cancel -command [list destroy $w]
    pack $w.about $w.file $w.label $w.name -fill x -padx 12 -pady 5
    pack $w.buttons.import $w.buttons.cancel -side left -padx 5
    pack $w.buttons -pady 10
    bind $w <Escape> [list destroy $w];bind $w.name <Return> [list ::GX::projectGuiImportProjectCommit $w];focus $w.name
}
proc ::GX::projectGuiImportProjectCommit {w} {
    if {[catch {set result [projectPortableImport $::GX::ui(projectPortableArchive) $::GX::ui(projectPortableName)]} err]} {workflowNotice {Project import failed} $err error;return}
    destroy $w
    projectGuiRefresh;set tree .top.nb.projects.body.left.tree;set id [dict get $result project_id]
    $tree selection set $id;$tree see $id;$tree focus $id;projectGuiShowSelected
    set message "Project imported: [projectField $id name]\nExperiments: [dict size [dict get $result experiments]]\n\nAll source identities and lineage are retained. Module snapshots are saved with this Project."
    dict for {eid diagnostic} [dict get $result diagnostics] {
        set issues [projectPortableDiagnosticsText $diagnostic]
        if {$issues ne {}} {append message "\n\n[projectBrowserExperimentName $eid]:\n$issues"}
    }
    workflowNotice {Project imported} $message info
}
