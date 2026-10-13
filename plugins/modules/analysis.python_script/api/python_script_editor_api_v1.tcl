# GX-TXT Python Script Workspace Viewer API v1.
# SPDX-License-Identifier: GPL-3.0-or-later
# The Script Registry owns executable source, metadata, revision and SHA-256.

namespace eval ::GX::PythonScriptEditor {
    variable moduleRoot [file normalize [file join [file dirname [info script]] ..]]
}

proc ::GX::PythonScriptEditor::workspaceList {} {
    set out {}
    foreach script [::GX::scriptRegistryList] {
        if {[dict get $script language] ne "Python"} continue
        dict set script reference "[dict get $script scope]:[dict get $script id]"
        lappend out $script
    }
    return $out
}

proc ::GX::PythonScriptEditor::workspaceRead {reference} {
    set script [::GX::scriptRegistryDescribe $reference]
    if {[dict get $script language] ne "Python"} {
        error "Python Script Workspace opens Python scripts only."
    }
    set channel [open [dict get $script source_path] r]
    fconfigure $channel -encoding binary -translation binary
    try {set bytes [read $channel]} finally {close $channel}
    set code [encoding convertfrom utf-8 $bytes]
    if {[encoding convertto utf-8 $code] ne $bytes} {
        error "Registered Python source is not valid UTF-8."
    }
    dict set script reference $reference
    dict set script code $code
    return $script
}

proc ::GX::PythonScriptEditor::workspaceSave {reference expectedSha scope scriptId name version description requiredApis parameters code} {
    if {$scope ni {user session}} {error "Choose User or Session scope."}
    ::GX::scriptRegistryId $scriptId
    set metadata [dict create language Python version $version description $description \
        required_apis $requiredApis parameters $parameters]
    if {$reference eq ""} {
        set result [::GX::scriptRegistrySave $scope $scriptId $name $code $metadata]
    } else {
        if {$reference ne "$scope:$scriptId"} {
            error "Registered script scope and ID cannot change. Use Save As to create another script."
        }
        set result [::GX::scriptRegistryUpdate $scope $scriptId $expectedSha \
            [dict merge $metadata [dict create name $name]] $code]
    }
    dict set result reference "$scope:$scriptId"
    catch {::GX::sessionScriptExplorerPopulate}
    catch {::GX::scriptAnalysisRefresh}
    catch {::GX::scriptLibraryRefresh}
    catch {::GX::scriptWorkspaceRefreshChoices}
    return $result
}

proc ::GX::PythonScriptEditor::workspaceDelete {reference expectedSha} {
    set current [::GX::scriptRegistryDescribe $reference]
    if {[dict get $current language] ne "Python"} {error "Python Script Workspace deletes Python scripts only."}
    if {[string tolower [dict get $current sha256]] ne [string tolower $expectedSha]} {
        error "Script changed since it was opened; reload before deleting."
    }
    set result [::GX::resourceLifecycleDeleteScript $reference]
    catch {::GX::sessionScriptExplorerPopulate}
    catch {::GX::scriptAnalysisRefresh}
    catch {::GX::scriptLibraryRefresh}
    catch {::GX::scriptWorkspaceRefreshChoices}
    return $result
}

proc ::GX::PythonScriptEditor::defaultCode {} {
    return {# GX-TXT Python Script
from gxtxt import gxtxt_context, gxtxt_api_list, gxtxt_api_call

ctx = gxtxt_context()
print(ctx)
print(gxtxt_api_list())
}
}

proc ::GX::PythonScriptEditor::_ensureUi {} {
    variable moduleRoot
    if {[llength [info commands ::GX::PythonScriptEditorUI::open]]} return
    set adapter [file join $moduleRoot ui python_script_editor_ui.tcl]
    if {![file isfile $adapter]} {error "Python Script Workspace UI adapter is missing: $adapter"}
    source $adapter
    if {![llength [info commands ::GX::PythonScriptEditorUI::open]]} {
        error "Python Script Workspace UI adapter did not register its open command."
    }
}

proc ::GX::PythonScriptEditor::viewerDispatch {action scene} {
    switch -- $action {
        open - rerender {
            if {$::GX::currentSession eq ""} {error "Open a Session before opening Python Script Workspace."}
            _ensureUi
            return [::GX::PythonScriptEditorUI::open]
        }
        default {error "Unsupported Python Script Workspace viewer action '$action'."}
    }
}

::GX::viewerBackendRegister python_script_editor_tk ::GX::PythonScriptEditor::viewerDispatch
