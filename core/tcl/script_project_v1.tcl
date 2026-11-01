# SPDX-License-Identifier: GPL-3.0-or-later
# Subordinate of SCRIPT_EXECUTION_API_v1; no independent Registry or Job owner.
proc ::GX::scriptProjectCommand {operation args} {
    return [list [runtimeToolResolve python] -B [file join $::GX::scriptDir core python script_project.py] $operation {*}$args]
}
proc ::GX::scriptProjectVerify {root} {return [exec {*}[scriptProjectCommand verify $root]]}
proc ::GX::scriptRegistryReadChosenSource {path} {
    # Trusted host chooser only. No Script Bridge/native producer operation
    # grants arbitrary file reads; the admitted Library keeps this path in CORE.
    if {[file pathtype $path] ne {absolute} || [regexp {[\x00]} $path]} {error {Choose an absolute ordinary source file}}
    return [exec {*}[scriptProjectCommand read_external $path]]
}
proc ::GX::scriptProjectCopy {root destination} {return [exec {*}[scriptProjectCommand copy $root $destination]]}
proc ::GX::scriptRegistryProjectFiles {metadata} {
    return [exec {*}[scriptProjectCommand read [file dirname [dict get $metadata project_manifest]] [dict get $metadata project_sha256]]]
}
proc ::GX::scriptProjectWrite {dir language entrypoint files} {
    if {[catch {dict size $files}]} {error {Project sources must be path-to-UTF-8-text dictionary}}
    set json {}
    dict for {path code} $files {
        # JSON strings are represented entirely as Unicode escapes to keep this
        # bridge independent of host JSON packages and never interpolate code.
        set escaped {};foreach char [split $path {}] {scan $char %c n;append escaped [format {\u%04x} $n]}
        lappend json "\"$escaped\":\"[binary encode hex [encoding convertto utf-8 $code]]\""
    }
    set pending [file join $dir project-revisions pending-[pid]-[clock clicks]]
    set result [exec {*}[scriptProjectCommand write $pending $language $entrypoint] << "\{[join $json ,]\}"]
    set revision [dict get $result project_sha256]
    set target [file join $dir project-revisions $revision]
    if {[file exists $target]} {
        set existing [scriptProjectVerify $target]
        if {[dict get $existing project_sha256] ne $revision} {error {Existing project revision differs}}
        file delete -force -- $pending
    } else {file rename -- $pending $target}
    return [scriptProjectVerify $target]
}
proc ::GX::scriptRegistryProjectSave {scope id name language entrypoint files {options {}} {session {}}} {
    set options [dict remove $options record_sha256 owner_context]
    set dir [scriptRegistryPath $scope $id $session]
    if {[file exists $dir]} {error {Script identity already exists}}
    set metadata [scriptRegistryValidate [dict merge [scriptRegistryDefaults] $options [dict create scope $scope id $id name $name language $language kind project revision 1]]]
    try {
        set project [scriptProjectWrite $dir $language $entrypoint $files]
        dict set metadata project_revision [dict get $project project_sha256]
        if {![dict exists $options explicit_apis]} {dict set metadata explicit_apis [dict get $metadata required_apis]}
        set saved [scriptRegistryWrite $metadata {} $session]
    } on error {message options} {
        # Only this newly created identity is ours; no user source is removed.
        if {[file exists $dir] && ![file exists [file join $dir script.ini]]} {file delete -force -- $dir}
        return -options $options $message
    }
    return $saved
}
proc ::GX::scriptRegistryProjectUpdate {scope id expectedSha metadata entrypoint files {session {}}} {
    set renames [expr {[dict exists $metadata source_authoring_renames] ? [dict get $metadata source_authoring_renames] : {}}]
    dict unset metadata source_authoring_renames
    set current [scriptRegistryRead $scope $id $session]
    if {[dict get $current kind] ne {project} || [dict get $current sha256] ne $expectedSha} {error {Project changed; reload before Save All}}
    set expected [_scriptRegistryExpectedFields $metadata]
    _scriptRegistryExpectedCheck $current $expected
    foreach key [dict keys $expected] {dict unset metadata $key}
    scriptSourceParametersMetadataValidate $current $metadata
    foreach immutable {id scope language source_scope source_id source_sha256 created_at kind source_authoring_v1 record_sha256 owner_context} {
        if {[dict exists $metadata $immutable] && [dict get $metadata $immutable] ne [dict get $current $immutable]} {error "Project $immutable cannot change"}
    }
    set dir [scriptRegistryPath $scope $id $session]
    set lock [file join $dir .project-write-lock]
    if {[catch {set handle [open $lock {WRONLY CREAT EXCL}]}]} {error {Another project update is in progress}}
    try {
        set check [scriptRegistryRead $scope $id $session]
        if {[dict get $check sha256] ne $expectedSha || [dict get $check revision] ne [dict get $current revision]} {error {Project revision changed before Save All}}
        _scriptRegistryExpectedCheck $check $expected
        set project [scriptProjectWrite $dir [dict get $current language] $entrypoint $files]
        set next [dict merge $current $metadata [dict create project_revision [dict get $project project_sha256] revision [expr {[dict get $current revision]+1}]]]
        if {[dict exists $metadata required_apis] && ![dict exists $metadata explicit_apis]} {dict set next explicit_apis [dict get $metadata required_apis]}
        set saved [scriptRegistryWrite $next {} $session $renames]
    } finally {close $handle;file delete -- $lock}
    return $saved
}
proc ::GX::scriptRegistryProjectExport {reference destination {session {}} {expected {}}} {
    if {$session eq {} && [info exists ::GX::currentSession]} {set session $::GX::currentSession}
    set m [scriptRegistryDescribe $reference $session]
    if {[dict get $m kind] ne {project}} {error {Select a Script Project}}
    _scriptRegistryExpectedCheck $m $expected
    set pinned [dict create expected_sha256 [dict get $m sha256] expected_revision [dict get $m revision] expected_record_sha256 [dict get $m record_sha256] expected_owner_context [dict get $m owner_context]]
    set lock [_scriptAuthoringLockPath $m $session];set handle {}
    set pending "${destination}.[pid].[clock clicks].pending"
    if {[file exists $destination] || [file type [file dirname $destination]] ne {directory}} {error {Choose a new Project archive destination}}
    try {
        if {[catch {set handle [open $lock {WRONLY CREAT EXCL}]}]} {error {Another source owner update is in progress}}
        set check [scriptRegistryDescribe $reference $session]
        _scriptRegistryExpectedCheck $check $pinned
        exec {*}[scriptProjectCommand export [file dirname [dict get $check project_manifest]] $pending] << $check
        _scriptRegistryExpectedCheck [scriptRegistryDescribe $reference $session] $pinned
        # Only an identity-checked complete ZIP becomes the selected result.
        # Tcl rename without -force preserves an existing destination.
        file rename -- $pending $destination
    } finally {
        if {$handle ne {}} {close $handle;file delete -- $lock}
        if {[file exists $pending]} {file delete -- $pending}
    }
    return $destination
}
proc ::GX::scriptRegistryProjectImport {scope id name archive {options {}} {session {}}} {
    if {[catch {dict size $options}]} {error {Project import options must be a dictionary}}
    set expectedLanguage {}
    if {[dict exists $options expected_language]} {
        set expectedLanguage [dict get $options expected_language]
        if {$expectedLanguage ni {Python Octave}} {error {Expected Project language must be Python or Octave}}
        dict unset options expected_language
    }
    set dir [scriptRegistryPath $scope $id $session]
    if {[file exists $dir]} {error {Script identity already exists}}
    set temporary "${dir}.[pid].[clock clicks].import"
    try {
        set p [exec {*}[scriptProjectCommand import $archive $temporary]]
        set manifest [dict get $p project_manifest]
        # The verifier owns language parsing; obtain it from the manifest via a
        # fixed expression, never from source code or executable artifact data.
        set language [exec [runtimeToolResolve python] -c {import json,sys;print(json.load(open(sys.argv[1]))['language'])} $manifest]
        if {$expectedLanguage ne {} && $language ne $expectedLanguage} {
            error "Project language '$language' does not match this $expectedLanguage editor; no Registry identity was created"
        }
        set importedOptions [dict merge [dict get $p portable_metadata] $options]
        # Admission context is not portable Script metadata, including when an
        # older archive happens to carry this newly reserved option name.
        dict unset importedOptions expected_language
        set importedPointer [_scriptAuthoringPointer $importedOptions]
        dict set importedOptions source_authoring_v1 {}
        dict set importedOptions source_scope project_import
        dict set importedOptions source_id [file tail $archive]
        dict set importedOptions source_sha256 [scriptRegistryHash $archive]
        set saved [scriptRegistryProjectSave $scope $id $name $language [dict get $p entrypoint] [scriptRegistryProjectFiles $p] $importedOptions $session]
        if {$importedPointer ne {}} {return [_scriptAuthoringClone [dict create source_authoring_v1 $importedPointer] [dict get $p portable_authoring_root] $saved $session]}
        return $saved
    } finally {foreach path [list $temporary "${temporary}.authoring"] {if {[file exists $path]} {file delete -force -- $path}}}
}
proc ::GX::scriptRegistryProjectRemove {metadata dir} {
    set contents [lsort [lmap p [glob -nocomplain -directory $dir * .*] {set n [file tail $p];if {$n in {. ..}} continue;set n}]]
    set allowed {project-revisions script.ini};if {[_scriptAuthoringPointer $metadata] ne {}} {lappend allowed authoring}
    if {$contents ne [lsort $allowed]} {error {Project directory contains unexpected content}}
    _scriptAuthoringCall $dir [dict create operation validate pointer [_scriptAuthoringPointer $metadata]]
    foreach revision [glob -nocomplain -directory [file join $dir project-revisions] * .*] {
        set n [file tail $revision];if {$n in {. ..}} continue
        if {![regexp {^[a-f0-9]{64}$} $n]} {error {Unexpected project revision directory}}
        scriptProjectVerify $revision
    }
    file delete -force -- $dir
    after idle ::GX::_scriptRegistryRefresh
}
proc ::GX::scriptSourceParametersMerge {parameters sourceParameters digest} {
    set out {}
    dict for {name descriptor} $parameters {
        if {[datasetPublicationV2DictDefault $descriptor origin registry] eq {source}} continue
        dict set out $name $descriptor
    }
    dict for {name descriptor} $sourceParameters {
        if {[dict exists $out $name]} {error "Source declaration '$name' conflicts with an editor/Registry parameter; choose distinct names"}
        dict set descriptor source_sha256 $digest
        if {![dict exists $descriptor source_file_sha256]} {dict set descriptor source_file_sha256 $digest}
        dict set out $name $descriptor
    }
    return [dict get [scriptRegistryValidate [dict create id source_parameters name Parameters scope user parameters $out]] parameters]
}
proc ::GX::scriptInvocationSchema {metadata invocationSchema} {
    set schema [dict get $metadata parameters]
    set manual [dict get [scriptRegistryValidate [dict create id invocation name Invocation scope user parameters $invocationSchema]] parameters]
    dict for {name descriptor} $manual {
        if {[dict exists $schema $name]} {error "Invocation parameter '$name' duplicates a saved declaration"}
        set type [dict get $descriptor type]
        foreach key {min max} {
            if {[dict exists $descriptor $key]} {
                set bound [dict get $descriptor $key]
                if {$type ni {integer double number} || ![string is double -strict $bound] || [catch {expr {double($bound)==double($bound) && abs(double($bound))<Inf}} finite] || !$finite} {error "Invocation parameter '$name' has an invalid $key constraint"}
            }
        }
        if {[dict exists $descriptor min] && [dict exists $descriptor max] && [dict get $descriptor min]>[dict get $descriptor max]} {error "Invocation parameter '$name' minimum exceeds maximum"}
        if {$type eq {choice}} {
            set choices [datasetPublicationV2DictDefault $descriptor values {}]
            if {[catch {llength $choices} count] || !$count || [llength [lsort -unique $choices]]!=$count} {error "Invocation parameter '$name' requires distinct choices"}
        }
        foreach key {alpha allow_inherit} {if {[dict exists $descriptor $key] && ![string is boolean -strict [dict get $descriptor $key]]} {error "Invocation parameter '$name' has an invalid $key flag"}}
        if {[dict exists $descriptor alpha] && $type ne {color}} {error {alpha requires color type}}
        dict set descriptor origin manual_invocation
        dict set schema $name $descriptor
    }
    return $schema
}
proc ::GX::scriptSourceParametersMetadataValidate {current metadata} {
    if {![dict exists $metadata parameters]} return
    dict for {name descriptor} [dict get $current parameters] {
        if {[datasetPublicationV2DictDefault $descriptor origin registry] ne {source} || ![dict exists $metadata parameters $name]} continue
        set supplied [dict get $metadata parameters $name]
        if {[scriptParameterDatasetSchema [dict create parameters [dict create $name $descriptor]]] ne [scriptParameterDatasetSchema [dict create parameters [dict create $name $supplied]]]} {
            error "Parameter '$name' is declared in source. Edit its source declaration; metadata cannot silently override it."
        }
    }
}
