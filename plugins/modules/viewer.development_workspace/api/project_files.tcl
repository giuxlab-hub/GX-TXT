# SPDX-License-Identifier: GPL-3.0-or-later
# File-aware presentation of the existing Development project/source owner.
# Every editable tab is an independent shared Source Surface, never a program.
proc ::GX::ViewerDevelopmentWorkspace::projectTabsReset {} {
    variable s
    if {[info exists ::GX::ViewerDevelopmentWorkspace::debug(request)] && $::GX::ViewerDevelopmentWorkspace::debug(request) ne {}} {
        # A copied project can have identical hashes at another path. Drain the
        # old managed debugger before reusing this window for that new root.
        set previous $s(busy);set request $::GX::ViewerDevelopmentWorkspace::debug(request)
        set s(busy) $request;controls;debugStop
        try {vwait ::GX::ViewerDevelopmentWorkspace::debug(request)} finally {if {$s(busy) eq $request} {set s(busy) $previous;controls}}
    }
    if {[info exists ::GX::ViewerDevelopmentWorkspace::debug(poll)] && $::GX::ViewerDevelopmentWorkspace::debug(poll) ne {}} {::GX::scriptJobRequestCancel $::GX::ViewerDevelopmentWorkspace::debug(poll) closed;set ::GX::ViewerDevelopmentWorkspace::debug(poll) {}}
    if {[info exists ::GX::ViewerDevelopmentWorkspace::debug(generation)]} {
        incr ::GX::ViewerDevelopmentWorkspace::debug(generation)
        set ::GX::ViewerDevelopmentWorkspace::debug(snapshot) {};set ::GX::ViewerDevelopmentWorkspace::debug(sequence) -1
        if {[winfo exists .gxViewerDevelopment.debugbar]} {debugRender {state IDLE sequence 0 frames {} locals {}}}
    }
    set book .gxViewerDevelopment.body.center.sources
    projectNotesFocus 0
    set pages [$book tabs]
    # Forgotten Notes are still live owned widgets. Dispose them as well before
    # resetting the serial, otherwise a new project can collide with their names.
    foreach key {tabs notes} {
        if {[info exists s($key)]} {dict for {name record} $s($key) {lappend pages [dict get $record page]}}
    }
    foreach page [lsort -unique $pages] {if {$page in [$book tabs]} {$book forget $page};if {[winfo exists $page]} {destroy $page}}
    set s(tabs) {};set s(notes) {};set s(showNotes) 0;set s(editor) {};set s(tabSerial) 0;set s(dirty) 0
}
proc ::GX::ViewerDevelopmentWorkspace::projectTabCreate {name source editable language checksum} {
    variable s
    set page .gxViewerDevelopment.body.center.sources.file[incr s(tabSerial)]
    set widget [::GX::sourceSurfaceCreate $page [dict create mode [expr {$editable?{editable}:{read_only}}] language $language]]
    dict set s(tabs) $name [dict create page $page text $widget baseline $source sha256 $checksum editable $editable dirty 0]
    ::GX::sourceSurfaceSet $widget $source
    .gxViewerDevelopment.body.center.sources add $page -text $name
    bind $widget <<Modified>> +[list ::GX::ViewerDevelopmentWorkspace::modified $widget]
    ::GX::uiTextEditingAttach .gxViewerDevelopment [list $widget]
    bind $widget <Control-w> {::GX::ViewerDevelopmentWorkspace::safe projectTabClose;break}
    bind $widget <Control-f> {::GX::ViewerDevelopmentWorkspace::safe projectNotesSearch find;break}
    return $widget
}
proc ::GX::ViewerDevelopmentWorkspace::projectTabSelected {} {
    variable s
    if {$s(mode) eq {maintenance}} return
    set page [.gxViewerDevelopment.body.center.sources select]
    set note [projectNotesActive]
    if {$note ne {}} {set page [dict get $s(tabs) $note page]}
    if {![info exists s(tabs)]} return
    dict for {name tab} $s(tabs) {
        if {[dict get $tab page] ne $page} continue
        set s(showNotes) [expr {[dict exists $s(notes) $name] && [dict get $s(notes) $name page] in [.gxViewerDevelopment.body.center.sources tabs]}]
        set s(editor) [dict get $tab text];set s(file) $name;set s(baseline) [dict get $tab baseline]
        projectNotesFocus [expr {$note ne {}}]
        .gxViewerDevelopment.menus.edit entryconfigure {Replace in Note…} -state [expr {$s(busy) eq {} && $note ne {}?{normal}:{disabled}}]
        set tree .gxViewerDevelopment.body.left.files.tree
        if {[$tree exists $name] && [$tree selection] ne [list $name]} {$tree selection set $name;$tree see $name}
        set s(status) "$name · [expr {[dict get $tab dirty]?{unsaved}:([dict get $tab editable]?{saved}:{read-only})}]"
        if {$s(mode) eq {acquisition}} {controls}
        return
    }
}
proc ::GX::ViewerDevelopmentWorkspace::projectDirty {} {
    variable s;set dirty 0
    dict for {name tab} $s(tabs) {
        if {![winfo exists [dict get $tab text]]} continue
        set changed [expr {[dict get $tab editable] && [::GX::sourceSurfaceGet [dict get $tab text]] ne [dict get $tab baseline]}]
        dict set s(tabs) $name dirty $changed
        .gxViewerDevelopment.body.center.sources tab [dict get $tab page] -text "$name[expr {$changed?{ *}:{}}]"
        if {$changed} {set dirty 1}
    }
    set s(dirty) $dirty
    return $dirty
}
proc ::GX::ViewerDevelopmentWorkspace::projectRead {name} {
    variable s
    if {$s(mode) eq {acquisition}} {return [acqRead $name]}
    set names [::GX::viewerDevelopmentSourceFiles $s(project)]
    set roots [dict create project.json [file join $s(project) project.json] MANUAL.md [file join $s(project) MANUAL.md] design.gxtxt-viewer [file join $s(project) design.gxtxt-viewer] validation.json [file join $s(project) derived validation.json] build.json [file join $s(project) derived build.json] adapter.cpp [file join $::GX::scriptDir core development sdk trusted_adapter_v1.cpp]]
    foreach source $names {dict set roots $source [file join $s(project) $source]}
    if {![dict exists $roots $name]} {error {Choose a declared source, manual or generated report}}
    if {[dict exists $s(tabs) $name]} {
        .gxViewerDevelopment.body.center.sources select [dict get $s(tabs) $name page]
        projectTabSelected
        return [text]
    }
    set path [dict get $roots $name];set source {};set checksum {}
    if {[file exists $path]} {
        if {![file isfile $path] || [file type $path] eq {link} || [file size $path]>4194304} {error {Source is not an ordinary bounded file}}
        set stream [::open $path rb];try {set source [encoding convertfrom utf-8 [::read $stream 4194305]]} finally {::close $stream}
        set checksum [::GX::sha256File $path]
    } elseif {$name ne {MANUAL.md}} {error {Selected source/report is unavailable}}
    set editable [expr {$name in $names || $name in {project.json MANUAL.md}}]
    set language [expr {[file extension $name] in {.cpp .hpp}?{cpp}:($name eq {MANUAL.md}?{markdown}:([file extension $name] eq {.json}?{javascript}:{tcl}))}]
    set widget [projectTabCreate $name $source $editable $language $checksum]
    if {$name in $names} {
        ::GX::sourceSurfaceDocumentIdentity $widget [list viewer-cpp:$s(project)/$name [::GX::_viewerDevelopmentSnapshot $s(project)] $checksum]
        if {[info exists ::GX::ViewerDevelopmentWorkspace::debug(request)] && $::GX::ViewerDevelopmentWorkspace::debug(request) ne {}} {::GX::sourceSurfaceBreakpoints $widget lock}
    }
    .gxViewerDevelopment.body.center.sources select [dict get $s(tabs) $name page];projectTabSelected
    return $widget
}
proc ::GX::ViewerDevelopmentWorkspace::projectTreeRefresh {} {
    variable s
    if {$s(mode) eq {acquisition}} {return [acqTreeRefresh]}
    set tree .gxViewerDevelopment.body.left.files.tree;$tree delete [$tree children {}]
    foreach name [::GX::viewerDevelopmentSourceFiles $s(project)] {
        set parent {};set prefix {}
        foreach part [lrange [split $name /] 0 end-1] {
            set prefix [expr {$prefix eq {}?$part:"$prefix/$part"}]
            set id folder:$prefix
            if {![$tree exists $id]} {$tree insert $parent end -id $id -text $part -open 1}
            set parent $id
        }
        $tree insert $parent end -id $name -text "[file tail $name][expr {$name eq {handlers.cpp}?{ · entrypoint}:{}}]"
    }
    foreach {name label} {project.json {Project / facilities / tests} MANUAL.md {Manual (Markdown)} design.gxtxt-viewer {Builder design (read-only)} validation.json {Validation report} build.json {Build manifest} adapter.cpp {Trusted C++ adapter}} {$tree insert {} end -id $name -text $label}
    ::GX::uiFieldInspectionColumnsSchedule $tree {recursive 1}
}
proc ::GX::ViewerDevelopmentWorkspace::projectSave {{all 0}} {
    variable s
    if {$s(mode) eq {acquisition}} {return [acqSave $all]}
    if {$s(mode) eq {maintenance}} {return [maintenanceSave]}
    projectDirty
    set updates {};set submitted {}
    dict for {name tab} $s(tabs) {
        if {![dict get $tab dirty] || (!$all && $name ne $s(file))} continue
        set source [::GX::sourceSurfaceGet [dict get $tab text]]
        set checksum [dict get $tab sha256]
        set expected [expr {$checksum eq {}?{null}:[::GX::viewerDevelopmentJsonString $checksum]}]
        lappend updates "[::GX::viewerDevelopmentJsonString $name]:\{\"source\":[::GX::viewerDevelopmentJsonString $source],\"expected_sha256\":$expected\}"
        dict set submitted $name $source
    }
    if {![llength $updates]} {set s(status) {No unsaved source changes.};return}
    set request [format {{"operation":"save_all","expected_project_sha256":"%s","files":{%s}}} $s(projectHash) [join $updates ,]]
    set result [maintenanceWait project_files $request]
    if {[dict get $result status] ne {SAVED}} {error {Save did not complete; source buffers retained}}
    # Only the exact submitted bytes become a baseline. Input may have continued
    # while the managed request yielded; newer keystrokes remain dirty.
    dict for {name source} $submitted {
        set path [file join $s(project) $name]
        set stream [::open $path rb];try {set actual [encoding convertfrom utf-8 [::read $stream]]} finally {::close $stream}
        if {$actual ne $source} {error "Save readback differs for $name; buffers retained, inspect before retry"}
    }
    dict for {name source} $submitted {dict set s(tabs) $name baseline $source;dict set s(tabs) $name sha256 [::GX::sha256File [file join $s(project) $name]]}
    set s(projectHash) [dict get $result project_sha256]
    projectSourceIdentities
    projectDirty;projectTabSelected
    set s(status) "[expr {$all?{Saved all changed files}:{Saved source}}] · [dict size $submitted] file(s) · source revision checked"
    if {[dict exists $submitted project.json]} {apiRefresh}
    return $result
}
proc ::GX::ViewerDevelopmentWorkspace::saveAll {} {set result [projectSave 1];if {![projectNotesSaveAll]} {error {Unsaved note retained}};return $result}
proc ::GX::ViewerDevelopmentWorkspace::projectTabClose {} {
    variable s
    if {$s(busy) ne {}} {error {Wait or cancel the active request before closing source tabs}}
    if {![dict exists $s(tabs) $s(file)]} return
    set name [projectNotesActive];if {$name eq {}} {set name $s(file)}
    set tab [dict get $s(tabs) $name]
    if {![projectNotesReview $name]} return
    if {[projectNotesActive] ne {}} {projectNotesDispose $name;.gxViewerDevelopment.body.center.sources select [dict get $tab page];return}
    projectDirty
    if {[dict get $s(tabs) $name dirty]} {
        set answer [tk_messageBox -parent .gxViewerDevelopment -type yesnocancel -icon question -title {Close source tab} -message "Save $name before closing this tab?"]
        if {$answer eq {cancel}} return
        if {$answer eq {yes}} {projectSave}
        if {$answer eq {yes} && [dict get $s(tabs) $name dirty]} {error {New edits arrived during Save; source tab retained}}
    }
    projectNotesDispose $name
    .gxViewerDevelopment.body.center.sources forget [dict get $tab page];destroy [dict get $tab page];dict unset s(tabs) $name
    projectDirty;projectTabSelected
    if {![dict size $s(tabs)]} {set s(editor) {};set s(file) {};set s(status) {Choose a project file to open a source tab.}}
}
proc ::GX::ViewerDevelopmentWorkspace::projectSourceIdentities {} {
    variable s
    if {$s(mode) eq {acquisition}} {return [acqSourceIdentities]}
    projectNotesSourceUpdated
    set snapshot [::GX::_viewerDevelopmentSnapshot $s(project)]
    set sources [::GX::viewerDevelopmentSourceFiles $s(project)]
    dict for {name tab} $s(tabs) {
        if {$name in $sources} {::GX::sourceSurfaceDocumentIdentity [dict get $tab text] [list viewer-cpp:$s(project)/$name $snapshot [dict get $tab sha256]]}
    }
}

