# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output
source [file join $root validation dev111_p022 fixtures.tcl]
set checks {}
dict for {count id} $documents {
    set before [::GX::interactiveDocumentRead $id]
    set snapshot [::GX::nativeCadSketchDocumentPresentation $id mm]
    if {[dict size [dict get $snapshot layers]]!=$count} {error {Display lost retained objects}}
    set converted [::GX::nativeCadSketchDocumentPresentation $id cm]
    dict for {name layer} [dict get $snapshot layers] {
        set convertedPoints [dict get $converted layers $name vertices]
        foreach p [dict get $layer vertices] q $convertedPoints {
            foreach a $p b $q {if {abs($a*.1-$b)>1e-12} {error {Display unit conversion changed physical coordinates}}}
        }
    }
    set receipt [::GX::native3DGuiHostDocumentPresentationSet $snapshot]
    set bad $snapshot;dict set bad generation invalid_generation
    if {![catch {::GX::native3DGuiHostDocumentPresentationSet $bad} message]} {error {Stale display was accepted}}
    if {$before ne [::GX::interactiveDocumentRead $id]} {error {Display preparation modified canonical science}}
    ::GX::native3DGuiHostDocumentPresentationRemove $id
    if {[dict exists [::GX::native3DGuiHostDocumentPresentationInspect] $id]} {error {Display resource was retained after release}}
    dict set checks $count [dict create result PASS receipt $receipt stale_rejection $message source_unchanged 1]
}
set f [open [file join $output CONTRACT.tcldict] w];puts $f $checks;close $f
::GX::Engine3D::stopWorker
puts $checks
