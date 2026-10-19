# SPDX-License-Identifier: GPL-3.0-or-later
# Host-only projections. These weak widget subscriptions never own Documents,
# resource trees, provider actions or scientific History.
namespace eval ::GX::SessionWorkspace {variable adapters {};variable hosts {};variable menus {}}
proc ::GX::_workspaceHostToken {} {if {$::GX::currentSession eq {} || ![file isdirectory $::GX::currentSession]} {return {}};return [interactiveDocumentSessionToken]}
proc ::GX::_workspaceHostContext {provider callbacks parent} {return [dict create provider $provider callbacks $callbacks parent $parent token [_workspaceHostToken] window_id [expr {[winfo exists $parent] ? [winfo id $parent] : {}}]]}
proc ::GX::_workspaceHostCheck {context} {
    if {[dict get $context token] eq {} || [dict get $context token] ne [_workspaceHostToken]} {error {Session changed. Reopen the Workspace command.}}
    set parent [dict get $context parent]
    if {![winfo exists $parent] || [winfo id $parent] != [dict get $context window_id]} {error {Workspace host has closed or was replaced.}}
}
proc ::GX::_workspaceHostReceipt {id} {set item [sessionWorkspaceGet $id];return [dict create workspace_id $id generation [dict get $item generation] revision [dict get $item revision] provider_id [dict get $item provider_id]]}
proc ::GX::_workspaceHostValidateReceipt {receipt} {
    set now [_workspaceHostReceipt [dict get $receipt workspace_id]]
    if {$now ne $receipt} {error {Workspace changed or was replaced. Refresh and select it again.}}
    return [dict get $receipt workspace_id]
}
proc ::GX::_workspaceHostAdapter {provider {context {}}} {
    if {$context ne {} && [dict get $context provider] eq $provider && [dict get $context callbacks] ne {}} {return $context}
    dict for {parent candidate} $::GX::SessionWorkspace::adapters {
        if {[winfo exists $parent] && [dict get $candidate provider] eq $provider && [dict get $candidate token] eq [_workspaceHostToken]} {return $candidate}
    }
    return [_workspaceHostContext $provider {} .]
}
proc ::GX::_workspaceHostCurrent {context} {set cb [dict get $context callbacks];if {![dict exists $cb current]} {return {}};return [uplevel #0 [dict get $cb current]]}
proc ::GX::sessionWorkspaceHostState {context {id {}}} {
    set valid [expr {[dict get $context token] ne {} && [dict get $context token] eq [_workspaceHostToken] && [winfo exists [dict get $context parent]] && [winfo id [dict get $context parent]] == [dict get $context window_id]}]
    set selected [expr {$valid && $id ne {} && ![catch {sessionWorkspaceGet $id} item]}]
    set provider [dict get $context provider]
    if {$selected} {set provider [dict get $item provider_id]}
    set adapter [_workspaceHostAdapter $provider $context];set cb [dict get $adapter callbacks]
    set current {};catch {set current [_workspaceHostCurrent $adapter]}
    set currentSelected [expr {$current ne {} && (!$selected || $current eq $id)}]
    set state [dict create refresh 1 manager $valid new [expr {$valid && [dict exists $cb open]}] import $valid open $selected duplicate $selected rename $selected delete $selected notes $selected preview $selected export $selected actions $selected save [expr {$valid && [dict exists $cb save] && (!$selected || $currentSelected)}] close [expr {$valid && [dict exists $cb close] && (!$selected || $currentSelected)}]]
    if {$provider ne {} && [catch {_workspaceProvider $provider}]} {foreach action {new open save duplicate rename delete notes preview export actions} {dict set state $action 0}}
    if {$valid && [dict exists $cb prepare] && [catch {uplevel #0 [list {*}[dict get $cb prepare] query]} reason]} {foreach action {new open save duplicate close delete} {dict set state $action 0}}
    return $state
}
proc ::GX::sessionWorkspaceHostPrepare {context action} {
    _workspaceHostCheck $context
    set cb [dict get $context callbacks]
    if {[dict exists $cb prepare]} {uplevel #0 [list {*}[dict get $cb prepare] $action]}
    if {![dict exists $cb dirty] || ![uplevel #0 [dict get $cb dirty]]} {return 1}
    if {[dict exists $cb review]} {uplevel #0 [list {*}[dict get $cb review] 1]}
    try {
    set answer [tk_messageBox -parent [dict get $context parent] -title {Workspace changes} -icon question -type yesnocancel -default cancel -message "Save the current Workspace changes before $action?\n\nYes: Save. No: Discard unsaved changes. Cancel: keep editing."]
    _workspaceHostCheck $context
    if {$answer eq {cancel}} {return 0}
    if {$answer eq {yes}} {
        if {![dict exists $cb save]} {error {This Viewer cannot save the current draft.}}
        uplevel #0 [dict get $cb save]
        if {[uplevel #0 [dict get $cb dirty]]} {error {Workspace changes remain unsaved. Continue editing before switching.}}
    } elseif {![dict exists $cb discard]} {error {This Viewer has no safe discard callback. Continue editing or Save.}}
    } finally {if {[dict exists $cb review] && [winfo exists [dict get $context parent]]} {uplevel #0 [list {*}[dict get $cb review] 0]}}

    return 1
}
proc ::GX::_workspaceHostClose {context} {set cb [dict get $context callbacks];if {[dict exists $cb discard]} {uplevel #0 [dict get $cb discard]} elseif {[dict exists $cb close]} {uplevel #0 [dict get $cb close]}}
proc ::GX::_workspaceHostDestroyed {widget actual} {
    if {$widget ne $actual} return
    foreach name {adapters hosts menus views titles} {if {[dict exists [set ::GX::SessionWorkspace::$name] $widget]} {dict unset ::GX::SessionWorkspace::$name $widget}}
    catch {image delete gxWorkspacePreview_[string map {. _} $widget]}
}
proc ::GX::sessionWorkspaceDemoCreate {widget callback} {
    ttk::labelframe $widget -text {DEMO / simulated Workspace controls} -padding 8
    ttk::label $widget.label -text {Synthetic interface layout · not a registered Workspace}
    ttk::menubutton $widget.commands -text {Workspace sample} -menu $widget.commands.menu
    menu $widget.commands.menu -tearoff 0
    foreach label {{New workspace…} {Open workspace…} Save {Save as / Duplicate…} Rename… {Session Workspaces…} Close Delete… Notes… Preview… Import… Export… Refresh} {$widget.commands.menu add command -label $label -state disabled}
    ttk::button $widget.inspect -text {Inspect inert sample} -command [list {*}$callback workspace_sample]
    pack $widget.label $widget.commands $widget.inspect -anchor w -padx 3 -pady 3
    return $widget
}
proc ::GX::sessionWorkspaceViewerMenu {menu provider callbacks parent} {
    set context [_workspaceHostContext $provider $callbacks $parent]
    dict set ::GX::SessionWorkspace::adapters $parent $context
    dict set ::GX::SessionWorkspace::menus $menu [dict create context $context actions {new open save duplicate rename manager close delete notes preview import export refresh}]
    bind $parent <Destroy> +[list ::GX::_workspaceHostDestroyed $parent %W]
    bind $menu <Destroy> +[list ::GX::_workspaceHostDestroyed $menu %W]
    foreach {label action} {{New workspace…} new {Open workspace…} open Save save {Save as / Duplicate…} duplicate Rename… rename {Session Workspaces…} manager Close close Delete… delete Notes… notes Preview… preview Import… import Export… export Refresh refresh} {
        $menu add command -label $label -command [list ::GX::sessionWorkspaceViewerAction $provider $callbacks $parent $action]
    }
    menu $menu.ownerActions -tearoff 0 -postcommand [list ::GX::sessionWorkspaceHostProviderMenu $menu $menu.ownerActions]
    $menu add cascade -label Actions -menu $menu.ownerActions
    $menu configure -postcommand [list ::GX::sessionWorkspaceViewerMenuRefresh $menu]
    sessionWorkspaceViewsChanged
}
proc ::GX::sessionWorkspaceViewerMenuRefresh {menu} {
    if {![winfo exists $menu] || ![dict exists $::GX::SessionWorkspace::menus $menu]} return
    set config [dict get $::GX::SessionWorkspace::menus $menu];set context [dict get $config context]
    set id {};catch {set id [_workspaceHostCurrent $context]}
    set states [sessionWorkspaceHostState $context $id];set i 0
    $menu entryconfigure 13 -state [expr {[dict get $states actions] ? {normal} : {disabled}}]
    foreach action [dict get $config actions] {$menu entryconfigure $i -state [expr {[dict get $states $action] ? {normal} : {disabled}}];incr i}
}
proc ::GX::sessionWorkspaceViewerAction {provider callbacks parent action {errorMode dialog}} {
    if {$errorMode ni {dialog propagate}} {error {Workspace error mode must be dialog or propagate.}}
    if {[dict exists $::GX::SessionWorkspace::adapters $parent]} {set context [dict get $::GX::SessionWorkspace::adapters $parent]} else {set context [_workspaceHostContext $provider $callbacks $parent]}
    set id {};catch {set id [_workspaceHostCurrent $context]}
    if {$action eq {close} && [dict get $context token] ne [_workspaceHostToken] && [dict exists $callbacks discard]} {
        # Closing a stale Viewer releases only its live handles. Its old Session
        # remains untouched; a stale window must never save into the new Session.
        return [uplevel #0 [dict get $callbacks discard]]
    }
    if {$errorMode eq {propagate}} {
        # Structured host clients need the same guarded dispatch error, rather
        # than a modal message box that hides failure from their receipt.
        return [sessionWorkspaceHostDispatch $context [expr {$action in {open manager preview} ? {manager} : $action}] $id]
    }
    if {$action in {open manager preview}} {return [sessionWorkspaceHostInvoke $context manager $id]}
    sessionWorkspaceHostInvoke $context $action $id
}
proc ::GX::sessionWorkspaceDialog {{parent .} {provider {}} {callbacks {}}} {
    set window .gxSessionWorkspaces
    if {[winfo exists $window]} {destroy $window}
    toplevel $window;wm title $window {Session Workspaces};wm transient $window $parent
    wm geometry $window 1000x650;wm minsize $window 650 440
    sessionWorkspaceBuild $window $provider $callbacks $parent
    return $window
}
proc ::GX::sessionWorkspaceBuild {frame {provider {}} {callbacks {}} {parent {}}} {
    if {$parent eq {}} {set parent [winfo toplevel $frame]}
    ttk::frame $frame.workspaces;set f $frame.workspaces;pack $f -fill both -expand 1
    dict set ::GX::SessionWorkspace::hosts $f [dict create context [_workspaceHostContext $provider $callbacks $parent] rows {} query {} provider $provider]
    ttk::frame $f.filters
    ttk::label $f.filters.label -text {Name / type / provider:}
    ttk::entry $f.filters.query -width 24
    ttk::combobox $f.filters.provider -state readonly -width 30
    ttk::button $f.filters.clear -text Reset -command [list ::GX::sessionWorkspaceHostFilterReset $f]
    pack $f.filters.label $f.filters.query $f.filters.provider $f.filters.clear -side left -padx 4 -pady 5
    pack $f.filters -fill x
    ttk::panedwindow $f.body -orient vertical;ttk::frame $f.body.list;ttk::frame $f.body.detail
    $f.body add $f.body.list -weight 3;$f.body add $f.body.detail -weight 1;pack $f.body -fill both -expand 1
    ttk::treeview $f.tree -columns {name type provider preview} -show headings -height 7 -selectmode browse
    foreach {key label width} {name Name 230 type Type 140 provider Provider 150 preview Preview 90} {$f.tree heading $key -text $label;$f.tree column $key -width $width -minwidth 70 -stretch 1}
    ttk::scrollbar $f.scroll -command [list $f.tree yview];$f.tree configure -yscrollcommand [list $f.scroll set]
    pack $f.scroll -in $f.body.list -side right -fill y;pack $f.tree -in $f.body.list -fill both -expand 1
    ttk::label $f.preview -text {Select a Workspace for preview and details.} -wraplength 600 -justify left
    pack $f.preview -in $f.body.detail -fill both -expand 1 -padx 8 -pady 5
    ttk::frame $f.actions;pack $f.actions -fill x -pady 4
    foreach {action label} {new New… open Open save Save duplicate Duplicate… rename Rename… close Close delete Delete… notes Notes… preview Preview import Import… export Export… refresh Refresh} {
        ttk::button $f.actions.$action -text $label -command [list ::GX::sessionWorkspaceGuiAction $f $action];pack $f.actions.$action -side left -padx 2
    }
    ttk::menubutton $f.actions.provider -text Actions -menu $f.actions.provider.menu
    menu $f.actions.provider.menu -tearoff 0 -postcommand [list ::GX::sessionWorkspaceHostProviderMenu $f $f.actions.provider.menu]
    pack $f.actions.provider -side left -padx 2
    uiMenuRowAttach $f.actions [pack slaves $f.actions]
    ttk::label $f.status -text {} -wraplength 800 -justify left;pack $f.status -fill x -padx 8 -pady 4
    bind $f.filters.query <KeyRelease> [list ::GX::sessionWorkspaceGuiAction $f refresh]
    bind $f.filters.provider <<ComboboxSelected>> [list ::GX::sessionWorkspaceGuiAction $f refresh]
    bind $f.tree <<TreeviewSelect>> [list ::GX::sessionWorkspaceGuiAction $f inspect]
    bind $f.tree <Double-1> [list ::GX::sessionWorkspaceGuiAction $f open]
    bind $f.tree <Return> [list ::GX::sessionWorkspaceGuiAction $f open]
    bind $f <Destroy> +[list ::GX::_workspaceHostDestroyed $f %W]
    dict set ::GX::SessionWorkspace::views $f {}
    sessionWorkspaceGuiAction $f refresh
    return $f
}
proc ::GX::sessionWorkspaceHostFilterReset {f} {$f.filters.query delete 0 end;dict set ::GX::SessionWorkspace::hosts $f provider [dict get $::GX::SessionWorkspace::hosts $f context provider];$f.filters.provider set {};sessionWorkspaceGuiAction $f refresh}
proc ::GX::_workspaceHostRefresh {f} {
    set config [dict get $::GX::SessionWorkspace::hosts $f];set context [dict get $config context]
    set selected [$f.tree selection]
    if {[dict get $context token] ne [_workspaceHostToken]} {set selected {}}
    if {[dict get $context callbacks] eq {}} {dict set context token [_workspaceHostToken]}
    dict set config context $context
    set query [string tolower [string trim [$f.filters.query get]]]
    set scope [dict get $context provider];set providers [dict create {All providers} {}]
    dict for {provider descriptor} $::GX::SessionWorkspace::providers {if {![catch {_workspaceProvider $provider}]} {dict set providers "[dict get $descriptor type] ($provider)" $provider}}
    $f.filters.provider configure -values [dict keys $providers]
    set label [$f.filters.provider get]
    if {$scope ne {}} {set label "Unavailable provider ($scope)";dict for {candidate value} $providers {if {$value eq $scope} {set label $candidate;break}};dict set providers $label $scope;$f.filters.provider configure -state disabled} elseif {![dict exists $providers $label]} {set label {All providers}}
    $f.filters.provider set $label;set filter [dict get $providers $label]
    $f.tree delete [$f.tree children {}];dict set config rows {}
    set available [expr {[dict get $context token] eq [_workspaceHostToken] ? [sessionWorkspaceList] : {}}]
    foreach workspace $available {
        if {$filter ne {} && [dict get $workspace provider_id] ne $filter} continue
        if {$query ne {} && [string first $query [string tolower "[dict get $workspace name] [dict get $workspace type] [dict get $workspace provider_id]"]]<0} continue
        set id [dict get $workspace workspace_id]
        $f.tree insert {} end -id $id -values [list [dict get $workspace name] [dict get $workspace type] [dict get $workspace provider_id] [expr {[dict get $workspace preview] eq {} ? {none} : {available}}]]
        dict set config rows $id [_workspaceHostReceipt $id]
    }
    dict set config provider $filter;dict set ::GX::SessionWorkspace::hosts $f $config
    if {[llength $selected]==1 && [$f.tree exists $selected]} {$f.tree selection set $selected;$f.tree see $selected}
    _workspaceHostInspect $f
}
proc ::GX::_workspaceHostInspect {f} {
    set config [dict get $::GX::SessionWorkspace::hosts $f];set id [$f.tree selection]
    if {[llength $id]!=1} {set id {}}
    set context [dict get $config context];if {[dict get $context provider] eq {}} {dict set context provider [dict get $config provider]}
    set states [sessionWorkspaceHostState $context $id]
    dict for {action enabled} $states {if {[winfo exists $f.actions.$action]} {$f.actions.$action configure -state [expr {$enabled ? {normal} : {disabled}}]}}
    $f.actions.provider configure -state [expr {[dict get $states actions] ? {normal} : {disabled}}]
    $f.preview configure -image {} -text {Select a Workspace for preview and details.}
    catch {image delete gxWorkspacePreview_[string map {. _} $f]}
    if {$id eq {}} {$f.status configure -text [expr {[_workspaceHostToken] eq {} ? {Open a Session to manage Workspaces.} : {Select one Workspace. New and Save require an available Viewer adapter.}}];return}
    set item [sessionWorkspaceGet $id]
    $f.status configure -text "[dict get $item name] • [dict get $item provider_id] • revision [dict get $item revision]"
    set resource [dict get $item preview]
    if {$resource eq {}} {$f.preview configure -text {No managed preview is associated with this Workspace.};return}
    if {[catch {_workspaceHostPreview $f $id $resource} problem]} {$f.preview configure -text "Preview unavailable: $problem"}
}
proc ::GX::_workspaceHostPreview {f id resource} {
    interactiveDocumentResourceInfo $resource
    if {[dict get $resource metadata format] ne {image.png}} {$f.preview configure -text {Managed vector preview available; open the provider for its scientific scene.};return}
    set source [file join [_documentResourceRoot $id] [dict get $resource sha256].blob]
    set temporary [previewDescriptorCreateTempDir]
    try {
        set artifact [datasetPreviewImageArtifact $source $temporary 1]
        if {![dict exists $artifact path]} {error {Bounded image preview is unavailable.}}
        set imageName gxWorkspacePreview_[string map {. _} $f]
        image create photo $imageName -file [dict get $artifact path]
        $f.preview configure -image $imageName -text {}
    } finally {previewDescriptorCleanupDir $temporary}
}
proc ::GX::sessionWorkspaceGuiAction {frame action} {
    if {![winfo exists $frame] || ![dict exists $::GX::SessionWorkspace::hosts $frame]} return
    if {$action eq {refresh}} {_workspaceHostRefresh $frame;return}
    if {$action in {inspect preview}} {_workspaceHostInspect $frame;return}
    set config [dict get $::GX::SessionWorkspace::hosts $frame];set id [$frame.tree selection]
    if {[llength $id]!=1} {set id {}}
    set context [dict get $config context]
    if {[dict get $context provider] eq {}} {dict set context provider [dict get $config provider]}
    set receipt {};if {$id ne {} && [dict exists $config rows $id]} {set receipt [dict get $config rows $id]}
    sessionWorkspaceHostInvoke $context $action $id $receipt
}
proc ::GX::sessionWorkspaceHostInvoke {context action {id {}} {receipt {}}} {
    if {[catch {sessionWorkspaceHostDispatch $context $action $id $receipt} message options]==1} {
        set parent [dict get $context parent];if {![winfo exists $parent]} {set parent .}
        tk_messageBox -parent $parent -title Workspaces -icon error -message $message
    }
}
proc ::GX::sessionWorkspaceHostDispatch {context action {id {}} {receipt {}}} {
    _workspaceHostCheck $context
    if {$id ne {}} {if {$receipt eq {}} {set receipt [_workspaceHostReceipt $id]};_workspaceHostValidateReceipt $receipt;set provider [dict get $receipt provider_id]} else {set provider [dict get $context provider]}
    if {[dict get $context provider] ne {} && $provider ne [dict get $context provider]} {error {Workspace belongs to a different provider. Use its own host or the unscoped manager.}}
    set adapter [_workspaceHostAdapter $provider $context];set cb [dict get $adapter callbacks]
    if {![dict get [sessionWorkspaceHostState $context $id] $action]} {error {This Workspace action is unavailable for the current selection and Viewer.}}
    switch -- $action {
        refresh {sessionWorkspaceViewsChanged}
        manager {sessionWorkspaceDialog [dict get $context parent] $provider $cb}
        new - rename - duplicate {
            set name [expr {$action eq {new} ? {New Workspace} : [dict get [sessionWorkspaceGet $id] name]}]
            if {$action eq {duplicate}} {append name { copy}}
            set w [dict get $context parent].workspaceName
            uiFieldFormCreate $w "[string totitle $action] Workspace" {name {type string required 1 label Name}} [dict create name $name] [list ::GX::sessionWorkspaceHostNamed $adapter $action $id $receipt $w] [dict get $context parent]
        }
        save {uplevel #0 [dict get $cb save];sessionWorkspaceViewsChanged}
        close {if {[sessionWorkspaceHostPrepare $adapter closing]} {_workspaceHostClose $adapter}}
        open {
            sessionWorkspaceValidate $id
            if {[dict exists $cb open]} {
                if {[_workspaceHostCurrent $adapter] ne $id} {if {![sessionWorkspaceHostPrepare $adapter opening]} return;_workspaceHostValidateReceipt $receipt;_workspaceHostClose $adapter}
                uplevel #0 [list {*}[dict get $cb open] [dict create workspace_id $id]]
            } else {sessionWorkspaceOpen $id}
        }
        delete {
            set item [sessionWorkspaceGet $id]
            set current {};catch {set current [_workspaceHostCurrent $adapter]}
            if {$current eq $id && ![sessionWorkspaceHostPrepare $adapter deleting]} return
            set receipt [_workspaceHostReceipt $id]
            if {[tk_messageBox -parent [dict get $context parent] -title {Delete Workspace} -type okcancel -default cancel -icon warning -message "Delete Workspace ‘[dict get $item name]’?\n\nIts Document, notes, History and owned managed resources are removed. Source and published Datasets remain unchanged."] ne {ok}} return
            _workspaceHostCheck $context;_workspaceHostValidateReceipt $receipt
            if {$current eq $id} {_workspaceHostClose $adapter}
            sessionWorkspaceDelete $id
        }
        notes {noteDocumentOpen $id view}
        export {
            set path [workspaceSaveFile export_dir -title {Export workspace package} -initialfile "[dict get [sessionWorkspaceGet $id] name].gxtxt-workspace.zip" -defaultextension .zip]
            if {$path eq {}} return
            _workspaceHostCheck $context;_workspaceHostValidateReceipt $receipt
            set resource [sessionWorkspaceExport $id];set source [file join [_documentResourceRoot $id] [dict get $resource sha256].blob]
            file copy -- $source $path
        }
        import {
            set path [workspaceOpenFile session_open_dir -title {Import workspace package} -filetypes {{{GX-TXT workspace ZIP} {.zip}}}]
            if {$path eq {}} return
            _workspaceHostCheck $context
            set w [dict get $context parent].workspaceName
            uiFieldFormCreate $w {Import Workspace} {name {type string required 1 label {Unique Workspace name}}} {name {Imported Workspace}} [list ::GX::sessionWorkspaceHostImport $context $path $w] [dict get $context parent]
        }
    }
}
proc ::GX::sessionWorkspaceHostNamed {context action id receipt form values} {
    _workspaceHostCheck $context
    if {$receipt ne {}} {_workspaceHostValidateReceipt $receipt}
    set name [_workspaceName [dict get $values name] [expr {$action eq {rename} ? $id : {}}]]
    set cb [dict get $context callbacks]
    switch -- $action {
        rename {sessionWorkspaceRename $id $name}
        new {
            if {![sessionWorkspaceHostPrepare $context {creating a new Workspace}]} return
            _workspaceHostClose $context
            uplevel #0 [list {*}[dict get $cb open] [dict create workspace_id new workspace_name $name]]
        }
        duplicate {
            set current {};catch {set current [_workspaceHostCurrent $context]}
            if {[dict exists $cb open] && ![sessionWorkspaceHostPrepare $context duplicating]} return
            set package [sessionWorkspaceExport $id];set duplicate [sessionWorkspaceImport $package $name]
            if {[dict exists $cb open]} {_workspaceHostClose $context;uplevel #0 [list {*}[dict get $cb open] [dict create workspace_id [dict get $duplicate workspace_id]]]}
        }
    }
    if {[winfo exists $form]} {destroy $form}
    sessionWorkspaceViewsChanged
}
proc ::GX::sessionWorkspaceHostImport {context path form values} {
    _workspaceHostCheck $context;set name [_workspaceName [dict get $values name]]
    set item [_sessionWorkspaceImportPath $path $name [dict get $context provider]]
    if {[winfo exists $form]} {destroy $form};sessionWorkspaceViewsChanged
}

proc ::GX::sessionWorkspaceHostProviderMenu {host menu} {
    $menu delete 0 end
    set id {};set receipt {}
    if {[dict exists $::GX::SessionWorkspace::hosts $host]} {
        set config [dict get $::GX::SessionWorkspace::hosts $host];set context [dict get $config context]
        set id [$host.tree selection]
        if {[llength $id]!=1} {set id {}}
        if {$id ne {} && [dict exists $config rows $id]} {set receipt [dict get $config rows $id]}
    } elseif {[dict exists $::GX::SessionWorkspace::menus $host]} {
        set context [dict get $::GX::SessionWorkspace::menus $host context]
        catch {set id [_workspaceHostCurrent $context]}
        if {$id ne {}} {catch {set receipt [_workspaceHostReceipt $id]}}
    } else {return}
    if {$id eq {} || $receipt eq {} || [catch {_workspaceHostCheck $context}]} {$menu add command -label {Select an available Workspace} -state disabled;return}
    foreach action [sessionWorkspaceActions $id] {$menu add command -label [dict get $action name] -command [list ::GX::sessionWorkspaceHostProviderInvoke $context $receipt [dict get $action action_id]]}
    if {[$menu index end] eq {none}} {$menu add command -label {No owner-defined actions} -state disabled}
}
proc ::GX::sessionWorkspaceHostProviderInvoke {context receipt action} {
    if {[catch {_workspaceHostCheck $context;set id [_workspaceHostValidateReceipt $receipt];sessionWorkspaceActionInvoke $id $action} message]} {
        set parent [dict get $context parent];if {![winfo exists $parent]} {set parent .}
        tk_messageBox -parent $parent -title Workspaces -icon error -message $message
    }
}

proc ::GX::sessionWorkspaceHostNoteSave {token receipt id text} {
    if {$token ne [_workspaceHostToken]} {error {Session changed. Reopen Workspace notes.}}
    _workspaceHostValidateReceipt $receipt
    set result [noteDocumentWrite $id $text]
    # A successful Save advances this existing editor's receipt; another editor
    # still holds its previous receipt and cannot overwrite the new revision.
    set button .gxMarkupEditor.bottom.save
    if {[llength [info commands winfo]] && [winfo exists $button] && [$button cget -command] eq [list ::GX::markupEditorSave [list ::GX::sessionWorkspaceHostNoteSave $token $receipt $id]]} {
        $button configure -command [list ::GX::markupEditorSave [list ::GX::sessionWorkspaceHostNoteSave $token [_workspaceHostReceipt $id] $id]]
    }
    return $result
}
proc ::GX::sessionWorkspaceHostNoteEdit {token receipt id} {
    if {[catch {
        if {$token ne [_workspaceHostToken]} {error {Session changed. Reopen Workspace notes.}}
        _workspaceHostValidateReceipt $receipt
        noteDocumentOpen $id edit
    } message]} {tk_messageBox -parent . -title {Workspace notes} -icon error -message $message}
}
