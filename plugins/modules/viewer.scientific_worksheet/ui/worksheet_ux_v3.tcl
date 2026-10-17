# Scientific Worksheet presentation. CORE owns model, History and Workspace data.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::ScientificWorksheet::UI {variable st;variable clip {};variable serial 0}
source [file join [file dirname [info script]] worksheet_configuration.tcl]
proc ::GX::ScientificWorksheet::UI::safe {w method args} {if {[catch {[namespace current]::$method $w {*}$args} e]} {if {[winfo exists $w]} {status $w $e};return 0}}
proc ::GX::ScientificWorksheet::UI::model {method args} {tailcall ::GX::ScientificWorksheet::$method {*}$args}
proc ::GX::ScientificWorksheet::UI::book {w} {return $::GX::ScientificWorksheet::ui($w,book)}
proc ::GX::ScientificWorksheet::UI::status {w message} {set ::GX::ScientificWorksheet::ui($w,status) $message}
proc ::GX::ScientificWorksheet::UI::guard {w} {
 variable st
 if {![winfo exists $w] || ![info exists st($w,token)] || $st($w,token) ne [::GX::interactiveDocumentSessionToken]} {error {Session changed; reopen this Worksheet}}
 if {[llength [info commands ::GX::ScientificWorksheet::refreshBookAuthority]]} {set ::GX::ScientificWorksheet::ui($w,book) [model refreshBookAuthority [book $w]]}
 model validateBook [book $w]
 return 1
}
proc ::GX::ScientificWorksheet::UI::capture {w} {return [model historySnapshot [book $w]]}
proc ::GX::ScientificWorksheet::UI::historyValidate {record} {
 foreach field {format base steps cursor} {if {![dict exists $record $field]} {error "Worksheet History requires $field"}}
 if {[dict get $record base format] ni {scientific_worksheet.v1 scientific_worksheet.v2}} {error {History checkpoint is not a Worksheet}}
}
proc ::GX::ScientificWorksheet::UI::historyCapture {w} {return [::GX::scientificHistoryViewerRecord $w]}
proc ::GX::ScientificWorksheet::UI::historyReplay {context record} {error {Use Worksheet History navigation in its owning Session}}
proc ::GX::ScientificWorksheet::UI::historyCommit {w record} {
 variable st
 dict set ::GX::ScientificWorksheet::ui($w,book) history $record
 set st($w,historySnapshot) [capture $w]
 refresh $w {} 0
}
proc ::GX::ScientificWorksheet::UI::historyRestore {w state} {
 variable st
 set history [::GX::scientificHistoryViewerRecord $w]
 set ::GX::ScientificWorksheet::ui($w,book) [model restoreBookIdentity $state [book $w]]
 dict set ::GX::ScientificWorksheet::ui($w,book) history $history
 set st($w,historySnapshot) [capture $w]
 refresh $w {} 0
}
proc ::GX::ScientificWorksheet::UI::attachHistory {w} {
 variable st
 set history [::GX::datasetPublicationV2DictDefault [book $w] history {}]
 ::GX::scientificHistoryViewerAttach $w viewer.scientific_worksheet [dict create capture [list [namespace current]::capture $w] restore [list [namespace current]::historyRestore $w] commit [list [namespace current]::historyCommit $w] guard [list [namespace current]::historyGuard $w]] $history
 set st($w,historySnapshot) [capture $w]
}
proc ::GX::ScientificWorksheet::UI::historyGuard {w} {guard $w;return 1}
proc ::GX::ScientificWorksheet::UI::prepareEdit {w} {guard $w;return [::GX::scientificHistoryViewerPrepareEdit $w]}
proc ::GX::ScientificWorksheet::UI::applyBook {w candidate description} {
 variable st
 guard $w
 if {![prepareEdit $w]} {return 0}
 if {[dict get $candidate active_filter] ne {}} {
  set view [dict get $candidate filter_views [dict get $candidate active_filter]]
  if {![dict exists $view evaluated_revision] || [dict get $view evaluated_revision]!=[dict get $candidate revision]-1} {set candidate [model filterViewApply $candidate [dict get $candidate active_filter]]}
 }
 set before [book $w]
 try {
  set ::GX::ScientificWorksheet::ui($w,book) $candidate
  ::GX::scientificHistoryViewerChanged $w $description
 } on error {e opts} {set ::GX::ScientificWorksheet::ui($w,book) $before;refresh $w {} 0;return -options $opts $e}
 refresh $w {} 0
 return 1
}
proc ::GX::ScientificWorksheet::UI::selection {w} {
 set u ::GX::ScientificWorksheet::ui
 if {[info exists ${u}($w,selections)] && [llength [set ${u}($w,selections)]]} {return [lindex [set ${u}($w,selections)] end]}
 return [list [set ${u}($w,active)] [set ${u}($w,active)]]
}
proc ::GX::ScientificWorksheet::UI::grid {w} {return $w.body.main.grid.cells}
proc ::GX::ScientificWorksheet::UI::fetch {w widget receipt} {
 variable st
 if {[catch {guard $w} message]} {status $w $message;return {}}
 if {[dict get $receipt generation]!=$st($w,generation) || [dict get $receipt revision]!=[dict get [book $w] revision]} {return {}}
 set extent [navigationExtent $w]
 if {[dict get $receipt last_row]>=[dict get $extent rows]-5 || [dict get $receipt last_column]>=[dict get $extent columns]-2} {
  if {![info exists st($w,navigationPending)]} {set st($w,navigationPending) [after idle [list [namespace current]::growNavigation $w $st($w,generation) $receipt]]}
 }
 set first [dict get $receipt first_row];set col [dict get $receipt first_column]
 set rows [expr {[dict get $receipt last_row]-$first+1}];set cols [expr {[dict get $receipt last_column]-$col+1}]
 # Rendering asks only for a bounded exact scientific viewport, never an A:ZZ scan.
 set result [model viewportRows [book $w] [dict get $receipt row_ids] $col $cols]
 if {[info exists st($w,edit)] && $st($w,edit)} {positionEditor $w}
 set cells [dict get $result cells]
 dict for {key item} $cells {
  set value [dict get $item text]
  if {![dict exists $item style category] && [dict get $item kind] eq {scalar} && ![string is entier -strict $value] && [string is double -strict $value] && ![catch {expr {abs(double($value))<Inf}} finite] && $finite} {
   set style [setting number_format];set digits [setting display_digits]
   switch $style {General {set value [format %.*g $digits $value]} Scientific {set value [format %.*e $digits $value]} Fixed {set value [format %.*f $digits $value]}}
   dict set cells $key text $value
  }
 }
 return $cells
}
proc ::GX::ScientificWorksheet::UI::refresh {w {description {Worksheet edit}} {record 1}} {
 variable st
 if {![winfo exists $w] || ![info exists st($w,generation)]} return
 if {[catch {guard $w} message]} {status $w $message;[grid $w] configure -generation [incr st($w,generation)];return}
 if {$record && [info exists st($w,historySnapshot)] && [capture $w] ne $st($w,historySnapshot)} {::GX::scientificHistoryViewerChanged $w $description}
 set labels {};dict for {col meta} [::GX::datasetPublicationV2DictDefault [book $w] column_metadata {}] {set label $col;if {[::GX::datasetPublicationV2DictDefault $meta name {}] ne {}} {append label " · [dict get $meta name]"};if {[::GX::datasetPublicationV2DictDefault $meta unit {}] ne {}} {append label " \[[dict get $meta unit]\]"};if {[::GX::datasetPublicationV2DictDefault $meta unit_state {}] eq {mixed}} {append label { [mixed units]}};dict set labels [model _columnNumber $col] $label}
 set extent [navigationExtent $w $::GX::ScientificWorksheet::ui($w,active)]
 [grid $w] configure -columnfilters 1 -rows [dict get $extent rows] -columns [dict get $extent columns] -rowheights [dict get [book $w] row_heights] -columnwidths [dict merge [setting column_widths] [dict get [book $w] column_widths]]
 [grid $w] configure -generation $st($w,generation) -revision [dict get [book $w] revision] -hiddenrows [lsort -integer -unique [concat [dict keys [dict get [book $w] hidden_rows]] [dict keys [dict get [book $w] filter_hidden_rows]]]] -columnlabels $labels
 tabs $w
 if {[llength [info commands ::GX::ScientificWorksheet::Charts::refresh]]} {::GX::ScientificWorksheet::Charts::refresh $w}
 ::GX::sessionWorkspaceViewerTitlesRefresh
 ::GX::viewerCommandToolbarRefresh $w
 if {![info exists st($w,edit)] || !$st($w,edit)} {inspect $w}
}
proc ::GX::ScientificWorksheet::UI::inspect {w} {
 variable st
 [grid $w] reference
 set active $::GX::ScientificWorksheet::ui($w,active);set b [book $w]
 set source {};if {[dict exists $b cells $active source]} {set source [dict get $b cells $active source]}
 set st($w,original) $source;set ::GX::ScientificWorksheet::ui($w,formula) $source
 set editor $w.body.inspector.tabs.cell.scroller.content.formula
 $editor delete 1.0 end;$editor insert 1.0 $source
 set detail {};if {[catch {set detail [::GX::ScientificWorksheet::_cellInspectionText $b $active]} e]} {set detail $e}
 set t $w.body.inspector.tabs.data.scroller.content.detail;$t configure -state normal;$t delete 1.0 end;$t insert 1.0 $detail;$t configure -state disabled
 set filterStatus {}
 if {[dict get $b active_filter] ne {}} {set name [dict get $b active_filter];set view [dict get $b filter_views $name];set filterStatus " · Filter $name: [dict get $view visible_count]/[expr {[dict get $view last]-[dict get $view first]+1}] rows"}
 status $w "[model activeSheet $b] · $active · revision [dict get $b revision]$filterStatus"
}
proc ::GX::ScientificWorksheet::UI::selected {w widget receipt} {
 variable st
 if {[catch {guard $w} message]} {status $w $message;return}
 if {[dict get $receipt generation]!=$st($w,generation)} return
 if {[dict get $receipt action] eq {edit}} {beginEdit $w;return}
 if {[dict get $receipt action] eq {resize}} {set c [dict get $receipt column];applyBook $w [model setSizes [book $w] column $c $c [dict get $receipt width]] {Resize column};return}
 if {[dict get $receipt action] eq {column_filter}} {columnFilter $w [dict get $receipt column];return}
 if {[dict get $receipt action] eq {resize_row}} {set r [dict get $receipt row];applyBook $w [model setSizes [book $w] row $r $r [dict get $receipt height]] {Resize row};return}
 set r [dict get $receipt row];set c [dict get $receipt column];set br [dict get $receipt anchor_row];set bc [dict get $receipt anchor_column]
 set address "[model _columnName $c]$r";set anchor "[model _columnName $bc]$br"
 if {[dict get $receipt action] eq {fill}} {if {[catch {applyBook $w [model fillRange [book $w] "[model _columnName [dict get $receipt source_first_column]][dict get $receipt source_first_row]" $address "[model _columnName [dict get $receipt source_last_column]][dict get $receipt source_last_row]"] "Fill $anchor:$address"} e]} {status $w $e};return}
 if {[info exists st($w,picking)] && $st($w,picking)} {
  set editor $w.body.inspector.tabs.cell.scroller.content.formula
  set phase [::GX::datasetPublicationV2DictDefault $receipt phase press]
  if {$phase in {press key} || ![info exists st($w,pickMark)]} {$editor mark set gxPickStart insert;$editor mark gravity gxPickStart left;$editor mark set gxPickEnd insert;$editor mark gravity gxPickEnd right;set st($w,pickMark) 1}
  if {$address eq $anchor} {set ref $address} else {set ref "$anchor:$address"}
  $editor delete gxPickStart gxPickEnd;$editor insert gxPickStart $ref
  set ::GX::ScientificWorksheet::ui($w,formula) [string trimright [$editor get 1.0 end] \n]
  [grid $w] reference $br $bc $r $c
  if {$phase eq {release}} {set st($w,picking) 0;unset -nocomplain st($w,pickMark);lassign [model _parts $::GX::ScientificWorksheet::ui($w,active)] oldC oldR;[grid $w] select $oldR $oldC;focus $editor}
  return
 }
 if {$address ne $::GX::ScientificWorksheet::ui($w,active) && ($st($w,edit) || [dirtyEditor $w])} {if {![commit $w]} {lassign [model _parts $::GX::ScientificWorksheet::ui($w,active)] oldC oldR;$widget select $oldR $oldC;$widget see $oldR $oldC;return}}
 set ::GX::ScientificWorksheet::ui($w,active) $address
 set ::GX::ScientificWorksheet::ui($w,selections) [list [list $anchor $address]]
 if {[dict get $receipt action] eq {row}} {set ::GX::ScientificWorksheet::ui($w,selections) [list [list A$r ZZ$r]]}
 if {[dict get $receipt action] eq {column}} {set ::GX::ScientificWorksheet::ui($w,selections) [list [list [model _columnName $c]1 [model _columnName $c]1000000]]}
 if {[info exists ::GX::ScientificWorksheet::Charts::state($w,selected)]} {set ::GX::ScientificWorksheet::Charts::state($w,selected) {}}
 inspect $w
 ::GX::viewerCommandToolbarRefresh $w
 set st($w,selectionPending) 1
 after idle [list [namespace current]::selectionStatus $w $st($w,generation)]
}
proc ::GX::ScientificWorksheet::UI::selectionStatus {w generation} {
 variable st
 if {![winfo exists $w] || ![info exists st($w,generation)] || $generation!=$st($w,generation)} return
 if {!$st($w,selectionPending)} return
 set st($w,selectionPending) 0
 # Existing shared Numeric/statistical service remains the aggregate authority.
 catch {::GX::ScientificWorksheet::_uiSelectionStatus $w}
}
proc ::GX::ScientificWorksheet::UI::commit {w {direction 0}} {
 variable st
 if {[catch {
  guard $w
  if {[info exists st($w,edit)] && $st($w,edit)} {set source $st($w,direct)} else {set source [string trimright [$w.body.inspector.tabs.cell.scroller.content.formula get 1.0 end] \n]}
  set address $::GX::ScientificWorksheet::ui($w,active)
  if {$source ne $st($w,original)} {applyBook $w [model setCell [book $w] $address $source] "Edit $address"}
  set st($w,edit) 0;place forget $w.edit
  inspect $w;[grid $w] invalidate
 } message]} {status $w $message;return 0}
 if {$direction} {lassign [model _parts $address] c r;set r [expr {min(1000000,max(1,$r+$direction))}];goto $w "[model _columnName $c]$r"}
 return 1
}
proc ::GX::ScientificWorksheet::UI::cancelEdit {w} {variable st;set st($w,edit) 0;place forget $w.edit;inspect $w;focus [grid $w]}
proc ::GX::ScientificWorksheet::UI::positionEditor {w} {
 variable st
 if {![winfo exists $w.edit] || ![info exists st($w,edit)] || !$st($w,edit)} return
 lassign [model _parts $::GX::ScientificWorksheet::ui($w,active)] c r
 lassign [[grid $w] bbox $r $c] x y width height
 set viewport [[grid $w] receipt]
 if {$x<[dict get $viewport row_header_width] || $y<[dict get $viewport header_height] || $x>=[winfo width [grid $w]] || $y>=[winfo height [grid $w]]} {place forget $w.edit;return}
 place $w.edit -in [grid $w] -x [expr {$x+2}] -y [expr {$y+2}] -width [expr {$width-3}] -height [expr {$height-3}]
}
proc ::GX::ScientificWorksheet::UI::beginEdit {w {initial {}} {replace 0}} {
 variable st
 if {[catch {guard $w} e]} {status $w $e;return}
 set st($w,edit) 1;if {$replace} {set st($w,direct) $initial} else {set st($w,direct) $st($w,original)}
 positionEditor $w
 focus $w.edit;$w.edit icursor end
 if {!$replace} {$w.edit selection range 0 end}
}
proc ::GX::ScientificWorksheet::UI::typed {w value key state} {
 if {$value eq {} || ($state&12)!=0 || $key in {Return Tab Escape BackSpace Delete} || [scan $value %c]<32} return
 beginEdit $w $value 1
 return -code break
}
proc ::GX::ScientificWorksheet::UI::goto {w address} {
 set address [model _cell $address];lassign [model _parts $address] c r
 set extent [navigationExtent $w $address];[grid $w] configure -columnfilters 1 -rows [dict get $extent rows] -columns [dict get $extent columns]
 set ::GX::ScientificWorksheet::ui($w,active) $address;set ::GX::ScientificWorksheet::ui($w,selections) [list [list $address $address]]
 [grid $w] select $r $c;[grid $w] see $r $c;inspect $w;focus [grid $w]
}
proc ::GX::ScientificWorksheet::UI::clear {w} {lassign [selection $w] a b;applyBook $w [model clearRange [book $w] $a $b] "Clear $a:$b"}
proc ::GX::ScientificWorksheet::UI::fill {w direction} {lassign [selection $w] a b;applyBook $w [model fillRange [book $w] $a $b] "Fill $direction $a:$b"}
proc ::GX::ScientificWorksheet::UI::copy {w {cut 0}} {
 variable clip
 guard $w;lassign [selection $w] a b
 set clip [model clipboardCapture [book $w] $a $b]
 lassign [model _parts $a] c0 r0;lassign [model _parts $b] c1 r1
 set rows {};for {set r [expr {min($r0,$r1)}]} {$r<=[expr {max($r0,$r1)}]} {incr r} {set row {};for {set c [expr {min($c0,$c1)}]} {$c<=[expr {max($c0,$c1)}]} {incr c} {set address "[model _columnName $c]$r";if {[dict exists [book $w] cells $address source]} {lappend row [dict get [book $w] cells $address source]} else {lappend row {}}};lappend rows $row}
 set text [model tsvEncode $rows]
 set typed [binary encode base64 -maxlen 0 [encoding convertto utf-8 $clip]]
 if {[string bytelength $text]>2097152 || [string bytelength $typed]>2097152} {error {Clipboard content exceeds the 2 MiB bounded interchange limit}}
 clipboard clear -displayof $w;clipboard append -displayof $w $text
 # A real X11 clipboard target identifies typed internal data. Identical external
 # TSV cannot impersonate the captured source and trigger reference relocation.
 clipboard append -displayof $w -type application/x-gxtxt-worksheet-v2 $typed
 if {$cut} {clear $w}
}
proc ::GX::ScientificWorksheet::UI::paste {w} {
 variable clip
 guard $w;set raw [clipboard get -displayof $w];if {[string bytelength $raw]>2097152} {error {Clipboard text exceeds the 2 MiB bounded interchange limit}};set destination $::GX::ScientificWorksheet::ui($w,active)
 set internal {}
 if {![catch {clipboard get -displayof $w -type application/x-gxtxt-worksheet-v2} encoded]} {
  if {[string bytelength $encoded]>2097152} {error {Typed clipboard exceeds the 2 MiB bound}}
  if {[catch {set internal [encoding convertfrom utf-8 [binary decode base64 -strict $encoded]];dict get $internal format} format] || $format ne {scientific_worksheet.clipboard.v2}} {error {Typed Worksheet clipboard data are malformed}}
 }
 if {$internal ne {}} {set candidate [model clipboardPaste [book $w] $internal $destination]} else {
  set rows [model tsvDecode $raw];lassign [model _parts $destination] c0 r0;set candidate [book $w];set r $r0
  foreach row $rows {set c $c0;foreach source $row {set candidate [model setCell $candidate "[model _columnName $c]$r" $source];incr c};incr r}
 }
 applyBook $w $candidate "Paste at $destination"
}
proc ::GX::ScientificWorksheet::UI::tabs {w} {
 foreach child [winfo children $w.sheets] {destroy $child}
 set i 0
 foreach name [model sheetNames [book $w]] {set title $name;if {$name eq [model activeSheet [book $w]]} {set title "● $name"};ttk::button $w.sheets.s[incr i] -text $title -command [list [namespace current]::switchSheet $w $name];pack $w.sheets.s$i -side left -padx 2}
 ttk::button $w.sheets.add -text + -width 3 -command [list [namespace current]::sheetAction $w create];pack $w.sheets.add -side left
}
proc ::GX::ScientificWorksheet::UI::switchSheet {w name} {
 variable st
 if {![commit $w]} return
 set ::GX::ScientificWorksheet::ui($w,book) [model selectSheet [book $w] $name]
 set st($w,historySnapshot) [capture $w]
 refresh $w {} 0;goto $w A1
}
proc ::GX::ScientificWorksheet::UI::sheetAction {w action} {
 guard $w
 if {$action eq {delete}} {if {[tk_messageBox -parent $w -type okcancel -default cancel -message {Delete the active sheet from this Workbook? Source Datasets are preserved.}] ne {ok}} return;applyBook $w [model deleteSheet [book $w] [model activeSheet [book $w]]] {Delete sheet};return}
 set d $w.sheetName;catch {destroy $d};toplevel $d;wm title $d {Sheet name};wm transient $d $w
 ttk::entry $d.name;pack $d.name -fill x -padx 8 -pady 8
 ttk::button $d.apply -text Apply -command [list [namespace current]::sheetApply $w $action $d];pack $d.apply;focus $d.name
}
proc ::GX::ScientificWorksheet::UI::sheetApply {w action d} {
 set name [$d.name get];set active [model activeSheet [book $w]]
 switch $action {create {set b [model createSheet [book $w] $name]} rename {set b [model renameSheet [book $w] $active $name]} duplicate {set b [model duplicateSheet [book $w] $active $name]}}
 applyBook $w $b "[string totitle $action] sheet $name";destroy $d
}
proc ::GX::ScientificWorksheet::UI::current {w} {return [dict get [book $w] document_id]}
proc ::GX::ScientificWorksheet::UI::draftName {w} {return [dict get [book $w] name]}
proc ::GX::ScientificWorksheet::UI::dirty {w} {variable st;return [expr {[model scientificComparison [book $w]] ne $st($w,saved) || [dirtyEditor $w]}]}
proc ::GX::ScientificWorksheet::UI::prepare {w action} {guard $w;if {$action ne {query} && $action eq {save}} {commit $w};return 1}
proc ::GX::ScientificWorksheet::UI::save {w} {
 variable st
 guard $w;if {![commit $w]} {error {Correct or cancel the active cell edit before saving}}
 set b [model prepareSave [book $w]];set name [dict get $b name]
 if {[dict get $b document_id] eq {}} {
  set item [::GX::sessionWorkspaceCreate scientific_worksheet $name [model snapshot $b]]
  set b [model load [dict get $item workspace_id]]
 } else {::GX::sessionWorkspacePromote [dict get $b document_id] $name;set b [model refreshBookAuthority $b];set item [::GX::sessionWorkspaceUpdate [dict get $b document_id] [model snapshot $b]];set b [model load [dict get $item workspace_id]]}
 set ::GX::ScientificWorksheet::ui($w,book) $b;set st($w,saved) [model scientificComparison [book $w]]
 set st($w,historySnapshot) [capture $w];refresh $w {} 0;status $w {Workspace saved with complete retained History}
 ::GX::sessionWorkspaceViewsChanged
 return [dict get $b document_id]
}
proc ::GX::ScientificWorksheet::UI::close {w} {set callbacks [callbacks $w];::GX::sessionWorkspaceViewerAction scientific_worksheet $callbacks $w close}
proc ::GX::ScientificWorksheet::UI::discard {w} {if {[llength [info commands ::GX::ScientificWorksheet::Charts::destroy]]} {::GX::ScientificWorksheet::Charts::destroy $w};destroy $w}
proc ::GX::ScientificWorksheet::UI::callbacks {w} {return [dict create current [list [namespace current]::current $w] save [list [namespace current]::save $w] open [list [namespace current]::open] close [list [namespace current]::close $w] dirty [list [namespace current]::dirty $w] prepare [list [namespace current]::prepare $w] discard [list [namespace current]::discard $w]]}
proc ::GX::ScientificWorksheet::UI::layout {w} {
 variable st
 set visible [setting inspector]
 set panes [$w.body panes]
 if {$visible && "$w.body.inspector" ni $panes} {$w.body insert 0 $w.body.inspector -weight 0} elseif {!$visible && "$w.body.inspector" in $panes} {$w.body forget $w.body.inspector}
 if {$visible} {after idle [list [namespace current]::sash $w]}
 [grid $w] configure -fontsize [setting font_size] -rowheight [expr {max([setting row_height],[setting font_size]+8)}] -columnwidth [setting column_width] -columnwidths [dict merge [setting column_widths] [dict get [book $w] column_widths]] -rowheights [dict get [book $w] row_heights]
}
proc ::GX::ScientificWorksheet::UI::sash {w} {if {[winfo exists $w.body] && [llength [$w.body panes]]>1} {$w.body sashpos 0 [expr {min([winfo width $w]/2,[setting inspector_width])}]}}
proc ::GX::ScientificWorksheet::UI::toggleInspector {w} {setSetting inspector [expr {![setting inspector]}];layout $w}
proc ::GX::ScientificWorksheet::UI::destroyed {w actual} {variable st;if {$actual ne $w} return;if {[info exists st($w,timer)]} {after cancel $st($w,timer)};if {[info exists st($w,job)]} {catch {model operationJobStatus $st($w,job)}};if {[info exists st($w,configurationSubscription)]} {::GX::configurationUnsubscribe $st($w,configurationSubscription)};if {[info exists st($w,panes)]} {foreach pane $st($w,panes) {set tag GXWorksheetInspector$pane;foreach sequence [bind $tag] {bind $tag $sequence {}}}};array unset st "$w,*";array unset ::GX::ScientificWorksheet::ui "$w,*"}
proc ::GX::ScientificWorksheet::UI::tick {w} {variable st;if {![winfo exists $w]} return;if {[catch {guard $w} message]} {status $w $message;[grid $w] configure -generation [incr st($w,generation)]};set st($w,timer) [after 700 [list [namespace current]::tick $w]]}
proc ::GX::ScientificWorksheet::UI::open {{context {}}} {
 variable st;variable serial
 package require Tk
 ::GX::ScientificWorksheet::_requireSession
 set w .scientific_worksheet
 if {[winfo exists $w]} {
  set requested [::GX::datasetPublicationV2DictDefault $context workspace_id [::GX::datasetPublicationV2DictDefault $context document_id {}]]
  if {$context eq {} || ($requested ne {new} && $requested eq [current $w])} {raise $w;return $w}
  guard $w
  set adapter [dict get $::GX::SessionWorkspace::adapters $w]
  if {![::GX::sessionWorkspaceHostPrepare $adapter opening]} {raise $w;return $w}
  discard $w
 }
 set b [model new [::GX::datasetPublicationV2DictDefault $context workspace_name {Untitled Worksheet}]]
 set id [::GX::datasetPublicationV2DictDefault $context workspace_id [::GX::datasetPublicationV2DictDefault $context document_id {}]]
 if {$id ni {{} new}} {set b [model load $id]}
 ::GX::native2DEnsure
 toplevel $w;wm geometry $w 1100x700+30+30;wm minsize $w 700 450
 set ::GX::ScientificWorksheet::ui($w,book) $b;set ::GX::ScientificWorksheet::ui($w,active) A1;set ::GX::ScientificWorksheet::ui($w,selections) {{A1 A1}};set ::GX::ScientificWorksheet::ui($w,status) {};set ::GX::ScientificWorksheet::ui($w,formula) {}
 set st($w,token) [::GX::interactiveDocumentSessionToken];set st($w,generation) [incr serial];set st($w,edit) 0;set st($w,picking) 0;set st($w,selectionPending) 0
 set st($w,saved) [model scientificComparison [book $w]]
 menu $w.menu -tearoff 0;$w configure -menu $w.menu
 foreach {name title} {workbook Workbook edit Edit insert Insert data Data formulas Formulas view View workspace Workspace history History} {menu $w.menu.$name -tearoff 0;$w.menu add cascade -label $title -menu $w.menu.$name}
 ttk::frame $w.toolbar -padding 4;pack $w.toolbar -fill x
 foreach {name label method args} {save Save save {} undo Undo navigate undo redo Redo navigate redo functions Functions showFunctions {} inspector Inspector toggleInspector {}} {ttk::button $w.toolbar.$name -text $label -command [list [namespace current]::safe $w $method {*}$args];pack $w.toolbar.$name -side left -padx 2}
 ttk::label $w.toolbar.gotoLabel -text {Go to};ttk::entry $w.toolbar.goto -width 10;pack $w.toolbar.gotoLabel $w.toolbar.goto -side left -padx 3;bind $w.toolbar.goto <Return> [list [namespace current]::gotoEntry $w]
 ttk::panedwindow $w.body -orient horizontal;pack $w.body -fill both -expand 1
 ttk::frame $w.body.inspector -width 300;ttk::panedwindow $w.body.main -orient vertical
 $w.body add $w.body.inspector -weight 0;$w.body add $w.body.main -weight 1
 ttk::notebook $w.body.inspector.tabs;pack $w.body.inspector.tabs -fill both -expand 1
 foreach {name title} {cell {Cell & Formula} functions Functions data {Data / Lineage} chart Chart} {ttk::frame $w.body.inspector.tabs.$name -padding 6;$w.body.inspector.tabs add $w.body.inspector.tabs.$name -text $title}
 foreach pane {cell functions data} {paneScroll $w.body.inspector.tabs.$pane}
 set pane $w.body.inspector.tabs.cell.scroller.content
 ttk::label $pane.active -textvariable ::GX::ScientificWorksheet::ui($w,active);pack $pane.active -anchor w
 text $pane.formula -height 6 -width 24 -wrap word -undo 1;pack $pane.formula -fill both -expand 1
 ttk::frame $pane.actions;pack $pane.actions -fill x
 foreach {name label method} {apply Apply commit cancel Cancel cancelEdit} {ttk::button $pane.actions.$name -text $label -command [list [namespace current]::safe $w $method];pack $pane.actions.$name -side left -padx 2}
 ttk::checkbutton $pane.pick -text {Pick cell/range reference} -variable [namespace current]::st($w,picking) -command [list [namespace current]::pickStart $w];pack $pane.pick -anchor w
 ttk::button $pane.fill -text {Fill selection} -command [list [namespace current]::fill $w down];pack $pane.fill -fill x
 bind $pane.formula <FocusIn> [list [namespace current]::dockFocus $w]
 bind $pane.formula <Control-space> [list [namespace current]::autocomplete $w]
 bind $pane.formula <Control-Return> [list [namespace current]::commit $w];bind $pane.formula <Escape> [list [namespace current]::cancelEdit $w]
 set pane $w.body.inspector.tabs.data.scroller.content;text $pane.detail -width 25 -height 12 -wrap word -state disabled;pack $pane.detail -fill both -expand 1
 foreach {name label callback} {columns {Columns / Ranges…} _uiNamesDialog bind {Bind Dataset…} _uiImportDialog sort {Sort / Filter…} _uiSortFilter unit {Convert Unit…} _uiConvertDialog} {ttk::button $pane.$name -text $label -command [list [namespace current]::legacy $w $callback];pack $pane.$name -fill x -pady 2}
 ttk::frame $w.body.main.grid;ttk::frame $w.body.main.charts
 $w.body.main add $w.body.main.grid -weight 3;$w.body.main add $w.body.main.charts -weight 2
 ::GX::native2DVirtualGridCreate [grid $w] [dict create -generation $st($w,generation) -revision [dict get $b revision] -fetchcommand [list [namespace current]::fetch $w] -command [list [namespace current]::selected $w] -xscrollcommand [list $w.body.main.grid.x set] -yscrollcommand [list $w.body.main.grid.y set]]
 ttk::scrollbar $w.body.main.grid.x -orient horizontal -command [list [grid $w] xview];ttk::scrollbar $w.body.main.grid.y -orient vertical -command [list [grid $w] yview]
 ::grid [grid $w] -row 0 -column 0 -sticky nsew;::grid $w.body.main.grid.y -row 0 -column 1 -sticky ns;::grid $w.body.main.grid.x -row 1 -column 0 -sticky ew;::grid rowconfigure $w.body.main.grid 0 -weight 1;::grid columnconfigure $w.body.main.grid 0 -weight 1
 ttk::entry $w.edit -textvariable [namespace current]::st($w,direct)
 bind $w.edit <Return> "[list [namespace current]::commit $w 1];break";bind $w.edit <Escape> "[list [namespace current]::cancelEdit $w];break";bind $w.edit <Tab> "[list [namespace current]::editTab $w 1];break";bind $w.edit <Shift-Tab> "[list [namespace current]::editTab $w -1];break"
 bind [grid $w] <Double-1> [list [namespace current]::autoFitHeader $w %x %y];bind [grid $w] <KeyPress> [list [namespace current]::typed $w %A %K %s]
 foreach {event method args} {<Control-c> copy {} <Control-x> copy 1 <Control-v> paste {} <Delete> clear {}} {bind [grid $w] $event "[list [namespace current]::safe $w $method {*}$args];break"}
 bind [grid $w] <Control-a> "[list [namespace current]::selectUsed $w];break"
 menu $w.context -tearoff 0;foreach {label method} {Copy copy Paste paste Clear clear {Fill down} fill} {$w.context add command -label $label -command [list [namespace current]::safe $w $method {*}[expr {$method eq {fill}?{down}:{}}]]};bind [grid $w] <Button-3> [list [namespace current]::context $w %x %y %X %Y]
 ttk::frame $w.sheets -padding 2;pack $w.sheets -before $w.body -side bottom -fill x
 ttk::label $w.status -textvariable ::GX::ScientificWorksheet::ui($w,status) -wraplength 850 -anchor w;pack $w.status -fill x -padx 6 -pady 3
 attachHistory $w
 ttk::frame $w.description;pack $w.description -before $w.body -side bottom -fill x
 ::GX::scientificHistoryViewerStrip $w $w.description $w.status module.viewer.scientific_worksheet.configuration.history_strip {-fill x}
 ::GX::sessionWorkspaceViewerMenu $w.menu.workspace scientific_worksheet [callbacks $w] $w
 ::GX::sessionWorkspaceViewerTitle $w {Scientific Worksheet} [list [namespace current]::current $w] [list [namespace current]::draftName $w]
 menus $w;functionsPane $w
 bind $w.body <ButtonRelease-1> [list [namespace current]::sashSaved $w]
 set handlers [dict create save [list [namespace current]::save $w] undo [list [namespace current]::navigate $w undo] redo [list [namespace current]::navigate $w redo] fill_down [list [namespace current]::fill $w down] fill_right [list [namespace current]::fill $w right] recalculate [list [namespace current]::recalculate $w] functions [list [namespace current]::showFunctions $w]]
 dict for {id command} $handlers {dict set handlers $id [dict create command $command]}
 foreach {id method args} {format_cells formatDialog {} merge_cells merge 0 unmerge_cells merge 1 row_size sizeDialog row column_size sizeDialog column autofit autoFit {} filters filterDialog {} scripts scriptPanel {} chart_edit chartAction edit chart_publish chartAction publish chart_remove chartAction remove} {
  dict set handlers $id [dict create command [list [namespace current]::safe $w $method {*}$args] applicable [list [namespace current]::actionApplicable $w $id]]
 }
 ::GX::viewerCommandsAttach $w viewer.scientific_worksheet $handlers [list [namespace current]::commandGuard $w] [list [grid $w]]
 if {[llength [info commands ::GX::ScientificWorksheet::Charts::attach]]} {::GX::ScientificWorksheet::Charts::attach $w $w.body.main.charts $w.body.inspector.tabs.chart}
 if {[llength [info commands ::GX::documentationBrowserAttachViewerHelp]]} {::GX::documentationBrowserAttachViewerHelp viewer.scientific_worksheet scientific_worksheet $w}
 ttk::frame $w.toolbar.context;pack $w.toolbar.context -side left -fill x -expand 1
 ::GX::viewerGuiActionsMount $w $w.toolbar.context {format_cells merge_cells unmerge_cells row_size column_size autofit filters scripts chart_edit chart_publish chart_remove}
 foreach id {format_cells merge_cells unmerge_cells row_size column_size autofit filters scripts} {::GX::viewerCommandMenuAdd $w $w.menu.edit $id;::GX::viewerCommandMenuAdd $w $w.context $id}
 wm protocol $w WM_DELETE_WINDOW [list [namespace current]::close $w]
 bind $w <Destroy> +[list [namespace current]::destroyed $w %W]
 set st($w,configurationSubscription) [::GX::configurationSubscribe [list [namespace current]::configurationChanged $w]]
 refresh $w {} 0;layout $w;tick $w
 return $w
}
proc ::GX::ScientificWorksheet::UI::legacy {w method args} {
 if {[catch {guard $w;model $method $w {*}$args} e]} {status $w $e}
}
proc ::GX::ScientificWorksheet::UI::navigate {w action} {variable st;guard $w;if {$st($w,edit) || [dirtyEditor $w]} {status $w {Apply or cancel the cell editor before navigating History};return};::GX::scientificHistoryViewerNavigate $w $action}
proc ::GX::ScientificWorksheet::UI::dirtyEditor {w} {
 variable st
 if {$st($w,edit)} {return [expr {$st($w,direct) ne $st($w,original)}]}
 return [expr {[string trimright [$w.body.inspector.tabs.cell.scroller.content.formula get 1.0 end] \n] ne $st($w,original)}]
}
proc ::GX::ScientificWorksheet::UI::pickStart {w} {
 variable st
 if {$st($w,picking)} {dockFocus $w;focus $w.body.inspector.tabs.cell.scroller.content.formula}
}
proc ::GX::ScientificWorksheet::UI::dockFocus {w} {
 variable st
 if {![info exists st($w,edit)] || !$st($w,edit)} return
 set editor $w.body.inspector.tabs.cell.scroller.content.formula
 $editor delete 1.0 end;$editor insert 1.0 $st($w,direct)
 set st($w,edit) 0;place forget $w.edit
}
proc ::GX::ScientificWorksheet::UI::commandGuard {w} {if {[catch {guard $w}]} {return 0};return 1}
proc ::GX::ScientificWorksheet::UI::recalculate {w} {guard $w;model recalculateWorkbook [book $w];refresh $w {Recalculate Workbook};status $w {Workbook recalculated through its scientific model}}
proc ::GX::ScientificWorksheet::UI::gotoEntry {w} {if {[catch {goto $w [$w.toolbar.goto get]} e]} {status $w $e}}
proc ::GX::ScientificWorksheet::UI::selectUsed {w} {
 set c 1;set r 1;foreach address [dict keys [dict get [book $w] cells]] {lassign [model _parts $address] cc rr;set c [expr {max($c,$cc)}];set r [expr {max($r,$rr)}]}
 set ::GX::ScientificWorksheet::ui($w,selections) [list [list A1 "[model _columnName $c]$r"]];[grid $w] select $r $c 1 1
 status $w "Selected populated extent A1:[model _columnName $c]$r; bounded operations enforce their documented limits"
}
proc ::GX::ScientificWorksheet::UI::context {w x y rootX rootY} {
 set cell [[grid $w] hit $x $y];if {[llength $cell]==2} {lassign $cell r c;goto $w "[model _columnName $c]$r"}
 tk_popup $w.context $rootX $rootY
}
proc ::GX::ScientificWorksheet::UI::structural {w method} {
 lassign [model _parts $::GX::ScientificWorksheet::ui($w,active)] col row
 set index [expr {[string match *Rows $method]?$row:$col}]
 if {[catch {applyBook $w [model $method [book $w] $index 1] "$method at $index"} e]} {status $w $e}
}
proc ::GX::ScientificWorksheet::UI::menus {w} {
 foreach {label method args} {{Save Workspace} save {} {Open Workspaces…} workspaceManager {} {Close} close {}} {$w.menu.workbook add command -label $label -command [list [namespace current]::safe $w $method {*}$args]}
 foreach {label method args} {Undo navigate undo Redo navigate redo Copy copy {} Cut copy 1 Paste paste {} Clear clear {} {Fill down} fill down {Fill right} fill right} {$w.menu.edit add command -label $label -command [list [namespace current]::safe $w $method {*}$args]}
 foreach {label method} {{Insert row} insertRows {Delete row} deleteRows {Insert column} insertColumns {Delete column} deleteColumns} {$w.menu.insert add command -label $label -command [list [namespace current]::structural $w $method]}
 foreach {label action} {{New sheet…} create {Rename sheet…} rename {Duplicate sheet…} duplicate {Delete sheet} delete} {$w.menu.insert add command -label $label -command [list [namespace current]::sheetAction $w $action]}
 foreach {label method} {{Bind Dataset…} _uiImportDialog {Columns / Ranges…} _uiNamesDialog {Sort / Filter…} _uiSortFilter {Convert Unit…} _uiConvertDialog} {$w.menu.data add command -label $label -command [list [namespace current]::legacy $w $method]}
 $w.menu.data add command -label {Publish Dataset…} -command [list [namespace current]::legacy $w _uiPlotDialog dataset]
 $w.menu.data add command -label {Charts / Publish…} -command [list [namespace current]::showCharts $w]
 $w.menu.formulas add command -label {Functions and guided operations} -command [list [namespace current]::showFunctions $w]
 $w.menu.formulas add command -label {Recalculate Workbook} -command [list [namespace current]::recalculate $w]
 $w.menu.formulas add command -label {Automatic / manual mode} -command [list [namespace current]::calculationMode $w]
 $w.menu.view add command -label {Show / hide left inspector} -command [list [namespace current]::toggleInspector $w]
 $w.menu.view add command -label {Description / History strip} -command [list ::GX::scientificHistoryViewerStripToggle $w]
 $w.menu.view add command -label {Viewer configuration…} -command [list ::GX::configurationModuleDialog viewer.scientific_worksheet $w]
 $w.menu.view add command -label {Reset layout} -command [list [namespace current]::resetLayout $w]
 foreach {label action} {Undo undo Redo redo Previous previous Next next {Return to latest} latest {Branch / Restart here…} branch} {$w.menu.history add command -label $label -command [list [namespace current]::navigate $w $action]}
 $w.menu.history add command -label {Details / Timeline…} -command [list ::GX::scientificHistoryViewerDetails $w]
 $w.menu.history add command -label {Clear History…} -command [list [namespace current]::clearHistory $w]
}
proc ::GX::ScientificWorksheet::UI::workspaceManager {w} {::GX::sessionWorkspaceDialog $w scientific_worksheet [callbacks $w]}
proc ::GX::ScientificWorksheet::UI::clearHistory {w} {if {[current $w] eq {}} {status $w {Save the Workspace before clearing its History};return};::GX::scientificHistoryViewerClear $w [current $w]}
proc ::GX::ScientificWorksheet::UI::calculationMode {w} {set b [book $w];dict set b options calculation_mode [expr {[dict get $b options calculation_mode] eq {automatic}?{manual}:{automatic}}];dict incr b revision;applyBook $w $b {Change calculation mode}}
proc ::GX::ScientificWorksheet::UI::resetLayout {w} {foreach {key value} {inspector 1 inspector_width 300 font_size 13 row_height 25 column_width 110} {setSetting $key $value};layout $w}
proc ::GX::ScientificWorksheet::UI::showCharts {w} {
 guard $w
 if {![setting inspector]} {setSetting inspector 1;layout $w}
 $w.body.inspector.tabs select $w.body.inspector.tabs.chart
}
proc ::GX::ScientificWorksheet::UI::showFunctions {w} {$w.body.inspector.tabs select $w.body.inspector.tabs.functions}
proc ::GX::ScientificWorksheet::UI::functionsPane {w} {
 variable st
 set p $w.body.inspector.tabs.functions.scroller.content
 ttk::entry $p.search -textvariable [namespace current]::st($w,query);pack $p.search -fill x
 listbox $p.list -height 7 -width 25 -exportselection 0;pack $p.list -fill both -expand 1
 text $p.help -width 25 -height 5 -wrap word -state disabled;pack $p.help -fill both -expand 1
 ttk::button $p.insert -text {Insert formula} -command [list [namespace current]::insertFunction $w];pack $p.insert -fill x
 ttk::button $p.recover -text {Recover saved scientific Job} -command [list [namespace current]::recoverJob $w];pack $p.recover -fill x
 ttk::frame $p.operation;pack $p.operation -fill both -expand 1
 bind $p.search <KeyRelease> [list [namespace current]::functionSearch $w]
 bind $p.list <<ListboxSelect>> [list [namespace current]::functionSelect $w]
 set st($w,query) {};functionSearch $w
}
proc ::GX::ScientificWorksheet::UI::functionSearch {w} {
 variable st
 set p $w.body.inspector.tabs.functions.scroller.content
 if {[catch {set st($w,catalog) [model functionCatalog $st($w,query)]} e]} {status $w $e;return}
 $p.list delete 0 end;set st($w,functionNames) [lsort -dictionary [dict keys $st($w,catalog)]]
 foreach name $st($w,functionNames) {$p.list insert end $name}
}
proc ::GX::ScientificWorksheet::UI::functionSelect {w} {
 variable st
 set p $w.body.inspector.tabs.functions.scroller.content;set n [lindex [$p.list curselection] 0];if {$n eq {}} return
 set name [lindex $st($w,functionNames) $n];set st($w,function) $name
 $p.help configure -state normal;$p.help delete 1.0 end;$p.help insert 1.0 [model functionHelp $name];$p.help configure -state disabled
 guidedPane $w $name [dict get $st($w,catalog) $name]
}
proc ::GX::ScientificWorksheet::UI::insertFunction {w} {
 variable st;if {![info exists st($w,function)]} return
 set editor $w.body.inspector.tabs.cell.scroller.content.formula;$w.body.inspector.tabs select $w.body.inspector.tabs.cell
 if {[string trim [$editor get 1.0 end]] eq {}} {$editor insert 1.0 =}
 $editor insert insert "$st($w,function)(";focus $editor
}
proc ::GX::ScientificWorksheet::UI::guidedPane {w name meta} {
 set p $w.body.inspector.tabs.functions.scroller.content.operation
 catch {destroy $w.body.inspector.tabs.functions.scroller.content.operation.editor};ttk::frame $w.body.inspector.tabs.functions.scroller.content.operation.editor;set d $w.body.inspector.tabs.functions.scroller.content.operation.editor
 pack $d -fill both -expand 1
 set u ::GX::ScientificWorksheet::ui
 set ${u}($w,apply_token) [::GX::interactiveDocumentSessionToken];unset -nocomplain ${u}($w,apply_preview)
 set ${u}($w,apply_name) $name;set ${u}($w,apply_count) 0
 if {[::GX::datasetPublicationV2DictDefault $meta worksheet_category formula] eq {unavailable}} {ttk::label $d.unavailable -text [dict get $meta worksheet_reason] -wraplength 240;pack $d.unavailable;return}
 set args [::GX::datasetPublicationV2DictDefault $meta arguments {}]
 if {$args eq {} && [dict exists $meta operands]} {set args [split [dict get $meta operands] ,]}
 foreach arg $args {
  if {$arg in {{} options model callback}} continue
  set n [set ${u}($w,apply_count)];incr ${u}($w,apply_count)
  set ${u}($w,apply_$n) [expr {$arg eq {session}?{@session}:{}}]
  ttk::label $d.l$n -text $arg;ttk::entry $d.e$n -textvariable ${u}($w,apply_$n);pack $d.l$n $d.e$n -fill x
 }
 foreach {key default} {apply_options {} apply_field {} apply_model_kind {} apply_model_fields {} apply_first_row 1 apply_row_count {}} {set ${u}($w,$key) $default}
 set ${u}($w,apply_destination) [set ${u}($w,active)]
 if {[dict exists $meta model_kinds]} {set ${u}($w,apply_model_kind) [lindex [dict get $meta model_kinds] 0];ttk::combobox $d.modelkind -state readonly -values [dict get $meta model_kinds] -textvariable ${u}($w,apply_model_kind);ttk::entry $d.modelfields -textvariable ${u}($w,apply_model_fields);pack $d.modelkind $d.modelfields -fill x}
 foreach {field label variable} {options Options apply_options field {Result field} apply_field firstrow {First result row} apply_first_row rowcount {Result row count} apply_row_count dest {Output cell} apply_destination} {
  ttk::label $d.l_$field -text $label
  if {$field eq {field}} {ttk::combobox $d.$field -textvariable ${u}($w,$variable)} else {ttk::entry $d.$field -textvariable ${u}($w,$variable)}
  pack $d.l_$field $d.$field -fill x
 }
 ttk::button $d.preview -text {Preview fields} -command [list [namespace current]::guidedPreview $w]
 ttk::button $d.apply -text {Apply result} -command [list [namespace current]::guidedApply $w]
 ttk::button $d.cancel -text {Cancel operation} -command [list [namespace current]::guidedCancel $w]
 pack $d.preview $d.apply $d.cancel -fill x -pady 2
}
# Stable presentation entrypoints used by retained scientific adapters. No Tcl
# rename/override chain is created; model code calls this final UI authority.
proc ::GX::ScientificWorksheet::_uiRefresh {w} {::GX::ScientificWorksheet::UI::refresh $w}
proc ::GX::ScientificWorksheet::_uiSelect {w} {::GX::ScientificWorksheet::UI::inspect $w}
proc ::GX::ScientificWorksheet::_uiRemember {w} {::GX::ScientificWorksheet::UI::prepareEdit $w}
proc ::GX::ScientificWorksheet::_uiUndo {w} {::GX::ScientificWorksheet::UI::navigate $w undo}
proc ::GX::ScientificWorksheet::_uiRedo {w} {::GX::ScientificWorksheet::UI::navigate $w redo}
proc ::GX::ScientificWorksheet::_uiError {w message} {::GX::ScientificWorksheet::UI::status $w $message}
proc ::GX::ScientificWorksheet::_uiFunctionBrowser {w} {::GX::ScientificWorksheet::UI::showFunctions $w}
proc ::GX::ScientificWorksheet::_uiSetSelection {w a b additive} {set ::GX::ScientificWorksheet::ui($w,selections) [list [list $a $b]]}
proc ::GX::ScientificWorksheet::_uiDrawSelection {w} {}
proc ::GX::ScientificWorksheet::_uiTabs {w} {::GX::ScientificWorksheet::UI::tabs $w}
proc ::GX::ScientificWorksheet::_uiCommit {w} {::GX::ScientificWorksheet::UI::commit $w}
proc ::GX::ScientificWorksheet::_uiImportDialog {w} {
 ::GX::ScientificWorksheet::_workbookImportDialog $w
 set columns {};for {set n 1} {$n<=702} {incr n} {lappend columns [::GX::ScientificWorksheet::_columnName $n]}
 $w.import.start configure -values $columns -state normal
}
# The Dataset picker is preserved from the existing scientific adapter by its
# statically named implementation, not a runtime procedure rename.

