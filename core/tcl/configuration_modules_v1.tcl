# SPDX-License-Identifier: GPL-3.0-or-later
# Additive CONFIGURATION_API_v1 operations. Values retain their existing owners:
# user defaults in configurationValues/configuration.ini; Session in moduleCfg.
namespace eval ::GX::Configuration {variable inherited {};variable syncing 0;variable listeners {};variable serial 0}

proc ::GX::configurationModuleFields {module} {
    set result {}
    dict for {id descriptor} [configurationFields] {
        if {[datasetPublicationV2DictDefault $descriptor module_id {}] eq $module} {dict set result $id $descriptor}
    }
    return $result
}
proc ::GX::configurationModuleDiscover {module} {
    set path [moduleField $module descriptor {}]
    if {$path eq {}} {return {}}
    set data $::GX::moduleCatalog($module,dict)
    set contribution [descriptorValue $data configuration entrypoint {}]
    if {$contribution ne {}} {
        set root [file normalize [file dirname $path]]
        set file [file normalize [file join $root $contribution]]
        if {![string match ${root}/* $file] || ![file isfile $file]} {error {Invalid module configuration contribution path}}
        # Contributions contain schemas/validators only, never main Viewer APIs.
        source $file
    }
    foreach key [splitList [moduleField $module config_fields {}]] {
        set id [moduleConfigField $module $key configuration_id "module.$module.$key"]
        set persistent [moduleConfigField $module $key persistent_default 0]
        set type [string tolower [moduleConfigField $module $key type string]]
        set originalType $type
        if {$type ni [dict get [uiFieldApiInfo] types]} {set type string}
        set descriptor [dict create group Modules label [moduleConfigField $module $key label $key] \
            type $type default [moduleConfigField $module $key default {}] \
            scope [expr {$persistent ? "module" : "session"}] module_id $module module_key $key \
            module_type $originalType scopes [expr {$persistent ? "user session" : "session"}] \
            application [moduleConfigField $module $key application next_invocation]]
        foreach option {min max required alpha allow_inherit readonly visible description validator structured_fields choices_provider} {
            set value [moduleConfigField $module $key $option {}]
            if {$value ne {}} {dict set descriptor $option $value}
        }
        if {$type eq "choice"} {dict set descriptor values [splitList [moduleConfigField $module $key values {}]]}
        configurationRegister $id $descriptor
        if {![info exists ::GX::moduleCfg($module,$key)]} {
            set ::GX::Configuration::syncing 1
            try {set ::GX::moduleCfg($module,$key) [configurationGet $id]} finally {set ::GX::Configuration::syncing 0}
            dict set ::GX::Configuration::inherited $id $persistent
        }
        set callback [list ::GX::_configurationModuleTrace $id]
        if {[lsearch -exact [trace info variable ::GX::moduleCfg($module,$key)] [list write $callback]]<0} {
            trace add variable ::GX::moduleCfg($module,$key) write $callback
        }
    }
    return [configurationModuleFields $module]
}
proc ::GX::_configurationModuleTrace {id name element op} {
    if {$::GX::Configuration::syncing} return
    dict set ::GX::Configuration::inherited $id 0
    configurationChanged $id
}
proc ::GX::configurationSubscribe {callback} {
    set id config[incr ::GX::Configuration::serial]
    dict set ::GX::Configuration::listeners $id $callback
    return $id
}
proc ::GX::configurationUnsubscribe {id} {dict unset ::GX::Configuration::listeners $id}
proc ::GX::configurationChanged {id} {
    # A projection failing to refresh cannot turn an already committed save
    # into a reported rollback. Other subscribers still receive the event.
    dict for {token callback} $::GX::Configuration::listeners {
        if {[catch {uplevel #0 [list {*}$callback $id]} message]} {puts stderr "Configuration subscriber $token: $message"}
    }
}
proc ::GX::configurationResolve {id} {
    set descriptor [dict get [configurationFields] $id]
    set user [configurationGet $id];set effective $user;set override {};set origin user
    set scopes [datasetPublicationV2DictDefault $descriptor scopes user]
    if {"user" ni $scopes} {set origin factory}
    if {[dict exists $descriptor module_id] && "session" in $scopes && $::GX::currentSession ne {}} {
        set module [dict get $descriptor module_id];set key [dict get $descriptor module_key]
        if {[datasetPublicationV2DictDefault $descriptor module_type {}] eq "table"} {
            set override [repeatableConfigSnapshot $module $key];set effective $override;set origin session
        } elseif {![datasetPublicationV2DictDefault $::GX::Configuration::inherited $id 0] && [info exists ::GX::moduleCfg($module,$key)]} {
            set override $::GX::moduleCfg($module,$key);set effective $override;set origin session
        }
    }
    return [dict create field_id $id factory [dict get $descriptor default] user $user override $override \
        effective $effective origin $origin scopes $scopes session_token [_configurationSessionToken]]
}
proc ::GX::configurationScopedValue {id scope} {
    set value [configurationResolve $id]
    if {$scope eq "user"} {return [dict get $value user]}
    if {$scope ne "session"} {error {Configuration scope must be user or session}}
    if {$::GX::currentSession eq {}} {error {Open a Session to edit Session overrides}}
    return [dict get $value effective]
}
proc ::GX::configurationSessionLoad {path} {
    set data [parseIni $path]
    set ::GX::Configuration::syncing 1
    try {
        dict for {id descriptor} [configurationFields] {
            if {![dict exists $descriptor module_id]} continue
            set module [dict get $descriptor module_id];set key [dict get $descriptor module_key]
            set dk "module_config.$module.$key"
            set inherit [expr {![dict exists $data $dk] && "user" in [dict get $descriptor scopes]}]
            dict set ::GX::Configuration::inherited $id $inherit
            if {$inherit} {set ::GX::moduleCfg($module,$key) [configurationGet $id]}
        }
    } finally {set ::GX::Configuration::syncing 0}
    configurationChanged {}
}
proc ::GX::configurationModuleShouldPersist {module key} {
    set id [moduleConfigField $module $key configuration_id "module.$module.$key"]
    dict for {field descriptor} [configurationModuleFields $module] {
        if {[dict get $descriptor module_key] eq $key} {set id $field;break}
    }
    return [expr {![datasetPublicationV2DictDefault $::GX::Configuration::inherited $id 0]}]
}

proc ::GX::_configurationModuleBind {id} {
    set descriptor [dict get [configurationFields] $id]
    if {![dict exists $descriptor module_id] || "session" ni [dict get $descriptor scopes]} return
    set module [dict get $descriptor module_id];set key [dict get $descriptor module_key]
    if {![info exists ::GX::moduleCfg($module,$key)]} {
        set syncing $::GX::Configuration::syncing;set ::GX::Configuration::syncing 1
        try {set ::GX::moduleCfg($module,$key) [configurationGet $id]} finally {set ::GX::Configuration::syncing $syncing}
        dict set ::GX::Configuration::inherited $id [expr {"user" in [dict get $descriptor scopes]}]
    }
    set callback [list ::GX::_configurationModuleTrace $id]
    if {[lsearch -exact [trace info variable ::GX::moduleCfg($module,$key)] [list write $callback]]<0} {trace add variable ::GX::moduleCfg($module,$key) write $callback}
}
proc ::GX::configurationCommit {changes {persist 1}} {
    # Each change: id, scope, value, expected (captured authoritative value),
    # session_token, optional clear. Validate the complete transaction first.
    set normalized {}
    foreach change $changes {
        set id [dict get $change id];set scope [dict get $change scope]
        set descriptor [dict get [configurationFields] $id]
        if {[datasetPublicationV2DictDefault $descriptor readonly 0]} {error "[dict get $descriptor label] is read-only"}
        if {$scope ni [datasetPublicationV2DictDefault $descriptor scopes user]} {error "Scope '$scope' is unavailable for $id"}
        if {[dict exists $change expected] && [dict get $change expected] ne [configurationScopedValue $id $scope]} {
            error "Configuration conflict for [dict get $descriptor label]. Another editor changed this value; reload or explicitly keep your draft."
        }
        if {$scope eq "session" && ([dict get $change session_token] ne [_configurationSessionToken] || $::GX::currentSession eq {})} {error {Session changed; reload this editor}}
        set value [configurationValidate $id [dict get $change value]]
        dict set change value [_configurationValidateBinding $descriptor $value]
        lappend normalized $change
    }
    set proposed $::GX::configurationValues
    foreach change $normalized {if {[dict get $change scope] eq "user"} {dict set proposed [dict get $change id] [dict get $change value]}}
    if {[dict get $proposed computation.default_workers]>[dict get $proposed computation.max_workers]} {error {Default workers cannot exceed maximum workers}}
    set prior $::GX::configurationValues;set oldSaved $::GX::configurationSaved
    set priorModule [array get ::GX::moduleCfg];set priorInherited $::GX::Configuration::inherited
    set priorRows [array get ::GX::repeatableRows];set priorCells [array get ::GX::repeatableValue]
    set userChanges 0;set sessionChanges 0;set ::GX::Configuration::syncing 1
    try {
        foreach change $normalized {
            set id [dict get $change id];set scope [dict get $change scope];set value [dict get $change value]
            set descriptor [dict get [configurationFields] $id]
            if {$scope eq "user"} {
                configurationSet $id $value;set userChanges 1
                if {[dict exists $descriptor module_id] && [datasetPublicationV2DictDefault $::GX::Configuration::inherited $id 1]} {
                    set ::GX::moduleCfg([dict get $descriptor module_id],[dict get $descriptor module_key]) $value
                }
            } else {
                set inherit [datasetPublicationV2DictDefault $change clear 0]
                if {$inherit && "user" ni [dict get $descriptor scopes]} {error {This field has no User default to inherit}}
                dict set ::GX::Configuration::inherited $id $inherit
                if {[datasetPublicationV2DictDefault $descriptor module_type {}] eq "table"} {
                    repeatableConfigApplySnapshot [dict get $descriptor module_id] [dict get $descriptor module_key] $value
                } else {set ::GX::moduleCfg([dict get $descriptor module_id],[dict get $descriptor module_key]) [expr {$inherit ? [configurationGet $id] : $value}]}
                set sessionChanges 1
            }
        }
        if {$persist && $userChanges && $sessionChanges} {error {Commit User defaults and Session overrides separately}}
        if {$persist && $userChanges} {configurationSave}
        if {$persist && $sessionChanges} {set manifest [file join $::GX::currentSession metadata manifest.ini]
            set temporary ${manifest}.[pid].config.tmp
            try {writeManifest $temporary;file rename -force -- $temporary $manifest} finally {file delete -force -- $temporary}}
    } on error {message options} {
        set ::GX::configurationValues $prior;set ::GX::configurationSaved $oldSaved
        # Restore elements without removing their lifetime/validation traces.
        foreach {element value} $priorModule {set ::GX::moduleCfg($element) $value}
        set ::GX::Configuration::inherited $priorInherited
        array unset ::GX::repeatableRows *;array set ::GX::repeatableRows $priorRows
        array unset ::GX::repeatableValue *;array set ::GX::repeatableValue $priorCells
        return -options $options $message
    } finally {set ::GX::Configuration::syncing 0}
    foreach change $normalized {configurationChanged [dict get $change id]}
    return [dict create status saved fields [llength $normalized]]
}

proc ::GX::_configurationValidateBinding {descriptor value} {
    if {![dict exists $descriptor module_id] || $value eq {}} {return $value}
    set module [dict get $descriptor module_id];set key [dict get $descriptor module_key]
    set type [dict get $descriptor module_type];set choices {}
    switch -- $type {
        dataset {set choices [datasetRegistryIds]}
        variable {
            set dataset [datasetSelectionSourceDataset $module [moduleConfigField $module $key source primary]]
            if {$dataset ne {}} {set choices [datasetVariableNamesById $dataset]}
        }
        model {set choices [scalarModelValues $module $key]}
        selection {set choices [datasetSelectionCompatibleIds $module $key]}
        temporal_set {set choices [temporalSetCompatibleIds $module $key]}
        analysis_definition {set choices [analysisDefinitionIdsForConfig $module $key]}
        registered_script {scriptRegistryDescribe $value;return $value}
        unit {unitRegistryConversionPlan $value $value;return $value}
        default {return $value}
    }
    if {$value ni $choices} {error "[dict get $descriptor label]: unknown or incompatible $type binding '$value'"}
    if {$type eq "temporal_set"} {temporalSetValidateDefinition $value}
    return $value
}

proc ::GX::_configurationSessionToken {} {
    if {$::GX::currentSession eq {}} {return no-session}
    return [interactiveDocumentSessionToken]
}
