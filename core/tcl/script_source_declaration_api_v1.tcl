# GX-TXT Script Analysis Sources declaration API v1.
# SPDX-License-Identifier: GPL-3.0-or-later
# The Python parser reads one comment metadata line; it never executes scripts.
namespace eval ::GX {
    variable scriptSourceDeclarationSignature
    variable scriptSourceDeclarationRows
    variable scriptSourceDeclarationError
}

proc ::GX::scriptAnalysisResetSessionState {session} {
    variable scriptSourceDeclarationSignature
    variable scriptSourceDeclarationRows
    variable scriptSourceDeclarationError
    foreach id {analysis.python_script analysis.octave_script} {
        set scriptSourceDeclarationSignature($id) [list [file normalize $session] ""]
        set scriptSourceDeclarationRows($id) {}
        set scriptSourceDeclarationError($id) ""
        analysisSourcesResetModule $id
    }
}

proc ::GX::scriptSourceDeclarationDiscover {sourcePath} {
    set parser [file join $::GX::scriptDir core python script_source_declaration_v1.py]
    set output [exec [runtimeToolResolve python] -B $parser --tsv $sourcePath]
    set rows {}
    foreach line [split [string trimright $output "\n"] "\n"] {
        if {$line eq ""} continue
        set fields [split $line "\t"]
        if {[llength $fields] != 6} { error "Static declaration parser returned an invalid source row." }
        lassign $fields source label required contracts purpose preferred
        lappend rows [dict create id $source label $label required $required \
            contracts [splitList $contracts] purpose $purpose preferred_dataset $preferred]
    }
    return $rows
}

proc ::GX::scriptAnalysisDeclarationRows {id} {
    variable scriptSourceDeclarationRows
    if {$id ni {analysis.python_script analysis.octave_script}} { return {} }
    if {[info exists scriptSourceDeclarationRows($id)]} { return $scriptSourceDeclarationRows($id) }
    return {}
}

proc ::GX::scriptAnalysisDeclarationFor {id source} {
    foreach item [scriptAnalysisDeclarationRows $id] {
        if {[dict get $item id] eq $source} { return $item }
    }
    return {}
}

proc ::GX::scriptAnalysisApplyDeclarations {id} {
    variable moduleCfg
    variable moduleAnalysisSource
    variable moduleAnalysisSourceCount
    variable scriptSourceDeclarationSignature
    variable scriptSourceDeclarationRows
    variable scriptSourceDeclarationError
    if {$id ni {analysis.python_script analysis.octave_script}} { return 0 }
    set reference [expr {[info exists moduleCfg($id,registered_script)] ? [string trim $moduleCfg($id,registered_script)] : ""}]
    set session [expr {[info exists ::GX::currentSession] && $::GX::currentSession ne "" ? [file normalize $::GX::currentSession] : ""}]
    set signature [list $session $reference]
    set rows {}
    set scriptSourceDeclarationError($id) ""
    if {$reference ne ""} {
        if {[catch {
            set metadata [scriptRegistryDescribe $reference]
            lappend signature [dict get $metadata sha256]
            set rows [scriptSourceDeclarationDiscover [dict get $metadata source_path]]
        } reason]} {
            set scriptSourceDeclarationError($id) $reason
            lappend signature unavailable
        }
    }
    if {[info exists scriptSourceDeclarationSignature($id)] && $scriptSourceDeclarationSignature($id) eq $signature} { return 0 }
    set previous [dict create]
    # Dataset bindings belong to a Session even when two Sessions own identical
    # script references and source bytes.
    if {[info exists moduleAnalysisSourceCount($id)] &&
        [info exists scriptSourceDeclarationSignature($id)] &&
        [lindex $scriptSourceDeclarationSignature($id) 0] eq $session} {
        for {set r 1} {$r <= $moduleAnalysisSourceCount($id)} {incr r} {
            if {[info exists moduleAnalysisSource($id,$r,id)] && [info exists moduleAnalysisSource($id,$r,dataset_id)]} {
                dict set previous $moduleAnalysisSource($id,$r,id) $moduleAnalysisSource($id,$r,dataset_id)
            }
        }
    }
    set scriptSourceDeclarationRows($id) $rows
    set scriptSourceDeclarationSignature($id) $signature
    analysisSourcesResetModule $id
    if {![llength $rows]} { set rows [list [dict create id primary preferred_dataset ""]] }
    foreach item $rows {
        set source [dict get $item id]
        set dataset [expr {[dict exists $previous $source] ? [dict get $previous $source] : ""}]
        if {$dataset eq "" && [dict get $item preferred_dataset] ne ""} {
            set candidate [dict get $item preferred_dataset]
            if {![catch {set kind [datasetField $candidate kind ""]}] && $kind ne "" &&
                [contractSatisfiesAny $kind [dict get $item contracts]]} { set dataset $candidate }
        }
        analysisSourceAppendRow $id $source $dataset
    }
    return 1
}

rename ::GX::ensureModuleAnalysisSourceDefaults ::GX::ensureModuleAnalysisSourceDefaults_v006
proc ::GX::ensureModuleAnalysisSourceDefaults {{onlyId ""}} {
    ::GX::ensureModuleAnalysisSourceDefaults_v006 $onlyId
    foreach id {analysis.python_script analysis.octave_script} {
        if {$onlyId ne "" && $onlyId ne $id} continue
        catch {::GX::scriptAnalysisApplyDeclarations $id}
    }
}

