# GX-TXT Session File Explorer API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only browser for text-like files inside the CURRENT GX-TXT session.
# It is intentionally not a general filesystem browser and excludes plots.

namespace eval ::GX {
    variable sessionFileExplorerApiVersion 1
    variable sessionFileMaxBytes 4194304
    variable sessionFileExtensions {.txt .csv .tsv .md .ini .log .json .yaml .yml .cfg .dat .asc .cir .net .lib}
}

proc ::GX::sessionFileExplorerAllowed {path} {
    variable sessionFileExtensions
    if {![file isfile $path]} { return 0 }
    set ext [string tolower [file extension $path]]
    return [expr {[lsearch -exact $sessionFileExtensions $ext] >= 0}]
}

proc ::GX::sessionFileExplorerRelative {path} {
    variable currentSession
    set root [file normalize $currentSession]; set p [file normalize $path]
    if {[string first "$root/" "$p/"] != 0} { error "File is outside current session." }
    return [string range $p [expr {[string length $root]+1}] end]
}

proc ::GX::sessionFileExplorerScan {{dir ""}} {
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { return {} }
    if {$dir eq ""} { set dir $currentSession }
    sessionFileExplorerRelative $dir
    # Never follow a directory link out of the Session during recursion.
    if {[file type $dir] eq "link"} {return {}}
    set out {}
    foreach p [lsort -dictionary [glob -nocomplain -directory $dir *]] {
        if {[file type $p] eq "link"} continue
        if {[file isdirectory $p]} {
            foreach q [sessionFileExplorerScan $p] { lappend out $q }
        } elseif {[sessionFileExplorerAllowed $p]} { lappend out $p }
    }
    return $out
}

proc ::GX::sessionFileExplorerRead {path} {
    variable sessionFileMaxBytes
    sessionFileExplorerRelative $path
    if {![sessionFileExplorerAllowed $path]} { error "Unsupported or non-text session file." }
    set size [file size $path]
    set fd [open $path r]; fconfigure $fd -encoding utf-8 -translation auto
    if {$size > $sessionFileMaxBytes} {
        set data [read $fd $sessionFileMaxBytes]
        append data "\n\n--- PREVIEW TRUNCATED: file size $size bytes, limit $sessionFileMaxBytes bytes ---\n"
    } else { set data [read $fd] }
    close $fd
    return $data
}

proc ::GX::sessionFileExplorerPopulate {} {
    variable ui
    variable currentSession
    if {![info exists ui(sessionFileTree)] || ![winfo exists $ui(sessionFileTree)]} return
    set t $ui(sessionFileTree)
    foreach item [$t children {}] { $t delete $item }
    if {$currentSession eq "" || ![file isdirectory $currentSession]} {
        if {[info exists ui(sessionFileInfo)]} { set ui(sessionFileInfo) "No session open." }
        catch {sessionScriptExplorerPopulate}
        return
    }
    set nodes [dict create "" {}]
    foreach path [sessionFileExplorerScan] {
        set rel [sessionFileExplorerRelative $path]
        set parts [file split $rel]
        set parent ""; set accum ""
        for {set i 0} {$i < [llength $parts]-1} {incr i} {
            set part [lindex $parts $i]
            set accum [expr {$accum eq "" ? $part : [file join $accum $part]}]
            set id "d:$accum"
            if {![$t exists $id]} { $t insert $parent end -id $id -text $part -values [list dir ""] }
            set parent $id
        }
        set fid "f:$rel"
        $t insert $parent end -id $fid -text [file tail $rel] -values [list file [file size $path]]
    }
    catch {sessionScriptExplorerPopulate}
    set ui(sessionFileInfo) "Session: [currentSessionDisplayName] — [llength [sessionFileExplorerScan]] text/data file(s)"
    set token [interactiveDocumentSessionToken]
    if {![info exists ui(sessionRunCaptionGeneration)]} {set ui(sessionRunCaptionGeneration) 0}
    set gen [incr ui(sessionRunCaptionGeneration)]
    scriptJobAsync [scriptJobCommand run_summaries [file normalize $currentSession]] {} [list ::GX::sessionFileExplorerRunCaptions $token $gen]
}

proc ::GX::sessionFileExplorerRunCaptions {token generation response} {
    variable ui
    if {$token ne [interactiveDocumentSessionToken] || $generation!=$ui(sessionRunCaptionGeneration) || ![winfo exists $ui(sessionFileTree)]} return
    if {![dict get $response ok]} {append ui(sessionFileInfo) " — Run metadata unavailable: [dict get $response error]";return}
    foreach run [dict get $response result] {
        set id [dict get $run id];set node "d:analysis/scripts/$id"
        if {![$ui(sessionFileTree) exists $node]} continue
        set name [scriptJobField $run script_name {}]
        if {$name eq {}} {set caption {Script name unavailable — Registered Script ID unavailable — Execution time unavailable}} else {
            set caption "$name — [scriptJobField $run reference]"
            set time [scriptJobField $run started {}]
            if {$time ne {}} {append caption " — [scriptJobTime $time]"} else {
                set submitted [scriptJobField $run submitted {}]
                append caption " — [expr {$submitted eq {} ? {Execution time unavailable} : "Submitted [scriptJobTime $submitted]"}]"
            }
        }
        $ui(sessionFileTree) item $node -text $caption
    }
}
proc ::GX::sessionFileExplorerRunSelected {} {
    variable ui
    if {![info exists ui(sessionFileTree)]} {return {}}
    set node [$ui(sessionFileTree) selection]
    if {[regexp {^[df]:analysis/scripts/(script-[A-Za-z0-9-]+)(?:/|$)} $node -> id]} {return $id}
    return {}
}
proc ::GX::sessionFileExplorerOpenRun {} {
    set id [sessionFileExplorerRunSelected]
    if {$id ne {}} {scriptJobDetailsWindow $id [file normalize $::GX::currentSession]}
}

