# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX { variable importerBuilderUi }

proc ::GX::importerBuilderDialog {} {
    variable importerBuilderUi
    set w .gxtxtImporterBuilder
    if {[winfo exists $w]} {raise $w;focus $w;return}
    array set importerBuilderUi {request {} inventory_request {} inventory_generation 0 inventory_receipts {} generation 0 loading 1 baseline {} selected {} file_sha absent mapMode table mappings {}}
    toplevel $w;wm title $w {GX-TXT Importer Builder · CSV recipes};wm geometry $w 1080x740;wm minsize $w 760 580
    wm protocol $w WM_DELETE_WINDOW ::GX::importerBuilderDialogClose
    menu $w.menus -tearoff 0;$w configure -menu $w.menus
    foreach {id label} {file File edit Edit run Run view View help Help} {menu $w.menus.$id -tearoff 0;$w.menus add cascade -label $label -underline 0 -menu $w.menus.$id}
    foreach {label method} {{New recipe} New Save Save Duplicate Duplicate {Import definition…} Import {Export definition…} Export Remove Remove Close Close} {$w.menus.file add command -label $label -command [list ::GX::importerBuilderDialog$method]}
    $w.menus.file insert 1 command -label {New Acquisition plugin project…} -command {::GX::importerBuilderDialogAcquisition new}
    $w.menus.file insert 2 command -label {Open Acquisition plugin project…} -command {::GX::importerBuilderDialogAcquisition open}
    foreach {label action} {{Add mapping…} add {Edit mapping…} edit {Remove mapping} remove {Move mapping up} up {Move mapping down} down} {$w.menus.edit add command -label $label -command [list ::GX::importerBuilderDialogMapping $action]}
    foreach {label method} {{Preview source (bounded)} Preview {Test complete parser} Test {Cancel request} Cancel} {$w.menus.run add command -label $label -command [list ::GX::importerBuilderDialog$method]}
    $w.menus.view add command -label {Reload definition inventory} -command {::GX::importerBuilderDialogRefresh 1}
    $w.menus.help add command -label {Recipe workflow and limits} -command [list ::GX::documentationBrowserOpenApiWindow IMPORTER_BUILDER_API_v1 viewer.development_workspace $w]
    foreach {key method} {<Control-n> New <Control-s> Save <Control-o> Import <F5> Test <Escape> Cancel} {bind $w $key [list ::GX::importerBuilderDialog$method]}
    ttk::frame $w.footer;pack $w.footer -side bottom -fill x
    ttk::label $w.footer.status -textvariable ::GX::importerBuilderUi(status) -anchor w -wraplength 700
    ttk::progressbar $w.footer.progress -mode indeterminate -length 110
    pack $w.footer.progress -side right -padx 6;pack $w.footer.status -fill x -expand 1 -padx 6 -pady 4
    ttk::panedwindow $w.body -orient horizontal;pack $w.body -fill both -expand 1
    ttk::frame $w.left;ttk::frame $w.right;$w.body add $w.left -weight 0;$w.body add $w.right -weight 1
    ttk::label $w.left.title -text {Saved CSV recipes};pack $w.left.title -anchor w -padx 6 -pady 6
    ttk::scrollbar $w.left.scroll -orient vertical -command [list $w.left.list yview]
    listbox $w.left.list -width 18 -height 15 -exportselection 0 -yscrollcommand [list $w.left.scroll set]
    pack $w.left.scroll -side right -fill y;pack $w.left.list -fill both -expand 1
    bind $w.left.list <<ListboxSelect>> ::GX::importerBuilderDialogSelect
    ttk::panedwindow $w.right.content -orient vertical;pack $w.right.content -fill both -expand 1
    ttk::notebook $w.right.tabs;$w.right.content add $w.right.tabs -weight 3
    foreach {tab title} {general General parser Parsing mapping {Variables / Metadata}} {
        ttk::frame $w.right.tabs.$tab;$w.right.tabs add $w.right.tabs.$tab -text $title
        # Existing UIField scroll owner handles tall font18/narrow forms.
        set body [uiFieldScrollableCreate $w.right.tabs.$tab.form 600]
        pack $w.right.tabs.$tab.form -fill both -expand 1
        set importerBuilderUi(body,$tab) $body;grid columnconfigure $body 1 -weight 1
    }
    set general $importerBuilderUi(body,general);set parser $importerBuilderUi(body,parser);set mapping $importerBuilderUi(body,mapping)
    set i 0
    foreach {key label} {id {Stable ID} name {Display name} version Version description Description match_regex {Filename matching regex} contract {Dataset contract} sample {Representative file}} {
        ttk::label $general.l$key -text $label
        if {$key eq {contract}} {ttk::combobox $general.e$key -textvariable ::GX::importerBuilderUi($key) -values [contractRegistryIds]} else {ttk::entry $general.e$key -textvariable ::GX::importerBuilderUi($key)}
        grid $general.l$key -row $i -column 0 -sticky w -padx 6 -pady 4;grid $general.e$key -row $i -column 1 -columnspan 2 -sticky ew -padx 6 -pady 4
        if {$key eq {sample}} {ttk::button $general.bsample -text Browse… -command ::GX::importerBuilderDialogBrowse;grid $general.bsample -row [expr {$i+1}] -column 1 -sticky w -padx 4}
        if {$key ne {sample}} {trace add variable ::GX::importerBuilderUi($key) write ::GX::importerBuilderDialogChanged}
        if {$key eq {sample}} {incr i}
        incr i
    }
    ttk::label $general.contractState -textvariable ::GX::importerBuilderUi(contract_state) -wraplength 440 -anchor w;grid $general.contractState -row $i -column 0 -columnspan 3 -sticky ew -padx 6 -pady 4
    foreach key {id sample} {trace add variable ::GX::importerBuilderUi($key) write [list ::GX::importerBuilderDialogIdentityChanged $key]}
    set i 0
    foreach {key label} {delimiter Delimiter header_rows {Header rows} skip_leading {Physical rows before header} footer_rows {Footer data rows} comment_prefix {Comment prefix} encoding {Python input encoding} decimal {Decimal convention}} {
        ttk::label $parser.l$key -text $label
        if {$key eq {delimiter}} {ttk::combobox $parser.e$key -textvariable ::GX::importerBuilderUi($key) -values {auto comma semicolon tab whitespace} -state readonly
        } elseif {$key eq {decimal}} {ttk::combobox $parser.e$key -textvariable ::GX::importerBuilderUi($key) -values {dot comma} -state readonly
        } else {ttk::entry $parser.e$key -textvariable ::GX::importerBuilderUi($key)}
        grid $parser.l$key -row $i -column 0 -sticky w -padx 6 -pady 4;grid $parser.e$key -row $i -column 1 -sticky ew -padx 6 -pady 4
        trace add variable ::GX::importerBuilderUi($key) write ::GX::importerBuilderDialogChanged;incr i
    }
    ttk::notebook $mapping.book;grid $mapping.book -row 0 -column 0 -columnspan 3 -sticky nsew -padx 5 -pady 4
    ttk::frame $mapping.book.table;ttk::frame $mapping.book.advanced
    $mapping.book add $mapping.book.table -text {Mapping table};$mapping.book add $mapping.book.advanced -text {Advanced text}
    set tree $mapping.book.table.rows
    ttk::treeview $tree -columns {column name unit scale offset} -show headings -height 6 -selectmode browse
    foreach {id title width} {column Column 70 name Variable 160 unit Unit 90 scale Scale 85 offset Offset 85} {$tree heading $id -text $title;set extent [expr {max($width,[font measure TkHeadingFont $title]+24)}];$tree column $id -width $extent -minwidth $extent}
    ttk::scrollbar $mapping.book.table.v -orient vertical -command [list $tree yview];ttk::scrollbar $mapping.book.table.h -orient horizontal -command [list $tree xview]
    $tree configure -yscrollcommand [list $mapping.book.table.v set] -xscrollcommand [list $mapping.book.table.h set]
    grid $tree -row 0 -column 0 -sticky nsew;grid $mapping.book.table.v -row 0 -column 1 -sticky ns;grid $mapping.book.table.h -row 1 -column 0 -sticky ew;grid rowconfigure $mapping.book.table 0 -weight 1;grid columnconfigure $mapping.book.table 0 -weight 1
    bind $tree <<ThemeChanged>> +[list ::GX::_uiFieldTreeFontRows $tree GXImporterBuilder.Treeview]
    bind $tree <Map> +[list ::GX::_uiFieldTreeFontRows $tree GXImporterBuilder.Treeview]
    _uiFieldTreeFontRows $tree GXImporterBuilder.Treeview
    bind $tree <Double-1> {::GX::importerBuilderDialogMapping edit};bind $tree <Return> {::GX::importerBuilderDialogMapping edit}
    menu $tree.context -tearoff 0
    foreach {label action} {Add… add Edit… edit Remove remove Up up Down down} {$tree.context add command -label $label -command [list ::GX::importerBuilderDialogMapping $action]}
    bind $tree <Button-3> [list tk_popup $tree.context %X %Y]
    text $mapping.book.advanced.map -height 6 -width 45 -wrap none -undo 1
    ttk::scrollbar $mapping.book.advanced.v -command [list $mapping.book.advanced.map yview];ttk::scrollbar $mapping.book.advanced.h -orient horizontal -command [list $mapping.book.advanced.map xview]
    $mapping.book.advanced.map configure -yscrollcommand [list $mapping.book.advanced.v set] -xscrollcommand [list $mapping.book.advanced.h set]
    grid $mapping.book.advanced.map -row 0 -column 0 -sticky nsew;grid $mapping.book.advanced.v -row 0 -column 1 -sticky ns;grid $mapping.book.advanced.h -row 1 -column 0 -sticky ew;grid rowconfigure $mapping.book.advanced 0 -weight 1;grid columnconfigure $mapping.book.advanced 0 -weight 1
    set importerBuilderUi(mapWidget) $mapping.book.advanced.map;set importerBuilderUi(mapTree) $tree;set importerBuilderUi(mapBook) $mapping.book
    bind $mapping.book <<NotebookTabChanged>> ::GX::importerBuilderDialogMappingMode
    bind $mapping.book.advanced.map <<Modified>> ::GX::importerBuilderDialogChanged
    ttk::label $mapping.syntax -text {Advanced syntax: column | Variable | unit | scale | offset} -wraplength 480;grid $mapping.syntax -row 1 -column 0 -columnspan 3 -sticky w -padx 6
    set i 2
    foreach {key label} {metadata_name {Metadata key} metadata_filename_regex {Filename capture regex} metadata_header_regex {Header capture regex}} {
        ttk::label $mapping.l$key -text $label;ttk::entry $mapping.e$key -textvariable ::GX::importerBuilderUi($key)
        grid $mapping.l$key -row $i -column 0 -sticky w -padx 6 -pady 4;grid $mapping.e$key -row $i -column 1 -columnspan 2 -sticky ew -padx 6 -pady 4
        trace add variable ::GX::importerBuilderUi($key) write ::GX::importerBuilderDialogChanged;incr i
    }
    ttk::frame $w.right.result
    text $w.right.result.preview -height 7 -width 1 -wrap none -state disabled
    ttk::scrollbar $w.right.result.v -command [list $w.right.result.preview yview]
    ttk::scrollbar $w.right.result.h -orient horizontal -command [list $w.right.result.preview xview]
    $w.right.result.preview configure -yscrollcommand [list $w.right.result.v set] -xscrollcommand [list $w.right.result.h set]
    grid $w.right.result.preview -row 0 -column 0 -sticky nsew
    grid $w.right.result.v -row 0 -column 1 -sticky ns
    grid $w.right.result.h -row 1 -column 0 -sticky ew
    grid rowconfigure $w.right.result 0 -weight 1;grid columnconfigure $w.right.result 0 -weight 1
    $w.right.content add $w.right.result -weight 1
    uiTextEditingAttach $w [list $importerBuilderUi(mapWidget) $w.right.result.preview]
    importerBuilderDialogNew;importerBuilderDialogRefresh
}

