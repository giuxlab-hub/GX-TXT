# SPDX-License-Identifier: GPL-3.0-or-later
# Additive packaged-function preparation on the existing Script Job/Supervisor.
proc ::GX::_scriptModuleProvidedAdmission {id api operation argumentsJson} {
    if {![moduleIsEnabled $id]} {error {Provided Script Module is disabled}}
    set info [scriptModuleDescriptor $id];set descriptor [dict get $info descriptor]
    if {$api ni [splitList [descriptorValue $descriptor public_apis ids {}]] || [descriptorValue $descriptor public_api.$api api_version {}] eq {}} {error {Script Module does not provide this admitted API}}
    set source [file join $::GX::scriptDir core python gxtxt_script_provided_runtime.py]
    set result [exec [runtimeToolRequired python] -B $source inspect [dict get $info root] $id $api $operation << $argumentsJson]
    if {[descriptorValue $descriptor public_api.$api api_version {}] ne [dict get $result operation_schema api_version]} {error {Provided API version disagrees with its descriptor}}
    set after [scriptModuleDescriptor $id]
    if {[dict get $after bundle_inventory_sha256] ne [dict get $info bundle_inventory_sha256] || [sha256File [moduleField $id descriptor]] ne [dict get $result pins descriptor_sha256]} {error {Provided Script Module changed during admission}}
    dict set result module_info $after
    return $result
}
proc ::GX::_scriptModuleProvidedInvocation {id api operation argumentsJson} {
    set admitted [_scriptModuleProvidedAdmission $id $api $operation $argumentsJson]
    return [dict create module_id $id api_id $api operation $operation arguments_json $argumentsJson expected [dict get $admitted pins]]
}
proc ::GX::scriptModuleProvidedApiInvokeJson {id api operation argumentsJson} {
    set session [_sessionInspectionRequire $::GX::currentSession]
    set lifetime [dict get [datasetCatalogSnapshot] session_token]
    set invocation [_scriptModuleProvidedInvocation $id $api $operation $argumentsJson]
    set job [scriptJobSubmit package:$id {} [dict create session $session package_invocation $invocation]]
    set terminal [scriptJobWait [dict get $job id] 60]
    if {[dict get $terminal state] ne {COMPLETED}} {error "Provided API Job [dict get $terminal state]: [datasetPublicationV2DictDefault $terminal error {}]"}
    if {$::GX::currentSession eq {} || [file normalize $::GX::currentSession] ne $session || [dict get [datasetCatalogSnapshot] session_token] ne $lifetime} {error {Provided API belongs to a previous Session lifetime}}
    # Re-admit the exact package before returning a completed result. A disabled
    # or replaced module never inherits an older successful result receipt.
    set current [_scriptModuleProvidedAdmission $id $api $operation $argumentsJson]
    if {[dict get $current pins] ne [dict get $invocation expected]} {error {Provided Script Module changed during execution}}
    if {[dict get $current language] eq {Octave}} {
        exec [runtimeToolRequired python] -B [file join $::GX::scriptDir core python gxtxt_script_provided_runtime.py] read_octave_result [dict get $terminal runtime]
    }
    set path [file join [dict get $terminal output_dir] provided_api_result.json]
    if {![file isfile $path] || [file type $path] eq {link} || [file size $path]>1048576} {error {Provided function did not produce its bounded result receipt}}
    set f [open $path rb];try {set raw [read $f]} finally {close $f}
    set text [encoding convertfrom utf-8 $raw]
    if {[encoding convertto utf-8 $text] ne $raw} {error {Provided function receipt is not exact UTF-8}}
    set typed [nativeWorkspaceJsonDecode $text]
    if {[lindex $typed 0] ne {object}} {error {Provided function receipt requires an object}}
    set receipt [nativeWorkspaceDecode $typed]
    foreach {key value} [list schema gxtxt.script_provided_result.v1 module_id $id api_id $api operation $operation] {
        if {![dict exists $receipt $key] || [dict get $receipt $key] ne $value} {error {Provided result identity differs from its admitted invocation}}
    }
    set pins [dict get $receipt pins]
    if {[lsort [dict keys $pins]] ne [lsort [dict keys [dict get $invocation expected]]]} {error {Provided result source pins differ}}
    dict for {key value} [dict get $invocation expected] {if {[dict get $pins $key] ne $value} {error {Provided result source identity differs}}}
    return [_viewerWorkspaceTypedJson [dict get [lindex $typed 1] result]]
}

