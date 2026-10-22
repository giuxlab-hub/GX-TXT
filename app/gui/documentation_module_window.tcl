# SPDX-License-Identifier: GPL-3.0-or-later
# Independent read-only hosts share the existing descriptor index and renderer.
# This state contains widgets/navigation only, never a second document store.
namespace eval ::GX::DocumentationManual {variable state;array set state {};variable htmlSerial;if {![info exists htmlSerial]} {set htmlSerial 0};variable generatorSerial;if {![info exists generatorSerial]} {set generatorSerial 0}}
proc ::GX::documentationBrowserModuleManual {module} {
    set descriptor [moduleField $module descriptor {}]
    if {$descriptor eq {}} {error "Module '$module' is not installed; its manual is unavailable."}
    documentationBrowserRefresh
    foreach kind {html_manual manual guide quick_start} {
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
    if {![file isfile $path] || [string tolower [file extension $path]] ni {.md .markdown .txt .html .htm}} {error {The requested rendered document is missing or has an unsupported format.}}
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
proc ::GX::documentationBrowserDemoCreate {widget callback} {
    ttk::labelframe $widget -text {DEMO / Help presentation} -padding 8
    ttk::label $widget.label -text {The manual is real; the component sample carries no scientific state.} -wraplength 500
    ttk::button $widget.manual -text {Open Builder manual} -command [list ::GX::documentationBrowserOpenModuleWindow viewer.interface_builder [winfo toplevel $widget]]
    ttk::button $widget.contract -text {Inspect Help sample contract} -command [list {*}$callback help_sample]
    pack $widget.label $widget.manual $widget.contract -anchor w -padx 3 -pady 3
    return $widget
}
proc ::GX::documentationBrowserOpenModuleWindow {module {parent {}}} {
    variable ::GX::DocumentationManual::state
    set w .gxManual_[binary encode hex [encoding convertto utf-8 $module]]
    if {[winfo exists $w]} {raise $w;focus $w.search.entry;return $w}
    toplevel $w;wm title $w "[moduleField $module name $module] — User Manual"
    uiFieldWindowFit $w 900 700;wm minsize $w 420 300
    # A manual survives its Viewer closing; it is deliberately not transient.
    set state($w,pending_anchor) {};set state($w,html_handle) {};set state($w,html_mode) 0;set state($w,tutorial_handle) {};set state($w,tutorial_ids) {};set state($w,tutorial_current) {};set state($w,tutorial_choice) {};set state($w,tutorial_status) {};set state($w,module) $module;set state($w,path) {};set state($w,back) {};set state($w,forward) {};set state($w,search) {};set state($w,status) {}
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
    ttk::notebook $w.tabs
    ttk::frame $w.tabs.manual
    ttk::frame $w.tabs.tutorial
    $w.tabs add $w.tabs.manual -text Manual
    $w.tabs add $w.tabs.tutorial -text {Interactive Tutorial}
    pack $w.tabs -fill both -expand 1 -padx 6 -pady 5
    ttk::frame $w.body;pack $w.body -in $w.tabs.manual -fill both -expand 1
    ttk::combobox $w.tabs.tutorial.choice -state readonly -textvariable ::GX::DocumentationManual::state($w,tutorial_choice)
    ttk::label $w.tabs.tutorial.status -textvariable ::GX::DocumentationManual::state($w,tutorial_status) -anchor w -wraplength 800
    ttk::frame $w.tabs.tutorial.host
    pack $w.tabs.tutorial.choice -side top -fill x -padx 5 -pady 5
    pack $w.tabs.tutorial.status -side bottom -fill x -padx 5 -pady 5
    pack $w.tabs.tutorial.host -fill both -expand 1
    bind $w.tabs.tutorial.choice <<ComboboxSelected>> [list ::GX::documentationBrowserTutorialSelected $w]
    bind $w.tabs <<NotebookTabChanged>> [list ::GX::documentationBrowserTutorialActivated $w]
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
    documentationBrowserTutorialRefresh $w
    return $w
}
proc ::GX::documentationBrowserManualDestroyed {w actual} {
    if {$w ne $actual} return
    documentationBrowserHtmlClose $w html_handle
    documentationBrowserHtmlClose $w tutorial_handle
    documentationBrowserManualImagesClear $w
    array unset ::GX::DocumentationManual::state "$w,*"
}
proc ::GX::documentationBrowserManualResize {w actual width} {
    if {$w eq $actual && [winfo exists $w.status]} {
        $w.status configure -wraplength [expr {max(100,$width-18)}]
        documentationBrowserManualImagesFit $w
    }
}
proc ::GX::documentationBrowserManualImagesClear {w} {
    variable ::GX::DocumentationManual::state
    if {[info exists state($w,images)]} {
        foreach pair $state($w,images) {foreach photo $pair {catch {image delete $photo}}}
    }
    set state($w,images) {}
    set state($w,image_paths) {}
    catch {destroy $w.screenshot}
}
proc ::GX::documentationBrowserManualImagesFit {w} {
    variable ::GX::DocumentationManual::state
    set text [expr {[info exists state($w,text)] ? $state($w,text) : "$w.body.text"}]
    if {![info exists state($w,images)] || ![winfo exists $text]} return
    set available [expr {max(160,[winfo width $text]-35)}]
    foreach pair $state($w,images) {
        lassign $pair displayed original
        set factor [expr {max(1,int(ceil([image width $original]/double($available))))}]
        $displayed copy $original -subsample $factor $factor -shrink
    }
}
proc ::GX::documentationBrowserManualImage {w text relative caption} {
    variable ::GX::DocumentationManual::state
    # The owning indexed document supplies the asset root, never Markdown.
    # Module manuals retain their module root; canonical API guides use docs/.
    set root [expr {[info exists state($w,asset_root)] ? $state($w,asset_root) : [file normalize [file dirname [moduleField $state($w,module) descriptor]]]}]
    set path [file normalize [file join [file dirname $state($w,path)] $relative]]
    if {[file pathtype $relative] ne {relative} || [string first "$root/" $path]!=0 || ![file isfile $path] || [file type $path] eq {link} || [file extension $path] ne {.png} || [file size $path]>8388608} {
        $text insert end "Image unavailable: $caption\n";return
    }
    set fd [open $path rb]
    try {set header [read $fd 24]} finally {close $fd}
    binary scan $header H16@16II signature width height
    if {$signature ne {89504e470d0a1a0a} || $width<1 || $height<1 || $width>4096 || $height>4096} {
        $text insert end "Image unavailable: invalid packaged PNG dimensions\n";return
    }
    if {[catch {set original [image create photo -file $path]} message]} {$text insert end "Image unavailable: $caption ($message)\n";return}
    set displayed [image create photo]
    lappend state($w,images) [list $displayed $original]
    lappend state($w,image_paths) $path
    documentationBrowserManualImagesFit $w
    $text image create end -image $displayed
    $text insert end "\n$caption\n\n"
    set tag gx_manual_image_[llength $state($w,images)]
    $text insert end {Open screenshot at full size} $tag
    $text insert end "\n\n"
    $text tag configure $tag -foreground #145da0 -underline 1
    $text tag bind $tag <Button-1> [list ::GX::documentationBrowserManualImageOpen $w $path $caption]
}
proc ::GX::documentationBrowserManualImageOpen {parent path caption} {
    set w $parent.screenshot
    catch {destroy $w}
    toplevel $w;wm title $w $caption
    uiFieldWindowFit $w 1100 760;wm minsize $w 350 250
    ttk::button $w.close -text Close -command [list destroy $w]
    grid $w.close -row 0 -column 0 -sticky w -padx 5 -pady 5
    set photo [image create photo -file $path]
    canvas $w.image -highlightthickness 0 -xscrollcommand [list $w.x set] -yscrollcommand [list $w.y set]
    $w.image create image 0 0 -anchor nw -image $photo
    $w.image configure -scrollregion [list 0 0 [image width $photo] [image height $photo]]
    ttk::scrollbar $w.x -orient horizontal -command [list $w.image xview]
    ttk::scrollbar $w.y -command [list $w.image yview]
    grid $w.image -row 1 -column 0 -sticky nsew
    grid $w.y -row 1 -column 1 -sticky ns
    grid $w.x -row 2 -column 0 -sticky ew
    grid rowconfigure $w 1 -weight 1;grid columnconfigure $w 0 -weight 1
    bind $w <Escape> [list destroy $w]
    bind $w <Destroy> [list ::GX::documentationBrowserManualImageClosed $w $photo %W]
}
proc ::GX::documentationBrowserManualImageClosed {w photo actual} {
    if {$w eq $actual} {catch {image delete $photo}}
}
proc ::GX::documentationBrowserManualUnavailable {w message} {
    documentationBrowserHtmlClose $w html_handle
    catch {destroy $w.body.html}
    set ::GX::DocumentationManual::state($w,html_mode) 0
    pack $w.body.scroll -side right -fill y;pack $w.body.text -fill both -expand 1
    set ::GX::DocumentationManual::state($w,status) $message
    markupRenderStringToWidget $w.body.text "# User manual unavailable\n\n$message"
    documentationBrowserManualEnable $w
}
proc ::GX::documentationBrowserManualReload {w} {
    variable ::GX::DocumentationManual::state
    if {![winfo exists $w]} return
    if {[winfo exists $w.tabs]} {$w.tabs select $w.tabs.manual}
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
    if {[string tolower [file extension $path]] in {.html .htm}} {
        set state($w,html_mode) 1
        pack forget $w.body.text $w.body.scroll
        documentationBrowserHtmlClose $w html_handle
        catch {destroy $w.body.html}
        ttk::frame $w.body.html;pack $w.body.html -fill both -expand 1
        documentationBrowserHtmlOpen $w html_handle $w.body.html $id
        set state($w,pending_anchor) $anchor
        documentationBrowserManualEnable $w
        return
    }
    set state($w,html_mode) 0
    set state($w,pending_anchor) {}
    documentationBrowserHtmlClose $w html_handle
    catch {destroy $w.body.html}
    pack $w.body.scroll -side right -fill y;pack $w.body.text -fill both -expand 1
    set text $w.body.text
    foreach tag [$text tag names] {if {[string match gx_manual_* $tag]} {$text tag delete $tag}}
    documentationBrowserManualImagesClear $w
    markupRenderStringToWidget $text $source [list ::GX::documentationBrowserManualImage $w]
    # Relative links use this host's path/history, never the main Help state.
    set display [$text get 1.0 end-1c];set at 0;set number 0
    $text configure -state normal
    while {[regexp -indices -start $at {\[[^]]+\]\([^)]+\)} $display range]} {
        lassign $range first last
        set literal [string range $display $first $last]
        set index [$text search -exact -- $literal 1.0 end]
        if {$index ne {} && [regexp {\[([^]]+)\]\(([^)]+)\)} $literal -> label target] && {gx_codeblock} ni [$text tag names $index]} {
            set tag gx_manual_link_[incr number]
            $text delete $index "$index + [string length $literal] chars"
            $text insert $index $label $tag
            $text tag configure $tag -foreground #145da0 -underline 1
            $text tag bind $tag <Button-1> [list ::GX::documentationBrowserManualFollow $w $target]
        }
        set at [expr {$last+1}]
    }
    $text configure -state disabled
    $text see 1.0
    if {$anchor ne {}} {documentationBrowserManualAnchor $w $anchor}
    documentationBrowserManualEnable $w
}
proc ::GX::documentationBrowserManualEnable {w} {
    variable ::GX::DocumentationManual::state
    set native {};set tutorial [expr {[winfo exists $w.tabs] && [$w.tabs select] eq "$w.tabs.tutorial"}]
    set handle [expr {$tutorial?$state($w,tutorial_handle):$state($w,html_handle)}]
    if {$handle ne {}} {catch {set native [::GX::HTMLViewer::inspect $handle]}}
    foreach key {back forward} {
        set enabled [expr {!$tutorial && [llength $state($w,$key)]>0}]
        if {$native ne {} && [dict get $native can_$key]} {set enabled 1}
        $w.navigation.$key state [expr {$enabled?{!disabled}:{disabled}}]
    }
}
proc ::GX::documentationBrowserManualHistory {w direction} {
    variable ::GX::DocumentationManual::state
    if {[winfo exists $w.tabs] && [$w.tabs select] eq "$w.tabs.tutorial"} {
        if {$state($w,tutorial_handle) ne {}} {catch {::GX::HTMLViewer::navigate $state($w,tutorial_handle) [dict create action $direction]}}
        return
    }
    if {[info exists state($w,html_handle)] && $state($w,html_handle) ne {}} {
        if {![catch {set native [::GX::HTMLViewer::inspect $state($w,html_handle)]}] && [dict get $native can_$direction]} {
            catch {::GX::HTMLViewer::navigate $state($w,html_handle) [dict create action $direction]};return
        }
    }
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
    variable ::GX::DocumentationManual::state
    if {[info exists state($w,html_handle)] && $state($w,html_handle) ne {}} {catch {::GX::HTMLViewer::navigate $state($w,html_handle) [dict create action relative target #$anchor]};return}
    set text $w.body.text
    foreach tag {gx_h1 gx_h2 gx_h3} {
        foreach {first last} [$text tag ranges $tag] {
            set heading [string tolower [string trim [$text get $first $last]]]
            regsub -all {[^[:alnum:] _-]} $heading {} heading
            regsub -all {[ _]+} $heading {-} heading
            if {$heading eq $anchor} {$text yview $first;return}
        }
    }
    set label [string map {- { } _ { }} $anchor]
    set index [$text search -nocase -exact -- $label 1.0]
    if {$index eq {}} {set index [$text search -exact -- "id=\"$anchor\"" 1.0]}
    if {$index ne {}} {$text yview $index} else {set ::GX::DocumentationManual::state($w,status) "Anchor unavailable: $anchor"}
}
proc ::GX::documentationBrowserManualSearch {w} {
    variable ::GX::DocumentationManual::state
    set query $state($w,search)
    set handle {}
    if {[winfo exists $w.tabs] && [$w.tabs select] eq "$w.tabs.tutorial"} {set handle $state($w,tutorial_handle)
    } elseif {[info exists state($w,html_mode)] && $state($w,html_mode)} {set handle $state($w,html_handle)}
    if {$handle ne {}} {catch {::GX::HTMLViewer::navigate $handle [dict create action find text $query]};return}
    if {[info exists state($w,html_mode)] && $state($w,html_mode)} return
    set text $w.body.text
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
        if {[regexp -nocase {(user|viewer|developer) manual} $label]} {set manual 1}
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
    append text "\nProvider: $module / $viewer"
    set apis [descriptorValue $data documentation api_refs [descriptorValue $data public_apis ids {}]]
    if {$apis ne {}} {append text "\nPublic APIs: [join [splitList $apis] {, }]"}
    tk_messageBox -parent $parent -title {About Module} -icon info -message $text
}

# HTML consumes the single CORE presentation service, never a second renderer.
proc ::GX::documentationBrowserHtmlClose {w key} {
    variable ::GX::DocumentationManual::state
    if {[info exists state($w,$key,generator)]} {
        set context $state($w,$key,generator)
        foreach field {button notice} {
            set widget [dict get $context $field]
            if {[winfo exists $widget] && [winfo id $widget] eq [dict get $context ${field}_id]} {destroy $widget}
        }
    }
    foreach field {generator generator_busy generator_status} {unset -nocomplain state($w,$key,$field)}
    if {[info exists state($w,$key)] && $state($w,$key) ne {}} {
        catch {::GX::HTMLViewer::detach $state($w,$key)}
        set state($w,$key) {}
    }
    if {[info exists state($w,$key,surface)]} {
        set surface $state($w,$key,surface);unset state($w,$key,surface)
        if {[winfo exists $surface]} {destroy $surface}
    }
}
proc ::GX::documentationBrowserHtmlSurfaceName {parent} {
    variable ::GX::DocumentationManual::htmlSerial
    return $parent.gxhtml[incr htmlSerial]
}
proc ::GX::documentationBrowserHtmlOpen {w key parent document} {
    variable ::GX::DocumentationManual::state
    documentationBrowserHtmlClose $w $key
    foreach name {unavailable markdown} {if {[winfo exists $parent.$name]} {destroy $parent.$name}}
    if {[catch {
        set entry [documentationBrowserResolve $document]
        if {![llength [info commands ::GX::HTMLViewer::attach]]} {error {Shared HTML service is unavailable.}}
        # A closing renderer retains its old native parent until group drain.
        # Every selection owns a fresh child, never the surviving host Frame.
        set surface [documentationBrowserHtmlSurfaceName $parent]
        ttk::frame $surface;pack $surface -fill both -expand 1
        set state($w,$key,surface) $surface
        set attached [::GX::HTMLViewer::attach $surface [dict create purpose documentation]]
        set state($w,$key) [dict get $attached handle]
        _documentationGeneratorCreate $w $key $parent $surface $entry
        bind $surface <<GXHTMLChanged>> [list ::GX::documentationBrowserHtmlChanged $w $key]
        ::GX::HTMLViewer::load $state($w,$key) [dict create kind documentation document_id $document]
    } message]} {
        documentationBrowserHtmlClose $w $key
        set unavailable {Interactive HTML is unavailable in this installation.}
        if {[info exists entry]} {
            set guidance [_documentationGeneratorGuidance $entry $state($w,module)]
            if {$guidance ne {}} {append unavailable "\n$guidance"}
        }
        ttk::label $parent.unavailable -text $unavailable -wraplength 650
        pack $parent.unavailable -anchor center -padx 12 -pady 18
        if {$key eq {html_handle}} {
            ttk::button $parent.markdown -text {Open preserved Markdown manual} -command [list ::GX::documentationBrowserLegacyManual $w]
            pack $parent.markdown -anchor center -padx 12 -pady 6
        } else {set state($w,tutorial_status) {This lesson requires the shared interactive HTML runtime.}}
    }
}
proc ::GX::documentationBrowserHtmlChanged {w key} {
    variable ::GX::DocumentationManual::state
    if {![winfo exists $w] || ![info exists state($w,$key)] || $state($w,$key) eq {}} return
    if {![catch {set receipt [::GX::HTMLViewer::inspect $state($w,$key)]}]} {
        if {$key eq {html_handle}} {
            if {[dict get $receipt state] eq {ready} && $state($w,pending_anchor) ne {}} {
                set anchor $state($w,pending_anchor);set state($w,pending_anchor) {}
                catch {::GX::HTMLViewer::navigate $state($w,$key) [dict create action relative target #$anchor]}
            }
            set state($w,status) [dict get $receipt status];documentationBrowserManualEnable $w
        } else {set state($w,tutorial_status) [dict get $receipt status]}
    }
    _documentationGeneratorRefresh $w $key
}
proc ::GX::documentationBrowserLegacyManual {w} {
    variable ::GX::DocumentationManual::state
    if {![winfo exists $w]} return
    foreach kind {manual guide quick_start} {
        set id module:$state($w,module):$kind
        if {[dict exists $::GX::documentationBrowserEntries $id]} {
            set entry [dict get $::GX::documentationBrowserEntries $id]
            if {[string tolower [file extension [dict get $entry path]]] in {.md .markdown .txt}} {documentationBrowserManualShow $w [dict get $entry path];return}
        }
    }
    set state($w,status) {No preserved Markdown manual is installed for this module.}
}
proc ::GX::documentationBrowserTutorialRefresh {w} {
    variable ::GX::DocumentationManual::state
    if {![winfo exists $w.tabs.tutorial.choice]} return
    set ids {};set labels {}
    foreach entry [documentationBrowserModuleTutorials $state($w,module)] {
        if {[string tolower [file extension [dict get $entry path]]] ni {.html .htm}} continue
        lappend ids [dict get $entry id];lappend labels [dict get $entry title]
    }
    set state($w,tutorial_ids) $ids
    $w.tabs.tutorial.choice configure -values $labels
    set current [lsearch -exact $ids $state($w,tutorial_current)]
    if {$current<0} {documentationBrowserHtmlClose $w tutorial_handle;set state($w,tutorial_current) {}}
    if {[llength $ids]} {
        $w.tabs.tutorial.choice current [expr {$current<0?0:$current}]
        set state($w,tutorial_status) {Select the Interactive Tutorial tab to open the registered lesson.}
    } else {
        set state($w,tutorial_choice) {}
        set state($w,tutorial_status) {No interactive tutorial package is installed for this module.}
    }
}
proc ::GX::documentationBrowserTutorialActivated {w} {
    variable ::GX::DocumentationManual::state
    if {![winfo exists $w] || ![info exists state($w,tutorial_handle)]} return
    if {[winfo exists $w.tabs] && [$w.tabs select] eq "$w.tabs.tutorial" && $state($w,tutorial_handle) eq {}} {documentationBrowserTutorialSelected $w}
    documentationBrowserManualEnable $w
    foreach key {html_handle tutorial_handle} {_documentationGeneratorRefresh $w $key}
}
proc ::GX::documentationBrowserTutorialSelected {w} {
    variable ::GX::DocumentationManual::state
    if {![winfo exists $w]} return
    set index [$w.tabs.tutorial.choice current]
    if {$index<0 || $index>=[llength $state($w,tutorial_ids)]} return
    documentationBrowserHtmlClose $w tutorial_handle
    set parent $w.tabs.tutorial.host
    foreach child [winfo children $parent] {destroy $child}
    set id [lindex $state($w,tutorial_ids) $index]
    set state($w,tutorial_current) $id
    if {[catch {set entry [documentationBrowserResolve $id]}]} {set state($w,tutorial_status) {This registered lesson is no longer available.};return}
    documentationBrowserHtmlOpen $w tutorial_handle $parent $id
}

# Native host button only. Page URLs/scripts receive no generator capability.
# The pure projections below share the exact UI predicate with bounded headless
# checks; they confer no widget, HTML, Generator or scientific authority.
proc ::GX::_documentationGeneratorEntry {entry module} {
    foreach field {id owner source_sha256 manifest_sha256 generator_library_id generator_id} {
        if {![dict exists $entry $field] || [dict get $entry $field] eq {}} {return {}}
    }
    if {[dict get $entry owner] ne $module} {return {}}
    foreach field {source_sha256 manifest_sha256} {
        if {![regexp {^[0-9a-f]{64}$} [dict get $entry $field]]} {return {}}
    }
    foreach field {generator_library_id generator_id} {
        if {![regexp {^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$} [dict get $entry $field]]} {return {}}
    }
    set result {}
    foreach field {id owner source_sha256 manifest_sha256 generator_library_id generator_id} {dict set result $field [dict get $entry $field]}
    return $result
}
proc ::GX::_documentationGeneratorGuidance {entry module} {
    set binding [_documentationGeneratorEntry $entry $module]
    if {$binding eq {}} {return {}}
    return "Session Generator: [dict get $binding generator_library_id] / [dict get $binding generator_id]. Open Generate Session normally."
}
proc ::GX::_documentationGeneratorMatch {expected current receipt entry} {
    foreach field {serial window_id surface surface_id tab handle} {
        if {![dict exists $current $field] || [dict get $current $field] ne [dict get $expected $field]} {return 0}
    }
    if {[dict get $current selected_tab] ne [dict get $expected tab]} {return 0}
    if {[_documentationGeneratorEntry $entry [dict get $expected owner]] ne [dict get $expected entry]} {return 0}
    foreach field {handle state generation source} {if {![dict exists $receipt $field]} {return 0}}
    if {[dict get $receipt handle] ne [dict get $expected handle] || [dict get $receipt state] ne {ready}} {return 0}
    if {![string is integer -strict [dict get $receipt generation]] || [dict get $receipt generation]<1} {return 0}
    if {[dict get $expected generation] ne {} && [dict get $receipt generation] ne [dict get $expected generation]} {return 0}
    set source [dict get $receipt source]
    foreach field {kind document_id source_sha256} {if {![dict exists $source $field]} {return 0}}
    return [expr {[dict get $source kind] eq {documentation} &&
        [dict get $source document_id] eq [dict get $expected entry id] &&
        [dict get $source source_sha256] eq [dict get $expected entry source_sha256]}]
}
proc ::GX::_documentationGeneratorResult {result library generator} {
    set unavailable [dict create status unavailable reason owner_result_invalid]
    if {[catch {dict size $result}] || [lsort [dict keys $result]] ne [lsort {status window library_id generator_id reason}]} {return $unavailable}
    if {[dict get $result library_id] ne $library || [dict get $result generator_id] ne $generator ||
        [dict get $result status] ni {opened unavailable busy} || [string bytelength [dict get $result reason]]>128 ||
        [string bytelength [dict get $result window]]>256} {return $unavailable}
    if {[dict get $result status] eq {opened} && ([dict get $result window] eq {} || [dict get $result reason] ne {})} {return $unavailable}
    return [dict create status [dict get $result status] reason [dict get $result reason]]
}
proc ::GX::_documentationGeneratorCreate {w key parent surface entry} {
    variable ::GX::DocumentationManual::state
    variable ::GX::DocumentationManual::generatorSerial
    set binding [_documentationGeneratorEntry $entry $state($w,module)]
    if {$binding eq {}} return
    set tab [expr {$key eq {html_handle}?"$w.tabs.manual":"$w.tabs.tutorial"}]
    set serial [incr generatorSerial]
    set button $parent.generator;set notice $parent.generatorStatus
    set state($w,$key,generator_status) {Loading registered documentation; generator selection is unavailable.}
    ttk::button $button -text {Open Generate Session…} -state disabled -command [list ::GX::_documentationGeneratorOpen $w $key $serial]
    ttk::label $notice -textvariable ::GX::DocumentationManual::state($w,$key,generator_status) -wraplength 650
    pack $notice -side bottom -fill x -padx 5 -pady 3
    pack $button -side bottom -anchor w -padx 5 -pady 3
    set state($w,$key,generator) [dict create serial $serial window_id [winfo id $w] surface $surface surface_id [winfo id $surface] tab $tab handle $state($w,$key) generation {} owner $state($w,module) entry $binding button $button button_id [winfo id $button] notice $notice notice_id [winfo id $notice]]
    set state($w,$key,generator_busy) 0
}
proc ::GX::_documentationGeneratorOwned {w key context} {
    variable ::GX::DocumentationManual::state
    if {![info exists state($w,$key,generator)] || $state($w,$key,generator) ne $context ||
        ![info exists state($w,$key)] || $state($w,$key) ne [dict get $context handle]} {return 0}
    foreach {widgetField idField} {surface surface_id button button_id notice notice_id} {
        set widget [dict get $context $widgetField]
        if {![winfo exists $widget] || [winfo id $widget] ne [dict get $context $idField]} {return 0}
    }
    return [expr {[winfo exists $w] && [winfo id $w] eq [dict get $context window_id]}]
}
proc ::GX::_documentationGeneratorCurrent {w key context} {
    variable ::GX::DocumentationManual::state
    if {![_documentationGeneratorOwned $w $key $context] || ![winfo exists $w.tabs]} {return {}}
    if {[catch {
        set current [dict create serial [dict get $state($w,$key,generator) serial] window_id [winfo id $w] surface [dict get $state($w,$key,generator) surface] surface_id [winfo id [dict get $context surface]] tab [dict get $context tab] handle $state($w,$key) selected_tab [$w.tabs select]]
        set receipt [::GX::HTMLViewer::inspect [dict get $context handle]]
        set entry [documentationBrowserResolve [dict get $context entry id]]
        if {![_documentationGeneratorMatch $context $current $receipt $entry]} {error {Documentation selection changed}}
    }]} {return {}}
    return $receipt
}
proc ::GX::_documentationGeneratorRefresh {w key} {
    variable ::GX::DocumentationManual::state
    if {![info exists state($w,$key,generator)]} return
    set context $state($w,$key,generator)
    if {![_documentationGeneratorOwned $w $key $context]} return
    set button [dict get $context button]
    $button state disabled
    if {$state($w,$key,generator_busy)} return
    set pair "[dict get $context entry generator_library_id] / [dict get $context entry generator_id]"
    if {![llength [info commands ::GX::sessionGeneratorOpenSelection]]} {
        set state($w,$key,generator_status) "Session Generator: $pair. Native selection is unavailable; open Generate Session normally."
        return
    }
    set receipt [_documentationGeneratorCurrent $w $key $context]
    if {$receipt eq {}} {
        set state($w,$key,generator_status) "Session Generator: $pair. Select this tab and load its current registered document before opening the generator."
        return
    }
    if {[dict get $context generation] eq {}} {
        dict set context generation [dict get $receipt generation]
        set state($w,$key,generator) $context
    }
    set state($w,$key,generator_status) "Session Generator: $pair. Opens the ordinary selection dialog; generation remains your choice."
    $button state !disabled
}
proc ::GX::_documentationGeneratorOpen {w key serial} {
    variable ::GX::DocumentationManual::state
    if {![info exists state($w,$key,generator)]} return
    set context $state($w,$key,generator)
    if {[dict get $context serial] ne $serial || ![_documentationGeneratorOwned $w $key $context] || $state($w,$key,generator_busy)} return
    if {[dict get $context generation] eq {} || ![llength [info commands ::GX::sessionGeneratorOpenSelection]] || [_documentationGeneratorCurrent $w $key $context] eq {}} {
        _documentationGeneratorRefresh $w $key
        return
    }
    set state($w,$key,generator_busy) 1
    [dict get $context button] state disabled
    set library [dict get $context entry generator_library_id];set generator [dict get $context entry generator_id]
    set result [dict create status unavailable reason owner_unavailable]
    try {
        set result [_documentationGeneratorResult [::GX::sessionGeneratorOpenSelection $library $generator] $library $generator]
    } on error {message options} {
        set result [dict create status unavailable reason owner_unavailable]
    } finally {
        # Owner may service idle layout work. Clear only our surviving context's
        # busy flag, including if its tab became hidden; never mutate replacement.
        if {[_documentationGeneratorOwned $w $key $context]} {set state($w,$key,generator_busy) 0}
    }
    if {[_documentationGeneratorCurrent $w $key $context] eq {}} return
    _documentationGeneratorRefresh $w $key
    switch -- [dict get $result status] {
        opened {set text {The ordinary Generate Session dialog is open with this registered generator selected.}}
        busy {set text {Another dialog is active. Finish it, then select Open Generate Session again.}}
        default {
            set reasons [dict create library_missing {The registered generator library is not installed.} library_disabled {The registered generator library is disabled.} generator_missing {The registered generator is not available in that library.} session_root_missing {Configure a Session output location before opening Generate Session.} session_root_invalid {The Session output location is unavailable.}]
            set text [expr {[dict exists $reasons [dict get $result reason]]?[dict get $reasons [dict get $result reason]]:{The registered generator selection is unavailable. Open Generate Session normally or reload this document.}}]
        }
    }
    set state($w,$key,generator_status) $text
}