proc ::GX::importerBuilderDialogClose {} {
    if {![importerBuilderDialogReview]} {return 0}
    importerBuilderDialogRetireRequest
    if {$::GX::importerBuilderUi(inventory_request) ne {}} {importerBuilderCancel $::GX::importerBuilderUi(inventory_request)}
    incr ::GX::importerBuilderUi(inventory_generation)
    incr ::GX::importerBuilderUi(generation)
    foreach key [dict keys [importerBuilderDefaults]] {if {$key ne {mappings}} {catch {trace remove variable ::GX::importerBuilderUi($key) write ::GX::importerBuilderDialogChanged}}}
    foreach key {id sample} {catch {trace remove variable ::GX::importerBuilderUi($key) write [list ::GX::importerBuilderDialogIdentityChanged $key]}}
    destroy .gxtxtImporterBuilder;return 1
}

proc ::GX::importerBuilderDialogNew {} {
    variable importerBuilderUi
    if {![importerBuilderDialogReview]} {return 0}
    importerBuilderDialogRetireRequest
    set importerBuilderUi(selected) {};set importerBuilderUi(file_sha) absent
    importerBuilderDialogLoad [importerBuilderDefaults]
    set importerBuilderUi(sample) {};set importerBuilderUi(status) {Enter recipe identity and mappings. Preview is bounded; Test validates the complete file.}
    .gxtxtImporterBuilder.left.list selection clear 0 end
    importerBuilderDialogShow {};return 1
}

