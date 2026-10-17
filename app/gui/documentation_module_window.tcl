# SPDX-License-Identifier: GPL-3.0-or-later
# Independent read-only hosts share the existing descriptor index and renderer.
# This state contains widgets/navigation only, never a second document store.
namespace eval ::GX::DocumentationManual {variable state;array set state {}}
proc ::GX::documentationBrowserModuleManual {module} {
    set descriptor [moduleField $module descriptor {}]
    if {$descriptor eq {}} {error "Module '$module' is not installed; its manual is unavailable."}
    documentationBrowserRefresh
    foreach kind {manual guide quick_start} {
        set id module:$module:$kind
        if {[dict exists $::GX::documentationBrowserEntries $id]} {
            set entry [dict get $::GX::documentationBrowserEntries $id]
            return $entry
        }
    }
    error "[moduleField $module name $module] does not declare an available rendered user manual."
}
proc ::GX::documentationBrowserManualPathAllowed {module path} {
    set descriptor [moduleField $module descriptor {}]
    if {$descriptor eq {}} {error {The manual's module is no longer installed.}}
    set path [file normalize $path];set root [file normalize [file dirname $descriptor]]
    if {[file exists $path] && [file type $path] eq {link}} {error {Linked documentation files are unsupported.}}
    if {![file isfile $path] || [string tolower [file extension $path]] ni {.md .markdown .txt}} {error {The requested rendered document is missing or has an unsupported format.}}
    if {[string first "$root/" "$path/"]==0} {return $path}
    # Public framework documentation is the same installed documentation tree
    # used by the main browser; links never reach arbitrary installation files.
    set publicRoot [file normalize [file join $::GX::scriptDir docs]]
    if {[string first "$publicRoot/" "$path/"]==0} {return $path}
    # A declared reference can also resolve through a registered API descriptor.
    set d [parseIni $descriptor]
    foreach api [splitList [descriptorValue $d documentation api_refs {}]] {
        set id api:$api
        if {[dict exists $::GX::documentationBrowserEntries $id] && [dict get $::GX::documentationBrowserEntries $id path] eq $path} {return $path}
    }
    error {The requested link is outside this module's documentation and declared API references.}
}
proc ::GX::documentationBrowserOpenModuleWindow {module {parent {}}} {
    variable ::GX::DocumentationManual::state
    set w .gxManual_[binary encode hex [encoding convertto utf-8 $module]]
    if {[winfo exists $w]} {raise $w;focus $w.search.entry;return $w}
    toplevel $w;wm title $w "[moduleField $module name $module] — User Manual"
    uiFieldWindowFit $w 900 700;wm minsize $w 420 300
    # A manual survives its Viewer closing; it is deliberately not transient.
    set state($w,module) $module;set state($w,path) {};set state($w,back) {};set state($w,forward) {};set state($w,search) {};set state($w,status) {}
    ttk::frame $w.navigation
    foreach {key label command} [list back Back [list documentationBrowserManualHistory $w back] forward Forward [list documentationBrowserManualHistory $w forward] home {User Manual} [list documentationBrowserManualReload $w] close Close [list destroy $w]] {
        set callback [expr {[lindex $command 0] eq "destroy"?"destroy":"::GX::[lindex $command 0]"}]
        # Command prefixes remain ordinary lists; no manual text is evaluated.
        ttk::button $w.navigation.$key -text $label -command [list $callback {*}[lrange $command 1 end]]
        pack $w.navigation.$key -side left -padx 3
    }
    pack $w.navigation -side top -fill x -padx 6 -pady 6
    ttk::frame $w.search
    ttk::label $w.search.label -text Find
    ttk::entry $w.search.entry -textvariable ::GX::DocumentationManual::state($w,search)
    ttk::button $w.search.next -text {Find next} -command [list ::GX::documentationBrowserManualSearch $w]
    pack $w.search.label -side left -padx 4;pack $w.search.next -side right;pack $w.search.entry -fill x -expand 1
    pack $w.search -side top -fill x -padx 6
    ttk::label $w.status -textvariable ::GX::DocumentationManual::state($w,status) -anchor w -wraplength 820
    pack $w.status -side bottom -fill x -padx 6 -pady 5
    ttk::frame $w.body;pack $w.body -fill both -expand 1 -padx 6 -pady 5
    text $w.body.text -wrap word -state disabled -font TkDefaultFont -yscrollcommand [list $w.body.scroll set]
    ttk::scrollbar $w.body.scroll -command [list $w.body.text yview]
    pack $w.body.scroll -side right -fill y;pack $w.body.text -fill both -expand 1
    bind $w <Escape> [list destroy $w]
    bind $w <F1> [list raise $w]
    bind $w <Control-f> [list focus $w.search.entry]
    bind $w.search.entry <Return> [list ::GX::documentationBrowserManualSearch $w]
    bind $w <Destroy> [list ::GX::documentationBrowserManualDestroyed $w %W]
    bind $w <Configure> [list ::GX::documentationBrowserManualResize $w %W %w]
    documentationBrowserManualReload $w
    return $w
}
proc ::GX::documentationBrowserManualDestroyed {w actual} {
    if {$w ne $actual} return
    array unset ::GX::DocumentationManual::state "$w,*"
}
proc ::GX::documentationBrowserManualResize {w actual width} {
    if {$w eq $actual && [winfo exists $w.status]} {$w.status configure -wraplength [expr {max(100,$width-18)}]}
}
proc ::GX::documentationBrowserManualUnavailable {w message} {
    set ::GX::DocumentationManual::state($w,status) $message
    markupRenderStringToWidget $w.body.text "# User manual unavailable\n\n$message"
    documentationBrowserManualEnable $w
}
proc ::GX::documentationBrowserManualReload {w} {
    variable ::GX::DocumentationManual::state
    if {![winfo exists $w]} return
    if {[catch {set entry [documentationBrowserModuleManual $state($w,module)];documentationBrowserManualShow $w [dict get $entry path]} message]} {documentationBrowserManualUnavailable $w $message}
}
proc ::GX::documentationBrowserManualShow {w path {anchor {}} {record 1}} {
    variable ::GX::DocumentationManual::state
    set path [documentationBrowserManualPathAllowed $state($w,module) $path]
    set id {}
    dict for {key entry} $::GX::documentationBrowserEntries {if {[dict get $entry path] eq $path} {set id $key;break}}
    if {$id eq {}} {
        set id "linked:$state($w,module):[sha256File $path]"
        documentationBrowserAdd $id {Linked document} [file tail $path] linked $path $state($w,module)
    }
    set source [documentationBrowserRead $id]
    if {$record && $state($w,path) ne {} && $state($w,path) ne $path} {lappend state($w,back) $state($w,path);set state($w,forward) {}}
    set state($w,path) $path;set state($w,status) "[moduleField $state($w,module) name $state($w,module)] — [file tail $path]"
    set text $w.body.text
    foreach tag [$text tag names] {if {[string match gx_manual_* $tag]} {$text tag delete $tag}}
    markupRenderStringToWidget $text $source
    # Relative links use this host's path/history, never the main Help state.
    set display [$text get 1.0 end-1c];set at 0;set number 0
    while {[regexp -indices -start $at {\[[^]]+\]\([^)]+\)} $display range]} {
        lassign $range first last
        if {[regexp {\[[^]]+\]\(([^)]+)\)} [string range $display $first $last] -> target] && {gx_codeblock} ni [$text tag names "1.0 + $first chars"]} {
            set tag gx_manual_link_[incr number]
            $text tag add $tag "1.0 + $first chars" "1.0 + [expr {$last+1}] chars"
            $text tag configure $tag -foreground #145da0 -underline 1
            $text tag bind $tag <Button-1> [list ::GX::documentationBrowserManualFollow $w $target]
        }
        set at [expr {$last+1}]
    }
    $text see 1.0
    if {$anchor ne {}} {documentationBrowserManualAnchor $w $anchor}
    documentationBrowserManualEnable $w
}
proc ::GX::documentationBrowserManualEnable {w} {
    variable ::GX::DocumentationManual::state
    foreach key {back forward} {$w.navigation.$key state [expr {[llength $state($w,$key)]?"!disabled":"disabled"}]}
}
proc ::GX::documentationBrowserManualHistory {w direction} {
    variable ::GX::DocumentationManual::state
    if {![llength $state($w,$direction)]} return
    set path [lindex $state($w,$direction) end]
    set other [expr {$direction eq "back"?"forward":"back"}]
    set previous $state($w,path)
    if {[catch {documentationBrowserManualShow $w $path {} 0} message]} {set state($w,status) $message;return}
    # Show has validated the destination; only then advance the navigation lists.
    lappend state($w,$other) $previous
    set state($w,$direction) [lrange $state($w,$direction) 0 end-1]
    documentationBrowserManualEnable $w
}
proc ::GX::documentationBrowserManualFollow {w target} {
    variable ::GX::DocumentationManual::state
    if {![winfo exists $w]} return
    if {[regexp {^https?://} $target]} {markupOpenWebLink $target;return}
    if {[regexp {^[A-Za-z][A-Za-z0-9+.-]*:} $target] || [file pathtype [lindex [split $target #] 0]] eq {absolute}} {set state($w,status) {Unsupported or unsafe link scheme.};return}
    lassign [split $target #] relative anchor
    if {$relative eq {}} {documentationBrowserManualAnchor $w $anchor;return}
    set state($w,historyFrom) $state($w,path)
    if {[catch {documentationBrowserManualShow $w [file join [file dirname $state($w,path)] $relative] $anchor} message]} {set state($w,status) $message}
}
proc ::GX::documentationBrowserManualAnchor {w anchor} {
    set text $w.body.text
    set label [string map {- { } _ { }} $anchor]
    set index [$text search -nocase -exact -- $label 1.0]
    if {$index eq {}} {set index [$text search -exact -- "id=\"$anchor\"" 1.0]}
    if {$index ne {}} {$text see $index} else {set ::GX::DocumentationManual::state($w,status) "Anchor unavailable: $anchor"}
}
proc ::GX::documentationBrowserManualSearch {w} {
    variable ::GX::DocumentationManual::state
    set text $w.body.text;set query $state($w,search)
    $text tag remove gx_manual_find 1.0 end
    if {$query eq {}} return
    set start [expr {[lsearch -exact [$text mark names] gxManualFind]>=0?[$text index gxManualFind]:"1.0"}]
    set at [$text search -nocase -exact -- $query $start end]
    if {$at eq {}} {set at [$text search -nocase -exact -- $query 1.0 end]}
    if {$at eq {}} {set state($w,status) {Text not found.};return}
    set end "$at + [string length $query] chars"
    $text tag add gx_manual_find $at $end;$text tag configure gx_manual_find -background #ffe48a -foreground black
    $text mark set gxManualFind $end;$text see $at
    set state($w,status) "Found: $query"
}
proc ::GX::documentationBrowserAttachViewerHelp {module viewer window} {
    if {[llength [info commands ::GX::viewerGuiWindowHelpRequested]] && ![viewerGuiWindowHelpRequested $window]} {return}
    if {![llength [info commands winfo]] || [llength $window]!=1 || ![winfo exists $window] || [winfo toplevel $window] ne $window || [winfo class $window] ne {Toplevel}} return
    if {$module eq {viewer.curve_digitizer}} return
    # Respect an existing plugin-local Help/F1 adapter. The generic dispatcher
    # only attaches to a normal Tk Viewer window returned by the public owner.
    set binding [bind $window <F1>]
    if {$binding ne {} && ![string match *documentationBrowserOpenModule* $binding]} return
    if {![catch {documentationBrowserModuleManual $module}]} {set available normal} else {set available disabled}
    set menu [$window cget -menu];set help {};set row {}
    # Legacy Viewers often use a row of native menubuttons instead of a Tk
    # window menubar. Attach to that row, preserving its original menu owners.
    if {$menu eq {} || $menu eq "$window.gxManualMenu"} {
        set best 0
        foreach frame [winfo children $window] {
            if {[winfo class $frame] ni {Frame TFrame}} continue
            set count 0
            foreach button [winfo children $frame] {
                if {[winfo class $button] in {Menubutton TMenubutton} && [winfo manager $button] ne {}} {incr count}
            }
            if {$count>$best} {set row $frame;set best $count}
        }
        if {$row eq {}} {
            # A legacy Viewer may expose only action buttons in its main row.
            # Keep Help in that horizontal row rather than inventing a menubar.
            foreach frame [winfo children $window] {
                if {[winfo class $frame] ni {Frame TFrame} || ![regexp {(toolbar|actions|buttons|head|tools|bar)$} [file tail $frame]]} continue
                set count 0
                foreach button [winfo children $frame] {
                    if {[winfo class $button] ni {Button TButton}} continue
                    set manager [winfo manager $button]
                    if {($manager eq {pack} && [dict get [pack info $button] -side] in {left right}) || ($manager eq {grid} && [dict get [grid info $button] -row]==0)} {incr count}
                }
                if {$count>$best} {set row $frame;set best $count}
            }
        }
    }
    if {$row ne {}} {
        foreach button [winfo children $row] {
            if {[winfo class $button] in {Menubutton TMenubutton} && [string equal -nocase [$button cget -text] Help]} {
                set help [$button cget -menu];set helpButton $button;break
            }
        }
        if {$help eq {}} {
            set helpButton $row.gxHelp
            set help $helpButton.menu
            ttk::menubutton $helpButton -text Help -menu $help
            menu $help -tearoff 0
        }
        if {[grid slaves $row] ne {}} {
            uiFieldControlsAppend $row $helpButton
        } else {
            pack forget $helpButton
            pack $helpButton -side left -padx 3
            uiMenuRowAppend $row $helpButton
        }
        if {$menu eq "$window.gxManualMenu"} {$window configure -menu {};destroy $menu}
    } else {
        if {$menu eq {}} {set menu $window.gxManualMenu;menu $menu -tearoff 0;$window configure -menu $menu}
        set end [$menu index end]
        if {$end ne {none}} {for {set index 0} {$index<=$end} {incr index} {
            if {[$menu type $index] eq {cascade} && [string equal -nocase [$menu entrycget $index -label] Help]} {
                set help [$menu entrycget $index -menu]
                if {$index!=$end} {_uiMenuCopyEntry $menu $index $menu;$menu delete $index}
                break
            }
        }}
        if {$help eq {}} {
            set help $window.gxManualHelp
            menu $help -tearoff 0
            $menu add cascade -label Help -menu $help
        }
    }
    set manual 0;set about 0;set end [$help index end]
    if {$end ne {none}} {for {set index 0} {$index<=$end} {incr index} {
        if {[$help type $index] ni {command cascade}} continue
        set label [$help entrycget $index -label]
        if {[regexp -nocase {user manual} $label]} {set manual 1}
        if {[regexp -nocase {^about} $label]} {set about 1}
    }}
    if {!$manual} {$help add command -label {User Manual…} -accelerator F1 -state $available -command [list ::GX::documentationBrowserOpenModuleWindow $module $window]}
    if {!$about} {$help add command -label {About Module…} -command [list ::GX::documentationBrowserAboutModule $module $viewer $window]}
    bind $window <F1> [list ::GX::documentationBrowserOpenModuleWindow $module $window]
}

proc ::GX::documentationBrowserAboutModule {module viewer parent} {
    set descriptor [moduleField $module descriptor {}]
    if {$descriptor eq {}} {error {The module is no longer installed}}
    set data [parseIni $descriptor]
    set text "[descriptorValue $data meta name $module]\nModule: $module\nViewer: $viewer\nVersion: [descriptorValue $data meta version {}]\n\n[descriptorValue $data meta description {}]"
    foreach field {author license} {set value [descriptorValue $data meta $field {}];if {$value ne {}} {append text "\n[string totitle $field]: $value"}}
    tk_messageBox -parent $parent -title {About Module} -icon info -message $text
}