proc ::GX::sessionFileExplorerOpenSelected_v092_before_rendered_markdown {} {
    variable ui
    variable currentSession
    if {![info exists ui(sessionFileTree)] || ![winfo exists $ui(sessionFileTree)]} return
    set sel [$ui(sessionFileTree) selection]
    if {[llength $sel] != 1} return
    set id [lindex $sel 0]
    if {![string match "f:*" $id]} return
    set rel [string range $id 2 end]
    set path [file normalize [file join $currentSession $rel]]
    if {[catch {set txt [sessionFileExplorerRead $path]} err]} { set txt "ERROR\n$err\n" }
    set w $ui(sessionFileText); $w configure -state normal; $w delete 1.0 end; $w insert end $txt; $w configure -state disabled
    set ui(sessionFileInfo) "$rel — [file size $path] bytes"
}

proc ::GX::sessionFileExplorerCopy {} {
    variable ui
    if {![info exists ui(sessionFileText)] || ![winfo exists $ui(sessionFileText)]} return
    copyTextWidget $ui(sessionFileText) "Session file"
}

proc ::GX::sessionScriptExplorerPopulate {} {
    variable ui
    if {[llength [info commands ::GX::scriptAnalysisRefresh]]} { catch {scriptAnalysisRefresh} }
    if {![info exists ui(sessionScriptTree)] || ![winfo exists $ui(sessionScriptTree)]} return
    set tree $ui(sessionScriptTree)
    $tree delete [$tree children {}]
    set ui(sessionScriptInfo) "No Session script selected."
    if {$::GX::currentSession eq ""} return
    foreach script [scriptRegistryList session $::GX::currentSession] {
        set id [dict get $script id]
        $tree insert {} end -id $id -text [dict get $script name] \
            -values [list [dict get $script language] $id [dict get $script version] [dict get $script revision] [string range [dict get $script sha256] 0 11]]
    }
}

proc ::GX::sessionScriptExplorerSelected {} {
    variable ui
    if {![info exists ui(sessionScriptTree)] || ![winfo exists $ui(sessionScriptTree)]} { return "" }
    set selection [$ui(sessionScriptTree) selection]
    if {[llength $selection] != 1} { return "" }
    return [lindex $selection 0]
}

proc ::GX::sessionScriptExplorerInspect {} {
    variable ui
    set id [sessionScriptExplorerSelected]
    if {$id eq ""} return
    if {[catch {set script [scriptRegistryRead session $id]} reason]} {
        set ui(sessionScriptInfo) $reason
        return
    }
    set ui(sessionScriptInfo) "[dict get $script language] | ID [dict get $script id] | [dict get $script name] | version [dict get $script version] | revision [dict get $script revision] | SHA-256 [dict get $script sha256] | required APIs [dict get $script required_apis] | [dict get $script description]"
}

proc ::GX::sessionScriptExplorerOpen {} {
    set id [sessionScriptExplorerSelected]
    scriptLibraryDialog
    if {$id ne ""} {
        set tree .gxtxtScriptLibrary.body.left.tree
        if {[$tree exists session:$id]} {
            $tree selection set session:$id
            $tree see session:$id
        }
    }
}

proc ::GX::sessionScriptExplorerRun {} {
    set id [sessionScriptExplorerSelected]
    if {$id eq ""} return
    set ::GX::scriptWorkspaceChoice session:$id
    scriptWorkspaceRunDialog
}

