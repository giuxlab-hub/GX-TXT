source [file join $::root validation session_generator_dev109 batch2_manager_helpers.tcl]
proc metadataProbe {} {
    set w .gxNewSession
    click $w.buttons.generate;settle
    click $w.generator.actions.manage;settle
    set c $w.manager.split.catalog
    set lt $c.libraries.list.table
    set gt $c.generators.list.table
    nativeRow $lt org.giuxlab.gxtxt.numerical_examples;settle
    nativeRow $gt linear_regression;settle
    set before [::GX::sessionGeneratorLibraryIds]
    click $c.libActions.create;settle
    clearEntryNative $w.createLibrary.e0 {SYNTHETIC_BATCH2_MANAGER_PROBE}
    clearEntryNative $w.createLibrary.e1 {Disposable metadata and selection refresh fixture; no scientific generation.}
    click $w.createLibrary.buttons.create;settle
    set added {}
    foreach id [::GX::sessionGeneratorLibraryIds] {if {$id ni $before} {lappend added $id}}
    check batch2_one_fixture {[llength $added]==1}
    set new [lindex $added 0]
    record batch2_fixture [::GX::sessionGeneratorLibraryInfo $new]
    managerState $w empty_library_after_create_refresh
    check batch2_empty_generator_cache_cleared {[$gt selection] eq {} && ![info exists ::GX::sessionGeneratorGui($w,manager_generator)]}
    set i $w.manager.split.inspector
    nativeTab $i {Library metadata}
    clearEntryNative $i.metadata.meta.e0 {SYNTHETIC_BATCH2_MANAGER_RENAMED}
    clearEntryNative $i.metadata.meta.e1 {Edited through the actual metadata controls; source and generator identities remain intact.}
    click $i.metadata.meta.save;settle
    check batch2_metadata_saved {[dict get [::GX::sessionGeneratorLibraryInfo $new] name] eq {SYNTHETIC_BATCH2_MANAGER_RENAMED}}
    managerState $w metadata_refresh
    check batch2_metadata_refresh_identity {[$lt selection] eq $new && [$gt selection] eq {} && ![info exists ::GX::sessionGeneratorGui($w,manager_generator)]}
    capture $w batch2_metadata_saved
    nativeTab $i Details
    capture $w batch2_empty_library_details
    record batch2_probe_complete [dict create deselection_result NOT_REPRODUCED selection_mode [$lt cget -selectmode] fixture $new]
    click $w.buttons.cancel
}
openNew metadataProbe
