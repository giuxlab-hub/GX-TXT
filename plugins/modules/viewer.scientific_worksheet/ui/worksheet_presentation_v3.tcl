# SPDX-License-Identifier: GPL-3.0-or-later
# UI adapters invoke the one Worksheet model and shared Viewer command owner.
proc ::GX::ScientificWorksheet::UI::actionApplicable {w id} {
    set chart [expr {[info exists ::GX::ScientificWorksheet::Charts::state($w,selected)] && $::GX::ScientificWorksheet::Charts::state($w,selected) ne {}}]
    if {[string match chart_* $id]} {return $chart}
    if {$chart && $id ni {scripts filters}} {return 0}
    lassign [selection $w] first last
    if {$id eq "merge_cells"} {return [expr {$first ne $last}]}
    if {$id eq "unmerge_cells"} {return [expr {[model mergeAt [book $w] $first] ne {}}]}
    return 1
}
proc ::GX::ScientificWorksheet::UI::chartAction {w action} {
    if {$action eq "edit"} {$w.body.inspector.tabs select $w.body.inspector.tabs.chart;return}
    ::GX::ScientificWorksheet::Charts::$action $w
}
proc ::GX::ScientificWorksheet::UI::merge {w unmerge} {
    lassign [selection $w] first last
    applyBook $w [model mergeRange [book $w] $first $last $unmerge] [expr {$unmerge?"Unmerge cells":"Merge cells"}]
}
proc ::GX::ScientificWorksheet::UI::formatDialog {w} {
    lassign [selection $w] first last
    set fields [dict create category {type choice label Category values {General Number Scientific Engineering Percentage Date Time Text Custom} default General} decimals {type integer label Decimals min 0 max 17 default 2} grouping {type boolean label {Thousands grouping} default 0} custom {type choice label {Custom format} values {0 0.0 0.00 0.000 0.00E+00 0% 0.00%} default 0.00} align {type choice label {Horizontal alignment} values {general left center right} default general} valign {type choice label {Vertical alignment} values {top middle bottom} default middle} wrap {type boolean label {Wrap text} default 0} foreground {type color label {Text color} default #233746} background {type color label Background default #FFFFFF} font_size {type integer label {Font size} min 6 max 72 default 13} bold {type boolean label Bold default 0} italic {type boolean label Italic default 0} underline {type boolean label Underline default 0} rotation {type number label {Rotation (degrees)} min -90 max 90 default 0} border_color {type color label {Border color} default #233746} border_width {type number label {Border width (px)} min 0 max 12 default 1} border_style {type choice label {Border style} values {solid dashed dotted} default solid} borders {type choice label Borders values {none all outer inner top bottom left right} default none}]
    dict set fields font_family [dict create type choice label {Available font family} values [lsort -dictionary [font families]] default [font actual TkDefaultFont -family]]
    set initial [model styleAt [book $w] $first]
    ::GX::uiFieldFormCreate $w.format "Format Cells — $first:$last" $fields $initial [list [namespace current]::formatApply $w $first $last] $w
}
proc ::GX::ScientificWorksheet::UI::formatApply {w first last values} {
    set borders [dict get $values borders];dict unset values borders
    applyBook $w [model formatRange [book $w] $first $last $values $borders] "Format $first:$last"
}
proc ::GX::ScientificWorksheet::UI::sizeDialog {w axis} {
    lassign [selection $w] first last;lassign [model rectangle $first $last] c1 r1 c2 r2
    set start [expr {$axis eq "row"?$r1:$c1}];set end [expr {$axis eq "row"?$r2:$c2}]
    set default [expr {$axis eq "row"?[setting row_height]:[setting column_width]}]
    ::GX::uiFieldFormCreate $w.size "[string totitle $axis] size" [dict create pixels [dict create type integer label {Size in device pixels} min [expr {$axis eq "row"?16:35}] max 2000 default $default]] {} [list [namespace current]::sizeApply $w $axis $start $end] $w
}
proc ::GX::ScientificWorksheet::UI::sizeApply {w axis first last values} {applyBook $w [model setSizes [book $w] $axis $first $last [dict get $values pixels]] "Resize selected ${axis}s"}
proc ::GX::ScientificWorksheet::UI::autoFit {w} {
    lassign [selection $w] first last;lassign [model rectangle $first $last] c1 r1 c2 r2
    set b [book $w];set widths {};set heights {}
    # Work is proportional to occupied cells, never nominal sheet capacity.
    dict for {address cell} [dict get $b cells] {
        lassign [model _parts $address] c r
        if {$c<$c1 || $c>$c2 || $r<$r1 || $r>$r2} continue
        set style [model styleAt $b $address]
        set size [::GX::datasetPublicationV2DictDefault $style font_size [setting font_size]]
        set family [::GX::datasetPublicationV2DictDefault $style font_family [font actual TkDefaultFont -family]]
        set description [list -family $family -size $size]
        set text [model formatValue [model value $b $address] $style]
        set measured 0;foreach line [split $text \n] {set measured [expr {max($measured,[font measure $description $line])}]}
        set currentWidth [::GX::datasetPublicationV2DictDefault [dict get $b column_widths] $c [setting column_width]]
        set wrap [::GX::datasetPublicationV2DictDefault $style wrap 0]
        set angle [::GX::datasetPublicationV2DictDefault $style rotation 0]
        set lineHeight [font metrics $description -linespace]
        set lines [expr {max(1,[llength [split $text \n]])}]
        if {$wrap} {set lines [expr {max($lines,int(ceil(double($measured)/max(1,$currentWidth-10))))}]}
        set height [expr {int(ceil(abs(sin($angle*acos(-1)/180))*$measured+abs(cos($angle*acos(-1)/180))*$lineHeight*$lines))+8}]
        dict set heights $r [expr {max([::GX::datasetPublicationV2DictDefault $heights $r 16],min(2000,$height))}]
        if {!$wrap} {dict set widths $c [expr {max([::GX::datasetPublicationV2DictDefault $widths $c 35],min(2000,$measured+12))}]}
    }
    dict for {c width} $widths {set b [model setSizes $b column $c $c $width]}
    dict for {r height} $heights {set b [model setSizes $b row $r $r $height]}
    applyBook $w $b {Auto-fit occupied selected cells}
}
proc ::GX::ScientificWorksheet::UI::filterDialog {w} {
    variable st
    set d $w.filters;if {[winfo exists $d]} {raise $d;return}
    toplevel $d;wm title $d {Presentation Filter Views};wm transient $d $w;wm geometry $d 720x640
    ttk::frame $d.actions;pack $d.actions -side bottom -fill x
    bind $d.actions <Configure> [list ::GX::uiFieldControlsLayout $d.actions %w]
    foreach {key default} {filter_name {My filter} filter_first 1 filter_last 100 filter_combine AND filter_column A filter_op contains filter_value {} filter_unit {} filter_predicates {}} {set st($w,$key) $default}
    ttk::label $d.note -wraplength 650 -text {Filters change displayed rows only. Formulas and charts keep their complete source ranges. Explicit visible-only script input records the exact row IDs.}
    pack $d.note -fill x -padx 8 -pady 6
    ttk::combobox $d.views -state readonly -values [linsert [dict keys [dict get [book $w] filter_views]] 0 {All rows}]
    bind $d.views <<ComboboxSelected>> [list [namespace current]::filterChoose $w]
    pack $d.views -fill x -padx 8
    foreach {key label} {name {Save as Filter View} first {First row} last {Last row (maximum 20000 rows)} column Column value {Value / selected values (Tcl list for in)} unit {Operand physical unit (optional)}} {
        ttk::label $d.l$key -text $label;ttk::entry $d.$key -textvariable [namespace current]::st($w,filter_$key)
        pack $d.l$key $d.$key -fill x -padx 8 -pady 2
    }
    ttk::combobox $d.op -state readonly -values {eq ne gt ge lt le contains starts in blank missing nan error boolean} -textvariable [namespace current]::st($w,filter_op)
    ttk::combobox $d.combine -state readonly -values {AND OR} -textvariable [namespace current]::st($w,filter_combine)
    pack $d.op $d.combine -fill x -padx 8
    listbox $d.criteria -height 3 -exportselection 0;pack $d.criteria -fill both -expand 1 -padx 8
    foreach {name label method} {add {Add criterion} filterAdd clear {Clear criteria} filterClear apply {Save and apply view} filterApply all {Show all rows} filterAll unique {Unique values in column} filterUnique} {ttk::button $d.actions.$name -text $label -command [list [namespace current]::safe $w $method];pack $d.actions.$name -side left -padx 3 -pady 4}
}
proc ::GX::ScientificWorksheet::UI::filterAdd {w} {variable st;set p [dict create column [string toupper $st($w,filter_column)] op $st($w,filter_op) value $st($w,filter_value) unit $st($w,filter_unit)];lappend st($w,filter_predicates) $p;$w.filters.criteria insert end $p}
proc ::GX::ScientificWorksheet::UI::filterClear {w} {variable st;set st($w,filter_predicates) {};$w.filters.criteria delete 0 end}
proc ::GX::ScientificWorksheet::UI::filterAll {w} {applyBook $w [model filterViewApply [book $w] {}] {Clear presentation filter}}
proc ::GX::ScientificWorksheet::UI::filterChoose {w} {set name [$w.filters.views get];if {$name eq {All rows}} {filterAll $w} else {applyBook $w [model filterViewApply [book $w] $name] "Filter View: $name"}}
proc ::GX::ScientificWorksheet::UI::filterApply {w} {
    variable st
    if {$st($w,filter_predicates) eq {}} {filterAdd $w}
    applyBook $w [model filterViewSave [book $w] $st($w,filter_name) $st($w,filter_first) $st($w,filter_last) $st($w,filter_predicates) $st($w,filter_combine)] "Apply Filter View $st($w,filter_name)"
    $w.filters.views configure -values [linsert [dict keys [dict get [book $w] filter_views]] 0 {All rows}]
    set view [dict get [book $w] filter_views $st($w,filter_name)]
    status $w "Presentation filter: [dict get $view visible_count] / [expr {[dict get $view last]-[dict get $view first]+1}] rows visible. Canonical values are unchanged."
}
proc ::GX::ScientificWorksheet::UI::filterUnique {w} {
    variable st
    set first $st($w,filter_first);set last $st($w,filter_last)
    if {![string is integer -strict $first] || ![string is integer -strict $last] || $first<1 || $last<$first || $last-$first>=20000} {error {Choose a bounded 1–20000-row range}}
    set column [string toupper $st($w,filter_column)];model _columnNumber $column
    set values {}
    for {set r $first} {$r<=$last} {incr r} {set item [model value [book $w] "$column$r"];dict set values [dict get $item value] 1;if {[dict size $values]>2048} {error {Unique-value picker supports 2048 distinct values; use typed predicates}}}
    set d $w.filters.unique;catch {destroy $d};toplevel $d;wm title $d {Select exact values};wm transient $d $w.filters
    ttk::entry $d.search;pack $d.search -fill x
    listbox $d.values -selectmode extended -exportselection 0 -height 15;pack $d.values -fill both -expand 1
    set st($w,unique_values) [lsort -dictionary [dict keys $values]]
    bind $d.search <KeyRelease> [list [namespace current]::filterUniqueSearch $w $d]
    ttk::button $d.apply -text {Use selected values} -command [list [namespace current]::filterUniqueApply $w $d];pack $d.apply -fill x
    filterUniqueSearch $w $d
}
proc ::GX::ScientificWorksheet::UI::filterUniqueSearch {w d} {variable st;$d.values delete 0 end;set search [string tolower [$d.search get]];foreach value $st($w,unique_values) {if {[string first $search [string tolower $value]]>=0} {$d.values insert end $value}}}
proc ::GX::ScientificWorksheet::UI::filterUniqueApply {w d} {variable st;set values {};foreach index [$d.values curselection] {lappend values [$d.values get $index]};set st($w,filter_op) in;set st($w,filter_value) $values;destroy $d;filterAdd $w}
proc ::GX::ScientificWorksheet::UI::scriptPanel {w} {
    variable st
    set p $w.body.inspector.tabs.scripts
    if {[winfo exists $p]} {$w.body.inspector.tabs select $p;return}
    ttk::frame $p -padding 4;$w.body.inspector.tabs add $p -text Scripts
    set st($w,script_name) {Worksheet script};set st($w,script_visible) 0
    ttk::label $p.label -text {Python — explicit managed Script Job};pack $p.label -fill x
    ttk::combobox $p.name -textvariable [namespace current]::st($w,script_name) -values [dict keys [dict get [book $w] scripts]];pack $p.name -fill x
    bind $p.name <<ComboboxSelected>> [list [namespace current]::safe $w scriptLoad]
    text $p.code -font TkFixedFont -width 30 -height 18 -wrap none -undo 1;pack $p.code -fill both -expand 1
    $p.code insert end "# Read a typed cell and propose a change. Apply is explicit.\nvalue = gxtxt_api_call('SCIENTIFIC_WORKSHEET_API_v1', 'inspect_cell', \[book, 'A1'\])\nprint(value)\nbook = gxtxt_api_call('SCIENTIFIC_WORKSHEET_API_v1', 'set_cell', \[book, 'B1', '42'\])\n"
    ttk::checkbutton $p.visible -text {Explicit visible-only row input} -variable [namespace current]::st($w,script_visible);pack $p.visible -fill x
    ttk::frame $p.actions;pack $p.actions -fill x
    foreach {id label method} {save Save scriptSave load Open scriptLoad run Run scriptRun stop Cancel scriptCancel apply {Apply proposal} scriptApply} {ttk::button $p.actions.$id -text $label -command [list [namespace current]::safe $w $method];pack $p.actions.$id -side left}
    bind $p.actions <Configure> [list ::GX::uiFieldControlsLayout $p.actions %w]
    text $p.logs -height 9 -width 30 -wrap word -state disabled;pack $p.logs -fill both -expand 1
    $w.body.inspector.tabs select $p
}
proc ::GX::ScientificWorksheet::UI::scriptSave {w} {variable st;set p $w.body.inspector.tabs.scripts;applyBook $w [model scriptSave [book $w] $st($w,script_name) [$p.code get 1.0 end-1c]] {Attach registered script};$p.name configure -values [dict keys [dict get [book $w] scripts]]}
proc ::GX::ScientificWorksheet::UI::scriptLoad {w} {variable st;set p $w.body.inspector.tabs.scripts;$p.code delete 1.0 end;$p.code insert end [model scriptSource [book $w] $st($w,script_name)]}
proc ::GX::ScientificWorksheet::UI::scriptRun {w} {variable st;scriptSave $w;lassign [selection $w] first last;set st($w,script_ticket) [model scriptSubmit [book $w] $st($w,script_name) $first $last $st($w,script_visible)];set st($w,script_log_offset) 0;set st($w,script_log_pending) {};set st($w,script_log_discard) 0
    set log $w.body.inspector.tabs.scripts.logs;$log configure -state normal;$log delete 1.0 end;$log configure -state disabled
    scriptPoll $w}
proc ::GX::ScientificWorksheet::UI::scriptPoll {w} {
    variable st;if {![winfo exists $w] || ![info exists st($w,script_ticket)]} return
    if {[catch {guard $w} message]} {status $w $message;return}
    set id [dict get $st($w,script_ticket) job_id];set job [::GX::scriptJobDescribe $id]
    set page [::GX::scriptJobLogRead $id $st($w,script_log_offset) 65536]
    if {[dict exists $page content]} {set p $w.body.inspector.tabs.scripts.logs;$p configure -state normal;$p insert end [scriptLogVisible $w [dict get $page content] [expr {[dict get $job state] in {COMPLETED FAILED CANCELLED CANCELED}}]];$p see end;$p configure -state disabled;set st($w,script_log_offset) [dict get $page next_offset]}
    status $w "Script Job $id: [dict get $job state]. Apply a completed proposal explicitly."
    if {[dict get $job state] ni {COMPLETED FAILED CANCELLED CANCELED}} {after 300 [list [namespace current]::scriptPoll $w]}
}
proc ::GX::ScientificWorksheet::UI::scriptCancel {w} {variable st;if {[info exists st($w,script_ticket)]} {::GX::scriptJobCancel [dict get $st($w,script_ticket) job_id]}}
proc ::GX::ScientificWorksheet::UI::scriptApply {w} {variable st;applyBook $w [model scriptCollect [book $w] $st($w,script_ticket)] {Apply script proposal}}

proc ::GX::ScientificWorksheet::UI::navigationExtent {w {address A1}} {
    variable st
    set b [book $w];set key [list [dict get $b _runtime workbook_id] [dict get $b active_sheet] [dict get $b revision]]
    if {![info exists st($w,navigationScan)] || $st($w,navigationScan) ne $key} {
        set st($w,navigationUsed) [model navigationExtent $b]
        set st($w,navigationScan) $key
    }
    set extent $st($w,navigationUsed);lassign [model _parts $address] c r
    dict set extent columns [expr {min(702,max([dict get $extent columns],$c+4))}]
    dict set extent rows [expr {min(1000000,max([dict get $extent rows],$r+20))}]
    set saved [::GX::datasetPublicationV2DictDefault [dict get [book $w] presentation] navigation_extent {}]
    foreach key {rows columns} {if {[dict exists $saved $key]} {dict set extent $key [expr {max([dict get $extent $key],[dict get $saved $key])}]}}
    dict set ::GX::ScientificWorksheet::ui($w,book) presentation navigation_extent $extent
    return $extent
}
proc ::GX::ScientificWorksheet::UI::growNavigation {w generation receipt} {
    variable st
    unset -nocomplain st($w,navigationPending)
    if {![winfo exists $w] || ![info exists st($w,generation)] || $generation!=$st($w,generation)} return
    set extent [navigationExtent $w]
    if {[dict get $receipt last_row]>=[dict get $extent rows]-5} {dict set extent rows [expr {min(1000000,[dict get $extent rows]+50)}]}
    if {[dict get $receipt last_column]>=[dict get $extent columns]-2} {dict set extent columns [expr {min(702,[dict get $extent columns]+6)}]}
    dict set ::GX::ScientificWorksheet::ui($w,book) presentation navigation_extent $extent
    [grid $w] configure -rows [dict get $extent rows] -columns [dict get $extent columns]
}
proc ::GX::ScientificWorksheet::UI::autoFitHeader {w x y} {
    set receipt [[grid $w] receipt]
    if {$x<[dict get $receipt row_header_width] || $y<[dict get $receipt header_height]} {safe $w autoFit} else {beginEdit $w}
}

proc ::GX::ScientificWorksheet::UI::columnFilter {w column} {
    variable st;filterDialog $w
    set st($w,filter_column) [::GX::ScientificWorksheet::_columnName $column]
    set used [model navigationExtent [book $w]];set st($w,filter_last) [expr {min(20000,[dict get $used rows])}]
    raise $w.filters
}

proc ::GX::ScientificWorksheet::UI::scriptLogVisible {w content terminal} {
    variable st
    set buffer "$st($w,script_log_pending)$content";set visible {}
    if {$st($w,script_log_discard)} {
        set end [string first \n $buffer]
        if {$end<0} {set st($w,script_log_pending) {};return {}}
        set buffer [string range $buffer [expr {$end+1}] end];set st($w,script_log_discard) 0
    }
    while {[set end [string first \n $buffer]]>=0} {
        set line [string range $buffer 0 [expr {$end-1}]];set buffer [string range $buffer [expr {$end+1}] end]
        if {[string match GXTXT_WORKSHEET_SCRIPT_RESULT:* $line]} {append visible "Workbook proposal received. Apply explicitly to adopt it.\n"} else {append visible [string range $line 0 8191] \n}
    }
    if {[string match GXTXT_WORKSHEET_SCRIPT_RESULT:* $buffer]} {
        append visible "Workbook proposal received. Apply explicitly to adopt it.\n";set buffer {};set st($w,script_log_discard) 1
    } elseif {[string length $buffer]>8192} {
        append visible [string range $buffer 0 8191] "\nLong diagnostic line: inspect the complete log in Jobs.\n";set buffer {};set st($w,script_log_discard) 1
    } elseif {$terminal} {append visible $buffer;set buffer {}}
    set st($w,script_log_pending) $buffer;return $visible
}
