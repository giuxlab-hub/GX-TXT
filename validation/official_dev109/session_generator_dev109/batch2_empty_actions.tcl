source [file join $::root validation session_generator_dev109 batch2_manager_helpers.tcl]
proc unexpectedDialog {} {
    foreach row [widgets .] {
        set d [lindex $row 0]
        if {[winfo toplevel $d] ne $d || $d eq {.gxNewSession} || ![winfo ismapped $d]} continue
        set ::unexpectedManagerDialog [list title [wm title $d] widgets [widgets $d]]
        record batch2_unexpected_dialog_[clock microseconds] $::unexpectedManagerDialog
        capture $d batch2_unexpected_dialog_[clock microseconds]
        foreach button [list $d.no $d.contents.f2.cancel $d.cancel $d.ok] {
            if {[winfo exists $button]} {click $button;return}
        }
    }
}
proc noOpAction {w button label} {
    set ::unexpectedManagerDialog {}
    after 300 unexpectedDialog
    click $button
    settle;settle
    check batch2_empty_action_$label {$::unexpectedManagerDialog eq {}}
    managerState $w empty_action_$label
}
proc emptyActions {} {
    set w .gxNewSession
    click $w.buttons.generate;settle
    click $w.generator.actions.manage;settle
    set c $w.manager.split.catalog
    set lt $c.libraries.list.table
    set gt $c.generators.list.table
    set fixture {}
    foreach id [::GX::sessionGeneratorLibraryIds] {if {[string match user.synthetic-batch2-manager-probe.* $id]} {set fixture $id}}
    nativeRow $lt $fixture;settle
    nativeRow $gt linear_regression;settle
    # Normal library change yields an actual empty generator selection.
    nativeRow $lt org.giuxlab.gxtxt.numerical_examples;settle
    check batch2_real_empty_selection {[$gt selection] eq {} && ![info exists ::GX::sessionGeneratorGui($w,manager_generator)]}
    set before [::GX::sha256File [dict get [::GX::sessionGeneratorLibraryInfo $fixture] descriptor]]
    set ids [::GX::sessionGeneratorLibraryIds]
    noOpAction $w $c.genActions.export export
    noOpAction $w $c.genActions.remove remove
    nativeTab $w.manager.split.inspector {Copy generator}
    noOpAction $w $w.manager.split.inspector.copy.add.copy copy
    check batch2_empty_actions_preserve_registry {[::GX::sessionGeneratorLibraryIds] eq $ids}
    check batch2_empty_actions_preserve_metadata {[::GX::sha256File [dict get [::GX::sessionGeneratorLibraryInfo $fixture] descriptor]] eq $before}
    capture $w batch2_empty_actions
    record batch2_empty_actions_complete NOT_REPRODUCED_NO_STALE_MANAGER_ACTION
    click $w.buttons.cancel
}
openNew emptyActions
