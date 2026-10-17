# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::ResultsView {variable records {};variable selected {};variable session {};variable search {};variable category All;variable offset 0;variable status {Open a Session to inspect scientific and import results.};variable epoch 0}
proc ::GX::buildResultsPage {} {
    set f .top.nb.results
    ttk::frame $f.buttons
    foreach {id label command} {refresh Refresh ::GX::refreshResults copy {Copy checked results} ::GX::resultsCopyChecked all {Check displayed group} ::GX::resultsCheckDisplayed clear {Clear all} ::GX::resultsClearChecked open {Open focused result} ::GX::resultsOpenFocused} {ttk::button $f.buttons.$id -text $label -command $command;pack $f.buttons.$id -side left -padx 3}
    ttk::entry $f.buttons.search -textvariable ::GX::ResultsView::search -width 20
    ttk::combobox $f.buttons.category -textvariable ::GX::ResultsView::category -state readonly -values {All Acquisition/import {Canonical Datasets} Analysis {Viewer publications} {Scientific Jobs} {User Script Jobs}} -width 22
    pack $f.buttons.category $f.buttons.search -side left -padx 3
    bind $f.buttons.search <KeyRelease> ::GX::resultsRenderInventory
    bind $f.buttons.category <<ComboboxSelected>> ::GX::resultsRenderInventory
    bind $f.buttons <Configure> {::GX::uiFieldControlsLayout %W %w}
    pack $f.buttons -fill x -padx 5 -pady 4
    ttk::panedwindow $f.split -orient vertical
    ttk::frame $f.split.inventory;ttk::frame $f.split.details
    $f.split add $f.split.inventory -weight 1;$f.split add $f.split.details -weight 2
    uiFieldCheckTableCreate $f.inventory {name category producer type state} ::GX::resultsRenderChecked
    foreach {id label} {name Result category Category producer Producer type Type state Status} {$f.inventory heading $id -text $label;$f.inventory column $id -width 160 -stretch 1}
    ttk::scrollbar $f.inventoryScroll -command [list $f.inventory yview];$f.inventory configure -yscrollcommand [list $f.inventoryScroll set]
    grid $f.inventory -in $f.split.inventory -row 0 -column 0 -sticky nsew;grid $f.inventoryScroll -in $f.split.inventory -row 0 -column 1 -sticky ns
    grid columnconfigure $f.split.inventory 0 -weight 1;grid rowconfigure $f.split.inventory 0 -weight 1
    text $f.txt -wrap word -font TkFixedFont -state disabled -exportselection 0
    ttk::scrollbar $f.sy -command [list $f.txt yview];$f.txt configure -yscrollcommand [list $f.sy set]
    grid $f.txt -in $f.split.details -row 0 -column 0 -sticky nsew;grid $f.sy -in $f.split.details -row 0 -column 1 -sticky ns
    grid columnconfigure $f.split.details 0 -weight 1;grid rowconfigure $f.split.details 0 -weight 1
    pack $f.split -fill both -expand 1
    ttk::frame $f.pages
    ttk::button $f.pages.previous -text {Previous 500} -command {set ::GX::ResultsView::offset [expr {max(0,$::GX::ResultsView::offset-500)}];::GX::refreshResults}
    ttk::button $f.pages.next -text {Next 500} -command {incr ::GX::ResultsView::offset 500;::GX::refreshResults}
    ttk::label $f.pages.status -textvariable ::GX::ResultsView::status
    pack $f.pages.previous $f.pages.next -side left;pack $f.pages.status -side left -fill x -expand 1;pack $f.pages -fill x
    bind $f.inventory <Double-1> ::GX::resultsOpenFocused
    set ::GX::ui(results) $f.txt
}
proc ::GX::resultsRefresh {} {
    variable ::GX::ResultsView::session;variable ::GX::ResultsView::selected;variable ::GX::ResultsView::offset
    set f .top.nb.results
    if {![winfo exists $f.inventory]} return
    if {$session ne $::GX::currentSession} {
        if {$session ne {}} {dict set selected $session [uiFieldCheckTableGet $f.inventory]}
        set session $::GX::currentSession;set offset 0
        uiFieldCheckTableSet $f.inventory {};set ::GX::ResultsView::records {}
        if {![dict exists $selected $session]} {dict set selected $session {}}
    }
    if {$session eq {}} {set ::GX::ResultsView::records {};resultsRenderInventory;return}
    set epoch [incr ::GX::ResultsView::epoch]
    set command [list [auto_execok tclsh] [file join $::GX::scriptDir core tcl results_inspection_request.tcl] $::GX::scriptDir]
    set payload [dict create session $session offset $offset root [scriptJobRoot]]
    scriptJobAsync $command $payload [list ::GX::resultsInventoryReady $epoch $session] {timeout_ms 30000 max_bytes 8388608 ui_lifetime 1 label {User result inventory}}
}
proc ::GX::resultsInventoryReady {epoch session response} {
    if {$epoch!=$::GX::ResultsView::epoch || $session ne $::GX::currentSession} return
    if {![dict get $response ok]} {set ::GX::ResultsView::status [dict get $response error];return}
    set inventory [dict get $response result];set ::GX::ResultsView::records [dict get $inventory records]
    set ::GX::ResultsView::status "[dict get $inventory total] user results; page [expr {[dict get $inventory offset]+1}]–[expr {[dict get $inventory offset]+[llength $::GX::ResultsView::records]}]. Check independent boxes to display results."
    resultsRenderInventory
}
proc ::GX::resultsRenderInventory {} {
    set f .top.nb.results;set t $f.inventory
    if {![winfo exists $t]} return
    set checked [uiFieldCheckTableGet $t]
    if {[dict exists $::GX::ResultsView::selected $::GX::currentSession]} {set checked [dict get $::GX::ResultsView::selected $::GX::currentSession]}
    $t delete [$t children {}]
    foreach row $::GX::ResultsView::records {
        if {$::GX::ResultsView::category ne {All} && [dict get $row category] ne $::GX::ResultsView::category} continue
        if {$::GX::ResultsView::search ne {} && [string first [string tolower $::GX::ResultsView::search] [string tolower $row]]<0} continue
        $t insert {} end -id [dict get $row id] -values [list [dict get $row name] [dict get $row category] [dict get $row producer] [dict get $row type] [dict get $row state]]
    }
    uiFieldCheckTableSet $t $checked
    resultsRenderChecked
}
proc ::GX::resultsCheckedText {} {
    set text {};set checked [uiFieldCheckTableGet .top.nb.results.inventory]
    foreach row $::GX::ResultsView::records {
        set id [dict get $row id]
        if {$id ni $checked || ![.top.nb.results.inventory exists $id]} continue
        append text "[dict get $row name] — [dict get $row category]\nProducer: [dict get $row producer]\nState: [dict get $row state]\nType: [dict get $row type]\n"
        if {[dict exists $row historical_operation_status]} {append text "[dict get $row historical_operation_status]\n"}
        set summary [dict get $row summary]
        dict for {key value} $summary {append text "$key: [string range $value 0 8191]\n"}
        append text "\n────────────────────────────────────────\n\n"
        if {[string length $text]>262144} {append text {Bounded consultation: narrow your selection for additional details.};break}
    }
    return $text
}
proc ::GX::resultsRenderChecked {} {
    set t .top.nb.results.txt
    dict set ::GX::ResultsView::selected $::GX::currentSession [uiFieldCheckTableGet .top.nb.results.inventory]
    $t configure -state normal;$t delete 1.0 end
    set content [resultsCheckedText]
    append ::GX::ResultsView::status ""
    if {$content eq {}} {set content {No checked visible results. Import data or run an authorized scientific workflow, Refresh, then check results to consult them.}}
    $t insert end $content;$t configure -state disabled
}
proc ::GX::resultsCheckDisplayed {} {set t .top.nb.results.inventory;uiFieldCheckTableSet $t [lsort -unique [concat [uiFieldCheckTableGet $t] [$t children {}]]];resultsRenderChecked}
proc ::GX::resultsClearChecked {} {uiFieldCheckTableSet .top.nb.results.inventory {};resultsRenderChecked}
proc ::GX::resultsCopyChecked {} {set content [resultsCheckedText];if {$content eq {}} {set ::GX::ResultsView::status {No checked visible results to copy.};return};clipboard clear;clipboard append -- $content}
proc ::GX::resultsOpenFocused {} {
    set selected [.top.nb.results.inventory selection];if {$selected eq {}} return
    foreach row $::GX::ResultsView::records {if {[dict get $row id] ne [lindex $selected 0]} continue
        if {[dict exists $row dataset_id]} {datasetViewerOpen [dict get $row dataset_id]} elseif {[dict exists $row job_id]} {scriptJobDetailsWindow [dict get $row job_id] $::GX::currentSession}
        break
    }
}
