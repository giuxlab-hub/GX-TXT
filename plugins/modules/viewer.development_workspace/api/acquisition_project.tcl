# SPDX-License-Identifier: GPL-3.0-or-later
# Target-aware presentation adapter only. Existing ProjectFiles owns every byte,
# lock, revision, compiler decision, export and recovery. SourceSurface owns edits.
proc ::GX::ViewerDevelopmentWorkspace::acqEnsure {} {
    if {![llength [info commands ::GX::AcquisitionPluginBuilder::json]]} {source [file join $::GX::scriptDir app gui acquisition_plugin_builder_dialog.tcl]}
}
proc ::GX::ViewerDevelopmentWorkspace::acqTarget {path} {
    set file [file join $path project.json]
    if {![file isfile $file] || [file type $file] eq {link} || [file size $file]>65536} {return 0}
    set f [::open $file rb];try {set raw [::read $f 65537]} finally {::close $f}
    # Only a routing hint; the actual target owner validates Describe/read again.
    set meta [::GX::nativeWorkspaceDecode [::GX::nativeWorkspaceJsonDecode [encoding convertfrom utf-8 [::GX::documentUtf8Prefix $raw [string length $raw]]]]]
    return [expr {[::GX::datasetPublicationV2DictDefault $meta schema {}] eq {gxtxt.acquisition_development_project.v1}}]
}
proc ::GX::ViewerDevelopmentWorkspace::acqPayload {operation {fields {}}} {
    variable s;acqEnsure
    set base [dict create schema [list text gxtxt.development_project_edit.v1] operation [list text $operation]]
    if {$operation ne {describe}} {dict set base expected_revision [list text [dict get $s(acqDescription) revision]]}
    return [::GX::AcquisitionPluginBuilder::json [list object [dict merge $base $fields]]]
}
proc ::GX::ViewerDevelopmentWorkspace::acqWait {operation {fields {}}} {return [maintenanceWait project_files [acqPayload $operation $fields]]}
proc ::GX::ViewerDevelopmentWorkspace::acqDescriptionAccept {description} {
    variable s
    if {[dict get $description target] ne {acquisition}} {error {Expected the genuine Acquisition project target}}
    set s(acqDescription) $description;set s(projectHash) [dict get $description project_sha256]
    set s(acqFiles) {};foreach row [dict get $description files] {dict set s(acqFiles) [dict get $row relative] $row}
}
proc ::GX::ViewerDevelopmentWorkspace::acqProject {path} {
    variable s
    if {$s(busy) ne {}} {error {Wait or cancel the current request before changing project}}
    if {![prepare]} return
    set old [array get s];set lifetime $s(windowGeneration)
    set s(project) [file normalize $path];set s(mode) acquisition;incr s(generation)
    try {
        set desc [acqWait describe]
        acqDescriptionAccept $desc
        set first [acqWait read [dict create relative [list text handlers.cpp]]]
    } on error {message options} {
        if {[winfo exists .gxViewerDevelopment] && $s(windowGeneration)==$lifetime} {array set s $old;controls}
        return -options $options $message
    }
    projectTabsReset
    set s(dirty) 0
    acqTreeRefresh
    acqReadAccept handlers.cpp $first
    wm title .gxViewerDevelopment "Acquisition Development Workspace · [dict get $desc module_id]"
    set s(status) "Registered sources only · [dict get $desc availability_reason]"
    acqReferenceNotice
    apiRefresh;controls
    return $desc
}
proc ::GX::ViewerDevelopmentWorkspace::acqPrepare {} {
    variable s
    if {$s(busy) ne {}} {error {Wait for the request or cancel it before changing the project context}}
    if {![projectNotesReview]} {return 0}
    projectDirty
    if {!$s(dirty)} {return 1}
    set answer [tk_messageBox -parent .gxViewerDevelopment -type yesnocancel -default cancel -icon question -title {Unsaved Acquisition source} -message {Save all changed registered sources before continuing? Yes saves with the full project revision; No discards only these local buffers on the requested transition; Cancel keeps editing.}]
    if {$answer eq {cancel}} {return 0}
    if {$answer eq {yes}} {acqSave 1;if {[projectDirty]} {error {New edits arrived during Save; buffers retained}}}
    return 1
}
proc ::GX::ViewerDevelopmentWorkspace::acqRead {name} {
    variable s
    if {[dict exists $s(tabs) $name]} {.gxViewerDevelopment.body.center.sources select [dict get $s(tabs) $name page];projectTabSelected;return [text]}
    if {$name ne {project.json} && ![dict exists $s(acqFiles) $name]} {error {Choose a registered source/helper or project.json}}
    return [acqReadAccept $name [acqWait read [dict create relative [list text $name]]]]
}
proc ::GX::ViewerDevelopmentWorkspace::acqReadAccept {name receipt} {
    variable s
    if {[dict get $receipt revision] ne [dict get $s(acqDescription) revision]} {error {Source response belongs to an earlier project revision; buffer retained}}
    set language javascript
    if {$name ne {project.json}} {set language [dict get $s(acqFiles) $name language];set language [dict get {cpp cpp Tcl tcl Python python} $language]}
    set widget [projectTabCreate $name [dict get $receipt source] [acqWritable] $language [dict get $receipt sha256]]
    ::GX::sourceSurfaceDocumentIdentity $widget [list acquisition-source:$s(project)/$name [dict get $s(acqDescription) revision] [dict get $receipt sha256]]
    .gxViewerDevelopment.body.center.sources select [dict get $s(tabs) $name page]
    projectTabSelected;return $widget
}
proc ::GX::ViewerDevelopmentWorkspace::acqTreeRefresh {} {
    variable s
    set tree .gxViewerDevelopment.body.left.files.tree;$tree delete [$tree children {}]
    dict for {name row} $s(acqFiles) {
        set parent {};set prefix {}
        foreach part [lrange [split $name /] 0 end-1] {set prefix [expr {$prefix eq {}?$part:"$prefix/$part"}];set id folder:$prefix;if {![$tree exists $id]} {$tree insert $parent end -id $id -text $part -open 1};set parent $id}
        $tree insert $parent end -id $name -text "[file tail $name] · [dict get $row language] / [dict get $row role]"
    }
    $tree insert {} end -id project.json -text {Project metadata (typed JSON)}
    ::GX::uiFieldInspectionColumnsSchedule $tree {recursive 1}
}
proc ::GX::ViewerDevelopmentWorkspace::acqSave {{all 0}} {
    variable s;projectDirty
    set changes {};set submitted {}
    dict for {name tab} $s(tabs) {
        if {![dict get $tab dirty] || (!$all && $name ne $s(file))} continue
        set source [::GX::sourceSurfaceGet [dict get $tab text]]
        dict set changes $name [list object [dict create source [list text $source] expected_sha256 [list text [dict get $tab sha256]]]]
        dict set submitted $name $source
    }
    if {![dict size $changes]} {set s(status) {No unsaved registered source changes.};return}
    set result [acqWait save_all [dict create files [list object $changes]]]
    acqDescriptionAccept [dict get $result description]
    dict for {name source} $submitted {
        set sha [expr {$name eq {project.json}?[dict get $s(acqDescription) project_sha256]:[dict get $s(acqFiles) $name sha256]}]
        dict set s(tabs) $name baseline $source;dict set s(tabs) $name sha256 $sha
    }
    acqSourceIdentities;projectDirty;projectTabSelected
    set s(status) "Saved [dict size $submitted] source(s) through full-revision ProjectFiles CAS; newer edits remain dirty."
    controls;return $result
}
proc ::GX::ViewerDevelopmentWorkspace::acqSourceIdentities {} {
    variable s
    dict for {name tab} $s(tabs) {::GX::sourceSurfaceDocumentIdentity [dict get $tab text] [list acquisition-source:$s(project)/$name [dict get $s(acqDescription) revision] [dict get $tab sha256]]}
    projectNotesSourceUpdated
}
proc ::GX::ViewerDevelopmentWorkspace::acqNoteRevisionAccept {receipt} {
    variable s
    # A note transaction changes project.json. Adopt only that exact receipt's
    # full revision, never a later outside edit; all local source buffers stay.
    set desc [acqWait describe]
    if {[dict get $desc revision] ne [dict get $receipt revision] || [dict get $desc project_sha256] ne [dict get $receipt project_sha256]} {error {Project changed after the note transaction; source buffers retained, reopen before further edits}}
    acqDescriptionAccept $desc
    dict for {name tab} $s(tabs) {::GX::sourceSurfaceDocumentIdentity [dict get $tab text] [list acquisition-source:$s(project)/$name [dict get $desc revision] [dict get $tab sha256]]}
    controls
}
proc ::GX::ViewerDevelopmentWorkspace::acqFileDialog {operation} {
    variable s
    if {$s(busy) ne {}} {error {Wait or cancel the current request}}
    set s(acqFileOperation) $operation;set s(acqFileSource) {};set s(acqFileName) src/helper.cpp;set s(acqFileLanguage) cpp;set s(acqHelperId) helper;set s(acqHelperEntry) process
    if {$operation eq {import}} {
        set path [tk_getOpenFile -parent .gxViewerDevelopment -title {Register existing source/helper as project data} -filetypes {{{Project sources} {.cpp .hpp .tcl .py}} {{All files} *}}]
        if {$path eq {}} return
        file lstat $path st
        if {$st(type) ne {file} || $st(nlink)!=1 || $st(size)>65536} {error {Choose an ordinary unlinked UTF-8 file within64KiB}}
        set f [::open $path rb];try {set bytes [::read $f 65537]} finally {::close $f}
        set s(acqFileSource) [encoding convertfrom utf-8 [::GX::documentUtf8Prefix $bytes [string length $bytes]]]
        set ext [file extension $path]
        set s(acqFileLanguage) [dict get {.cpp cpp .hpp cpp .tcl Tcl .py Python} $ext]
        set s(acqFileName) [file join [expr {$ext eq {.hpp}?{include}:($s(acqFileLanguage) eq {cpp}?{src}:{helpers})}] [file tail $path]]
    } elseif {$operation eq {rename}} {
        if {$s(file) eq {handlers.cpp} || ![dict exists $s(acqFiles) $s(file)]} {error {Choose a registered auxiliary source/helper}}
        set s(acqOriginal) $s(file);set s(acqFileName) $s(file);set s(acqFileLanguage) [dict get $s(acqFiles) $s(file) language]
    }
    set w .gxViewerDevelopment.projectFile;catch {destroy $w}
    ::GX::uiFieldDialogCreate $w .gxViewerDevelopment {Acquisition project file} 720x480
    ttk::frame $w.buttons;ttk::button $w.buttons.apply -text Apply -command {::GX::ViewerDevelopmentWorkspace::safe acqFileCommit};ttk::button $w.buttons.cancel -text Cancel -command [list ::GX::uiFieldDialogClose $w]
    pack $w.buttons.apply $w.buttons.cancel -side left -padx 5;pack $w.buttons -side bottom -fill x -padx 8 -pady 6
    set body [::GX::uiFieldScrollableCreate $w.form 650];pack $w.form -fill both -expand 1;grid columnconfigure $body 1 -weight 1
    set i 0
    foreach {key label} {acqFileName {Project-relative path} acqFileLanguage {Declared language} acqHelperId {Helper ID (scripts only)} acqHelperEntry {Helper entrypoint (scripts only)}} {
        ttk::label $body.l$key -text $label
        if {$key eq {acqFileLanguage}} {ttk::combobox $body.e$key -state readonly -values {cpp Tcl Python} -textvariable ::GX::ViewerDevelopmentWorkspace::s($key)} else {ttk::entry $body.e$key -textvariable ::GX::ViewerDevelopmentWorkspace::s($key)}
        grid $body.l$key -row $i -column 0 -sticky w -padx 8 -pady 5;grid $body.e$key -row $i -column 1 -sticky ew -padx 8 -pady 5;incr i
    }
    if {$operation eq {rename}} {$body.eacqFileLanguage state disabled}
    ttk::label $body.notice -text {Up to32 C++ files plus32 helpers,64KiB each and1MiB total. C++: src/*.cpp or include/*.hpp. Helpers: helpers/*.tcl or helpers/*.py with explicit helper ID/entrypoint. Registration does not execute a helper or admit native callbacks. Rename updates declared profile file bindings through the owner.} -wraplength 600
    grid $body.notice -row $i -column 0 -columnspan 2 -sticky ew -padx 8 -pady 8
    ::GX::uiFieldDialogPresent $w $body.eacqFileName 0
}
proc ::GX::ViewerDevelopmentWorkspace::acqFileCommit {} {
    variable s;projectDirty
    if {$s(dirty)} {acqSave 1;if {$s(dirty)} {error {New edits arrived during Save All; buffers retained}}}
    set name $s(acqFileName)
    if {$s(acqFileOperation) eq {rename}} {
        set original $s(acqOriginal)
        if {![projectNotesReview $original]} return
        set result [acqWait rename [dict create relative [list text $original] target [list text $name] expected_sha256 [list text [dict get $s(acqFiles) $original sha256]]]]
        projectNotesDispose $original
        if {[dict exists $s(tabs) $original]} {set page [dict get $s(tabs) $original page];.gxViewerDevelopment.body.center.sources forget $page;destroy $page;dict unset s(tabs) $original}
    } else {
        set descriptor [dict create relative [list text $name] language [list text $s(acqFileLanguage)]]
        if {$s(acqFileLanguage) eq {cpp}} {dict set descriptor role [list text [expr {[file extension $name] eq {.hpp}?{header}:{translation_unit}}]]
        } else {dict set descriptor role [list text runtime_helper];dict set descriptor helper_id [list text $s(acqHelperId)];dict set descriptor entrypoint [list text $s(acqHelperEntry)]}
        set result [acqWait add [dict create file [list object $descriptor] source [list text $s(acqFileSource)]]]
    }
    acqDescriptionAccept [dict get $result description];acqTreeRefresh;acqRead $name;acqSourceIdentities
    ::GX::uiFieldDialogClose .gxViewerDevelopment.projectFile
    set s(status) "Registered source $name · [dict get $s(acqFiles) $name binding_status] · no execution granted"
    controls
}
proc ::GX::ViewerDevelopmentWorkspace::acqRemove {} {
    variable s
    set name $s(file)
    if {$name eq {handlers.cpp} || ![dict exists $s(acqFiles) $name]} {error {Choose a registered auxiliary source/helper}}
    if {![acqPrepare]} return
    if {[tk_messageBox -parent .gxViewerDevelopment -type yesno -default no -icon question -title {Remove registered file} -message "Remove $name from this project? Source files still referenced by a profile are refused by the owner."] ne {yes}} return
    set result [acqWait remove [dict create relative [list text $name] expected_sha256 [list text [dict get $s(acqFiles) $name sha256]]]]
    projectNotesDispose $name
    if {[dict exists $s(tabs) $name]} {set page [dict get $s(tabs) $name page];.gxViewerDevelopment.body.center.sources forget $page;destroy $page;dict unset s(tabs) $name}
    acqDescriptionAccept [dict get $result description];acqTreeRefresh;acqRead handlers.cpp;controls
}
proc ::GX::ViewerDevelopmentWorkspace::acqBuilder {{new 0}} {
    variable s;acqEnsure
    if {$new} {return [::GX::AcquisitionPluginBuilder::open new]}
    if {$s(mode) eq {acquisition}} {return [::GX::AcquisitionPluginBuilder::open open $s(project)]}
    return [::GX::AcquisitionPluginBuilder::open open]
}
proc ::GX::ViewerDevelopmentWorkspace::acqRun {operation} {
    variable s
    set desc $s(acqDescription)
    set flag [expr {$operation in {validate build export}?{build_available}:($operation eq {test}?{project_test_available}:{runtime_available})}]
    if {![dict get $desc $flag]} {error [dict get $desc availability_reason]}
    if {$operation eq {test}} {
        # Another project window may save profiles/configuration without changing
        # registered source bytes. Refresh only those saved declarations; never
        # re-read/reset an editor or silently adopt an outside source change.
        set previous $s(acqDescription)
        set current [acqWait describe]
        if {[dict get $current module_id] ne [dict get $previous module_id] || [dict get $current source_tree_sha256] ne [dict get $previous source_tree_sha256]} {
            error {Saved project identity or registered sources changed outside this Workspace. Source and Notes buffers are retained; review the changes and explicitly reopen the project before Test.}
        }
        acqDescriptionAccept $current
    }
    projectDirty
    if {$s(dirty)} {acqSave 1;if {$s(dirty)} {error {New edits arrived during Save All; source buffers retained}}}
    if {$operation eq {export}} {if {![projectNotesReview]} return;projectNotesSnapshotExport}
    if {$operation eq {test}} {
        set context [list $s(project) [dict get $s(acqDescription) revision] $s(generation)]
        return [::GX::viewerDevelopmentAcquisitionTestChoose .gxViewerDevelopment $s(acqDescription) {} [list [namespace current]::acqTestContextValid $context] [list [namespace current]::acqTestSubmit]]
    }
    incr s(generation)
    set s(busy) [::GX::viewerDevelopmentRequest $operation $s(project) [list ::GX::ViewerDevelopmentWorkspace::completed $operation $s(project) $s(generation)]]
    controls
}
proc ::GX::ViewerDevelopmentWorkspace::acqTestContextValid {context} {
    variable s
    if {![winfo exists .gxViewerDevelopment] || $s(mode) ne {acquisition} || $s(busy) ne {}} {return 0}
    projectDirty
    return [expr {!$s(dirty) && $context eq [list $s(project) [dict get $s(acqDescription) revision] $s(generation)]}]
}
proc ::GX::ViewerDevelopmentWorkspace::acqTestSubmit {profile request} {
    variable s
    incr s(generation)
    set s(busy) [::GX::viewerDevelopmentRequest test $s(project) [list [namespace current]::completed test $s(project) $s(generation)] [dict create request_json $request]]
    controls
}
proc ::GX::ViewerDevelopmentWorkspace::acqWritable {} {
    variable s
    return [expr {![dict exists $s(acqDescription) metadata provenance source_authoring_v1] || [::GX::datasetPublicationV2DictDefault $s(acqDescription) source_notes_available 0]}]
}
proc ::GX::ViewerDevelopmentWorkspace::acqControls {} {
    variable s
    set idle [expr {$s(busy) eq {}}]
    set writable [expr {![info exists s(acqDescription)] || [acqWritable]}]
    foreach id {new open save saveall} {.gxViewerDevelopment.toolbar.$id state [expr {$idle && ($id in {new open} || $writable)?{!disabled}:{disabled}}]}
    set desc [expr {[info exists s(acqDescription)]?$s(acqDescription):{}}]
    set build [expr {$idle && $desc ne {} && [dict get $desc build_available]}]
    set runtime [expr {$idle && $desc ne {} && [dict get $desc runtime_available]}]
    set test [expr {$idle && $desc ne {} && [::GX::datasetPublicationV2DictDefault $desc project_test_available 0]}]
    foreach {id enabled} [list validate $build build $build export $build demo $runtime test $test cancel [expr {!$idle}]] {.gxViewerDevelopment.toolbar.$id state [expr {$enabled?{!disabled}:{disabled}}]}
    .gxViewerDevelopment.menus.file entryconfigure {Export candidate} -state [expr {$build?{normal}:{disabled}}]
    .gxViewerDevelopment.menus.develop entryconfigure {Cancel request} -state [expr {$idle?{disabled}:{normal}}]
    foreach label {Validate Build} {.gxViewerDevelopment.menus.develop entryconfigure $label -state [expr {$build?{normal}:{disabled}}]}
    .gxViewerDevelopment.menus.develop entryconfigure {Demo / Preview} -state [expr {$runtime?{normal}:{disabled}}]
    .gxViewerDevelopment.menus.develop entryconfigure Test -state [expr {$test?{normal}:{disabled}}]
    foreach label {{Enable installed native GUI testing} {Review saved Workspace upgrade…}} {.gxViewerDevelopment.menus.develop entryconfigure $label -state disabled}
    foreach id {add import rename remove close} {.gxViewerDevelopment.toolbar.file_$id state [expr {$idle && ($id eq {close} || $writable)?{!disabled}:{disabled}}]}
    foreach label {{New project file…} {Add existing file…} {Rename / move file…} {Remove project file…} {Close source tab}} {.gxViewerDevelopment.menus.file entryconfigure $label -state [expr {$idle && ($label eq {Close source tab} || $writable)?{normal}:{disabled}}]}
    set notes [expr {$idle && $s(file) in [projectNoteSources]}]
    .gxViewerDevelopment.menus.edit entryconfigure {Edit Notes} -state [expr {$notes?{normal}:{disabled}}]
    .gxViewerDevelopment.menus.view entryconfigure {Show Notes} -state [expr {$notes?{normal}:{disabled}}]
    foreach widget [winfo children .gxViewerDevelopment.debugbar] {if {[winfo class $widget] eq {TButton}} {$widget state disabled}}
}
proc ::GX::ViewerDevelopmentWorkspace::acqReferenceNotice {} {
    variable s
    set w .gxViewerDevelopment
    set project $s(project);set generation $s(windowGeneration)
    if {![info exists s(viewerProfileText)]} {set s(viewerProfileText) [$w.body.right.profile.text get 1.0 end-1c]}
    set sdk $w.body.right.sdk.source.text
    if {![info exists s(viewerSdkText)]} {set s(viewerSdkText) [::GX::sourceSurfaceGet $sdk]}
    if {[catch {
        set receipt [maintenanceWait inspect sdk_v1]
        set bytes [encoding convertto utf-8 [dict get $receipt content]]
        if {[dict get $receipt status] ne {SAVED} || [dict get $receipt identity] ne {sdk_v1} || ![dict get $receipt read_only] || [string length $bytes]!=[dict get $receipt bytes] || [::GX::scriptRegistryHashBytes $bytes] ne [dict get $receipt sha256]} {error {Acquisition SDK reference receipt differs}}
        ::GX::sourceSurfaceSet $sdk [dict get $receipt content]
        set s(acqSdkReceipt) $receipt
        $w.body.right tab $w.body.right.sdk -text {Acquisition SDK v1}
    } reason]} {
        if {![winfo exists $w] || $s(project) ne $project || $s(windowGeneration)!=$generation} return
        unset -nocomplain s(acqSdkReceipt)
        ::GX::sourceSurfaceSet $sdk "Acquisition SDK reference unavailable.\n$reason"
        $w.body.right tab $w.body.right.sdk -text {Acquisition SDK unavailable}
    }
    $w.body.right.profile.text configure -state normal;$w.body.right.profile.text delete 1.0 end
    $w.body.right.profile.text insert end "Acquisition target\n\n[dict get $s(acqDescription) availability_reason]\n\n[dict get $s(acqDescription) source_notes_reason]\n\nThe API Browser shows this saved Acquisition project's declared capability requests and exact target SDK references. Reference admission does not validate source/AST or activate runtime grants. Metadata/profiles are authored through File → Acquisition project metadata/profiles; actual validation, execution and publication use their normal owning services."
    $w.body.right.profile.text configure -state disabled
}
proc ::GX::ViewerDevelopmentWorkspace::acqReferenceRestore {} {
    variable s
    if {![info exists s(viewerProfileText)]} return
    set w .gxViewerDevelopment
    $w.body.right tab $w.body.right.sdk -text SDK
    if {[info exists s(viewerSdkText)]} {::GX::sourceSurfaceSet $w.body.right.sdk.source.text $s(viewerSdkText)}
    $w.body.right.profile.text configure -state normal;$w.body.right.profile.text delete 1.0 end;$w.body.right.profile.text insert end $s(viewerProfileText);$w.body.right.profile.text configure -state disabled
    .gxViewerDevelopment.menus.file entryconfigure {Export candidate} -state normal
    .gxViewerDevelopment.menus.develop entryconfigure {Cancel request} -state normal
    .gxViewerDevelopment.menus.edit entryconfigure {Edit Notes} -state normal;.gxViewerDevelopment.menus.view entryconfigure {Show Notes} -state normal
}
