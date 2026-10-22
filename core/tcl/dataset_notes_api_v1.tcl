# GX-TXT Dataset Notes / Lightweight Markup Editor API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# v0.9.2 storage refinement:
# - user notes are real UTF-8 .md files inside the session tree;
# - dataset notes live under notes/datasets/ and remain attached to the canonical
#   Dataset ID through metadata/datasets.ini;
# - the four Experiment notebook pages use the same GX-Markup editor engine and
#   are stored under notes/experiment/;
# - metadata/datasets.ini and manifest.ini retain compatibility mirrors so older
#   v0.9.x code can still read the text, but .md is authoritative when present.

namespace eval ::GX {
    variable datasetNotesApiVersion 1
    variable datasetNotesCurrentId ""
    variable datasetNotesEditor ""
    variable datasetNotesPreview ""
    variable markupPreviewBySource
    variable markupChangeCommand
    variable experimentNoteSaveAfter
    array set markupPreviewBySource {}
    array set markupChangeCommand {}
    array set experimentNoteSaveAfter {}
}

# -----------------------------------------------------------------------------
# UTF-8 note documents and session paths
# -----------------------------------------------------------------------------
proc ::GX::noteWriteUtf8 {path text} {
    file mkdir [file dirname $path]
    set tmp "${path}.tmp.[pid]"
    set fd [open $tmp w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts -nonewline $fd $text
    close $fd
    file rename -force $tmp $path
    return $path
}

proc ::GX::noteReadUtf8 {path {default ""}} {
    if {![file isfile $path]} { return $default }
    set fd [open $path r]
    fconfigure $fd -encoding utf-8 -translation auto
    set text [read $fd]
    close $fd
    return $text
}

proc ::GX::notesRoot {{session ""}} {
    variable currentSession
    if {$session eq ""} { set session $currentSession }
    if {$session eq ""} { return "" }
    return [file join $session notes]
}

proc ::GX::datasetNoteStem {datasetId} {
    set stem [sanitize $datasetId]
    if {$stem eq ""} { set stem dataset }
    # Canonical Dataset IDs are normally already filesystem-safe.  Should an
    # imported ID contain other characters, retain uniqueness after sanitizing.
    if {$stem ne $datasetId} {
        set crc [format %08x [zlib crc32 [encoding convertto utf-8 $datasetId]]]
        append stem "_" $crc
    }
    return $stem
}

proc ::GX::datasetNoteRelativePath {datasetId} {
    return [file join notes datasets "[datasetNoteStem $datasetId].md"]
}

proc ::GX::datasetNotePath {datasetId {session ""}} {
    variable currentSession
    if {$session eq ""} { set session $currentSession }
    if {$session eq ""} { return "" }
    return [file join $session [datasetNoteRelativePath $datasetId]]
}

proc ::GX::experimentNoteSpecs {} {
    return {
        experiment_notes        notes.md
        experiment_objective    objective.md
        experiment_procedure    procedure.md
        experiment_observations observations.md
    }
}

proc ::GX::experimentNotePath {key {session ""}} {
    variable currentSession
    if {$session eq ""} { set session $currentSession }
    if {$session eq ""} { return "" }
    set filename ""
    foreach {k f} [experimentNoteSpecs] {
        if {$k eq $key} { set filename $f; break }
    }
    if {$filename eq ""} { error "Unknown Experiment note key: $key" }
    return [file join $session notes experiment $filename]
}

proc ::GX::ensureSessionNoteDirectories {{session ""}} {
    variable currentSession
    if {$session eq ""} { set session $currentSession }
    if {$session eq "" || ![file isdirectory $session]} { return }
    file mkdir [file join $session notes datasets]
    file mkdir [file join $session notes experiment]
}

# -----------------------------------------------------------------------------
# Dataset notes: .md is primary storage; registry fields are compatibility/index.
# -----------------------------------------------------------------------------
proc ::GX::datasetUserNotes {datasetId} {
    variable currentSession
    set path [datasetNotePath $datasetId]
    if {$path ne "" && [file isfile $path]} { return [noteReadUtf8 $path] }
    # Migration/fallback from the first v0.9.2 package.
    return [datasetField $datasetId user_notes_markup ""]
}

proc ::GX::datasetUserNotesSave {datasetId markup} {
    if {![datasetAuthorityActive $::GX::currentSession]} {return [datasetAuthorityTransaction $::GX::currentSession ::GX::datasetUserNotesSave $datasetId $markup]}
    variable currentSession
    if {$::GX::DatasetPrivate::activeContext ne {}} {_datasetNamespaceRequireModuleWrite $currentSession [dict get $::GX::DatasetPrivate::activeContext module_id] $datasetId}
    variable datasetRegistry
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { error "No current session." }
    loadDatasetRegistry $currentSession
    if {[datasetField $datasetId id ""] eq ""} { error "Unknown canonical dataset ID: $datasetId" }
    ensureSessionNoteDirectories $currentSession
    set rel [datasetNoteRelativePath $datasetId]
    set path [file join $currentSession $rel]
    noteWriteUtf8 $path $markup
    set datasetRegistry($datasetId,user_notes_file) $rel
    set datasetRegistry($datasetId,user_notes_format) "gx-markup-v1"
    set datasetRegistry($datasetId,user_notes_updated_at) [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]
    # Compatibility mirror for the already-released v0.9.2 metadata reader.
    set datasetRegistry($datasetId,user_notes_markup) $markup
    saveDatasetRegistry $currentSession
    catch {sessionFileExplorerPopulate}
    catch {refreshResults}
    return $path
}

proc ::GX::datasetNotesMigrateRegistryToFiles {{session ""}} {
    variable currentSession
    variable datasetRegistry
    if {$session eq ""} { set session $currentSession }
    if {$session eq "" || ![file isdirectory $session]} { return }
    ensureSessionNoteDirectories $session
    loadDatasetRegistry $session
    set changed 0
    foreach id [datasetRegistryIds] {
        set rel [datasetField $id user_notes_file ""]
        if {$rel eq ""} { set rel [datasetNoteRelativePath $id] }
        set path [file join $session $rel]
        set legacy [datasetField $id user_notes_markup ""]
        if {![file isfile $path] && $legacy ne ""} {
            noteWriteUtf8 $path $legacy
            set datasetRegistry($id,user_notes_file) $rel
            set datasetRegistry($id,user_notes_format) "gx-markup-v1"
            if {[datasetField $id user_notes_updated_at ""] eq ""} {
                set datasetRegistry($id,user_notes_updated_at) [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]
            }
            set changed 1
        } elseif {[file isfile $path] && [datasetField $id user_notes_file ""] eq ""} {
            set datasetRegistry($id,user_notes_file) $rel
            set changed 1
        }
    }
    if {$changed} { saveDatasetRegistry $session }
}

# -----------------------------------------------------------------------------
# Experiment notebook documents
# -----------------------------------------------------------------------------
proc ::GX::experimentDocumentsEnsure {{session ""}} {
    variable currentSession
    variable cfg
    if {$session eq ""} { set session $currentSession }
    if {$session eq "" || ![file isdirectory $session]} { return }
    ensureSessionNoteDirectories $session
    foreach {key filename} [experimentNoteSpecs] {
        set p [experimentNotePath $key $session]
        if {![file exists $p]} {
            set initial [expr {[info exists cfg($key)] ? $cfg($key) : ""}]
            noteWriteUtf8 $p $initial
        }
    }
}

proc ::GX::experimentDocumentsLoad {{session ""}} {
    variable currentSession
    variable cfg
    if {$session eq ""} { set session $currentSession }
    if {$session eq "" || ![file isdirectory $session]} { return }
    ensureSessionNoteDirectories $session
    foreach {key filename} [experimentNoteSpecs] {
        set p [experimentNotePath $key $session]
        if {[file isfile $p]} {
            set cfg($key) [noteReadUtf8 $p]
        } elseif {[info exists cfg($key)] && $cfg($key) ne ""} {
            # Migrate notebook text previously stored only in manifest.ini.
            noteWriteUtf8 $p $cfg($key)
        } else {
            set cfg($key) ""
            noteWriteUtf8 $p ""
        }
    }
}

proc ::GX::experimentDocumentSave {key markup} {
    variable currentSession
    variable cfg
    set cfg($key) $markup
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { return "" }
    ensureSessionNoteDirectories $currentSession
    set p [experimentNotePath $key $currentSession]
    noteWriteUtf8 $p $markup
    catch {sessionFileExplorerPopulate}
    return $p
}

proc ::GX::experimentDocumentsSaveAll {} {
    variable currentSession
    variable cfg
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { return }
    foreach {key filename} [experimentNoteSpecs] {
        experimentDocumentSave $key [expr {[info exists cfg($key)] ? $cfg($key) : ""}]
    }
}

proc ::GX::experimentMarkupChanged_impl {source key} {
    variable cfg
    variable experimentNoteSaveAfter
    if {![winfo exists $source]} return
    set cfg($key) [string trimright [$source get 1.0 end] "\n"]
    if {[info exists experimentNoteSaveAfter($key)] && $experimentNoteSaveAfter($key) ne ""} {
        catch {after cancel $experimentNoteSaveAfter($key)}
    }
    # Debounced disk persistence keeps notebook .md files current while typing.
    set experimentNoteSaveAfter($key) [after 350 [list ::GX::experimentDocumentSave $key $cfg($key)]]
}

# -----------------------------------------------------------------------------
# Generic GX-Markup v1 editing engine
# -----------------------------------------------------------------------------
proc ::GX::markupRegisterEditor {source preview {changeCommand {}}} {
    variable markupPreviewBySource
    variable markupChangeCommand
    set markupPreviewBySource($source) $preview
    set markupChangeCommand($source) $changeCommand
}

proc ::GX::markupPreviewForSource {source} {
    variable markupPreviewBySource
    if {[info exists markupPreviewBySource($source)]} { return $markupPreviewBySource($source) }
    return ""
}

proc ::GX::markupSourceChanged {source} {
    variable markupChangeCommand
    if {![winfo exists $source]} return
    markupPreviewRefreshFor $source
    if {[info exists markupChangeCommand($source)] && [llength $markupChangeCommand($source)]} {
        uplevel #0 [linsert $markupChangeCommand($source) end $source]
    }
}

proc ::GX::markupWrapSelection {w before after} {
    if {![winfo exists $w]} return
    if {![catch {$w index sel.first} a] && ![catch {$w index sel.last} b]} {
        set txt [$w get $a $b]
        $w delete $a $b
        $w insert $a "$before$txt$after"
        set end [$w index "$a + [string length "$before$txt$after"] chars"]
        $w tag add sel $a $end
    } else {
        $w insert insert "$before$after"
        $w mark set insert "insert - [string length $after] chars"
    }
    markupSourceChanged $w
}

proc ::GX::markupHeading {w level} {
    if {![winfo exists $w]} return
    set level [expr {max(1,min(3,int($level)))}]
    set idx [$w index insert]
    set line [$w index "$idx linestart"]
    set old [$w get $line "$line lineend"]
    regsub {^#{1,3}[[:space:]]+} $old "" old
    $w delete $line "$line lineend"
    $w insert $line "[string repeat # $level] $old"
    markupSourceChanged $w
}

proc ::GX::markupCodeBlock {w} {
    if {![winfo exists $w]} return
    if {![catch {$w index sel.first} a] && ![catch {$w index sel.last} b]} {
        set txt [$w get $a $b]
        $w delete $a $b
        $w insert $a "```\n$txt\n```"
    } else {
        $w insert insert "```\n\n```"
        $w mark set insert "insert - 4 chars"
    }
    markupSourceChanged $w
}

proc ::GX::markupChooseColor {w} {
    set c [tk_chooseColor -title "Text color"]
    if {$c eq ""} return
    set before [format {[color=%s]} $c]
    markupWrapSelection $w $before {[/color]}
}

proc ::GX::markupPreviewInsertInline {w text} {
    # Minimal deterministic GX-Markup v1 renderer.
    set pos 0
    set n [string length $text]
    while {$pos < $n} {
        set rest [string range $text $pos end]
        if {[regexp -indices {^\[([^]]+)\]\((https?://[^ )]+)\)} $rest whole title target]} {
            lassign $whole _ e; lassign $title ts te; lassign $target us ue
            set url [string range $rest $us $ue]
            set tag "gx_link_[clock clicks]_$pos"
            $w tag configure $tag -foreground #0645ad -underline 1
            $w tag bind $tag <Button-1> [list ::GX::markupOpenWebLink $url]
            $w insert end [string range $rest $ts $te] $tag
            incr pos [expr {$e+1}]
            continue
        }
        if {[regexp -indices {^\[color=(#[0-9A-Fa-f]{6})\](.*?)\[/color\]} $rest whole color body]} {
            lassign $whole _ e; lassign $color cs ce; lassign $body bs be
            set col [string range $rest $cs $ce]
            set bodytxt [string range $rest $bs $be]
            set tag "gxcolor_[string map {# _} $col]"
            catch {$w tag configure $tag -foreground $col}
            $w insert end $bodytxt $tag
            incr pos [expr {$e+1}]
            continue
        }
        if {[regexp -indices {^\*\*([^*]+)\*\*} $rest whole body]} {
            lassign $whole _ e; lassign $body bs be
            $w insert end [string range $rest $bs $be] gx_bold
            incr pos [expr {$e+1}]
            continue
        }
        if {[regexp -indices {^\*([^*]+)\*} $rest whole body]} {
            lassign $whole _ e; lassign $body bs be
            $w insert end [string range $rest $bs $be] gx_italic
            incr pos [expr {$e+1}]
            continue
        }
        if {[regexp -indices {^`([^`]+)`} $rest whole body]} {
            lassign $whole _ e; lassign $body bs be
            $w insert end [string range $rest $bs $be] gx_code
            incr pos [expr {$e+1}]
            continue
        }
        $w insert end [string index $text $pos]
        incr pos
    }
}

proc ::GX::markupOpenWebLink {url} {
    if {![regexp {^https?://[^[:space:]]+$} $url]} return
    set opener [auto_execok xdg-open]
    if {$opener ne ""} {catch {exec $opener -- $url &}}
}

proc ::GX::markupConfigurePreviewTags {w} {
    $w tag configure gx_h1 -font {TkDefaultFont 18 bold} -spacing1 8 -spacing3 4
    $w tag configure gx_h2 -font {TkDefaultFont 15 bold} -spacing1 7 -spacing3 3
    $w tag configure gx_h3 -font {TkDefaultFont 12 bold} -spacing1 6 -spacing3 2
    $w tag configure gx_italic -font {TkDefaultFont 10 italic}
    $w tag configure gx_bold -font {TkDefaultFont 10 bold}
    $w tag configure gx_code -font TkFixedFont -background #eeeeee
    $w tag configure gx_codeblock -font TkFixedFont -background #eeeeee -lmargin1 8 -lmargin2 8
    $w tag configure gx_list -font {TkDefaultFont 10 bold} -lmargin1 12 -lmargin2 24
    $w tag configure gx_table -font TkFixedFont -background #f4f4f4
}

proc ::GX::markupPreviewRefreshFor {source} {
    set preview [markupPreviewForSource $source]
    if {$preview eq "" || ![winfo exists $source] || ![winfo exists $preview]} return
    set src [$source get 1.0 "end-1c"]
    $preview configure -state normal
    $preview delete 1.0 end
    set inCode 0
    foreach line [split $src "\n"] {
        if {[string trim $line] eq "```"} { set inCode [expr {!$inCode}]; continue }
        if {$inCode} { $preview insert end "$line\n" gx_codeblock; continue }
        if {[regexp {^(#{1,3})[[:space:]]+(.*)$} $line -> marks body]} {
            set tag "gx_h[string length $marks]"
            $preview insert end $body $tag
            $preview insert end "\n"
            continue
        }
        markupPreviewInsertInline $preview $line
        $preview insert end "\n"
    }
    $preview configure -state disabled
}

# Compatibility entry point used by the original v0.9.2 top-level editor.
proc ::GX::markupPreviewRefresh {} {
    variable datasetNotesEditor
    if {$datasetNotesEditor ne ""} { markupPreviewRefreshFor $datasetNotesEditor }
}


proc ::GX::markupToggleWrap {w} {
    if {![winfo exists $w]} return
    if {[$w cget -wrap] eq "none"} {
        $w configure -wrap word
    } else {
        $w configure -wrap none
    }
}

proc ::GX::buildMarkupEditorWidget {parent initial {changeCommand {}}} {
    grid rowconfigure $parent 1 -weight 1
    grid columnconfigure $parent 0 -weight 1

    ttk::frame $parent.tb
    ttk::panedwindow $parent.pw -orient horizontal
    ttk::frame $parent.pw.edit
    ttk::frame $parent.pw.preview
    $parent.pw add $parent.pw.edit -weight 1
    $parent.pw add $parent.pw.preview -weight 1

    set source $parent.pw.edit.t
    set preview $parent.pw.preview.t
    ttk::button $parent.tb.undo -text "Undo" -command [list catch [list $source edit undo]]
    ttk::button $parent.tb.redo -text "Redo" -command [list catch [list $source edit redo]]
    ttk::button $parent.tb.wrap -text "Wrap" -command [list ::GX::markupToggleWrap $source]
    ttk::button $parent.tb.h1 -text "H1" -command [list ::GX::markupHeading $source 1]
    ttk::button $parent.tb.h2 -text "H2" -command [list ::GX::markupHeading $source 2]
    ttk::button $parent.tb.h3 -text "H3" -command [list ::GX::markupHeading $source 3]
    ttk::button $parent.tb.i -text "Italic" -command [list ::GX::markupWrapSelection $source "*" "*"]
    ttk::button $parent.tb.b -text "Bold" -command [list ::GX::markupWrapSelection $source "**" "**"]
    ttk::button $parent.tb.code -text "Inline code" -command [list ::GX::markupWrapSelection $source "`" "`"]
    ttk::button $parent.tb.block -text "Code block" -command [list ::GX::markupCodeBlock $source]
    ttk::button $parent.tb.color -text "Color..." -command [list ::GX::markupChooseColor $source]
    ttk::button $parent.tb.preview -text "Refresh preview" -command [list ::GX::markupPreviewRefreshFor $source]
    pack $parent.tb.undo $parent.tb.redo $parent.tb.wrap $parent.tb.h1 $parent.tb.h2 $parent.tb.h3 $parent.tb.i $parent.tb.b $parent.tb.code $parent.tb.block $parent.tb.color $parent.tb.preview -side left -padx 2 -pady 4
    grid $parent.tb -row 0 -column 0 -sticky ew -padx 4 -pady {2 0}
    grid $parent.pw -row 1 -column 0 -sticky nsew -padx 4 -pady 4

    grid rowconfigure $parent.pw.edit 1 -weight 1; grid columnconfigure $parent.pw.edit 0 -weight 1
    grid rowconfigure $parent.pw.preview 1 -weight 1; grid columnconfigure $parent.pw.preview 0 -weight 1
    ttk::label $parent.pw.edit.l -text "GX-Markup / Markdown source"
    text $source -wrap word -undo 1 -autoseparators 1 -maxundo 0 -font TkFixedFont
    ttk::scrollbar $parent.pw.edit.sy -orient vertical -command [list $source yview]
    ttk::scrollbar $parent.pw.edit.sx -orient horizontal -command [list $source xview]
    $source configure -yscrollcommand [list $parent.pw.edit.sy set] -xscrollcommand [list $parent.pw.edit.sx set]
    grid $parent.pw.edit.l -row 0 -column 0 -sticky w
    grid $source -row 1 -column 0 -sticky nsew
    grid $parent.pw.edit.sy -row 1 -column 1 -sticky ns
    grid $parent.pw.edit.sx -row 2 -column 0 -sticky ew

    ttk::label $parent.pw.preview.l -text "Preview"
    text $preview -wrap word -state disabled
    ttk::scrollbar $parent.pw.preview.sy -orient vertical -command [list $preview yview]
    $preview configure -yscrollcommand [list $parent.pw.preview.sy set]
    grid $parent.pw.preview.l -row 0 -column 0 -sticky w
    grid $preview -row 1 -column 0 -sticky nsew
    grid $parent.pw.preview.sy -row 1 -column 1 -sticky ns
    markupConfigurePreviewTags $preview

    markupRegisterEditor $source $preview $changeCommand
    $source insert 1.0 $initial
    bind $source <KeyRelease> [list after idle [list ::GX::markupSourceChanged $source]]
    markupPreviewRefreshFor $source
    return [list $source $preview]
}

proc ::GX::markupEditorSave {saveCommand} {
    variable datasetNotesEditor
    if {$datasetNotesEditor eq "" || ![winfo exists $datasetNotesEditor]} return
    set txt [$datasetNotesEditor get 1.0 "end-1c"]
    uplevel #0 [linsert $saveCommand end $txt]
}

proc ::GX::openMarkupEditor {title initial saveCommand} {
    variable datasetNotesEditor
    variable datasetNotesPreview
    set w .gxMarkupEditor
    catch {destroy $w}
    toplevel $w
    wm title $w $title
    wm geometry $w 1050x700
    grid rowconfigure $w 0 -weight 1
    grid columnconfigure $w 0 -weight 1
    ttk::frame $w.editor
    grid $w.editor -row 0 -column 0 -sticky nsew -padx 4 -pady 4
    lassign [buildMarkupEditorWidget $w.editor $initial] datasetNotesEditor datasetNotesPreview

    ttk::frame $w.bottom
    ttk::label $w.bottom.hint -wraplength 780 -text {GX-Markup v1 is stored as UTF-8 .md: # headings, *italic*, **bold**, `code`, fenced code blocks, [color=#RRGGBB]text[/color].}
    ttk::button $w.bottom.save -text "Save" -command [list ::GX::markupEditorSave $saveCommand]
    ttk::button $w.bottom.close -text "Close" -command [list destroy $w]
    pack $w.bottom.close $w.bottom.save -side right -padx 4
    pack $w.bottom.hint -side left -fill x -expand 1 -padx 4
    grid $w.bottom -row 1 -column 0 -sticky ew -padx 6 -pady {0 6}
    focus $datasetNotesEditor
    return $w
}

# -----------------------------------------------------------------------------
# Dataset note GUI
# -----------------------------------------------------------------------------
proc ::GX::datasetNotesEditorSave {datasetId markup} {
    if {[catch {set p [datasetUserNotesSave $datasetId $markup]} err]} {
        tk_messageBox -icon error -message $err
        return
    }
    tk_messageBox -icon info -message "Notes saved for dataset '$datasetId'.\n\n$p"
}

proc ::GX::datasetNotesOpen {datasetId} {
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { tk_messageBox -message "Open or create a session first."; return }
    loadDatasetRegistry $currentSession
    if {[datasetField $datasetId id ""] eq ""} { tk_messageBox -icon error -message "Unknown dataset ID: $datasetId"; return }
    openMarkupEditor "Dataset notes — $datasetId" [datasetUserNotes $datasetId] [list ::GX::datasetNotesEditorSave $datasetId]
}

proc ::GX::datasetNotesChoose {} {
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { tk_messageBox -message "Open or create a session first."; return }
    loadDatasetRegistry $currentSession
    set ids [datasetRegistryIds]
    if {![llength $ids]} { tk_messageBox -message "No canonical datasets are registered in this session."; return }
    set w .datasetNotesChoose; catch {destroy $w}; toplevel $w; wm title $w "Dataset notes"
    ttk::label $w.l -text "Canonical Dataset ID:"
    ttk::combobox $w.ds -textvariable ::GX::datasetNotesCurrentId -values $ids -state readonly -width 55
    datasetSelectorAttach $w.ds ::GX::datasetRegistryIds
    set ::GX::datasetNotesCurrentId [lindex $ids 0]
    ttk::button $w.open -text "Edit notes..." -command {if {$::GX::datasetNotesCurrentId ne ""} {::GX::datasetNotesOpen $::GX::datasetNotesCurrentId}}
    ttk::button $w.close -text "Close" -command [list destroy $w]
    grid $w.l -row 0 -column 0 -padx 8 -pady 10 -sticky e
    grid $w.ds -row 0 -column 1 -padx 8 -pady 10 -sticky ew
    grid $w.open -row 1 -column 1 -padx 8 -pady {0 8} -sticky e
    grid $w.close -row 1 -column 2 -padx 8 -pady {0 8}
    grid columnconfigure $w 1 -weight 1
}

# -----------------------------------------------------------------------------
# Experiment GUI: replace the old plain text tabs with the same markup engine.
# -----------------------------------------------------------------------------
proc ::GX::addExperimentTextTab {nb name label key} {
    variable cfg
    set tab $nb.$name
    ttk::frame $tab
    $nb add $tab -text $label
    grid columnconfigure $tab 0 -weight 1
    grid columnconfigure $tab 2 -weight 1
    grid rowconfigure $tab 2 -weight 1

    # Keep the historical source-widget path "$tab.t" for GUI/backward
    # compatibility while routing editing/preview through the common GX-Markup
    # engine used by dataset notes.
    ttk::frame $tab.tb
    set source $tab.t
    set preview $tab.preview
    ttk::button $tab.tb.h1 -text "H1" -command [list ::GX::markupHeading $source 1]
    ttk::button $tab.tb.h2 -text "H2" -command [list ::GX::markupHeading $source 2]
    ttk::button $tab.tb.h3 -text "H3" -command [list ::GX::markupHeading $source 3]
    ttk::button $tab.tb.i -text "Italic" -command [list ::GX::markupWrapSelection $source "*" "*"]
    ttk::button $tab.tb.b -text "Bold" -command [list ::GX::markupWrapSelection $source "**" "**"]
    ttk::button $tab.tb.code -text "Inline code" -command [list ::GX::markupWrapSelection $source "`" "`"]
    ttk::button $tab.tb.block -text "Code block" -command [list ::GX::markupCodeBlock $source]
    ttk::button $tab.tb.color -text "Color..." -command [list ::GX::markupChooseColor $source]
    ttk::button $tab.tb.refresh -text "Refresh preview" -command [list ::GX::markupPreviewRefreshFor $source]
    pack $tab.tb.h1 $tab.tb.h2 $tab.tb.h3 $tab.tb.i $tab.tb.b $tab.tb.code $tab.tb.block $tab.tb.color $tab.tb.refresh -side left -padx 2 -pady 3
    grid $tab.tb -row 0 -column 0 -columnspan 4 -sticky ew -padx 4 -pady {2 0}

    ttk::label $tab.srcLabel -text "GX-Markup / Markdown source"
    ttk::label $tab.previewLabel -text "Preview"
    grid $tab.srcLabel -row 1 -column 0 -sticky w -padx 4
    grid $tab.previewLabel -row 1 -column 2 -sticky w -padx 4

    text $source -wrap word -undo 1 -font TkFixedFont
    ttk::scrollbar $tab.sy -orient vertical -command [list $source yview]
    $source configure -yscrollcommand [list $tab.sy set]
    text $preview -wrap word -state disabled
    ttk::scrollbar $tab.psy -orient vertical -command [list $preview yview]
    $preview configure -yscrollcommand [list $tab.psy set]
    grid $source -row 2 -column 0 -sticky nsew -padx {4 0} -pady {0 4}
    grid $tab.sy -row 2 -column 1 -sticky ns -pady {0 4}
    grid $preview -row 2 -column 2 -sticky nsew -padx {8 0} -pady {0 4}
    grid $tab.psy -row 2 -column 3 -sticky ns -padx {0 4} -pady {0 4}
    markupConfigurePreviewTags $preview

    set initial [expr {[info exists cfg($key)] ? $cfg($key) : ""}]
    markupRegisterEditor $source $preview [list ::GX::experimentMarkupChanged $key]
    $source insert 1.0 $initial
    bind $source <KeyRelease> [list after idle [list ::GX::markupSourceChanged $source]]
    markupPreviewRefreshFor $source
}
# experimentMarkupChanged is called as commandPrefix + source by the generic
# editor; adapt the argument order used above.
proc ::GX::experimentMarkupChanged {key source} {
    ::GX::experimentMarkupChanged_impl $source $key
}

# -----------------------------------------------------------------------------
# Session file explorer integration: .md notes are visible in the existing tree
# and can be opened in the same editor directly from that tab.
# -----------------------------------------------------------------------------
proc ::GX::sessionSelectedPath {} {
    variable ui
    variable currentSession
    if {![info exists ui(sessionFileTree)] || ![winfo exists $ui(sessionFileTree)]} { return "" }
    set sel [$ui(sessionFileTree) selection]
    if {[llength $sel] != 1} { return "" }
    set id [lindex $sel 0]
    if {![string match "f:*" $id]} { return "" }
    set rel [string range $id 2 end]
    return [file normalize [file join $currentSession $rel]]
}

proc ::GX::sessionNoteSaveFromExplorer {path markup} {
    variable currentSession
    variable cfg
    variable datasetRegistry
    sessionFileExplorerRelative $path
    set rel [sessionFileExplorerRelative $path]
    if {![string match "notes/*" [string map {\\ /} $rel]] || [string tolower [file extension $path]] ne ".md"} {
        error "Only Markdown files under the session notes/ directory are editable here."
    }
    noteWriteUtf8 $path $markup

    # Keep compatibility metadata synchronized when a note is edited from the
    # Session files tab rather than through its dedicated Dataset/Experiment UI.
    if {[string match "notes/datasets/*" [string map {\\ /} $rel]]} {
        loadDatasetRegistry $currentSession
        foreach id [datasetRegistryIds] {
            set nrel [datasetField $id user_notes_file ""]
            if {$nrel eq ""} { set nrel [datasetNoteRelativePath $id] }
            if {[string map {\\ /} $nrel] eq [string map {\\ /} $rel]} {
                set datasetRegistry($id,user_notes_file) $rel
                set datasetRegistry($id,user_notes_markup) $markup
                set datasetRegistry($id,user_notes_format) "gx-markup-v1"
                set datasetRegistry($id,user_notes_updated_at) [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]
                saveDatasetRegistry $currentSession
                break
            }
        }
    } elseif {[string match "notes/experiment/*" [string map {\\ /} $rel]]} {
        foreach {key filename} [experimentNoteSpecs] {
            if {[file tail $path] eq $filename} { set cfg($key) $markup; break }
        }
    }
    catch {sessionFileExplorerPopulate}
    catch {sessionFileExplorerOpenSelected}
    catch {refreshResults}
}

proc ::GX::sessionFileExplorerEditSelected {} {
    set path [sessionSelectedPath]
    if {$path eq ""} { tk_messageBox -message "Select a Markdown note file first."; return }
    set rel [sessionFileExplorerRelative $path]
    if {![string match "notes/*" [string map {\\ /} $rel]] || [string tolower [file extension $path]] ne ".md"} {
        tk_messageBox -icon info -message "Only .md files in the session notes/ directory are editable with the GX-Markup editor."
        return
    }
    openMarkupEditor "Session note — $rel" [noteReadUtf8 $path] [list ::GX::sessionNoteSaveFromExplorer $path]
}

# -----------------------------------------------------------------------------
# Framework lifecycle integration / migration
# -----------------------------------------------------------------------------
proc ::GX::makeSession {} {
    set session [::GX::makeSession_v092_before_note_files]
    ensureSessionNoteDirectories $session
    experimentDocumentsEnsure $session
    return $session
}

proc ::GX::saveCurrentSessionConfig_before_project_api_v1 {} {
    catch {experimentDocumentsSaveAll}
    set r [::GX::saveCurrentSessionConfig_v092_before_note_files]
    catch {sessionFileExplorerPopulate}
    return $r
}

proc ::GX::chooseSession {} {
    set before $::GX::currentSession
    set r [::GX::chooseSession_v092_before_note_files]
    # openSessionPath already refreshes the effective Experiment panel. A
    # cancelled chooser/switch must leave the current editor's draft intact.
    if {$::GX::currentSession eq $before} {return $r}
    if {$::GX::currentSession ne "" && [file isdirectory $::GX::currentSession]} {
        catch {datasetNotesMigrateRegistryToFiles $::GX::currentSession}
        catch {experimentDocumentsLoad $::GX::currentSession}
        catch {rebuildNativeExperimentGui}
        catch {sessionFileExplorerPopulate}
    }
    return $r
}

# Results expose whether a dataset carries user-authored notes and where the
# corresponding Markdown file lives.
# Retain the older Results text-widget path for programmatic and historical GUI callers.
proc ::GX::refreshResults {} {return [resultsRefresh]}

# Add reusable entry points without disturbing the existing Results/Session
# Files layouts.
proc ::GX::launchGui_before_plugin_install_v1 {} {
    ::GX::launchGui_v091_before_dataset_notes
    set f .top.nb.results.buttons
    if {[winfo exists $f] && ![winfo exists $f.datasetnotes]} {
        ttk::button $f.datasetnotes -text "Dataset notes..." -command ::GX::datasetNotesChoose
        pack $f.datasetnotes -side left -padx 4
    }
    set sf .top.nb.sessionfiles.bar
    if {[winfo exists $sf] && ![winfo exists $sf.editnote]} {
        ttk::button $sf.editnote -text "Edit note..." -command ::GX::sessionFileExplorerEditSelected
        pack $sf.editnote -side left -padx 4 -after $sf.copy
    }
    if {$::GX::currentSession ne "" && [file isdirectory $::GX::currentSession]} {
        catch {datasetNotesMigrateRegistryToFiles $::GX::currentSession}
        catch {experimentDocumentsLoad $::GX::currentSession}
        catch {rebuildNativeExperimentGui}
        catch {sessionFileExplorerPopulate}
    }
}

# -----------------------------------------------------------------------------
# v0.9.2 refinement: Session files renders Markdown notes by default.
# The source markup is shown only inside the GX-Markup editor.
# -----------------------------------------------------------------------------
proc ::GX::markupRenderStringToWidget {w src {imageCommand {}}} {
    if {![winfo exists $w]} return
    markupConfigurePreviewTags $w
    $w configure -state normal -wrap word
    $w delete 1.0 end
    set inCode 0
    set paragraph {}
    foreach line [split $src "\n"] {
        # Inline delimiters can span source lines within one ordinary paragraph.
        # Keep the original newlines, and flush before every existing block kind.
        if {!$inCode && [string trim $line] ne {} &&
            ![regexp {^```[[:alnum:]_+.-]*$} [string trim $line]] &&
            !($imageCommand ne {} && [regexp {^!\[([^]]*)\]\(([^)]+)\)[[:space:]]*$} $line]) &&
            ![regexp {^(#{1,3})[[:space:]]+} $line] &&
            ![regexp {^[[:space:]]*([-*]|[0-9]+[.])[[:space:]]+} $line] &&
            ![regexp {^[[:space:]]*\|.*\|[[:space:]]*$} $line]} {
            lappend paragraph $line
            continue
        }
        if {[llength $paragraph]} {
            markupPreviewInsertInline $w [join $paragraph "\n"]
            $w insert end "\n"
            set paragraph {}
        }
        if {[regexp {^```[[:alnum:]_+.-]*$} [string trim $line]]} { set inCode [expr {!$inCode}]; continue }
        if {$inCode} { $w insert end "$line\n" gx_codeblock; continue }
        if {$imageCommand ne {} && [regexp {^!\[([^]]*)\]\(([^)]+)\)[[:space:]]*$} $line -> caption relative]} {
            {*}$imageCommand $w $relative $caption
            continue
        }
        if {[regexp {^(#{1,3})[[:space:]]+(.*)$} $line -> marks body]} {
            $w insert end $body "gx_h[string length $marks]"
            $w insert end "\n"
            continue
        }
        if {[regexp {^[[:space:]]*([-*]|[0-9]+[.])[[:space:]]+(.*)$} $line -> marker body]} {
            $w insert end "  $marker  " gx_list
            markupPreviewInsertInline $w $body
            $w insert end "\n"
            continue
        }
        if {[regexp {^[[:space:]]*\|.*\|[[:space:]]*$} $line]} {
            if {[regexp {^\|[[:space:]|:-]+\|$} [string trim $line]]} continue
            $w insert end "[string trim $line]\n" gx_table
            continue
        }
        markupPreviewInsertInline $w $line
        $w insert end "\n"
    }
    if {[llength $paragraph]} {
        markupPreviewInsertInline $w [join $paragraph "\n"]
        $w insert end "\n"
    }
    $w configure -state disabled
}

proc ::GX::sessionFileExplorerOpenSelected {} {
    variable ui
    variable currentSession
    set run [sessionFileExplorerRunSelected]
    if {$run ne {} && [string match "d:*" [$ui(sessionFileTree) selection]]} {
        set ui(sessionFileInfo) "Execution $run — analysis/scripts/$run. Open job details for immutable identity and complete log."
        return
    }
    set path [sessionSelectedPath]
    if {$path eq ""} { return [::GX::sessionFileExplorerOpenSelected_v092_before_rendered_markdown] }
    set rel [sessionFileExplorerRelative $path]
    if {[string tolower [file extension $path]] ne ".md"} {
        set r [::GX::sessionFileExplorerOpenSelected_v092_before_rendered_markdown]
        # The plain-file viewer is monospaced and non-wrapping; restore its
        # historical presentation after a rendered Markdown document.
        if {[info exists ui(sessionFileText)] && [winfo exists $ui(sessionFileText)]} { $ui(sessionFileText) configure -wrap none -font TkFixedFont }
        return $r
    }
    if {[catch {set src [sessionFileExplorerRead $path]} err]} { set src "ERROR\n$err\n" }
    set w $ui(sessionFileText)
    $w configure -font TkDefaultFont
    markupRenderStringToWidget $w $src
    set ui(sessionFileInfo) "$rel — [file size $path] bytes — rendered Markdown (Edit note... shows source)"
}
