source [file join [file dirname [info script]] .. official_dev099 project_common.tcl]
try {
    set session [::GX::createNewSession worksheet_dev102]
    ::GX::modulePublicApiActivate viewer.scientific_worksheet SCIENTIFIC_WORKSHEET_API_v1
    namespace import ::GX::ScientificWorksheet::*
    proc model {method args} {tailcall ::GX::ScientificWorksheet::$method {*}$args}
    set b [model new]
    foreach {a v} {A1 4 A2 5 A3 6 B1 0.5 C1 0.75 D1 1 E1 6 E2 5 E3 4 G1 {=A1+$A$1}} {set b [model setCell $b $a $v]}
    set b [model fillRange $b A1 A6 A3]
    check {[dict get [model value $b A4] value]==7 && [dict get [model value $b A6] value]==9} {Three-row numerical seed continues 7,8,9}
    set b [model fillRange $b B1 F1 D1]
    check {[dict get [model value $b E1] value]==1.25 && [dict get [model value $b F1] value]==1.5} {Horizontal decimal fill preserves constant step}
    set b [model fillRange $b E1 E6 E3 copy]
    check {[dict get [model value $b E4] value]==1.25} {Explicit Copy Cells repeats the full seed}
    set b [model fillRange $b G1 G3]
    check {[dict get $b cells G3 source] eq {=A3+$A$1} && [dict get [model value $b G3] value]==10} {Fill relocates mixed relative and absolute formula references}
    foreach {a v} {J4 4 J5 5 J6 6} {set b [model setCell $b $a $v]}
    set b [model fillRange $b J4 J1 J6]
    check {[dict get [model value $b J1] value]==1 && [dict get [model value $b J3] value]==3} {Upward series preserves seed-relative progression}
    foreach {a v} {M8 4 N8 3 O8 2} {set b [model setCell $b $a $v]}
    set b [model fillRange $b M8 K8 O8]
    check {[dict get [model value $b K8] value]==6} {Leftward descending series follows the same mathematical sequence}
    set before $b
    check {[catch {model mergeRange $b A1 A3}] && $b eq $before} {Merge refuses nonempty subordinate cells without losing values}
    set b [model setCell $b B10 {Retained header}]
    set b [model mergeRange $b B10 D12]
    check {[dict get [model mergeAt $b C11] anchor] eq {B10}} {Rectangular merge retains stable anchor}
    check {[catch {model setCell $b C11 17}]} {Hidden subordinate editing refuses}
    set b [model mergeRange $b B10 D12 1]
    check {[model mergeAt $b C11] eq {} && [dict get [model value $b B10] value] eq {Retained header}} {Unmerge restores presentation with intact underlying content}
    set b [model setTypedCell $b B15 {kind scalar value 0.125 unit V}]
    set exact [model value $b B15]
    set b [model formatRange $b B15 D16 {category Percentage decimals 2 align right valign top wrap 1 foreground #112233 background #EEEEFF font_size 14 bold 1 italic 1 underline 1 rotation 45 border_color #008000 border_width 2 border_style dashed} outer]
    check {[model value $b B15] eq $exact && [model formatValue $exact [dict get $b styles B15]] eq {12.50%}} {Display formatting preserves exact scientific value and unit}
    set b [model setSizes $b row 2 2 63];set b [model setSizes $b column 8 8 185]
    check {[dict get $b row_heights 2]==63 && ![dict exists $b row_heights 3]} {Sparse independent row sizing preserves neighbors}
    check {[dict get [model navigationExtent $b] rows]<200 && [dict get [model navigationExtent $b ZZ999999] rows]==1000000} {Compact navigation retains distant hard capacity}
    set b [model setCell $b K20 {Merged source}]
    set b [model mergeRange $b K20 M21]
    set b [model formatRange $b K20 M21 {background #ABCDEF rotation 45} outer]
    set b [model clipboardPaste $b [model clipboardCapture $b K20 M21] N23]
    check {[dict get [model mergeAt $b O24] anchor] eq {N23} && [dict get $b styles N23 background] eq {#ABCDEF} && [dict get [model value $b N23] value] eq {Merged source}} {Typed internal clipboard preserves merged topology, style and values}
    set b [model insertRows $b 20 1]
    check {[dict get [model mergeAt $b L22] anchor] eq {K21} && [dict get $b styles K21 background] eq {#ABCDEF}} {Row insertion shifts merges and sparse styles with their original cells}
    set b [model deleteRows $b 20 1]
    check {[dict get [model mergeAt $b L21] anchor] eq {K20}} {Row deletion restores merge geometry through the existing structural owner}
    set b [model formatRange $b Q1 Q1000000 {category Scientific decimals 4 background #EEFFEE} outer]
    check {[dict size [dict get $b styles]]<100 && [llength [dict get $b range_styles]]==1 && [dict get [model styleAt $b Q999999] category] eq "Scientific" && [dict get [model navigationExtent $b] rows]<200} {Full-column formatting is sparse and does not expose a million empty rows}
    set b [model formatRange $b Q10 Q10 {decimals 2}]
    check {[dict get [model styleAt $b Q10] decimals]==2 && [dict get [model styleAt $b Q11] decimals]==4} {A cell override composes with its sparse column style}
    set b [model formatRange $b Q1 Q1000000 {foreground #AAAAAA}]
    set b [model formatRange $b Q100 Q1000000 {foreground #BBBBBB}]
    set b [model formatRange $b Q1 Q1000000 {background #CCCCCC}]
    check {[dict get [model styleAt $b Q5000] foreground] eq {#BBBBBB} && [dict get [model styleAt $b Q10] decimals]==2} {Ordered large style layers preserve intervening edits and cell overrides}
    set b [model save $b];set id [dict get $b document_id]
    set snap [model historySnapshot $b];set b [model load $id]
    check {[dict get $b styles B15 rotation]==45 && [dict get $b column_widths 8]==185 && [dict get $b row_heights 2]==63 && [model value $b B15] eq $exact} {Workbook save/load preserves style, sizing, exact values and units}
    check {[model historySnapshot $b] eq $snap} {Existing History snapshot retains the complete durable presentation}
    save result [dict create status PASS checks $checks session $session]
} on error {message options} {save result [dict create status FAIL checks $checks details [dict get $options -errorinfo]];puts stderr [dict get $options -errorinfo];exit 1}
exit
