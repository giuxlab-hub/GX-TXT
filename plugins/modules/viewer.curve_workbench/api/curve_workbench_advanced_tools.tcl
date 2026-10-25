# SPDX-License-Identifier: GPL-3.0-or-later
# Domain policy/adoption remains here; CORE owns advanced input/proposals.
proc ::GX::CurveWorkbench::_advancedCore {w} {return [[_cadCanvas $w] advanced]}
proc ::GX::CurveWorkbench::_cadCanvasAdvanced {w event} {
    variable st
    switch -- [dict get $event phase] {
        admit {
            if {![_cadCanvasGuard $w $event]} {error {Advanced CAD Session or Document lifetime is stale}}
            if {[_historyBrowsing $w]} {error {Return to editable History before advanced CAD work}}
            if {[string match constraint.* [dict get $event operation]] || [string match dimension.* [dict get $event operation]]} {return [_advancedConstraintAdmit $w $event]}
            return 1
        }
        exclude {return [expr {$st($w,toolPreview) eq {}?{}:[list $st($w,toolPreview)]}]}
        preview {
            if {[dict get $event operation] eq {construction}} {
                if {[dict get $event definition] eq {}} {_toolPreviewClear $w} else {_toolPreview $w [dict get $event definition]}
                return {handled 1}
            }
        }
        cancelled {if {[dict get $event operation] eq {construction}} {_toolPreviewClear $w;set st($w,constructionPlaces) {};set st($w,placements) {};set st($w,snapCandidate) {}}}
    }
    return {}
}
