# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::InstallationIdentity {}
proc ::GX::InstallationIdentity::root {} {
    if {[info exists ::env(GXTXT_INSTALLATION_ROOT)] && [string trim $::env(GXTXT_INSTALLATION_ROOT)] ne {}} {
        return [file join [file normalize $::env(GXTXT_INSTALLATION_ROOT)] identity]
    }
    # Deployment path is the instance anchor; replacing its release tree preserves the sibling ledger.
    set path [file normalize $::GX::scriptDir]
    return [file join [file dirname $path] .gxtxt-installation-[file tail $path] identity]
}
proc ::GX::InstallationIdentity::host {operation {reason {}}} {
    set python [auto_execok python3]
    if {$python eq {}} {set python [auto_execok python]}
    if {$python eq {}} {error {Installation identity requires the supported Python runtime.}}
    return [exec {*}$python -B [file join $::GX::scriptDir core installation_identity.py] [root] $operation $reason]
}
proc ::GX::installationIdentityInfo {} {return [::GX::InstallationIdentity::host read]}
proc ::GX::installationIdentityCurrent {} {return [dict get [installationIdentityInfo] current]}
proc ::GX::installationIdentityHistory {} {return [dict get [installationIdentityInfo] history]}
# Initialization is part of normal CORE source/startup, including headless clients.
::GX::installationIdentityInfo
