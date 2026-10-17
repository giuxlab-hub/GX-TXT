# Accepted names are display/provenance labels; canonical fit IDs never change.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_acceptedName {name} {
    set name [string trim $name]
    if {$name eq {}||[string length $name]>160||[regexp {[\x00-\x1f\x7f]} $name]} {error {Accepted curve name must contain 1–160 characters on one line, without control characters}}
    return $name
}
proc ::GX::DatasetCurveFit::_acceptDialog {w {batch 0}} {
    variable state
    _assertLoaded $w
    if {![_historyGuard $w]} {error {Finish the active operation before accepting}}
    if {![_commitFocusedSetting $w]} return
    _workspaceCapture $w
    if {$batch} {set ids [$w.left.viewport.content.sources.body.sources selection]} else {set ids [list $state($w,activeSource)]}
    if {$ids eq {}} {error {Select source curves with unaccepted previews}}
    set fields {};set values {};set captured {};set index 0
    foreach id $ids {
        set source [dict get $state($w,sources) $id state];set preview [dict get $source preview]
        if {$preview eq {}||[dict get $source previewAccepted]} {error "Source '$id' needs an unaccepted preview"}
        incr index;set field name$index
        dict set fields $field [dict create type string label "Curve name — $id ([dict get $preview model])" required 1]
        dict set values $field "[dict get $preview model] fit [expr {$state($w,nextFit)+$index}]"
        dict set captured $id $preview
    }
    # Opening/closing this form does not prepare a History branch or accept data.
    ::GX::uiFieldFormCreate $w.acceptName {Accept fitted curves} $fields $values [list ::GX::DatasetCurveFit::_acceptDialogApply $w $state($w,activeSource) $captured $batch] $w
    $w.acceptName.actions.apply configure -text {Accept named curves}
    $w.acceptName.actions.close configure -text Cancel
    bind $w.acceptName <Escape> [list destroy $w.acceptName]
    if {!$batch} {wm geometry $w.acceptName 650x300;$w.acceptName.actions.apply configure -text {Accept named curve}}
}
proc ::GX::DatasetCurveFit::_acceptDialogApply {w owner captured batch values} {
    variable state
    _assertLoaded $w
    if {![_historyGuard $w]||$state($w,activeSource) ne $owner} {error {Active source or operation changed; reopen Accept}}
    _workspaceCapture $w
    set names {};set index 0
    dict for {id preview} $captured {
        if {![dict exists $state($w,sources) $id]||[dict get $state($w,sources) $id state preview] ne $preview||[dict get $state($w,sources) $id state previewAccepted]} {error {The captured preview changed; reopen Accept}}
        dict set names $id [_acceptedName [dict get $values name[incr index]]]
    }
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    set state($w,historyDescription) {Accept named fitted curves}
    try {
        if {$batch} {
            set accepted [acceptSources $w [dict keys $captured] $names]
            _refreshFits $w;set state($w,status) "Accepted [llength $accepted] named curves. Publish Datasets explicitly."
            _workspaceCapture $w;_saveState $w;redraw $w
        } else {_uiAccept $w [dict get $names $owner]}
    } finally {unset -nocomplain state($w,historyDescription)}
    destroy $w.acceptName
}