rename ::GX::moduleAnalysisSourceDeclaredIds ::GX::moduleAnalysisSourceDeclaredIds_v006
proc ::GX::moduleAnalysisSourceDeclaredIds {id} {
    set rows [scriptAnalysisDeclarationRows $id]
    if {[llength $rows]} { return [lmap item $rows {dict get $item id}] }
    return [::GX::moduleAnalysisSourceDeclaredIds_v006 $id]
}

rename ::GX::moduleAnalysisSourcesDynamic ::GX::moduleAnalysisSourcesDynamic_v006
proc ::GX::moduleAnalysisSourcesDynamic {id} {
    if {[llength [scriptAnalysisDeclarationRows $id]]} { return 0 }
    return [::GX::moduleAnalysisSourcesDynamic_v006 $id]
}

rename ::GX::analysisSourceIsRequired ::GX::analysisSourceIsRequired_v006
proc ::GX::analysisSourceIsRequired {id source} {
    set declaration [scriptAnalysisDeclarationFor $id $source]
    if {$declaration ne ""} { return [dict get $declaration required] }
    if {$id in {analysis.python_script analysis.octave_script} && $source eq "primary"} { return 0 }
    return [::GX::analysisSourceIsRequired_v006 $id $source]
}

rename ::GX::analysisSourceExpectedContracts ::GX::analysisSourceExpectedContracts_v006
proc ::GX::analysisSourceExpectedContracts {id source} {
    set declaration [scriptAnalysisDeclarationFor $id $source]
    if {$declaration ne ""} { return [dict get $declaration contracts] }
    return [::GX::analysisSourceExpectedContracts_v006 $id $source]
}

rename ::GX::analysisSourceValidateModule ::GX::analysisSourceValidateModule_v006
proc ::GX::analysisSourceValidateModule {id} {
    ::GX::scriptAnalysisApplyDeclarations $id
    if {$id in {analysis.python_script analysis.octave_script} &&
        [info exists ::GX::scriptSourceDeclarationError($id)] && $::GX::scriptSourceDeclarationError($id) ne ""} {
        error "$id: script Analysis Sources declaration: $::GX::scriptSourceDeclarationError($id)"
    }
    return [::GX::analysisSourceValidateModule_v006 $id]
}

rename ::GX::scriptAnalysisRefresh ::GX::scriptAnalysisRefresh_v006
proc ::GX::scriptAnalysisRefresh {} {
    ::GX::scriptAnalysisRefresh_v006
    foreach id {analysis.python_script analysis.octave_script} {
        if {[catch {set changed [scriptAnalysisApplyDeclarations $id]}]} continue
        if {$changed} {
            catch {analysisSourcesRenderForModule $id}
            catch {refreshModuleBindingChoices $id}
            catch {refreshManifestPreview}
        }
    }
}

rename ::GX::renderModuleAnalysisSources ::GX::renderModuleAnalysisSources_v006
proc ::GX::renderModuleAnalysisSources {parent id} {
    ::GX::renderModuleAnalysisSources_v006 $parent $id
    set rows [scriptAnalysisDeclarationRows $id]
    if {![llength $rows]} { return }
    ttk::label $parent.h3 -text "Script declaration"
    grid $parent.h3 -row 1 -column 3 -sticky w -padx 4
    foreach r [analysisSourceRows $id] {
        set source [analysisSourceRowId $id $r]
        set declaration [scriptAnalysisDeclarationFor $id $source]
        if {$declaration eq ""} continue
        set text [dict get $declaration label]
        set purpose [dict get $declaration purpose]
        if {$purpose ne ""} { append text " — $purpose" }
        ttk::label $parent.label$r -text $text -wraplength 320 -justify left
        grid $parent.label$r -row [expr {$r+1}] -column 3 -sticky w -padx 4 -pady 2
        if {[winfo exists $parent.rm$r]} { $parent.rm$r state disabled }
    }
}

rename ::GX::analysisSourceRemoveGuiRow ::GX::analysisSourceRemoveGuiRow_v006
proc ::GX::analysisSourceRemoveGuiRow {id row} {
    set source [analysisSourceRowId $id $row]
    if {[scriptAnalysisDeclarationFor $id $source] ne ""} { return }
    return [::GX::analysisSourceRemoveGuiRow_v006 $id $row]
}

rename ::GX::refreshNativeAnalysisState ::GX::refreshNativeAnalysisState_v006
proc ::GX::refreshNativeAnalysisState {} {
    ::GX::refreshNativeAnalysisState_v006
    foreach id {analysis.python_script analysis.octave_script} {
        if {![info exists ::GX::ui(analysisModuleFrame,$id)]} continue
        set parent $::GX::ui(analysisModuleFrame,$id).sources
        if {![winfo exists $parent]} continue
        foreach row [analysisSourceRows $id] {
            if {[scriptAnalysisDeclarationFor $id [analysisSourceRowId $id $row]] eq ""} continue
            if {[winfo exists $parent.rm$row]} { $parent.rm$row state disabled }
        }
    }
}
