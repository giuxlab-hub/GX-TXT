# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::PdfOcrViewer {}
proc ::GX::PdfOcrViewer::workspaceValidate {payload} {::GX::nativeWorkspaceJsonValidate gxtxt.pdf_ocr.workspace 1.0 $payload}
proc ::GX::PdfOcrViewer::workspaceOpen {id} {
    ::GX::sessionWorkspaceValidate $id
    ::GX::modulePublicApiActivate viewer.pdf_ocr PDF_OCR_VIEWER_API_v1
    return [_launch [dict create workspace_id $id]]
}
