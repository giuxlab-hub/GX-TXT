source [file join [file dirname [info script]] .. official_dev099 workspace_common.tcl]
if {$::env(DISPLAY) ne {:1}} {error {Actual Debian DISPLAY :1 required}}
set argv {};::GX::main
proc model {method args} {tailcall ::GX::ScientificWorksheet::$method {*}$args}
proc ui {method args} {tailcall ::GX::ScientificWorksheet::UI::$method {*}$args}
proc click {w} {raise [winfo toplevel $w];pause 100;exec xdotool mousemove --sync [expr {[winfo rootx $w]+[winfo width $w]/2}] [expr {[winfo rooty $w]+[winfo height $w]/2}] click 1;pause 150}
proc choose {w id} {
    foreach label [$w.import.datasets cget -values] {if {[dict get $::GX::ScientificWorksheet::ui($w,import_catalog) $label id] eq $id} {$w.import.datasets set $label;event generate $w.import.datasets <<ComboboxSelected>>;pause;return}}
    error "Dataset $id is absent from guided compatible picker"
}
proc waitJob {ticket} {
    set until [expr {[clock milliseconds]+60000}]
    while {[clock milliseconds]<$until} {set state [dict get [::GX::scriptJobDescribe [dict get $ticket job_id]] state];if {$state in {COMPLETED CANCELLED FAILED}} {return $state};pause 150}
    error {Managed GUI script did not terminate in 60 seconds}
}
proc run {} {
    workspaceSeed
    foreach {id storage ns} {csv_table csv study/A hdf_table hdf5 study/A/child other_table csv study/B} {
        ::GX::datasetPublicationV2PublishSeries $::session math.numeric [dict create dataset_id $id contract table.generic storage $storage x_values {0 1 2 3} y_values {2 4 6 8} x_variable {variable_id elapsed unit s name Time} y_variable {variable_id response unit V name Voltage}]
        ::GX::datasetNamespaceSet $::session $id $ns
    }
    image create photo fixtureImage -width 10 -height 10;fixtureImage put #66AA88 -to 0 0 10 10;fixtureImage write [file join $::out raster.png] -format png;image delete fixtureImage
    set f [open [file join $::out mesh.stl] w];puts $f "solid triangle\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid triangle";close $f
    foreach {id contract format media path} [list document_pdf document.pdf pdf application/pdf /usr/share/doc/shared-mime-info/shared-mime-info-spec.pdf raster_image image.raster png image/png [file join $::out raster.png] mesh_model geometry.mesh stl model/stl [file join $::out mesh.stl]] {
        ::GX::datasetFilePublicationPublish $::session viewer.curve_digitizer [dict create dataset_id $id contract $contract format $format media_type $media storage_kind binary source_file $path]
    }
    set p [::GX::datasetPublicationV2Prepare $::session math.numeric {dataset_id rank2_table contract table.generic storage hdf5}];set wr [::GX::datasetPublicationV2OpenWriter $p]
    ::GX::datasetPublicationV2DeclareDimension $wr u 2 {};::GX::datasetPublicationV2DeclareDimension $wr v 2 {}
    ::GX::datasetPublicationV2DeclareVariable $wr matrix {dtype float64 dimension_ids {u;v} unit V}
    ::GX::datasetPublicationV2WriteVariable $wr matrix {1 2 3 4} {2 2};::GX::datasetPublicationV2Finalize $wr
    foreach {sid id} {sel_001 csv_table sel_002 other_table} {::GX::datasetSelectionRegister $sid [list type x_range source_dataset_id $id x_variable_id elapsed x_min 1 x_max 2 enabled 1]};::GX::datasetSelectionSaveRegistry $::session
    set w [::GX::viewerOpen viewer.scientific_worksheet scientific_worksheet {workspace_id new}];pause 400
    ::GX::ScientificWorksheet::_uiImportDialog $w;pause
    set ids [lmap label [$w.import.datasets cget -values] {dict get $::GX::ScientificWorksheet::ui($w,import_catalog) $label id}]
    check {{csv_table} in $ids && {hdf_table} in $ids && {document_pdf} ni $ids && {raster_image} ni $ids && {mesh_model} ni $ids && {rank2_table} ni $ids} {Guided GUI keeps real CSV/HDF5 and excludes PDF, raster, mesh and rank-2}
    set ::GX::ScientificWorksheet::ui($w,import_namespace) study/A;set ::GX::ScientificWorksheet::ui($w,import_descendants) 0;::GX::ScientificWorksheet::_uiImportCatalog $w
    check {[llength [$w.import.datasets cget -values]]==1} {Exact namespace scope excludes descendants}
    set ::GX::ScientificWorksheet::ui($w,import_descendants) 1;::GX::ScientificWorksheet::_uiImportCatalog $w
    check {[llength [$w.import.datasets cget -values]]==2} {Hierarchical namespace scope includes child tables}
    choose $w csv_table
    save picker_state [list selections [$w.import.selections cget -values] preview [$w.import.preview get 1.0 end]]
    check {[$w.import.selections cget -values] eq {{} sel_001} && [string match {*elapsed:*0*1*2*3*} [$w.import.preview get 1.0 end]]} {Subset choices belong to the selected Dataset and bounded values are visible inline}
    set ::GX::ScientificWorksheet::ui($w,import_search) hdf;::GX::ScientificWorksheet::_uiImportCatalog $w
    check {[llength [$w.import.datasets cget -values]]==1} {Search filters readable name and exact Dataset ID}
    set ::GX::ScientificWorksheet::ui($w,import_search) {};::GX::ScientificWorksheet::_uiImportCatalog $w;choose $w csv_table
    $w.import.variables selection set 0 end
    ::GX::datasetMetadataUpdate $::session csv_table {revision_probe changed}
    set before [ui book $w];::GX::ScientificWorksheet::_uiImport $w $w.import
    check {[ui book $w] eq $before && [winfo exists $w.import]} {A source changed since preview refuses guided binding without mutation}
    ::GX::ScientificWorksheet::_uiImportCatalog $w;choose $w csv_table;$w.import.variables selection set 0 end;click $w.import.go
    set b [ui book $w]
    check {[dict size [dict get $b bindings]]==2 && [dict get $b cells B3 lineage source_row]==2 && [dict get [model value $b B3] unit] eq {V}} {Real guided Apply maps selected Variables consecutively and preserves exact source rows/units}
    ::GX::ScientificWorksheet::_uiImportDialog $w;pause;choose $w hdf_table
    set ::GX::ScientificWorksheet::ui($w,import_start) F;$w.import.variables selection set 0 end;click $w.import.go
    check {[dict get [ui book $w] cells G3 lineage dataset_id] eq {hdf_table} && [dict get [model value [ui book $w] G3] value]==6} {Actual guided HDF5 binding preserves canonical Variable and row lineage}
    ui save $w
    ui goto $w B1;ui formatDialog $w;pause
    check {[winfo exists $w.format]} {Format Cells opens the shared public UI Field form}
    ui formatApply $w B1 B4 {category Number decimals 3 align right wrap 1 rotation 30 background #EEFFEE border_color #112233 border_width 1 border_style dotted borders outer}
    destroy $w.format;pause
    check {[dict get [model value [ui book $w] B3] value]==6 && [dict get [model styleAt [ui book $w] B3] rotation]==30} {GUI formatting changes presentation while preserving exact scientific values}
    set g [ui grid $w];ui goto $w B1;pause
    lassign [$g bbox 1 2] x1 y1 cw rh;lassign [$g bbox 4 2] x4 y4
    exec xdotool mousemove --sync [expr {[winfo rootx $g]+$x1+20}] [expr {[winfo rooty $g]+$y1+10}] mousedown 1
    pause 60
    exec xdotool mousemove --sync [expr {[winfo rootx $g]+$x4+20}] [expr {[winfo rooty $g]+$y4+10}] mouseup 1;pause
    click [dict get $::GX::ViewerCommands::windows $w toolbar buttons autofit]
    check {[dict get [ui book $w] row_heights 1]>35 && [dict get [ui book $w] row_heights 4]>35 && ![dict exists [ui book $w] row_heights 5]} {Actual shared Auto-fit accommodates rotated/wrapped selected cells without resizing neighbors}
    lassign [$g bbox 1 2] x y cw rh
    exec xdotool mousemove --sync [expr {[winfo rootx $g]+$x+$cw-14}] [expr {[winfo rooty $g]+12}] click 1;pause
    check {[winfo exists $w.filters] && $::GX::ScientificWorksheet::UI::st($w,filter_column) eq {B}} {Real native column dropdown opens the shared typed Filter View builder}
    foreach {key value} {filter_name high_voltage filter_first 1 filter_last 4 filter_column B filter_op gt filter_value 4 filter_unit V} {set ::GX::ScientificWorksheet::UI::st($w,$key) $value}
    click $w.filters.actions.add;click $w.filters.actions.apply
    save filter_diagnostic [dict create status $::GX::ScientificWorksheet::ui($w,status) book [dict get [ui book $w] filter_views] predicates $::GX::ScientificWorksheet::UI::st($w,filter_predicates)]
    check {[dict get [ui book $w] filter_views high_voltage visible_rows] eq {3 4} && [dict get [$g receipt] first_row]>=3} {Typed GUI filter projects matching source rows without deleting measurements}
    exec import -window [winfo id $w] [file join $::out filter_view.png]
    ui filterAll $w;destroy $w.filters
    ui scriptPanel $w;pause;set p $w.body.inspector.tabs.scripts
    set ::GX::ScientificWorksheet::UI::st($w,script_name) {Typed voltage example}
    $p.code delete 1.0 end;$p.code insert end {cell = gxtxt_api_call('SCIENTIFIC_WORKSHEET_API_v1','inspect_cell',[book,'B1'])
assert cell['unit'] == 'V'
book = gxtxt_api_call('SCIENTIFIC_WORKSHEET_API_v1','set_typed_cell',[book,'D1',{'kind':'scalar','value':float(cell['value_utf8'])*2,'unit':'V'}])
print('Typed voltage proposal ready', flush=True)}
    click $p.actions.run;set ticket $::GX::ScientificWorksheet::UI::st($w,script_ticket)
    check {[waitJob $ticket] eq {COMPLETED} && ![dict exists [ui book $w] cells D1]} {Scripts editor runs a real managed Python Job without an early Workbook commit}
    pause 350
    check {[string first {Typed voltage proposal ready} [$p.logs get 1.0 end]]>=0 && [string first GXTXT_WORKSHEET_SCRIPT_RESULT: [$p.logs get 1.0 end]]<0} {Scripts editor shows readable diagnostics and proposal status rather than transport payloads}
    click $p.actions.apply
    check {[dict get [model value [ui book $w] D1] value]==4 && [dict get [model value [ui book $w] D1] unit] eq {V}} {Explicit GUI Apply adopts the typed proposal}
    ui navigate $w undo;pause
    check {![dict exists [ui book $w] cells D1]} {Script adoption is one Undo item}
    ui navigate $w redo;pause
    click $p.actions.run;set ticket $::GX::ScientificWorksheet::UI::st($w,script_ticket);waitJob $ticket
    ui applyBook $w [model setCell [ui book $w] E1 99] {Newer user edit}
    check {[catch {ui scriptApply $w}]} {Actual editor refuses a stale completed proposal}
    $p.code delete 1.0 end;$p.code insert end {import time
print('Cancellation GUI fixture',flush=True)
time.sleep(20)
book = gxtxt_api_call('SCIENTIFIC_WORKSHEET_API_v1','set_cell',[book,'Z1','99'])}
    click $p.actions.run;set ticket $::GX::ScientificWorksheet::UI::st($w,script_ticket);click $p.actions.stop
    check {[waitJob $ticket] eq {CANCELLED} && ![dict exists [ui book $w] cells Z1]} {Actual editor Cancel prevents partial Worksheet adoption}
    exec import -window [winfo id $w] [file join $::out scripts_editor.png]
    set toolbarHeight [winfo height $w.toolbar]
    ui goto $w A1;set ::GX::ScientificWorksheet::ui($w,selections) {{A1 B4}};::GX::ScientificWorksheet::Charts::add $w;pause
    set buttons [dict get $::GX::ViewerCommands::windows $w toolbar buttons]
    check {[winfo ismapped [dict get $buttons chart_publish]] && ![winfo ismapped [dict get $buttons format_cells]]} {Selected chart instantly shows chart actions and hides cell-only controls}
    check {[winfo height $w.toolbar]==$toolbarHeight} {Context switching reserves toolbar height and does not move the native viewport}
    set ref [::GX::ScientificWorksheet::Charts::publish $w];pause;save plot_reference $ref
    check {[dict exists $ref variant_id]} {Actual retained chart publishes a genuine native Plot v4 Graph Variant}
    set id [ui save $w];set b [model load $id]
    check {[dict exists $b scripts {Typed voltage example}] && [dict exists $b filter_views high_voltage] && [dict get [model styleAt $b B3] rotation]==30} {Workspace reopen preserves scripts, Filter Views, formatting and published Chart links}
    check {[sha $::source] eq $::sourceSha && ![info exists ::bgfailed]} {Real workflows preserve canonical source and have no Tk background error}
    save result [dict create status PASS checks $::checks session $::session document_id $id]
}
set failed {};set done 0
after 500 {if {[catch {run} message options]} {set ::failed [dict get $options -errorinfo];save result [dict create status FAIL checks $::checks details $::failed];puts stderr $::failed};catch {destroy .};set ::done 1}
vwait done
exit [expr {$failed ne {}}]
