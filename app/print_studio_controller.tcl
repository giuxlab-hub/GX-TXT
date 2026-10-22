# SPDX-License-Identifier: GPL-3.0-or-later
# Main Print tab adapter. CORE owns print recipes and derived document requests.
namespace eval ::GX::PrintStudio {variable state;array set state {revision 0 mediaChecking 0 printUnsupported {} outputLabel {No exported PDF yet. Choose Save PDF after reviewing the document.} query {} representation {} sourceStatus {Choose a source to inspect its supported Preview.} documentStatus {Empty composition} currentPage 1 pageCount 0 zoom 1 pageMode fit_page showBrowser 1 logVisible 0 item_columns {} item_start 0 item_count 200 pages {} id {} stamp {} saved {} previewWatch {} selectedSource {} sourceGeneration 0}}
proc ::GX::printStudioInit {} {
    variable ::GX::PrintStudio::state
    if {![info exists state(recipe)]} {set state(recipe) [printRecipePosterNew];set state(history) [printRecipeHistoryCreate $state(recipe)];set state(saved) $state(recipe);set state(session_token) {};catch {set state(session_token) [interactiveDocumentSessionToken]}}
    set state(logVisible) [configurationGet printing.log_visible]
    set ::GX::ui(printStatus) {Add supported content, update the document Preview, then export or print explicitly.}
    set ::GX::ui(cupsStatus) {Printer metadata has not been verified. PDF export is independent.}
    if {![info exists state(catalogSubscription)]} {set state(catalogSubscription) [datasetCatalogSubscribe ::GX::printStudioCatalogChanged]}
}
proc ::GX::printStudioCatalogChanged {receipt} {
    variable ::GX::PrintStudio::state
    if {[dict get $receipt change_kind] eq {session}} {
        printStudioSourceCancel
        if {[info exists ::GX::ui(printSourceCanvas)] && [winfo exists $::GX::ui(printSourceCanvas)]} {printStudioSourceClear}
        set state(selectedSource) {};set state(sourceDescriptor) {};set state(representation) {}
        set state(sourceStatus) {Session changed. Select a source in the current Session.}
    }
    printStudioCatalogSchedule
}
proc ::GX::printStudioScopeActive {} {return [expr {[winfo exists .top.nb.print] && [.top.nb select] eq {.top.nb.print}}]}
proc ::GX::printStudioCommandCatalog {} {
    set result {}
    foreach {id label method key} {
        new {New composition} printStudioNew Ctrl+n open {Open composition} printStudioOpen Ctrl+o save {Save composition} printStudioSave Ctrl+s
        add {Add selected content} printStudioAdd {} legacy {Add selected Graphs} printStudioAddLegacy {}
        remove Remove {printStudioQueueEdit remove} Delete duplicate Duplicate {printStudioQueueEdit duplicate} Ctrl+d
        up {Move up} {printStudioQueueEdit up} {} down {Move down} {printStudioQueueEdit down} {}
        undo Undo {printStudioNavigate undo} Ctrl+z redo Redo {printStudioNavigate redo} Ctrl+y
        preview {Update Preview} printStudioPreview F5 cancel_document {Cancel document operation} printStudioCancel {} export {Save PDF…} exportPdf {} open_pdf {Open PDF} openPrintPdf {}
        print Print printPdf Ctrl+p setup {Page setup} printStudioSetup {}
        job_status {CUPS job status} {printJobAction job_status} {} cancel_job {Cancel submitted job} {printJobAction cancel_job} {}
        fit_page {Fit page} {printStudioView fit_page} {} fit_width {Fit width} {printStudioView fit_width} {}
        zoom_in {Zoom in} {printStudioView zoom_in} {} zoom_out {Zoom out} {printStudioView zoom_out} {}
        previous Previous {printStudioPage -1} {} next Next {printStudioPage 1} {}
        browser {Show / hide browser} printStudioBrowserToggle {} log Diagnostics printStudioLogToggle {}
        help {Print Studio guide} {documentationBrowserOpenApi PRINT_DOCUMENT_API_v1} {}
        heading {Insert heading} {printStudioPosterInsert heading} {} body {Insert body text} {printStudioPosterInsert body} {}
        annotation {Insert annotation} {printStudioPosterInsert annotation} {} block {Insert color block} {printStudioPosterInsert block} {}
        separator {Insert separator} {printStudioPosterInsert separator} {} properties {Object properties…} printStudioPosterProperties {}
        edit_layout {Edit layout} {printStudioPosterReview 0} {} review_pdf {Review PDF} {printStudioPosterReview 1} {}
    } {dict set result $id [dict create label $label default $key method $method]}
    return $result
}
proc ::GX::printStudioInvoke {id} {
    if {[catch {set spec [dict get [printStudioCommandCatalog] $id];{*}[dict get $spec method]} result options]} {set ::GX::ui(printStatus) $result;printDiagnostic $result;return 0}
    return $result
}
proc ::GX::printStudioEnabled {id} {
    variable ::GX::PrintStudio::state
    switch $id {
        add {return [expr {$state(selectedSource) ne {} && !$state(mediaChecking) && [dict exists $state(sourceDescriptor) representations] && [dict get $state(sourceDescriptor) representations] ne {}}]}
        remove - duplicate - up - down {return [expr {[info exists ::GX::ui(printQueue)] && [llength [$::GX::ui(printQueue) selection]]>0}]}
        cancel_document {return [expr {[info exists state(documentRequest)] || [info exists state(exportRequest)]}]}
        preview {return [expr {[llength [dict get $state(recipe) items]]>0}]}
        export - print - open_pdf {return [printStudioDocumentReady]}
        previous {return [expr {$state(currentPage)>1}]}
        next {return [expr {$state(currentPage)<$state(pageCount)}]}
        fit_page - fit_width - zoom_in - zoom_out {return [expr {[printStudioIsPoster] || $state(pageCount)>0}]}
        properties {return [expr {[printStudioIsPoster] && [info exists ::GX::ui(printQueue)] && [winfo exists $::GX::ui(printQueue)] && [llength [$::GX::ui(printQueue) selection]]==1}]}
        heading - body - annotation - block - separator - edit_layout {return [printStudioIsPoster]}
        review_pdf {return [printStudioDocumentReady]}
        job_status - cancel_job {return [expr {$state(job) ne {} && [dict get $state(job) job_id] ne {}}]}
        undo {return [expr {[dict get $state(history) cursor]>0}]}
        redo {return [expr {[dict get $state(history) cursor]<[llength [dict get $state(history) steps]]}]}
    }
    return 1
}
proc ::GX::printStudioPrepare {} {
    variable ::GX::PrintStudio::state
    if {$state(recipe) eq $state(saved)} {return 1}
    set answer [tk_messageBox -parent . -title {Print composition changes} -type yesnocancel -default cancel -icon question -message {Save the current print composition before continuing?}]
    if {$answer eq {cancel}} {return 0}
    if {$answer eq {yes}} {printStudioSave;return [expr {$state(recipe) eq $state(saved)}]}
    return 1
}
proc ::GX::printStudioNew {} {
    variable ::GX::PrintStudio::state
    if {![printStudioPrepare]} return
    printStudioClearDocument
    set state(recipe) [printRecipePosterNew];set state(saved) $state(recipe);set state(history) [printRecipeHistoryCreate $state(recipe)];set state(id) {};set state(stamp) {}
    set state(session_token) {};catch {set state(session_token) [interactiveDocumentSessionToken]}
    printStudioInvalidate {New empty composition};printStudioQueueRefresh
}
proc ::GX::printStudioEdit {recipe description} {
    variable ::GX::PrintStudio::state
    set recipe [printRecipeValidate $recipe]
    if {$recipe eq $state(recipe)} return
    set state(history) [printRecipeHistoryEdit $state(history) $recipe $description];set state(recipe) $recipe
    printStudioInvalidate $description;printStudioQueueRefresh
}
proc ::GX::printStudioInvalidate {reason} {
    variable ::GX::PrintStudio::state
    if {[dict get [printCupsState submission] request] ne {}} {printCupsCancel submission}
    incr state(revision);set state(documentStatus) "Update required — $reason"
    if {[info exists state(documentRequest)]} {printDocumentCancel $state(documentRequest)}
    if {[dict get $state(recipe) items] eq {}} {
        printStudioClearDocument
        set state(documentStatus) {Empty composition — add content to create a document}
    }
    set ::GX::ui(printStatus) $state(documentStatus)
    printStudioPosterAfterEdit
    if {[winfo exists .top.nb.print]} {viewerGuiActionsRefresh .top.nb.print}
}
proc ::GX::printStudioDocumentReady {{verifyNow 0}} {
    variable ::GX::PrintStudio::state
    if {![info exists state(document)] || ![dict exists $state(document) revision] || [dict get $state(document) revision]!=$state(revision)} {return 0}
    if {[catch {interactiveDocumentSessionToken} token] || $token ne [dict get $state(document) session_token]} {set state(documentStatus) {Update required — Session changed};return 0}
    set key [list $state(revision) $token [dict get $state(document) pdf_sha256]]
    if {!$verifyNow && [info exists state(readyCache)] && [dict get $state(readyCache) key] eq $key} {return [dict get $state(readyCache) ready]}
    set ready [file isfile [dict get $state(document) pdf]]
    foreach item [dict get $state(recipe) items] {
        if {[dict get $item source_kind] eq {literal}} continue
        if {[catch {printRecipeSourceSignature [dict get $item source_kind] [dict get $item source_id]} signature] || $signature ne [dict get $item source_signature]} {set state(documentStatus) {Update required — Scientific source changed};set ready 0;break}
    }
    # Menus, toolbar and dock share one source check within this event turn.
    # Explicit Print/Export always force a fresh check and their worker repeats
    # the physical-byte/schema/calibration guards before external publication.
    set state(readyCache) [dict create key $key ready $ready]
    if {![info exists state(readyCacheTimer)]} {set state(readyCacheTimer) [after 0 ::GX::printStudioReadyCacheClear]}
    return $ready
}
proc ::GX::printStudioReadyCacheClear {} {unset -nocomplain ::GX::PrintStudio::state(readyCache) ::GX::PrintStudio::state(readyCacheTimer)}
proc ::GX::printStudioNavigate {direction} {
    variable ::GX::PrintStudio::state
    set cursor [dict get $state(history) cursor];set next [expr {$cursor+($direction eq {undo} ? -1 : 1)}]
    if {$next<0 || $next>[llength [dict get $state(history) steps]]} return
    set state(history) [scientificHistoryNavigate framework.printing $state(history) $next]
    set state(recipe) [scientificHistoryState $state(history)];printStudioInvalidate $direction;printStudioQueueRefresh
}
proc ::GX::printStudioSave {} {
    variable ::GX::PrintStudio::state
    printStudioDocumentSession
    if {![printStudioApplySetup]} {error $::GX::ui(printStatus)}
    set doc [printRecipeDocumentSave $state(recipe) $state(history) $state(id) $state(stamp)]
    set state(id) [dict get $doc id];set state(stamp) [list [dict get $doc generation] [dict get $doc revision] [dict get $doc sha256]];set state(saved) $state(recipe)
    set ::GX::ui(printStatus) "Saved print composition $state(id); scientific sources are unchanged."
    printStudioSavedRefresh
}
proc ::GX::printStudioSavedRefresh {} {
    variable ::GX::PrintStudio::state
    set choices {};set state(savedChoices) {}
    foreach doc [interactiveDocumentList framework.printing print_composition] {
        if {[catch {printRecipeDocumentRead [dict get $doc id]} data]} continue
        set label "[dict get $data payload recipe title] · [dict get $doc id]"
        lappend choices $label;dict set state(savedChoices) $label [dict get $doc id]
    }
    if {[info exists ::GX::ui(printSaved)] && [winfo exists $::GX::ui(printSaved)]} {$::GX::ui(printSaved) configure -values $choices}
}
proc ::GX::printStudioOpen {} {printStudioSavedRefresh;$::GX::ui(printDock) select $::GX::ui(printDocumentTab);focus $::GX::ui(printSaved)}
proc ::GX::printStudioOpenSelected {} {
    variable ::GX::PrintStudio::state
    if {![dict exists $state(savedChoices) $state(savedChoice)]} {error {Choose a saved Session print composition.}}
    if {![printStudioPrepare]} return
    printStudioClearDocument
    set doc [printRecipeDocumentRead [dict get $state(savedChoices) $state(savedChoice)]]
    set state(recipe) [dict get $doc payload recipe];set state(history) [dict get $doc payload history];set state(saved) $state(recipe)
    set state(id) [dict get $doc id];set state(stamp) [list [dict get $doc generation] [dict get $doc revision] [dict get $doc sha256]]
    set state(session_token) [interactiveDocumentSessionToken]
    printStudioInvalidate {Composition reopened; verify current sources};printStudioQueueRefresh
}
proc ::GX::printStudioDocumentSession {} {
    variable ::GX::PrintStudio::state
    set token [interactiveDocumentSessionToken]
    if {$state(session_token) eq {} && [dict get $state(recipe) items] eq {}} {set state(session_token) $token}
    if {$token ne $state(session_token)} {error {This composition belongs to a previous Session. Reopen that Session, or choose New/Open composition for the current Session.}}
    return $token
}
proc ::GX::printStudioApplySetup {args} {
    variable cfg;variable ::GX::PrintStudio::state
    if {[catch {
        if {$state(session_token) ne {} || [dict get $state(recipe) items] ne {}} {printStudioDocumentSession}
        set recipe $state(recipe);dict set recipe title $cfg(print_title)
        foreach {field key} {paper print_page orientation print_orientation rows print_rows columns print_cols margin_mm print_margin_mm gap_mm print_gap_mm captions print_captions} {dict set recipe page $field $cfg($key)}
        dict set recipe page layout_mode $state(layout_mode);dict set recipe page background $state(page_background)
        if {$state(layout_mode) eq {poster}} {
            set placed {};set initial $recipe;dict set initial items {}
            foreach item [dict get $recipe items] {if {![dict exists $item frame]} {dict set item frame [printStudioPosterFrame $initial]};lappend placed $item;dict lappend initial items $item}
            dict set recipe items $placed
        }
        printStudioEdit $recipe {Page setup changed}
    } message]} {printStudioInvalidate {Invalid page settings};set ::GX::ui(printStatus) $message;return 0}
    return 1
}
proc ::GX::printStudioQueueRefresh {} {
    variable ::GX::PrintStudio::state
    if {![info exists ::GX::ui(printQueue)] || ![winfo exists $::GX::ui(printQueue)]} return
    foreach {field key} {paper print_page orientation print_orientation rows print_rows columns print_cols margin_mm print_margin_mm gap_mm print_gap_mm captions print_captions} {set ::GX::cfg($key) [dict get $state(recipe) page $field]}
    set ::GX::cfg(print_title) [dict get $state(recipe) title]
    set state(layout_mode) [datasetPublicationV2DictDefault [dict get $state(recipe) page] layout_mode grid]
    set state(page_background) [datasetPublicationV2DictDefault [dict get $state(recipe) page] background #ffffff]
    set tree $::GX::ui(printQueue);set selected [$tree selection];$tree delete [$tree children {}]
    foreach item [dict get $state(recipe) items] {$tree insert {} end -id [dict get $item id] -text [printRecipeItemLabel $item] -values [list [dict get $item presentation] [expr {[dict get $item source_kind] eq {literal} ? {Document} : [dict get $item source_id]}]]}
    foreach id $selected {if {[$tree exists $id]} {$tree selection add $id}}
    viewerGuiActionsRefresh .top.nb.print
}
proc ::GX::printStudioQueueEdit {operation} {
    variable ::GX::PrintStudio::state
    set ids [$::GX::ui(printQueue) selection];if {$ids eq {}} {error {Select composition items first.}}
    set items [dict get $state(recipe) items];set result {}
    switch $operation {
        remove {foreach item $items {if {[dict get $item id] ni $ids} {lappend result $item}}}
        duplicate {foreach item $items {lappend result $item;if {[dict get $item id] in $ids} {dict set item id print_[clock microseconds];lappend result $item}}}
        up - down {
            set result $items;set first [lindex $ids 0];set at -1
            for {set n 0} {$n<[llength $items]} {incr n} {if {[dict get [lindex $items $n] id] eq $first} {set at $n;break}}
            set next [expr {$at+($operation eq {up} ? -1 : 1)}]
            if {$at>=0 && $next>=0 && $next<[llength $items]} {set other [lindex $items $next];lset result $next [lindex $items $at];lset result $at $other}
        }
    }
    set recipe $state(recipe);dict set recipe items $result;printStudioEdit $recipe "Composition $operation"
}
proc ::GX::printStudioSetup {} {$::GX::ui(printDock) select $::GX::ui(printSetupTab);focus $::GX::ui(printPaper)}
proc ::GX::printStudioLogToggle {} {
    variable ::GX::PrintStudio::state
    set state(logVisible) [expr {!$state(logVisible)}];set pane .top.nb.print.vertical
    if {$state(logVisible)} {if {{.top.nb.print.vertical.logs} ni [$pane panes]} {$pane add $pane.logs -weight 0}} elseif {{.top.nb.print.vertical.logs} in [$pane panes]} {$pane forget $pane.logs}
    configurationSet printing.log_visible $state(logVisible);configurationSave printing.log_visible 0
    if {$state(logVisible)} {after 50 ::GX::printStudioRestoreLogHeight}
}
proc ::GX::printStudioBrowserToggle {} {
    variable ::GX::PrintStudio::state
    set pane .top.nb.print.vertical.main;set state(showBrowser) [expr {!$state(showBrowser)}]
    if {$state(showBrowser)} {$pane add $pane.dock -weight 0} else {$pane forget $pane.dock}
}
proc ::GX::printStudioCatalogSchedule {args} {
    variable ::GX::PrintStudio::state
    if {[info exists state(catalogTimer)]} {after cancel $state(catalogTimer)}
    set state(catalogTimer) [after 150 ::GX::printStudioCatalogRefresh]
}
proc ::GX::printStudioCatalogRefresh {{refreshGraphCatalog 0}} {
    variable ::GX::PrintStudio::state;variable ui;variable currentSession
    if {![info exists ui(printContentTree)] || ![winfo exists $ui(printContentTree)]} return
    # Rebind the public subscription to the current catalog Session token.
    if {[info exists state(catalogSubscription)]} {datasetCatalogUnsubscribe $state(catalogSubscription)}
    set state(catalogSubscription) [datasetCatalogSubscribe ::GX::printStudioCatalogChanged]
    if {$refreshGraphCatalog} {refreshGraphs}
    set tree $ui(printContentTree);set selected [$tree selection];$tree delete [$tree children {}];set state(contentRows) {}
    if {$currentSession eq {}} {set state(sourceStatus) {Open a Session to browse scientific content.};return}
    set query [string tolower [string trim $state(query)]]
    foreach row [dict get [datasetCatalogSnapshot] datasets] {
        set id [dict get $row dataset_id];set title [dict get $row display_name];if {$title eq {}} {set title $id}
        set namespace [dict get $row namespace];if {$namespace eq {}} {set namespace Ungrouped}
        if {$query ne {} && [string first $query [string tolower "$id $title $namespace [dict get $row kind]"]]<0} continue
        set parent ns:[binary encode hex [encoding convertto utf-8 $namespace]]
        if {![$tree exists $parent]} {$tree insert {} end -id $parent -text "Datasets · $namespace" -open 1}
        set node dataset:$id;$tree insert $parent end -id $node -text $title -values [list [dict get $row kind]]
        dict set state(contentRows) $node [dict create kind dataset id $id]
    }
    foreach graph [graphBrowserCatalog] {
        set relative [dict get $graph relative_path];set title [dict get $graph title]
        if {$query ne {} && [string first $query [string tolower "$relative $title Graph"]]<0} continue
        if {![$tree exists graphs]} {$tree insert {} end -id graphs -text {Published Graphs} -open 1}
        set node graph:[binary encode hex [encoding convertto utf-8 $relative]]
        $tree insert graphs end -id $node -text $title -values Graph
        dict set state(contentRows) $node [dict create kind graph id $relative]
    }
    foreach node $selected {if {[$tree exists $node]} {$tree selection set $node}}
    viewerGuiActionsRefresh .top.nb.print
}
proc ::GX::printStudioSourceCancel {} {
    variable ::GX::PrintStudio::state
    if {$state(previewWatch) ne {}} {datasetPreviewCacheUnsubscribe [dict get $state(previewWatch) ticket];set state(previewWatch) {}}
    foreach request {sourceRequest sourceMediaRequest} {if {[info exists state($request)]} {printDocumentCancel $state($request)}}
    if {[info exists state(sourceReceipt)]} {printDocumentRelease [dict get $state(sourceReceipt) resource_id];unset state(sourceReceipt)}
    set state(mediaChecking) 0
    incr state(sourceGeneration)
}
proc ::GX::printStudioSourceSelect {} {
    variable ::GX::PrintStudio::state;variable ui
    set node [lindex [$ui(printContentTree) selection] 0]
    if {![dict exists $state(contentRows) $node]} return
    printStudioSourceCancel
    set state(selectedSource) [dict get $state(contentRows) $node]
    if {[catch {
        set state(sourceToken) [interactiveDocumentSessionToken]
        set descriptor [printContentDescribe [dict get $state(selectedSource) kind] [dict get $state(selectedSource) id]]
    } message]} {
        set state(selectedSource) {};set state(sourceDescriptor) {};set state(representation) {}
        set state(sourceStatus) "Source unavailable: $message";printStudioCatalogSchedule
        viewerGuiActionsRefresh .top.nb.print;return
    }
    set state(sourceDescriptor) $descriptor;set state(representation) [dict get $descriptor default];set state(printUnsupported) {}
    if {[dict get $descriptor default] eq {image}} {
        set state(mediaChecking) 1
        set state(sourceMediaRequest) [printDocumentMediaInfo [dict get $state(selectedSource) id] [list ::GX::printStudioMediaInfoPrepared $state(sourceGeneration)]]
    }
    $ui(printRepresentation) configure -values [dict get $descriptor representations]
    set text $ui(printSourceSummary);$text configure -state normal;$text delete 1.0 end
    $text insert end "[dict get $descriptor title]\nSource: [dict get $descriptor source_id]\nKind: [dict get $descriptor kind]\n"
    if {[dict exists $descriptor variables]} {foreach variable [dict get $descriptor variables] {$text insert end "[dict get $variable variable_id] · [dict get $variable unit]\n"}}
    if {[dict get $descriptor reason] ne {}} {$text insert end "[dict get $descriptor reason]\n"}
    $text configure -state disabled
    printStudioSourceClear
    if {[dict get $state(selectedSource) kind] eq {dataset} && $state(representation) eq {table}} {
        printStudioSourceTable [dict get $state(selectedSource) id] [dict create variables [lrange [dict get $descriptor table_variables] 0 63]]
    } elseif {[dict get $state(selectedSource) kind] eq {dataset}} {
        set state(sourceStatus) {Preparing a bounded source Preview…}
        set state(previewWatch) [datasetPreviewCacheSubscribe [dict get $state(selectedSource) id] {} [list ::GX::printStudioSourcePrepared $state(sourceGeneration) [dict get $state(selectedSource) id]]]
    } else {
        set state(sourceStatus) {Graph artwork selected. This source Preview is separate from assembled PDF pages.}
        if {[llength [info commands ::GX::printDocumentSourcePreview]]} {set state(sourceRequest) [printDocumentSourcePreview [dict get $state(selectedSource) id] [list ::GX::printStudioGraphPreviewPrepared $state(sourceGeneration)]]}
    }
    viewerGuiActionsRefresh .top.nb.print
}
proc ::GX::printStudioSourcePrepared {generation id response} {
    variable ::GX::PrintStudio::state;variable ui
    if {![printStudioSourceCurrent $generation] || ![winfo exists $ui(printSourceCanvas)]} return
    if {[dict get $response status] eq {preparing}} {set state(sourceStatus) "Source Preview: [dict get $response state]";return}
    set state(previewWatch) {}
    if {[dict get $response status] ne {ready}} {set state(sourceStatus) "Source Preview unavailable: [datasetPublicationV2DictDefault $response message error]";return}
    set key [dict get $response key];set cached [datasetPreviewCacheRead $id $key]
    if {$cached eq {}} {set state(sourceStatus) {Source changed; select it again to request a current Preview.};return}
    set artifact {}
    if {[dict exists $cached media_artifact path]} {set artifact [dict get $cached media_artifact path]}
    set standard [file join [datasetPreviewCachePath $::GX::currentSession $key] standard.png]
    if {[dict exists $cached artifacts standard.png] && [file isfile $standard]} {set artifact $standard}
    if {$artifact ne {}} {printStudioSourceImage $artifact}
    set hit [datasetPublicationV2DictDefault $response cache_hit 0]
    set state(sourceStatus) "Source Preview · cache [expr {$hit ? {HIT} : {MISS → prepared}}]. Print uses the original scientific source."
    if {[dict exists $cached description]} {append state(sourceStatus) " [dict get $cached description]"}
    if {$state(printUnsupported) ne {}} {append state(sourceStatus) " $state(printUnsupported)"}
    if {[dict exists $cached table_page]} {printStudioSourceTableSnapshot [dict get $cached table_page]}
}
proc ::GX::printStudioSourceClear {} {
    unset -nocomplain ::GX::PrintStudio::state(sourceTableKey)
    set canvas $::GX::ui(printSourceCanvas)
    $canvas delete all
    foreach child [winfo children $canvas] {destroy $child}
}
proc ::GX::printStudioSourceTableSnapshot {snapshot} {
    variable ui
    printStudioSourceClear
    set canvas $ui(printSourceCanvas);set frame $canvas.table
    ttk::frame $frame
    text $frame.text -height 8 -width 30 -wrap none -font TkFixedFont -borderwidth 0
    ttk::scrollbar $frame.y -command [list $frame.text yview]
    ttk::scrollbar $frame.x -orient horizontal -command [list $frame.text xview]
    $frame.text configure -yscrollcommand [list $frame.y set] -xscrollcommand [list $frame.x set]
    grid $frame.text -row 0 -column 0 -sticky nsew
    grid $frame.y -row 0 -column 1 -sticky ns
    grid $frame.x -row 1 -column 0 -sticky ew
    grid columnconfigure $frame 0 -weight 1;grid rowconfigure $frame 0 -weight 1
    datasetPreviewRenderTableSnapshot $frame.text $snapshot
    $frame.text configure -state disabled
    $canvas create window 0 0 -anchor nw -window $frame -tags table_preview -width [winfo width $canvas] -height [winfo height $canvas]
    bind $canvas <Configure> [list $canvas itemconfigure table_preview -width %w -height %h]
}
proc ::GX::printStudioSourceTable {id options {expected {}}} {
    variable ::GX::PrintStudio::state
    try {
        set token [interactiveDocumentSessionToken]
        set signature [printRecipeSourceSignature dataset $id]
        if {$expected ne {} && $signature ne $expected} {error {Table source changed; update the composition source before previewing.}}
        set key [list $token $id $signature $options]
        if {[info exists state(sourceTableKey)] && $state(sourceTableKey) eq $key && [winfo exists $::GX::ui(printSourceCanvas).table]} {return}
        printStudioSourceClear
        set start [datasetPublicationV2DictDefault $options start 0]
        set count [datasetPublicationV2DictDefault $options count 200]
        set page [datasetPreviewPage $::GX::currentSession $id [dict create start $start count [expr {min(12,$count)}] variable_ids [datasetPublicationV2DictDefault $options variables {}]]]
        if {$token ne [interactiveDocumentSessionToken] || $signature ne [printRecipeSourceSignature dataset $id]} {error {Table source or Session changed during Preview.}}
        if {![dict get $page available]} {error [dict get $page reason]}
        printStudioSourceTableSnapshot $page
        set state(sourceTableKey) $key
        set state(sourceStatus) "Table $id · first [dict get $page count] row(s) of the display range; zero-based start $start, requested count $count. Preview row labels are relative to this sample. Source data are unchanged."
    } on error {message errorOptions} {printStudioSourceClear;set state(sourceStatus) "Table Preview unavailable: $message"}
}
proc ::GX::printStudioTableRangeOptions {options start count} {
    # Empty fields omit the existing optional keys. Materialization retains
    # the established first-200-row default; no new Dataset range semantics.
    foreach key {start count} value [list $start $count] {
        set value [string trim $value]
        dict unset options $key
        if {$value ne {}} {dict set options $key $value}
    }
    return $options
}
proc ::GX::printStudioSourceImage {path} {
    variable ::GX::PrintStudio::state;variable ui
    set canvas $ui(printSourceCanvas);printStudioSourceClear
    if {[info exists state(sourcePhoto)]} {catch {image delete $state(sourcePhoto)}}
    if {[catch {set master [image create photo -file $path]} message]} {set state(sourceStatus) "Inline source Preview unavailable: $message";return}
    set factor [expr {max(1,int(ceil(max([image width $master]/double(max(100,[winfo width $canvas]-10)),[image height $master]/double(max(100,[winfo height $canvas]-10))))))}]
    set state(sourcePhoto) [image create photo];$state(sourcePhoto) copy $master -subsample $factor $factor;image delete $master
    $canvas create image [expr {[winfo width $canvas]/2}] [expr {[winfo height $canvas]/2}] -anchor center -image $state(sourcePhoto)
}
proc ::GX::printStudioGraphPreviewPrepared {generation response} {
    variable ::GX::PrintStudio::state
    if {![printStudioSourceCurrent $generation]} {if {[dict get $response ok]} {printDocumentRelease [dict get $response result resource_id]};return}
    unset -nocomplain state(sourceRequest)
    if {![dict get $response ok]} {set state(sourceStatus) [dict get $response error];return}
    if {[info exists state(sourceReceipt)]} {printDocumentRelease [dict get $state(sourceReceipt) resource_id]}
    set state(sourceReceipt) [dict get $response result]
    printStudioSourceImage [dict get $response result path]
}
proc ::GX::printStudioAdd {} {
    variable ::GX::PrintStudio::state
    printStudioDocumentSession
    if {$state(selectedSource) eq {}} {error {Choose supported Session content first.}}
    if {$state(mediaChecking) || ![printStudioSourceCurrent $state(sourceGeneration)]} {error {Source validation is pending or the Session changed. Select the source again.}}
    set source $state(selectedSource);set descriptor [printContentDescribe [dict get $source kind] [dict get $source id]]
    if {$state(representation) ni [dict get $descriptor representations] || $state(representation) ni [dict get $state(sourceDescriptor) representations]} {error {Choose an actually supported print representation.}}
    set options {}
    if {[dict get $source kind] eq {dataset}} {
        set variables [lrange [dict get $descriptor table_variables] 0 63]
        if {$state(representation) eq {table}} {set count [dict get $descriptor row_count];if {![string is integer -strict $count] || $count<1} {set count 200};set options [dict create variables $variables start 0 count [expr {min(200,$count)}]]}
        if {$state(representation) eq {xy}} {set numeric [dict get $descriptor xy_variables];set options [dict create x_variable_id [lindex $numeric 0] y_variable_id [lindex $numeric 1]]}
    }
    set item [dict create id print_[clock microseconds] source_kind [dict get $source kind] source_id [dict get $source id] presentation $state(representation) source_signature [printRecipeSourceSignature [dict get $source kind] [dict get $source id]] options $options caption [dict get $descriptor title]]
    if {[printStudioIsPoster]} {dict set item frame [printStudioPosterFrame $state(recipe)];set state(currentPage) [dict get $item frame page];set state(posterSelection) [dict get $item id]}
    set recipe $state(recipe);dict lappend recipe items $item;printStudioEdit $recipe {Content added}
    if {[printStudioIsPoster]} {$::GX::ui(printQueue) selection set [dict get $item id];printStudioItemSelected}
}
proc ::GX::printStudioAddLegacy {} {
    variable ::GX::PrintStudio::state
    printStudioDocumentSession
    set paths [selectedGraphPaths_annotation_base]
    if {$paths eq {}} {error {Select Graphs in the existing Plots page first.}}
    set recipe $state(recipe)
    foreach path $paths {
        set relative [string range [file normalize $path] [expr {[string length [file normalize $::GX::currentSession]]+1}] end]
        set descriptor [printContentDescribe graph $relative]
        set item [dict create id print_[clock microseconds] source_kind graph source_id $relative presentation graph source_signature [printRecipeSourceSignature graph $relative] options {} caption [dict get $descriptor title]]
        if {[printStudioIsPoster]} {dict set item frame [printStudioPosterFrame $recipe]}
        dict lappend recipe items $item
    }
    printStudioEdit $recipe {Selected legacy Graphs added}
}
proc ::GX::printStudioItemSelected {} {
    variable ::GX::PrintStudio::state
    set id [lindex [$::GX::ui(printQueue) selection] 0]
    set state(posterSelection) $id
    foreach item [dict get $state(recipe) items] {
        if {[dict get $item id] ne $id} continue
        set options [dict get $item options]
        set state(item_columns) [join [datasetPublicationV2DictDefault $options variables {}] ,]
        set state(item_start) [datasetPublicationV2DictDefault $options start {}]
        set state(item_count) [datasetPublicationV2DictDefault $options count {}]
        if {[dict get $item presentation] eq {table}} {
            printStudioSourceCancel
            printStudioSourceTable [dict get $item source_id] $options [dict get $item source_signature]
        }
    }
    if {[printStudioIsPoster]} {printStudioPosterDraw}
}
proc ::GX::printStudioItemApply {} {
    variable ::GX::PrintStudio::state
    if {[catch {
        set selected [$::GX::ui(printQueue) selection];set items {}
        foreach item [dict get $state(recipe) items] {
            if {[dict get $item id] in $selected && [dict get $item presentation] eq {table}} {
                set variables {};foreach value [split $state(item_columns) ,] {set value [string trim $value];if {$value ne {}} {lappend variables $value}}
                if {$variables eq {}} {error {Choose at least one table Variable ID.}}
                dict set item options [printStudioTableRangeOptions [dict create variables $variables] $state(item_start) $state(item_count)]
            }
            lappend items $item
        }
        set recipe $state(recipe);dict set recipe items $items;printStudioEdit $recipe {Print table selection changed}
    } message]} {set ::GX::ui(printStatus) $message}
}
proc ::GX::printStudioPage {delta} {set ::GX::PrintStudio::state(currentPage) [expr {max(1,min($::GX::PrintStudio::state(pageCount),$::GX::PrintStudio::state(currentPage)+$delta))}];printStudioPageShow}
proc ::GX::printStudioPageSelected {} {set id [lindex [$::GX::ui(printPages) selection] 0];if {[regexp {^page:([0-9]+)$} $id -> page]} {set ::GX::PrintStudio::state(currentPage) $page;printStudioPageShow}}
proc ::GX::printStudioView {mode} {
    variable ::GX::PrintStudio::state
    if {$mode in {zoom_in zoom_out}} {set state(pageMode) zoom;set state(zoom) [expr {max(.25,min(3.0,$state(zoom)*($mode eq {zoom_in} ? 1.25 : .8)))}]} else {set state(pageMode) $mode}
    printStudioPageShow
}
proc ::GX::printStudioPageResize {args} {
    variable ::GX::PrintStudio::state
    if {[info exists state(pageTimer)]} {after cancel $state(pageTimer)}
    set state(pageTimer) [after 100 ::GX::printStudioPageShow]
}
proc ::GX::printStudioPageShow {} {
    variable ::GX::PrintStudio::state
    if {[printStudioIsPoster] && !$state(posterReview)} {printStudioPosterDraw}
    if {$state(pageCount)<1 || ![info exists state(document)]} return
    if {[printStudioIsPoster] && $state(currentPage)>[dict get $state(document) page_count]} return
    printStudioPageRequest
}

proc ::GX::printStudioCancel {} {
    variable ::GX::PrintStudio::state
    foreach key {documentRequest exportRequest} {if {[info exists state($key)]} {printDocumentCancel $state($key)}}
    set ::GX::ui(printStatus) {Cancelling owned print document operation…}
}
proc ::GX::printStudioPreview {} {
    variable ::GX::PrintStudio::state
    set token [printStudioDocumentSession];if {![printStudioApplySetup]} {error $::GX::ui(printStatus)}
    if {[info exists state(documentRequest)]} {error {A document request is pending; cancel it or wait for its receipt.}}
    set recipe $state(recipe);set items {}
    foreach item [dict get $recipe items] {
        # Update Preview explicitly accepts current sources, then freezes them.
        if {[dict get $item source_kind] ne {literal}} {dict set item source_signature [printRecipeSourceSignature [dict get $item source_kind] [dict get $item source_id]]}
        lappend items $item
    }
    if {$items eq {}} {error {Add supported scientific content first.}}
    dict set recipe items $items
    printStudioEdit $recipe {Current source identities accepted for Preview}
    set state(documentStatus) {Freezing scientific sources and assembling PDF…}
    set ::GX::ui(printStatus) $state(documentStatus)
    set arguments [dict create session $::GX::currentSession payload [dict create recipe $recipe nodes [printStudioSourceNodes $recipe]]]
    set state(documentRequest) [printDocumentRequest compose $arguments [list ::GX::printStudioDocumentPrepared $state(revision) $token]]
    viewerGuiActionsRefresh .top.nb.print
}
proc ::GX::printStudioDocumentPrepared {revision token response} {
    variable ::GX::PrintStudio::state
    unset -nocomplain state(documentRequest)
    if {$revision!=$state(revision) || [catch {interactiveDocumentSessionToken} current] || $current ne $token} {if {[dict get $response ok]} {printDocumentRelease [dict get $response result resource_id]};return}
    if {![dict get $response ok]} {set state(documentStatus) "Document unavailable: [dict get $response error]";set ::GX::ui(printStatus) $state(documentStatus);printDiagnostic $state(documentStatus);viewerGuiActionsRefresh .top.nb.print;return}
    set document [dict get $response result]
    if {$revision!=$state(revision) || [catch {interactiveDocumentSessionToken} current] || $current ne $token} {printDocumentRelease [dict get $document resource_id];return}
    foreach key {pageRequest thumbnailRequest} {if {[info exists state($key)]} {printDocumentCancel $state($key)}}
    foreach key {document pageReceipt thumbnailReceipt} {if {[info exists state($key)]} {printDocumentRelease [dict get $state($key) resource_id];unset state($key)}}
    foreach key [array names state thumb,*] {catch {image delete $state($key)};unset state($key)}
    dict set document revision $revision;dict set document session_token $token
    dict set document recipe $state(recipe)
    set state(document) $document;set state(pageCount) [dict get $document page_count];set state(currentPage) 1
    set state(documentStatus) "Current PDF · $state(pageCount) pages"
    set notices {};foreach notice [dict get $document notices] {lappend notices "[dict get $notice message] ([dict get $notice effective_ppi] PPI)"}
    set ::GX::ui(printStatus) "Validated PDF ready. Review its pages, then Save PDF or Print explicitly. [join $notices {; }]"
    set ::GX::cfg(print_output_pdf) [dict get $document pdf]
    set tree $::GX::ui(printPages);$tree delete [$tree children {}]
    for {set n 1} {$n<=$state(pageCount)} {incr n} {$tree insert {} end -id page:$n -text "Page $n"}
    $::GX::ui(printPageNumber) configure -to $state(pageCount)
    printStudioPageRequest
    set state(thumbnailRequest) [printDocumentRequest thumbnails [printStudioDocumentArguments] [list ::GX::printStudioThumbnailsPrepared $revision]]
    viewerGuiActionsRefresh .top.nb.print
}
proc ::GX::printStudioDocumentArguments {} {
    variable ::GX::PrintStudio::state
    set arguments [dict create source_resource [dict get $state(document) resource_id]]
    foreach key {pdf pdf_sha256 source_manifest page_count} {dict set arguments $key [dict get $state(document) $key]}
    return $arguments
}
proc ::GX::printStudioPagePixelWidth {canvas widthPt heightPt} {
    variable ::GX::PrintStudio::state
    set width [expr {max(200,[winfo width $canvas]-32)}]
    set ratio [expr {double($widthPt)/$heightPt}]
    if {$state(pageMode) eq {fit_page}} {set width [expr {int(min($width,max(200,[winfo height $canvas]-32)*$ratio))}]}
    if {$state(pageMode) eq {zoom}} {set width [expr {int($widthPt*96/72*$state(zoom))}]}
    return [expr {max(200,min(3000,$width))}]
}
proc ::GX::printStudioPageRequest {} {
    variable ::GX::PrintStudio::state;variable ui
    if {![info exists state(document)] || ![winfo exists $ui(printPageCanvas)]} return
    if {![string is integer -strict $state(currentPage)] || $state(currentPage)<1 || $state(currentPage)>$state(pageCount)} {set state(currentPage) 1}
    set canvas $ui(printPageCanvas)
    set dimensions [lindex [dict get $state(document) pages] [expr {$state(currentPage)-1}]]
    set width [printStudioPagePixelWidth $canvas [dict get $dimensions width_pt] [dict get $dimensions height_pt]]
    set key [list [dict get $state(document) pdf_sha256] $state(currentPage) $width]
    if {[info exists state(pageKey)] && $state(pageKey) eq $key} return
    set state(pageKey) $key
    if {[info exists state(pageRequest)]} {set state(pagePending) 1;printDocumentCancel $state(pageRequest);return}
    set state(pagePending) 0
    set arguments [dict merge [printStudioDocumentArguments] [dict create page $state(currentPage) width $width]]
    set state(pageRequest) [printDocumentRequest page $arguments [list ::GX::printStudioPagePrepared $key]]
}
proc ::GX::printStudioPagePrepared {key response} {
    variable ::GX::PrintStudio::state;variable ui
    unset -nocomplain state(pageRequest)
    if {![info exists state(document)] || ![info exists state(pageKey)]} {if {[dict get $response ok]} {printDocumentRelease [dict get $response result resource_id]};return}
    if {[info exists state(pagePending)] && $state(pagePending)} {
        if {[dict get $response ok]} {printDocumentRelease [dict get $response result resource_id]}
        unset -nocomplain state(pageKey);printStudioPageRequest;return
    }
    if {![dict get $response ok]} {if {$key eq $state(pageKey)} {set state(documentStatus) "Page Preview unavailable: [dict get $response error]"};return}
    set result [dict get $response result]
    if {$key ne $state(pageKey) || ![info exists state(document)] || [dict get $result pdf_sha256] ne [dict get $state(document) pdf_sha256]} {printDocumentRelease [dict get $result resource_id];return}
    if {[info exists state(pageReceipt)]} {printDocumentRelease [dict get $state(pageReceipt) resource_id]}
    set state(pageReceipt) $result
    if {[info exists state(pagePhoto)]} {catch {image delete $state(pagePhoto)}}
    set state(pagePhoto) [image create photo -file [dict get $result path]]
    if {[printStudioIsPoster] && !$state(posterReview)} {
        printStudioPosterPhotos $result;printStudioPosterDraw
        $ui(printPages) selection set page:$state(currentPage)
        viewerGuiActionsRefresh .top.nb.print
        return
    }
    set canvas $ui(printPageCanvas);$canvas delete all
    set width [dict get $result width];set height [dict get $result height]
    set left [expr {max(16,([winfo width $canvas]-$width)/2)}]
    $canvas create rectangle [expr {$left+5}] 21 [expr {$left+$width+5}] [expr {$height+21}] -fill #39414a -outline {}
    $canvas create image $left 16 -anchor nw -image $state(pagePhoto)
    $canvas configure -scrollregion [list 0 0 [expr {max([winfo width $canvas],$left+$width+16)}] [expr {$height+32}]]
    $canvas xview moveto 0;$canvas yview moveto 0
    $ui(printPages) selection set page:$state(currentPage);$ui(printPages) see page:$state(currentPage)
    viewerGuiActionsRefresh .top.nb.print
}
proc ::GX::printStudioThumbnailsPrepared {revision response} {
    variable ::GX::PrintStudio::state;variable ui
    unset -nocomplain state(thumbnailRequest)
    if {![dict get $response ok]} {printDiagnostic "Page thumbnails: [dict get $response error]";return}
    set result [dict get $response result]
    if {![info exists state(document)] || $revision!=[dict get $state(document) revision]} {printDocumentRelease [dict get $result resource_id];return}
    set state(thumbnailReceipt) $result;set n 0
    foreach path [dict get $result paths] {
        incr n;set state(thumb,$n) [image create photo -file $path]
        $ui(printPages) item page:$n -image $state(thumb,$n)
    }
}
proc ::GX::printStudioExport {} {
    variable ::GX::PrintStudio::state
    if {![printStudioDocumentReady 1]} {error {Document is stale or absent. Update and review its Preview first.}}
    set destination [workspaceSaveFile export_dir -parent . -title {Save reviewed scientific PDF} -initialfile GXTXT_scientific.pdf -defaultextension .pdf -filetypes {{{PDF document} {.pdf}}}]
    if {$destination eq {}} return
    if {[info exists state(exportRequest)]} {error {An export is pending.}}
    set arguments [dict merge [printStudioDocumentArguments] [dict create destination [file normalize $destination] session $::GX::currentSession replace [file exists $destination]]]
    set state(exportRequest) [printDocumentRequest export $arguments ::GX::printStudioExported]
    set ::GX::ui(printStatus) {Verifying scientific sources and publishing the reviewed PDF…}
}
proc ::GX::printStudioExported {response} {
    variable ::GX::PrintStudio::state
    unset -nocomplain state(exportRequest)
    if {![dict get $response ok]} {set ::GX::ui(printStatus) "PDF export failed: [dict get $response error]";return}
    set result [dict get $response result];printDocumentRelease [dict get $result resource_id]
    resourceManagementAsync observe [list path [dict get $result path] subsystem printing category protected_authoritative lifetime user_export] ::GX::_printDocumentCleanupDone
    set state(outputLabel) [dict get $result path]
    set ::GX::ui(printStatus) "PDF saved: [dict get $result path] · SHA [dict get $result pdf_sha256]"
}

proc ::GX::printStudioSourceNodes {recipe} {
    set selected {}
    foreach item [dict get $recipe items] {
        if {[dict get $item source_kind] eq {literal}} continue
        if {[dict get $item source_kind] eq {dataset}} {set ids [list [dict get $item source_id]]} else {set ids [dict keys [lindex [dict get $item source_signature] 8]]}
        foreach id $ids {if {[datasetProviderFor $id] eq {remote}} {set node [datasetField $id remote_node_id];set nodes [scientificExecutionNodes];if {![dict exists $nodes $node]} {error {Remote source node configuration is unavailable.}};dict set selected $node [dict get $nodes $node]}}
    }
    return $selected
}

proc ::GX::printStudioRememberSplit {} {
    set main .top.nb.print.vertical.main;set vertical .top.nb.print.vertical
    if {![winfo exists $main]} return
    set fields {}
    if {[llength [$main panes]]==2} {configurationSet printing.dock_width [expr {max(200,min(900,[winfo width $main]-[$main sashpos 0]))}];lappend fields printing.dock_width}
    if {[llength [$vertical panes]]==2} {configurationSet printing.log_height [expr {max(40,min(600,[winfo height $vertical]-[$vertical sashpos 0]))}];lappend fields printing.log_height}
    if {$fields ne {}} {configurationSave $fields 0}
}
proc ::GX::printStudioRestoreLogHeight {} {
    set pane .top.nb.print.vertical
    if {[winfo exists $pane] && [llength [$pane panes]]==2} {$pane sashpos 0 [expr {max(200,[winfo height $pane]-[configurationGet printing.log_height])}]}
}
proc ::GX::printStudioLogMapped {widget} {
    if {$widget eq {.top.nb.print.vertical}} {after 50 ::GX::printStudioRestoreLogHeight}
}
proc ::GX::printStudioClearDocument {} {
    variable ::GX::PrintStudio::state;variable ui
    foreach key {documentRequest pageRequest thumbnailRequest objectRequest} {if {[info exists state($key)]} {printDocumentCancel $state($key)}}
    foreach key {document pageReceipt thumbnailReceipt} {if {[info exists state($key)]} {printDocumentRelease [dict get $state($key) resource_id];unset state($key)}}
    foreach key [array names state thumb,*] {catch {image delete $state($key)};unset state($key)}
    if {[info exists state(pagePhoto)]} {catch {image delete $state(pagePhoto)};unset state(pagePhoto)}
    foreach key [array names state objectPhoto,*] {catch {image delete $state($key)};unset state($key)}
    foreach key [array names state objectContent,*] {unset state($key)}
    if {[info exists state(objectTimer)]} {after cancel $state(objectTimer)}
    unset -nocomplain state(objectTimer) state(objectKey) state(objectPending) state(objectProjection)
    set state(posterSelection) {};set state(posterGesture) {};set state(posterReview) 0
    if {[winfo exists .gxPrintObjectProperties]} {destroy .gxPrintObjectProperties}
    unset -nocomplain state(pageKey);set state(pageCount) 0;set state(currentPage) 1;set ::GX::cfg(print_output_pdf) {}
    if {[info exists ui(printPages)] && [winfo exists $ui(printPages)]} {$ui(printPages) delete [$ui(printPages) children {}]}
    if {[info exists ui(printPageCanvas)] && [winfo exists $ui(printPageCanvas)]} {$ui(printPageCanvas) delete all;$ui(printPageCanvas) create text 30 30 -anchor nw -fill white -text {No assembled document. Add content, then Update Preview.}}
}

proc ::GX::printStudioMediaInfoPrepared {generation response} {
    variable ::GX::PrintStudio::state;variable ui
    if {![printStudioSourceCurrent $generation]} {if {[dict get $response ok]} {printDocumentRelease [dict get $response result resource_id]};return}
    unset -nocomplain state(sourceMediaRequest);set state(mediaChecking) 0
    if {![dict get $response ok]} {
        set state(printUnsupported) [dict get $response error]
        dict set state(sourceDescriptor) representations {};set state(representation) {}
        $ui(printRepresentation) configure -values {}
    } else {
        set result [dict get $response result];printDocumentRelease [dict get $result resource_id]
        if {![dict get $result printable]} {
            set state(printUnsupported) "Original mode [dict get $result mode], [dict get $result frames] frame(s). [dict get $result reason]"
            dict set state(sourceDescriptor) representations {metadata};set state(representation) metadata
            $ui(printRepresentation) configure -values metadata
        }
    }
    if {$state(printUnsupported) ne {}} {append state(sourceStatus) " $state(printUnsupported)"}
    viewerGuiActionsRefresh .top.nb.print
}
proc ::GX::printStudioSourceCurrent {generation} {
    variable ::GX::PrintStudio::state
    return [expr {$generation==$state(sourceGeneration) && [info exists state(sourceToken)] && ![catch {interactiveDocumentSessionToken} token] && $token eq $state(sourceToken)}]
}
source [file join $::GX::scriptDir app print_studio_poster.tcl]