proc ::GX::_scriptProvidedTyped {spec value} {
    switch -- [dict get $spec kind] {
        object {
            if {[catch {dict size $value}]} {error {Provided object requires a dictionary}}
            set fields {};set names {}
            foreach field [dict get $spec fields] {
                set name [dict get $field name];lappend names $name
                if {[dict exists $value $name]} {set item [dict get $value $name]
                } elseif {[dict get $field required]} {error "Missing provided field '$name'"
                } else {set item [dict get $field default]}
                dict set fields $name [_scriptProvidedTyped $field $item]
            }
            foreach name [dict keys $value] {if {$name ni $names} {error {Unknown provided object field}}}
            return [list object $fields]
        }
        array {
            if {[llength $value]>[dict get $spec max_items]} {error {Provided array exceeds its declared bound}}
            set items {};foreach item $value {lappend items [_scriptProvidedTyped [dict get $spec items] $item]}
            return [list array $items]
        }
        string {return [nativeWorkspaceEncode text $value]}
        integer {return [nativeWorkspaceEncode int $value]}
        boolean {return [nativeWorkspaceEncode bool $value]}
        number - double {return [nativeWorkspaceEncode real $value]}
        null {return [nativeWorkspaceEncode null $value]}
        default {error {Unsupported provided argument type}}
    }
}
proc ::GX::_scriptModuleProvidedOperationSchema {id api operation} {
    # A package can retain disjoint legacy Analysis wrappers alongside real
    # provided functions. Dispatch only actual immutable manifest members.
    set info [scriptModuleDescriptor $id]
    set descriptor [dict get $info descriptor]
    set path [scriptModuleSafeRelative [dict get $info root] [descriptorValue $descriptor script provided_manifest {}]]
    if {[file size $path]>1048576 || [sha256File $path] ne [descriptorValue $descriptor script provided_manifest_sha256 {}]} {error {Provided manifest changed}}
    set f [open $path rb];try {set text [encoding convertfrom utf-8 [read $f]]} finally {close $f}
    set inventory [nativeWorkspaceDecode [nativeWorkspaceJsonDecode $text]];set selected {}
    foreach op [dict get $inventory operations] {if {[dict get $op api_id] eq $api && [dict get $op id] eq $operation} {if {$selected ne {}} {error {Ambiguous provided operation}};set selected $op}}
    return $selected
}
proc ::GX::_scriptModuleProvidedTclArguments {id api operation arguments} {
    set selected [_scriptModuleProvidedOperationSchema $id $api $operation]
    if {$selected eq {}} {error {Unknown provided operation}}
    return [_viewerWorkspaceTypedJson [_scriptProvidedTyped [dict create kind object fields [dict get $selected arguments]] $arguments]]
}

proc ::GX::_scriptProvidedPythonSnapshotAudit {snapshot reference report} {
    # Only the freshly verified normal Project snapshot from Job preparation is
    # passed here. Reuse the existing nonexecuting dependency scanner unchanged.
    set verified [scriptProjectVerify [file dirname [dict get $snapshot project_manifest]]]
    if {[dict get $verified project_sha256] ne [dict get $snapshot project_sha256]} {error {Provided Python source snapshot changed before import preflight}}
    set files {};set root [dict get $verified project_root]
    foreach path [dict get $verified admitted_sources] {lappend files [_pythonAuditJsonObject [dict create path $path root $root sha256 [sha256File $path] logical_id $reference]]}
    set json [format {{"schema":"gxtxt.python_import_audit_request.v1","scope":"project","scope_identity":%s,"session_identity":%s,"truncated":false,"sources":[%s]}} [viewerDevelopmentJsonString [list $reference [dict get $verified project_sha256]]] [viewerDevelopmentJsonString $::GX::currentSession] [join $files ,]]
    return [_pythonEnvironmentAuditSync [dict create admission_json $json] $report]
}
