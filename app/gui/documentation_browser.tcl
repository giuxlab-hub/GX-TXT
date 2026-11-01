# GX-TXT Help / Documentation Browser.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX { variable documentationBrowserUi }
source [file join [file dirname [info script]] documentation_module_window.tcl]

proc ::GX::documentationBrowserPopulate {} {
    variable documentationBrowserUi
    set tree .top.nb.help.left.tree
    if {![winfo exists $tree]} return
    documentationBrowserRefresh
    $tree delete [$tree children {}]
    set query [expr {[info exists documentationBrowserUi(search)] ? $documentationBrowserUi(search) : ""}]
    foreach entry [documentationBrowserList $query] {
        set group [dict get $entry category]
        set parent "group:$group"
        if {![$tree exists $parent]} { $tree insert {} end -id $parent -text $group -open 1 }
        $tree insert $parent end -id [dict get $entry id] -text [dict get $entry title] \
            -values [list [dict get $entry type] [dict get $entry version]]
    }
}

proc ::GX::documentationBrowserShow {id} {
    variable documentationBrowserUi
    variable documentationBrowserEntries
    set tree .top.nb.help.left.tree
    set w .top.nb.help.right.text
    if {![winfo exists $tree] || ![winfo exists $w]} return
    if {![dict exists $documentationBrowserEntries $id]} { documentationBrowserPopulate }
    if {![dict exists $documentationBrowserEntries $id]} { error "Documentation is unavailable: $id" }
    set entry [dict get $documentationBrowserEntries $id]
    set documentationBrowserUi(current) $id
    set documentationBrowserUi(status) "[dict get $entry title] | [dict get $entry owner] [dict get $entry version]"
    if {[string tolower [file extension [dict get $entry path]]] in {.html .htm}} {
        set module [dict get $entry owner]
        if {[moduleField $module descriptor {}] ne {}} {
            set host [documentationBrowserOpenModuleWindow $module]
            if {[dict get $entry type] eq {tutorial}} {
                set at [lsearch -exact $::GX::DocumentationManual::state($host,tutorial_ids) $id]
                if {$at>=0} {$host.tabs.tutorial.choice current $at;$host.tabs select $host.tabs.tutorial;documentationBrowserTutorialSelected $host}
            } elseif {$::GX::DocumentationManual::state($host,path) ne [dict get $entry path]} {documentationBrowserManualShow $host [dict get $entry path]}
            markupRenderStringToWidget $w {# HTML documentation

Opened in the module Guides window.}
        } else {markupRenderStringToWidget $w {# HTML documentation unavailable

The owning module is not installed.}}
        if {[$tree exists $id]} {$tree selection set $id;$tree see $id}
        return
    }
    if {[catch {set source [documentationBrowserRead $id]} reason]} {
        set source "# Documentation unavailable\n\n$reason"
    }
    documentationBrowserManualImagesClear $w
    set ::GX::DocumentationManual::state($w,text) $w
    set ::GX::DocumentationManual::state($w,path) [dict get $entry path]
    set assetRoot {}
    set docsRoot [file normalize [file join $::GX::scriptDir docs]]
    if {[dict get $entry path] ne {}} {
        set documentPath [file normalize [dict get $entry path]]
        if {[string first "$docsRoot/" $documentPath]==0} {
            set assetRoot $docsRoot
        } else {
            set descriptor [moduleField [dict get $entry owner] descriptor {}]
            if {$descriptor ne {}} {
                set moduleRoot [file normalize [file dirname $descriptor]]
                if {[string first "$moduleRoot/" $documentPath]==0} {set assetRoot $moduleRoot}
            }
        }
    }
    set ::GX::DocumentationManual::state($w,asset_root) $assetRoot
    set imageCallback [expr {$assetRoot ne {} ? [list ::GX::documentationBrowserManualImage $w] : {}}]
    foreach tag [$w tag names] {if {[string match gx_manual_image_* $tag]} {$w tag delete $tag}}
    set context [markdownNavigationContext documentation $id [dict create \
        open_command ::GX::_documentationBrowserMainMarkdownOpen \
        status_command [list set ::GX::documentationBrowserUi(status)]]]
    markupRenderStringToWidget $w $source $imageCallback $context
    $w see 1.0
    if {[$tree exists $id]} { $tree selection set $id; $tree see $id }
}

