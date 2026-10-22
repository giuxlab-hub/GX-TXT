# One exact signed spool request. Ordinary Session chooser, approved No/Yes and five-facet routes, close.
source [file join [file dirname [dict get $::ready10 request_source]] native10.tcl]
proc ::qa420::chooseSession10 {} {
    if {[catch {
        set top .__tk_choosedir;set entry $top.contents.f2.ent
        for {set i 0} {$i<50 && (![winfo exists $entry] || ![winfo ismapped $entry])} {incr i} {pause 100}
        check {[winfo exists $entry] && [winfo ismapped $entry] && [wm title $top] eq {Open GX-TXT session}} {Expected normal Session chooser unavailable}
        capture Session_chooser $top
        click $entry;key $entry Home shift+End BackSpace
        input type --clearmodifiers -- [dict get $::ready10 session]
        check {[$entry get] eq [dict get $::ready10 session]} {Typed normal Session chooser path differs}
        key $entry Return;pause
        if {[winfo exists $entry] && [winfo ismapped $entry]} {key $entry Return}
    } m o]} {set ::chooserFailure10 [dict create message $m options $o]}
}
set chooserFailure10 {}
::qa420::tab .top.nb .top.nb.sessionfiles
# Map the menu before scheduling the blocking chooser watcher: activation's
# event-loop pause must not start the watcher before the actual menu click.
::qa420::click .top.nb.sessionfiles.bar.session
set menu10 .top.nb.sessionfiles.bar.session.menu;set row10 -1
for {set i 0} {$i<=[$menu10 index end]} {incr i} {
    if {[$menu10 type $i] ne {separator} && [$menu10 entrycget $i -label] eq {Open Session...}} {set row10 $i}
}
::qa420::check {$row10>=0 && [winfo ismapped $menu10]} {Normal Open Session menu row unavailable}
set y10 [$menu10 yposition $row10]
set bottom10 [expr {$row10<[$menu10 index end]?[$menu10 yposition [expr {$row10+1}]]:[winfo height $menu10]-2}]
::qa420::record Session_menu [dict create menu $menu10 index $row10 command_readonly [$menu10 entrycget $row10 -command]]
after 80 ::qa420::chooseSession10
::qa420::input mousemove [expr {[winfo rootx $menu10]+min(60,[winfo width $menu10]/2)}] [expr {[winfo rooty $menu10]+($y10+$bottom10)/2}] click 1
::qa420::pause 500
if {$chooserFailure10 ne {}} {error $chooserFailure10}
if {$::GX::currentSession ne [dict get $::ready10 session]} {error {Normal chooser opened wrong Session}}
desktopRecord10 SESSION_CHOOSER [dict create session $::GX::currentSession inputs $::qa420::inputs]
::qa420::init $::root [dict get $::ready10 out] $::approval $::approvalSha
foreach phase10 [dict get $::ready10 phase_order] {
    ::qa420::run $phase10
    if {$::failed10} {error {Background failure preserved; stop before further input}}
}
set native10 {}
foreach library [info loaded] {
    if {[string tolower [lindex $library 1]] ne {gx2dtcl}} continue
    set path [file normalize [lindex $library 0]]
    ::qa420::check {$path eq [file join $::root core native2d bin gx2dtcl.so] && [hash10 $path] eq [dict get $::ready10 source_files core/native2d/bin/gx2dtcl.so]} {Actual GUI Native2D owner differs}
    lappend native10 [dict create path $path sha256 [hash10 $path]]
}
::qa420::check {[llength $native10]==1} {Actual GUI pinned Native2D library unavailable}
::qa420::record actual_native $native10
::qa420::capture root_before_normal_close .
::qa420::key . alt+F4
return {AFTER_REQUEST_COMPLETED_MAIN_REVIEW_REQUIRED}
