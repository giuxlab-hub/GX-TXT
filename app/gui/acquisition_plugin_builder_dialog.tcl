# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted presentation client of existing Development target/ProjectFiles APIs.
# No compiler, parser, source grant, publication authority or project store here.
namespace eval ::GX::AcquisitionPluginBuilder {variable s;array set s {project {} description {} manifest {} busy {} generation 0 current_profile {} metadata_baseline {} profile_baseline {} status {Create or open an Acquisition source project. No scientific Session is required.}}}
proc ::GX::AcquisitionPluginBuilder::str {value} {return [list text $value]}
proc ::GX::AcquisitionPluginBuilder::object {value} {return [list object $value]}
proc ::GX::AcquisitionPluginBuilder::arrayText {values} {return [list array [lmap value $values {list text $value}]]}
proc ::GX::AcquisitionPluginBuilder::json {typed} {return [::GX::nativeWorkspaceJsonEncode $typed]}
proc ::GX::AcquisitionPluginBuilder::parse {raw {kind object}} {
    if {[string bytelength $raw]>65536} {error {Declaration JSON exceeds64KiB}}
    set typed [::GX::nativeWorkspaceJsonDecode $raw]
    if {[lindex $typed 0] ne $kind} {error "Declaration requires a JSON $kind"}
    return $typed
}
proc ::GX::AcquisitionPluginBuilder::safe {method args} {
    if {[catch {[namespace current]::$method {*}$args} result options]} {set ::GX::AcquisitionPluginBuilder::s(status) $result;return 0}
    return $result
}
proc ::GX::AcquisitionPluginBuilder::ensureIdle {} {variable s;if {$s(busy) ne {}} {error {Wait for the current request or choose Run → Cancel request.}}}
proc ::GX::AcquisitionPluginBuilder::rpc {operation path typed callback} {
    variable s;ensureIdle
    set generation [incr s(generation)]
    set options [expr {$operation in {project_init project_files test}?[dict create request_json [json $typed]]:{}}]
    set s(busy) [::GX::viewerDevelopmentRequest $operation $path [list [namespace current]::reply $generation $path $callback] $options]
    set s(status) "$operation · managed Development request…";controls
    return $s(busy)
}
proc ::GX::AcquisitionPluginBuilder::reply {generation path callback response} {
    variable s
    if {![winfo exists .gxAcquisitionBuilder] || $generation!=$s(generation)} return
    set s(busy) {};controls
    if {![dict get $response ok]} {set s(status) "[::GX::datasetPublicationV2DictDefault $response code REQUEST_REFUSED]: [dict get $response error] · drafts retained";return}
    if {[catch {uplevel #0 [list {*}$callback $path [dict get $response result]]} reason]} {set s(status) "$reason · drafts retained"}
}
proc ::GX::AcquisitionPluginBuilder::edit {operation fields callback} {
    variable s
    if {$s(project) eq {} || $s(description) eq {}} {error {Open or create a saved Acquisition project first}}
    set base [dict create schema [str gxtxt.development_project_edit.v1] operation [str $operation] expected_revision [str [dict get $s(description) revision]]]
    return [rpc project_files $s(project) [object [dict merge $base $fields]] $callback]
}
proc ::GX::AcquisitionPluginBuilder::cancel {} {variable s;if {$s(busy) ne {}} {::GX::scriptJobRequestCancel $s(busy) cancelled;set s(status) {Cancellation requested; refresh to review any completed backend transaction.}}}
proc ::GX::AcquisitionPluginBuilder::lines {widget} {
    set result {};foreach value [split [$widget get 1.0 end-1c] \n] {if {$value ne {}} {lappend result $value}};return $result
}
proc ::GX::AcquisitionPluginBuilder::setLines {widget values} {
    set state [$widget cget -state];$widget configure -state normal
    try {$widget delete 1.0 end;$widget insert end [join $values \n]} finally {$widget configure -state $state}
}
proc ::GX::AcquisitionPluginBuilder::metadata {} {
    variable s
    set fields {}
    foreach key {module_id version name description license} {dict set fields $key [str $s(meta,$key)]}
    dict set fields dependencies [arrayText [lines $s(meta,dependencies_widget)]]
    foreach key {capabilities provenance tests config_fields input_contracts provided_contracts} {dict set fields $key $s(meta,$key)}
    return [object $fields]
}
proc ::GX::AcquisitionPluginBuilder::profile {} {
    variable s
    set fields {};foreach key {id name source_kind} {dict set fields $key [str $s(profile,$key)]}
    foreach key {file_patterns mime_types output_contracts dependencies} {dict set fields $key [arrayText [lines $s(profile,$key,widget)]]}
    foreach key {recognize inspect import} {dict set fields $key [object [dict create file [str $s(profile,$key,file)] symbol [str $s(profile,$key,symbol)]]]}
    foreach key {capabilities limits} {dict set fields $key $s(profile,$key)}
    return [object $fields]
}
proc ::GX::AcquisitionPluginBuilder::review {{which both}} {
    variable s
    if {$s(description) eq {} && $s(project) eq {}} {return 1}
    if {[winfo exists .gxAcquisitionBuilder.declaration]} {error {Finish or cancel the declaration editor before changing context}}
    set dirty 0
    if {$which in {both metadata} && [json [metadata]] ne $s(metadata_baseline)} {set dirty 1}
    if {$which in {both profile} && $s(current_profile) ne {} && [json [profile]] ne $s(profile_baseline)} {set dirty 1}
    if {!$dirty} {return 1}
    # Saving is explicit and asynchronous; never discard a draft while waiting.
    set answer [tk_messageBox -parent .gxAcquisitionBuilder -type yesnocancel -default cancel -icon question -title {Unsaved project declarations} -message {Save declarations before continuing? Yes starts the current tab's Save and keeps this context; retry the action after completion. No discards the local declaration draft. Cancel keeps editing.}]
    if {$answer eq {yes}} {if {$which eq {profile} || [.gxAcquisitionBuilder.tabs select] eq {.gxAcquisitionBuilder.tabs.profiles}} {saveProfile} else {saveMetadata};return 0}
    if {$answer eq {no}} {
        if {$which in {both metadata}} {metadataLoad [parse $s(metadata_baseline)]}
        if {$which in {both profile} && $s(current_profile) ne {}} {profileLoad [parse $s(profile_baseline)] 0}
        return 1
    }
    return 0
}
proc ::GX::AcquisitionPluginBuilder::new {} {
    variable s;ensureIdle;if {![review]} return
    set parent [tk_chooseDirectory -parent .gxAcquisitionBuilder -title {Parent of a new Acquisition source project}]
    if {$parent eq {}} return
    set s(project) [file join $parent acquisition_project_[clock microseconds]];set s(description) {};set s(manifest) {};set s(current_profile) {}
    foreach {key value} {module_id acq.user_importer version 1.0.0 name {New Acquisition importer} description {} license GPL-3.0-or-later} {set s(meta,$key) $value}
    foreach key {provenance tests} {set s(meta,$key) [object {}]}
    foreach key {capabilities config_fields input_contracts provided_contracts} {set s(meta,$key) [list array {}]}
    setLines $s(meta,dependencies_widget) {}
    set s(metadata_baseline) [json [metadata]]
    .gxAcquisitionBuilder.tabs.profiles.inventory.rows delete [.gxAcquisitionBuilder.tabs.profiles.inventory.rows children {}]
    .gxAcquisitionBuilder.tabs.files.inventory.rows delete [.gxAcquisitionBuilder.tabs.files.inventory.rows children {}]
    .gxAcquisitionBuilder.tabs select .gxAcquisitionBuilder.tabs.general
    set s(status) {Unsaved Acquisition project · File → Save project metadata creates only the real target and an explicitly unauthored source starter.}
    controls
}
proc ::GX::AcquisitionPluginBuilder::openProject {{path {}}} {
    ensureIdle;if {![review]} return
    if {$path eq {}} {set path [tk_chooseDirectory -parent .gxAcquisitionBuilder -title {Open Acquisition source project}]}
    if {$path eq {}} return
    set payload [object [dict create schema [str gxtxt.development_project_edit.v1] operation [str describe]]]
    rpc project_files [file normalize $path] $payload [list [namespace current]::described]
}
proc ::GX::AcquisitionPluginBuilder::described {path description {drafts {}} {selected {}} {afterRead {}}} {
    if {[::GX::datasetPublicationV2DictDefault $description schema {}] ne {gxtxt.development_project_description.v1} || ![dict exists $description target] || [dict get $description target] ne {acquisition}} {error {This window opens genuine Acquisition projects; use Development for Viewer/Preview projects.}}
    set request [object [dict create schema [str gxtxt.development_project_edit.v1] operation [str read] expected_revision [str [dict get $description revision]] relative [str project.json]]]
    rpc project_files $path $request [list [namespace current]::manifestRead $description $drafts $selected $afterRead]
}
proc ::GX::AcquisitionPluginBuilder::manifestRead {description drafts selected afterRead path receipt} {
    if {[dict get $receipt revision] ne [dict get $description revision]} {error {Project changed during read; previous draft retained}}
    adopt $path $description [parse [dict get $receipt source]]
    variable s
    if {[dict exists $drafts metadata]} {metadataLoad [dict get $drafts metadata]}
    if {[dict exists $drafts profile]} {
        set draft [dict get $drafts profile]
        set s(current_profile) [dict get $draft id]
        profileLoad [dict get $draft typed] 0
        set s(profile_baseline) [dict get $draft baseline]
    } elseif {$selected ne {}} {
        foreach item [lindex [dict get [lindex $s(manifest) 1] formats] 1] {
            if {[lindex [dict get [lindex $item 1] id] 1] eq $selected} {set s(current_profile) $selected;profileLoad $item 0;break}
        }
    }
    controls
    if {$afterRead ne {}} {uplevel #0 [list {*}$afterRead $path $description]}
}
proc ::GX::AcquisitionPluginBuilder::adopt {path description manifest} {
    variable s
    set s(project) $path;set s(description) $description;set s(manifest) $manifest
    set fields [lindex $manifest 1]
    metadataLoad [object $fields]
    set s(metadata_baseline) [json [metadata]];set s(current_profile) {}
    set tree .gxAcquisitionBuilder.tabs.profiles.inventory.rows;$tree delete [$tree children {}]
    foreach p [dict get $description formats] {
        set id [dict get $p id]
        $tree insert {} end -id $id -text "[dict get $description module_id]/$id" -values [list [dict get $p source_kind] [join [dict get $p output_contracts] {, }] [profileBindingState $p]]
    }
    set tree .gxAcquisitionBuilder.tabs.files.inventory.rows;$tree delete [$tree children {}]
    foreach row [dict get $description files] {$tree insert {} end -id [dict get $row relative] -text [dict get $row relative] -values [list [dict get $row language] [dict get $row role] [dict get $row size_bytes] [dict get $row binding_status]]}
    foreach tree [list .gxAcquisitionBuilder.tabs.profiles.inventory.rows .gxAcquisitionBuilder.tabs.files.inventory.rows] {
        ::GX::_uiFieldTreeFontRows $tree GXAcquisitionBuilder.Treeview
        ::GX::uiFieldInspectionColumnsSchedule $tree {recursive 1 fill {#0}}
    }
    set compiled {};foreach row [dict get $description files] {if {[dict get $row language] eq {cpp}} {lappend compiled [dict get $row relative]}}
    foreach key {recognize inspect import} {$s(callback_file,$key) configure -values $compiled -state readonly}
    set s(status) "[dict get $description module_id] · [llength [dict get $description formats]] profiles · [dict get $description availability_reason]"
    controls
}
proc ::GX::AcquisitionPluginBuilder::saveCurrent {} {
    if {[.gxAcquisitionBuilder.tabs select] eq {.gxAcquisitionBuilder.tabs.profiles}} {saveProfile} else {saveMetadata}
}
proc ::GX::AcquisitionPluginBuilder::saveMetadata {} {
    variable s;ensureIdle
    if {$s(project) eq {}} {error {Choose File → New project first}}
    if {$s(description) eq {}} {
        rpc project_init $s(project) [object [dict create schema [str gxtxt.development_project_init.v1] target [str acquisition] metadata [metadata]]] [list [namespace current]::created]
    } else {
        set drafts {}
        if {$s(current_profile) ne {}} {dict set drafts profile [dict create id $s(current_profile) typed [profile] baseline $s(profile_baseline)]}
        edit metadata_set [dict create patch [metadata]] [list [namespace current]::saved $drafts {}]
    }
}
proc ::GX::AcquisitionPluginBuilder::created {path result} {described $path [dict get $result description]}
proc ::GX::AcquisitionPluginBuilder::saved {drafts selected path result} {described $path [dict get $result description] $drafts $selected}
proc ::GX::AcquisitionPluginBuilder::refresh {} {variable s;ensureIdle;if {![review]} return;if {$s(project) ne {}} {openProject $s(project)}}
proc ::GX::AcquisitionPluginBuilder::profileLoad {typed {selectTab 1}} {
    variable s;set fields [lindex $typed 1]
    foreach key {id name source_kind} {set s(profile,$key) [lindex [dict get $fields $key] 1]}
    foreach key {file_patterns mime_types output_contracts dependencies} {setLines $s(profile,$key,widget) [::GX::nativeWorkspaceDecode [dict get $fields $key]]}
    foreach key {recognize inspect import} {foreach part {file symbol} {set s(profile,$key,$part) [lindex [dict get [lindex [dict get $fields $key] 1] $part] 1]}}
    foreach key {capabilities limits} {set s(profile,$key) [dict get $fields $key]}
    set s(profile_baseline) [json [profile]]
    if {$selectTab} {.gxAcquisitionBuilder.tabs select .gxAcquisitionBuilder.tabs.profiles}
    controls
}
proc ::GX::AcquisitionPluginBuilder::selectProfile {} {
    variable s;if {$s(busy) ne {}} return
    set selected [.gxAcquisitionBuilder.tabs.profiles.inventory.rows selection];if {![llength $selected]} return
    set id [lindex $selected 0];if {$id eq $s(current_profile)} return
    if {![review profile]} {set tree .gxAcquisitionBuilder.tabs.profiles.inventory.rows;$tree selection clear; if {$s(current_profile) ni {{} @new}} {$tree selection set $s(current_profile)};return}
    foreach item [lindex [dict get [lindex $s(manifest) 1] formats] 1] {if {[lindex [dict get [lindex $item 1] id] 1] eq $id} {set s(current_profile) $id;profileLoad $item;break}}
}
proc ::GX::AcquisitionPluginBuilder::newProfile {} {
    variable s;ensureIdle;if {$s(description) eq {}} {error {Create or open the saved project first}};if {![review profile]} return
    set fields [dict create id [str {}] name [str {}] source_kind [str text]]
    foreach key {file_patterns mime_types output_contracts dependencies} {dict set fields $key [arrayText [expr {$key eq {output_contracts}?{table.generic}:{}}]]}
    foreach key {recognize inspect import} {dict set fields $key [object [dict create file [str handlers.cpp] symbol [str {}]]]}
    dict set fields capabilities [list array {}];dict set fields limits [object {}]
    set s(current_profile) @new;profileLoad [object $fields]
    set s(status) {New local profile draft · declare real callbacks in registered C++ sources. No parser is generated.}
}
proc ::GX::AcquisitionPluginBuilder::saveProfile {} {
    variable s;ensureIdle
    if {$s(current_profile) eq {}} {error {Select a profile or choose Project → Add profile}}
    set profile [profile];set id [lindex [dict get [lindex $profile 1] id] 1]
    if {$s(current_profile) ne {@new} && $id ne $s(current_profile)} {error {Profile identity is stable; add another profile for a new ID}}
    if {$s(current_profile) eq {@new} && [dict exists $s(description) profile_sha256 $id]} {error {Profile ID already exists; select it to edit or choose another ID}}
    set expected [list null {}]
    if {[dict exists $s(description) profile_sha256 $id]} {set expected [str [dict get $s(description) profile_sha256 $id]]}
    edit profile_put [dict create profile $profile expected_profile_sha256 $expected] [list [namespace current]::saved [dict create metadata [metadata]] $id]
}
proc ::GX::AcquisitionPluginBuilder::removeProfile {} {
    variable s;ensureIdle
    if {$s(current_profile) in {{} @new}} {error {Select an existing saved profile}}
    set id $s(current_profile)
    if {[tk_messageBox -parent .gxAcquisitionBuilder -type yesno -default no -icon question -title {Remove format profile} -message "Remove saved profile [dict get $s(description) module_id]/$id? Source files remain unchanged."] ne {yes}} return
    edit profile_remove [dict create profile_id [str $id] expected_profile_sha256 [str [dict get $s(description) profile_sha256 $id]]] [list [namespace current]::saved [dict create metadata [metadata]] {}]
}
proc ::GX::AcquisitionPluginBuilder::advancedSearch {operation} {
    variable s
    if {![winfo exists .gxAcquisitionBuilder.declaration] || ![winfo exists $s(advanced_widget)]} {return 0}
    set surface [::GX::sourceSurfaceParent $s(advanced_widget)]
    if {$operation eq {hide}} {
        if {[winfo manager $surface.find] ne {grid}} {return 0}
        grid remove $surface.find;focus $s(advanced_widget);return 1
    }
    if {$operation ni {find replace}} {error {Unknown declaration search presentation}}
    grid $surface.find
    focus [expr {$operation eq {replace}?"$surface.find.replace.value":"$surface.find.query"}]
    return 1
}
proc ::GX::AcquisitionPluginBuilder::advanced {scope key kind} {
    variable s;ensureIdle
    set w .gxAcquisitionBuilder.declaration;catch {destroy $w}
    ::GX::uiFieldDialogCreate $w .gxAcquisitionBuilder "Declared $key" 760x520
    menu $w.menus -tearoff 0;$w configure -menu $w.menus
    menu $w.menus.edit -tearoff 0;$w.menus add cascade -label Edit -underline 0 -menu $w.menus.edit
    foreach {label operation} {Undo undo Redo redo {Select all} select_all Copy copy Cut cut Paste paste} {$w.menus.edit add command -label $label -command [list ::GX::uiTextEdit $w $operation]}
    foreach {label operation shortcut} {{Find…} find Ctrl+F {Replace…} replace Ctrl+H} {$w.menus.edit add command -label $label -accelerator $shortcut -command [list [namespace current]::advancedSearch $operation]}
    ttk::frame $w.buttons
    ttk::button $w.buttons.apply -text {Keep draft} -command [list [namespace current]::safe advancedApply $scope $key $kind]
    ttk::button $w.buttons.cancel -text Cancel -command [list ::GX::uiFieldDialogClose $w]
    pack $w.buttons.apply $w.buttons.cancel -side left -padx 5;pack $w.buttons -side bottom -fill x -padx 8 -pady 6
    set notice {Typed JSON declaration. CORE validates API/version/operation requests. Keep draft, then use the primary Save action. Ctrl+F/H reveals Find/Replace; Escape returns to the source.}
    if {$scope eq {meta} && $key eq {config_fields}} {set notice {Ordered fields: id,type,label,default,required. Choice adds values; numeric fields allow min/max. Up to32; format_profile is reserved. Keep JSON types. Full schema: Developer manual. Ctrl+F/H searches.}}
    if {$scope eq {meta} && $key eq {input_contracts}} {set notice {Ordered JSON array of literal Contract IDs, up to64 unique IDs. These are input declarations; CORE decides actual compatibility and dependencies. Keep draft, then Save project metadata.}}
    if {$scope eq {meta} && $key eq {provided_contracts}} {set notice {Ordered JSON array of definitions: id,description,parents (an ID array). Up to64 definitions; duplicate IDs/self-parents/local cycles refuse. These are declarations. Actual installed providers and compatibility remain CORE decisions.}}
    ttk::label $w.notice -text $notice -wraplength 680 -padding 8;pack $w.notice -fill x
    set s(advanced_widget) [::GX::sourceSurfaceCreate $w.source {mode editable language javascript find_bar 1}]
    pack $w.source -fill both -expand 1
    set encoded [json $s($scope,$key)]
    if {$kind eq {array} && [llength [lindex $s($scope,$key) 1]]} {set encoded "\[\n  [join [lmap item [lindex $s($scope,$key) 1] {json $item}] ",\n  "]\n\]"}
    ::GX::sourceSurfaceSet $s(advanced_widget) $encoded
    grid remove $w.source.find
    foreach {sequence operation} {<Control-f> find <Control-h> replace} {bind $s(advanced_widget) $sequence "[list [namespace current]::advancedSearch $operation];break"}
    foreach control [list $s(advanced_widget) $w.source.find.query $w.source.find.previous $w.source.find.next $w.source.find.replace.value $w.source.find.replace.current $w.source.find.replace.all] {bind $control <Escape> "if {\[[namespace current]::advancedSearch hide\]} {break}"}
    set s(advanced_context) [list $s(project) $s(generation) $s(current_profile)]
    ::GX::uiFieldDialogPresent $w $s(advanced_widget) 1
}
proc ::GX::AcquisitionPluginBuilder::advancedApply {scope key kind} {
    variable s
    try {
        if {$s(advanced_context) ne [list $s(project) $s(generation) $s(current_profile)]} {error {Declaration belongs to an earlier context; copy it or cancel before retrying}}
        set typed [parse [::GX::sourceSurfaceGet $s(advanced_widget)] $kind]
    } on error {message options} {
        if {[winfo exists .gxAcquisitionBuilder.declaration.notice]} {.gxAcquisitionBuilder.declaration.notice configure -text "Declaration refused: $message"}
        return -options $options $message
    }
    set s($scope,$key) $typed
    ::GX::uiFieldDialogClose .gxAcquisitionBuilder.declaration
    set s(status) "$key draft retained; use the primary Save action to persist with revision checks."
}
proc ::GX::AcquisitionPluginBuilder::sources {} {
    variable s;ensureIdle;if {$s(description) eq {}} {error {Create or open the project first}}
    ::GX::viewerBackendEnsure viewer.development_workspace development_workspace
    ::GX::ViewerDevelopmentWorkspace::open [dict create project $s(project)]
    if {[info exists s(last_run)] && [dict get $s(last_run) project] eq $s(project)} {reportInSourceWorkspace $s(project) [dict get $s(last_run) operation] [dict get $s(last_run) result]}
}
proc ::GX::AcquisitionPluginBuilder::run {operation} {
    variable s;ensureIdle
    if {![review]} return
    set flag [expr {$operation in {validate build export}?{build_available}:($operation eq {test}?{project_test_available}:{runtime_available})}]
    if {$s(description) eq {} || ![dict get $s(description) $flag]} {error {This target capability is not admitted yet; source/project drafts remain available.}}
    if {$operation in {build export} && ![eligibleProfiles]} {error {At least one saved profile with current AST-eligible callbacks is required}}
    if {$operation eq {test}} {return [testChoose]}
    rpc $operation $s(project) [object {}] [list [namespace current]::runDone $operation $s(current_profile)]
}
proc ::GX::AcquisitionPluginBuilder::testContextValid {context} {
    variable s
    if {![winfo exists .gxAcquisitionBuilder] || $s(busy) ne {} || $s(description) eq {} || $context ne [list $s(project) [dict get $s(description) revision] $s(generation) $s(current_profile)]} {return 0}
    return [expr {[json [metadata]] eq $s(metadata_baseline) && ($s(current_profile) eq {} || [json [profile]] eq $s(profile_baseline))}]
}
proc ::GX::AcquisitionPluginBuilder::testChoose {} {
    variable s;ensureIdle
    set context [list $s(project) [dict get $s(description) revision] $s(generation) $s(current_profile)]
    return [::GX::viewerDevelopmentAcquisitionTestChoose .gxAcquisitionBuilder $s(description) $s(current_profile) [list [namespace current]::testContextValid $context] [list [namespace current]::testSubmit]]
}
proc ::GX::AcquisitionPluginBuilder::testSubmit {profile request} {
    variable s;ensureIdle
    rpc test $s(project) [::GX::nativeWorkspaceJsonDecode $request] [list [namespace current]::runDone test $profile]
}
proc ::GX::AcquisitionPluginBuilder::runDone {operation selected path result} {
    rpc project_files $path [object [dict create schema [str gxtxt.development_project_edit.v1] operation [str describe]]] [list [namespace current]::runDescribed $operation $result $selected]
}
proc ::GX::AcquisitionPluginBuilder::runDescribed {operation result selected path description} {
    described $path $description {} $selected [list [namespace current]::runReport $operation $result]
}
proc ::GX::AcquisitionPluginBuilder::runReport {operation result path description} {
    variable s
    set s(last_run) [dict create project $path operation $operation result $result]
    set report [::GX::datasetPublicationV2DictDefault $result validation $result]
    set summary "$operation · [dict get $result status]"
    if {[dict exists $result package]} {append summary " · [dict get $result package]"}
    set diagnostics [::GX::datasetPublicationV2DictDefault $report diagnostics {}]
    if {[llength $diagnostics]} {
        set item [lindex $diagnostics 0]
        append summary " · [dict get $item file]:[dict get $item line]:[dict get $item column] [lindex [split [dict get $item message] \n] 0] · full report in the source workspace"
    }
    set s(status) $summary
    reportInSourceWorkspace $path $operation $result
}
proc ::GX::AcquisitionPluginBuilder::reportInSourceWorkspace {path operation result} {
    if {![winfo exists .gxViewerDevelopment] || $::GX::ViewerDevelopmentWorkspace::s(project) ne $path} return
    ::GX::ViewerDevelopmentWorkspace::log "$operation: $result\n"
    ::GX::ViewerDevelopmentWorkspace::diagnosticsShow [::GX::datasetPublicationV2DictDefault $result validation $result]
}
proc ::GX::AcquisitionPluginBuilder::metadataLoad {typed} {
    variable s;set fields [lindex $typed 1]
    foreach key {module_id version name description license} {set s(meta,$key) [lindex [dict get $fields $key] 1]}
    foreach key {capabilities provenance tests} {set s(meta,$key) [dict get $fields $key]}
    foreach key {config_fields input_contracts provided_contracts} {set s(meta,$key) [::GX::datasetPublicationV2DictDefault $fields $key [list array {}]]}
    setLines $s(meta,dependencies_widget) [::GX::nativeWorkspaceDecode [dict get $fields dependencies]]
}
proc ::GX::AcquisitionPluginBuilder::profileBindingState {profile} {
    variable s
    if {$s(description) eq {}} {return unvalidated}
    set files {};foreach row [dict get $s(description) files] {dict set files [dict get $row relative] $row}
    foreach key {recognize inspect import} {
        set binding [dict get $profile $key];set file [dict get $binding file]
        if {![dict exists $files $file] || [dict get $binding symbol] ni [dict get $files $file validated_entrypoints]} {return unvalidated}
    }
    return validated_ast
}
proc ::GX::AcquisitionPluginBuilder::eligibleProfiles {} {
    variable s
    if {$s(description) eq {} || ![llength [dict get $s(description) formats]]} {return 0}
    foreach profile [dict get $s(description) formats] {if {[profileBindingState $profile] ne {validated_ast}} {return 0}}
    return 1
}

proc ::GX::AcquisitionPluginBuilder::controls {} {
    variable s;if {![winfo exists .gxAcquisitionBuilder]} return
    set idle [expr {$s(busy) eq {}}];set saved [expr {$s(description) ne {}}]
    foreach {menu labels} {file {{New project…} {Open project…} {Save project metadata} {Open source workspace}} project {{Add profile} {Save profile} {Remove profile}} view {{Refresh from disk}}} {
        foreach label $labels {.gxAcquisitionBuilder.menus.$menu entryconfigure $label -state [expr {$idle && ($menu ne {project} || $saved)?{normal}:{disabled}}]}
    }
    foreach {label flag} {Validate build_available Build build_available Test project_test_available {Export candidate} build_available} {
        set eligible [expr {$label ni {Build {Export candidate}} || [eligibleProfiles]}]
        .gxAcquisitionBuilder.menus.run entryconfigure $label -state [expr {$idle && $saved && [dict get $s(description) $flag] && $eligible?{normal}:{disabled}}]
    }
    .gxAcquisitionBuilder.menus.run entryconfigure {Cancel request} -state [expr {$idle?{disabled}:{normal}}]
    .gxAcquisitionBuilder.menus.file entryconfigure {Save project metadata} -state [expr {$idle && $s(project) ne {}?{normal}:{disabled}}]
    foreach label {{Save profile} {Remove profile}} {.gxAcquisitionBuilder.menus.project entryconfigure $label -state [expr {$idle && $saved && $s(current_profile) ne {} && ($label ne {Remove profile} || $s(current_profile) ne {@new})?{normal}:{disabled}}]}
    set pending [winfo children .gxAcquisitionBuilder.tabs]
    for {set i 0} {$i<[llength $pending]} {incr i} {
        set widget [lindex $pending $i];lappend pending {*}[winfo children $widget]
        set class [winfo class $widget]
        set editable [expr {$idle && $s(project) ne {}}]
        if {[string match .gxAcquisitionBuilder.tabs.profiles.form.* $widget] && $s(current_profile) eq {}} {set editable 0}
        if {$class in {TEntry TCombobox}} {$widget configure -state [expr {!$editable?{disabled}:($class eq {TCombobox}?{readonly}:{normal})}]}
        if {$class eq {Text}} {$widget configure -state [expr {$editable?{normal}:{disabled}}]}
        if {$class eq {TButton} && [string match *.b* $widget]} {$widget configure -state [expr {$editable?{normal}:{disabled}}]}
    }
    set s(identity) [expr {$saved?"[dict get $s(description) module_id] / [dict get $s(description) version] · $s(project)":$s(project)}]
}
proc ::GX::AcquisitionPluginBuilder::close {} {
    variable s;ensureIdle;if {![review]} return
    cancel;incr s(generation);destroy .gxAcquisitionBuilder
}
proc ::GX::AcquisitionPluginBuilder::open {{action open} {path {}}} {
    variable s;set w .gxAcquisitionBuilder
    if {[winfo exists $w]} {raise $w;if {$path ne {} && $path ne $s(project)} {safe openProject $path} elseif {$path eq {} && $action eq {new}} {safe new} elseif {$path eq {} && $action eq {open}} {safe openProject};return $w}
    set s(project) {};set s(description) {};set s(manifest) {};set s(busy) {};set s(current_profile) {};incr s(generation)
    toplevel $w;wm title $w {GX-TXT Acquisition Plugin Builder};wm geometry $w 1100x780;wm minsize $w 760 580
    menu $w.menus -tearoff 0;$w configure -menu $w.menus
    foreach {key title} {file File edit Edit project Project view View run Run help Help} {menu $w.menus.$key -tearoff 0;$w.menus add cascade -label $title -underline 0 -menu $w.menus.$key}
    foreach {label method} {{New project…} new {Open project…} openProject {Save project metadata} saveMetadata {Open source workspace} sources Close close} {$w.menus.file add command -label $label -command [list [namespace current]::safe $method]}
    foreach {label operation} {Undo undo Redo redo {Select all} select_all Copy copy Cut cut Paste paste} {$w.menus.edit add command -label $label -command [list ::GX::uiTextEdit $w $operation]}
    foreach {label method} {{Add profile} newProfile {Save profile} saveProfile {Remove profile} removeProfile} {$w.menus.project add command -label $label -command [list [namespace current]::safe $method]}
    $w.menus.view add command -label {Refresh from disk} -command [list [namespace current]::safe refresh]
    foreach {label op} {Validate validate Build build Test test {Export candidate} export} {$w.menus.run add command -label $label -command [list [namespace current]::safe run $op]}
    $w.menus.run add command -label {Cancel request} -command [list [namespace current]::cancel]
    $w.menus.help add command -label {Developer manual} -command {::GX::documentationBrowserOpenModuleWindow viewer.development_workspace .gxAcquisitionBuilder}
    $w.menus.help add command -label {Development public API} -command {::GX::documentationBrowserOpenApiWindow VIEWER_DEVELOPMENT_API_v1}
    ttk::entry $w.identity -textvariable ::GX::AcquisitionPluginBuilder::s(identity) -state readonly;pack $w.identity -fill x -padx 8 -pady 4
    ttk::label $w.status -textvariable ::GX::AcquisitionPluginBuilder::s(status) -anchor w -wraplength 1000;pack $w.status -side bottom -fill x -padx 8 -pady 4
    bind $w.status <Configure> [list ::GX::_uiFieldComponentTextWrap $w.status 32767 %W %w]
    ttk::notebook $w.tabs;pack $w.tabs -fill both -expand 1
    foreach {id title} {general {Module metadata} profiles {Format profiles} files {Registered sources}} {ttk::frame $w.tabs.$id;$w.tabs add $w.tabs.$id -text $title}
    set body [::GX::uiFieldScrollableCreate $w.tabs.general.form 850];pack $w.tabs.general.form -fill both -expand 1
    grid columnconfigure $body 1 -weight 1;set row 0
    foreach {key label} {module_id {Module ID} version Version name Name description Description license License} {ttk::label $body.l$key -text $label;ttk::entry $body.e$key -textvariable ::GX::AcquisitionPluginBuilder::s(meta,$key);grid $body.l$key -row $row -column 0 -sticky w -padx 8 -pady 5;grid $body.e$key -row $row -column 1 -sticky ew -padx 8 -pady 5;incr row}
    ttk::label $body.ldep -text {Dependencies (one ID per line)};text $body.dependencies -height 3 -width 20 -wrap none;set s(meta,dependencies_widget) $body.dependencies
    grid $body.ldep -row $row -column 0 -sticky nw -padx 8;grid $body.dependencies -row $row -column 1 -sticky ew -padx 8;incr row
    foreach {key kind} {capabilities array provenance object tests object config_fields array input_contracts array provided_contracts array} {
        set labels [dict create config_fields {Edit configuration fields…} input_contracts {Edit input Contract declarations…} provided_contracts {Edit provided Contract declarations…}]
        set label [::GX::datasetPublicationV2DictDefault $labels $key "Edit $key declarations…"]
        ttk::button $body.b$key -text $label -command [list [namespace current]::safe advanced meta $key $kind]
        grid $body.b$key -row $row -column 1 -sticky w -padx 8 -pady 5;incr row
    }
    ttk::label $body.note -text {A real Acquisition source project has registered C++/header/helper files and provider-qualified format profiles. Registration is not compilation or helper execution. RAW, Session, source grants and publication remain CORE-owned.} -wraplength 680;grid $body.note -row $row -column 0 -columnspan 2 -sticky ew -padx 8 -pady 8
    # Actual profile and source inventories remain accessible across their tabs.
    ttk::frame $w.tabs.profiles.inventory;pack $w.tabs.profiles.inventory -fill x
    ttk::treeview $w.tabs.profiles.inventory.rows -columns {kind contracts binding} -show {tree headings} -height 3 -selectmode browse
    foreach {id title width} {#0 {Qualified profile} 250 kind Source 100 contracts Contracts 220 binding Bindings 160} {$w.tabs.profiles.inventory.rows heading $id -text $title;$w.tabs.profiles.inventory.rows column $id -width $width -minwidth 70}
    ttk::scrollbar $w.tabs.profiles.inventory.h -orient horizontal -command [list $w.tabs.profiles.inventory.rows xview];ttk::scrollbar $w.tabs.profiles.inventory.v -command [list $w.tabs.profiles.inventory.rows yview]
    $w.tabs.profiles.inventory.rows configure -xscrollcommand [list $w.tabs.profiles.inventory.h set] -yscrollcommand [list $w.tabs.profiles.inventory.v set]
    pack $w.tabs.profiles.inventory.h -side bottom -fill x;pack $w.tabs.profiles.inventory.v -side right -fill y;pack $w.tabs.profiles.inventory.rows -fill x
    bind $w.tabs.profiles.inventory.rows <<TreeviewSelect>> [list [namespace current]::safe selectProfile]
    set body [::GX::uiFieldScrollableCreate $w.tabs.profiles.form 850];pack $w.tabs.profiles.form -fill both -expand 1
    grid columnconfigure $body 1 -weight 1;set row 0
    foreach {key label} {id {Local profile ID} name Name source_kind {Source kind}} {
        ttk::label $body.l$key -text $label
        if {$key eq {source_kind}} {ttk::combobox $body.e$key -state readonly -values {text binary} -textvariable ::GX::AcquisitionPluginBuilder::s(profile,$key)} else {ttk::entry $body.e$key -textvariable ::GX::AcquisitionPluginBuilder::s(profile,$key)}
        grid $body.l$key -row $row -column 0 -sticky w -padx 8 -pady 4;grid $body.e$key -row $row -column 1 -columnspan 2 -sticky ew -padx 8 -pady 4;incr row
    }
    foreach key {recognize inspect import} {
        ttk::label $body.l$key -text "[string totitle $key] callback"
        ttk::combobox $body.f$key -textvariable ::GX::AcquisitionPluginBuilder::s(profile,$key,file) -values handlers.cpp
        ttk::entry $body.s$key -textvariable ::GX::AcquisitionPluginBuilder::s(profile,$key,symbol)
        set s(callback_file,$key) $body.f$key
        grid $body.l$key -row $row -column 0 -sticky w -padx 8 -pady 4;grid $body.f$key -row $row -column 1 -sticky ew -padx 8 -pady 4;grid $body.s$key -row $row -column 2 -sticky ew -padx 8 -pady 4;incr row
    }
    grid columnconfigure $body 2 -weight 1
    foreach {key title} {file_patterns {Filename patterns (one per line)} mime_types {MIME hints (one per line)} output_contracts {Output contracts (one per line)} dependencies {Profile dependencies (one per line)}} {
        ttk::label $body.l$key -text $title;text $body.e$key -height 2 -width 20 -wrap none
        set s(profile,$key,widget) $body.e$key
        grid $body.l$key -row $row -column 0 -sticky nw -padx 8 -pady 4;grid $body.e$key -row $row -column 1 -columnspan 2 -sticky ew -padx 8 -pady 4;incr row
    }
    foreach {key kind} {capabilities array limits object} {ttk::button $body.b$key -text "Edit $key declarations…" -command [list [namespace current]::safe advanced profile $key $kind];grid $body.b$key -row $row -column 1 -columnspan 2 -sticky w -padx 8 -pady 4;incr row}
    ttk::label $body.notice -text {Patterns/MIME are hints, not recognition proof. Callbacks must be real declared qualified C++ functions; actual AST eligibility comes from matching backend validation. Unknown contracts remain declared data, never invented compatibility.} -wraplength 680;grid $body.notice -row $row -column 0 -columnspan 3 -sticky ew -padx 8 -pady 8
    ttk::frame $w.tabs.files.inventory;pack $w.tabs.files.inventory -fill both -expand 1
    ttk::treeview $w.tabs.files.inventory.rows -columns {language role bytes binding} -show {tree headings} -height 10
    foreach {id title width} {#0 File 260 language Language 100 role Role 160 bytes Bytes 90 binding {Entry binding} 160} {$w.tabs.files.inventory.rows heading $id -text $title;$w.tabs.files.inventory.rows column $id -width $width -minwidth 70}
    ttk::scrollbar $w.tabs.files.inventory.h -orient horizontal -command [list $w.tabs.files.inventory.rows xview];ttk::scrollbar $w.tabs.files.inventory.v -command [list $w.tabs.files.inventory.rows yview]
    $w.tabs.files.inventory.rows configure -xscrollcommand [list $w.tabs.files.inventory.h set] -yscrollcommand [list $w.tabs.files.inventory.v set]
    pack $w.tabs.files.inventory.h -side bottom -fill x;pack $w.tabs.files.inventory.v -side right -fill y;pack $w.tabs.files.inventory.rows -fill both -expand 1
    bind $w.tabs.files.inventory.rows <Double-1> [list [namespace current]::safe sources]
    foreach tree [list $w.tabs.files.inventory.rows $w.tabs.profiles.inventory.rows] {::GX::_uiFieldTreeFontRows $tree GXAcquisitionBuilder.Treeview;bind $tree <<ThemeChanged>> +[list ::GX::_uiFieldTreeFontRows $tree GXAcquisitionBuilder.Treeview]}
    ::GX::uiTextEditingAttach $w [concat [list $w.identity $s(meta,dependencies_widget)] [lmap key {file_patterns mime_types output_contracts dependencies} {set a $s(profile,$key,widget)}]]
    wm protocol $w WM_DELETE_WINDOW [list [namespace current]::safe close]
    bind $w <Control-s> [list [namespace current]::safe saveCurrent]
    foreach {key value} {module_id {} version 1.0.0 name {} description {} license GPL-3.0-or-later} {set s(meta,$key) $value}
    foreach key {provenance tests} {set s(meta,$key) [object {}]}
    foreach key {capabilities config_fields input_contracts provided_contracts} {set s(meta,$key) [list array {}]}
    foreach key {capabilities limits} {set s(profile,$key) [expr {$key eq {capabilities}?[list array {}]:[object {}]}]}
    set s(metadata_baseline) [json [metadata]];controls
    if {$path ne {}} {safe openProject $path} elseif {$action eq {new}} {safe new} elseif {$action eq {open}} {safe openProject}
    return $w
}
