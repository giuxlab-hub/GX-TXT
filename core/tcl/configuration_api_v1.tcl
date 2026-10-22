# GX-TXT Configuration API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# User defaults are distinct from Session manifests and runtime state. Existing
# workspace, preview, module and parallel services remain the owners of their
# respective behavior; this registry supplies persistent defaults to them.
namespace eval ::GX {
    variable configurationSchema [dict create]
    variable configurationValues [dict create]
    variable configurationSaved [dict create]
    variable configurationLoaded 0
    variable configurationWarnings {}
}

proc ::GX::configurationApiInfo {} {
    return [dict create api_name CONFIGURATION_API_v1 api_version 1 scopes {framework user module session runtime} module_scopes {user session} operations {register fields get set validate save module_discover module_fields resolve scoped_value commit subscribe unsubscribe viewer_command_catalog viewer_commands_attach viewer_command_invoke viewer_commands_detach open_page}]
}

proc ::GX::configurationPath {} {
    return [file join [file dirname [workspaceProfilesPath]] configuration.ini]
}

proc ::GX::configurationRegister {id descriptor} {
    variable configurationSchema
    variable configurationValues
    variable configurationSaved
    if {![regexp {^[a-z][a-zA-Z0-9_.-]*$} $id]} { error "Invalid configuration field ID '$id'." }
    foreach required {group label type default scope} {
        if {![dict exists $descriptor $required]} { error "Configuration field '$id' is missing $required." }
    }
    if {[dict get $descriptor scope] ni {framework user module session runtime}} {
        error "Configuration field '$id' has an invalid scope."
    }
    if {[dict get $descriptor type] ni {string path file command integer boolean double number choice color}} {
        error "Configuration field '$id' has an unsupported type."
    }
    if {[dict exists $descriptor module_id]} {
        foreach {key fallback} [list module_key [lindex [split $id .] end] module_type [dict get $descriptor type] scopes [expr {[dict get $descriptor scope] eq "session" ? "session" : "user"}] application next_invocation] {
            if {![dict exists $descriptor $key]} {dict set descriptor $key $fallback}
        }
    }
    if {[dict exists $configurationSchema $id]} {
        set prior [dict get $configurationSchema $id]
        if {$prior eq $descriptor} {return $id}
        # Catalog upgrades may evolve a module-owned schema; preserve its valid
        # value. Unrelated/differently owned duplicate registration still rejects.
        if {![dict exists $descriptor module_id] || ![dict exists $prior module_id] || [dict get $descriptor module_id] ne [dict get $prior module_id] || [dict get $descriptor module_key] ne [dict get $prior module_key]} {error "Configuration field '$id' was registered twice with different metadata."}
        set previous [dict get $configurationValues $id]
        dict set configurationSchema $id $descriptor
        if {[catch {configurationValidate $id $previous} valid]} {
            lappend ::GX::configurationWarnings "$id: saved value needs review after schema update: $valid"
            set valid [configurationValidate $id [dict get $descriptor default]]
        }
        dict set configurationValues $id $valid
        _configurationModuleBind $id
        configurationChanged $id
        return $id
    }
    dict set configurationSchema $id $descriptor
    set value [dict get $descriptor default]
    if {[dict exists $configurationSaved $id] && [dict get $descriptor scope] in {user module}} {
        set value [dict get $configurationSaved $id]
    }
    if {[catch {configurationValidate $id $value} valid]} {
        lappend ::GX::configurationWarnings "$id: $valid"
        # Session descriptors can intentionally require a binding at invocation.
        # An unset factory binding is inspectable, never a valid submitted value.
        if {[dict get $descriptor scope] eq "session" && [dict get $descriptor default] eq {}} {
            set valid {}
        } else {set valid [configurationValidate $id [dict get $descriptor default]]}
    }
    dict set configurationValues $id $valid
    _configurationModuleBind $id
    configurationChanged $id
    return $id
}

