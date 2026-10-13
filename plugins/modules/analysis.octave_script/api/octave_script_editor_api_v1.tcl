# GX-TXT Octave Script Workspace Viewer API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Host-independent activation/persistence layer. The optional Tk implementation
# lives under ui/ and is loaded only after a real Viewer open/rerender request.

namespace eval ::GX::OctaveScriptEditor {
    variable version 1.2.0
    variable moduleId analysis.octave_script
    variable providerId octave_script_editor
    variable documentFormat gxtxt.octave_script.document
    variable documentFormatVersion 1.0
    variable moduleRoot [file normalize [file join [file dirname [info script]] ..]]
}

proc ::GX::OctaveScriptEditor::requireSession {} {
    return [::GX::sessionInspectionCurrentSession]
}

proc ::GX::OctaveScriptEditor::_b64e {value} {
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]
}

proc ::GX::OctaveScriptEditor::_b64d {value} {
    return [encoding convertfrom utf-8 [binary decode base64 $value]]
}

proc ::GX::OctaveScriptEditor::payloadEncode {name arguments description code} {
    set name [string trim $name]
    if {$name eq ""} { set name "Untitled script" }
    return "GXTXT_OCTAVE_SCRIPT_DOCUMENT_V1\nname64=[_b64e $name]\narguments64=[_b64e $arguments]\ndescription64=[_b64e $description]\n---\n$code"
}

proc ::GX::OctaveScriptEditor::payloadDecode {payload} {
    set marker "\n---\n"
    set splitAt [string first $marker $payload]
    if {$splitAt < 0} { error "Invalid Octave Script document: missing payload separator." }
    set header [string range $payload 0 [expr {$splitAt - 1}]]
    set code [string range $payload [expr {$splitAt + [string length $marker]}] end]
    set lines [split $header "\n"]
    if {[llength $lines] < 4 || [lindex $lines 0] ne "GXTXT_OCTAVE_SCRIPT_DOCUMENT_V1"} {
        error "Invalid Octave Script document format."
    }
    set fields [dict create]
    foreach line [lrange $lines 1 end] {
        set eq [string first = $line]
        if {$eq < 1} continue
        dict set fields [string range $line 0 [expr {$eq - 1}]] [string range $line [expr {$eq + 1}] end]
    }
    foreach required {name64 arguments64 description64} {
        if {![dict exists $fields $required]} { error "Invalid Octave Script document: missing $required." }
    }
    return [dict create \
        name [_b64d [dict get $fields name64]] \
        arguments [_b64d [dict get $fields arguments64]] \
        description [_b64d [dict get $fields description64]] \
        code $code]
}

proc ::GX::OctaveScriptEditor::_ownedDocumentRead {documentId} {
    variable moduleId
    variable providerId
    variable documentFormat
    variable documentFormatVersion
    requireSession
    set full [::GX::interactiveDocumentRead $documentId]
    if {[dict get $full module_id] ne $moduleId || [dict get $full provider_id] ne $providerId} {
        error "Interactive Document '$documentId' is not owned by Octave Script Workspace."
    }
    if {[dict get $full format] ne $documentFormat || [dict get $full format_version] ne $documentFormatVersion} {
        error "Interactive Document '$documentId' uses an unsupported Octave Script format/version."
    }
    return $full
}

proc ::GX::OctaveScriptEditor::documentList {} {
    variable moduleId
    variable providerId
    requireSession
    set out {}
    foreach item [::GX::interactiveDocumentList $moduleId $providerId] {
        set id [dict get $item id]
        if {[catch {
            set full [_ownedDocumentRead $id]
            set decoded [payloadDecode [dict get $full payload]]
            dict set item name [dict get $decoded name]
            dict set item arguments [dict get $decoded arguments]
            dict set item description [dict get $decoded description]
        }]} {
            dict set item name "$id (unreadable)"
            dict set item arguments ""
            dict set item description ""
        }
        lappend out $item
    }
    return $out
}

proc ::GX::OctaveScriptEditor::documentRead {documentId} {
    set full [_ownedDocumentRead $documentId]
    return [dict merge $full [payloadDecode [dict get $full payload]]]
}

proc ::GX::OctaveScriptEditor::documentCreate {name arguments description code} {
    variable moduleId
    variable providerId
    variable documentFormat
    variable documentFormatVersion
    requireSession
    set payload [payloadEncode $name $arguments $description $code]
    return [::GX::interactiveDocumentCreate $moduleId $providerId $documentFormat $documentFormatVersion $payload]
}

proc ::GX::OctaveScriptEditor::documentUpdate {documentId expectedSha name arguments description code} {
    variable documentFormat
    variable documentFormatVersion
    set current [_ownedDocumentRead $documentId]
    if {[string trim $expectedSha] ne "" && [string tolower [dict get $current sha256]] ne [string tolower [string trim $expectedSha]]} {
        error "This script changed outside this window. Reload it before saving to avoid overwriting newer state."
    }
    set payload [payloadEncode $name $arguments $description $code]
    return [::GX::interactiveDocumentUpdate $documentId $payload $documentFormat $documentFormatVersion]
}

