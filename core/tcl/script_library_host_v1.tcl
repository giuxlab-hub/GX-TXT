# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generic GUI client of the existing Script Registry/Project owners.
# MAIN supplies actual module/SDK/user-event/Session admission. No fallback grant.
namespace eval ::GX::ScriptLibraryHost {variable bindings {};variable serial 0;variable answers}
proc ::GX::_scriptLibraryHostGuard {window form operation} {
    if {![llength [info commands ::GX::_viewerGuiScriptLibraryGuard]]} {
        error {Script Library admission is unavailable in this CORE; no operation was performed}
    }
    set context [_viewerGuiScriptLibraryGuard $window $form $operation]
    foreach key {module_id session_token components component_ids user_action} {
        if {![dict exists $context $key]} {error {Incomplete trusted Script Library admission}}
    }
    return $context
}
proc ::GX::_scriptLibraryHostKey {window form} {return [list $window $form]}
proc ::GX::_scriptLibraryHostGet {key} {
    if {![dict exists $::GX::ScriptLibraryHost::bindings $key]} {error {Script Library binding has closed}}
    return [dict get $::GX::ScriptLibraryHost::bindings $key]
}
proc ::GX::_scriptLibraryHostPut {key record} {dict set ::GX::ScriptLibraryHost::bindings $key $record}
proc ::GX::_scriptLibraryHostWidget {context role} {
    if {![dict exists $context components $role]} {error "Missing declared Script Library role '$role'"}
    set widget [dict get $context components $role]
    if {![winfo exists $widget]} {error {A declared Script Library component has closed}}
    return $widget
}
proc ::GX::_scriptLibraryHostValue {context role {type field}} {
    return [uiFieldComponentRead [_scriptLibraryHostWidget $context $role] $type]
}
proc ::GX::_scriptLibraryHostSetValue {window context role value} {
    viewerGuiDesignValueSet $window [dict get $context component_ids $role] $value
}
proc ::GX::_scriptLibraryHostStatus {window context message} {
    viewerGuiDesignTextSet $window [dict get $context component_ids operation_status] $message
}
proc ::GX::_scriptLibraryHostEnsure {window form context} {
    variable ::GX::ScriptLibraryHost::bindings
    variable ::GX::ScriptLibraryHost::serial
    set key [_scriptLibraryHostKey $window $form]
    set source [_scriptLibraryHostWidget $context registered_source]
    set roster [_scriptLibraryHostWidget $context source_files]
    set parameters [_scriptLibraryHostWidget $context parameter_definitions]
    set identity [list [dict get $context module_id] [winfo id $window] [winfo id $source] [winfo id $roster] [winfo id $parameters]]
    if {[dict exists $bindings $key]} {
        if {[dict get $bindings $key identity] ne $identity} {error {Script Library components changed; close the previous binding normally}}
        return $key
    }
    set token "script-library-draft-[pid]-[incr serial]-[clock clicks]"
    set tree $roster.libraryFiles$serial
    ttk::treeview $tree -columns {role sha256} -show {tree headings} -selectmode browse
    $tree heading #0 -text {Source file};$tree heading role -text Role;$tree heading sha256 -text SHA-256
    $tree column #0 -width 190 -stretch 0;$tree column role -width 90 -stretch 0;$tree column sha256 -width 480 -stretch 0
    ttk::scrollbar ${tree}Y -command [list $tree yview]
    ttk::scrollbar ${tree}X -orient horizontal -command [list $tree xview]
    $tree configure -yscrollcommand [list ${tree}Y set] -xscrollcommand [list ${tree}X set]
    grid $tree -row 0 -column 0 -sticky nsew;grid ${tree}Y -row 0 -column 1 -sticky ns;grid ${tree}X -row 1 -column 0 -sticky ew
    grid rowconfigure $roster 0 -weight 1;grid columnconfigure $roster 0 -weight 1
    uiFieldInspectionColumnsFit $tree
    set sourceHost $source.librarySources$serial
    ttk::frame $sourceHost;pack $sourceHost -fill both -expand 1
    set parameterHost $parameters.libraryParameters$serial
    set parameterText [sourceSurfaceCreate $parameterHost [dict create mode editable language plaintext find_bar 1 find_bar_visible 0 change_command [list ::GX::_scriptLibraryHostChanged $window $form]]]
    pack $parameterHost -fill both -expand 1
    set record [dict create identity $identity context $context binding_token $token draft_token $token selected {} baseline {} session_token {} \
        active_file {} sources {} source_host $sourceHost tree $tree parameter_host $parameterHost parameter_text $parameterText \
        parameter_baseline {} parameter_definitions {} metadata_baseline {} inventory {offset 0 limit 50 total 0 records {}} \
        row_references {} filters {scope all language all query {}} busy 0 generation 1]
    dict set bindings $key $record
    # Native pane weights describe the authored initial proportions. Requested
    # tree/text widths otherwise consume narrow pages before weights can resize.
    set ancestor [winfo parent $source]
    while {$ancestor ne "$window.body.canvas" && $ancestor ne $window && $ancestor ne {.}} {
        if {[winfo class $ancestor] eq {TPanedwindow}} {
            bind $ancestor <Map> +[list ::GX::_scriptLibraryHostPaneMap $window $form $token $ancestor %W]
            if {[winfo ismapped $ancestor]} {_scriptLibraryHostPaneMap $window $form $token $ancestor $ancestor}
        }
        set ancestor [winfo parent $ancestor]
    }
    foreach {role choices} {scope_filter {all user session} language_filter {all python octave}} {
        viewerGuiDesignChoicesSet $window [dict get $context component_ids $role] $choices
        set value [_scriptLibraryHostValue $context $role choice]
        if {$value ni $choices} {_scriptLibraryHostSetValue $window $context $role all}
    }
    # Generic Source/roster owner state only. The existing common Viewer callback
    # receives the declared panel ID; no worker ever obtains this widget path.
    bind $tree <<TreeviewSelect>> [list ::GX::_scriptLibraryHostSourceSelected $window $form $token]
    bind $tree <FocusIn> +[list ::GX::_scriptLibraryHostRememberFocus $key $tree]
    bind $parameterText <FocusIn> +[list ::GX::_scriptLibraryHostRememberFocus $key $parameterText]
    _scriptLibraryHostRenderMetadata $window $context [dict merge [scriptRegistryDefaults] {scope user}] 0 0
    sourceSurfaceConfigure $parameterText {mode read_only}
    return $key
}
proc ::GX::_scriptLibraryHostPaneMap {window form token pane actual} {
    if {$pane ne $actual || [catch {set context [_scriptLibraryHostGuard $window $form source_notification]}]} return
    set key [_scriptLibraryHostKey $window $form];set record [_scriptLibraryHostGet $key]
    if {[dict get $record binding_token] ne $token || [dict exists $record initial_splitters $pane]} return
    dict set record initial_splitters $pane pending;_scriptLibraryHostPut $key $record
    after idle [list ::GX::_scriptLibraryHostPaneApply $window $form $token $pane [winfo id $pane] 0]
}
proc ::GX::_scriptLibraryHostPaneApply {window form token pane identity attempt} {
    if {![winfo exists $pane] || [winfo id $pane] ne $identity || [catch {_scriptLibraryHostGuard $window $form source_notification}]} return
    set key [_scriptLibraryHostKey $window $form];set record [_scriptLibraryHostGet $key]
    if {[dict get $record binding_token] ne $token || ![dict exists $record initial_splitters $pane] || [dict get $record initial_splitters $pane] ne {pending}} return
    set room [expr {[$pane cget -orient] eq {horizontal}?[winfo width $pane]:[winfo height $pane]}]
    if {$room<2 || ![winfo ismapped $pane]} {
        if {$attempt<4} {after 25 [list ::GX::_scriptLibraryHostPaneApply $window $form $token $pane $identity [expr {$attempt+1}]]}
        return
    }
    set total 0;set weights {}
    foreach child [$pane panes] {
        set weight [$pane pane $child -weight]
        if {$weight<=0} {return}
        incr total $weight;lappend weights $weight
    }
    if {[llength $weights]>1} {
        set cumulative 0
        for {set index 0} {$index<[llength $weights]-1} {incr index} {
            incr cumulative [lindex $weights $index]
            $pane sashpos $index [expr {int(double($room)*$cumulative/$total)}]
        }
    }
    dict set record initial_splitters $pane done;_scriptLibraryHostPut $key $record
}

