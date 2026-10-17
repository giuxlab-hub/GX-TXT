source [file join [file dirname [info script]] .. official_dev099 project_common.tcl]
proc model {method args} {tailcall ::GX::ScientificWorksheet::$method {*}$args}
try {
    set session [::GX::createNewSession automation_dev102]
    ::GX::modulePublicApiActivate viewer.scientific_worksheet SCIENTIFIC_WORKSHEET_API_v1
    set b [model new]
    foreach {a v} {A1 1 A2 2 A3 3 A4 4 B1 alpha B2 beta B3 alpha B4 beta} {set b [model setCell $b $a $v]}
    set b [model setTypedCell $b A5 {kind missing value {} unit V}]
    set b [model setTypedCell $b A6 {kind nan value NaN unit V}]
    set exact [dict get $b cells]
    set b [model filterViewSave $b alpha_high 1 6 {{column A op gt value 1} {column B op eq value alpha}} AND]
    check {[dict get $b filter_views alpha_high visible_rows] eq {3} && [dict get $b cells] eq $exact} {AND filter changes presentation only}
    set b [model filterViewSave $b missing_or_nan 1 6 {{column A op missing} {column A op nan}} OR]
    check {[dict get $b filter_views missing_or_nan visible_rows] eq {5 6}} {Missing and NaN retain distinct typed predicates}
    set b [model setTypedCell $b C1 {kind scalar value 1 unit V}]
    set b [model filterViewSave $b physical 1 1 {{column C op gt value 500 unit mV}}]
    check {[dict get $b filter_views physical visible_rows] eq {1}} {Physical filter operand conversion delegates to CORE Unit Registry}
    check {[catch {model filterViewSave $b invalid_unit 1 1 {{column C op gt value 500 unit s}}}]} {Incompatible filter units refuse}
    set b [model filterViewApply $b {}]
    check {[dict get $b filter_hidden_rows] eq {} && [dict exists $b filter_views alpha_high]} {Show all clears projection and preserves named Filter Views}
    set b [model save $b]
    set code {print('Real Worksheet Python Job')
cell = gxtxt_api_call('SCIENTIFIC_WORKSHEET_API_v1', 'inspect_cell', [book, 'C1'])
assert cell['unit'] == 'V'
book = gxtxt_api_call('SCIENTIFIC_WORKSHEET_API_v1', 'set_typed_cell', [book, 'D1', {'kind':'scalar', 'value':float(cell['value_utf8'])*2, 'unit':'V'}])}
    set b [model scriptSave $b {Double voltage} $code]
    set ticket [model scriptSubmit $b {Double voltage} C1 C1]
    set job [::GX::scriptJobWait [dict get $ticket job_id] 60]
    check {[dict get $job state] eq {COMPLETED}} {Real registered Python Script Job completes}
    set candidate [model scriptCollect $b $ticket]
    check {[dict get [model value $candidate D1] value]==2 && [dict get [model value $candidate D1] unit] eq {V} && ![dict exists $b cells D1]} {Script proposal preserves physical typing without early mutation}
    set stale [model setCell $b E1 99]
    check {[catch {model scriptCollect $stale $ticket}]} {Stale Workbook refuses completed script adoption}
    set b [model save $candidate];set id [dict get $b document_id]
    set b [model load $id]
    check {[model scriptSource $b {Double voltage}] eq $code && [dict exists $b filter_views alpha_high] && [dict get [model value $b D1] value]==2} {Script source, result link and Filter Views survive Workbook reopen}
    set b [model scriptSave $b {Cancellation} {import time
print('Cancel fixture started', flush=True)
time.sleep(20)
book = gxtxt_api_call('SCIENTIFIC_WORKSHEET_API_v1', 'set_cell', [book, 'Z1', '99'])}]
    set ticket [model scriptSubmit $b Cancellation A1 A1]
    ::GX::scriptJobCancel [dict get $ticket job_id]
    set job [::GX::scriptJobWait [dict get $ticket job_id] 30]
    check {[dict get $job state] in {CANCELLED CANCELED} && [catch {model scriptCollect $b $ticket}] && ![dict exists $b cells Z1]} {Cancelled managed Job cannot commit partial Workbook changes}
    set b [model scriptSave $b {Numeric mean example} {values = [float(gxtxt_api_call('SCIENTIFIC_WORKSHEET_API_v1','inspect_cell',[book,'A'+str(row)])['value_utf8']) for row in range(1,5)]
summary = gxtxt_api_call('NUMERIC_API_v1','reduce_summary',[values,{}])
book = gxtxt_api_call('SCIENTIFIC_WORKSHEET_API_v1','set_typed_cell',[book,'H1',{'kind':'scalar','value':summary['mean'],'unit':''}])}]
    set ticket [model scriptSubmit $b {Numeric mean example} A1 A4];set job [::GX::scriptJobWait [dict get $ticket job_id] 60]
    set proposal [model scriptCollect $b $ticket]
    check {[dict get [model value $proposal H1] value]==2.5} {Documented Numeric mean example uses the actual public scientific reducer}
    set large [model new];for {set row 1} {$row<=20000} {incr row} {dict set large cells A$row [dict create source $row kind manual unit V]}
    set started [clock microseconds];set large [model filterViewSave $large bounded_20k 1 20000 {{column A op ge value 10000 unit V}}]
    save filter_20k [dict create elapsed_ms [expr {([clock microseconds]-$started)/1000.}] rows 20000 visible [dict get $large filter_views bounded_20k visible_count]]
    check {[dict get $large filter_views bounded_20k visible_count]==10001 && [dict size [dict get $large cells]]==20000} {Bounded 20000-row typed filter preserves complete Workbook content}
    set portable [model save [model new {Portable scripts}]]
    set portable [model scriptSave $portable {Portable source} {print('Explicit portable script')}]
    set portable [model save $portable];set resource [::GX::sessionWorkspaceExport [dict get $portable document_id]]
    set bytes {};set total [dict get $resource size_bytes]
    for {set offset 0} {$offset<$total} {incr offset 1048576} {append bytes [::GX::interactiveDocumentResourceReadChunk $resource $offset [expr {min(1048576,$total-$offset)}]]}
    ::GX::createNewSession standalone_workspace_import
    set carrier [model save [model new {Import carrier}]]
    set resource [::GX::managedResourceWrite [dict get $carrier document_id] {format gxtxt.workspace.zip} $bytes]
    set imported [::GX::sessionWorkspaceImport $resource]
    set portable [model load [dict get $imported workspace_id]]
    check {[model scriptSource $portable {Portable source}] eq {print('Explicit portable script')}} {Standalone Workspace transfer carries authenticated script source without its old Session registry}
    save result [dict create status PASS checks $checks session $session]
} on error {message options} {save result [dict create status FAIL checks $checks details [dict get $options -errorinfo]];puts stderr [dict get $options -errorinfo];exit 1}
exit
