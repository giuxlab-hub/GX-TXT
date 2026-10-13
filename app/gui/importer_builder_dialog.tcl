# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX { variable importerBuilderUi }

proc ::GX::importerBuilderDialog {} {
    variable importerBuilderUi
    set w .gxtxtImporterBuilder
    if {[winfo exists $w]} { raise $w; focus $w; return }
    toplevel $w
    wm title $w "GX-TXT Importer Builder"
    wm geometry $w 1080x740
    wm minsize $w 820 600
    ttk::frame $w.left
    ttk::label $w.left.title -text "Reusable importers"
    listbox $w.left.list -height 18 -exportselection 0
    ttk::scrollbar $w.left.scroll -orient vertical -command [list $w.left.list yview]
    $w.left.list configure -yscrollcommand [list $w.left.scroll set]
    pack $w.left.title -anchor w -padx 6 -pady 6
    pack $w.left.scroll -side right -fill y
    pack $w.left.list -side left -fill both -expand 1
    pack $w.left -side left -fill y -padx 6 -pady 6
    bind $w.left.list <<ListboxSelect>> ::GX::importerBuilderDialogSelect

    ttk::frame $w.right
    pack $w.right -side left -fill both -expand 1 -padx 6 -pady 6
    ttk::notebook $w.right.tabs
    pack $w.right.tabs -fill both -expand 1
    foreach {tab title} {general General parser Parsing mapping {Variables / Metadata}} {
        ttk::frame $w.right.tabs.$tab
        $w.right.tabs add $w.right.tabs.$tab -text $title
        grid columnconfigure $w.right.tabs.$tab 1 -weight 1
    }
    set general $w.right.tabs.general
    set parser $w.right.tabs.parser
    set mapping $w.right.tabs.mapping
    set i 0
    foreach {key label} {id {Stable ID} name {Display name} version Version description Description match_regex {Filename matching regex} contract {Dataset contract} sample {Representative file}} {
        ttk::label $general.l$key -text $label
        ttk::entry $general.e$key -textvariable ::GX::importerBuilderUi($key)
        grid $general.l$key -row $i -column 0 -sticky e -padx 7 -pady 5
        grid $general.e$key -row $i -column 1 -sticky ew -padx 7 -pady 5
        if {$key eq "sample"} {
            ttk::button $general.bsample -text "Browse..." -command ::GX::importerBuilderDialogBrowse
            grid $general.bsample -row $i -column 2 -padx 5
        }
        incr i
    }
    ttk::label $general.help -text "Definitions live in your GX-TXT user library. A Session stores the importer ID/version in Dataset provenance." -wraplength 650 -justify left
    grid $general.help -row $i -column 0 -columnspan 3 -sticky ew -padx 8 -pady 12
    set i 0
    foreach {key label} {delimiter Delimiter header_rows {Header rows} skip_leading {Physical rows before header} footer_rows {Footer data rows} comment_prefix {Comment prefix} encoding {Input encoding} decimal {Decimal convention}} {
        ttk::label $parser.l$key -text $label
        if {$key eq "delimiter"} {
            ttk::combobox $parser.e$key -textvariable ::GX::importerBuilderUi($key) -values {auto comma semicolon tab whitespace} -state readonly
        } elseif {$key eq "decimal"} {
            ttk::combobox $parser.e$key -textvariable ::GX::importerBuilderUi($key) -values {dot comma} -state readonly
        } else {
            ttk::entry $parser.e$key -textvariable ::GX::importerBuilderUi($key)
        }
        grid $parser.l$key -row $i -column 0 -sticky e -padx 7 -pady 5
        grid $parser.e$key -row $i -column 1 -sticky ew -padx 7 -pady 5
        incr i
    }
    ttk::label $parser.help -text "Whitespace parses space/tab-separated columns. Comments and blank lines are ignored. Numeric scale/offset and decimal conversion affect canonical data only; RAW remains intact." -wraplength 650 -justify left
    grid $parser.help -row $i -column 0 -columnspan 2 -sticky ew -padx 8 -pady 12
    ttk::label $mapping.lmap -text "Column mappings, one per line: source column | canonical Variable | unit | scale | offset"
    grid $mapping.lmap -row 0 -column 0 -columnspan 2 -sticky w -padx 7 -pady 5
    text $mapping.map -height 8 -width 65 -wrap none -undo 1
    ttk::scrollbar $mapping.maps -orient vertical -command [list $mapping.map yview]
    $mapping.map configure -yscrollcommand [list $mapping.maps set]
    grid $mapping.map -row 1 -column 0 -columnspan 2 -sticky nsew -padx 7
    grid $mapping.maps -row 1 -column 2 -sticky ns
    grid rowconfigure $mapping 1 -weight 1
    set i 2
    foreach {key label} {metadata_name {Metadata key} metadata_filename_regex {Filename capture regex} metadata_header_regex {Header capture regex}} {
        ttk::label $mapping.l$key -text $label
        ttk::entry $mapping.e$key -textvariable ::GX::importerBuilderUi($key)
        grid $mapping.l$key -row $i -column 0 -sticky e -padx 7 -pady 5
        grid $mapping.e$key -row $i -column 1 -sticky ew -padx 7 -pady 5
        incr i
    }
    ttk::label $mapping.help -text {Use one capture group in a regex. Metadata is saved with the imported Dataset. Example: ^run_([0-9]+)\.csv$} -wraplength 650 -justify left
    grid $mapping.help -row $i -column 0 -columnspan 2 -sticky ew -padx 7 -pady 6

    ttk::frame $w.right.buttons
    foreach {key label action} {new New importerBuilderDialogNew preview {Preview source} importerBuilderDialogPreview test {Test parser} importerBuilderDialogTest save Save importerBuilderDialogSave duplicate Duplicate importerBuilderDialogDuplicate export Export importerBuilderDialogExport import Import importerBuilderDialogImport remove Remove importerBuilderDialogRemove close Close importerBuilderDialogClose} {
        ttk::button $w.right.buttons.$key -text $label -command [list ::GX::$action]
        pack $w.right.buttons.$key -side left -padx 3 -pady 5
    }
    pack $w.right.buttons -fill x
    ttk::label $w.right.status -textvariable ::GX::importerBuilderUi(status) -anchor w
    pack $w.right.status -fill x -padx 5
    text $w.right.preview -height 9 -wrap none -state disabled
    pack $w.right.preview -fill both -expand 0 -padx 5 -pady 5
    importerBuilderDialogNew
    importerBuilderDialogRefresh
}

