# GX-TXT Mathematics Explorer activation entry point
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::MathematicsExplorer {
    variable moduleId viewer.mathematics_explorer
    variable providerId mathematics_explorer
    variable formatId gxtxt.mathematics_explorer.state
    variable formatVersion 1
}
set _gx_math_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $_gx_math_root lib expression.tcl]
source [file join $_gx_math_root lib science.tcl]
source [file join $_gx_math_root ui mathematics_explorer_tk.tcl]
unset _gx_math_root
::GX::viewerBackendRegister mathematics_explorer_tk ::GX::MathematicsExplorer::viewerDispatch