::GX::scientificRecipeHostRegister viewer.scientific_worksheet [dict create capture ::GX::ScientificWorksheet::UI::historyCapture validate ::GX::ScientificWorksheet::UI::historyValidate replay ::GX::ScientificWorksheet::UI::historyReplay]
set chartFile [file join [file dirname [info script]] worksheet_charts_v4.tcl]
if {[file isfile $chartFile]} {source $chartFile}
proc ::GX::ScientificWorksheet::UI::setting {key} {return [dict get [::GX::configurationResolve module.viewer.scientific_worksheet.configuration.$key] effective]}
proc ::GX::ScientificWorksheet::UI::setSetting {key value} {::GX::configurationCommit [list [dict create id module.viewer.scientific_worksheet.configuration.$key scope session value $value session_token [::GX::_configurationSessionToken]]]}
proc ::GX::ScientificWorksheet::UI::configurationChanged {w id} {
 variable st
 if {![winfo exists $w] || ![info exists st($w,token)] || [catch {::GX::interactiveDocumentSessionToken} token] || $st($w,token) ne $token} return
 if {![dict exists [::GX::configurationFields] module.viewer.scientific_worksheet.configuration.inspector]} return
 if {$id eq {} || [string match module.viewer.scientific_worksheet.configuration.* $id]} {layout $w}
}
proc ::GX::ScientificWorksheet::UI::editTab {w direction} {if {![commit $w]} return;lassign [model _parts $::GX::ScientificWorksheet::ui($w,active)] c r;set c [expr {max(1,min(702,$c+$direction))}];goto $w "[model _columnName $c]$r"}
proc ::GX::ScientificWorksheet::UI::guidedPreview {w {apply 0}} {
 variable st
 if {[catch {
  guard $w
  lassign [model _uiOperationInputs $w] inputs options declarative
  set key [model _uiOperationKey $w $inputs $options $declarative]
  if {[info exists st($w,job)]} {set existing [model operationJobStatus $st($w,job)];if {[dict get $existing state] ni {COMPLETED CANCELLED FAILED ABORTED}} {error {A scientific Job is already active; cancel it before starting another}}}
  set st($w,job) [model operationJobSubmit [book $w] $::GX::ScientificWorksheet::ui($w,apply_name) $inputs $options $declarative]
  dict set ::GX::ScientificWorksheet::ui($w,book) managed_operation_tickets [dict get $st($w,job) job_id] $st($w,job)
  set st($w,jobKey) [model _uiOperationKey $w $inputs $options $declarative];set st($w,applyWhenReady) $apply
  set st($w,jobWindow) [winfo id $w.body.inspector.tabs.functions.scroller.content.operation.editor]
  status $w "Scientific Job [dict get $st($w,job) job_id] submitted; progress and logs are retained by CORE Jobs"
  after 150 [list [namespace current]::guidedPoll $w $st($w,generation) [dict get $st($w,job) job_id]]
 } e]} {status $w $e}
}
proc ::GX::ScientificWorksheet::UI::guidedPoll {w generation jobId} {
 variable st
 if {![winfo exists $w] || ![info exists st($w,generation)] || $generation!=$st($w,generation) || ![info exists st($w,job)] || [dict get $st($w,job) job_id] ne $jobId} return
 if {[catch {
  guard $w
  set state [model operationJobStatus $st($w,job)];set phase [dict get $state state]
  status $w "Scientific Job $jobId · $phase · Cancel is available in the Functions pane"
  if {$phase eq {COMPLETED}} {
   if {![winfo exists $w.body.inspector.tabs.functions.scroller.content.operation.editor] || [winfo id $w.body.inspector.tabs.functions.scroller.content.operation.editor]!=$st($w,jobWindow)} {error {Operation editor changed; retained Job output was not applied}}
   lassign [model _uiOperationInputs $w] inputs options declarative
   if {[model _uiOperationKey $w $inputs $options $declarative] ne $st($w,jobKey)} {error {Workbook or operation inputs changed; retained Job output was not applied}}
   set raw [model operationJobResult [book $w] $st($w,job)]
   set fields [model _resultFieldPaths $raw]
   $w.body.inspector.tabs.functions.scroller.content.operation.editor.field configure -values $fields
   if {[llength $fields]==1} {set ::GX::ScientificWorksheet::ui($w,apply_field) [lindex $fields 0]}
   status $w "Captured result fields: [join $fields {, }]. Select a field and Apply; the estimator will not run again."
   if {$st($w,applyWhenReady)} {guidedApply $w}
  } elseif {$phase ni {CANCELLED FAILED ABORTED INTERRUPTED}} {after 150 [list [namespace current]::guidedPoll $w $generation $jobId]}
 } e]} {status $w $e}
}
proc ::GX::ScientificWorksheet::UI::guidedApply {w} {
 variable st
 if {![info exists st($w,job)]} {guidedPreview $w 1;return}
 if {[catch {
  guard $w
  if {![prepareEdit $w]} return
  lassign [model _uiOperationInputs $w] inputs options declarative
  if {[model _uiOperationKey $w $inputs $options $declarative] ne $st($w,jobKey)} {error {Operation inputs changed after capture; preview the current inputs before applying}}
  set destination $::GX::ScientificWorksheet::ui($w,apply_destination);set field $::GX::ScientificWorksheet::ui($w,apply_field)
  if {$field eq {}} {error {Preview and select a captured result field before applying}}
  lassign [model operationJobCollect [book $w] $st($w,job) $destination $field [model _uiResultWindow $w]] candidate raw
  applyBook $w $candidate "Apply $::GX::ScientificWorksheet::ui($w,apply_name) at $destination"
  status $w "Applied captured scientific result at $destination; original source data are unchanged"
  unset st($w,job)
 } e]} {status $w $e}
}
proc ::GX::ScientificWorksheet::UI::guidedCancel {w} {variable st;if {[info exists st($w,job)]} {if {[catch {model operationJobCancel $st($w,job)} e]} {status $w $e} else {status $w {Scientific Job cancellation requested through CORE Jobs; no cells were changed}}}}
proc ::GX::ScientificWorksheet::UI::paneScroll {pane} {
 canvas $pane.scroller -highlightthickness 0 -width 260
 ttk::scrollbar $pane.bar -command [list $pane.scroller yview]
 $pane.scroller configure -yscrollcommand [list $pane.bar set]
 ttk::frame $pane.scroller.content
 $pane.scroller create window 0 0 -window $pane.scroller.content -anchor nw -tags content
 pack $pane.bar -side right -fill y;pack $pane.scroller -fill both -expand 1
 bind $pane.scroller <Configure> [list [namespace current]::paneResize $pane]
 bind $pane.scroller.content <Configure> [list [namespace current]::paneResize $pane]
 set tag GXWorksheetInspector$pane
 bind $tag <Button-4> [format {if {[::GX::ScientificWorksheet::UI::paneWheel %s %%W -1]} {break}} [list $pane]]
 bind $tag <Button-5> [format {if {[::GX::ScientificWorksheet::UI::paneWheel %s %%W 1]} {break}} [list $pane]]
 bind $tag <MouseWheel> [format {if {[::GX::ScientificWorksheet::UI::paneWheelDelta %s %%W %%D]} {break}} [list $pane]]
 set window [winfo toplevel $pane]
 bind $window <Map> +[list [namespace current]::inspectorMapped $pane %W]
 variable st;lappend st($window,panes) $pane
}
proc ::GX::ScientificWorksheet::UI::paneResize {pane} {if {![winfo exists $pane.scroller]} return;$pane.scroller itemconfigure content -width [winfo width $pane.scroller];$pane.scroller configure -scrollregion [list 0 0 [winfo width $pane.scroller] [winfo reqheight $pane.scroller.content]]}
proc ::GX::ScientificWorksheet::UI::sashSaved {w} {if {![winfo exists $w.body] || [llength [$w.body panes]]<2} return;set width [$w.body sashpos 0];if {$width>=140&&$width<=1200} {setSetting inspector_width $width}}
proc ::GX::ScientificWorksheet::UI::recoverJob {w} {
 variable st
 if {[catch {
  guard $w
  set tickets [::GX::datasetPublicationV2DictDefault [book $w] managed_operation_tickets {}]
  if {$tickets eq {}} {error {No saved scientific Job ticket is present in this Workspace}}
  set ticket [dict get $tickets [lindex [dict keys $tickets] end]]
  set st($w,job) [model operationJobRecover [book $w] $ticket]
  set name [dict get $ticket operation];set catalog [model functionCatalog $name]
  guidedPane $w $name [dict get $catalog $name]
  set n 0;foreach value [dict get $ticket inputs] {set ::GX::ScientificWorksheet::ui($w,apply_$n) $value;incr n}
  set options {};dict for {key value} [dict get $ticket options] {lappend options "$key=$value"}
  set ::GX::ScientificWorksheet::ui($w,apply_options) [join $options { }]
  set declarative [dict get $ticket model]
  if {$declarative ne {}} {set ::GX::ScientificWorksheet::ui($w,apply_model_kind) [dict get $declarative kind];set fields {};dict for {key value} [dict remove $declarative kind] {lappend fields "$key=$value"};set ::GX::ScientificWorksheet::ui($w,apply_model_fields) [join $fields { }]}
  set st($w,jobWindow) [winfo id $w.body.inspector.tabs.functions.scroller.content.operation.editor]
  lassign [model _uiOperationInputs $w] inputs options declarative
  set st($w,jobKey) [model _uiOperationKey $w $inputs $options $declarative]
  set st($w,applyWhenReady) 0
  guidedPoll $w $st($w,generation) [dict get $st($w,job) job_id]
 } e]} {status $w $e}
}
proc ::GX::ScientificWorksheet::UI::autocomplete {w} {
 set editor $w.body.inspector.tabs.cell.scroller.content.formula
 set prefixText [$editor get 1.0 insert]
 if {![regexp {([A-Za-z_][A-Za-z0-9_.]*)$} $prefixText unused prefix]} return
 set matches {};foreach name [concat [dict keys [model functionCatalog $prefix]] [dict keys [dict get [book $w] ranges]] [dict keys [dict get [book $w] columns]] [model sheetNames [book $w]]] {if {[string first $prefix $name]==0} {lappend matches $name}}
 set matches [lsort -unique $matches]
 if {[llength $matches]==1} {set name [lindex $matches 0];$editor delete "insert-[string length $prefix]c" insert;$editor insert insert $name} else {status $w "Completions: [join [lrange $matches 0 9] {, }]"}
 return -code break
}
proc ::GX::ScientificWorksheet::UI::inspectorMapped {pane widget} {
 if {![winfo exists $pane.scroller.content] || ![string match $pane.scroller.content.* $widget]} return
 set tag GXWorksheetInspector$pane;set tags [bindtags $widget]
 if {$tag ni $tags} {bindtags $widget [linsert $tags 1 $tag]}
}
proc ::GX::ScientificWorksheet::UI::paneWheel {pane widget direction} {
 if {![winfo exists $pane.scroller] || ![winfo exists $widget]} {return 0}
 if {[winfo class $widget] in {Text Listbox}} {
  if {![catch {$widget yview} view] && [llength $view]==2 && (($direction<0&&[lindex $view 0]>0)||($direction>0&&[lindex $view 1]<1))} {return 0}
 }
 $pane.scroller yview scroll [expr {$direction*3}] units
 return 1
}
proc ::GX::ScientificWorksheet::UI::paneWheelDelta {pane widget delta} {if {$delta==0} {return 0};return [paneWheel $pane $widget [expr {$delta>0?-1:1}]]}