proc ::GX::documentationBrowserFollow {target} {
    return [markupNavigationFollow .top.nb.help.right.text $target]
}
proc ::GX::_documentationBrowserMainMarkdownOpen {destination} {
    if {[dict get $destination kind] ne {documentation}} {error {Documentation requires an indexed document target}}
    if {[string tolower [file extension [dict get $destination path]]] in {.html .htm}} {
        set owner [dict get $destination owner]
        if {[moduleField $owner descriptor {}] eq {}} {error {Linked HTML requires its installed documentation module}}
        set host [documentationBrowserOpenModuleWindow $owner]
        documentationBrowserManualShow $host [dict get $destination path] [dict get $destination fragment]
        return {anchor_handled 1}
    }
    documentationBrowserShow [dict get $destination id]
    return [dict create widget .top.nb.help.right.text]
}

proc ::GX::documentationBrowserSelected {} {
    variable documentationBrowserUi
    set tree .top.nb.help.left.tree
    set selection [$tree selection]
    if {[llength $selection] != 1} return
    set id [lindex $selection 0]
    if {[string match "group:*" $id]} return
    if {[info exists documentationBrowserUi(current)] && $documentationBrowserUi(current) eq $id} return
    documentationBrowserShow $id
}

proc ::GX::documentationBrowserOpenModule {id} {
    set nb .top.nb
    if {![winfo exists $nb.help]} return
    documentationBrowserPopulate
    $nb select $nb.help
    set preferred "module:$id:manual"
    foreach candidate [list $preferred "module:$id:guide" "module:$id:quick_start"] {
        if {[.top.nb.help.left.tree exists $candidate]} {
            documentationBrowserShow $candidate
            return
        }
    }
    documentationBrowserShow core:analysis
}
proc ::GX::documentationBrowserOpenApi {api} {
    documentationBrowserPopulate
    set id api:$api
    if {![dict exists $::GX::documentationBrowserEntries $id]} {error "Public API guide is unavailable: $api"}
    .top.nb select .top.nb.help
    documentationBrowserShow $id
    raise .
    return $id
}

proc ::GX::buildHelpPage {} {
    variable documentationBrowserUi
    set f .top.nb.help
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 1 -weight 1
    ttk::frame $f.buttons
    ttk::label $f.buttons.title -text "GX-TXT Documentation" -font {TkDefaultFont 12 bold}
    ttk::button $f.buttons.docs -text "Registry details..." -command ::GX::documentationRegistryDialog
    pack $f.buttons.title -side left -padx 5
    pack $f.buttons.docs -side right -padx 5
    grid $f.buttons -row 0 -column 0 -sticky ew -padx 8 -pady 6
    ttk::panedwindow $f.body -orient horizontal
    grid $f.body -row 1 -column 0 -sticky nsew -padx 8 -pady 4
    ttk::frame $f.left
    ttk::frame $f.right
    $f.body add $f.left -weight 1
    $f.body add $f.right -weight 3
    ttk::entry $f.left.search -textvariable ::GX::documentationBrowserUi(search)
    pack $f.left.search -fill x -padx 3 -pady 3
    bind $f.left.search <KeyRelease> ::GX::documentationBrowserPopulate
    ttk::treeview $f.left.tree -columns {type version} -show tree -selectmode browse
    ttk::scrollbar $f.left.sy -orient vertical -command [list $f.left.tree yview]
    $f.left.tree configure -yscrollcommand [list $f.left.sy set]
    pack $f.left.sy -side right -fill y
    pack $f.left.tree -fill both -expand 1
    bind $f.left.tree <<TreeviewSelect>> ::GX::documentationBrowserSelected
    text $f.right.text -wrap word -state disabled
    ttk::scrollbar $f.right.sy -orient vertical -command [list $f.right.text yview]
    $f.right.text configure -yscrollcommand [list $f.right.sy set]
    pack $f.right.sy -side right -fill y
    pack $f.right.text -fill both -expand 1
    bind $f.right.text <Configure> [list ::GX::documentationBrowserManualImagesFit $f.right.text]
    bind $f.right.text <Destroy> [list ::GX::documentationBrowserManualDestroyed $f.right.text %W]
    ttk::label $f.status -textvariable ::GX::documentationBrowserUi(status) -anchor w
    grid $f.status -row 2 -column 0 -sticky ew -padx 9 -pady {0 5}
    set documentationBrowserUi(search) ""
    documentationBrowserPopulate
    documentationBrowserShow core:getting_started
}

proc ::GX::augmentStandardGui {} {
    ::GX::augmentStandardGui_before_documentation_browser
    if {[winfo exists .top.nb.modules.buttons.help]} {
        .top.nb.modules.buttons.help configure -text "Open module manual..." -command {
            set id [::GX::selectedModuleFromTree]
            if {$id ne ""} { ::GX::documentationBrowserOpenModule $id }
        }
    }
}