proc ::GX::_scriptLibraryHostRememberFocus {key widget} {
    if {[dict exists $::GX::ScriptLibraryHost::bindings $key]} {dict set ::GX::ScriptLibraryHost::bindings $key last_focus $widget}
}
proc ::GX::_scriptLibraryHostSourceSelected {window form token} {
    if {[catch {set context [_scriptLibraryHostGuard $window $form source_notification]}]} return
    set key [_scriptLibraryHostKey $window $form];set record [_scriptLibraryHostGet $key]
    if {[dict get $record binding_token] ne $token || [dict get $record busy]} return
    set tree [dict get $record tree];set selection [$tree selection]
    if {[llength $selection]!=1 || ![dict exists $record file_rows [lindex $selection 0]]} return
    # Only report actual source selection to the existing Viewer/native event
    # owner. The C++ client still emits the finite source_select request.
    set relative [dict get $record file_rows [lindex $selection 0]]
    if {$relative eq [dict get $record active_file]} {
        dict set record selected_relative_file $relative;_scriptLibraryHostPut $key $record
        return
    }
    dict set record selected_relative_file $relative;_scriptLibraryHostPut $key $record
    viewerGuiTraceEmit $window [dict get $context component_ids source_files] selected [dict create status selected relative_file $relative]
    if {[llength [info commands ::GX::_viewerGuiScriptLibrarySourceEvent]]} {
        _viewerGuiScriptLibrarySourceEvent $window $form [dict get $context component_ids source_files]
    }
}
proc ::GX::_scriptLibraryHostMetadata {context {validate 1}} {
    set result {}
    foreach {role field} {record_scope scope record_language language record_id id record_name name record_version version record_description description record_required_apis required_apis} {
        dict set result $field [_scriptLibraryHostValue $context $role]
    }
    if {!$validate} {return $result}
    set language [string tolower [dict get $result language]]
    if {$language ni {python octave}} {error {Choose Python or Octave}}
    dict set result language [expr {$language eq {python}?{Python}:{Octave}}]
    if {[dict get $result scope] ni {user session}} {error {Choose User or Session scope}}
    return $result
}
proc ::GX::_scriptLibraryHostMetadataProjection {metadata} {
    set result {};foreach key {scope language id name version description required_apis} {dict set result $key [dict get $metadata $key]}
    return $result
}
proc ::GX::_scriptLibraryHostIdentityText {metadata reference} {
    set description "[dict get $metadata name]\n[dict get $metadata language] · [dict get $metadata kind] · [dict get $metadata scope]\n"
    append description "Reference: [expr {$reference eq {}?{New draft}:$reference}]\nVersion: [dict get $metadata version]\nRevision: [dict get $metadata revision]\nSHA-256: [dict get $metadata sha256]\n"
    append description "Source lineage: [dict get $metadata source_scope] / [dict get $metadata source_id]\nOriginal source SHA-256: [dict get $metadata source_sha256]\nRequired/consumed APIs (effective): [dict get $metadata required_apis]\nSource-declared consumed APIs: [dict get $metadata declared_apis]\nExplicit consumed APIs (metadata): [dict get $metadata explicit_apis]\nNamed callables (registered): [dict keys [dict get $metadata callables]]\n"
    append description "\nSource-declared provided APIs — canonical static snapshot only\nLocal unsaved edits are not included; declarations grant no registration or execution authority.\n"
    if {$reference eq {}} {
        append description "Save the new source before inspecting its registered API inventory.\n"
    } elseif {![llength [info commands ::GX::scriptRegistryProvidedApiInventory]]} {
        append description "Provided API inventory is unavailable in this CORE.\n"
    } elseif {[catch {set inventory [scriptRegistryProvidedApiInventory $reference [_scriptLibraryHostExpected $metadata]]} problem]} {
        append description "Inventory unavailable for this exact record/namespace: $problem\n"
    } else {
        append description "Source scope: [dict get $inventory source_scope]\nStatic declarations valid: [dict get $inventory valid]\nInventory SHA-256: [dict get $inventory declaration_sha256]\nInventory consumed APIs: [dict get $inventory consumed]\n"
        if {![llength [dict get $inventory provided]]} {append description "Provided APIs: none declared.\n"}
        foreach api [dict get $inventory provided] {append description "  [dict get $api id] @ [dict get $api version] — [join [dict get $api operations] {, }]\n"}
        if {[llength [dict get $inventory diagnostics]]} {append description "Static diagnostics: [llength [dict get $inventory diagnostics]]; review the declared source in the existing Workspace.\n"}
    }
    append description "\nPer-file Notes use the existing language Workspace."
    if {[string length [encoding convertto utf-8 $description]]>1048576} {error {Script identity details exceed the maintained consultation bound}}
    return $description
}
proc ::GX::_scriptLibraryHostRenderMetadata {window context metadata existing {active 1}} {
    foreach {role field} {record_scope scope record_language language record_id id record_name name record_version version record_description description record_required_apis required_apis} {
        _scriptLibraryHostSetValue $window $context $role [dict get $metadata $field]
    }
    foreach role {record_scope record_language record_id} {uiFieldComponentEnabled [_scriptLibraryHostWidget $context $role] field [expr {$active && !$existing}]}
    foreach role {record_id record_name record_version record_description record_required_apis} {uiFieldComponentEnabled [_scriptLibraryHostWidget $context $role] field [expr {$active && ($role ne {record_id} || !$existing)}]}
}
proc ::GX::_scriptLibraryHostDirty {key context} {
    set record [_scriptLibraryHostGet $key]
    if {[dict get $record baseline] eq {}} {return 0}
    if {[_scriptLibraryHostMetadata $context 0] ne [dict get $record metadata_baseline]} {return 1}
    if {[sourceSurfaceGet [dict get $record parameter_text]] ne [dict get $record parameter_baseline]} {return 1}
    dict for {relative source} [dict get $record sources] {
        if {[sourceSurfaceGet [dict get $source text]] ne [dict get $source baseline]} {return 1}
    }
    return 0
}
proc ::GX::_scriptLibraryHostSession {record context} {
    if {[dict get $record baseline] eq {} || [dict get $record baseline scope] ne {session}} return
    if {[dict get $context session_token] eq {} || [dict get $record session_token] ne [dict get $context session_token]} {error {Session changed; the source draft is retained. Reopen its original context before saving}}
}
proc ::GX::_scriptLibraryHostBoundRequest {record context request {allowNew 0}} {
    _scriptLibraryHostSession $record $context
    set baseline [dict get $record baseline]
    if {$baseline eq {}} {error {Choose a Script or create a draft first}}
    set reference [dict get $record selected]
    if {$reference eq {}} {
        if {!$allowNew || [dict get $request expected_revision]!=0 || [dict get $request expected_sha256] ne {} || [dict get $request draft_token] ne [dict get $record draft_token]} {error {The new draft identity differs}}
        return $baseline
    }
    if {[dict get $request expected_revision] ne [dict get $baseline revision] || [dict get $request expected_sha256] ne [dict get $baseline sha256]} {error {The request does not match the bound draft baseline}}
    if {[dict exists $request reference] && [dict get $request reference] ne $reference} {error {The requested Script differs from the bound draft}}
    if {[dict exists $request draft_token] && [dict get $request draft_token] ne [dict get $record draft_token]} {error {The bound source draft changed}}
    return $baseline
}
proc ::GX::_scriptLibraryHostCAS {record context request {allowNew 0}} {
    set baseline [_scriptLibraryHostBoundRequest $record $context $request $allowNew]
    set reference [dict get $record selected]
    if {$reference eq {}} {return $baseline}
    set current [scriptRegistryDescribe $reference]
    if {[dict get $current revision] ne [dict get $baseline revision] || [dict get $current sha256] ne [dict get $baseline sha256]} {error {Registered Script metadata/source changed; the unsaved draft is retained. Review or reload explicitly}}
    if {![dict exists $baseline record_sha256] || ![regexp {^[a-f0-9]{64}$} [dict get $baseline record_sha256]] || ![dict exists $current record_sha256]} {error {Full-record Registry CAS is unavailable; the source draft is retained}}
    if {[dict get $current record_sha256] ne [dict get $baseline record_sha256]} {error {Registered record identity changed; the unsaved draft is retained}}
    if {![dict exists $baseline owner_context] || ![dict exists $current owner_context]} {error {Registry namespace comparison is unavailable; reopen/review before canonical writes}}
    if {[dict get $current owner_context] ne [dict get $baseline owner_context]} {error {User/Session Registry root changed; the original local draft is retained}}
    return $current
}
proc ::GX::_scriptLibraryHostClearSources {key} {
    set record [_scriptLibraryHostGet $key]
    dict for {relative source} [dict get $record sources] {if {[winfo exists [dict get $source frame]]} {destroy [dict get $source frame]}}
    dict set record sources {};dict set record active_file {};dict set record selected_relative_file {}
    _scriptLibraryHostPut $key $record
}
proc ::GX::_scriptLibraryHostRoster {metadata} {
    if {[dict get $metadata kind] eq {project}} {return [dict get $metadata project_files]}
    return [dict create [scriptRegistrySourceName [dict get $metadata language]] [dict create sha256 [dict get $metadata sha256]]]
}
proc ::GX::_scriptLibraryHostReadCurrent {record context {current {}}} {
    _scriptLibraryHostSession $record $context
    set reference [dict get $record selected];set baseline [dict get $record baseline]
    if {![dict exists $record source_read_admissions $reference]} {error {This file was not captured in the restored snapshot. Reload the registered source to review its current namespace before reading an uncaptured file}}
    set pins [dict get $record source_read_admissions $reference]
    foreach {expected field} {expected_revision revision expected_sha256 sha256 expected_record_sha256 record_sha256} {
        if {![dict exists $baseline $field] || [dict get $pins $expected] ne [dict get $baseline $field]} {error {The restored Project differs from its live read admission; local sources are retained}}
    }
    if {$current eq {}} {set current [scriptRegistryDescribe $reference]}
    _scriptRegistryExpectedCheck $current $pins
    return $current
}
proc ::GX::_scriptLibraryHostFileHighlight {key} {
    if {![dict exists $::GX::ScriptLibraryHost::bindings $key]} return
    set record [_scriptLibraryHostGet $key];set tree [dict get $record tree];set active [dict get $record active_file]
    dict set record selected_relative_file $active;_scriptLibraryHostPut $key $record
    if {![winfo exists $tree] || [winfo id [winfo parent $tree]] ne [lindex [dict get $record identity] 3]} return
    set row {};dict for {id relative} [dict get $record file_rows] {if {$relative eq $active} {set row $id;break}}
    if {$row eq {}} {$tree selection remove [$tree selection]
    } else {if {[$tree selection] ne [list $row]} {$tree selection set $row};$tree focus $row;$tree see $row}
}
proc ::GX::_scriptLibraryHostFile {window form key context relative {initial {}} {prefetched 0}} {
    set record [_scriptLibraryHostGet $key];set baseline [dict get $record baseline]
    if {![dict exists $record roster $relative]} {error {Source file is outside the actual registered Project roster}}
    if {![dict exists $record sources $relative]} {
        set reference [dict get $record selected]
        if {$reference ne {} && !$prefetched} {
            _scriptLibraryHostReadCurrent $record $context
            set source [scriptSourceNoteOwner read_local [dict create reference $reference relative $relative expected_source_sha256 [dict get $record roster $relative sha256]]]
            set initial [dict get $source source]
            set context [_scriptLibraryHostGuard $window $form source_select]
            _scriptLibraryHostReadCurrent $record $context
        }
        set frame [dict get $record source_host].file[incr ::GX::ScriptLibraryHost::serial]
        try {
            set text [sourceSurfaceCreate $frame [dict create mode editable language [string tolower [dict get $baseline language]] find_bar 1 find_bar_visible 0 change_command [list ::GX::_scriptLibraryHostChanged $window $form]]]
            sourceSurfaceSet $text $initial
        } on error {message options} {if {[winfo exists $frame]} {destroy $frame};return -options $options $message}
        sourceSurfaceDocumentIdentity $text [list [dict get $record selected] $relative [dict get $baseline sha256]]
        bind $text <FocusIn> +[list ::GX::_scriptLibraryHostRememberFocus $key $text]
        dict set record sources $relative [dict create frame $frame text $text baseline $initial]
    }
    dict for {name source} [dict get $record sources] {pack forget [dict get $source frame]}
    pack [dict get $record sources $relative frame] -fill both -expand 1
    if {[dict exists $::GX::ScientificHistory::viewers $window] && [dict get $::GX::ScientificHistory::viewers $window browsing]} {sourceSurfaceConfigure [dict get $record sources $relative text] {mode read_only}}
    dict set record active_file $relative;dict set record selected_relative_file $relative
    _scriptLibraryHostPut $key $record
    return [dict get $record sources $relative text]
}
proc ::GX::_scriptLibraryHostBind {window form key context metadata reference {code {}}} {
    # Admit the new saved source before discarding any previous local editor.
    # A too-large/malformed/stale selected record keeps the prior valid draft.
    set originalSession [dict get $context session_token]
    if {$reference ne {}} {
        set roster [_scriptLibraryHostRoster $metadata]
        set relative [expr {[dict get $metadata kind] eq {project}?[dict get $metadata entrypoint]:[lindex [dict keys $roster] 0]}]
        set read [scriptSourceNoteOwner read_local [dict create reference $reference relative $relative expected_source_sha256 [dict get $roster $relative sha256]]]
        set code [dict get $read source]
        set context [_scriptLibraryHostGuard $window $form source_select]
        if {[dict get $metadata scope] eq {session} && ($originalSession eq {} || $originalSession ne [dict get $context session_token])} {error {Session changed before source adoption}}
        set current [scriptRegistryDescribe $reference]
        if {[dict get $current revision] ne [dict get $metadata revision] || [dict get $current sha256] ne [dict get $metadata sha256]} {error {Registered source changed before editor adoption}}
        foreach field {record_sha256 owner_context} {
            if {[dict exists $metadata $field] && (![dict exists $current $field] || [dict get $metadata $field] ne [dict get $current $field])} {error {Registered record/namespace changed before source adoption}}
        }
    }
    set previous [_scriptLibraryHostGet $key];set record $previous
    dict set record baseline $metadata;dict set record selected $reference
    if {$reference ne {}} {
        # Live read admission stays in this window only. Portable snapshots
        # never serialize it or regain canonical write authority.
        set admissions [datasetPublicationV2DictDefault $record source_read_admissions {}]
        if {[dict exists $admissions $reference]} {dict unset admissions $reference}
        dict set admissions $reference [_scriptLibraryHostExpected $metadata]
        while {[dict size $admissions]>64} {dict unset admissions [lindex [dict keys $admissions] 0]}
        dict set record source_read_admissions $admissions
    }
    dict set record session_token [expr {[dict get $metadata scope] eq {session}?[dict get $context session_token]:{}}]
    dict set record draft_token "script-library-draft-[pid]-[incr ::GX::ScriptLibraryHost::serial]-[clock clicks]"
    dict set record parameter_definitions [dict get $metadata parameters]
    set parameters [scriptParameterDefinitionsFormat [dict get $metadata parameters]]
    dict set record parameter_baseline $parameters
    dict set record metadata_baseline [_scriptLibraryHostMetadataProjection $metadata]
    if {$reference eq {}} {
        set relative [scriptRegistrySourceName [dict get $metadata language]]
        dict set record roster [dict create $relative [dict create sha256 {}]]
    } else {dict set record roster [_scriptLibraryHostRoster $metadata]}
    set active [expr {[dict get $metadata kind] eq {project}?[dict get $metadata entrypoint]:[lindex [dict keys [dict get $record roster]] 0]}]
    set fileRows {};set treeRows {};set index 0
    dict for {relative file} [dict get $record roster] {
        set row f[incr index];dict set fileRows $row $relative
        set role [expr {[dict get $metadata kind] eq {project} && $relative eq [dict get $metadata entrypoint]?{entrypoint}:{source}}]
        lappend treeRows [list $row $relative $role [dict get $file sha256]]
    }
    dict set record file_rows $fileRows
    set description [_scriptLibraryHostIdentityText $metadata $reference]
    set frame [dict get $record source_host].file[incr ::GX::ScriptLibraryHost::serial]
    set oldFields [_scriptLibraryHostMetadata $context 0]
    try {
        set text [sourceSurfaceCreate $frame [dict create mode editable language [string tolower [dict get $metadata language]] find_bar 1 find_bar_visible 0 change_command [list ::GX::_scriptLibraryHostChanged $window $form]]]
        sourceSurfaceSet $text $code
        sourceSurfaceDocumentIdentity $text [list $reference $active [dict get $metadata sha256]]
        set context [_scriptLibraryHostGuard $window $form source_select]
        if {[dict get $metadata scope] eq {session} && ($originalSession eq {} || $originalSession ne [dict get $context session_token])} {error {Session changed before source adoption}}
        _scriptLibraryHostRenderMetadata $window $context $metadata [expr {$reference ne {}}]
        viewerGuiDesignTextSet $window [dict get $context component_ids record_identity] $description
    } on error {message options} {
        if {[winfo exists $frame]} {destroy $frame}
        if {[winfo exists $window]} {catch {_scriptLibraryHostRenderMetadata $window $context $oldFields [expr {[dict get $previous selected] ne {}}]}}
        return -options $options $message
    }
    sourceSurfaceConfigure [dict get $record parameter_text] {mode editable}
    sourceSurfaceSet [dict get $record parameter_text] $parameters
    set tree [dict get $record tree];$tree delete [$tree children {}]
    foreach row $treeRows {lassign $row id relative role hash;$tree insert {} end -id $id -text $relative -values [list $role $hash]}
    bind $text <FocusIn> +[list ::GX::_scriptLibraryHostRememberFocus $key $text]
    dict set record sources [dict create $active [dict create frame $frame text $text baseline $code]]
    dict set record active_file $active;dict set record selected_relative_file $active
    _scriptLibraryHostPut $key $record
    dict for {relative source} [dict get $previous sources] {if {[winfo exists [dict get $source frame]]} {destroy [dict get $source frame]}}
    pack $frame -fill both -expand 1
    if {$reference eq {}} {
        set recordsTree [uiFieldComponentTableWidget [_scriptLibraryHostWidget $context records]]
        $recordsTree selection remove [$recordsTree selection]
    }
}
proc ::GX::_scriptLibraryHostReview {window form key context} {
    if {![_scriptLibraryHostDirty $key $context]} {return 1}
    set answer [tk_messageBox -parent $window -title {Unsaved Script Library draft} -type yesnocancel -default cancel -icon question -message {Save the changed source, metadata and parameter draft before continuing? No discards this local draft only.}]
    set context [_scriptLibraryHostGuard $window $form review]
    if {$answer eq {cancel}} {return 0}
    if {$answer eq {yes}} {
        set record [_scriptLibraryHostGet $key];set baseline [dict get $record baseline]
        _scriptLibraryHostSave $window $form $key $context [dict create draft_token [dict get $record draft_token] expected_revision [dict get $baseline revision] expected_sha256 [dict get $baseline sha256]]
    }
    return 1
}
proc ::GX::_scriptLibraryHostOwnerReviewEligible {record metadata reference} {
    set baseline [dict get $record baseline]
    if {$baseline eq {} || [dict get $record selected] ne $reference || [dict exists $baseline owner_context]} {return 0}
    # Only the exact saved logical baseline may be reviewed against a current
    # owner. Stale or altered source/metadata is never guessed forward.
    foreach field [concat [dict keys [scriptRegistryDefaults]] record_sha256] {
        if {![dict exists $baseline $field] || ![dict exists $metadata $field] || [dict get $baseline $field] ne [dict get $metadata $field]} {return 0}
    }
    set roster [_scriptLibraryHostRoster $metadata]
    if {[dict size $roster]!=[dict size [dict get $record roster]]} {return 0}
    dict for {relative file} [dict get $record roster] {
        if {![dict exists $roster $relative sha256] || [dict get $file sha256] ne [dict get $roster $relative sha256]} {return 0}
    }
    return 1
}
proc ::GX::_scriptLibraryHostOwnerQuestion {window message} {
    variable ::GX::ScriptLibraryHost::answers
    set serial [incr ::GX::ScriptLibraryHost::serial];set dialog $window.scriptLibraryOwner$serial
    uiFieldDialogCreate $dialog $window {Review restored Script owner} 760x480
    text $dialog.text -wrap word -font TkTextFont -width 1 -height 1 -undo 0 -exportselection 0
    ttk::scrollbar $dialog.scroll -command [list $dialog.text yview]
    $dialog.text configure -yscrollcommand [list $dialog.scroll set]
    ttk::frame $dialog.actions
    foreach {answer label} {yes {Authorize this owner} no {Keep draft unbound}} {
        ttk::button $dialog.actions.$answer -text $label -command [list ::GX::_scriptLibraryHostOwnerAnswer $dialog $serial $answer]
        pack $dialog.actions.$answer -side left -padx 4 -pady 6
    }
    grid $dialog.text -row 0 -column 0 -sticky nsew;grid $dialog.scroll -row 0 -column 1 -sticky ns
    grid $dialog.actions -row 1 -column 0 -columnspan 2 -sticky ew
    grid rowconfigure $dialog 0 -weight 1;grid columnconfigure $dialog 0 -weight 1
    $dialog.text insert 1.0 $message;$dialog.text configure -state disabled
    uiTextEditingAttach $dialog [list $dialog.text]
    bind $dialog <Destroy> +[list ::GX::_scriptLibraryHostIdDestroyed $dialog $serial %W]
    foreach answer {yes no} {bind $dialog.actions.$answer <Return> "[list $dialog.actions.$answer invoke];break"}
    uiFieldDialogPresent $dialog $dialog.actions.no 1
    after idle [list ::GX::uiFieldWindowFit $dialog]
    vwait ::GX::ScriptLibraryHost::answers($serial)
    set result $answers($serial);unset answers($serial)
    return $result
}
proc ::GX::_scriptLibraryHostOwnerAnswer {dialog serial answer} {
    set ::GX::ScriptLibraryHost::answers($serial) $answer
    uiFieldDialogClose $dialog
}
proc ::GX::_scriptLibraryHostOwnerReview {window form key context metadata reference} {
    set record [_scriptLibraryHostGet $key]
    if {![_scriptLibraryHostOwnerReviewEligible $record $metadata $reference]} {error {Restored source does not match the current registered baseline; the local draft is retained}}
    set expected [_scriptLibraryHostExpected $metadata]
    set session [dict get $context session_token]
    set root [file normalize [scriptRegistryRoot [dict get $metadata scope]]]
    set message [format {Authorize this restored local draft to use the current registered owner?

Record: %s
Name: %s
Revision: %s
Current Registry root: %s
Source SHA-256: %s
Full record SHA-256: %s

The saved baseline matches this current record. Yes authorizes a later explicit Save against this owner. This review does not save, discard or replace source, parameters or Undo. No retains the draft without write authorization.} $reference [dict get $metadata name] [dict get $metadata revision] $root [dict get $metadata sha256] [dict get $metadata record_sha256]]
    set answer [_scriptLibraryHostOwnerQuestion $window $message]
    set context [_scriptLibraryHostGuard $window $form select]
    if {$answer ne {yes}} {return 0}
    set current [_scriptLibraryHostGet $key]
    if {[dict get $context session_token] ne $session || [dict get $current identity] ne [dict get $record identity] || [dict get $current draft_token] ne [dict get $record draft_token] || [dict get $current baseline] ne [dict get $record baseline]} {error {Script draft or Session changed during owner review; the original draft is retained}}
    set check [scriptRegistryDescribe $reference]
    _scriptRegistryExpectedCheck $check $expected
    if {![_scriptLibraryHostOwnerReviewEligible $current $check $reference]} {error {Registered baseline changed during owner review; the local draft is retained}}
    # Authority is admitted by this actual mutating native selection and the
    # explicit host review, never by deserializing a Workspace/History body.
    # Keep every editor/widget/buffer and its Undo unchanged.
    dict set current baseline $check
    dict set current source_read_admissions $reference [_scriptLibraryHostExpected $check]
    while {[dict size [dict get $current source_read_admissions]]>64} {dict unset current source_read_admissions [lindex [dict keys [dict get $current source_read_admissions]] 0]}
    _scriptLibraryHostPut $key $current
    _scriptLibraryHostStatus $window $context {Current registered owner reviewed. The local draft is unchanged; Save remains a separate action.}
    return 1
}
proc ::GX::_scriptLibraryHostSave {window form key context request} {
    set context [_scriptLibraryHostGuard $window $form save]
    set record [_scriptLibraryHostGet $key];set baseline [_scriptLibraryHostCAS $record $context $request 1]
    set submittedFields [_scriptLibraryHostMetadata $context 0]
    set fields [_scriptLibraryHostMetadata $context]
    if {[dict get $fields scope] eq {session} && [dict get $context session_token] eq {}} {error {Open a Session before saving a Session script}}
    if {[dict get $record selected] ne {}} {
        foreach immutable {scope id language} {if {[dict get $fields $immutable] ne [dict get $baseline $immutable]} {error "Registered $immutable is immutable"}}
    }
    set options [dict create language [dict get $fields language] version [dict get $fields version] description [dict get $fields description] required_apis [dict get $fields required_apis] \
        parameters [scriptParameterDefinitionsParse [sourceSurfaceGet [dict get $record parameter_text]] [dict get $record parameter_definitions]]]
    if {[dict get $record selected] ne {}} {dict set options expected_record_sha256 [dict get $baseline record_sha256];dict set options expected_owner_context [dict get $baseline owner_context]}
    set submittedSources {};dict for {relative source} [dict get $record sources] {dict set submittedSources $relative [sourceSurfaceGet [dict get $source text]]}
    set submittedParameters [sourceSurfaceGet [dict get $record parameter_text]]
    set sourceBytes 0
    dict for {relative text} $submittedSources {
        set size [string length [encoding convertto utf-8 $text]]
        if {$size>4194304} {error {Source draft exceeds the maintained 4 MiB per-file boundary}}
        incr sourceBytes $size
    }
    if {$sourceBytes>16777216 || [string length [encoding convertto utf-8 $submittedParameters]]>1048576} {error {Source/parameter draft exceeds its bounded owner transport}}
    set context [_scriptLibraryHostGuard $window $form save]
    _scriptLibraryHostCAS $record $context $request 1
    if {[dict get $baseline kind] eq {project}} {
        set files [scriptRegistryProjectFiles $baseline]
        dict for {relative source} $submittedSources {dict set files $relative $source}
        _scriptLibraryHostCAS $record [_scriptLibraryHostGuard $window $form save] $request
        dict set options name [dict get $fields name];dict set options expected_revision [dict get $baseline revision]
        set saved [scriptRegistryProjectUpdate [dict get $baseline scope] [dict get $baseline id] [dict get $baseline sha256] $options [dict get $baseline entrypoint] $files]
    } else {
        set code [dict get $submittedSources [dict get $record active_file]]
        if {[dict get $record selected] eq {}} {
            set saved [scriptRegistrySave [dict get $fields scope] [dict get $fields id] [dict get $fields name] $code $options]
        } else {
            dict set options name [dict get $fields name];dict set options expected_revision [dict get $baseline revision]
            set saved [scriptRegistryUpdate [dict get $baseline scope] [dict get $baseline id] [dict get $baseline sha256] $options $code]
        }
    }
    set reference "[dict get $saved scope]:[dict get $saved id]"
    # Bind the exact returned commit, never a newer Registry Describe baseline.
    # Retain existing SourceSurface widgets and Undo; only accepted submitted
    # text becomes the source baseline.
    dict set record baseline $saved;dict set record selected $reference
    # Our successful guarded Save admits exactly its returned commit for later
    # uncaptured-file reads. Never consult/adopt a newer Registry revision here.
    dict set record source_read_admissions $reference [_scriptLibraryHostExpected $saved]
    while {[dict size [dict get $record source_read_admissions]]>64} {dict unset record source_read_admissions [lindex [dict keys [dict get $record source_read_admissions]] 0]}
    dict set record session_token [expr {[dict get $saved scope] eq {session}?[dict get $context session_token]:{}}]
    dict set record metadata_baseline [_scriptLibraryHostMetadataProjection $saved]
    dict set record parameter_definitions [dict get $saved parameters]
    set formatted [scriptParameterDefinitionsFormat [dict get $saved parameters]]
    dict set record parameter_baseline $formatted
    if {[sourceSurfaceGet [dict get $record parameter_text]] eq $submittedParameters && $formatted ne $submittedParameters} {sourceSurfaceReplace [dict get $record parameter_text] $formatted}
    dict for {relative source} $submittedSources {dict set record sources $relative baseline $source}
    dict set record roster [_scriptLibraryHostRoster $saved]
    _scriptLibraryHostPut $key $record
    if {[_scriptLibraryHostMetadata $context 0] eq $submittedFields} {_scriptLibraryHostRenderMetadata $window $context $saved 1}
    foreach role {record_scope record_language record_id} {uiFieldComponentEnabled [_scriptLibraryHostWidget $context $role] field 0}
    # Identity consultation stays in the actual existing log, never the native
    # result/view or a new frontend. An inventory failure cannot undo a commit.
    if {![catch {_scriptLibraryHostIdentityText $saved $reference} identity]} {viewerGuiDesignTextSet $window [dict get $context component_ids record_identity] $identity}
    _scriptLibraryHostRefreshBound $window $key $context
    _scriptLibraryHostStatus $window $context "Saved $reference · revision [dict get $saved revision]"
    return $saved
}
proc ::GX::_scriptLibraryHostHighlight {record context {reveal 0}} {
    set tree [uiFieldComponentTableWidget [_scriptLibraryHostWidget $context records]]
    set selectedRow {}
    dict for {row reference} [dict get $record row_references] {if {$reference eq [dict get $record selected]} {set selectedRow $row;break}}
    if {$selectedRow eq {}} {$tree selection remove [$tree selection]
    } else {$tree selection set $selectedRow;if {$reveal} {$tree see $selectedRow}}
}
proc ::GX::_scriptLibraryHostList {window key context request {reveal 0}} {
    set scope [dict get $request scope];set language [dict get $request language];set query [dict get $request query]
    set offset [dict get $request offset];set limit [dict get $request limit]
    if {$scope ni {all user session} || $language ni {all python octave} || [string length $query]>256 || [string length [encoding convertto utf-8 $query]]>1024 ||
        ![string is wideinteger -strict $offset] || $offset<0 || ![string is integer -strict $limit] || $limit<1 || $limit>100} {error {Invalid bounded Script Library query}}
    if {$scope eq {session} && [dict get $context session_token] eq {}} {error {Open a Session to browse Session scripts}}
    set matches {};set referencePins {};set needle [string tolower $query]
    foreach metadata [scriptRegistryList $scope] {
        if {$language ne {all} && [string tolower [dict get $metadata language]] ne $language} continue
        set reference "[dict get $metadata scope]:[dict get $metadata id]"
        if {$needle ne {} && [string first $needle [string tolower "$reference [dict get $metadata language] [dict get $metadata name] [dict get $metadata description]"]]<0} continue
        dict set referencePins $reference [_scriptLibraryHostExpected $metadata]
        set item [dict create reference $reference]
        foreach field {scope language kind id name version revision sha256} {dict set item $field [dict get $metadata $field]}
        dict set item language [string tolower [dict get $item language]]
        lappend matches $item
    }
    if {$reveal} {
        set selected [dict get [_scriptLibraryHostGet $key] selected];set index 0
        foreach item $matches {
            if {[dict get $item reference] eq $selected} {set offset [expr {($index/$limit)*$limit}];break}
            incr index
        }
    }
    set total [llength $matches];if {$offset>$total} {set offset [expr {max(0,$total-$limit)}]}
    set page [lrange $matches $offset [expr {$offset+$limit-1}]]
    set shape {array {record {reference text scope text language text kind text id text name text version text revision int sha256 text}}}
    if {[string length [encoding convertto utf-8 [nativeWorkspaceJsonEncode [nativeWorkspaceEncode $shape $page]]]]>45056} {error {Narrow the query/page: complete Script identities exceed the 48 KiB receipt budget}}
    set rows {};foreach item $page {lappend rows [list [dict get $item name] [dict get $item scope] [dict get $item language] [dict get $item kind] [dict get $item id] [dict get $item version]]}
    viewerGuiDesignTableSet $window [dict get $context component_ids records] $rows
    set tree [uiFieldComponentTableWidget [_scriptLibraryHostWidget $context records]]
    set record [_scriptLibraryHostGet $key];set rowMap {};set index 0
    foreach row [$tree children {}] item $page {dict set rowMap $row [dict get $item reference];incr index}
    # Table row indexes are presentation only. Select by the bound stable
    # reference, never an old positional highlight after import/save/refresh.
    _scriptLibraryHostHighlight [dict replace $record row_references $rowMap] $context $reveal
    set pagePins {};foreach item $page {set reference [dict get $item reference];dict set pagePins $reference [dict get $referencePins $reference]}
    dict set record inventory_pins $pagePins
    dict set record row_references $rowMap
    dict set record inventory [dict create offset $offset limit $limit total $total records $page]
    dict set record filters [dict create scope $scope language $language query $query]
    _scriptLibraryHostPut $key $record
    foreach {role field} {scope_filter scope language_filter language search_query query} {_scriptLibraryHostSetValue $window $context $role [dict get $request $field]}
    _scriptLibraryHostStatus $window $context "[llength $page] of $total registered Scripts · source drafts retained"
}
proc ::GX::_scriptLibraryHostRefreshBound {window key context} {
    set record [_scriptLibraryHostGet $key]
    set request [dict merge [dict get $record filters] [dict create offset [dict get $record inventory offset] limit [dict get $record inventory limit]]]
    _scriptLibraryHostList $window $key $context $request 1
}

