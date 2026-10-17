# Inert recipes and supervised submission for the same public family workflow.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::CurveFamilyV1::_modelIdentity {model} {
    set descriptor [::GX::modelField $model descriptor {}];set script [::GX::modelField $model script {}]
    if {$descriptor eq {}||$script eq {}} {_error {Callable model declaration is unavailable}}
    if {[file pathtype $script] eq "relative"} {set script [file join $::GX::scriptDir $script]}
    return [dict create model_id $model descriptor_sha256 [::GX::sha256File $descriptor] source_sha256 [::GX::sha256File $script]]
}
proc ::GX::CurveFamilyV1::_fileReference {path} {
    set path [file normalize $path];set session [_session];set scope external
    set location $path
    if {[string first "$session/" $path]==0} {set scope session;set location [string range $path [expr {[string length $session]+1}] end]}
    set exists [file isfile $path];set sha {};if {$exists} {set sha [::GX::sha256File $path]}
    return [dict create scope $scope path $location exists $exists sha256 $sha]
}
proc ::GX::CurveFamilyV1::_fileResolve {reference} {
    set path [dict get $reference path]
    switch [dict get $reference scope] {
        session {
            if {[file pathtype $path] ne "relative"} {_error {Invalid Session-relative frozen file}}
            set session [_session];set path [file normalize [file join $session $path]]
            if {[string first "$session/" $path]!=0} {_error {Frozen file escapes its Session}}
        }
        external {if {[file pathtype $path] ne "absolute"} {_error {External frozen file requires its explicit absolute path}}}
        default {_error {Unknown frozen file scope}}
    }
    if {[file isfile $path]!=[dict get $reference exists]} {_error {Frozen parameter/domain file availability changed}}
    if {[dict get $reference exists]&&[::GX::sha256File $path] ne [dict get $reference sha256]} {_error {Frozen parameter/domain file changed}}
    return $path
}
proc ::GX::CurveFamilyV1::recipe {dataset model bindings config} {
    set identity [_validate $dataset $model $bindings $config]
    set files {}
    if {[::GX::datasetPublicationV2DictDefault $config operation_mode fit] eq "evaluate"&&[::GX::datasetPublicationV2DictDefault $config parameter_source manual] eq "csv"} {
        set path [::GX::datasetPublicationV2DictDefault $config parameter_csv_path {}]
        if {$path eq {}||![file isfile $path]} {_error {Choose an existing frozen parameter CSV before capturing the recipe}}
        dict set files parameters [_fileReference $path]
        dict set files domain [_fileReference [file join [file dirname [file normalize $path]] fit_domain.csv]]
        dict unset config parameter_csv_path
    }
    return [::GX::scientificRecipeEncode [dict create format gxtxt.family_recipe.v1 owner curvefit.family_global source_identity $identity model_identity [_modelIdentity $model] dataset_id $dataset model_id $model bindings $bindings config $config frozen_files $files scope complete_canonical_dataset]]
}
proc ::GX::CurveFamilyV1::_recipeRead {encoded} {
    set recipe [::GX::scientificRecipeDataDecode $encoded gxtxt.family_recipe.v1]
    if {[lsort [dict keys $recipe]] ne [lsort {format owner source_identity model_identity dataset_id model_id bindings config frozen_files scope}]} {_error {Family recipe fields differ from its versioned contract}}
    if {[dict get $recipe owner] ne "curvefit.family_global"||[dict get $recipe scope] ne "complete_canonical_dataset"} {_error {Family recipe owner or Dataset scope differs}}
    set config [dict get $recipe config];set files [dict get $recipe frozen_files]
    if {$files ne {}} {
        if {[lsort [dict keys $files]] ne {domain parameters}} {_error {Frozen file receipt is incomplete}}
        dict set config parameter_csv_path [_fileResolve [dict get $files parameters]]
        _fileResolve [dict get $files domain]
    }
    set identity [_validate [dict get $recipe dataset_id] [dict get $recipe model_id] [dict get $recipe bindings] $config]
    if {$identity ne [dict get $recipe source_identity]} {_error {Family recipe scientific Dataset content/schema changed}}
    if {[_modelIdentity [dict get $recipe model_id]] ne [dict get $recipe model_identity]} {_error {Family recipe mathematical model declaration/source changed}}
    dict set recipe config $config
    return $recipe
}
proc ::GX::CurveFamilyV1::recipeValidate {encoded} {
    set recipe [_recipeRead $encoded]
    return [dict create status validated format gxtxt.family_recipe.v1 dataset_id [dict get $recipe dataset_id] model_id [dict get $recipe model_id] scope [dict get $recipe scope]]
}
proc ::GX::CurveFamilyV1::recipeRun {encoded} {
    set recipe [_recipeRead $encoded]
    return [_run [dict get $recipe dataset_id] [dict get $recipe model_id] [dict get $recipe bindings] [dict get $recipe config] $recipe]
}
proc ::GX::CurveFamilyV1::submit {encoded {name {Global family fit}}} {
    recipeValidate $encoded
    if {[string trim $name] eq {}||[string length $name]>160||[regexp {[\r\n\x00]} $name]} {_error {Family Job name must be a nonempty single line of at most 160 characters}}
    # Canonical base64 is inert data and safe inside this fixed Python template.
    set encoded [::GX::scientificRecipeEncode [::GX::scientificRecipeDataDecode $encoded gxtxt.family_recipe.v1]]
    set code [format {from pathlib import Path
from gxtxt import gxtxt_api_call, gxtxt_context
result = gxtxt_api_call('CURVE_FAMILY_API_v1', 'recipe_run', ['%s'])
reference = result['reference']
path = Path(gxtxt_context()['output_dir']) / 'family_result.ini'
with path.open('x', encoding='utf-8') as stream:
    stream.write('[result]\n' + ''.join(key+'='+reference[key]+'\n' for key in ('schema','run_id','receipt_sha256')))
print('Global family result saved; '+str(len(result['parameter_map']['slot_ids']))+' joint parameter slots.')
} $encoded]
    set id family_global_[clock microseconds]
    ::GX::scriptRegistrySave session $id $name $code {language Python required_apis CURVE_FAMILY_API_v1}
    return [::GX::scriptJobSubmit session:$id {}]
}
proc ::GX::CurveFamilyV1::jobResult {jobId} {
    set job [::GX::scriptJobDescribe $jobId]
    if {[file normalize [dict get $job session]] ne [_session]||[dict get $job state] ne "COMPLETED"} {_error {Choose a completed family Job from the current Session}}
    set path [file join [dict get $job output_dir] family_result.ini]
    if {![file isfile $path]||[file size $path]>4096} {_error {This Job has no bounded family result reference}}
    set ini [::GX::parseIni $path];set reference {}
    foreach key {schema run_id receipt_sha256} {dict set reference $key [dict get $ini result.$key]}
    return [resultInfo $reference]
}
proc ::GX::CurveFamilyV1::results {} {
    set entries {}
    set root [file join [_session] analysis curvefit_family_global runs]
    foreach path [lsort -decreasing [glob -nocomplain -directory $root */result.tcldict]] {
        set f [open $path];fconfigure $f -encoding utf-8;try {set receipt [read $f]} finally {close $f}
        set id [dict get $receipt run_id];set model [dict get $receipt model_id]
        if {![regexp {^family-([0-9]+)-[0-9]+$} $id unused micros]} {_error {Invalid retained family run identity}}
        set date [clock format [expr {$micros/1000000}] -format {%Y-%m-%d %H:%M:%S}]
        lappend entries [dict create reference [dict create schema gxtxt.family_reference.v1 run_id $id receipt_sha256 [::GX::sha256File $path]] model_id $model label "[::GX::modelField $model name $model] — $date"]
    }
    return $entries
}
