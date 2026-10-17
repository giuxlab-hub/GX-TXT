source [file join [file dirname [info script]] .. official_dev099 workspace_common.tcl]
if {$::env(DISPLAY) ne {:1}} {error {Actual Debian DISPLAY :1 required}}
set argv {};::GX::main
proc click {w} {raise [winfo toplevel $w];update;exec xdotool mousemove --sync [expr {[winfo rootx $w]+[winfo width $w]/2}] [expr {[winfo rooty $w]+[winfo height $w]/2}] click 1;pause}
proc findChoices {w} {
    set result {}
    foreach child [winfo children $w] {
        if {[winfo class $child] eq "TCombobox" && [$child cget -values] eq {Description History}} {lappend result $child}
        set result [concat $result [findChoices $child]]
    }
    return $result
}
proc run {} {
    workspaceSeed
    if {[info exists ::env(GXTXT_SELECTOR_TRACE)]} {
        proc selectorTrace {command op} {puts "TRACE $command"}
        foreach command {::GX::uiFieldSelectorPost ::GX::uiFieldSelectorClose ::GX::_uiFieldSelectorResize ::GX::_uiFieldSelectorViewerChanged ::GX::_uiFieldSelectorClick} {trace add execution $command enter selectorTrace}
    }
    foreach {module provider} {viewer.scientific_worksheet scientific_worksheet viewer.dataset_curve_fit dataset_curve_fit} {
        set w [::GX::viewerOpen $module $provider {workspace_id new}];pause 400
        wm geometry $w 850x500+20+20;raise $w;pause
        set chooser [lindex [findChoices $w] 0]
        check {$chooser ne {}} "$provider uses the genuine shared History selector"
        set documentToken [::GX::interactiveDocumentSessionToken]
        set prior [$chooser get]
        if {[info exists ::env(GXTXT_SELECTOR_TRACE)]} {puts "CHOOSER $chooser at [winfo rootx $chooser],[winfo rooty $chooser] [winfo width $chooser]x[winfo height $chooser]; viewer [winfo geometry $w] at [winfo rootx $w],[winfo rooty $w]; tags [bindtags $chooser]";exec import -window [winfo id $w] [file join $::out before_${provider}.png]}
        click $chooser;pause
        set panel [::GX::_uiFieldSelectorPanel $chooser $w]
        check {[winfo exists $panel] && [winfo viewable $panel]} "$provider real pointer opens in-Viewer options"
        check {[winfo rootx $panel]>=[winfo rootx $w] && [winfo rooty $panel]>=[winfo rooty $w] && [winfo rootx $panel]+[winfo width $panel]<=[winfo rootx $w]+[winfo width $w] && [winfo rooty $panel]+[winfo height $panel]<=[winfo rooty $w]+[winfo height $w]} "$provider list stays inside Viewer client bounds"
        check {[$chooser get] eq $prior && [::GX::interactiveDocumentSessionToken] eq $documentToken} "$provider opening does not execute a History choice"
        wm geometry $w 820x480;pause
        check {[winfo exists $panel] && [winfo rooty $panel]+[winfo height $panel]<=[winfo rooty $w]+[winfo height $w]} "$provider resizing retains options inside the Viewer"
        exec import -window [winfo id $w] [file join $::out ${provider}_selector.png]
        event generate $panel.options <Escape>;pause
        check {![winfo exists $panel] && [focus] eq $chooser} "$provider Escape closes and restores keyboard focus"
        event generate $chooser <Key-Down>;pause
        event generate $panel.options <Key-Down>;event generate $panel.options <Return>;pause
        check {![winfo exists $panel]} "$provider keyboard commits through the same combobox event"
        wm minsize $w 120 70;wm geometry $w 320x140;pause
        # A long list exercises the shared bounded scroll projection directly.
        ttk::combobox $w.testchoice -state readonly -values [lmap n {1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20} {format {Option %02d} $n}]
        place $w.testchoice -x 5 -y 55 -width 180 -height 24
        ::GX::uiFieldSelectorWithinViewer $w.testchoice $w
        click $w.testchoice;pause
        set panel [::GX::_uiFieldSelectorPanel $w.testchoice $w]
        check {[winfo height $panel]<100 && [winfo viewable $panel.scroll]} "$provider insufficient space uses bounded native scrolling"
        $panel.options see end;$panel.options selection clear 0 end;$panel.options selection set end
        event generate $panel.options <Return>;pause
        check {[$w.testchoice get] eq {Option 20}} "$provider every option remains keyboard reachable"
        destroy $w.testchoice
        destroy $w;pause
    }
    check {![info exists ::bgfailed]} {No Tk background errors}
    save result [dict create status PASS checks $::checks]
}
set failed {};set done 0
after 500 {if {[catch {run} message options]} {set ::failed [dict get $options -errorinfo];save result [dict create status FAIL checks $::checks details $::failed];puts stderr $::failed};catch {destroy .};set ::done 1}
vwait done
exit [expr {$failed ne {}}]
