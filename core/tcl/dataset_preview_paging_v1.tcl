# Bounded table preview extension of DATASET_PREVIEW_API_v1.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX {variable datasetPreviewPageState}
proc ::GX::datasetPreviewPage {session datasetId {options {}}} {
    set start [tableStreamOption $options start 0]
    set count [tableStreamOption $options count 100]
    set selected [tableStreamOption $options variable_ids {}]
    foreach {value name} [list $start start $count count] {
        if {![string is entier -strict $value] || $value<0} {error "Preview $name must be a nonnegative integer"}
    }
    if {$count<1 || $count>1000} {error "Preview count must be between 1 and 1000"}
    set access [datasetAccessOpen $session $datasetId]
    try {set metadata [datasetAccessMetadata $access]} finally {datasetAccessClose $access}
    set variables [dict get $metadata variables]
    set byId [dict create]
    foreach variable $variables {dict set byId [dict get $variable variable_id] $variable}
    if {![llength $selected]} {
        foreach variable $variables {
            if {[dict get $variable rank]==1} {lappend selected [dict get $variable variable_id]}
            if {[llength $selected]>=32} break
        }
    }
    if {![llength $selected]} {return [dict create available 0 reason "Dataset has no table-shaped variables"]}
    set columns {}
    foreach id $selected {
        if {![dict exists $byId $id]} {error "Dataset $datasetId has no variable $id"}
        set variable [dict get $byId $id]
        set label [dict get $variable display_label]
        if {$label eq ""} {set label [dict get $variable canonical]}
        if {$label eq ""} {set label $id}
        lappend columns [dict merge $variable [dict create label $label]]
    }
    set total [dict get $metadata row_count]
    if {$total>=0 && $start>$total} {error "Preview source row is outside Dataset $datasetId ($total rows)"}
    set rangeCount [expr {$total<0 ? $count : min($count,$total-$start)}]
    set stream [tableStreamOpenDataset $session $datasetId $selected $count [dict create start $start count $rangeCount numeric_transport values]]
    try {set chunk [tableStreamNext $stream]} finally {tableStreamClose $stream}
    set rows {};set sourceRows {}
    for {set r 0} {$r<[dict get $chunk row_count]} {incr r} {
        set row {}
        foreach id $selected {lappend row [lindex [dict get $chunk values $id] $r]}
        lappend rows $row;lappend sourceRows [expr {$start+$r+1}]
    }
    set total [dict get $metadata row_count]
    return [dict create available 1 dataset_id $datasetId storage_provider [dict get $metadata storage_provider] row_count $total start $start count [llength $rows] page_size $count source_rows $sourceRows columns $columns rows $rows total_variable_count [llength $variables] selected_variable_count [llength $selected] has_previous [expr {$start>0}] has_next [expr {$total>=0 ? $start+[llength $rows]<$total : [llength $rows]==$count}]]
}
proc ::GX::datasetPreviewTableSnapshot {session datasetId {maxRows ""} {maxColumns ""}} {
    if {$maxRows eq ""} {set maxRows [previewSetting table_rows]}
    if {$maxColumns eq ""} {set maxColumns [previewSetting table_columns]}
    set handle [datasetAccessOpen $session $datasetId]
    try {set metadata [datasetAccessMetadata $handle]} finally {datasetAccessClose $handle}
    set selected {}
    foreach variable [dict get $metadata variables] {
        if {[dict get $variable rank]==1} {lappend selected [dict get $variable variable_id]}
        if {[llength $selected]>=$maxColumns} break
    }
    return [datasetPreviewPage $session $datasetId [dict create count [expr {min(1000,max(1,$maxRows))}] variable_ids $selected]]
}
proc ::GX::datasetPreviewTableCurrent {parent} {
    variable datasetPreviewPageState
    if {![info exists datasetPreviewPageState($parent)]} {return 0}
    set state $datasetPreviewPageState($parent)
    if {![catch {interactiveDocumentSessionToken} token] && [dict get $state session_token] eq $token} {return 1}
    # Retain the accepted page as a previous-Session observation. In
    # particular, a queued Go/Return must not read its old source after the
    # active Session has changed.
    $parent.status configure -text "Previous Session table ([file tail [dict get $state session]] / [dict get $state dataset_id]). Reopen the table from the active Session."
    foreach control {previous next go row} {
        if {[winfo exists $parent.nav.$control]} {$parent.nav.$control configure -state disabled}
    }
    return 0
}
proc ::GX::datasetPreviewTableCatalogChanged {parent receipt} {
    if {[winfo exists $parent.tree]} {datasetPreviewTableCurrent $parent}
}
proc ::GX::datasetPreviewTableCopy {parent {section data}} {
    variable datasetPreviewPageState
    if {![info exists datasetPreviewPageState($parent)] || ![winfo exists $parent.tree]} {return 0}
    if {![datasetPreviewTableCurrent $parent]} {return 0}
    set state $datasetPreviewPageState($parent)
    # Copy the retained observation only while its existing scientific source
    # identity is current. Never silently copy a previous Session/schema/source.
    if {![dict exists $state copy_source_identity] ||
        [catch {datasetViewerScientificIdentity [dict get $state dataset_id]} identity] ||
        $identity ne [dict get $state copy_source_identity]} {
        $parent.status configure -text {Dataset source changed or is unavailable. Refresh or reopen the table before copying.}
        return 0
    }
    set tree [expr {$section eq {schema} ? "$parent.schema.tree" : "$parent.tree"}]
    if {![llength [$tree selection]]} {
        $parent.status configure -text {Select one or more table rows to copy.}
        return 0
    }
    if {[catch {uiFieldComponentTableCopy $tree} count]} {
        $parent.status configure -text "Unable to copy selected rows: $count"
        return 0
    }
    if {$count>0} {$parent.status configure -text "Copied $count selected data row(s)."}
    return $count
}
proc ::GX::datasetPreviewTableRefresh {parent {delta 0}} {
    variable datasetPreviewPageState
    if {![datasetPreviewTableCurrent $parent]} {return 0}
    set state $datasetPreviewPageState($parent)
    set start [expr {max(0,[dict get $state start]+$delta*[dict get $state count])}]
    if {[catch {
        set page [datasetPreviewPage [dict get $state session] [dict get $state dataset_id] [dict create start $start count [dict get $state count] variable_ids [dict get $state variable_ids]]]
        set copyIdentity [datasetViewerScientificIdentity [dict get $state dataset_id]]
    } reason]} {
        $parent.status configure -text $reason
        return 0
    }
    if {![datasetPreviewTableCurrent $parent]} {return 0}
    if {![dict get $page available]} {$parent.status configure -text [dict get $page reason];return 0}
    $parent.tree delete [$parent.tree children {}]
    set ids {};foreach column [dict get $page columns] {lappend ids [dict get $column variable_id]}
    set previousColumns [$parent.tree cget -columns];set previousSizing {}
    if {$previousColumns ne $ids} {
        foreach id $previousColumns {dict set previousSizing $id [list -width [$parent.tree column $id -width] -minwidth [$parent.tree column $id -minwidth] -stretch [$parent.tree column $id -stretch]]}
        $parent.tree configure -columns $ids
    }
    set headingFont [ttk::style lookup Treeview.Heading -font]
    if {$headingFont eq ""} {set headingFont TkHeadingFont}
    set fontSignature [font actual $headingFont]
    set oldHeaders [::GX::datasetPublicationV2DictDefault $state header_signatures {}];set headers {}
    $parent.tree heading #0 -text "Source row"
    set signature [list "Source row" $fontSignature];dict set headers #0 $signature
    if {![dict exists $oldHeaders #0]||[dict get $oldHeaders #0] ne $signature} {
        set required [expr {max(95,[font measure $headingFont "Source row"]+24)}]
        $parent.tree column #0 -width $required -minwidth $required -stretch 0
    }
    foreach column [dict get $page columns] {
        set label [dict get $column label]
        if {[dict get $column unit] ne ""} {append label " ([dict get $column unit])"}
        set id [dict get $column variable_id]
        $parent.tree heading $id -text $label
        set signature [list $label $fontSignature];dict set headers $id $signature
        if {![dict exists $oldHeaders $id]||[dict get $oldHeaders $id] ne $signature} {
            set required [expr {min(480,max(150,[font measure $headingFont $label]+24))}]
            $parent.tree column $id -width $required -minwidth $required -stretch 0
        } elseif {[dict exists $previousSizing $id]} {
            $parent.tree column $id {*}[dict get $previousSizing $id]
        }
    }
    foreach sourceRow [dict get $page source_rows] row [dict get $page rows] {$parent.tree insert {} end -id "row.$sourceRow" -text $sourceRow -values $row}
    set total [dict get $page row_count]
    if {$total<0} {set total unknown}
    $parent.status configure -text "Dataset: [dict get $page dataset_id] · Storage: [dict get $page storage_provider] · Rows [expr {$start+1}]–[expr {$start+[dict get $page count]}] of $total"
    $parent.nav.previous configure -state [expr {[dict get $page has_previous] ? "normal" : "disabled"}]
    $parent.nav.next configure -state [expr {[dict get $page has_next] ? "normal" : "disabled"}]
    dict set state start $start
    dict set state header_signatures $headers
    dict set state page $page
    dict set state copy_source_identity $copyIdentity
    set datasetPreviewPageState($parent) $state
    datasetPreviewTableSchemaRefresh $parent $page
    return 1
}
proc ::GX::datasetPreviewTableSchemaRefresh {parent page} {
    set tree $parent.schema.tree
    $tree delete [$tree children {}]
    foreach column [dict get $page columns] {
        set values {}
        foreach key {variable_id label dtype value_kind unit semantic_role shape} {
            set value [datasetPublicationV2DictDefault $column $key {}]
            if {$value eq {}} {set value {(not declared)}}
            lappend values $value
        }
        $tree insert {} end -id [dict get $column variable_id] -values $values
    }
    $parent.schema.caption configure -text "Declared variable schema: [dict get $page selected_variable_count] displayed columns of [dict get $page total_variable_count]. Empty metadata is shown as not declared."
    uiFieldInspectionColumnsSchedule $tree
}
proc ::GX::datasetPreviewTableSchemaToggle {parent} {
    if {[winfo manager $parent.schema] eq {}} {
        grid $parent.schema -row 4 -column 0 -columnspan 2 -sticky nsew -pady 4
        $parent.nav.schema configure -text {Hide column details}
        uiFieldInspectionColumnsSchedule $parent.schema.tree
    } else {
        grid remove $parent.schema
        $parent.nav.schema configure -text {Column details}
    }
}
# The same bounded page and declared schema back both standalone and embedded
# consultation. This is an observation, not a second schema/data authority.
proc ::GX::datasetPreviewTableInspect {parent} {
    variable datasetPreviewPageState
    if {![info exists datasetPreviewPageState($parent)] || ![winfo exists $parent.tree]} {error {Unknown or closed table consultation}}
    set state $datasetPreviewPageState($parent)
    if {![dict exists $state page]} {return [dict create status unavailable read_only 1]}
    if {![datasetPreviewTableCurrent $parent]} {
        return [dict merge [dict get $state page] [dict create status unavailable read_only 1 current 0 reason {Previous Session table; reopen from the active Session} selected_source_rows {} schema_visible [expr {[winfo manager $parent.schema] ne {}}]]]
    }
    set selected {}
    foreach item [$parent.tree selection] {lappend selected [$parent.tree item $item -text]}
    return [dict merge [dict get $state page] [dict create status ready read_only 1 selected_source_rows $selected schema_visible [expr {[winfo manager $parent.schema] ne {}}]]]
}
proc ::GX::datasetPreviewTableGoto {parent} {
    variable datasetPreviewPageState;variable datasetPreviewGoto
    if {![datasetPreviewTableCurrent $parent]} return
    if {![string is entier -strict $datasetPreviewGoto($parent)] || $datasetPreviewGoto($parent)<1} {$parent.status configure -text "Enter a positive source row number";return}
    set before $datasetPreviewPageState($parent)
    dict set datasetPreviewPageState($parent) start [expr {$datasetPreviewGoto($parent)-1}]
    if {![datasetPreviewTableRefresh $parent]} {set datasetPreviewPageState($parent) $before}
}
proc ::GX::datasetPreviewOpenSelectedTable {{surface preview}} {
    variable csvPreviewDatasetChoice;variable variableDatasetChoice
    set choice [expr {$surface eq "variables" ? $variableDatasetChoice : $csvPreviewDatasetChoice}]
    lassign [datasetInspectionParseChoice $choice] mode id
    if {$mode ne "imported" || $id eq ""} {setStatus "Select an imported table Dataset first." 0;return}
    return [datasetPreviewOpenTable $id]
}
proc ::GX::datasetPreviewCreateTable {parent session datasetId {variableIds {}}} {
    variable datasetPreviewPageState;variable datasetPreviewGoto
    ttk::frame $parent
    ttk::label $parent.status -wraplength 650
    ttk::treeview $parent.tree -show {tree headings} -selectmode extended
    bind $parent.tree <Control-c> "[list ::GX::datasetPreviewTableCopy $parent];break"
    bind $parent.tree <Control-C> "[list ::GX::datasetPreviewTableCopy $parent];break"
    ttk::scrollbar $parent.vertical -orient vertical -command [list $parent.tree yview]
    ttk::scrollbar $parent.horizontal -orient horizontal -command [list $parent.tree xview]
    $parent.tree configure -yscrollcommand [list $parent.vertical set] -xscrollcommand [list $parent.horizontal set]
    ttk::frame $parent.nav
    ttk::button $parent.nav.previous -text "Previous page" -command [list ::GX::datasetPreviewTableRefresh $parent -1]
    ttk::button $parent.nav.next -text "Next page" -command [list ::GX::datasetPreviewTableRefresh $parent 1]
    ttk::label $parent.nav.label -text "Go to source row:"
    set datasetPreviewGoto($parent) 1
    ttk::entry $parent.nav.row -width 12 -textvariable ::GX::datasetPreviewGoto($parent)
    ttk::button $parent.nav.go -text "Go" -command [list ::GX::datasetPreviewTableGoto $parent]
    ttk::button $parent.nav.schema -text {Column details} -command [list ::GX::datasetPreviewTableSchemaToggle $parent]
    bind $parent.nav.row <Return> [list ::GX::datasetPreviewTableGoto $parent]
    pack $parent.nav.previous $parent.nav.next $parent.nav.label $parent.nav.row $parent.nav.go $parent.nav.schema -side left -padx 5 -pady 5
    bind $parent.nav <Configure> [list ::GX::uiFieldControlsLayout $parent.nav %w]
    ttk::frame $parent.schema
    ttk::label $parent.schema.caption -wraplength 650
    ttk::treeview $parent.schema.tree -show headings -columns {variable_id label dtype value_kind unit semantic_role shape} -height 4 -selectmode browse
    foreach {key title} {variable_id {Variable ID} label Label dtype Type value_kind {Value kind} unit Unit semantic_role {Semantic role} shape Shape} {
        $parent.schema.tree heading $key -text $title
        $parent.schema.tree column $key -width 140 -minwidth 90 -stretch 0
    }
    ttk::scrollbar $parent.schema.vertical -command [list $parent.schema.tree yview]
    ttk::scrollbar $parent.schema.horizontal -orient horizontal -command [list $parent.schema.tree xview]
    $parent.schema.tree configure -yscrollcommand [list $parent.schema.vertical set] -xscrollcommand [list $parent.schema.horizontal set]
    bind $parent.schema.tree <Control-c> "[list ::GX::datasetPreviewTableCopy $parent schema];break"
    bind $parent.schema.tree <Control-C> "[list ::GX::datasetPreviewTableCopy $parent schema];break"
    grid $parent.schema.caption -row 0 -column 0 -columnspan 2 -sticky ew
    grid $parent.schema.tree -row 1 -column 0 -sticky nsew
    grid $parent.schema.vertical -row 1 -column 1 -sticky ns
    grid $parent.schema.horizontal -row 2 -column 0 -sticky ew
    grid columnconfigure $parent.schema 0 -weight 1
    grid rowconfigure $parent.schema 1 -weight 1
    grid $parent.status -row 0 -column 0 -columnspan 2 -sticky ew -pady 6
    grid $parent.tree -row 1 -column 0 -sticky nsew
    grid $parent.vertical -row 1 -column 1 -sticky ns
    grid $parent.horizontal -row 2 -column 0 -sticky ew
    grid $parent.nav -row 3 -column 0 -columnspan 2 -sticky ew
    grid rowconfigure $parent 1 -weight 1;grid columnconfigure $parent 0 -weight 1
    set datasetPreviewPageState($parent) [dict create session $session session_token [interactiveDocumentSessionToken] dataset_id $datasetId variable_ids $variableIds start 0 count 100]
    dict set datasetPreviewPageState($parent) subscription [datasetCatalogSubscribe [list ::GX::datasetPreviewTableCatalogChanged $parent]]
    bind $parent <Destroy> +[list ::GX::datasetPreviewTableCleanup $parent %W]
    datasetPreviewTableRefresh $parent
    return $parent
}
proc ::GX::datasetPreviewTableCleanup {parent widget} {
    if {$widget ne $parent} return
    if {[info exists ::GX::datasetPreviewPageState($parent)] && [dict exists $::GX::datasetPreviewPageState($parent) subscription]} {
        datasetCatalogUnsubscribe [dict get $::GX::datasetPreviewPageState($parent) subscription]
    }
    catch {unset ::GX::datasetPreviewPageState($parent)}
    catch {unset ::GX::datasetPreviewGoto($parent)}
}
proc ::GX::datasetPreviewOpenTable {datasetId} {
    variable currentSession
    set w .datasetTablePreview
    catch {destroy $w}
    toplevel $w;wm title $w "Dataset table — $datasetId";wm geometry $w 900x550;wm minsize $w 460 300
    pack [datasetPreviewCreateTable $w.table $currentSession $datasetId] -fill both -expand 1 -padx 8 -pady 8
    ttk::button $w.close -text "Close" -command [list destroy $w]
    pack $w.close -side bottom -pady 6
    bind $w <Escape> [list destroy $w]
    return $w
}
