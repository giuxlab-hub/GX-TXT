# SPDX-License-Identifier: GPL-3.0-or-later
# Pure public Dataset producer shared by focused Worksheet measurements.
proc worksheetFixtureDataset {session dataset rows} {
    if {![string is entier -strict $rows] || $rows<1 || $rows>20000} {error {Fixture row count must be 1–20000}}
    set plan [::GX::datasetPublicationV2Prepare $session viewer.scientific_worksheet [dict create dataset_id $dataset contract table.generic storage csv provenance {Deterministic independent source: sin(row*0.01); same values in three named Variables}]]
    set writer [::GX::datasetPublicationV2OpenWriter $plan]
    try {
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 {extendible 1}
        set values {};set generated {};for {set r 0} {$r<$rows} {incr r} {lappend generated [expr {sin($r*.01)}]}
        foreach id {source_x source_y source_auxiliary} {::GX::datasetPublicationV2DeclareVariable $writer $id [dict create dtype float64 unit V dimension_ids row];dict set values $id $generated}
        ::GX::datasetPublicationV2Append $writer row $values
        set receipt [::GX::datasetPublicationV2Finalize $writer];set writer {}
        return $receipt
    } finally {if {$writer ne {}} {::GX::datasetPublicationV2Abort $writer}}
}
