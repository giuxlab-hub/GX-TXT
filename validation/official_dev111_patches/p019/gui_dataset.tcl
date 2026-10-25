# P019 focused current-source Dataset, heterogeneous-axis and persistence GUI verification; private data only.
# Adapted inspected P018 validation paths; no historical deployment/source replacement.
lassign $argv framework output
set mode patched
if {[file exists $output]} {error {Fresh output required}}
set framework [file normalize $framework];file mkdir $output;set output [file normalize $output];file attributes $output -permissions 0700
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1;set argv0 __p019_stress__
set catalog [file join $output framework];file mkdir [file join $catalog plugins modules]
foreach name {core app docs services gxtxt_pipeline.tcl} {file copy [file join $framework $name] [file join $catalog $name]}
foreach name {math.numeric plot.dataset viewer.curve_workbench} {file copy [file join $framework plugins modules $name] [file join $catalog plugins modules $name]}
source [file join $catalog gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
proc write {path text} {set f [open $path w];puts -nonewline $f $text;close $f}
proc pause {{ms 120}} {set ::waiting 1;after $ms {set ::waiting 0};vwait ::waiting;update idletasks}
proc check {test label} {
 if {![uplevel 1 [list expr $test]]} {error "FAIL: $label"}
 lappend ::checks [dict create name $label status PASS];write [file join $::output checks.tcllist] $::checks
 puts "PASS: $label";flush stdout
}
set checks {};set inputTrace {};set errors {};set evaluations {};set publications 0;set nativeEvents {};set modalEvents {};set inTrace 0
proc bgerror {message} {lappend ::errors $message;puts stderr "BACKGROUND: $message"}
proc traceEvaluate {command op} {lappend ::evaluations [lindex $command 2]}
proc tracePublish {command op} {incr ::publications}
proc traceInput {cmd op} {
 if {[lindex $cmd 1] eq {xdotool}} {lappend ::inputTrace [list [clock milliseconds] {*}[lrange $cmd 1 end]];write [file join $::output input.tcllist] $::inputTrace}
}
trace add execution exec enter traceInput
proc stockChoice {widget value} {
 click $widget;set i [lsearch -exact [$widget cget -values] $value]
 if {$i<0} {error "Missing actual choice $value in $widget"}
 exec xdotool key Home
 for {set n 0} {$n<$i} {incr n} {exec xdotool key Down}
 exec xdotool key Return;pause 100
 check {[$widget get] eq $value} "actual keyboard choice $value"
}
proc branchWatch {} {
 if {[winfo exists .]} {
  foreach top [guiWidgets .] {
   if {![winfo exists $top]} continue
   if {[winfo toplevel $top] ne $top || [wm title $top] ne {Branch Workspace History}} continue
   foreach button [guiWidgets $top] {
    if {[winfo class $button] in {Button TButton} && [winfo viewable $button] && [$button cget -text] eq {OK}} {
     lappend ::modalEvents [list branch_confirmation [clock milliseconds]]
     exec xdotool mousemove [expr {[winfo rootx $button]+[winfo width $button]/2}] [expr {[winfo rooty $button]+[winfo height $button]/2}] click 1
     break
    }
   }
  }
  set ::branchWatcher [after 70 branchWatch]
 }
}
proc guiWidgets {w} {set all [list $w];foreach c [winfo children $w] {lappend all {*}[guiWidgets $c]};return $all}
proc see {widget} {::GX::native2DViewportSeeWidget $::canvas $widget;pause 60}
proc click {widget} {
    see $widget
    check {[winfo ismapped $widget]} "mapped control $widget"
    exec xdotool mousemove [expr {[winfo rootx $widget]+[winfo width $widget]/2}] [expr {[winfo rooty $widget]+[winfo height $widget]/2}] click 1
    pause
}
proc combo {widget pattern} {
    see $widget
    exec xdotool mousemove [expr {[winfo rootx $widget]+[winfo width $widget]-8}] [expr {[winfo rooty $widget]+[winfo height $widget]/2}] click 1
    pause
    set popup [::GX::_uiFieldSelectorPanel $widget [winfo toplevel $widget]];set list $popup.options
    if {![winfo exists $popup] || ![winfo ismapped $popup]} {set popup [::ttk::combobox::PopdownWindow $widget];set list $popup.f.l}
    check {[winfo ismapped $popup]} {actual unit-selector popup opens}
    set wanted -1;set i 0;foreach label [$list get 0 end] {if {[string match $pattern $label]} {set wanted $i;break};incr i}
    check {$wanted>=0} "choice exists: $pattern"
    $list see $wanted;pause 50
    lassign [$list bbox $wanted] x y width height
    exec xdotool mousemove [expr {[winfo rootx $list]+$x+20}] [expr {[winfo rooty $list]+$y+$height/2}] click 1
    pause
}
proc typeInto {widget text} {click $widget;exec xdotool key Home shift+End BackSpace;exec xdotool type --clearmodifiers -- $text;pause 80}
proc shot {name} {::GX::native2DViewportTooltipHide;pause 80;exec timeout 8s import -silent -window root [file join $::output $name.png]}
proc menuIndex {menu pattern} {for {set i 0} {$i<=[$menu index end]} {incr i} {if {[$menu type $i] ne {separator} && [string match $pattern [$menu entrycget $i -label]]} {return $i}};error "Missing menu $pattern"}
proc menuChoose {button pattern} {
    click $button;set m [$button cget -menu];set i [menuIndex $m $pattern]
    set height [expr {[font metrics [$m cget -font] -linespace]+6}]
    if {$i<[$m index end]} {set height [expr {[$m yposition [expr {$i+1}]]-[$m yposition $i]}]}
    exec xdotool mousemove [expr {[winfo rootx $m]+40}] [expr {[winfo rooty $m]+[$m yposition $i]+$height/2}] click 1
    pause
}
proc selectCurve {id} {
    set tree $::w.leftScroll.viewport.content.curves
    $tree see $id;pause 50;lassign [$tree bbox $id name] x y width height
    exec xdotool mousemove [expr {[winfo rootx $tree]+$x+25}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1
    pause
}


proc points {} {::GX::Native2D::core points $::scene [dict get $::GX::CurveWorkbench::st($::w,curves) $::a native]}
proc movePointer {xy} {lassign $xy x y;exec xdotool mousemove [expr {[winfo rootx $::canvas]+int(round($x))}] [expr {[winfo rooty $::canvas]+int(round($y))}]}
proc gizmoDrag {mode {finish release}} {
    menuChoose $::w.sketchbar.modify [string totitle $mode]
    set items [::GX::Native2D::core render_gizmo $::scene]
    set start {};set end {}
    foreach item $items {
        if {$mode eq {translate} && [dict get $item handle] eq {x} && [dict get $item kind] eq {line}} {
            lassign [dict get $item a] ax ay;lassign [dict get $item b] bx by
            set start [list [expr {($ax+$bx)/2.0}] [expr {($ay+$by)/2.0}]]
            set end [list [expr {[lindex $start 0]+$::translationPixels}] [lindex $start 1]];break
        }
        if {$mode eq {rotate} && [dict get $item handle] eq {rotate}} {
            set start [dict get $item a]
            set pivot [dict get [::GX::Native2D::core pivot $::scene] point]
            lassign [::GX::Native2D::core device $::scene $pivot] cx cy
            set radius [expr {[lindex $start 0]-$cx}]
            set end [list $cx [expr {$cy-$radius}]];break
        }
    }
    check {$start ne {} && $end ne {}} "existing $mode gizmo geometry available"
    set expectedHandle [expr {$mode eq {translate}?{x}:{rotate}}]
    check {[::GX::Native2D::core gizmo_hit $::scene $start 5] eq $expectedHandle} "actual $mode handle hit"
    set before [points]
    if {$finish eq {reject}} {set end [::GX::Native2D::core device $::scene [dict get [::GX::Native2D::core pivot $::scene] point]]}
    movePointer $start;exec xdotool mousedown 1;pause 70
    set activeBegin [::GX::Native2D::core drag_active $::scene]
    movePointer $end;pause 120
    set preview [points];set activePreview [::GX::Native2D::core drag_active $::scene]
    if {$finish eq {escape}} {exec xdotool key Escape;pause 80}
    exec xdotool mouseup 1;pause 150
    set after [points];set activeAfter [::GX::Native2D::core drag_active $::scene]
    set record [dict create mode $mode finish $finish before $before preview $preview after $after start $start end $end active_begin $activeBegin active_preview $activePreview active_after $activeAfter]
    lappend ::gestures $record
    write [file join $::output gestures.tcllist] $::gestures
    shot $mode-$finish-[llength $::gestures]
    puts "GESTURE: $record";flush stdout
    return $record
}

::GX::configurationSet storage.session_root [file join $output Sessions];::GX::configurationSet storage.temp_dir [file join $output tmp];::GX::configurationSave {storage.session_root storage.temp_dir}
set session [::GX::createNewSession p019_stress {} 0]
::GX::datasetPreviewCacheInit;::GX::configurationSet preview.cache_enabled 0
package require Tk;wm withdraw .
set branchWatcher [after 70 branchWatch]
set wmPids [exec xfwm4 --replace --compositor=off --sm-client-disable >[file join $output wm.log] 2>@1 &];pause 300
set w {};set timings {};set snapshots {};set ids {};set segmentCount 0
try {
 set w [::GX::viewerOpen viewer.curve_workbench curve_workbench {workspace_id new workspace_name {P019 Heterogeneous time-voltage}}]
 wm geometry $w 1480x940+20+20;raise $w;pause 200
 set canvas $w.right.viewport.canvas;set scene $::GX::CurveWorkbench::st($w,scene)
 set host [::GX::CurveWorkbench::_cadCanvas $w];set tools [$host advanced]

 source [file join [file dirname [info script]] gui_helpers.tcl]
 proc near {before after {tol 1e-8}} {if {[llength $before]!=[llength $after]} {return 0};set d 0;foreach a $before b $after {foreach x $a y $b {set d [expr {max($d,abs($x-$y))}]}};return [expr {$d<$tol}]}
 proc sourcePage {rec} {set token [::GX::curveSourceOpen $::session [dict get $rec source_request]];try {return [::GX::curveSourcePage $token 0 1000]} finally {::GX::curveSourceClose $token}}
 proc cascadeChoose {button parent label} {
  click $button;set menu [$button cget -menu];set i [menuIndex $menu $parent];set sub [$menu entrycget $i -menu]
  exec xdotool mousemove [expr {[winfo rootx $menu]+70}] [expr {[winfo rooty $menu]+[$menu yposition $i]+10}];pause 400;popupEntry $sub $label
 }
 menuChoose $w.toolbar.workspace {Workspace Configuration*}
 typeInto $w.coordinateConfiguration.viewport.content.field0.entry ms
 typeInto $w.coordinateConfiguration.viewport.content.field1.entry mV
 click $w.coordinateConfiguration.viewport.content.field2.entry
 click $w.coordinateConfiguration.actions.apply
 check {$::GX::UiField::formStatus($w.coordinateConfiguration) eq {Applied.}} {actual empty Workspace Configuration admits explicit heterogeneous ms and mV axes}
 click $w.coordinateConfiguration.actions.close
 set xs {};set ys {};for {set j 0} {$j<32} {incr j} {lappend xs [expr {500.0*$j}];lappend ys [expr {100.0*sin(.4*$j)}]}
 ::GX::datasetPublicationV2PublishSeries $session math.numeric [dict create dataset_id time_voltage contract table.generic storage csv x_values $xs y_values $ys x_variable {variable_id time_ms canonical time_ms unit ms} y_variable {variable_id voltage_mV canonical voltage_mV unit mV}]
 set sourceBefore [::GX::sessionInspectionDatasetPayload time_voltage]
 write [file join $output source-baseline.tcldict] $sourceBefore
 set ::GX::CurveWorkbench::st($w,preferredDataset) time_voltage
 click $w.toolbar.add
 set label {};dict for {text did} $::GX::CurveWorkbench::st($w,source.datasetMap) {if {$did eq {time_voltage}} {set label $text}}
 stockChoice $w.source.dataset $label
 foreach {axis vid} {x time_ms y voltage_mV} {set label {};dict for {text actual} $::GX::CurveWorkbench::st($w,source.varMap) {if {$actual eq $vid} {set label $text}};stockChoice $w.source.$axis $label}
 check {[::GX::CurveWorkbench::_sourceId $w x] eq {time_ms} && [::GX::CurveWorkbench::_sourceId $w y] eq {voltage_mV}} {actual selectors retain scientific X and Y variable identities}
 click $w.source.buttons.add
 set datasetCurve $::GX::CurveWorkbench::st($w,active);set record [::GX::CurveWorkbench::_record $w $datasetCurve]
 check {[::GX::CurveWorkbench::_coordinateUnits $record] eq {ms mV}} {heterogeneous source import preserves distinct stored physical units}
 set sourceRequest [dict get $record source_request];set sourcePage [sourcePage $record]
 set expected [lmap x $xs y $ys {list $x $y}]
 check {[near [curvePoints $datasetCurve] $expected]} {native source coordinates equal canonical time-voltage samples}
 ::GX::CurveWorkbench::_fit $w 1;pause 120
 set view [::GX::Native2D::core view $scene];lassign $view width height left top right bottom bounds;lassign $bounds x0 y0 x1 y1
 set sx [expr {($width-$left-$right)/($x1-$x0)}];set sy [expr {($height-$top-$bottom)/($y1-$y0)}]
 check {[::GX::Native2D::core aspect $scene] eq {auto} && max($sx/$sy,$sy/$sx)>10} {nonuniform viewport aspect is explicit and distinct from dimensional incompatibility}
 menuChoose $w.toolbar.view {Axis display units*}
 combo $w.axisunits.viewport.content.field0.entry s
 combo $w.axisunits.viewport.content.field1.entry V
 click $w.axisunits.actions.apply
 check {$::GX::UiField::formStatus($w.axisunits) eq {Applied.}} {actual independent X and Y display conversion applies}
 click $w.axisunits.actions.close
 write [file join $output axis-applied.tcldict] [dict create x [::GX::CurveWorkbench::_coordinateAxis $w $datasetCurve x] y [::GX::CurveWorkbench::_coordinateAxis $w $datasetCurve y] presentation $::GX::CurveWorkbench::st($w,coordinatePresentation)]
 check {[dict get [::GX::CurveWorkbench::_coordinateAxis $w $datasetCurve x] display_unit] eq {s} && [dict get [::GX::CurveWorkbench::_coordinateAxis $w $datasetCurve y] display_unit] eq {V}} {display seconds and volts stay independent from stored milliseconds and millivolts}
 shot heterogeneous-source
 selectMode {Local Geometry*}
 set sourceIndex 13;set sourcePoint [lindex $expected $sourceIndex]
 set historyCount [dict get [::GX::scientificHistoryViewerStatus $w] count]
 set start [xy $sourcePoint];canvasClick $start
 set members [::GX::CurveWorkbench::_semanticMembers $w]
 check {[dict get [lindex $members 0] kind] eq {point} && [dict get [lindex $members 0] index]==$sourceIndex} {heterogeneous pointer hit retains original canonical source row index}
 set tree $w.leftScroll.viewport.content.points
 check {[lindex [$tree selection] 0] eq "p$sourceIndex"} {point table synchronizes with native source-row selection}
 set original [curvePoints $datasetCurve]
 movePointer $start;exec xdotool mousedown 1;pause 50;movePointer [list [expr {[lindex $start 0]+25}] [expr {[lindex $start 1]-20}]];pause 80;exec xdotool mouseup 1;pause 100
 check {[curvePoints $datasetCurve] eq $original && [dict get [::GX::scientificHistoryViewerStatus $w] count]==$historyCount} {untouched Dataset source remains read-only under actual point drag and harmless selection adds no History}
 menuChoose $w.sketchbar.represent {Dataset → editable points*}
 typeInto $w.convert.viewport.content.field0.entry 10
 typeInto $w.convert.viewport.content.field1.entry 16
 typeInto $w.convert.viewport.content.field2.entry {Derived time-voltage}
 click $w.convert.actions.apply
 check {$::GX::UiField::formStatus($w.convert) eq {Applied.}} {reviewed exact Dataset range converts to editable native points}
 click $w.convert.actions.close
 set derived $::GX::CurveWorkbench::st($w,active);set a $derived;set b $datasetCurve
 set derivedRecord [::GX::CurveWorkbench::_record $w $derived]
 check {[dict get $derivedRecord source] eq {time_voltage} && [dict get $derivedRecord parents] eq [list $datasetCurve] && [::GX::CurveWorkbench::_coordinateUnits $derivedRecord] eq {ms mV}} {editable derivative keeps logical parent source identity and independent physical quantities}
 menuChoose $w.toolbar.view {Axis display units*}
 combo $w.axisunits.viewport.content.field0.entry s
 combo $w.axisunits.viewport.content.field1.entry V
 click $w.axisunits.actions.apply;click $w.axisunits.actions.close
 ::GX::CurveWorkbench::_fit $w 1;pause 100
 set tree $w.leftScroll.viewport.content.points;$tree see p3;pause 50;lassign [$tree bbox p3] x y width height
 exec xdotool mousemove [expr {[winfo rootx $tree]+$x+25}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1;pause 100
 check {[lindex [$tree item p3 -values] end]==13} {derived local point index retains canonical original row13}
 set before [curvePoints $derived]
 typeInto $w.leftScroll.viewport.content.numeric.editX 6.8
 typeInto $w.leftScroll.viewport.content.numeric.editY 0.125
 click $w.leftScroll.viewport.content.numeric.apply
 set changed [curvePoints $derived]
 check {abs([lindex $changed 3 0]-6800)<1e-7 && abs([lindex $changed 3 1]-125)<1e-7} {actual numeric editor converts independent display seconds-volts into exact native ms-mV coordinates}
 click $w.toolbar.undo;check {[near [curvePoints $derived] $before]} {heterogeneous point edit Undo restores exact original native values}
 click $w.toolbar.redo;check {[near [curvePoints $derived] $changed]} {heterogeneous point edit Redo restores independent-axis conversion}
 set grid [::GX::Native2D::core grid $scene];::GX::Native2D::core grid $scene {spacing_x 500 spacing_y 50}
 set controls [::GX::native2DViewportPanelWidget $canvas controls];click $controls.body.grid_snap
 selectCurve $derived;::GX::CurveWorkbench::_fit $w 1;pause 100
 ::GX::Native2D::core pivot $scene custom {8500 0};set gestures {};set translationPixels 70
 set g [gizmoDrag translate]
 set dx [expr {[lindex [dict get $g after] 0 0]-[lindex [dict get $g before] 0 0]}]
 check {abs($dx)>1 && abs($dx/500-round($dx/500))<1e-8} {heterogeneous componentwise translation uses native milliseconds grid snapping}
 click $w.toolbar.undo;click $w.toolbar.redo
 click $controls.body.grid_snap;::GX::Native2D::core grid $scene $grid
 set before [curvePoints $derived];set count [dict get [::GX::scientificHistoryViewerStatus $w] count]
 set g [gizmoDrag rotate]
 if {$mode eq {patched}} {check {[curvePoints $derived] eq $before && ![dict get $g active_begin] && [dict get [::GX::scientificHistoryViewerStatus $w] count]==$count} {metric Rotate is rejected before mutation for physically incompatible time-voltage axes}}
 if {$mode eq {baseline}} {write [file join $output baseline-numeric-rotation.tcldict] $g;if {[curvePoints $derived] ne $before} {click $w.toolbar.undo}}
 exec xdotool key Escape;pause 80
 set panel [::GX::native2DViewportPanelWidget $canvas compare];set p [::GX::CurveWorkbench::_comparisonControls $w]
 click $panel.header.toggle
 set labels [$p.measures.metric cget -values]
 check {{Geometric length} ni $labels && {Signed area} ni $labels} {physical Euclidean length and area are not offered for incompatible axes}
 check {[catch {::GX::native2DMetrics $scene [native $derived] {ms mV}} metricReason]} {existing public physical metric authority rejects unlike dimensions}
 write [file join $output metric-rejection.tcldict] [dict create available $labels reason $metricReason]
 click $panel.header.close
 # Independent X dimension remains physically meaningful and records milliseconds.
 selectCurve $derived;::GX::CurveWorkbench::_fit $w 1;pause 100;selectMode {Local Geometry*}
 canvasClick [xy [lindex [curvePoints $derived] 6]]
 cascadeChoose $w.sketchbar.constraints Dimensional {X Dimension}
 set place [lindex [curvePoints $derived] 6];lset place 1 [expr {[lindex $place 1]+30}]
 movePointer [xy $place];pause 80;exec xdotool click 1;pause 100
 check {[winfo exists $w.inline.value]} {allowed X Dimension opens physical-axis inline editor}
 write [file join $output shared-axis-dimension-state.tcldict] [dict create host [$host state] advanced [$tools state] dimension [$tools dimension state]]
 typeInto $w.inline.value [format %.9g [expr {[lindex [curvePoints $derived] 6 0]/1000.0}]]
 set dimensionBefore [curvePoints $derived]
 click $w.inline.commit
 set referenceFallback 0
 if {$::GX::CurveWorkbench::st($w,selectedRelationship) eq {} && [winfo exists $w.inline.reference] && [winfo viewable $w.inline.reference]} {
  check {[string match {*driving dimension conflicts*} [$w.inline.message cget -text]] && [curvePoints $derived] eq $dimensionBefore} {native rejected driving dimension preserves scientific geometry and offers explicit reference fallback}
  shot dimension-reference-offer
  click $w.inline.reference;set referenceFallback 1
 }
 set dimension $::GX::CurveWorkbench::st($w,selectedRelationship)
 set receipt [::GX::Native2D::core constraint_get $scene [dict get $::GX::CurveWorkbench::st($w,constraints) $dimension native]]
 set shared [dict get [$tools state] receipt];check {[dict get $shared operation] eq {constraint.apply} && [dict get $shared status] eq {committed}} {heterogeneous dimension commits through public shared CORE relationship owner}
 check {[dict get $receipt valid] && [dict get $receipt kind] eq {lock_x} && (!$referenceFallback || [dict get $receipt driven])} {heterogeneous independent-axis dimension uses supported native X reference relationship rather than a Euclidean norm}
 write [file join $output heterogeneous-dimension.tcldict] [dict create native $receipt reference_fallback $referenceFallback unchanged [expr {[curvePoints $derived] eq $dimensionBefore}]]
 exec xdotool key Escape;pause 80
 # Actual publication retains established source lineage and canonical units.
 click $w.toolbar.objects
 set objectMenu $w.toolbar.objects.menu;set publishRow [menuIndex $objectMenu {Publish selection*}]
 exec xdotool mousemove [expr {[winfo rootx $objectMenu]+70}] [expr {[winfo rooty $objectMenu]+[$objectMenu yposition $publishRow]+10}];pause 350
 popupEntry $w.toolbar.objects.menu.publish {Separate Dataset outputs*}
 check {[winfo exists $w.publishBatch]} {Objects publication opens established reviewed batch form}
 typeInto $w.publishBatch.viewport.content.field0.entry p019_time_voltage_derived
 click $w.publishBatch.actions.apply
 check {$::GX::UiField::formStatus($w.publishBatch) eq {Applied.} && {p019_time_voltage_derived} in [::GX::sessionInspectionDatasetIds]} {actual public Dataset publication creates derived time-voltage output}
 click $w.publishBatch.actions.close
 set metadata [::GX::datasetMetadataRead $session p019_time_voltage_derived]
 set publishedSchema [::GX::datasetVariableSchemaV3 p019_time_voltage_derived]
 check {[dict exists $metadata curve_workbench.provenance] && [dict get [lindex [dict get $metadata curve_workbench.provenance] 0] source] eq {time_voltage} && [string match {*source_row_ordinal*} $publishedSchema]} {published derivative retains source lineage metadata and row identity columns}
 write [file join $output derived-metadata.tcldict] $metadata
 set sourceAfter [sourcePage [::GX::CurveWorkbench::_record $w $datasetCurve]]
 foreach field {rows source_rows columns} {check {[dict get $sourceAfter $field] eq [dict get $sourcePage $field]} "immutable canonical time-voltage source unchanged: $field"}
 check {[::GX::sessionInspectionDatasetPayload time_voltage] eq $sourceBefore} {source canonical Dataset payload hash and variables remain unchanged after derived edits/publication}
 menuChoose $w.toolbar.workspace {Save*}
 set document $::GX::CurveWorkbench::st($w,document);set saved [curvePoints $derived];set savedHistory [::GX::scientificHistoryViewerStatus $w]
 set savedUnits [::GX::CurveWorkbench::_coordinateUnits [::GX::CurveWorkbench::_record $w $derived]]
 set sourceDescriptor [dict get [::GX::CurveWorkbench::_record $w $datasetCurve] source_descriptor]
 ::GX::CurveWorkbench::_close $w
 set w [::GX::viewerOpen viewer.curve_workbench curve_workbench [dict create workspace_id $document]];wm geometry $w 1480x940+20+20;pause 250
 set canvas $w.right.viewport.canvas;set scene $::GX::CurveWorkbench::st($w,scene)
 check {[dict get [::GX::CurveWorkbench::_coordinateAxis $w $derived x] display_unit] eq {s} && [dict get [::GX::CurveWorkbench::_coordinateAxis $w $derived y] display_unit] eq {V}} {reopened Workspace restores independent s and V display units}
 check {[near [curvePoints $derived] $saved] && [::GX::CurveWorkbench::_coordinateUnits [::GX::CurveWorkbench::_record $w $derived]] eq $savedUnits} {Save Close Reopen preserves independent physical units and exact derived native coordinates}
 check {[dict get [::GX::CurveWorkbench::_record $w $datasetCurve] source_descriptor] eq $sourceDescriptor && [dict get [::GX::scientificHistoryViewerStatus $w] count]==[dict get $savedHistory count]} {reopened Workspace retains original source identities and native History count}
 pause 120;shot heterogeneous-reopened
 write [file join $output source-receipt.tcldict] [dict create before $sourceBefore after [::GX::sessionInspectionDatasetPayload time_voltage] page_before $sourcePage page_after $sourceAfter]
 write [file join $output history-receipt.tcldict] [dict create saved $savedHistory reopened [::GX::scientificHistoryViewerStatus $w] branch_modals $modalEvents]
 check {$errors eq {}} {no unexpected heterogeneous GUI callback exceptions}
 write [file join $output RESULT.txt] {PASS: actual ms-mV Dataset/workspace/display/source/derived editing/physical-admission/dimension/publication/persistence workflow.}

} on error {message options} {puts stderr [dict get $options -errorinfo];if {$w ne {} && [winfo exists $w]} {catch {shot failure}};set exitStatus 1} finally {
 catch {after cancel $branchWatcher}
 write [file join $output errors.tcllist] $errors
 write [file join $output input.tcllist] $inputTrace
 if {$w ne {} && [winfo exists $w]} {catch {::GX::CurveWorkbench::_close $w}};catch {destroy .};foreach pid $wmPids {catch {exec kill -TERM -- $pid}}
}
if {[info exists exitStatus]} {exit $exitStatus};exit 0
