# SPDX-License-Identifier: GPL-3.0-or-later
# Explicit scripts and presentation filters extend the existing Workbook owner.
proc ::GX::ScientificWorksheet::filterPredicate {book row predicate} {
    set column [dict get $predicate column];_columnNumber $column
    set op [dict get $predicate op];set item {};set address "$column$row"
    if {[dict exists $book cells $address] && [dict get $book cells $address kind] in {manual dataset text scalar boolean missing nan}} {
        set cell [dict get $book cells $address]
        set item [dict create kind [dict get $cell kind] value [dict get $cell source] unit [dict get $cell unit]];set failed 0
    } else {set failed [catch {set item [value $book $address]} diagnostic]}
    if {$op eq "error"} {return $failed}
    if {$failed} {return 0}
    set kind [dict get $item kind];set raw [dict get $item value]
    switch $op {
        blank {return [expr {$kind eq "missing" || $raw eq {}}]}
        missing {return [expr {$kind eq "missing"}]}
        nan {return [expr {$kind eq "nan"}]}
        boolean {return [expr {$kind eq "boolean" && [string is true -strict $raw]==[string is true -strict [dict get $predicate value]]}]}
    }
    if {$kind in {missing nan complex vector matrix}} {return 0}
    set operand [::GX::datasetPublicationV2DictDefault $predicate value {}]
    if {$op in {gt ge lt le eq ne} && $kind ne "text"} {
        if {![string is double -strict $raw] || ![string is double -strict $operand] || $kind eq "text"} {return 0}
        set operandUnit [::GX::datasetPublicationV2DictDefault $predicate unit {}]
        if {$operandUnit ne {}} {set operand [lindex [::GX::unitRegistryConvertValues $operandUnit [dict get $item unit] [list $operand]] 0]}
        switch $op {eq {return [expr {$raw==$operand}]} ne {return [expr {$raw!=$operand}]} gt {return [expr {$raw>$operand}]} ge {return [expr {$raw>=$operand}]} lt {return [expr {$raw<$operand}]} le {return [expr {$raw<=$operand}]}}
    }
    switch $op {
        eq {return [expr {$raw eq $operand}]}
        ne {return [expr {$raw ne $operand}]}
        contains {return [expr {[string first [string tolower $operand] [string tolower $raw]]>=0}]}
        starts {return [expr {[string first [string tolower $operand] [string tolower $raw]]==0}]}
        in {return [expr {$raw in $operand}]}
    }
    error "Unsupported filter predicate '$op'"
}
proc ::GX::ScientificWorksheet::_filterBindingRevisions {book} {
    set revisions {}
    dict for {column binding} [dict get $book bindings] {set id [dict get $binding dataset_id];dict set revisions $id [::GX::datasetRevisionToken $id [_requireSession]]}
    return $revisions
}
proc ::GX::ScientificWorksheet::filterViewSave {book name first last predicates {combine AND}} {
    validateBook $book
    if {[string trim $name] eq {} || [string length $name]>120 || $combine ni {AND OR}} {error {Filter View requires a name and AND/OR combination}}
    if {![string is integer -strict $first] || ![string is integer -strict $last] || $first<1 || $last<$first || $last>1000000 || $last-$first>=20000 || [llength $predicates]>32} {error {Filter View supports 1–20000 rows and at most 32 predicates}}
    foreach predicate $predicates {
        _columnNumber [dict get $predicate column]
        if {[dict get $predicate op] ni {eq ne gt ge lt le contains starts in blank missing nan error boolean}} {error {Invalid typed filter operation}}
    }
    dict set book filter_views $name [dict create first $first last $last predicates $predicates combine $combine binding_revisions [_filterBindingRevisions $book] sheet [dict get $book active_sheet] source_revision [dict get $book revision]]
    return [filterViewApply $book $name]
}
proc ::GX::ScientificWorksheet::filterViewApply {book name} {
    validateBook $book
    if {$name eq {}} {dict set book active_filter {};dict set book filter_hidden_rows {};dict incr book revision;return $book}
    set view [dict get $book filter_views $name]
    if {[dict exists $view invalid_reason]} {error [dict get $view invalid_reason]}
    if {[dict exists $view binding_revisions] && [dict get $view binding_revisions] ne [_filterBindingRevisions $book]} {error {A bound canonical source changed. Refresh the binding and explicitly save this Filter View again.}}
    set hidden {};set accepted {};set count 0
    for {set row [dict get $view first]} {$row<=[dict get $view last]} {incr row} {
        set keep [expr {[dict get $view combine] eq "AND"}]
        foreach predicate [dict get $view predicates] {
            set match [filterPredicate $book $row $predicate]
            if {[dict get $view combine] eq "AND" && !$match} {set keep 0;break}
            if {[dict get $view combine] eq "OR" && $match} {set keep 1;break}
        }
        if {[dict get $view predicates] eq {}} {set keep 1}
        if {$keep} {lappend accepted $row;incr count} else {dict set hidden $row 1}
    }
    dict set book filter_hidden_rows $hidden;dict set book active_filter $name
    dict set book filter_views $name evaluated_revision [dict get $book revision]
    dict set book filter_views $name visible_rows $accepted
    dict set book filter_views $name visible_count $count
    dict incr book revision;return $book
}
proc ::GX::ScientificWorksheet::filterVisibleRows {book first last} {
    validateBook $book
    if {$last<$first || $last-$first>=20000} {error {Visible selection exceeds 20000 rows}}
    set rows {}
    for {set r $first} {$r<=$last} {incr r} {if {![dict exists $book hidden_rows $r] && ![dict exists $book filter_hidden_rows $r]} {lappend rows $r}}
    return $rows
}
proc ::GX::ScientificWorksheet::scriptSave {book name code} {
    validateBook $book
    if {[dict get $book document_id] eq {}} {error {Save the Workspace before attaching a script}}
    if {[string trim $name] eq {} || [string length $name]>120 || [string bytelength $code]>1048576} {error {Script requires a name and at most 1 MiB UTF-8 source}}
    set id worksheet_source_[clock clicks]
    set registered [::GX::scriptRegistrySave session $id $name $code {language Python required_apis {SCIENTIFIC_WORKSHEET_API_v1;NUMERIC_API_v1;UNIT_REGISTRY_API_v1}}]
    set sourceRecord [::GX::scriptRegistryRead session $id]
    set f [::open [dict get $sourceRecord source_path] rb];try {set bytes [read $f]} finally {close $f}
    set resource [::GX::managedResourceWrite [dict get $book document_id] {format scientific_worksheet.script.v1 language Python} $bytes]
    dict set book scripts $name [dict create reference session:$id script_id $id sha256 [dict get $registered sha256] language Python source_resource $resource]
    dict incr book revision;return $book
}
proc ::GX::ScientificWorksheet::scriptSource {book name} {
    validateBook $book;set script [dict get $book scripts $name]
    if {[dict exists $script source_resource]} {
        set resource [dict get $script source_resource];set info [::GX::interactiveDocumentResourceInfo $resource]
        if {[dict get $info sha256] ne [dict get $script sha256] || [dict get $info size_bytes]>1048576} {error {Workspace script resource differs from its registered source SHA/size}}
        return [encoding convertfrom utf-8 [::GX::interactiveDocumentResourceReadChunk $resource 0 [dict get $info size_bytes]]]
    }
    set registered [::GX::scriptRegistryRead session [dict get $script script_id]]
    if {[dict get $registered sha256] ne [dict get $script sha256]} {error {Attached script source changed; reopen its explicit registered revision}}
    set f [::open [dict get $registered source_path] r];try {return [read $f]} finally {close $f}
}
proc ::GX::ScientificWorksheet::scriptContext {encoded} {
    set context [_scriptRequest $encoded];set book [dict get $context book]
    if {[dict exists $book _runtime]} {dict unset book _runtime}
    set book [_upgrade $book];set id [dict get $book document_id]
    set item [::GX::interactiveDocumentRead $id]
    if {[dict get $item module_id] ne "viewer.scientific_worksheet"} {error {Script source is not a Worksheet}}
    dict set book _runtime owner_generation [dict get $item generation];dict set book _runtime document_revision [dict get $item revision]
    validateBook $book;return $book
}
proc ::GX::ScientificWorksheet::_scriptRequest {encoded} {
    if {[string length $encoded]>11184812} {error {Script context exceeds 8 MiB}}
    set request [encoding convertfrom utf-8 [binary decode base64 -strict $encoded]]
    workspaceValidate [dict get $request book]
    return $request
}
proc ::GX::ScientificWorksheet::scriptSelection {encoded} {return [dict get [_scriptRequest $encoded] selection]}
proc ::GX::ScientificWorksheet::scriptSnapshot {book} {
    validateBook $book;set result [snapshot $book];workspaceValidate $result
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $result]]
}
proc ::GX::ScientificWorksheet::scriptSubmit {book name first last {visibleOnly 0}} {
    validateBook $book
    set source [scriptSource $book $name]
    set selection [dict create first [_cell $first] last [_cell $last] visible_only $visibleOnly]
    if {$visibleOnly} {lassign [rectangle $first $last] c1 r1 c2 r2;dict set selection exact_row_ids [filterVisibleRows $book $r1 $r2]}
    set request [dict create book [snapshot $book] selection $selection]
    set encoded [binary encode base64 -maxlen 0 [encoding convertto utf-8 $request]]
    if {[string length $encoded]>11184812} {error {Save/split a smaller Workbook for the bounded 8 MiB script context}}
    set wrapper "# Explicit Worksheet user script; ordinary Script Job trust model.\nfrom gxtxt import gxtxt_api_call\nbook = gxtxt_api_call('SCIENTIFIC_WORKSHEET_API_v1', 'script_context', \['$encoded'\])\nselection = gxtxt_api_call('SCIENTIFIC_WORKSHEET_API_v1', 'script_selection', \['$encoded'\])\n$source\nprint('GXTXT_WORKSHEET_SCRIPT_RESULT:' + gxtxt_api_call('SCIENTIFIC_WORKSHEET_API_v1', 'script_snapshot', \[book\]), flush=True)\n"
    set scriptId worksheet_execution_[clock clicks]
    ::GX::scriptRegistrySave session $scriptId "Worksheet: $name" $wrapper {language Python required_apis {SCIENTIFIC_WORKSHEET_API_v1;NUMERIC_API_v1;UNIT_REGISTRY_API_v1}}
    set revisions {}
    dict for {column binding} [dict get $book bindings] {set id [dict get $binding dataset_id];dict set revisions $id [::GX::datasetRevisionToken $id [_requireSession]]}
    set job [::GX::scriptJobSubmit session:$scriptId {}]
    return [dict create job_id [dict get $job id] identity [bookIdentity $book] snapshot [historySnapshot $book] sources $revisions script [dict get $book scripts $name] selection $selection]
}
proc ::GX::ScientificWorksheet::scriptCollect {book ticket} {
    validateBook $book
    if {[dict get $ticket identity] ne [bookIdentity $book] || [dict get $ticket snapshot] ne [historySnapshot $book]} {error {Worksheet changed. Script result is retained in Jobs and cannot overwrite newer edits}}
    dict for {id revision} [dict get $ticket sources] {if {[::GX::datasetRevisionToken $id [_requireSession]] ne $revision} {error {Canonical source changed since script submission}}}
    set job [::GX::scriptJobDescribe [dict get $ticket job_id]]
    if {[dict get $job state] ne "COMPLETED"} {error {Only a successfully completed Script Job can propose Worksheet changes}}
    set log {};set offset 0
    while 1 {
        set chunk [::GX::scriptJobLogRead [dict get $ticket job_id] $offset 65536]
        append log [dict get $chunk content]
        if {[string bytelength $log]>16777216} {error {Script output exceeds 16 MiB proposal limit}}
        if {[dict get $chunk eof]} break
        set offset [dict get $chunk next_offset]
    }
    if {![regexp -line {^GXTXT_WORKSHEET_SCRIPT_RESULT:([A-Za-z0-9+/=]+)$} $log -> encoded]} {error {Completed script did not return a valid Workbook proposal}}
    set proposed [encoding convertfrom utf-8 [binary decode base64 -strict $encoded]]
    workspaceValidate $proposed
    if {[dict get $proposed workbook_uuid] ne [dict get $book workbook_uuid] || [dict get $proposed document_id] ne [dict get $book document_id]} {error {Script proposal changed Workbook identity}}
    set proposed [restoreBookIdentity $proposed $book]
    dict for {address style} [dict get $proposed styles] {_cell $address;styleValidate $style}
    dict set proposed last_script [dict create job_id [dict get $ticket job_id] source [dict get $ticket script] selection [dict get $ticket selection]]
    return $proposed
}