proc ::GX::importerBuilderDialogShow {message} {
    set t .gxtxtImporterBuilder.right.result.preview
    $t configure -state normal
    $t delete 1.0 end
    $t insert end $message
    $t configure -state disabled
}

proc ::GX::importerBuilderDialogRefresh {{review 0}} {
    variable importerBuilderUi
    if {$review && ![importerBuilderDialogReview]} return
    if {$importerBuilderUi(inventory_request) ne {}} {importerBuilderCancel $importerBuilderUi(inventory_request)}
    incr importerBuilderUi(inventory_generation)
    set capture [importerBuilderDialogCapture]
    if {[catch {set token [importerBuilderReloadAsync [list ::GX::importerBuilderDialogInventoryDone $importerBuilderUi(inventory_generation) $review $capture] [list ::GX::importerBuilderDialogInventoryProgress $importerBuilderUi(inventory_generation)]]} reason]} {set importerBuilderUi(inventory_request) {};if {$importerBuilderUi(request) eq {}} {.gxtxtImporterBuilder.footer.progress stop};importerBuilderDialogRunState;set importerBuilderUi(status) "Inventory refused: $reason";return}
    set importerBuilderUi(inventory_request) $token
    importerBuilderDialogRunState
    .gxtxtImporterBuilder.footer.progress start 15
    set importerBuilderUi(status) {Reading bounded recipe inventory in the managed worker…}
}
proc ::GX::importerBuilderDialogInventoryProgress {generation token event} {
    variable importerBuilderUi
    if {![winfo exists .gxtxtImporterBuilder] || $generation!=$importerBuilderUi(inventory_generation) || $token ne $importerBuilderUi(inventory_request)} return
    if {$importerBuilderUi(request) eq {}} {set importerBuilderUi(status) "Inventory · [dict get $event rows] recipes inspected · UI remains available"}
}
proc ::GX::importerBuilderDialogInventoryDone {generation review capture token response} {
    variable importerBuilderUi
    if {![winfo exists .gxtxtImporterBuilder] || $generation!=$importerBuilderUi(inventory_generation) || $token ne $importerBuilderUi(inventory_request)} return
    set importerBuilderUi(inventory_request) {}
    importerBuilderDialogRunState
    if {$importerBuilderUi(request) eq {}} {.gxtxtImporterBuilder.footer.progress stop}
    if {![dict get $response ok]} {set importerBuilderUi(status) "Inventory failed: [dict get $response error]";return}
    set result [dict get $response result]
    set importerBuilderUi(inventory_receipts) {};set ::GX::importerBuilderDefinitions {}
    dict for {id receipt} [dict get $result items] {
        dict set receipt contract_state [importerBuilderContractState [dict get $receipt definition contract]]
        dict set importerBuilderUi(inventory_receipts) $id $receipt
        dict set ::GX::importerBuilderDefinitions $id [dict get $receipt definition]
    }
    set ::GX::importerBuilderDiagnostics [dict get $result diagnostics]
    set list .gxtxtImporterBuilder.left.list
    set importerBuilderUi(loading) 1
    $list delete 0 end
    foreach id [lsort -dictionary [dict keys $importerBuilderUi(inventory_receipts)]] {$list insert end $id}
    set importerBuilderUi(loading) 0
    importerBuilderDialogRestoreSelection
    if {$review && [dict exists $importerBuilderUi(inventory_receipts) $importerBuilderUi(selected)]} {
        if {[importerBuilderDialogCapture] eq $capture} {
            importerBuilderDialogRetireRequest
            set receipt [dict get $importerBuilderUi(inventory_receipts) $importerBuilderUi(selected)]
            set importerBuilderUi(file_sha) [dict get $receipt file_sha256]
            importerBuilderDialogLoad [dict get $receipt definition]
        } else {set importerBuilderUi(status) {Newer edits arrived during Reload; draft retained.}}
    }
    set errors {}
    foreach row $::GX::importerBuilderDiagnostics {append errors "[file tail [dict get $row path]]: [dict get $row error]\n"}
    if {$errors ne {}} {importerBuilderDialogShow "Definition inventory diagnostics:\n$errors"}
    if {$importerBuilderUi(request) eq {}} {set importerBuilderUi(status) "Inventory: [dict size $importerBuilderUi(inventory_receipts)] recipes · [llength $::GX::importerBuilderDiagnostics] diagnostics[expr {[dict get $result truncated]?{ · LIMIT REACHED; remaining files not read}:{}}]"}
    # Refresh the existing selector from the admitted snapshot; do not invoke
    # importerBuilderRefreshSelector, whose compatibility API synchronously reloads.
    if {[llength [info commands ::GX::acquisitionBrowserRefresh]] && [winfo exists .top.nb.acq.browser.tree]} {acquisitionBrowserRefresh}
}