proc ::GX::OctaveScriptEditor::documentDelete {documentId expectedSha} {
    set current [_ownedDocumentRead $documentId]
    if {[string trim $expectedSha] ne "" && [string tolower [dict get $current sha256]] ne [string tolower [string trim $expectedSha]]} {
        error "This script changed outside this window. Reload it before deleting."
    }
    return [::GX::interactiveDocumentDelete $documentId]
}

# Registered scripts are the executable identity used by Library, Explorer and
# Analysis. Legacy documents remain readable until the user converts one.
proc ::GX::OctaveScriptEditor::workspaceList {} {
    set out {}
    foreach m [::GX::scriptRegistryList] {
        if {[dict get $m language] ne "Octave"} continue
        dict set m reference "[dict get $m scope]:[dict get $m id]"
        lappend out $m
    }
    foreach d [documentList] {
        dict set d reference "legacy:[dict get $d id]"
        dict set d scope legacy
        lappend out $d
    }
    return $out
}
proc ::GX::OctaveScriptEditor::workspaceRead {reference} {
    if {[string match legacy:* $reference]} {
        set d [documentRead [string range $reference 7 end]]
        dict set d reference $reference
        dict set d scope legacy
        dict set d script_id ""
        return $d
    }
    set m [::GX::scriptRegistryDescribe $reference]
    if {[dict get $m language] ne "Octave"} {error "This Workspace edits Octave scripts only."}
    set ch [open [dict get $m source_path] r]
    fconfigure $ch -encoding utf-8
    try {set code [read $ch]} finally {close $ch}
    dict set m reference $reference
    dict set m script_id [dict get $m id]
    dict set m code $code
    dict set m arguments ""
    return $m
}
proc ::GX::OctaveScriptEditor::workspaceSave {reference expectedSha scope scriptId name description code} {
    if {$scope ni {user session}} {error "Choose User or Session scope."}
    ::GX::scriptRegistryId $scriptId
    if {$reference eq "" || [string match legacy:* $reference]} {
        set result [::GX::scriptRegistrySave $scope $scriptId $name $code [dict create language Octave description $description]]
    } else {
        if {$reference ne "$scope:$scriptId"} {error "Registered script scope and ID cannot change; use Save copy."}
        set result [::GX::scriptRegistryUpdate $scope $scriptId $expectedSha [dict create name $name description $description] $code]
    }
    dict set result reference "$scope:$scriptId"
    catch {::GX::sessionScriptExplorerPopulate}
    catch {::GX::scriptAnalysisRefresh}
    catch {::GX::scriptLibraryRefresh}
    return $result
}
proc ::GX::OctaveScriptEditor::workspaceDelete {reference expectedSha} {
    if {[string match legacy:* $reference]} {return [documentDelete [string range $reference 7 end] $expectedSha]}
    set current [::GX::scriptRegistryDescribe $reference]
    if {[dict get $current sha256] ne $expectedSha} {error "Script changed; reload before deleting."}
    ::GX::scriptRegistryRemove $reference
}

proc ::GX::OctaveScriptEditor::defaultCode {} {
    return {% GX-TXT Octave Script
% This is ordinary GNU Octave code with access to GX-TXT public APIs through
% OCTAVE_SCRIPT_BRIDGE_API_v1.

ctx = gxtxt_context();
disp(ctx);

% Discover script-callable public APIs:
apis = gxtxt_api_list();
fprintf('Available GX-TXT APIs: %d\n', numel(apis));

% Example pattern:
% api_id = 'SOME_PUBLIC_API_v1';
% if (!gxtxt_api_has(api_id))
%   error('Required GX-TXT API is unavailable: %s', api_id);
% endif
% description = gxtxt_api_describe(api_id);
% disp(description);
% request = struct();
% result = gxtxt_api_call(api_id, 'documented_operation', {request});
}
}

proc ::GX::OctaveScriptEditor::_ensureUi {} {
    variable moduleRoot
    if {[llength [info commands ::GX::OctaveScriptEditorUI::open]]} { return }
    set adapter [file join $moduleRoot ui octave_script_editor_ui.tcl]
    if {![file isfile $adapter]} { error "Octave Script Workspace UI adapter is missing: $adapter" }
    source $adapter
    if {![llength [info commands ::GX::OctaveScriptEditorUI::open]]} {
        error "Octave Script Workspace UI adapter did not register its open command."
    }
}

proc ::GX::OctaveScriptEditor::_launch {} {
    requireSession
    _ensureUi
    return [::GX::OctaveScriptEditorUI::open]
}

proc ::GX::OctaveScriptEditor::viewerDispatch {action scene} {
    switch -- $action {
        open - rerender { return [_launch] }
        default { error "Unsupported Octave Script Workspace viewer action '$action'." }
    }
}

::GX::viewerBackendRegister octave_script_editor_tk ::GX::OctaveScriptEditor::viewerDispatch
