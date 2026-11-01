# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::CurveDigitizer {}
proc ::GX::CurveDigitizer::workspaceValidate {payload} {::GX::nativeWorkspaceJsonValidate gxtxt.curve_digitizer.configuration 1.0 $payload}
proc ::GX::CurveDigitizer::workspaceDecode {typed} {::GX::_nativeWorkspaceLibraryRequire;return [dict create json [::GX::workspaceNative json_encode_lexical $typed]]}
proc ::GX::CurveDigitizer::workspaceOpen {id} {
    ::GX::sessionWorkspaceValidate $id
    ::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_VIEWER_API_v1
    return [_launch $id]
}
