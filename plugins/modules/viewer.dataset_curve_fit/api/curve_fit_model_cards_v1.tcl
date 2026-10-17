# Read-only workflow documentation. Numerical algorithms and statistical
# interpretation remain with their existing public owners, named by each card.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::modelCards {} {
    variable root
    set path [file join $root plugins modules viewer.dataset_curve_fit model_cards_v1.tsv]
    set f [::open $path r];fconfigure $f -encoding utf-8
    set cards {};set seen {}
    try {
        while {[gets $f line]>=0} {
            if {$line eq {}||[string index $line 0] eq "#"} continue
            set values [split $line \t]
            if {[llength $values]!=12} {error {Malformed Fitter documentation card}}
            set card [dict create schema gxtxt.fitter_model_card.v1 documentation_only 1]
            foreach field {model_id label equation parameters domain method initialization solver uncertainty extrapolation source_owner statistics_model_id} value $values {
                if {$value eq {}||[string length $value]>4096} {error {Empty or oversized Fitter documentation field}}
                dict set card $field $value
            }
            set id [dict get $card model_id]
            if {![regexp {^[a-z][a-z0-9_]*$} $id]||[dict exists $seen $id]} {error {Invalid or duplicate Fitter documentation identity}}
            dict set seen $id 1
            set descriptor [::GX::StatisticsV1::model [dict get $card statistics_model_id]]
            dict set card statistical_profile [dict get $descriptor profile]
            dict set card statistical_label [dict get $descriptor label]
            lappend cards $card
        }
    } finally {::close $f}
    return $cards
}
proc ::GX::DatasetCurveFit::_modelCardDetails {w} {
    variable state
    set d $w.modelCard;catch {destroy $d}
    toplevel $d;wm title $d {Model documentation};wm transient $d $w
    set cards {};foreach card [modelCards] {dict set cards [dict get $card model_id] $card}
    set state($d,model) $state($w,model)
    ttk::combobox $d.model -values [dict keys $cards] -state readonly -textvariable ::GX::DatasetCurveFit::state($d,model) -width 32
    text $d.text -wrap word -width 92 -height 29 -yscrollcommand [list $d.scroll set]
    ttk::scrollbar $d.scroll -command [list $d.text yview]
    grid $d.model -row 0 -column 0 -sticky w -padx 8 -pady 8
    grid $d.text -row 1 -column 0 -sticky nsew;grid $d.scroll -row 1 -column 1 -sticky ns
    grid rowconfigure $d 1 -weight 1;grid columnconfigure $d 0 -weight 1
    bind $d.model <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_modelCardRender $d $cards]
    bind $d <Escape> [list destroy $d]
    _modelCardRender $d $cards;focus $d.text
}
proc ::GX::DatasetCurveFit::_modelCardRender {d cards} {
    variable state
    set card [dict get $cards $state($d,model)]
    set text "[dict get $card label]\n\nU and V denote the chosen independent and response units. Functional equations use fit-space coordinates; the scientific report retains physical-coordinate translations and inverse mapping. Parametric X/Y retain their own axis units.\n"
    foreach {field title} {equation Equation parameters {Parameter meanings and units} domain {Valid domain} method Method initialization Initialization solver {Solver and assumptions} uncertainty {Uncertainty and diagnostics} extrapolation Extrapolation} {
        append text "\n$title\n[dict get $card $field]\n"
    }
    append text "\nCORE statistical profile: [dict get $card statistical_profile] ([dict get $card statistics_model_id]).\n\nThis card documents the method. The retained scientific report is authoritative for the actual data, constraints, solver result and available uncertainty."
    $d.text configure -state normal;$d.text delete 1.0 end;$d.text insert end $text;$d.text configure -state disabled
}
