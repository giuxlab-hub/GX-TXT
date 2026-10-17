# Source in an isolated desktop console. All opened windows belong to this Tk.
set ::catalogChecks {};set ::catalogSerial 0;set ::catalogDialogs {};set ::catalogOpenReceipts {}
proc catalogPause {ms} {set n ::catalogWait[incr ::catalogSerial];after $ms [list set $n 1];vwait $n;unset $n}
proc catalogCheck {condition label} {if {![uplevel 1 [list expr $condition]]} {error "FAIL $label"};lappend ::catalogChecks $label;record catalog_checks $::catalogChecks;puts "PASS $label";flush stdout}
proc catalogOpened {command code result op} {lappend ::catalogOpenReceipts [dict create module [lindex $command 1] viewer [lindex $command 2] code $code result $result]}
proc catalogDialogs {} {
    foreach item [widgets .] {
        lassign $item path class text
        if {![string match *.__tk__messagebox.msg $path]} continue
        set dialog [winfo parent $path]
        lappend ::catalogDialogs [list $dialog $text]
        foreach choice {no cancel ok} {if {[winfo exists $dialog.$choice]} {$dialog.$choice invoke;break}}
    }
    set ::catalogDialogAfter [after 100 catalogDialogs]
}
proc catalogWorkflow {} {
    set ::GX::cfg(output_root) [file join $::out sessions]
    set session [::GX::createNewSession catalog_acceptance]
    source [file join [file dirname [info script]] catalog_seed.tcl]
    catalogSeed [file join [pwd] _private_dev103 catalog_inputs]
    .top.nb select .top.nb.viewers
    set providers [::GX::viewerProviderCatalog];record installed_providers $providers
    catalogCheck {[llength $providers]==30} {Complete installed inventory contains thirty bundled Viewer providers}
    set hashes {};foreach provider $providers {
        set icon [dict get $provider icon_path]
        catalogCheck {$icon ne {} && [dict get $provider short_title] ne {} && [dict get $provider semantic_group] ne {}} "Descriptor supplies artwork, title and group: [dict get $provider viewer_id]"
        lappend hashes [::GX::sha256File $icon]
        set photo [::GX::viewerCatalogIcon $provider]
        catalogCheck {[image width $photo]>=48 && [image height $photo]>=48} "Native artwork meets visible size: [dict get $provider viewer_id]"
    }
    catalogCheck {[llength [lsort -unique $hashes]]==30} {Every bundled Viewer has distinct actual graphical artwork}
    catalogPause 200;capture . catalog_top
    .top.nb.viewers.viewport yview moveto .5;catalogPause 100;capture . catalog_middle
    .top.nb.viewers.viewport yview moveto 1;catalogPause 100;capture . catalog_bottom
    wm geometry . 800x600;catalogPause 150;capture . catalog_compact
    set scaling [tk scaling];set theme [ttk::style theme use]
    tk scaling 2;ttk::style theme use clam;set ::GX::ViewerCatalog::signature {};::GX::viewerGuiRefresh
    wm geometry . 1400x900;catalogPause 200
    .top.nb.viewers.viewport yview moveto 0;capture . catalog_hidpi_clam
    set maximum 0;foreach group [winfo children .top.nb.viewers.viewport.content] {foreach tile [winfo children $group] {set maximum [expr {max($maximum,[winfo x $tile]+[winfo width $tile])}]}}
    catalogCheck {$maximum<=[winfo width .top.nb.viewers.viewport]} {HiDPI responsive columns retain access to every tile}
    tk scaling $scaling;ttk::style theme use $theme;set ::GX::ViewerCatalog::signature {};::GX::viewerGuiRefresh;wm geometry . 1280x840
    # Only account-local presentation is disabled; no scientific service changes.
    set f .top.nb.configuration.sections.modules.kinds.viewers
    .top.nb select .top.nb.configuration;.top.nb.configuration.sections select .top.nb.configuration.sections.modules;.top.nb.configuration.sections.modules.kinds select $f
    $f.tree selection set viewer.replicate_curve_analysis/replicate_consensus;$f.tools.disable invoke
    catalogCheck {![::GX::viewerProviderEnabled viewer.replicate_curve_analysis replicate_consensus]} {Modules Viewer control genuinely disables protected bundled presentation}
    catalogCheck {[catch {::GX::viewerOpen viewer.replicate_curve_analysis replicate_consensus}]} {Disabled Viewer refuses a subsequent public Open}
    record persisted_disabled [exec [auto_execok tclsh] [file join $::root validation official_dev103 catalog_persist.tcl] $::root]
    set descriptor $::GX::moduleCatalog(math.numeric,descriptor);set ::GX::moduleCatalog(math.numeric,descriptor) {}
    set missing [catch {::GX::viewerProviderSetEnabled viewer.replicate_curve_analysis replicate_consensus 1} reason]
    set ::GX::moduleCatalog(math.numeric,descriptor) $descriptor
    catalogCheck {$missing} {Viewer enablement diagnoses a missing declared dependency}
    $f.tree selection set viewer.replicate_curve_analysis/replicate_consensus;$f.tools.enable invoke
    catalogCheck {[::GX::viewerProviderEnabled viewer.replicate_curve_analysis replicate_consensus] && [::GX::moduleIsEnabled math.numeric]} {Presentation re-enables while the essential scientific service remains available}
    capture . viewer_manager
    trace add execution ::GX::viewerOpen leave catalogOpened
    catalogDialogs
    set index 0
    foreach provider $providers {
        incr index
        set module [dict get $provider module_id];set viewer [dict get $provider viewer_id]
        .top.nb select .top.nb.viewers;set tile {}
        foreach group [winfo children .top.nb.viewers.viewport.content] {foreach button [winfo children $group] {if {[lrange [$button cget -command] end-1 end] eq [list $module $viewer]} {set tile $button}}}
        catalogCheck {$tile ne {}} "Installed Viewer has a real clickable catalog tile: $viewer"
        set previous [winfo children .]
        $tile invoke;catalogPause 250
        set current [winfo children .];set opened {}
        foreach window $current {if {$window ni $previous && [winfo toplevel $window] eq $window && [winfo viewable $window]} {lappend opened $window}}
        record opening_[format %02d $index] [list provider $module/$viewer result [lindex $::catalogOpenReceipts end] windows $opened dialogs $::catalogDialogs]
        set external [lindex [lindex $::catalogOpenReceipts end] end]
        if {![catch {dict get $external pid} pid]} {set external $pid}
        if {[string is integer -strict $external] && $external>1000} {
            catalogPause 2000
            set externalWindows {};catch {set externalWindows [exec xdotool search --onlyvisible --pid $external]}
            record external_[format %02d $index] [list pid $external windows $externalWindows]
            foreach xid $externalWindows {catch {exec import -window $xid [file join $::out viewer_[format %02d $index]_external_$xid.png]};catch {exec xdotool windowclose $xid}}
        }
        foreach window $opened {
            capture $window viewer_[format %02d $index]_[string map {. _} [string trimleft $window .]]
            set close [wm protocol $window WM_DELETE_WINDOW]
            if {$close eq {}} {destroy $window} else {uplevel #0 $close}
        }
        catalogPause 50
    }
    after cancel $::catalogDialogAfter
    trace remove execution ::GX::viewerOpen leave catalogOpened
    record catalog_open_receipts $::catalogOpenReceipts
    record catalog_dialogs $::catalogDialogs
    record catalog_result [dict create status PASS checks $::catalogChecks openings $::catalogOpenReceipts session $session]
}
catalogWorkflow