proc ::GX::importerBuilderDialogClose {} { destroy .gxtxtImporterBuilder }

proc ::GX::importerBuilderDialogNew {} {
    variable importerBuilderUi
    dict for {key value} [importerBuilderDefaults] {
        if {$key ne "mappings"} { set importerBuilderUi($key) $value }
    }
    set importerBuilderUi(sample) ""
    set importerBuilderUi(status) "Enter an ID, sample file and column mappings."
    set t .gxtxtImporterBuilder.right.tabs.mapping.map
    $t delete 1.0 end
    importerBuilderDialogShow ""
}

proc ::GX::importerBuilderDialogShow {message} {
    set t .gxtxtImporterBuilder.right.preview
    $t configure -state normal
    $t delete 1.0 end
    $t insert end $message
    $t configure -state disabled
}

proc ::GX::importerBuilderDialogRefresh {} {
    importerBuilderReload
    importerBuilderRefreshSelector
    set list .gxtxtImporterBuilder.left.list
    if {![winfo exists $list]} return
    $list delete 0 end
    foreach id [lsort -dictionary [dict keys $::GX::importerBuilderDefinitions]] { $list insert end $id }
}

proc ::GX::importerBuilderDialogSelect {} {
    variable importerBuilderUi
    set list .gxtxtImporterBuilder.left.list
    set selected [$list curselection]
    if {![llength $selected]} return
    set d [importerBuilderGet [$list get [lindex $selected 0]]]
    dict for {key value} $d {
        if {$key ne "mappings"} { set importerBuilderUi($key) $value }
    }
    set t .gxtxtImporterBuilder.right.tabs.mapping.map
    $t delete 1.0 end
    foreach m [dict get $d mappings] {
        $t insert end "[dict get $m column] | [dict get $m name] | [dict get $m unit] | [dict get $m scale] | [dict get $m offset]\n"
    }
    set importerBuilderUi(status) "Editing [dict get $d id] v[dict get $d version]"
}

proc ::GX::importerBuilderDialogDefinition {} {
    variable importerBuilderUi
    set d [importerBuilderDefaults]
    foreach key [dict keys $d] {
        if {$key ne "mappings"} { dict set d $key $importerBuilderUi($key) }
    }
    set mappings {}
    set t .gxtxtImporterBuilder.right.tabs.mapping.map
    foreach line [split [$t get 1.0 end-1c] "\n"] {
        if {[string trim $line] eq ""} continue
        set parts [split $line |]
        if {[llength $parts] < 2 || [llength $parts] > 5} { error "Mapping lines need column | Variable | unit | scale | offset." }
        while {[llength $parts] < 5} { lappend parts "" }
        lassign [lmap p $parts {string trim $p}] column name unit scale offset
        lappend mappings [dict create column $column name $name unit $unit scale $scale offset $offset]
    }
    dict set d mappings $mappings
    return [importerBuilderValidate $d]
}