# Fixed adapter for SOURCE_NOTE_API_v1. The existing owned C++ project remains
# the only root; public note references never choose a filesystem pathname.
proc ::GX::ViewerDevelopmentWorkspace::sourceNoteOwner {operation reference {request {}}} {
    variable s
    if {![info exists s(mode)] || $s(mode) ni {cpp acquisition} || $s(project) eq {} || ![winfo exists .gxViewerDevelopment]} {error {Associated source project is not open in its Development Workspace}}
    if {$s(busy) ne {}} {error {C++ project is busy; retry its note when the request completes}}
    if {$operation ni {describe read_local write_local ensure_identity asset_read}} {error {Unsupported C++ source-note operation}}
    set relative [dict get $reference relative]
    if {[::GX::datasetPublicationV2DictDefault $reference file_key {}] eq {} && $relative ni [projectNoteSources]} {error {Associated source is undeclared or its Notes support is unavailable}}
    set expectedKey [::GX::datasetPublicationV2DictDefault $reference owner_key [::GX::datasetPublicationV2DictDefault $reference project_key {}]]
    set fileKey [::GX::datasetPublicationV2DictDefault $reference file_key {}]
    set readRequest [projectNoteRequestJson [list {"operation":"note_read"} "\"relative\":[::GX::viewerDevelopmentJsonString $relative]" "\"owner_key\":[::GX::viewerDevelopmentJsonString $expectedKey]" "\"file_key\":[::GX::viewerDevelopmentJsonString $fileKey]" "\"expected_project_sha256\":[::GX::viewerDevelopmentJsonString $s(projectHash)]"]]
    set current [maintenanceWait project_files $readRequest]
    if {$expectedKey ne {} && $expectedKey ne [dict get $current owner_key]} {error {Associated C++ project identity changed; the note was not retargeted}}
    set relative [dict get $current relative]
    if {$s(mode) eq {acquisition} && ($relative ni [projectNoteSources] || [dict get $current language] ne [dict get $s(acqFiles) $relative source_notes_language])} {error {Associated source Notes capability or actual language changed}}
    if {$operation eq {asset_read}} {
        foreach key {name start count expected_authoring_revision expected_owner_revision expected_asset_sha256} {if {![dict exists $request $key]} {error {Pinned source asset read required}}}
        if {[dict get $request expected_owner_revision] ne [dict get $current project_sha256]} {error {C++ owner changed before reading its image}}
        if {![string is entier -strict [dict get $request start]] || [dict get $request start]<0 || ![string is entier -strict [dict get $request count]] || [dict get $request count]<1 || [dict get $request count]>1048576} {error {Source asset reads are bounded to1MiB}}
        set fields [list {"operation":"note_asset_read"} "\"relative\":[::GX::viewerDevelopmentJsonString $relative]" "\"owner_key\":[::GX::viewerDevelopmentJsonString $expectedKey]" "\"file_key\":[::GX::viewerDevelopmentJsonString $fileKey]" "\"expected_project_sha256\":[::GX::viewerDevelopmentJsonString $s(projectHash)]"]
        foreach key {name expected_authoring_revision expected_asset_sha256} {lappend fields "\"$key\":[::GX::viewerDevelopmentJsonString [dict get $request $key]]"}
        foreach key {start count} {lappend fields "\"$key\":[dict get $request $key]"}
        set chunk [maintenanceWait project_files [projectNoteRequestJson $fields]]
        if {![dict exists $chunk status] || [dict get $chunk status] ne {SAVED}} {error {Source asset read did not return its exact saved receipt}}
        # ProjectFiles has a CLI/Job status envelope; SOURCE_NOTE owns the exact
        # six-field chunk contract. Strip only that validated transport field.
        return [dict remove $chunk status]
    }
    if {$operation in {write_local ensure_identity}} {
        if {![dict exists $request expected_authoring_revision]} {error {Source note save requires its explicit authoring revision}}
        if {[dict exists $request expected_owner_revision] && [dict get $request expected_owner_revision] ne [dict get $current project_sha256]} {error {C++ project revision changed before saving its note}}
        set expectedSource [::GX::datasetPublicationV2DictDefault $reference expected_source_sha256 [dict get $current source_sha256]]
        set expectedRevision [::GX::datasetPublicationV2DictDefault $request expected_authoring_revision [dict get $current authoring_revision]]
        set op [expr {$operation eq {write_local}?{note_write}:{note_identity}}]
        set fields [list "\"operation\":[::GX::viewerDevelopmentJsonString $op]" \
            "\"relative\":[::GX::viewerDevelopmentJsonString $relative]" \
            "\"owner_key\":[::GX::viewerDevelopmentJsonString $expectedKey]" \
            "\"file_key\":[::GX::viewerDevelopmentJsonString $fileKey]" \
            "\"expected_project_sha256\":[::GX::viewerDevelopmentJsonString $s(projectHash)]" \
            "\"expected_source_sha256\":[::GX::viewerDevelopmentJsonString $expectedSource]" \
            "\"expected_authoring_revision\":[::GX::viewerDevelopmentJsonString $expectedRevision]"]
        if {$operation eq {write_local} && [dict exists $request asset_plan]} {
            if {![llength [info commands ::GX::sourceNoteAssetPlanConsume]]} {error {CORE source asset plan admission is unavailable}}
            set sourceReceipt [dict merge $current [dict create owner cpp_viewer_project owner_revision [dict get $current project_sha256]]]
            set topRef [dict create owner cpp_viewer_project reference $reference]
            set plan [::GX::sourceNoteAssetPlanConsume [dict get $request asset_plan] $sourceReceipt $topRef]
            set encoded [format {{"directory":%s,"index_sha256":%s,"index_size":%d}} [::GX::viewerDevelopmentJsonString [dict get $plan directory]] [::GX::viewerDevelopmentJsonString [dict get $plan index_sha256]] [dict get $plan index_size]]
            lappend fields "\"asset_plan\":$encoded"
        }
        if {$operation eq {write_local}} {
            set bytes [encoding convertto utf-8 [dict get $request text]]
            if {[string length $bytes]>4194304 || [string first \x00 $bytes]>=0} {error {C++ source notes require UTF-8 text up to4MiB without NUL}}
            ::GX::documentUtf8Prefix $bytes [string length $bytes]
            lappend fields "\"note_base64\":[::GX::viewerDevelopmentJsonString [binary encode base64 -maxlen 0 $bytes]]"
        }
        set current [maintenanceWait project_files [projectNoteRequestJson $fields]]
        set s(projectHash) [dict get $current project_sha256]
        if {$s(mode) eq {acquisition}} {acqNoteRevisionAccept $current}
    }
    if {[dict exists $current note_base64]} {
        set bytes [binary decode base64 [dict get $current note_base64]]
        ::GX::documentUtf8Prefix $bytes [string length $bytes]
        dict set current text [encoding convertfrom utf-8 $bytes]
        dict unset current note_base64
    }
    dict set current owner cpp_viewer_project
    dict set current owner_revision [dict get $current project_sha256]
    dict set current reference "project:[dict get $current owner_key]"
    return $current
}
proc ::GX::ViewerDevelopmentWorkspace::projectFileDialog {operation} {
    variable s
    if {$s(mode) eq {acquisition}} {return [acqFileDialog $operation]}
    if {$s(mode) ne {cpp} || $s(project) eq {} || $s(busy) ne {}} {error {Open an idle C++ project first}}
    set s(fileOperation) $operation;set s(newFileSource) {};set s(newFileName) src/helper.cpp
    if {$operation eq {import}} {
        set path [tk_getOpenFile -parent .gxViewerDevelopment -title {Add existing source/header} -filetypes {{{C++ project sources} {.cpp .hpp}}}]
        if {$path eq {}} return
        if {![file isfile $path] || [file type $path] eq {link} || [file size $path]>65536} {error {Choose an ordinary UTF-8 source/header within64KiB}}
        set stream [::open $path rb];try {set s(newFileSource) [encoding convertfrom utf-8 [::read $stream 65537]]} finally {::close $stream}
        set s(newFileName) [file join [expr {[file extension $path] eq {.hpp}?{include}:{src}}] [file tail $path]]
    } elseif {$operation eq {rename}} {
        if {$s(file) ni [::GX::viewerDevelopmentSourceFiles $s(project)] || $s(file) eq {handlers.cpp}} {error {Open an auxiliary source/header to rename or move}}
        set s(fileOriginal) $s(file);set s(newFileName) $s(file)
    }
    set w .gxViewerDevelopment.projectFile;catch {destroy $w}
    ::GX::uiFieldDialogCreate $w .gxViewerDevelopment [expr {$operation eq {rename}?{Rename or move project file}:{Add project file}}]
    ttk::label $w.help -text {Use src/path.cpp for a translation unit or include/path.hpp for a local header. Names are project-relative. Rename/move preserves source bytes and does not rewrite C++ include statements.} -wraplength 570 -justify left
    ttk::label $w.label -text {Project-relative file name}
    ttk::entry $w.name -textvariable ::GX::ViewerDevelopmentWorkspace::s(newFileName) -width 55
    ::GX::uiTextEditingAttach $w [list $w.name]
    ttk::frame $w.buttons
    ttk::button $w.buttons.apply -text [expr {$operation eq {rename}?{Rename / move}:{Add file}}] -command {::GX::ViewerDevelopmentWorkspace::safe projectFileCommit}
    ttk::button $w.buttons.cancel -text Cancel -command [list ::GX::uiFieldDialogClose $w]
    pack $w.buttons.apply $w.buttons.cancel -side left -padx 4
    # Settle the nested row request before the dialog's first size negotiation.
    pack $w.help $w.label $w.name -fill x -padx 12 -pady 6;pack $w.buttons -fill x -padx 8 -pady 8
    bind $w.name <Return> {::GX::ViewerDevelopmentWorkspace::safe projectFileCommit;break}
    bind $w <Escape> [list ::GX::uiFieldDialogClose $w]
    ::GX::uiFieldDialogPresent $w $w.name 0
}
proc ::GX::ViewerDevelopmentWorkspace::projectFileCommit {} {
    variable s
    if {$s(dirty)} {saveAll}
    if {$s(dirty)} {error {New edits arrived during Save All; project files are preserved}}
    set name $s(newFileName);set fields [format {"expected_project_sha256":"%s"} $s(projectHash)]
    if {$s(fileOperation) eq {rename}} {
        set original $s(fileOriginal)
        set request [format {{"operation":"rename",%s,"name":%s,"target":%s}} $fields [::GX::viewerDevelopmentJsonString $original] [::GX::viewerDevelopmentJsonString $name]]
    } else {
        set source $s(newFileSource)
        if {$source eq {} && [file extension $name] eq {.hpp}} {set source "#pragma once\n"}
        set request [format {{"operation":"add",%s,"name":%s,"source":%s}} $fields [::GX::viewerDevelopmentJsonString $name] [::GX::viewerDevelopmentJsonString $source]]
    }
    set result [maintenanceWait project_files $request]
    if {$s(fileOperation) eq {rename} && [dict exists $s(tabs) $original]} {
        set page [dict get $s(tabs) $original page];.gxViewerDevelopment.body.center.sources forget $page;destroy $page;dict unset s(tabs) $original
    }
    set s(projectHash) [dict get $result project_sha256]
    if {$s(fileOperation) eq {rename} && [dict exists $s(notes) $original]} {
        dict set s(notes) $name [dict get $s(notes) $original];dict unset s(notes) $original
        set handle [dict get $s(notes) $name editor]
        dict set ::GX::SourceNoteEditor::bindings $handle options on_change [list ::GX::ViewerDevelopmentWorkspace::projectNotesChanged $name]
    }
    projectTreeRefresh;read $name;projectSourceIdentities
    if {[dict exists $s(notes) $name]} {
        set page [dict get $s(notes) $name page];set book .gxViewerDevelopment.body.center.sources
        if {$page in [$book tabs]} {set at [expr {[$book index [dict get $s(tabs) $name page]]+1}];if {$at>=[llength [$book tabs]]} {set at end};$book insert $at $page}
    }
    ::GX::uiFieldDialogClose .gxViewerDevelopment.projectFile
    set s(status) "Project file [expr {$s(fileOperation) eq {rename}?{renamed/moved}:{added}}]: $name · Build explicitly for this revision"
}
proc ::GX::ViewerDevelopmentWorkspace::projectFileRemove {} {
    variable s
    if {$s(mode) eq {acquisition}} {return [acqRemove]}
    set name $s(file)
    if {$name eq {handlers.cpp} || $name ni [::GX::viewerDevelopmentSourceFiles $s(project)]} {error {Open an auxiliary source/header to remove}}
    if {![prepare]} return
    if {[tk_messageBox -parent .gxViewerDevelopment -type yesno -default no -icon warning -title {Remove project file} -message "Remove $name from this project and its source folder? Other source text and includes are preserved."] ne {yes}} return
    set request [format {{"operation":"remove","expected_project_sha256":"%s","name":%s}} $s(projectHash) [::GX::viewerDevelopmentJsonString $name]]
    set result [maintenanceWait project_files $request]
    projectNotesDispose $name
    if {[dict exists $s(tabs) $name]} {set page [dict get $s(tabs) $name page];.gxViewerDevelopment.body.center.sources forget $page;destroy $page;dict unset s(tabs) $name}
    set s(projectHash) [dict get $result project_sha256];projectTreeRefresh;projectSourceIdentities;read handlers.cpp
    set s(status) "Removed $name · remaining includes may need editing before Build"
}
proc ::GX::ViewerDevelopmentWorkspace::importProject {} {
    variable s
    if {![prepare]} return
    set package [tk_getOpenFile -parent .gxViewerDevelopment -title {Import exported C++ Viewer project} -filetypes {{{Viewer package} {.zip}}}]
    if {$package eq {}} return
    set parent [tk_chooseDirectory -parent .gxViewerDevelopment -title {Parent folder for the imported editable project}]
    if {$parent eq {}} return
    set s(newProject) [file join $parent viewer_import_[clock microseconds]]
    incr s(generation)
    set s(busy) [::GX::viewerDevelopmentRequest import_project $s(newProject) [list ::GX::ViewerDevelopmentWorkspace::created $s(generation)] [dict create source_package $package]]
    set s(status) {Checking package/source closure and importing a new editable project…};controls
}

proc ::GX::ViewerDevelopmentWorkspace::apiPanelToggle {} {
    variable s
    set book .gxViewerDevelopment.body.right
    if {$s(apiVisible)} {$book add $book.api -text {API Browser};$book select $book.api} else {$book hide $book.api}
    responsiveBody .gxViewerDevelopment
}

source [file join [file dirname [info script]] source_notes.tcl]

source [file join [file dirname [info script]] acquisition_project.tcl]
