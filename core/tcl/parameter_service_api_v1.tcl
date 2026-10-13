# SPDX-License-Identifier: GPL-3.0-or-later
# CORE owns scope identity and canonical persistence; C owns all expressions.
namespace eval ::GX::Parameters {variable declarations {};variable contexts {};variable listeners {};variable state {};variable sessionToken {}}
proc ::GX::parameterServiceInfo {} {return [dict create api_id CORE_PARAMETER_SERVICE_v1 authority portable_c scopes {session module workspace} namespace_assignment framework script_policy read_evaluate_only]}
proc ::GX::_parameterEnsure {} {
    variable scriptDir
    if {![llength [info commands ::GX::Parameters::native]]} {load [file join $scriptDir core parameters gxparameters[info sharedlibextension]] Gxparameters}
    set token [interactiveDocumentSessionToken]
    if {$token ne $::GX::Parameters::sessionToken} {
        set ::GX::Parameters::sessionToken $token;set ::GX::Parameters::state {};set ::GX::Parameters::contexts {};set ::GX::Parameters::listeners {};set ::GX::Parameters::readViews {}
        if {$::GX::currentSession ne {}&&[file isfile [file join $::GX::currentSession metadata manifest.ini]]} {
            set ini [parseIni [file join $::GX::currentSession metadata manifest.ini]]
            set ::GX::Parameters::state [datasetPublicationV2DictDefault $ini core_parameters.state {}]
        }
    }
}
proc ::GX::_parameterOwner {capability} {
    if {![dict exists $::GX::DatasetPrivate::owners $capability]} {error {Invalid framework module capability}}
    set owner [dict get $::GX::DatasetPrivate::owners $capability]
    if {$::GX::DatasetPrivate::activeContext ne {} && [dict get [datasetPrivateMetadataContext] module_id] ne $owner} {error {Module cannot use another owner capability}}
    return $owner
}
proc ::GX::parameterModuleRegister {definitions} {
    set identity [datasetPrivateMetadataContext];set module [dict get $identity module_id]
    _parameterDefinitionsValidate $definitions
    dict set ::GX::Parameters::declarations $module $definitions
    return [dict get $identity capability]
}
proc ::GX::_parameterDefinitionsValidate {definitions} {
    if {[dict size $definitions]>4096} {error {Too many parameters}}
    dict for {name record} $definitions {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $name]} {error "Invalid parameter name '$name'"}
        foreach key [dict keys $record] {if {$key ni {formula label description unit type min max editable}} {error "Unsupported parameter field '$key'; namespaces are assigned by CORE"}}
        if {![dict exists $record formula]} {error "Parameter '$name' needs a formula or numeric value"}
        foreach key {min max} {if {[dict exists $record $key]&&![string is double -strict [dict get $record $key]]} {error "Invalid $key for '$name'"}}
        if {[dict exists $record editable]&&![string is boolean -strict [dict get $record editable]]} {error "Invalid editability for '$name'"}
        if {[dict exists $record type]&&[dict get $record type] ni {number integer}} {error "Unsupported parameter type for '$name'"}
    }
    return $definitions
}
proc ::GX::_parameterFormulas {definitions} {set out {};dict for {name record} $definitions {dict set out $name [dict get $record formula]};return $out}
proc ::GX::_parameterEvaluate {definitions session {expression {}}} {
    _parameterEnsure;_parameterDefinitionsValidate $definitions
    set values [::GX::Parameters::native [_parameterFormulas $definitions] [_parameterFormulas $session]]
    dict for {name receipt} $values {
        set definition [dict get $definitions $name];set value [dict get $receipt value]
        foreach {field op} {min < max >} {if {[dict exists $definition $field]&&[expr "$value $op [dict get $definition $field]"]} {error "Parameter '$name' violates $field"}}
        if {[datasetPublicationV2DictDefault $definition type number] eq "integer"&&$value!=floor($value)} {error "Parameter '$name' requires an integer"}
        dict set values $name [dict merge $definition $receipt]
    }
    if {$expression ne {}} {return [::GX::Parameters::native [_parameterFormulas $definitions] [_parameterFormulas $session] $expression]}
    return $values
}
proc ::GX::parameterSessionDefinitions {} {_parameterEnsure;return [datasetPublicationV2DictDefault $::GX::Parameters::state session {}]}
proc ::GX::parameterSessionList {} {return [_parameterEvaluate [parameterSessionDefinitions] {}]}
proc ::GX::parameterSessionEvaluate {expression} {return [_parameterEvaluate [parameterSessionDefinitions] {} $expression]}
proc ::GX::parameterContext {capability {workspace {}}} {
    _parameterEnsure;set module [_parameterOwner $capability]
    if {$workspace ne {}} {set doc [sessionWorkspaceGet $workspace];if {[dict get $doc module_id] ne $module} {error {Workspace belongs to another module}}}
    set key [list $module $workspace];set token parameter#[parallelOctaveRandomToken]
    dict set ::GX::Parameters::contexts $token [dict create module $module workspace $workspace session [interactiveDocumentSessionToken] key $key]
    return $token
}
proc ::GX::_parameterContext {token} {
    _parameterEnsure
    if {![dict exists $::GX::Parameters::contexts $token]} {error {Invalid or stale parameter context}}
    set context [dict get $::GX::Parameters::contexts $token]
    if {$::GX::DatasetPrivate::activeContext ne {} && [dict get [datasetPrivateMetadataContext] module_id] ne [dict get $context module]} {error {Module cannot use another parameter context}}
    set workspace [dict get $context workspace]
    if {$workspace ne {}&&[dict get [sessionWorkspaceGet $workspace] module_id] ne [dict get $context module]} {error {Parameter owner changed}}
    return $context
}
namespace eval ::GX::Parameters {variable readViews {}}
proc ::GX::parameterReadView {token definitions {sessionDefinitions {}}} {
    _parameterContext $token;_parameterDefinitionsValidate $definitions
    dict set ::GX::Parameters::readViews $token [dict create definitions $definitions session $sessionDefinitions]
}
proc ::GX::parameterReadViewClose {token} {dict unset ::GX::Parameters::readViews $token}
proc ::GX::parameterDefinitions {token} {
    _parameterContext $token
    if {[dict exists $::GX::Parameters::readViews $token]} {return [dict get $::GX::Parameters::readViews $token definitions]}
    set context [_parameterContext $token];set module [dict get $context module];set workspace [dict get $context workspace]
    set defaults [datasetPublicationV2DictDefault $::GX::Parameters::declarations $module {}]
    if {$workspace ne {}} {set metadata [dict get [interactiveDocumentRead $workspace] payload workspace_metadata];set stored [datasetPublicationV2DictDefault $metadata parameters {}]} else {set stored [datasetPublicationV2DictDefault $::GX::Parameters::state module.$module {}]}
    return [dict merge $defaults $stored]
}
proc ::GX::parameterViewSessionDefinitions {token} {
    if {[dict exists $::GX::Parameters::readViews $token]} {return [dict get $::GX::Parameters::readViews $token session]}
    return [parameterSessionDefinitions]
}
proc ::GX::parameterList {token} {return [_parameterEvaluate [parameterDefinitions $token] [parameterViewSessionDefinitions $token]]}
proc ::GX::parameterEvaluate {token expression} {return [_parameterEvaluate [parameterDefinitions $token] [parameterViewSessionDefinitions $token] $expression]}
proc ::GX::parameterContextInfo {token} {set c [_parameterContext $token];dict set c namespace module/[dict get $c module];return [dict remove $c key session]}
proc ::GX::parameterSubscribe {token callback} {_parameterContext $token;dict set ::GX::Parameters::listeners $token $callback}
proc ::GX::parameterUnsubscribe {token} {dict unset ::GX::Parameters::listeners $token}
proc ::GX::_parameterWrite {token definitions} {
    if {[dict exists $::GX::Parameters::readViews $token]} {error {This parameter context is inspecting History and is read-only.}}
    _parameterDefinitionsValidate $definitions
    set oldState $::GX::Parameters::state;set documents {};set applied {}
    if {$token eq "session"} {
        _parameterEvaluate $definitions {}
        # Validate dependencies of every stored Workspace before accepting a
        # Session change, including providers whose UI is currently closed.
        foreach workspace [sessionWorkspaceList] {
            set doc [interactiveDocumentRead [dict get $workspace id]]
            set local [datasetPublicationV2DictDefault [dict get $doc payload workspace_metadata] parameters {}]
            set defaults [datasetPublicationV2DictDefault $::GX::Parameters::declarations [dict get $workspace module_id] {}]
            set local [dict merge $defaults $local]
            _parameterEvaluate $local $definitions
            foreach expression [dict values [datasetPublicationV2DictDefault [dict get $doc payload workspace_metadata] parameter_bindings {}]] {_parameterEvaluate $local $definitions $expression}
        }
        dict for {scope local} $::GX::Parameters::state {if {[string match module.* $scope]} {_parameterEvaluate $local $definitions}}
        dict set ::GX::Parameters::state session $definitions
        set targets [dict keys $::GX::Parameters::listeners]
    } else {
        set context [_parameterContext $token];_parameterEvaluate $definitions [parameterSessionDefinitions]
        set workspace [dict get $context workspace]
        if {$workspace eq {}} {dict set ::GX::Parameters::state module.[dict get $context module] $definitions} else {
            set payload [dict get [interactiveDocumentRead $workspace] payload];dict set documents $workspace $payload
            foreach expression [dict values [datasetPublicationV2DictDefault [dict get $payload workspace_metadata] parameter_bindings {}]] {_parameterEvaluate $definitions [parameterSessionDefinitions] $expression}
            dict set payload workspace_metadata parameters $definitions
            interactiveDocumentUpdate $workspace $payload
        }
        set targets {}
        dict for {candidate callback} $::GX::Parameters::listeners {if {[dict get [_parameterContext $candidate] key] eq [dict get $context key]} {lappend targets $candidate}}
    }
    try {
        foreach target $targets {
            if {![dict exists $::GX::Parameters::listeners $target]} continue
            set workspace [dict get [_parameterContext $target] workspace]
            if {$workspace ne {}&&![dict exists $documents $workspace]} {dict set documents $workspace [dict get [interactiveDocumentRead $workspace] payload]}
            set callback [dict get $::GX::Parameters::listeners $target]
            set rollback [uplevel #0 [list {*}$callback $target]];lappend applied $rollback
        }
        if {$::GX::currentSession ne {}} {writeManifest [file join $::GX::currentSession metadata manifest.ini]}
    } on error {message options} {
        set ::GX::Parameters::state $oldState
        foreach rollback [lreverse $applied] {if {$rollback ne {}} {uplevel #0 $rollback}}
        dict for {id payload} $documents {interactiveDocumentUpdate $id $payload}
        if {$::GX::currentSession ne {}} {writeManifest [file join $::GX::currentSession metadata manifest.ini]}
        return -options $options $message
    }
    return [expr {$token eq "session"?[parameterSessionList]:[parameterList $token]}]
}
proc ::GX::_parameterChange {token name definition remove} {
    _interactiveDocumentRequireSession
    set definitions [expr {$token eq "session"?[parameterSessionDefinitions]:[parameterDefinitions $token]}]
    if {[dict exists $definitions $name]&&![datasetPublicationV2DictDefault [dict get $definitions $name] editable 1]} {error "Parameter '$name' is read-only"}
    if {$remove && $token ne "session"} {set owner [dict get [_parameterContext $token] module];if {[dict exists $::GX::Parameters::declarations $owner $name]} {error {Declared module parameters cannot be deleted; update their permitted value instead}}}
    if {$remove} {if {![dict exists $definitions $name]} {error "Unknown parameter '$name'"};dict unset definitions $name} else {dict set definitions $name $definition}
    return [_parameterWrite $token $definitions]
}
proc ::GX::parameterSet {token name definition} {_parameterContext $token;return [_parameterChange $token $name $definition 0]}
proc ::GX::parameterDelete {token name} {_parameterContext $token;return [_parameterChange $token $name {} 1]}
# Session administration is host/UI-only, never an operation on module tokens.
proc ::GX::parameterSessionSet {name definition} {if {$::GX::DatasetPrivate::activeContext ne {}} {error {Module callbacks cannot administer Session parameters}};return [_parameterChange session $name $definition 0]}
proc ::GX::parameterSessionDelete {name} {if {$::GX::DatasetPrivate::activeContext ne {}} {error {Module callbacks cannot administer Session parameters}};return [_parameterChange session $name {} 1]}
rename ::GX::manifestStringV2 ::GX::manifestStringV2_before_parameters
proc ::GX::manifestStringV2 {} {
    _parameterEnsure;set out [manifestStringV2_before_parameters]
    append out "\n\[core_parameters\]\n";appendKV out api_version 1;appendKV out state $::GX::Parameters::state
    return $out
}
rename ::GX::loadManifestV2 ::GX::loadManifestV2_before_parameters
proc ::GX::loadManifestV2 {path} {
    set ini [parseIni $path];set state [datasetPublicationV2DictDefault $ini core_parameters.state {}]
    _parameterEvaluate [datasetPublicationV2DictDefault $state session {}] {}
    loadManifestV2_before_parameters $path
    set ::GX::Parameters::sessionToken [interactiveDocumentSessionToken];set ::GX::Parameters::state $state
    set ::GX::Parameters::contexts {};set ::GX::Parameters::listeners {};set ::GX::Parameters::readViews {}
}

# A reusable Native2D consumer adapter: modules supply bindings, never parsers.
proc ::GX::parameterApplyDimensions {token scene expressions} {
    set values {};dict for {id expression} $expressions {dict set values $id [parameterEvaluate $token $expression]}
    ::GX::Native2D::core interaction_constraint_values $scene $values
    return $values
}

# Read-only Bridge entry points do not return reusable administration tokens.
proc ::GX::parameterWorkspaceRead {workspace {expression {}}} {
    set doc [sessionWorkspaceGet $workspace];set metadata [dict get [interactiveDocumentRead $workspace] payload workspace_metadata]
    set defaults [datasetPublicationV2DictDefault $::GX::Parameters::declarations [dict get $doc module_id] {}]
    set definitions [dict merge $defaults [datasetPublicationV2DictDefault $metadata parameters {}]]
    return [_parameterEvaluate $definitions [parameterSessionDefinitions] $expression]
}

# Persist consumer expression dependencies alongside canonical Workspace state,
# allowing closed providers to participate in formula/deletion validation.
proc ::GX::parameterBindingsSet {token bindings} {
    set context [_parameterContext $token];set workspace [dict get $context workspace]
    if {$workspace eq {}} {error {Consumer bindings require a Workspace context}}
    dict for {id expression} $bindings {parameterEvaluate $token $expression}
    set payload [dict get [interactiveDocumentRead $workspace] payload]
    if {[datasetPublicationV2DictDefault [dict get $payload workspace_metadata] parameter_bindings {}] eq $bindings} return
    dict set payload workspace_metadata parameter_bindings $bindings
    interactiveDocumentUpdate $workspace $payload
}