proc ::GX::importerBuilderDialogBrowse {} {
    set file [tk_getOpenFile -filetypes {{{Data files} {.csv .txt .tsv .dat}} {{All files} *}}]
    if {$file ne ""} { set ::GX::importerBuilderUi(sample) $file }
}

proc ::GX::importerBuilderDialogPreview {} {
    variable importerBuilderUi
    set path $importerBuilderUi(sample)
    if {![file isfile $path]} { set importerBuilderUi(status) "Select an existing representative file."; return }
    set ch [open $path r]
    fconfigure $ch -encoding utf-8
    set lines {}
    try {
        for {set i 0} {$i < 30 && [gets $ch line] >= 0} {incr i} { lappend lines $line }
    } finally { close $ch }
    importerBuilderDialogShow [join $lines "\n"]
    set importerBuilderUi(status) "Source preview: [file tail $path]"
}

proc ::GX::importerBuilderDialogTest {} {
    variable importerBuilderUi
    if {[catch {
        set d [importerBuilderDialogDefinition]
        set result [importerBuilderTest $d $importerBuilderUi(sample)]
    } reason]} {
        set importerBuilderUi(status) "Test failed: $reason"
        return
    }
    importerBuilderDialogShow [dict get $result preview]
    set importerBuilderUi(status) "Parser passed: [dict get $result report]"
}

proc ::GX::importerBuilderDialogSave {} {
    variable importerBuilderUi
    if {[catch {set id [importerBuilderSave [importerBuilderDialogDefinition]]} reason]} {
        set importerBuilderUi(status) "Save failed: $reason"
        return
    }
    importerBuilderDialogRefresh
    set importerBuilderUi(status) "Saved importer $id in your user library."
}

proc ::GX::importerBuilderDialogAskId {title} {
    set w .gxtxtImporterBuilder.askId
    catch {destroy $w}
    toplevel $w
    wm title $w $title
    ttk::label $w.label -text "New importer ID"
    ttk::entry $w.entry -textvariable ::GX::importerBuilderUi(newId)
    ttk::button $w.ok -text OK -command [list set ::GX::importerBuilderUi(askDone) 1]
    ttk::button $w.cancel -text Cancel -command [list set ::GX::importerBuilderUi(askDone) 0]
    pack $w.label $w.entry -fill x -padx 10 -pady 5
    pack $w.ok $w.cancel -side left -padx 10 -pady 8
    set ::GX::importerBuilderUi(newId) ""
    set ::GX::importerBuilderUi(askDone) -1
    focus $w.entry
    tkwait variable ::GX::importerBuilderUi(askDone)
    set id [expr {$::GX::importerBuilderUi(askDone) ? $::GX::importerBuilderUi(newId) : ""}]
    destroy $w
    return $id
}

proc ::GX::importerBuilderDialogDuplicate {} {
    variable importerBuilderUi
    set id [importerBuilderDialogAskId "Duplicate importer"]
    if {$id eq ""} return
    if {[catch {set duplicate [importerBuilderDuplicate $importerBuilderUi(id) $id]} reason]} {
        set importerBuilderUi(status) "Duplicate failed: $reason"; return
    }
    importerBuilderDialogRefresh
    set importerBuilderUi(status) "Created importer $duplicate."
}

proc ::GX::importerBuilderDialogExport {} {
    variable importerBuilderUi
    set path [tk_getSaveFile -defaultextension .ini -filetypes {{{GX-TXT importer definitions} {.ini}}}]
    if {$path eq ""} return
    if {[catch {importerBuilderExport $importerBuilderUi(id) $path} reason]} {
        set importerBuilderUi(status) "Export failed: $reason"; return
    }
    set importerBuilderUi(status) "Exported importer to $path"
}

proc ::GX::importerBuilderDialogImport {} {
    variable importerBuilderUi
    set path [tk_getOpenFile -filetypes {{{GX-TXT importer definitions} {.ini}}}]
    if {$path eq ""} return
    if {[catch {set id [importerBuilderImport $path]} reason]} {
        set importerBuilderUi(status) "Import failed: $reason"; return
    }
    importerBuilderDialogRefresh
    set importerBuilderUi(status) "Imported reusable definition $id."
}

proc ::GX::importerBuilderDialogRemove {} {
    variable importerBuilderUi
    set id $importerBuilderUi(id)
    if {$id eq ""} return
    if {[tk_messageBox -type yesno -icon question -title "Remove importer" -message "Remove importer $id from your user library?"] ne "yes"} return
    if {[catch {importerBuilderRemove $id} reason]} {
        set importerBuilderUi(status) "Remove failed: $reason"; return
    }
    importerBuilderDialogNew
    importerBuilderDialogRefresh
    set importerBuilderUi(status) "Removed importer $id."
}
