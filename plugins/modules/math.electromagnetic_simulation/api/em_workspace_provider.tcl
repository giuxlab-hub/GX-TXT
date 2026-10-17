# Lazy host-only discovery adapter: Workspace validation/open precedes Module API
# activation in the existing host. Science remains in the public native service.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::EMWorkspace {}
proc ::GX::EMWorkspace::validate {payload} {
    ::GX::modulePublicApiActivate math.electromagnetic_simulation ELECTROMAGNETIC_SIMULATION_API_v1
    tailcall ::GX::ElectromagneticSimulation::workspaceValidate $payload
}
proc ::GX::EMWorkspace::open {id} {
    ::GX::modulePublicApiActivate math.electromagnetic_simulation ELECTROMAGNETIC_SIMULATION_API_v1
    tailcall ::GX::ElectromagneticSimulation::workspaceOpen $id
}