proc ::GX::importerBuilderDialogSelect {} {
    variable importerBuilderUi
    if {$importerBuilderUi(loading)} return
    set list .gxtxtImporterBuilder.left.list;set selection [$list curselection]
    if {![llength $selection]} return
    set id [$list get [lindex $selection 0]]
    if {$id eq $importerBuilderUi(selected)} return
    if {![importerBuilderDialogReview]} {importerBuilderDialogRestoreSelection;return}
    if {![dict exists $importerBuilderUi(inventory_receipts) $id]} {set importerBuilderUi(status) {Recipe snapshot unavailable; reload the inventory.};importerBuilderDialogRestoreSelection;return}
    set receipt [dict get $importerBuilderUi(inventory_receipts) $id]
    importerBuilderDialogRetireRequest
    set importerBuilderUi(selected) $id;set importerBuilderUi(file_sha) [dict get $receipt file_sha256]
    importerBuilderDialogLoad [dict get $receipt definition]
    set importerBuilderUi(status) "Editing $id · [dict get $receipt contract_state]"
}

proc ::GX::importerBuilderDialogDefinition {} {
    variable importerBuilderUi
    set d [importerBuilderDefaults]
    foreach key [dict keys $d] {if {$key ne {mappings}} {dict set d $key $importerBuilderUi($key)}}
    dict set d mappings [expr {$importerBuilderUi(mapMode) eq {advanced}?[importerBuilderDialogMappingsParse]:$importerBuilderUi(mappings)}]
    return [importerBuilderValidate $d]
}

proc ::GX::importerBuilderDialogBrowse {} {
    set file [tk_getOpenFile -filetypes {{{Data files} {.csv .txt .tsv .dat}} {{All files} *}}]
    if {$file ne ""} { set ::GX::importerBuilderUi(sample) $file }
}

proc ::GX::importerBuilderDialogPreview {} {importerBuilderDialogStart preview}

proc ::GX::importerBuilderDialogTest {} {importerBuilderDialogStart test}