proc ::GX::buildSessionFileExplorerGui_before_sessions_page {} {
    variable ui
    set nb .top.nb
    if {![winfo exists $nb] || [winfo exists $nb.sessionfiles]} return
    ttk::frame $nb.sessionfiles
    if {[winfo exists $nb.help]} { $nb insert $nb.help $nb.sessionfiles -text "Session files" } else { $nb add $nb.sessionfiles -text "Session files" }
    set f $nb.sessionfiles
    grid columnconfigure $f 0 -weight 0; grid columnconfigure $f 1 -weight 1; grid rowconfigure $f 1 -weight 1
    ttk::combobox $f.navigation -state readonly -width 26 -values {{Session files} {Session scripts} Workspaces {Configuration / Manifest} {Session Parameters}}
    $f.navigation current 0
    grid $f.navigation -row 0 -column 0 -sticky w -padx 5 -pady 5
    ttk::frame $f.content
    grid $f.content -row 1 -column 0 -columnspan 2 -sticky nsew -padx 5 -pady 5
    grid columnconfigure $f.content 0 -weight 1;grid columnconfigure $f.content 1 -weight 2
    grid rowconfigure $f.content 0 -weight 1
    bind $f.navigation <<ComboboxSelected>> {::GX::sessionPageSelect}
    ttk::frame $f.bar
    ttk::button $f.bar.refresh -text Refresh -command ::GX::sessionFileExplorerPopulate
    ttk::button $f.bar.copy -text "Copy file text" -command ::GX::sessionFileExplorerCopy
    ttk::label $f.bar.info -textvariable ::GX::ui(sessionFileInfo) -anchor w
    pack $f.bar.refresh $f.bar.copy -side left -padx 4; pack $f.bar.info -side left -fill x -expand 1 -padx 8
    grid $f.bar -row 0 -column 1 -sticky ew -padx 5 -pady 5
    ttk::frame $f.left; ttk::frame $f.right
    grid $f.left -in $f.content -row 0 -column 0 -sticky nswe -padx {0 3}; grid $f.right -in $f.content -row 0 -column 1 -sticky nsew -padx {3 0}
    grid rowconfigure $f.left 0 -weight 1; grid columnconfigure $f.left 0 -weight 1; grid rowconfigure $f.right 0 -weight 1; grid columnconfigure $f.right 0 -weight 1
    ttk::treeview $f.left.tree -columns {kind size} -show tree
    $f.left.tree column #0 -width 320
    ttk::scrollbar $f.left.sy -orient vertical -command [list $f.left.tree yview]; $f.left.tree configure -yscrollcommand [list $f.left.sy set]
    grid $f.left.tree -row 0 -column 0 -sticky nsew; grid $f.left.sy -row 0 -column 1 -sticky ns
    text $f.right.txt -wrap none -font TkFixedFont -state disabled
    ttk::scrollbar $f.right.sy -orient vertical -command [list $f.right.txt yview]; ttk::scrollbar $f.right.sx -orient horizontal -command [list $f.right.txt xview]
    $f.right.txt configure -yscrollcommand [list $f.right.sy set] -xscrollcommand [list $f.right.sx set]
    grid $f.right.txt -row 0 -column 0 -sticky nsew; grid $f.right.sy -row 0 -column 1 -sticky ns; grid $f.right.sx -row 1 -column 0 -sticky ew
    set ui(sessionFileTree) $f.left.tree; set ui(sessionFileText) $f.right.txt; set ui(sessionFileInfo) "No session open."
    ttk::labelframe $f.scripts -text "Session scripts"
    ttk::treeview $f.scripts.tree -columns {language id version revision sha} -show {tree headings} -height 4 -selectmode browse
    $f.scripts.tree heading #0 -text Name
    foreach {column heading width} {language Language 80 id ID 180 version Version 80 revision Revision 70 sha {SHA-256 prefix} 120} {
        $f.scripts.tree heading $column -text $heading
        $f.scripts.tree column $column -width $width
    }
    pack $f.scripts.tree -side left -fill both -expand 1 -padx 4 -pady 4
    ttk::frame $f.scripts.actions
    foreach {name label command} {open {Open in Script Library} sessionScriptExplorerOpen run {Run selected} sessionScriptExplorerRun} {
        ttk::button $f.scripts.actions.$name -text $label -command [list ::GX::$command]
        pack $f.scripts.actions.$name -fill x -padx 3 -pady 3
    }
    # Reserve action labels before the table takes the remaining page width.
    pack $f.scripts.actions -side right -fill y -before $f.scripts.tree
    ttk::label $f.scriptInfo -textvariable ::GX::ui(sessionScriptInfo) -wraplength 850 -anchor w
    set ui(sessionScriptTree) $f.scripts.tree
    set ui(sessionScriptInfo) "No Session script selected."
    bind $f.scripts.tree <<TreeviewSelect>> ::GX::sessionScriptExplorerInspect
    bind $f.scripts.tree <Double-1> ::GX::sessionScriptExplorerOpen
    bind $f.left.tree <<TreeviewSelect>> {::GX::sessionFileExplorerOpenSelected}
    bind $f.left.tree <Double-1> {::GX::sessionFileExplorerOpenSelected}
    sessionFileExplorerPopulate
}

proc ::GX::augmentStandardGui_before_dataset_preview_v1 {} {
    ::GX::augmentStandardGui_v089_before_session_files
    buildSessionFileExplorerGui
}

proc ::GX::updateSessionUi_before_sessions_page {} {
    set r [::GX::updateSessionUi_v089_before_session_files]
    catch {sessionFileExplorerPopulate}
    return $r
}

proc ::GX::onNotebookChanged_before_sessions_page {nb} {
    set r [::GX::onNotebookChanged_v089_before_session_files $nb]
    if {[winfo exists $nb.sessionfiles] && [$nb select] eq "$nb.sessionfiles"} { catch {sessionFileExplorerPopulate} }
    return $r
}