proc ::GX::_configurationNormalize {id value} {
    variable configurationSchema
    if {![dict exists $configurationSchema $id]} { error "Unknown configuration field '$id'." }
    set descriptor [dict get $configurationSchema $id]
    if {[dict get $descriptor type] in {double number choice color file} || ([dict get $descriptor type] eq "integer" && [dict exists $descriptor module_id])} {return [uiFieldNormalize $descriptor $value]}
    switch -- [dict get $descriptor type] {
        integer {
            if {![string is integer -strict $value] || $value < 1} { error "Configuration '$id' requires an integer >= 1." }
        }
        boolean {
            if {![string is boolean -strict $value]} { error "Configuration '$id' requires a boolean." }
            set value [expr {$value ? 1 : 0}]
        }
        command - path {
            set value [string trim $value]
            if {[string first "\n" $value] >= 0 || [string first "\r" $value] >= 0} {
                error "Configuration '$id' cannot contain a line break."
            }
        }
        default { set value [string trim $value] }
    }
    if {$id eq "ui.x11_popup_repair_delay_ms" && ($value < 25 || $value > 2000)} {
        error "Delay after popup mapping must be an integer from 25 to 2000 ms."
    }
    if {$id eq "ui.font_size" && $value ne "system" &&
        (![string is integer -strict $value] || $value < 8 || $value > 24)} {
        error "GUI font size must be System/default or an integer from 8 to 24 points."
    }
    if {$id in {ui.theme ui.font_family} && ($value eq {} || [regexp {[\r\n]} $value])} {
        error "Configuration '$id' requires a nonempty single-line choice."
    }
    if {[string match {viewers.native3d.*} $id]} {
        set key [string range $id [string length {viewers.native3d.}] end]
        set choices [dict create preset {Low Medium High Ultra Custom} execution {Auto Hardware Software} \
            normal_quality {Preview Low Medium High Full} interaction_lod {Off On} \
            interaction_quality {Preview Low Medium High} msaa {Off 2x 4x 8x} \
            transparency {Standard {Depth peeling}} shadow_rendering {Off {Opaque objects only} {Opaque and translucent objects}}]
        if {[dict exists $choices $key] && $value ni [dict get $choices $key]} {
            error "Configuration '$id' must be one of: [join [dict get $choices $key] {, }]."
        }
        set limits [dict create export_supersampling {1 4} display_triangle_budget {1000 4000000} \
            worker_rss_budget_mib {128 65536} worker_address_space_budget_mib {512 65536}]
        if {[dict exists $limits $key]} {
            lassign [dict get $limits $key] low high
            if {![string is integer -strict $value] || $value < $low || $value > $high} {
                error "Configuration '$id' requires an integer from $low to $high."
            }
        }
        if {$key eq "gpu_budget_mib" && $value ne "auto" &&
            (![string is integer -strict $value] || $value < 16 || $value > 16384)} {
            error "Configuration '$id' requires auto or 16..16384 MiB."
        }
    }
    return $value
}