proc ::GX::importerBuilderDialogSave {} {
    variable importerBuilderUi
    if {[catch {
        set d [importerBuilderDialogDefinition]
        if {$importerBuilderUi(selected) ne {} && [dict get $d id] ne $importerBuilderUi(selected)} {error {Use Duplicate for a new ID; Save retains the loaded recipe identity}}
        set id [importerBuilderSave $d $importerBuilderUi(file_sha)]
        set receipt [importerBuilderDescribe $id]
    } reason]} {set importerBuilderUi(status) "Save failed: $reason";return 0}
    set importerBuilderUi(selected) $id;set importerBuilderUi(file_sha) [dict get $receipt file_sha256]
    importerBuilderDialogLoad [dict get $receipt definition];importerBuilderDialogRefresh
    set importerBuilderUi(status) "Saved $id · [dict get $receipt contract_state]";return 1
}

proc ::GX::importerBuilderDialogAskId {title} {
    variable importerBuilderUi
    set w .gxtxtImporterBuilder.askId;catch {destroy $w}
    uiFieldDialogCreate $w .gxtxtImporterBuilder $title
    ttk::label $w.label -text {New recipe ID}
    ttk::entry $w.entry -textvariable ::GX::importerBuilderUi(newId)
    ttk::frame $w.buttons
    ttk::button $w.buttons.ok -text OK -command {set ::GX::importerBuilderUi(askDone) 1}
    ttk::button $w.buttons.cancel -text Cancel -command {set ::GX::importerBuilderUi(askDone) 0}
    pack $w.buttons.ok $w.buttons.cancel -side left -padx 6
    pack $w.label $w.entry $w.buttons -fill x -padx 12 -pady 6
    set importerBuilderUi(newId) {};set importerBuilderUi(askDone) -1
    wm protocol $w WM_DELETE_WINDOW {set ::GX::importerBuilderUi(askDone) 0}
    bind $w <Escape> {set ::GX::importerBuilderUi(askDone) 0}
    bind $w.entry <Return> {set ::GX::importerBuilderUi(askDone) 1}
    uiTextEditingAttach $w [list $w.entry];uiFieldDialogPresent $w $w.entry 1
    tkwait variable ::GX::importerBuilderUi(askDone)
    set id [expr {$importerBuilderUi(askDone)==1?$importerBuilderUi(newId):{}}]
    uiFieldDialogClose $w
    return $id
}

proc ::GX::importerBuilderDialogDuplicate {} {
    variable importerBuilderUi
    set id [importerBuilderDialogAskId {Duplicate recipe draft}];if {$id eq {}} return
    if {[catch {set d [importerBuilderDialogDefinition];dict set d id $id;dict set d name "[dict get $d name] copy";importerBuilderSave $d absent;set receipt [importerBuilderDescribe $id]} reason]} {set importerBuilderUi(status) "Duplicate failed: $reason";return}
    importerBuilderDialogRetireRequest
    set importerBuilderUi(selected) $id;set importerBuilderUi(file_sha) [dict get $receipt file_sha256]
    importerBuilderDialogLoad [dict get $receipt definition];importerBuilderDialogRefresh;set importerBuilderUi(status) "Created $id"
}

proc ::GX::importerBuilderDialogExport {} {
    variable importerBuilderUi
    if {![importerBuilderDialogReview]} return
    set path [tk_getSaveFile -parent .gxtxtImporterBuilder -defaultextension .ini -filetypes {{{GX-TXT CSV recipe} {.ini}}}]
    if {$path eq {}} return
    if {[catch {importerBuilderExport $importerBuilderUi(selected) $path} reason]} {set importerBuilderUi(status) "Export failed: $reason";return}
    set importerBuilderUi(status) "Exported $path"
}

proc ::GX::importerBuilderDialogImport {} {
    variable importerBuilderUi
    if {![importerBuilderDialogReview]} return
    set path [tk_getOpenFile -parent .gxtxtImporterBuilder -filetypes {{{GX-TXT CSV recipe} {.ini}}}];if {$path eq {}} return
    if {[catch {set id [importerBuilderImport $path];set receipt [importerBuilderDescribe $id]} reason]} {set importerBuilderUi(status) "Import failed: $reason";return}
    importerBuilderDialogRetireRequest
    set importerBuilderUi(selected) $id;set importerBuilderUi(file_sha) [dict get $receipt file_sha256]
    importerBuilderDialogLoad [dict get $receipt definition];importerBuilderDialogRefresh
    set importerBuilderUi(status) "Imported $id"
}

proc ::GX::importerBuilderDialogRemove {} {
    variable importerBuilderUi
    set id $importerBuilderUi(selected);if {$id eq {}} return
    if {[tk_messageBox -parent .gxtxtImporterBuilder -type yesno -default no -icon question -title {Remove recipe} -message "Remove saved recipe $id? The current draft will be discarded only after a successful checked removal."] ne {yes}} return
    if {[catch {importerBuilderRemove $id $importerBuilderUi(file_sha)} reason]} {set importerBuilderUi(status) "Remove failed: $reason";return}
    set importerBuilderUi(baseline) [importerBuilderDialogCapture];importerBuilderDialogNew;importerBuilderDialogRefresh
    set importerBuilderUi(status) "Removed $id"
}

