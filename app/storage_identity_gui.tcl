# SPDX-License-Identifier: GPL-3.0-or-later
# GUI state distinguishes the applied context, catalog selection and an unsaved draft.
namespace eval ::GX {variable storageUi}
proc ::GX::workflowNotice {title message {kind error} {parent .}} {
    set w .gxWorkflowNotice;catch {destroy $w};toplevel $w
    wm title $w $title;wm transient $w [winfo toplevel $parent]
    wm geometry $w 760x360;wm minsize $w 520 240
    ttk::label $w.title -text $title -font TkHeadingFont
    ttk::frame $w.body
    text $w.body.text -wrap word -width 80 -height 12 -padx 12 -pady 10
    ttk::scrollbar $w.body.scroll -command [list $w.body.text yview]
    $w.body.text configure -yscrollcommand [list $w.body.scroll set]
    $w.body.text insert end $message;$w.body.text configure -state disabled
    pack $w.body.scroll -side right -fill y;pack $w.body.text -fill both -expand 1
    ttk::button $w.close -text Close -command [list destroy $w]
    pack $w.title -anchor w -padx 12 -pady 8;pack $w.body -fill both -expand 1 -padx 8
    pack $w.close -anchor e -padx 12 -pady 8
    bind $w <Escape> [list destroy $w];bind $w <Return> [list destroy $w]
    focus $w.close;raise $w
    # No modal grab: full details can be selected/copied and the operator can
    # inspect the unchanged draft underneath. All failed writes retain it.
    return $w
}
proc ::GX::storageRoleLabel {role} {
    return [dict get {acquisition_dir Acquisition session_root {New Session root} session_open_dir {Open Session} manifest_dir Manifest export_dir Export} $role]
}
proc ::GX::storageGlobalSource {} {
    set name $::GX::workspaceProfileCurrent
    if {$name ne {} && $name in [workspaceProfileNames]} {
        set same 1
        foreach role [workspaceProfileFields] {if {$::GX::workspaceDir($role) ne $::GX::workspaceProfileCatalog($name,$role)} {set same 0}}
        if {$same} {return "Global — profile $name"}
        return "Global — directories adjusted since profile $name"
    }
    return {Global — current directories (no named profile applied)}
}
proc ::GX::storageProfilesBuild {w scope} {
    variable storageUi
    grid columnconfigure $w 1 -weight 1
    set storageUi($scope,name) {};set storageUi($scope,global) {};set storageUi($scope,mode) view
    set storageUi($scope,selected) {};set storageUi($scope,session) {};set storageUi($scope,status) {}
    ttk::label $w.title -textvariable ::GX::storageUi($scope,context) -font TkHeadingFont -anchor w
    grid $w.title -row 0 -column 0 -columnspan 4 -sticky ew -pady 5
    ttk::label $w.editor -textvariable ::GX::storageUi($scope,editor) -anchor w
    grid $w.editor -row 1 -column 0 -columnspan 4 -sticky ew -pady 3
    ttk::label $w.nl -text {Profile name:}
    ttk::entry $w.name -textvariable ::GX::storageUi($scope,name)
    grid $w.nl -row 2 -column 0 -sticky e -padx 4;grid $w.name -row 2 -column 1 -columnspan 3 -sticky ew -padx 4
    set row 3
    foreach role [workspaceProfileFields] {
        set storageUi($scope,$role) {};set storageUi($scope,origin,$role) {}
        ttk::label $w.l_$role -text [storageRoleLabel $role]
        ttk::entry $w.e_$role -textvariable ::GX::storageUi($scope,$role)
        ttk::button $w.b_$role -text {Browse…} -command [list ::GX::storageProfilesBrowse $scope $role]
        ttk::label $w.o_$role -textvariable ::GX::storageUi($scope,origin,$role) -width 27
        grid $w.l_$role -row $row -column 0 -sticky e -padx 4 -pady 2
        grid $w.e_$role -row $row -column 1 -sticky ew -padx 4 -pady 2
        grid $w.b_$role -row $row -column 2 -padx 4;grid $w.o_$role -row $row -column 3 -sticky w -padx 4
        incr row
    }
    if {$scope eq {private}} {
        ttk::frame $w.globalActions
        ttk::label $w.globalActions.label -text {Global profile:}
        ttk::combobox $w.global -textvariable ::GX::storageUi($scope,global) -state readonly -width 24
        ttk::button $w.useGlobal -text {Use global profile} -command [list ::GX::storageProfilesAction $w $scope global]
        ttk::button $w.copy -text {Create independent private copy} -command [list ::GX::storageProfilesAction $w $scope copy]
        pack $w.globalActions.label $w.global $w.useGlobal $w.copy -in $w.globalActions -side left -padx 4 -pady 4
        grid $w.globalActions -row $row -column 0 -columnspan 4 -sticky ew;incr row
    }
    ttk::frame $w.actions
    foreach {action label} [expr {$scope eq {global} ? {new New load {Edit selected} save Save apply {Save & Apply} delete Remove cancel {Cancel / Show applied}} : {new {New private} load {Edit private copy} save {Save private} apply {Save & Use private} use {Use selected private} delete Remove cancel {Cancel / Show effective}}}] {
        ttk::button $w.actions.$action -text $label -command [list ::GX::storageProfilesAction $w $scope $action]
        pack $w.actions.$action -side left -padx 3 -pady 3
    }
    grid $w.actions -row $row -column 0 -columnspan 4 -sticky ew;incr row
    ttk::label $w.status -textvariable ::GX::storageUi($scope,status) -anchor w -justify left
    grid $w.status -row $row -column 0 -columnspan 4 -sticky ew -pady 3;incr row
    ttk::label $w.catalogLabel -text [expr {$scope eq {global} ? {All global profiles — select a row to inspect/edit its five directories; selection does not apply it} : {Saved private profiles in this Session — independent from global profiles, even with the same name}}]
    grid $w.catalogLabel -row $row -column 0 -columnspan 4 -sticky w -padx 4 -pady 4;incr row
    ttk::frame $w.catalog
    ttk::treeview $w.catalog.tree -columns {name applied acquisition_dir session_root session_open_dir manifest_dir export_dir} -show headings -selectmode browse -height 4
    foreach {col text width} {name Profile 190 applied {In use} 85 acquisition_dir Acquisition 230 session_root {Session root} 230 session_open_dir {Open Session} 230 manifest_dir Manifest 230 export_dir Export 230} {
        $w.catalog.tree heading $col -text $text;$w.catalog.tree column $col -width $width -minwidth [expr {$col eq {name} ? 190 : 65}] -stretch [expr {$col eq {name}}]
    }
    ttk::scrollbar $w.catalog.sy -command [list $w.catalog.tree yview]
    ttk::scrollbar $w.catalog.sx -orient horizontal -command [list $w.catalog.tree xview]
    $w.catalog.tree configure -yscrollcommand [list $w.catalog.sy set] -xscrollcommand [list $w.catalog.sx set]
    grid columnconfigure $w.catalog 0 -weight 1;grid rowconfigure $w.catalog 0 -weight 1
    grid $w.catalog.tree -row 0 -column 0 -sticky nsew;grid $w.catalog.sy -row 0 -column 1 -sticky ns
    grid $w.catalog.sx -row 1 -column 0 -sticky ew
    grid $w.catalog -row $row -column 0 -columnspan 4 -sticky nsew -padx 4 -pady 4
    grid rowconfigure $w $row -weight 1
    bind $w.catalog.tree <<TreeviewSelect>> [list ::GX::storageProfilesSelect $w $scope]
    bind $w <Map> [list ::GX::storageProfilesRefresh $w $scope]
    storageProfilesRefresh $w $scope
}
proc ::GX::storageProfilesValues {scope} {
    set values {};foreach role [workspaceProfileFields] {dict set values $role $::GX::storageUi($scope,$role)};return $values
}
proc ::GX::storageProfilesSetMode {w scope mode} {
    set ::GX::storageUi($scope,mode) $mode
    set state [expr {$mode eq {edit} ? {normal} : {readonly}}]
    $w.name configure -state $state
    foreach role [workspaceProfileFields] {$w.e_$role configure -state $state;$w.b_$role configure -state [expr {$mode eq {edit} ? {normal} : {disabled}}]}
    foreach action {save apply} {$w.actions.$action configure -state [expr {$mode eq {edit} ? {normal} : {disabled}}]}
}
proc ::GX::storageProfilesSelect {w scope} {
    set selected [$w.catalog.tree selection]
    if {[llength $selected]!=1} return
    set name [lindex [$w.catalog.tree item [lindex $selected 0] -values] 0]
    if {$::GX::storageUi($scope,selected) eq $name} return
    set ::GX::storageUi($scope,selected) $name
    if {$scope eq {global}} {storageProfilesPerform $w $scope load} else {storageProfilesRefresh $w $scope}
}
proc ::GX::storageProfilesBrowse {scope role} {
    set path [_workspaceChooseDirectory $role -title "[storageRoleLabel $role] — choose or create directory"]
    if {$path ne {}} {set ::GX::storageUi($scope,$role) $path}
}
proc ::GX::storageProfilesRefresh {w scope} {
    variable storageUi
    if {![llength [info commands winfo]] || ![winfo exists $w]} return
    set global [storageGlobalSource];set active {};set profiles {}
    if {$scope eq {private}} {
        $w.global configure -values [workspaceProfileNames]
        if {$storageUi($scope,session) ne $::GX::currentSession} {
            set storageUi($scope,session) $::GX::currentSession;set storageUi($scope,selected) {};set storageUi($scope,mode) view;set storageUi($scope,name) {};set storageUi($scope,status) {}
        }
        if {$::GX::currentSession ne {}} {set data [sessionStorageProfilesRead];set active [dict get $data active];set profiles [dict get $data profiles]}
    } else {
        workspaceProfilesLoadCatalog
        foreach name [workspaceProfileNames] {foreach role [workspaceProfileFields] {dict set profiles $name $role $::GX::workspaceProfileCatalog($name,$role)}}
        set active $::GX::workspaceProfileCurrent
    }
    set tree $w.catalog.tree
    # Avoid rebuilding unchanged catalogs: TreeviewSelect is queued asynchronously.
    set fingerprint [list $profiles $active]
    if {![info exists storageUi($scope,catalog)] || $storageUi($scope,catalog) ne $fingerprint} {
        set storageUi($scope,catalog) $fingerprint;$tree delete [$tree children {}]
        set i 0;dict for {name values} $profiles {
            set id p[incr i];set row [list $name [expr {$name eq $active ? {Applied} : {}}]]
            foreach role [workspaceProfileFields] {lappend row [dict get $values $role]}
            $tree insert {} end -id $id -values $row
            if {$name eq $storageUi($scope,selected)} {$tree selection set $id}
        }
    }
    foreach row [$tree children {}] {
        if {[lindex [$tree item $row -values] 0] eq $storageUi($scope,selected) && [$tree selection] ne $row} {$tree selection set $row}
    }
    set context $global;set privateCount 0;set fallbackCount 0
    foreach role [workspaceProfileFields] {
        set effective [expr {$scope eq {global} ? [workspaceInitialDir_before_storage082 $role] : [workspaceInitialDir $role]}];set source Global
        if {$scope eq {private} && $active ne {}} {
            set own [sessionStorageProfileEffective $role]
            if {$own ne {} && [file isdirectory $own]} {set source Private;incr privateCount} else {set source {Global fallback};incr fallbackCount}
        }
        if {$storageUi($scope,mode) eq {view}} {set storageUi($scope,$role) $effective;set storageUi($scope,origin,$role) $source}
    }
    if {$scope eq {private}} {
        if {$::GX::currentSession eq {}} {set context {No Session open — global directories shown; open a Session to create private profiles}}
        if {$active ne {}} {
            if {$fallbackCount==0} {set context "Session private — profile $active"} else {set context "Mixed / per-role fallback — private $active; $global"}
        }
    }
    set storageUi($scope,context) $context
    if {$storageUi($scope,mode) eq {view}} {
        set storageUi($scope,name) $active
        set storageUi($scope,editor) {Effective directories (read-only). Select Edit or New to change a saved profile.}
        storageProfilesSetMode $w $scope view
    }
    if {[dict size $profiles]==0 && $storageUi($scope,status) eq {}} {set storageUi($scope,status) [expr {$scope eq {global} ? {No saved global profiles. New creates a named profile; Save and Apply are separate.} : {No private profiles. Use global directly, or create an independent private copy.}}]}
    if {[dict size $profiles]>0 && $storageUi($scope,status) eq {}} {set storageUi($scope,status) "[dict size $profiles] saved $scope profiles. Select a row to use or edit it."}
}
proc ::GX::storageProfilesAction {w scope action} {
    if {[catch {storageProfilesPerform $w $scope $action} err]} {
        workflowNotice {Storage Profiles — operation failed} "Operation: $action\nScope: $scope\n\n$err\n\nThe operation did not complete. Check the applied context before retrying. Your editor values remain available. Correct the value or Cancel / Show effective to return." error $w
    }
}
proc ::GX::storageProfilesCheckDirectories {values} {
    dict for {role path} $values {
        if {$path eq {}} continue
        if {[string match @session/* $path]} {set path [file join $::GX::currentSession [string range $path 9 end]]}
        if {![file isdirectory $path]} {error "[storageRoleLabel $role] directory is unavailable:\n$path\n\nChoose an existing directory with Browse, create it first, or leave this role blank to use its global fallback."}
    }
}
proc ::GX::storageProfilesPerform {w scope action} {
    variable storageUi
    if {$scope eq {private}} {sessionStorageProfilesPath}
    set name [string trim $storageUi($scope,name)]
    if {$action eq {new}} {
        set storageUi($scope,name) {};set storageUi($scope,selected) {}
        $w.catalog.tree selection remove [$w.catalog.tree selection]
        foreach role [workspaceProfileFields] {set storageUi($scope,$role) {};set storageUi($scope,origin,$role) [expr {$scope eq {private} ? {Blank → global fallback} : {Global profile draft}}]}
        set storageUi($scope,editor) "Editing a new $scope profile — existing applied directories remain in use until Apply."
        set storageUi($scope,status) {};storageProfilesSetMode $w $scope edit;focus $w.name;return
    }
    if {$action eq {cancel}} {set storageUi($scope,name) {};set storageUi($scope,mode) view;set storageUi($scope,status) {Draft cancelled; applied directories shown.};storageProfilesRefresh $w $scope;return}
    if {$action eq {copy}} {
        set source $storageUi($scope,global)
        if {$source eq {}} {error {Select a global profile to copy.}}
        if {$name eq {} || $storageUi($scope,mode) eq {view}} {set name $source}
        set data [sessionStorageProfilesRead]
        if {[dict exists $data profiles $name]} {error "Private profile '$name' already exists in this Session.\n\nIt was not overwritten. Select that private row and Edit private copy, or choose New private and enter a different name before copying. Global and private profiles may share a name."}
        sessionStorageProfileCopyGlobal $source $name
        set storageUi($scope,selected) $name;set storageUi($scope,name) $name
        set action load;set storageUi($scope,status) "Independent private copy '$name' created. Edit if needed, then Save & Use private. Global '$source' is unchanged."
    }
    if {$action eq {load}} {
        if {$storageUi($scope,selected) ne {}} {set name $storageUi($scope,selected)}
        if {$scope eq {global}} {
            workspaceProfilesLoadCatalog
            if {$name ni [workspaceProfileNames]} {error {Select a saved global profile row first.}}
            set values {};foreach role [workspaceProfileFields] {dict set values $role $::GX::workspaceProfileCatalog($name,$role)}
        } else {
            set data [sessionStorageProfilesRead]
            if {![dict exists $data profiles $name]} {error {Select a saved private profile row first.}}
            set values [dict get $data profiles $name]
        }
        set storageUi($scope,name) $name;set storageUi($scope,selected) $name
        foreach role [workspaceProfileFields] {set storageUi($scope,$role) [dict get $values $role];set storageUi($scope,origin,$role) [expr {$scope eq {private} ? {Private; blank → global} : {Saved global value}}]}
        set storageUi($scope,editor) "Editing $scope profile '$name' — saving does not switch the applied profile."
        if {$scope eq {private} && [dict get $data active] eq $name} {set storageUi($scope,editor) "Editing active private profile '$name' — Save updates its directories; global values stay unchanged."}
        storageProfilesSetMode $w $scope edit
    } elseif {$action in {save apply}} {
        set values [storageProfilesValues $scope];sessionStorageProfileValidate $name $values
        set exists [expr {$scope eq {global} ? $name in [workspaceProfileNames] : [dict exists [sessionStorageProfilesRead] profiles $name]}]
        if {$exists && $storageUi($scope,selected) ne $name} {error "A $scope profile named '$name' already exists.\n\nSelect that row and Edit it to update it, or use a different name. The existing profile was not overwritten."}
        if {$action eq {apply}} {storageProfilesCheckDirectories $values}
        if {$scope eq {private}} {
            sessionStorageProfileSave $name $values
            if {$action eq {apply}} {sessionStorageProfileApply $name}
        } else {
            foreach role [workspaceProfileFields] {if {[string match @session/* [dict get $values $role]]} {error {Global profiles require absolute directories; @session paths belong to private profiles.}}}
            workspaceProfileSave $name $values
            if {$action eq {apply}} {
                workspaceProfileApply $name
                if {$::GX::currentSession ne {}} {sessionStorageProfileApply {}}
            }
        }
        set storageUi($scope,selected) $name;set storageUi($scope,status) "Saved $scope profile '$name'.[expr {$action eq {apply} ? { Applied; effective directories shown.} : { Applied directories were not changed.}}]"
        set storageUi($scope,editor) "Editing saved $scope profile '$name' — Apply is explicit."
        if {$scope eq {private} && [dict get [sessionStorageProfilesRead] active] eq $name} {
            _sessionStorageProfileRuntimeRefresh;set storageUi($scope,mode) view
            set storageUi($scope,status) "Saved active private profile '$name'; effective directories updated. Global values are unchanged."
        }
        if {$action eq {apply}} {set storageUi($scope,mode) view}
    } elseif {$action eq {use}} {
        set name $storageUi($scope,selected);set data [sessionStorageProfilesRead]
        if {![dict exists $data profiles $name]} {error {Select a saved private profile row first.}}
        storageProfilesCheckDirectories [dict get $data profiles $name];sessionStorageProfileApply $name
        set storageUi($scope,mode) view;set storageUi($scope,status) "Using private profile '$name'."
    } elseif {$action eq {global}} {
        set name $storageUi($scope,global)
        if {$name eq {} || $name ni [workspaceProfileNames]} {error {Select a saved global profile first. No private copy is required.}}
        set values {};foreach role [workspaceProfileFields] {dict set values $role $::GX::workspaceProfileCatalog($name,$role)}
        storageProfilesCheckDirectories $values;workspaceProfileApply $name;sessionStorageProfileApply {}
        set storageUi($scope,mode) view;set storageUi($scope,name) {};set storageUi($scope,status) "Using global '$name' directly; private copies remain independent."
    } elseif {$action eq {delete}} {
        set name $storageUi($scope,selected)
        if {$name eq {}} {error {Select a saved profile row to remove.}}
        if {[tk_messageBox -parent $w -type yesno -default no -icon question -title {Remove Storage Profile} -message "Remove the $scope profile '$name'?\nDirectories and scientific files will remain intact."] ne {yes}} return
        if {$scope eq {global}} {workspaceProfileDelete $name} else {sessionStorageProfileDelete $name}
        set storageUi($scope,selected) {};set storageUi($scope,name) {};set storageUi($scope,mode) view;set storageUi($scope,status) "Removed $scope profile '$name'; directory contents retained."
    } elseif {$action eq {fallback}} {sessionStorageProfileApply {};set storageUi($scope,mode) view}
    storageProfilesRefresh $w $scope
    storageProfilesRefresh .top.nb.sessionfiles.config.pages.storage private
    if {$scope eq {private}} {storageProfilesRefresh .top.nb.configuration.sections.storage.profiles global}
}
proc ::GX::storageDefaultsToggle {} {
    set parent .top.nb.configuration.sections.storage
    set ::GX::storageUi(defaultsVisible) [expr {!$::GX::storageUi(defaultsVisible)}]
    foreach child $::GX::storageUi(defaultWidgets) {
        if {$::GX::storageUi(defaultsVisible)} {grid $child} else {grid remove $child}
    }
    $parent.defaultsToggle configure -text [expr {$::GX::storageUi(defaultsVisible) ? {Hide Storage defaults & cache settings} : {Show Storage defaults & cache settings…}}]
}
proc ::GX::installationIdentityGuiRefresh {} {
    set w .top.nb.configuration.sections.identity
    set data [installationIdentityInfo]
    $w.current configure -text "Current installation ID: [dict get $data current]\nAuthority: [dict get $data authority]\nStatus: [dict get $data diagnostic]"
    $w.history delete [$w.history children {}]
    foreach item [dict get $data history] {$w.history insert {} end -values [list [dict get $item order] [dict get $item id] [dict get $item date] [dict get $item reason]]}
}
proc ::GX::installationIdentityGuiRotate {} {
    set w .top.nb.configuration.sections.identity
    if {[string trim $::GX::storageUi(rotationReason)] eq {}} {workflowNotice {Installation identity} {Enter a reason before rotating the installation ID.};return}
    if {[tk_messageBox -parent $w -icon warning -type yesno -default no -title {Rotate installation ID} -message {Generate a new installation ID? The current ID will be retired in retained history. Existing object creators remain unchanged.}] ne {yes}} return
    if {[catch {::GX::InstallationIdentity::host rotate $::GX::storageUi(rotationReason)} err]} {workflowNotice {Installation identity — rotation failed} $err;return}
    installationIdentityGuiRefresh
}
proc ::GX::currentSessionDisplayName {} {
    if {$::GX::currentSession eq {}} {return {No Session open}}
    if {[info exists ::GX::cfg(experiment_name)] && [string trim $::GX::cfg(experiment_name)] ne {}} {return $::GX::cfg(experiment_name)}
    return [file tail $::GX::currentSession]
}
rename ::GX::updateSessionUi ::GX::updateSessionUi_before_storage082
proc ::GX::updateSessionUi {} {
    set result [updateSessionUi_before_storage082]
    set ::GX::ui(sessionPath) [currentSessionDisplayName]
    if {[llength [info commands winfo]] && [winfo exists .top.nb.sessionfiles.bar.projectHome]} {
        .top.nb.sessionfiles.bar.projectHome configure -state [expr {$::GX::currentSession ne {} && [projectExists [projectCurrentId]] ? {normal} : {disabled}}]
    }
    if {[llength [info commands winfo]]} {catch {storageProfilesRefresh .top.nb.sessionfiles.config.pages.storage private}}
    return $result
}
rename ::GX::launchGui ::GX::launchGui_before_storage082
proc ::GX::launchGui {} {
    workspaceStorageRestore
    launchGui_before_storage082
    # Keep the established settings widgets and their controller. Folding only
    # this Storage cluster gives the requested profile catalog useful height.
    set ::GX::storageUi(defaultWidgets) [grid slaves .top.nb.configuration.sections.storage]
    set ::GX::storageUi(defaultsVisible) 0
    foreach child $::GX::storageUi(defaultWidgets) {grid remove $child}
    ttk::button .top.nb.configuration.sections.storage.defaultsToggle -text {Show Storage defaults & cache settings…} -command ::GX::storageDefaultsToggle
    grid .top.nb.configuration.sections.storage.defaultsToggle -row 7 -column 0 -columnspan 4 -sticky w -padx 8 -pady 4
    set w .top.nb.configuration.sections.storage.profiles
    ttk::labelframe $w -text {Storage Profiles};storageProfilesBuild $w global
    grid $w -row 8 -column 0 -columnspan 4 -sticky nsew -padx 6 -pady 4
    grid rowconfigure .top.nb.configuration.sections.storage 8 -weight 1
    set w .top.nb.sessionfiles.config.pages.storage
    ttk::frame $w;.top.nb.sessionfiles.config.pages add $w -text {Storage Profiles}
    storageProfilesBuild $w private
    foreach key {wssep wslab ws wsload wsedit} {if {[winfo exists .top.sessionbar.$key]} {destroy .top.sessionbar.$key}}
    # The old top-bar combobox no longer exists. Catalog projection is refreshed
    # by workspaceProfilesRefreshGui, not by configuring this editor Entry.
    unset -nocomplain ::GX::ui(workspaceProfileCombo)
    set w .top.nb.configuration.sections.identity
    ttk::frame $w;.top.nb.configuration.sections add $w -text {Installation Identity}
    ttk::label $w.current -wraplength 850 -justify left
    ttk::treeview $w.history -columns {order id date reason} -show headings
    foreach {key width} {order 60 id 300 date 170 reason 240} {$w.history heading $key -text [string totitle $key];$w.history column $key -width $width}
    ttk::scrollbar $w.scroll -command [list $w.history yview];$w.history configure -yscrollcommand [list $w.scroll set]
    set ::GX::storageUi(rotationReason) {}
    ttk::label $w.reasonLabel -text {Rotation reason:};ttk::entry $w.reason -textvariable ::GX::storageUi(rotationReason)
    ttk::button $w.rotate -text {Rotate / Regenerate installation ID…} -command ::GX::installationIdentityGuiRotate
    grid columnconfigure $w 0 -weight 1;grid rowconfigure $w 1 -weight 1
    grid $w.current -row 0 -column 0 -columnspan 2 -sticky ew -padx 6 -pady 6
    grid $w.history -row 1 -column 0 -sticky nsew;grid $w.scroll -row 1 -column 1 -sticky ns
    grid $w.reasonLabel -row 2 -column 0 -sticky w;grid $w.reason -row 3 -column 0 -sticky ew
    grid $w.rotate -row 4 -column 0 -sticky w -pady 6
    installationIdentityGuiRefresh
    set order {acq preview channels modules analysis run results graphs print sessionfiles projects viewers configuration help}
    # Installation Identity is appended here, after the base Configuration
    # builder. Append Appearance at this actual final owner to keep it rightmost.
    configurationAppearanceBuild
    set index 0
    foreach tab $order {if {[lsearch -exact [.top.nb tabs] .top.nb.$tab]>=0} {.top.nb insert $index .top.nb.$tab;incr index}}
    plotsToolbarOrganize
    updateSessionUi
}