proc ::GX::configurationValidate {id value} {
    set descriptor [dict get [configurationFields] $id]
    if {[datasetPublicationV2DictDefault $descriptor module_type {}] eq "table"} {
        if {$value eq {} && [dict get $descriptor scope] eq "session"} {return {}}
        return [repeatableConfigValidateSnapshot [dict get $descriptor module_id] [dict get $descriptor module_key] $value]
    }
    set value [_configurationNormalize $id $value]
    if {[dict exists $descriptor validator]} {set value [uplevel #0 [list {*}[dict get $descriptor validator] $value]]}
    return $value
}

proc ::GX::configurationFields {} {
    variable configurationSchema
    return $configurationSchema
}

proc ::GX::configurationGet {id} {
    variable configurationValues
    if {![dict exists $configurationValues $id]} { error "Unknown configuration field '$id'." }
    return [dict get $configurationValues $id]
}

proc ::GX::configurationSet {id value} {
    variable configurationSchema
    variable configurationValues
    if {![dict exists $configurationSchema $id]} { error "Unknown configuration field '$id'." }
    if {[dict get $configurationSchema $id scope] in {framework runtime session}} {
        error "Configuration '$id' is read-only."
    }
    dict set configurationValues $id [configurationValidate $id $value]
    if {$id eq "viewers.native3d.preset" && $value ne "Custom"} {
        dict for {key setting} [native3dGraphicsPresetFields $value] {
            dict set configurationValues viewers.native3d.$key $setting
        }
    } elseif {[string match {viewers.native3d.*} $id]} {
        dict set configurationValues viewers.native3d.preset [native3dGraphicsPresetDetect $configurationValues]
    }
    if {!$::GX::Configuration::syncing} {
        set descriptor [dict get $configurationSchema $id]
        if {[dict exists $descriptor module_id] && [datasetPublicationV2DictDefault $::GX::Configuration::inherited $id 1]} {
            set ::GX::Configuration::syncing 1
            try {set ::GX::moduleCfg([dict get $descriptor module_id],[dict get $descriptor module_key]) [dict get $configurationValues $id]} finally {set ::GX::Configuration::syncing 0}
        }
        configurationChanged $id
    }
    return [dict get $configurationValues $id]
}

proc ::GX::native3dGraphicsPresetFields {preset} {
    switch -- $preset {
        Low {return [dict create normal_quality Low interaction_lod On interaction_quality Preview msaa Off transparency Standard shadow_rendering Off display_triangle_budget 250000]}
        Medium {return [dict create normal_quality Medium interaction_lod On interaction_quality Low msaa 2x transparency Standard shadow_rendering {Opaque objects only} display_triangle_budget 500000]}
        High {return [dict create normal_quality High interaction_lod On interaction_quality Medium msaa 4x transparency {Depth peeling} shadow_rendering {Opaque and translucent objects} display_triangle_budget 1000000]}
        Ultra {return [dict create normal_quality Full interaction_lod Off interaction_quality High msaa 8x transparency {Depth peeling} shadow_rendering {Opaque and translucent objects} display_triangle_budget 4000000]}
        default {error "Unknown Native 3D graphics preset '$preset'."}
    }
}

proc ::GX::native3dGraphicsPresetDetect {values} {
    foreach preset {Low Medium High Ultra} {
        set match 1
        dict for {key setting} [native3dGraphicsPresetFields $preset] {
            if {[dict get $values viewers.native3d.$key] ne $setting} {set match 0;break}
        }
        if {$match} {return $preset}
    }
    return Custom
}

proc ::GX::native3dGraphicsPolicy {} {
    set policy [dict create]
    foreach key {preset execution normal_quality interaction_lod interaction_quality msaa transparency shadow_rendering \
        export_supersampling display_triangle_budget gpu_budget_mib worker_rss_budget_mib \
        worker_address_space_budget_mib} {
        dict set policy $key [configurationGet viewers.native3d.$key]
    }
    dict set policy gpu_budget_bytes [expr {[dict get $policy gpu_budget_mib] eq "auto" ? 0 :
        wide([dict get $policy gpu_budget_mib])*1048576}]
    return $policy
}

proc ::GX::configurationHome {} {
    if {[info exists ::env(USERPROFILE)] && $::env(USERPROFILE) ne ""} { return $::env(USERPROFILE) }
    if {[info exists ::env(HOME)] && $::env(HOME) ne ""} { return $::env(HOME) }
    return [pwd]
}

proc ::GX::configurationRegisterBuiltins {} {
    foreach kind {markdown html} {configurationRegister runtime.${kind}_viewer [dict create group Runtime label "[string totitle $kind] Dataset viewer (internal or argv prefix)" type string default internal scope user]}
    sourceSurfaceConfigurationRegister
    configurationRegister ui.projects.organization [dict create group General label {Project navigator state} type string default {selected {} opened {} y 0 query {}} scope user scopes {user} application on_reopen validator ::GX::projectOrganizationGuiStateValidate]
    foreach {id label type default} {printing.dock_width {Print Studio dock width (px)} integer 350 printing.log_height {Print Studio diagnostics height (px)} integer 150 printing.cups_timeout_ms {CUPS operation timeout (ms)} integer 3000 printing.log_visible {Show Print Studio diagnostics} boolean 0 printing.last_printer {Last verified printer} string {} printing.capabilities_cache {Verified printer metadata cache} string {}} {
        configurationRegister $id [dict create group Printing label $label type $type default $default scope user scopes {user} application immediate]
    }
    set home [configurationHome]
    set threads [parallelExecutionHardwareThreads]
    foreach {id label type default} {
        ui.theme {Theme} string system
        ui.font_family {Proportional GUI font family} string system
        ui.font_size {GUI font size (points)} string system
        ui.x11_popup_repair_enabled {Enable remote X11 popup recovery} boolean 1
        ui.x11_popup_repair_delay_ms {Delay after popup mapping (ms)} integer 150
    } {
        configurationRegister $id [dict create group Appearance label $label type $type default $default scope user]
    }
    foreach {id group label type default scope} [list \
        storage.session_root Storage {Session and Project root} path {} user \
        storage.temp_dir Storage {Temporary directory} path [file join $home .cache gxtxt_pipeline tmp] user \
        storage.cache_dir Storage {Cache directory} path [file join $home .cache gxtxt_pipeline] user \
        storage.export_dir Storage {Default export directory} path {} user \
        storage.package_dir Storage {Framework package directory} path [file join $::GX::scriptDir plugin_packages] framework \
        runtime.octave Runtime {Octave CLI} command auto user \
        runtime.python Runtime {Python} command auto user \
        runtime.latex Runtime {LaTeX build driver / engine} command auto user \
        runtime.bibtex Runtime {BibTeX bibliography tool} command auto user \
        runtime.biber Runtime {Biber bibliography tool} command auto user \
        runtime.ffmpeg Runtime {FFmpeg} command auto user \
        runtime.ffprobe Runtime {FFprobe} command auto user \
        runtime.tesseract Runtime {Tesseract OCR} command auto user \
        runtime.spice Runtime {SPICE tool} command auto user \
        runtime.gmsh Runtime {Gmsh mesh generator} command auto user \
        runtime.getdp Runtime {GetDP finite element solver} command auto user \
        runtime.mpi Runtime {MPI launcher} command auto user \
        runtime.magick Runtime {ImageMagick} command auto user \
        runtime.pdftoppm Runtime {PDF thumbnailer} command auto user \
        runtime.mutool Runtime {MuPDF tools} command auto user \
        runtime.qpdf Runtime {QPDF} command auto user \
        computation.default_workers Computation {Default workers} integer [expr {max(1, int(ceil($threads * 0.8)))}] user \
        computation.max_workers Computation {Maximum workers} integer $threads user \
        libraries.scientific_root Libraries {GX-TXT Library Root} path [file join [expr {[info exists ::env(XDG_DATA_HOME)] ? $::env(XDG_DATA_HOME) : [file join $home .local share]}] gxtxt_pipeline scientific_libraries] user \
        scripts.user_root Scripts {User script library} path [file join $home gxtxt scripts] user \
        features.script_workspace Scripts {Show Script Workspace in Analysis} boolean 0 user \
        plugins.package_chooser_directory Modules {Default plugin package directory} path {} user \
        viewers.text Viewers {Text / CSV viewer} command auto user \
        viewers.image Viewers {Image viewer} command auto user \
        viewers.pdf Viewers {PDF viewer} command auto user \
        viewers.audio Viewers {Audio viewer} command auto user \
        viewers.video Viewers {Video viewer} command auto user \
        viewers.spectrum Viewers {Spectrum viewer} command auto user \
        viewers.binary Viewers {Binary / HDF5 viewer} command auto user \
        viewers.mesh Viewers {3D mesh viewer} command auto user] {
        configurationRegister $id [dict create group $group label $label type $type default $default scope $scope]
    }
    foreach {key label type default} {
        preset {Graphics preset} string High
        execution {Rendering execution} string Auto
        normal_quality {Normal geometry quality} string High
        interaction_lod {Interactive LOD} string On
        interaction_quality {Interaction quality} string Medium
        msaa {MSAA} string 4x
        transparency {Transparency quality} string {Depth peeling}
        shadow_rendering {Shadow rendering} string {Opaque and translucent objects}
        export_supersampling {Export supersampling factor} integer 1
        display_triangle_budget {Display triangle budget} integer 1000000
        gpu_budget_mib {GPU resource budget (MiB; auto = unlimited)} string 512
        worker_rss_budget_mib {Renderer worker RSS budget (MiB)} integer 4096
        worker_address_space_budget_mib {Renderer worker address space budget (MiB)} integer 8192
    } {
        configurationRegister viewers.native3d.$key [dict create group Viewers label $label type $type default $default scope user]
    }
}

proc ::GX::configurationLoad {} {
    variable configurationLoaded
    variable configurationSaved
    variable configurationValues
    variable configurationSchema
    variable configurationWarnings
    set configurationWarnings {}
    set configurationSaved [dict create]
    set path [configurationPath]
    if {[file isfile $path]} {
        set ini [parseIni $path]
        dict for {key value} $ini {
            if {[string match {user.*} $key]} {
                dict set configurationSaved [string range $key 5 end] $value
            }
        }
    }
    set configurationValues [dict create]
    set configurationSchema [dict create]
    configurationRegisterBuiltins
    if {[llength [info commands ::GX::viewerCommandSchemasRestore]]} {viewerCommandSchemasRestore}
    dict set configurationValues viewers.native3d.preset [native3dGraphicsPresetDetect $configurationValues]
    set configurationLoaded 1
    configurationApply
    return $configurationValues
}

proc ::GX::configurationApply {} {
    variable cfg
    variable workspaceDir
    # Named Storage Profiles are applied host preferences. Session initialization
    # may reload user defaults, but must not silently replace that profile's root.
    set named [expr {[info exists ::GX::workspaceProfileCurrent] && $::GX::workspaceProfileCurrent ne {}}]
    set root [configurationGet storage.session_root]
    if {$named && [info exists workspaceDir(session_root)] && $workspaceDir(session_root) ne {}} {
        set cfg(output_root) $workspaceDir(session_root)
    } elseif {$root ne ""} {
        set cfg(output_root) $root
        if {!$named} {set workspaceDir(session_root) $root}
    }
    set export [configurationGet storage.export_dir]
    if {$named && [info exists workspaceDir(export_dir)] && $workspaceDir(export_dir) ne {}} {set cfg(export_dir) $workspaceDir(export_dir)} elseif {$export ne ""} {set cfg(export_dir) $export}
    set ::env(GXTXT_SCIENTIFIC_LIBRARY_ROOT) [configurationGet libraries.scientific_root]
    configurationApplyRuntime
    # Theme/font changes are startup-only. Recovery policy is safe for subsequent
    # maps immediately; Session/default reloads must not restyle existing windows.
    if {[llength [info commands winfo]] && [winfo exists .] &&
        [info exists ::GX::ui(appearanceInitialized)]} {uiFieldComboboxInstall}
}

proc ::GX::configurationApplyRuntime {} {
    variable cfg
    if {[catch {set cfg(octave_cmd) [runtimeToolResolve octave]} reason]} {
        set cfg(octave_cmd) ""
        lappend ::GX::configurationWarnings "runtime.octave: $reason"
    }
    parallelExecutionConfigure [dict create \
        max_workers [configurationGet computation.max_workers] \
        default_workers [configurationGet computation.default_workers]]
}

proc ::GX::configurationTempDirectory {} {
    set value [string trim [configurationGet storage.temp_dir]]
    if {$value eq ""} { error "Configure a temporary directory in Configuration > Storage." }
    set path [file normalize $value]
    file mkdir $path
    return $path
}

proc ::GX::configurationCacheDirectory {} {
    set value [string trim [configurationGet storage.cache_dir]]
    if {$value eq ""} { error "Configure a cache directory in Configuration > Storage." }
    set path [file normalize $value]
    file mkdir $path
    return $path
}

proc ::GX::configurationSave {{fields {}} {apply 1}} {
    variable configurationSchema
    variable configurationValues
    variable configurationSaved
    if {![string is boolean -strict $apply]} {error {Configuration apply flag must be boolean}}
    foreach id $fields {
        if {![dict exists $configurationSchema $id] || [dict get $configurationSchema $id scope] ni {user module}} {error "Cannot persist Configuration field: $id"}
    }
    set path [configurationPath]
    file mkdir [file dirname $path]
    set temp "${path}.[pid].tmp"
    set fd [open $temp w]
    fconfigure $fd -encoding utf-8 -translation lf
    try {
        puts $fd "; GX-TXT Configuration API v1 user defaults"
        puts $fd "\[user\]"
        set saved $configurationSaved
        dict for {id descriptor} $configurationSchema {
            if {[dict get $descriptor scope] in {user module} && ($fields eq {} || $id in $fields)} {dict set saved $id [configurationValidate $id [dict get $configurationValues $id]]}
        }
        foreach id [lsort -dictionary [dict keys $saved]] {putKV $fd $id [dict get $saved $id]}
    } finally { close $fd }
    set existed [file isfile $path]
    set backup ${path}.[pid].previous
    if {$existed} {file copy -force -- $path $backup}
    try {
        file rename -force -- $temp $path
        if {$apply} {configurationApply}
        set configurationSaved $saved
    } on error {message options} {
        if {$existed} {file rename -force -- $backup $path} else {file delete -force -- $path}
        return -options $options $message
    } finally {file delete -force -- $temp $backup}
    return $path
}

proc ::GX::runtimeToolDetect {name} {
    set candidates [dict create octave {octave octave-cli} python {python3 python} \
        ffmpeg {ffmpeg} ffprobe {ffprobe} tesseract {tesseract} spice {ngspice} gmsh {gmsh} getdp {getdp} mpi {mpirun mpiexec} latex {latexmk pdflatex xelatex lualatex} bibtex {bibtex} biber {biber} \
        magick {magick} pdftoppm {pdftoppm} mutool {mutool} qpdf {qpdf}]
    if {![dict exists $candidates $name]} { error "Unknown runtime tool '$name'." }
    if {$::tcl_platform(platform) eq "windows"} {
        set installation [file dirname $::GX::scriptDir]
        set localNames [dict create \
            octave {runtime/octave/Octave-11.3.0/mingw64/bin/octave-cli.exe} \
            python {runtime/msys64/ucrt64/bin/python.exe} \
            ffmpeg {tools/ffmpeg/ffmpeg.exe} ffprobe {tools/ffmpeg/ffprobe.exe} \
            tesseract {runtime/msys64/ucrt64/bin/tesseract.exe} \
            spice {runtime/msys64/ucrt64/bin/ngspice.exe} \
            mpi {runtime/msys64/ucrt64/bin/mpiexec.exe} \
            magick {runtime/msys64/ucrt64/bin/magick.exe} \
            pdftoppm {runtime/msys64/ucrt64/bin/pdftoppm.exe} \
            mutool {runtime/msys64/ucrt64/bin/mutool.exe} \
            qpdf {runtime/msys64/ucrt64/bin/qpdf.exe}]
        set localPath {}
        if {[dict exists $localNames $name]} {set localPath [file join $installation [dict get $localNames $name]]}
        if {[file isfile $localPath]} { return [file normalize $localPath] }
    }
    foreach command [dict get $candidates $name] {
        set resolved [auto_execok $command]
        if {$resolved ne ""} { return $resolved }
    }
    if {$name eq "octave" && $::tcl_platform(platform) eq "windows"} {
        set known {C:/Program Files/GNU Octave/Octave-11.3.0/mingw64/bin/octave-cli.exe}
        if {[file isfile $known]} { return $known }
    }
    return ""
}

proc ::GX::runtimeToolResolve {name} {
    set value [configurationGet runtime.$name]
    if {$value eq "auto" || $value eq ""} { return [runtimeToolDetect $name] }
    if {[file isfile $value]} { return $value }
    set found [auto_execok $value]
    if {$found ne ""} { return $found }
    error "Configured runtime tool '$name' was not found: $value"
}

proc ::GX::runtimeToolRequired {name} {
    set path [runtimeToolResolve $name]
    if {$path eq ""} { error "Required runtime tool '$name' is unavailable; configure it in Configuration > Runtime." }
    return $path
}

proc ::GX::runtimeToolStatus {name} {
    if {[catch {set path [runtimeToolResolve $name]} reason] || $path eq ""} {
        return [dict create available 0 path "" message [expr {[info exists reason] ? $reason : "Not detected"}]]
    }
    set flag [expr {$name in {ffmpeg ffprobe} ? "-version" : ($name in {pdftoppm mutool} ? "-v" : "--version")}]
    if {[catch {exec $path $flag 2>@1} output]} {
        return [dict create available 0 path $path message [lindex [split $output "\n"] 0]]
    }
    return [dict create available 1 path $path version [lindex [split $output "\n"] 0]]
}

proc ::GX::defaults_before_core_ui_surfaces {} {
    ::GX::defaults_before_configuration_v1
    configurationLoad
}

proc ::GX::openSessionPath {path} {
    set result [::GX::openSessionPath_before_configuration_v1 $path]
    # Session manifests may carry an old machine's runtime path. A configured
    # user override remains authoritative for this installation after reopen.
    if {$::GX::configurationLoaded} { configurationApply }
    return $result
}

source [file join [file dirname [info script]] configuration_modules_v1.tcl]
source [file join [file dirname [info script]] configuration_viewer_commands.tcl]
source [file join [file dirname [info script]] configuration_latex_v1.tcl]