proc ::GX::importerBuilderDialogLoad {definition} {
    variable importerBuilderUi
    set importerBuilderUi(loading) 1
    dict for {key value} $definition {if {$key ne {mappings}} {set importerBuilderUi($key) $value}}
    set importerBuilderUi(mappings) [dict get $definition mappings]
    importerBuilderDialogMappingsRender
    set importerBuilderUi(loading) 0
    set importerBuilderUi(baseline) [importerBuilderDialogCapture]
    importerBuilderDialogChanged
}
proc ::GX::importerBuilderDialogCapture {} {
    variable importerBuilderUi
    set d {};foreach key [dict keys [importerBuilderDefaults]] {if {$key ne {mappings}} {dict set d $key $importerBuilderUi($key)}}
    # Capture the literal advanced draft even while malformed; no normalization
    # can hide an unsaved edit, and changing tabs is not itself a scientific edit.
    dict set d mapping_text [$importerBuilderUi(mapWidget) get 1.0 end-1c]
    return $d
}
proc ::GX::importerBuilderDialogChanged {args} {
    variable importerBuilderUi
    if {![winfo exists .gxtxtImporterBuilder] || $importerBuilderUi(loading)} return
    if {[$importerBuilderUi(mapWidget) edit modified]} {$importerBuilderUi(mapWidget) edit modified 0}
    set dirty [expr {[importerBuilderDialogCapture] ne $importerBuilderUi(baseline)}]
    set importerBuilderUi(contract_state) "Contract: [importerBuilderContractState $importerBuilderUi(contract)]"
    wm title .gxtxtImporterBuilder "GX-TXT Importer Builder · CSV recipes[expr {$dirty?{ *}:{}}]"
    importerBuilderDialogRunState
}
proc ::GX::importerBuilderDialogReview {} {
    variable importerBuilderUi
    if {![info exists importerBuilderUi(mapWidget)] || ![winfo exists $importerBuilderUi(mapWidget)] || $importerBuilderUi(loading) || [importerBuilderDialogCapture] eq $importerBuilderUi(baseline)} {return 1}
    set answer [tk_messageBox -parent .gxtxtImporterBuilder -type yesnocancel -default cancel -icon question -title {Unsaved CSV recipe} -message {Save the current recipe draft before continuing? Yes saves, No discards, Cancel keeps editing.}]
    if {$answer eq {cancel}} {return 0}
    if {$answer eq {yes}} {return [importerBuilderDialogSave]}
    return 1
}
proc ::GX::importerBuilderDialogRestoreSelection {} {
    variable importerBuilderUi
    set list .gxtxtImporterBuilder.left.list
    set importerBuilderUi(loading) 1
    $list selection clear 0 end
    set index [lsearch -exact [$list get 0 end] $importerBuilderUi(selected)]
    if {$index>=0} {$list selection set $index;$list see $index}
    set importerBuilderUi(loading) 0
}
proc ::GX::importerBuilderDialogMappingsParse {} {
    set result {}
    foreach line [split [$::GX::importerBuilderUi(mapWidget) get 1.0 end-1c] \n] {
        if {[string trim $line] eq {}} continue
        set parts [split $line |]
        if {[llength $parts]<2 || [llength $parts]>5} {error {Advanced mappings need column | Variable | unit | scale | offset}}
        while {[llength $parts]<5} {lappend parts {}}
        lassign [lmap p $parts {string trim $p}] column name unit scale offset
        lappend result [dict create column $column name $name unit $unit scale $scale offset $offset]
    }
    return $result
}
proc ::GX::importerBuilderDialogMappingsRender {} {
    variable importerBuilderUi
    set old $importerBuilderUi(loading);set importerBuilderUi(loading) 1
    set tree $importerBuilderUi(mapTree);$tree delete [$tree children {}]
    set text $importerBuilderUi(mapWidget);$text delete 1.0 end
    set i 0
    foreach m $importerBuilderUi(mappings) {
        set values {};foreach key {column name unit scale offset} {lappend values [dict get $m $key]}
        $tree insert {} end -id row[incr i] -values $values
        $text insert end "[join $values { | }]\n"
    }
    $text edit modified 0
    set importerBuilderUi(loading) $old
}
proc ::GX::importerBuilderDialogMappingMode {} {
    variable importerBuilderUi
    if {$importerBuilderUi(loading)} return
    set new [expr {[$importerBuilderUi(mapBook) select] eq "$importerBuilderUi(mapBook).advanced"?{advanced}:{table}}]
    if {$new eq $importerBuilderUi(mapMode)} return
    if {$importerBuilderUi(mapMode) eq {advanced}} {
        if {[catch {set importerBuilderUi(mappings) [importerBuilderDialogMappingsParse]} reason]} {
            set importerBuilderUi(status) $reason
            set importerBuilderUi(loading) 1;$importerBuilderUi(mapBook) select $importerBuilderUi(mapBook).advanced;set importerBuilderUi(loading) 0;return
        }
        # Render only the table, preserving the user's literal advanced text.
        set tree $importerBuilderUi(mapTree);$tree delete [$tree children {}];set i 0
        foreach m $importerBuilderUi(mappings) {set values {};foreach key {column name unit scale offset} {lappend values [dict get $m $key]};$tree insert {} end -id row[incr i] -values $values}
    }
    set importerBuilderUi(mapMode) $new
}
proc ::GX::importerBuilderDialogMapping {operation} {
    variable importerBuilderUi
    if {$importerBuilderUi(mapMode) eq {advanced}} {
        if {[catch {set importerBuilderUi(mappings) [importerBuilderDialogMappingsParse]} reason]} {set importerBuilderUi(status) $reason;return}
    }
    set tree $importerBuilderUi(mapTree);set selected [$tree selection]
    set index [expr {[llength $selected]?[$tree index [lindex $selected 0]]:-1}]
    if {$operation in {edit remove up down} && $index<0} {set importerBuilderUi(status) {Select a mapping row first.};return}
    if {$operation eq {remove}} {set importerBuilderUi(mappings) [lreplace $importerBuilderUi(mappings) $index $index];importerBuilderDialogMappingsRender;importerBuilderDialogChanged;return}
    if {$operation in {up down}} {
        set target [expr {$index+($operation eq {up}?-1:1)}]
        if {$target<0 || $target>=[llength $importerBuilderUi(mappings)]} return
        set row [lindex $importerBuilderUi(mappings) $index]
        set importerBuilderUi(mappings) [linsert [lreplace $importerBuilderUi(mappings) $index $index] $target $row]
        importerBuilderDialogMappingsRender;$tree selection set row[expr {$target+1}];$tree see row[expr {$target+1}];importerBuilderDialogChanged;return
    }
    set m [expr {$operation eq {edit}?[lindex $importerBuilderUi(mappings) $index]:[dict create column [expr {[llength $importerBuilderUi(mappings)]+1}] name {} unit {} scale {} offset {}]}]
    dict for {key value} $m {set importerBuilderUi(map,$key) $value}
    set importerBuilderUi(mapIndex) $index;set importerBuilderUi(mapOperation) $operation
    set w .gxtxtImporterBuilder.mappingEditor;catch {destroy $w}
    uiFieldDialogCreate $w .gxtxtImporterBuilder {Column mapping} 700x500
    ttk::frame $w.buttons
    ttk::button $w.buttons.save -text Apply -command ::GX::importerBuilderDialogMappingCommit
    ttk::button $w.buttons.cancel -text Cancel -command [list ::GX::uiFieldDialogClose $w]
    pack $w.buttons.save $w.buttons.cancel -side left -padx 4
    pack $w.buttons -side bottom -fill x -padx 8 -pady 6
    set body [uiFieldScrollableCreate $w.body 650];pack $w.body -fill both -expand 1
    grid columnconfigure $body 1 -weight 1
    set i 0
    foreach {key label} {column {Source column (1-based)} name {Canonical Variable} unit {Declared unit} scale {Numeric scale (optional)} offset {Numeric offset (optional)}} {
        ttk::label $body.l$key -text $label
        if {$key eq {unit} && [llength [info commands ::GX::unitRegistryList]]} {ttk::combobox $body.e$key -textvariable ::GX::importerBuilderUi(map,$key) -values [unitRegistryList]} else {ttk::entry $body.e$key -textvariable ::GX::importerBuilderUi(map,$key)}
        grid $body.l$key -row $i -column 0 -sticky w -padx 8 -pady 4;grid $body.e$key -row $i -column 1 -sticky ew -padx 8 -pady 4;incr i
    }
    ttk::label $body.info -text {Units are declared, not inferred or converted. Empty scale/offset leaves values unchanged.} -wraplength 550
    grid $body.info -row $i -column 0 -columnspan 2 -sticky ew -padx 8 -pady 6
    uiTextEditingAttach $w [lmap key {column name unit scale offset} {set x $body.e$key}]
    bind $w <Escape> [list ::GX::uiFieldDialogClose $w]
    uiFieldDialogPresent $w $body.ecolumn 0
}
proc ::GX::importerBuilderDialogMappingCommit {} {
    variable importerBuilderUi
    set m {};foreach key {column name unit scale offset} {dict set m $key $importerBuilderUi(map,$key)}
    set proposed $importerBuilderUi(mappings)
    if {$importerBuilderUi(mapOperation) eq {edit}} {set proposed [lreplace $proposed $importerBuilderUi(mapIndex) $importerBuilderUi(mapIndex) $m]} else {lappend proposed $m}
    # Validate the row schema through the existing recipe owner. Provisional
    # identity is only for row editing and never saved or used for publication.
    set d [dict merge [importerBuilderDefaults] [dict create id row_edit name {Mapping edit} mappings $proposed]]
    if {[catch {_importerBuilderValidateFields $d} reason]} {set importerBuilderUi(status) "Mapping refused: $reason";return}
    set importerBuilderUi(mappings) $proposed;importerBuilderDialogMappingsRender;importerBuilderDialogChanged
    uiFieldDialogClose .gxtxtImporterBuilder.mappingEditor
}
proc ::GX::importerBuilderDialogStart {operation} {
    variable importerBuilderUi
    if {$importerBuilderUi(request) ne {}} {set importerBuilderUi(status) {Wait for the request or choose Run → Cancel request.};return}
    incr importerBuilderUi(generation)
    if {[catch {
        set d [importerBuilderDialogDefinition]
        set importerBuilderUi(request_draft) [importerBuilderDialogCapture]
        set importerBuilderUi(request) [importerBuilderRequest $operation $d $importerBuilderUi(sample) [list ::GX::importerBuilderDialogDone $importerBuilderUi(generation)] [list ::GX::importerBuilderDialogProgress $importerBuilderUi(generation)]]
    } reason]} {set importerBuilderUi(status) "$operation failed: $reason";return}
    importerBuilderDialogRunState
    .gxtxtImporterBuilder.footer.progress start 15
    set importerBuilderUi(status) "$operation running; draft editing is preserved independently."
}
proc ::GX::importerBuilderDialogProgress {generation token event} {
    variable importerBuilderUi
    if {![winfo exists .gxtxtImporterBuilder] || $generation!=$importerBuilderUi(generation) || $token ne $importerBuilderUi(request)} return
    set importerBuilderUi(status) "[dict get $event phase] · [dict get $event rows] rows · Run → Cancel request"
}
proc ::GX::importerBuilderDialogDone {generation token response} {
    variable importerBuilderUi
    if {![winfo exists .gxtxtImporterBuilder] || $generation!=$importerBuilderUi(generation) || $token ne $importerBuilderUi(request)} return
    set importerBuilderUi(request) {}; if {$importerBuilderUi(inventory_request) eq {}} {.gxtxtImporterBuilder.footer.progress stop}
    importerBuilderDialogRunState
    if {![dict get $response ok]} {set importerBuilderUi(status) "Request refused: [dict get $response error]";return}
    set r [dict get $response result]
    set captured [importerBuilderRequestInspect $token]
    set metadata [importerBuilderMetadataFromText [dict get $r definition] [dict get $captured source] [dict get $r header_text]]
    set diagnostic [datasetPublicationV2DictDefault [dict get $r parser_result] diagnostic {}]
    set state [expr {[importerBuilderDialogCapture] eq $importerBuilderUi(request_draft)?{CURRENT_CAPTURE}:{STALE_DRAFT · captured result only}}]
    set context "Recipe [dict get $r definition id] · Source [file tail [dict get $captured source]] · $state"
    importerBuilderDialogShow "$context\n[dict get $r report]\nDigest scope: [dict get $r digest_scope] · bytes read: [dict get $r bytes_read]\nConfig SHA: [dict get $r config_sha256]\nMetadata: $metadata\n$diagnostic\n\nSource sample:\n[dict get $r source_preview]\n\nCanonical sample:\n[dict get $r preview]"
    set importerBuilderUi(status) "[dict get $r report] · $context"
}
proc ::GX::importerBuilderDialogCancel {} {
    variable importerBuilderUi
    set requested 0
    foreach key {request inventory_request} {if {[info exists importerBuilderUi($key)] && $importerBuilderUi($key) ne {}} {importerBuilderCancel $importerBuilderUi($key);set requested 1}}
    if {$requested} {set importerBuilderUi(status) {Cancellation requested; temporary resources close after worker shutdown.}}
}