proc ::GX::_scriptLibraryHostView {key context} {
    set record [_scriptLibraryHostGet $key];set baseline [dict get $record baseline]
    set selected {};set draft {};set valid 1;set conflict {};set current {}
    if {$baseline ne {}} {
        set selected [dict create reference [dict get $record selected] revision [dict get $baseline revision] sha256 [dict get $baseline sha256] draft_token [dict get $record draft_token]]
        set draft [dict create scope [dict get $baseline scope] language [string tolower [dict get $baseline language]] dirty [_scriptLibraryHostDirty $key $context]]
        if {[catch {
            _scriptLibraryHostSession $record $context
            if {[dict get $record selected] ne {}} {
                set current [scriptRegistryDescribe [dict get $record selected]]
                if {[dict get $current revision] ne [dict get $baseline revision] || [dict get $current sha256] ne [dict get $baseline sha256]} {error {Registered source or metadata changed. The bound baseline and unsaved draft are retained; reload explicitly}}
                if {![dict exists $baseline record_sha256] || ![dict exists $current record_sha256]} {error {Full-record Registry CAS is unavailable; source remains inspectable}}
                if {[dict get $current record_sha256] ne [dict get $baseline record_sha256]} {error {Registered record identity changed; source draft and original baseline are retained}}
                if {![dict exists $baseline owner_context] || ![dict exists $current owner_context] || [dict get $current owner_context] ne [dict get $baseline owner_context]} {error {Registry namespace changed or requires an explicit restore review; local sources are retained}}
            }
        } message]} {set valid 0;set conflict $message}
    }
    set selectedRow {};set tree [uiFieldComponentTableWidget [_scriptLibraryHostWidget $context records]]
    set selection [$tree selection]
    if {[llength $selection]==1 && [dict exists $record row_references [lindex $selection 0]]} {set selectedRow [dict get $record row_references [lindex $selection 0]]}
    set relative [datasetPublicationV2DictDefault $record selected_relative_file {}]
    set readValid 0;set readError {Choose an actual Project source file first}
    if {$baseline ne {} && [dict exists $record roster $relative]} {
        if {[dict exists $record sources $relative]} {set readValid 1;set readError {}
        } elseif {![catch {_scriptLibraryHostReadCurrent $record $context $current} readError]} {set readValid 1;set readError {}}
    }
    return [dict create selected $selected inventory [dict get $record inventory] draft $draft selected_row_reference $selectedRow selected_relative_file $relative selection_valid $valid conflict_message $conflict source_read_valid $readValid source_read_error $readError]
}
proc ::GX::viewerGuiScriptLibrarySnapshot {window form} {
    set context [_scriptLibraryHostGuard $window $form snapshot]
    set key [_scriptLibraryHostEnsure $window $form $context]
    _scriptLibraryHostNewLanguage $window $key $context
    return [_scriptLibraryHostView $key $context]
}
proc ::GX::_scriptLibraryHostRequest {operation request} {
    if {[catch {dict size $request}]} {error {Script Library request must be an object}}
    set fields [dict get {
        list {scope language query offset limit} select {reference expected_revision expected_sha256 review_owner}
        new_script {scope language} new_project {scope language}
        source_select {reference relative_file expected_revision expected_sha256 expected_file_sha256}
        save {draft_token expected_revision expected_sha256}
        copy_record {reference expected_revision expected_sha256} assign_session {reference expected_revision expected_sha256}
        open_workspace {reference expected_revision expected_sha256} run_review {reference expected_revision expected_sha256}
        import_script {scope} import_project {scope} export {reference expected_revision expected_sha256}
        delete {reference expected_revision expected_sha256} jobs {} refresh {} close {}
        undo {} redo {} find {} replace {} cut {} copy_text {} paste {} select_all {}
    } $operation]
    foreach field [dict keys $request] {if {$field ni $fields} {error "Unknown Script Library request field '$field'"}}
    foreach field $fields {if {$field ni {expected_file_sha256 review_owner} && ![dict exists $request $field]} {error "Missing Script Library request field '$field'"}}
    if {[dict exists $request review_owner] && ![string is boolean -strict [dict get $request review_owner]]} {error {Owner review requires an exact Boolean flag}}
    foreach field {expected_revision offset limit} {if {[dict exists $request $field] && (![string is wideinteger -strict [dict get $request $field]] || [dict get $request $field]<0)} {error {Exact nonnegative integer request identity required}}}
    foreach field {expected_sha256 expected_file_sha256} {
        if {[dict exists $request $field]} {
            set hash [dict get $request $field]
            if {$hash ne {} && ![regexp {^[a-f0-9]{64}$} $hash]} {error {Exact lowercase source SHA-256 required}}
        }
    }
    return $request
}
proc ::GX::_scriptLibraryHostId {window form} {
    variable ::GX::ScriptLibraryHost::answers
    set serial [incr ::GX::ScriptLibraryHost::serial];set dialog $window.scriptLibraryId$serial
    uiFieldDialogCreate $dialog $window {New registered Script ID}
    ttk::label $dialog.label -text {Stable new ID (letters, digits, underscore, dot and hyphen):} -wraplength 420
    ttk::entry $dialog.value -width 36
    ttk::label $dialog.status -wraplength 420
    ttk::button $dialog.ok -text Continue -command [list ::GX::_scriptLibraryHostIdAccept $dialog $serial]
    ttk::button $dialog.cancel -text Cancel -command [list ::GX::uiFieldDialogClose $dialog]
    pack $dialog.label $dialog.value $dialog.status $dialog.ok $dialog.cancel -fill x -padx 10 -pady 5
    uiTextEditingAttach $dialog [list $dialog.value]
    bind $dialog <Destroy> +[list ::GX::_scriptLibraryHostIdDestroyed $dialog $serial %W]
    uiFieldDialogPresent $dialog $dialog.value 1
    vwait ::GX::ScriptLibraryHost::answers($serial)
    set result $answers($serial);unset answers($serial)
    _scriptLibraryHostGuard $window $form id_review
    return $result
}
proc ::GX::_scriptLibraryHostIdAccept {dialog serial} {
    if {[catch {set id [scriptRegistryId [$dialog.value get]]} message]} {$dialog.status configure -text $message;return}
    set ::GX::ScriptLibraryHost::answers($serial) $id
    uiFieldDialogClose $dialog
}
proc ::GX::_scriptLibraryHostIdDestroyed {dialog serial actual} {
    if {$dialog eq $actual && ![info exists ::GX::ScriptLibraryHost::answers($serial)]} {set ::GX::ScriptLibraryHost::answers($serial) {}}
}
proc ::GX::_scriptLibraryHostWorkspace {window form context metadata mode} {
    set language [dict get $metadata language]
    modulePublicApiActivate [scriptAnalysisModule $language] [string toupper $language]_SCRIPT_EDITOR_API_v1
    ::GX::${language}ScriptEditor::_ensureUi
    ::GX::${language}ScriptEditorUI::open
    _scriptLibraryHostGuard $window $form [expr {$mode eq {new}?{new_project}:{open_workspace}}]
    if {$mode eq {new}} {
        _scriptLibraryHostCorrectedOwner ::GX::scriptProjectCanvasShow options
        scriptProjectCanvasShow ::GX::${language}ScriptEditorUI $language new [dict create scope [dict get $metadata scope]]
        return pending
    }
    if {![::GX::${language}ScriptEditorUI::_loadDocument "[dict get $metadata scope]:[dict get $metadata id]"]} {return cancelled}
    return completed
}
proc ::GX::_scriptLibraryHostEdit {window key operation} {
    if {$operation in {undo redo cut paste select_all copy_text}} {return [uiTextEdit $window [expr {$operation eq {copy_text}?{copy}:$operation}]]}
    set target [uiTextEditTarget $window]
    if {$target eq {} || [winfo class $target] ne {Text}} {error {Focus a Source or Parameters editor first}}
    set record [_scriptLibraryHostGet $key];set owned [list [dict get $record parameter_text]]
    dict for {relative source} [dict get $record sources] {lappend owned [dict get $source text]}
    if {$target ni $owned} {error {Choose this Library's maintained source editor}}
    set surface [sourceSurfaceParent $target]
    if {![winfo exists $surface.find.query]} {error {Source search controls are unavailable}}
    if {$operation eq {replace}} {
        sourceSurfaceConfigure $target {mode editable}
        sourceSurfaceFindShow $target replace
    } else {sourceSurfaceFindShow $target find}
    return 1
}
proc ::GX::viewerGuiScriptLibraryCommand {window form operation request} {
    set context [_scriptLibraryHostGuard $window $form $operation]
    _viewerGuiScriptLibraryHistoryFlush $window
    set request [_scriptLibraryHostRequest $operation $request]
    set key [_scriptLibraryHostEnsure $window $form $context]
    _scriptLibraryHostNewLanguage $window $key $context
    set record [_scriptLibraryHostGet $key]
    if {[dict get $record busy]} {error {Complete or cancel the current Script Library review first}}
    dict set record busy 1;_scriptLibraryHostPut $key $record
    set status completed;set message {};set result {}
    try {
        switch -- $operation {
            list {_scriptLibraryHostList $window $key $context $request}
            refresh {_scriptLibraryHostList $window $key $context [dict merge [dict get $record filters] [dict create offset [dict get $record inventory offset] limit [dict get $record inventory limit]]]]}
            select {
                set reference [dict get $request reference]
                if {![dict exists $record inventory_pins $reference]} {error {Refresh the actual Script inventory before selecting this reference}}
                set metadata [scriptRegistryDescribe $reference]
                _scriptRegistryExpectedCheck $metadata [dict get $record inventory_pins $reference]
                if {[dict get $metadata revision] ne [dict get $request expected_revision] || [dict get $metadata sha256] ne [dict get $request expected_sha256]} {error {Inventory source changed; refresh before selecting}}
                # Freeze the actually reviewed record/namespace, not merely its
                # source bytes. A modal review may pump another Registry edit,
                # root replacement or Session switch before it returns.
                set reviewedIdentity [_scriptLibraryHostExpected $metadata]
                set reviewedSession [dict get $context session_token]
                set ownerEligible [_scriptLibraryHostOwnerReviewEligible $record $metadata $reference]
                if {[datasetPublicationV2DictDefault $request review_owner 0] && !$ownerEligible} {error {Choose the exact matching restored record for owner review; no source is saved, reloaded or discarded}}
                if {$ownerEligible} {
                    if {![_scriptLibraryHostOwnerReview $window $form $key $context $metadata $reference]} {set status cancelled}
                    _scriptLibraryHostHighlight [_scriptLibraryHostGet $key] $context
                } else {
                    set reload [expr {[dict get $record baseline] eq {} || [dict get $record selected] ne [dict get $request reference]}]
                    if {!$reload && ([dict get $record baseline revision] ne [dict get $metadata revision] || [dict get $record baseline sha256] ne [dict get $metadata sha256])} {set reload 1}
                    if {!$reload && [datasetPublicationV2DictDefault [dict get $record baseline] record_sha256 {}] ne [datasetPublicationV2DictDefault $metadata record_sha256 {}]} {set reload 1}
                    if {!$reload && [datasetPublicationV2DictDefault [dict get $record baseline] owner_context {}] ne [dict get $metadata owner_context]} {set reload 1}
                    if {$reload} {
                        if {![_scriptLibraryHostReview $window $form $key $context]} {
                            set status cancelled
                            if {![catch {set currentContext [_scriptLibraryHostGuard $window $form snapshot]}]} {_scriptLibraryHostHighlight [_scriptLibraryHostGet $key] $currentContext}
                        } else {
                            set context [_scriptLibraryHostGuard $window $form select]
                            if {[dict get $context session_token] ne $reviewedSession} {error {Session changed during selection review; the original source draft is retained}}
                            set check [scriptRegistryDescribe [dict get $request reference]]
                            if {[_scriptLibraryHostExpected $check] ne $reviewedIdentity} {error {Script source, record or Registry namespace changed during selection review; the original source draft is retained}}
                            _scriptLibraryHostBind $window $form $key $context $check [dict get $request reference]
                            # Saving the previous draft may have rebuilt its page
                            # and queued a selection notification. Reveal the
                            # actually requested new record before that notification.
                            _scriptLibraryHostRefreshBound $window $key $context
                        }
                    }
                }
            }
            new_script {
                if {[dict get $request scope] ni {user session} || [dict get $request language] ni {python octave}} {error {Choose a supported Script scope/language}}
                if {[dict get $request scope] eq {session} && [dict get $context session_token] eq {}} {error {Open a Session before creating a Session script}}
                if {![_scriptLibraryHostReview $window $form $key $context]} {set status cancelled
                } else {
                    set context [_scriptLibraryHostGuard $window $form new_script]
                    set language [expr {[dict get $request language] eq {python}?{Python}:{Octave}}]
                    set code [expr {$language eq {Python}?"# Registered GX-TXT Python script\nfrom gxtxt import gxtxt_context\nctx = gxtxt_context()\n":"% Registered GX-TXT Octave script\nctx = gxtxt_context();\n"}]
                    set metadata [dict merge [scriptRegistryDefaults] [dict create scope [dict get $request scope] language $language revision 0 sha256 {}]]
                    _scriptLibraryHostBind $window $form $key $context $metadata {} $code
                }
            }
            new_project {
                if {[dict get $request scope] ni {user session} || [dict get $request language] ni {python octave}} {error {Choose a supported Project scope/language}}
                if {[dict get $request scope] eq {session} && [dict get $context session_token] eq {}} {error {Open a Session before creating a Session Project}}
                if {![_scriptLibraryHostReview $window $form $key $context]} {set status cancelled
                } else {
                    set language [expr {[dict get $request language] eq {python}?{Python}:{Octave}}]
                    _scriptLibraryHostWorkspace $window $form $context [dict create language $language scope [dict get $request scope]] new
                    set status pending;set message {Project creation is open in the existing language editor; no Script identity has been fabricated}
                }
            }
            source_select {
                _scriptLibraryHostBoundRequest $record $context $request 1
                set relative [dict get $request relative_file]
                if {[dict exists $request expected_file_sha256] && (![dict exists $record roster $relative] || [dict get $record roster $relative sha256] ne [dict get $request expected_file_sha256])} {error {Project source file changed}}
                _scriptLibraryHostFile $window $form $key $context $relative
            }
            save {_scriptLibraryHostSave $window $form $key $context $request}
            open_workspace - run_review - export - copy_record - assign_session - delete {
                set metadata [_scriptLibraryHostCAS $record $context $request]
                switch -- $operation {
                    open_workspace {set status [_scriptLibraryHostWorkspace $window $form $context $metadata open]}
                    run_review {if {[dict get $context session_token] eq {}} {error {Open the intended scientific Session before reviewing a run. No Job was submitted}};scriptWorkspaceRunDialog [dict get $request reference]}
                    export {set status [_scriptLibraryHostExport $window $form $key $context $metadata $request]}
                    copy_record {set status [_scriptLibraryHostCopy $window $form $key $context $metadata $request]}
                    assign_session {set status [_scriptLibraryHostAssign $window $form $key $context $metadata $request]}
                    delete {if {![_scriptLibraryHostDelete $window $form $key $context $metadata $request]} {set status cancelled}}
                }
            }
            import_script - import_project {if {![_scriptLibraryHostImport $window $form $key $context $operation $request]} {set status cancelled}}
            jobs {scriptJobsDialog}
            close {
                _scriptLibraryHostGuard $window $form close
                # Both native Close and WM close use the one owning host review.
                set command [wm protocol $window WM_DELETE_WINDOW]
                if {$command eq {}} {error {The normal Viewer close guard is unavailable}}
                uplevel #0 $command
                if {[winfo exists $window]} {set status cancelled}
            }
            undo - redo - find - replace - cut - copy_text - paste - select_all {_scriptLibraryHostEdit $window $key $operation}
        }
        if {[winfo exists $window] && [dict exists $::GX::ScriptLibraryHost::bindings $key]} {
            set context [_scriptLibraryHostGuard $window $form snapshot]
            set result [_scriptLibraryHostView $key $context]
        }
        return [dict create status $status message $message result [expr {$status eq {cancelled}?{}:$result}]]
    } finally {
        if {[dict exists $::GX::ScriptLibraryHost::bindings $key] && [dict get $::GX::ScriptLibraryHost::bindings $key identity] eq [dict get $record identity]} {
            if {$operation eq {source_select}} {_scriptLibraryHostFileHighlight $key}
            dict set ::GX::ScriptLibraryHost::bindings $key busy 0
        }
    }
}
proc ::GX::_scriptLibraryHostExpected {metadata} {
    if {![dict exists $metadata record_sha256] || ![dict exists $metadata owner_context]} {error {Full-record/namespace Registry CAS is unavailable}}
    return [dict create expected_revision [dict get $metadata revision] expected_sha256 [dict get $metadata sha256] expected_record_sha256 [dict get $metadata record_sha256] expected_owner_context [dict get $metadata owner_context]]
}
proc ::GX::_scriptLibraryHostCorrectedOwner {command {argument {}}} {
    if {![llength [info commands $command]] || ($argument ne {} && $argument ni [info args $command])} {error {The corrected shared Script owner is not available; no operation was performed}}
}
proc ::GX::_scriptLibraryHostExport {window form key context metadata request} {
    set project [expr {[dict get $metadata kind] eq {project}}]
    if {$project} {_scriptLibraryHostCorrectedOwner ::GX::scriptRegistryProjectExport expected}
    set extension [expr {$project?{.zip}:([dict get $metadata language] eq {Python}?{.py}:{.m})}]
    set path [workspaceSaveFile manifest_dir -parent $window -title {Export saved Script snapshot} -defaultextension $extension -initialfile "[dict get $metadata id]$extension"]
    if {$path eq {}} {return cancelled}
    set context [_scriptLibraryHostGuard $window $form export]
    set record [_scriptLibraryHostGet $key];set metadata [_scriptLibraryHostCAS $record $context $request]
    if {$project} {
        # The maintained owner snapshots notes; the old editable baseline is
        # deliberately not guessed forward if that revises Registry metadata.
        set sourceActor [scriptAnalysisModule [dict get $metadata language]]
        _datasetPrivateWithModule $sourceActor [list ::GX::scriptSourceNoteSnapshotProject [dict get $request reference]]
        _scriptLibraryHostGuard $window $form export
        scriptRegistryProjectExport [dict get $request reference] $path {} [_scriptLibraryHostExpected $metadata]
    } else {filePublicationCopy [dict get $metadata source_path] $path [dict get $metadata sha256] create_only}
    _scriptLibraryHostStatus $window $context {Exported the reviewed saved source snapshot; local unsaved edits were not exported}
    return completed
}
proc ::GX::_scriptLibraryHostCopy {window form key context metadata request} {
    # Source+asset rollback belongs to the maintained Registry owner, not a
    # controller-created lock, temporary Registry, or compensating raw delete.
    _scriptLibraryHostCorrectedOwner ::GX::scriptRegistryCopySnapshot
    set id [_scriptLibraryHostId $window $form]
    if {$id eq {}} {return cancelled}
    set context [_scriptLibraryHostGuard $window $form copy_record]
    set metadata [_scriptLibraryHostCAS [_scriptLibraryHostGet $key] $context $request]
    set saved [scriptRegistryCopySnapshot [dict get $request reference] $id [_scriptLibraryHostExpected $metadata]]
    _scriptLibraryHostBind $window $form $key $context $saved "[dict get $saved scope]:[dict get $saved id]"
    _scriptLibraryHostRefreshBound $window $key $context
    _scriptLibraryHostStatus $window $context {Copied the reviewed saved Script and its SourceNote associations}
    return completed
}
proc ::GX::_scriptLibraryHostAssign {window form key context metadata request} {
    _scriptLibraryHostCorrectedOwner ::GX::scriptRegistryAssignToSession expected
    if {[dict get $metadata scope] ne {user}} {error {Select a User Script to assign to a Session}}
    if {[dict get $context session_token] eq {}} {error {Open the intended Session before assigning a Script}}
    set context [_scriptLibraryHostGuard $window $form assign_session]
    set metadata [_scriptLibraryHostCAS [_scriptLibraryHostGet $key] $context $request]
    scriptRegistryAssignToSession [dict get $metadata id] {} [_scriptLibraryHostExpected $metadata]
    _scriptLibraryHostRefreshBound $window $key $context
    _scriptLibraryHostStatus $window $context {The Session owns a saved-source snapshot with its existing SourceNote associations; User source is unchanged}
    return completed
}
proc ::GX::_scriptLibraryHostDelete {window form key context metadata request} {
    _scriptLibraryHostCorrectedOwner ::GX::resourceLifecycleDeleteScript expected
    if {[_scriptLibraryHostDirty $key $context]} {error {Save or explicitly discard the local draft before deleting a registered Script}}
    set dependencies [resourceLifecycleScriptDependencies [dict get $request reference]]
    if {[llength $dependencies]} {error "Script is in use. Detach and save these Analysis references first:\n[join $dependencies \n]"}
    set message "Delete saved [dict get $metadata scope] Script '[dict get $metadata name]'?\n\nReference: [dict get $request reference]\nLanguage: [dict get $metadata language]\nRevision: [dict get $metadata revision]\n\nOnly this Registry-owned record/source is deleted. Historical execution snapshots, provenance and external files remain."
    if {[tk_messageBox -parent $window -type yesno -default no -icon warning -title {Delete registered Script} -message $message] ne {yes}} {return 0}
    set context [_scriptLibraryHostGuard $window $form delete]
    set metadata [_scriptLibraryHostCAS [_scriptLibraryHostGet $key] $context $request]
    resourceLifecycleDeleteScript [dict get $request reference] [_scriptLibraryHostExpected $metadata]
    _scriptLibraryHostClearSources $key
    set record [_scriptLibraryHostGet $key]
    dict set record selected {};dict set record baseline {};dict set record roster {};dict set record metadata_baseline {}
    sourceSurfaceSet [dict get $record parameter_text] {};dict set record parameter_baseline {};dict set record parameter_definitions {}
    [dict get $record tree] delete [[dict get $record tree] children {}]
    _scriptLibraryHostPut $key $record
    _scriptLibraryHostRenderMetadata $window $context [dict merge [scriptRegistryDefaults] {scope user}] 0 0
    sourceSurfaceConfigure [dict get $record parameter_text] {mode read_only}
    viewerGuiDesignTextSet $window [dict get $context component_ids record_identity] {Choose a saved Script or create a new draft.}
    _scriptLibraryHostRefreshBound $window $key $context
    _scriptLibraryHostStatus $window $context {Deleted the reviewed Registry record. Historical execution snapshots and external sources remain}
    return 1
}
proc ::GX::_scriptLibraryHostImport {window form key context operation request} {
    set scope [dict get $request scope]
    if {$scope ni {user session} || ($scope eq {session} && [dict get $context session_token] eq {})} {error {Choose an available User/Session import scope}}
    if {$operation eq {import_script}} {_scriptLibraryHostCorrectedOwner ::GX::scriptRegistryReadChosenSource}
    set types [expr {$operation eq {import_project}?{{{Script Project ZIP} {.zip}}}:{{{Python or Octave source} {.py .m}}}}]
    set path [workspaceOpenFile manifest_dir -parent $window -title {Import registered Script source} -filetypes $types]
    if {$path eq {}} {return 0}
    set context [_scriptLibraryHostGuard $window $form $operation]
    if {$scope eq {session} && [dict get $context session_token] eq {}} {error {Session changed during import}}
    set token [dict get $context session_token]
    set id [_scriptLibraryHostId $window $form]
    if {$id eq {}} {return 0}
    set context [_scriptLibraryHostGuard $window $form $operation]
    if {$scope eq {session} && ($token eq {} || $token ne [dict get $context session_token])} {error {Session changed during import review}}
    if {![_scriptLibraryHostReview $window $form $key $context]} {return 0}
    set context [_scriptLibraryHostGuard $window $form $operation]
    if {$scope eq {session} && $token ne [dict get $context session_token]} {error {Session changed before import}}
    if {$operation eq {import_project}} {
        set saved [scriptRegistryProjectImport $scope $id [file rootname [file tail $path]] $path]
    } else {
        # User-picked path stays in trusted CORE only. The maintained reader
        # owns ordinary-file/identity/size/UTF-8 validation, not this GUI.
        set chosen [scriptRegistryReadChosenSource $path]
        set context [_scriptLibraryHostGuard $window $form import_script]
        if {$scope eq {session} && $token ne [dict get $context session_token]} {error {Session changed before source registration}}
        set saved [scriptRegistrySave $scope $id [file rootname [file tail $path]] [dict get $chosen source] [dict create language [dict get $chosen language] description "Imported source snapshot [file tail $path]" source_scope external_import source_id [file tail $path] source_sha256 [dict get $chosen sha256]]]
    }
    _scriptLibraryHostBind $window $form $key $context $saved "[dict get $saved scope]:[dict get $saved id]"
    _scriptLibraryHostRefreshBound $window $key $context
    _scriptLibraryHostStatus $window $context "Imported [dict get $saved scope]:[dict get $saved id]; no source was executed"
    return 1
}
proc ::GX::viewerGuiScriptLibraryDispose {window form} {
    _scriptLibraryHostGuard $window $form dispose
    set key [_scriptLibraryHostKey $window $form]
    if {![dict exists $::GX::ScriptLibraryHost::bindings $key]} return
    set record [_scriptLibraryHostGet $key]
    foreach widget [list [dict get $record tree] [dict get $record tree]X [dict get $record tree]Y [dict get $record source_host] [dict get $record parameter_host]] {if {[winfo exists $widget]} {destroy $widget}}
    dict unset ::GX::ScriptLibraryHost::bindings $key
}
proc ::GX::_scriptLibraryHostChanged {window form} {
    if {[catch {set context [_scriptLibraryHostGuard $window $form draft_changed]}]} return
    set key [_scriptLibraryHostKey $window $form]
    if {![dict exists $::GX::ScriptLibraryHost::bindings $key] || [dict get $::GX::ScriptLibraryHost::bindings $key busy]} return
    viewerGuiTraceEmit $window [dict get $context component_ids registered_source] source_changed [dict create status local_draft source_bytes_in_event 0]
    if {[llength [info commands ::GX::_viewerGuiScriptLibraryDraftChanged]]} {_viewerGuiScriptLibraryDraftChanged $window $form}
}
proc ::GX::_scriptLibraryHostStub {language} {
    return [expr {$language eq {Python}?"# Registered GX-TXT Python script\nfrom gxtxt import gxtxt_context\nctx = gxtxt_context()\n":"% Registered GX-TXT Octave script\nctx = gxtxt_context();\n"}]
}
proc ::GX::_scriptLibraryHostNewLanguage {window key context} {
    set record [_scriptLibraryHostGet $key]
    if {[dict get $record selected] ne {} || [dict get $record baseline] eq {} || [dict get $record baseline kind] ne {script} || [dict get $record busy]} return
    set language [string tolower [_scriptLibraryHostValue $context record_language]]
    if {$language ni {python octave}} return
    set language [expr {$language eq {python}?{Python}:{Octave}}]
    set original [dict get $record baseline language]
    if {$language eq $original} return
    set active [dict get $record active_file];set source [dict get $record sources $active]
    set current [sourceSurfaceGet [dict get $source text]]
    if {$current eq [_scriptLibraryHostStub $original] && [dict get $source baseline] eq $current} {
        set replacement [_scriptLibraryHostStub $language]
        sourceSurfaceReplace [dict get $source text] $replacement
        dict set source baseline $replacement
    }
    sourceSurfaceConfigure [dict get $source text] [dict create language [string tolower $language]]
    set relative [scriptRegistrySourceName $language]
    dict set record baseline language $language
    dict set record sources [dict create $relative $source]
    dict set record roster [dict create $relative [dict create sha256 {}]]
    dict set record active_file $relative;dict set record selected_relative_file $relative
    set tree [dict get $record tree];$tree delete [$tree children {}]
    $tree insert {} end -id f1 -text $relative -values [list source {}]
    dict set record file_rows [dict create f1 $relative]
    _scriptLibraryHostPut $key $record
}
proc ::GX::_scriptLibraryHostTextView {text} {
    return [dict create cursor [$text index insert] selection [$text tag ranges sel] xview [lindex [$text xview] 0] yview [lindex [$text yview] 0]]
}
proc ::GX::_scriptLibraryHostTextViewValidate {view} {
    if {[catch {dict size $view}] || [lsort [dict keys $view]] ne {cursor selection xview yview}} {error {Invalid captured Source presentation fields}}
    foreach key {xview yview} {set value [dict get $view $key];if {![string is double -strict $value] || !($value>=0 && $value<=1)} {error {Invalid captured Source scroll anchor}}}
    if {[llength [dict get $view selection]]%2 || [llength [dict get $view selection]]>2} {error {Invalid captured Source selection}}
    foreach index [concat [list [dict get $view cursor]] [dict get $view selection]] {if {![regexp {^[1-9][0-9]{0,8}\.[0-9]{1,9}$} $index]} {error {Invalid captured Source cursor/selection}}}
    return $view
}
proc ::GX::_scriptLibraryHostRestoreTextView {text view} {
    foreach key {cursor selection xview yview} {if {![dict exists $view $key]} {error {Incomplete Source presentation snapshot}}}
    foreach key {xview yview} {set value [dict get $view $key];if {![string is double -strict $value] || !($value>=0 && $value<=1)} {error {Invalid Source scroll anchor}}}
    foreach index [concat [list [dict get $view cursor]] [dict get $view selection]] {if {![regexp {^[1-9][0-9]{0,8}\.[0-9]{1,9}$} $index]} {error {Invalid Source text index}}}
    if {[llength [dict get $view selection]]%2 || [llength [dict get $view selection]]>2} {error {Invalid Source selection}}
    $text mark set insert [dict get $view cursor];$text tag remove sel 1.0 end
    if {[llength [dict get $view selection]]} {$text tag add sel {*}[dict get $view selection]}
    $text xview moveto [dict get $view xview];$text yview moveto [dict get $view yview]
}
proc ::GX::_scriptLibraryHostDraftValidate {snapshot} {
    set fields {schema reference baseline metadata_fields roster active_file sources parameter_text parameter_baseline parameter_definitions parameter_view filters inventory_offset inventory_limit}
    if {[catch {dict size $snapshot}] || [lsort [dict keys $snapshot]] ne [lsort $fields] || [dict get $snapshot schema] ne {gxtxt.script_library_ui_draft.v1}} {error {Unsupported Script Library draft snapshot}}
    set reference [dict get $snapshot reference]
    if {$reference ne {} && ![regexp {^(user|session):[A-Za-z][A-Za-z0-9_.-]*$} $reference]} {error {Invalid captured Script reference}}
    if {[catch {dict size [dict get $snapshot roster]}] || [dict size [dict get $snapshot roster]]>256 || [catch {dict size [dict get $snapshot sources]}] || [dict size [dict get $snapshot sources]]>256} {error {Script draft exceeds the existing 256-file Project boundary}}
    set baseline [dict get $snapshot baseline]
    if {$baseline ne {}} {
        set allowed [concat [dict keys [scriptRegistryDefaults]] record_sha256]
        foreach key [dict keys $baseline] {if {$key ni $allowed} {error {Captured baseline contains undeclared data or paths}}}
        if {[dict get $baseline scope] ni {user session} || [dict get $baseline language] ni {Python Octave} || [dict get $baseline kind] ni {script project}} {error {Invalid captured Script baseline}}
        if {$reference ne "[dict get $baseline scope]:[dict get $baseline id]" && $reference ne {}} {error {Captured Script identity differs from its baseline}}
        foreach key [dict keys [scriptRegistryDefaults]] {if {![dict exists $baseline $key]} {error {Captured baseline is incomplete}}}
        set revision [dict get $baseline revision]
        if {![string is wideinteger -strict $revision] || $revision<0 || $revision>9223372036854775807} {error {Invalid captured Registry revision}}
        if {$reference ne {} && ($revision<1 || ![regexp {^[a-f0-9]{64}$} [dict get $baseline sha256]])} {error {Invalid captured saved-source baseline}}
        if {$reference eq {} && ($revision!=0 || [dict get $baseline sha256] ne {} || [dict get $baseline kind] ne {script})} {error {Invalid captured new-source baseline}}
        if {[dict exists $baseline record_sha256] && ![regexp {^[a-f0-9]{64}$} [dict get $baseline record_sha256]]} {error {Invalid captured record identity}}
    } elseif {[dict size [dict get $snapshot sources]] || [dict size [dict get $snapshot roster]] || [dict get $snapshot active_file] ne {} || $reference ne {}} {error {Unbound snapshot cannot supply registered source buffers}}
    foreach relative [dict keys [dict get $snapshot roster]] {
        if {$relative eq {} || [string length [encoding convertto utf-8 $relative]]>1024 || [file pathtype $relative] ne {relative} || [string first \\ $relative]>=0 || [regexp {[\x00-\x1f]} $relative]} {error {Invalid inert source-relative name}}
        foreach segment [split $relative /] {if {$segment in {{} . ..}} {error {Invalid inert source-relative segment}}}
        set file [dict get $snapshot roster $relative]
        if {[dict keys $file] ne {sha256} || ([dict get $file sha256] ne {} && ![regexp {^[a-f0-9]{64}$} [dict get $file sha256]])} {error {Invalid captured source roster}}
    }
    set active [dict get $snapshot active_file]
    if {$active ne {} && ![dict exists $snapshot sources $active]} {error {Captured active source is absent}}
    set currentBytes 0;set baselineBytes 0
    dict for {relative source} [dict get $snapshot sources] {
        if {![dict exists $snapshot roster $relative] || [lsort [dict keys $source]] ne {baseline_text text view}} {error {Captured source differs from its declared roster/schema}}
        foreach {key total} {text currentBytes baseline_text baselineBytes} {
            set size [string length [encoding convertto utf-8 [dict get $source $key]]]
            if {$size>4194304} {error {Captured Source exceeds 4 MiB per file}}
            incr $total $size
        }
        set view [dict get $source view]
        _scriptLibraryHostTextViewValidate $view
    }
    if {$currentBytes>16777216 || $baselineBytes>16777216} {error {Captured Source exceeds 16 MiB current/baseline Project bounds}}
    set size [expr {$currentBytes+$baselineBytes}]
    foreach key {parameter_text parameter_baseline metadata_fields baseline parameter_definitions} {
        set bytes [string length [encoding convertto utf-8 [dict get $snapshot $key]]]
        if {$bytes>1048576} {error {Captured metadata/parameters exceed 1 MiB}}
        incr size $bytes
    }
    if {$size>41943040} {error {Script Library draft exceeds its explicit 40 MiB controller bound}}
    _scriptLibraryHostTextViewValidate [dict get $snapshot parameter_view]
    if {[lsort [dict keys [dict get $snapshot metadata_fields]]] ne {description id language name required_apis scope version}} {error {Invalid captured metadata field schema}}
    if {[lsort [dict keys [dict get $snapshot filters]]] ne {language query scope} || [dict get $snapshot filters scope] ni {all user session} || [dict get $snapshot filters language] ni {all python octave} || [string length [dict get $snapshot filters query]]>256} {error {Invalid captured inventory filter}}
    foreach key {inventory_offset inventory_limit} {if {![string is wideinteger -strict [dict get $snapshot $key]] || [dict get $snapshot $key]<0} {error {Invalid captured inventory page}}}
    if {[dict get $snapshot inventory_limit]<1 || [dict get $snapshot inventory_limit]>100} {error {Invalid captured inventory page bound}}
    return $snapshot
}
# Trusted host only: this source-bearing schema never enters the authored Host
# operation registry or its 48 KiB receipt. MAIN's normal Workspace codec must
# retain large bodies using existing typed managed Resource transport.
proc ::GX::_viewerGuiScriptLibraryCapture {window form} {
    set context [_scriptLibraryHostGuard $window $form capture]
    set key [_scriptLibraryHostEnsure $window $form $context];set record [_scriptLibraryHostGet $key]
    set baseline {}
    if {[dict get $record baseline] ne {}} {
        foreach field [concat [dict keys [scriptRegistryDefaults]] record_sha256] {if {[dict exists $record baseline $field]} {dict set baseline $field [dict get $record baseline $field]}}
    }
    set roster {};dict for {relative descriptor} [datasetPublicationV2DictDefault $record roster {}] {dict set roster $relative [dict create sha256 [dict get $descriptor sha256]]}
    set sources {}
    dict for {relative source} [dict get $record sources] {
        dict set sources $relative [dict create text [sourceSurfaceGet [dict get $source text]] baseline_text [dict get $source baseline] view [_scriptLibraryHostTextView [dict get $source text]]]
    }
    set snapshot [dict create schema gxtxt.script_library_ui_draft.v1 reference [dict get $record selected] baseline $baseline metadata_fields [_scriptLibraryHostMetadata $context 0] roster $roster \
        active_file [dict get $record active_file] sources $sources parameter_text [sourceSurfaceGet [dict get $record parameter_text]] parameter_baseline [dict get $record parameter_baseline] \
        parameter_definitions [dict get $record parameter_definitions] parameter_view [_scriptLibraryHostTextView [dict get $record parameter_text]] filters [dict get $record filters] \
        inventory_offset [dict get $record inventory offset] inventory_limit [dict get $record inventory limit]]
    return [_scriptLibraryHostDraftValidate $snapshot]
}
proc ::GX::_viewerGuiScriptLibraryRestore {window form snapshot} {
    set context [_scriptLibraryHostGuard $window $form restore]
    set snapshot [_scriptLibraryHostDraftValidate $snapshot]
    set readOnly [expr {[dict exists $::GX::ScientificHistory::viewers $window] && [dict get [scientificHistoryViewerRestoreContext $window] mode] eq {browse}}]
    set key [_scriptLibraryHostEnsure $window $form $context];set old [_scriptLibraryHostGet $key]
    if {[dict get $old busy]} {error {Complete the current Script review before restoring a draft}}
    set candidate {};set created {};set views {}
    try {
        dict for {relative source} [dict get $snapshot sources] {
            set reuse [expr {[dict exists $old sources $relative] && [dict get $old selected] eq [dict get $snapshot reference]}]
            if {$reuse} {set frame [dict get $old sources $relative frame];set text [dict get $old sources $relative text]
            } else {
                set frame [dict get $old source_host].file[incr ::GX::ScriptLibraryHost::serial]
                lappend created $frame
                set text [sourceSurfaceCreate $frame [dict create mode editable language [string tolower [dict get $snapshot baseline language]] find_bar 1 find_bar_visible 0 change_command [list ::GX::_scriptLibraryHostChanged $window $form]]]
            }
            dict set candidate $relative [dict create frame $frame text $text baseline [dict get $source baseline_text]]
            dict set views $relative [dict get $source view]
        }
        set context [_scriptLibraryHostGuard $window $form restore]
    } on error {message options} {foreach frame $created {if {[winfo exists $frame]} {destroy $frame}};return -options $options $message}
    dict set ::GX::ScriptLibraryHost::bindings $key busy 1
    try {
        dict for {relative source} [dict get $snapshot sources] {
            set text [dict get $candidate $relative text]
            sourceSurfaceConfigure $text {mode editable}
            if {[sourceSurfaceGet $text] ne [dict get $source text]} {sourceSurfaceReplace $text [dict get $source text]}
            sourceSurfaceConfigure $text [dict create mode [expr {$readOnly?{read_only}:{editable}}]]
            _scriptLibraryHostRestoreTextView $text [dict get $source view]
        }
        set fields [dict get $snapshot metadata_fields]
        _scriptLibraryHostRenderMetadata $window $context $fields [expr {[dict get $snapshot reference] ne {}}] [expr {!$readOnly && [dict get $snapshot baseline] ne {}}]
        set parameterText [dict get $old parameter_text]
        sourceSurfaceConfigure $parameterText {mode editable}
        if {[sourceSurfaceGet $parameterText] ne [dict get $snapshot parameter_text]} {sourceSurfaceReplace $parameterText [dict get $snapshot parameter_text]}
        sourceSurfaceConfigure $parameterText [dict create mode [expr {$readOnly || [dict get $snapshot baseline] eq {}?{read_only}:{editable}}]]
        _scriptLibraryHostRestoreTextView $parameterText [dict get $snapshot parameter_view]
        set record $old
        dict set record sources $candidate;dict set record baseline [dict get $snapshot baseline];dict set record selected [dict get $snapshot reference]
        dict set record roster [dict get $snapshot roster];dict set record active_file [dict get $snapshot active_file];dict set record selected_relative_file [dict get $snapshot active_file]
        dict set record metadata_baseline [expr {[dict get $snapshot baseline] eq {}?{}:[_scriptLibraryHostMetadataProjection [dict get $snapshot baseline]]}]
        dict set record parameter_baseline [dict get $snapshot parameter_baseline];dict set record parameter_definitions [dict get $snapshot parameter_definitions]
        dict set record draft_token "script-library-draft-[pid]-[incr ::GX::ScriptLibraryHost::serial]-[clock clicks]"
        dict set record session_token [expr {[dict get $snapshot baseline] ne {} && [dict get $snapshot baseline scope] eq {session}?[dict get $context session_token]:{}}]
        dict set record filters [dict get $snapshot filters]
        set tree [dict get $record tree];$tree delete [$tree children {}];set fileRows {};set index 0
        dict for {relative file} [dict get $snapshot roster] {set id f[incr index];dict set fileRows $id $relative;$tree insert {} end -id $id -text $relative -values [list source [dict get $file sha256]]}
        dict set record file_rows $fileRows;dict set record busy 0
        _scriptLibraryHostPut $key $record
        dict for {relative source} [dict get $old sources] {
            if {![dict exists $candidate $relative] || [dict get $candidate $relative frame] ne [dict get $source frame]} {destroy [dict get $source frame]}
        }
        dict for {relative source} $candidate {pack forget [dict get $source frame]}
        if {[dict get $record active_file] ne {}} {pack [dict get $candidate [dict get $record active_file] frame] -fill both -expand 1}
        foreach {role field} {scope_filter scope language_filter language search_query query} {_scriptLibraryHostSetValue $window $context $role [dict get $snapshot filters $field]}
        _scriptLibraryHostStatus $window $context {Restored local source draft only; canonical Registry/SourceNote state is unchanged}
        return [_scriptLibraryHostView $key $context]
    } finally {if {[dict exists $::GX::ScriptLibraryHost::bindings $key]} {dict set ::GX::ScriptLibraryHost::bindings $key busy 0}}
}

source [file join [file dirname [info script]] script_library_history_v1.tcl]
source [file join [file dirname [info script]] script_library_launch_v1.tcl]