proc ::GX::importerBuilderDialogRunState {} {
    variable importerBuilderUi
    if {![winfo exists .gxtxtImporterBuilder] || ![info exists importerBuilderUi(contract)]} return
    set idle [expr {$importerBuilderUi(request) eq {}}]
    set available [expr {$idle && [importerBuilderContractState $importerBuilderUi(contract)] eq {KNOWN_COMPATIBLE}}]
    foreach label {{Preview source (bounded)} {Test complete parser}} {.gxtxtImporterBuilder.menus.run entryconfigure $label -state [expr {$available?{normal}:{disabled}}]}
    .gxtxtImporterBuilder.menus.run entryconfigure {Cancel request} -state [expr {$idle && $importerBuilderUi(inventory_request) eq {}?{disabled}:{normal}}]
}

proc ::GX::importerBuilderDialogRetireRequest {} {
    variable importerBuilderUi
    if {[info exists importerBuilderUi(request)] && $importerBuilderUi(request) ne {}} {importerBuilderCancel $importerBuilderUi(request)}
    set importerBuilderUi(request) {};incr importerBuilderUi(generation)
    if {[winfo exists .gxtxtImporterBuilder.right.result.preview]} {importerBuilderDialogShow {}}
    if {[winfo exists .gxtxtImporterBuilder] && [info exists importerBuilderUi(inventory_request)]} {
        if {$importerBuilderUi(inventory_request) eq {}} {.gxtxtImporterBuilder.footer.progress stop}
        importerBuilderDialogRunState
    }
}
proc ::GX::importerBuilderDialogIdentityChanged {key args} {
    variable importerBuilderUi
    set current $importerBuilderUi($key)
    set changed [expr {![info exists importerBuilderUi(identity,$key)] || $importerBuilderUi(identity,$key) ne $current}]
    set importerBuilderUi(identity,$key) $current
    if {$importerBuilderUi(loading) || !$changed} return
    importerBuilderDialogRetireRequest
    set importerBuilderUi(status) {Recipe/source identity changed; earlier request retired. Choose Run for the new source.}
}

proc ::GX::importerBuilderDialogAcquisition {action} {
    # Opening an adjacent project window does not replace/discard the CSV draft.
    if {![llength [info commands ::GX::AcquisitionPluginBuilder::open]]} {source [file join $::GX::scriptDir app gui acquisition_plugin_builder_dialog.tcl]}
    ::GX::AcquisitionPluginBuilder::open $action
}
