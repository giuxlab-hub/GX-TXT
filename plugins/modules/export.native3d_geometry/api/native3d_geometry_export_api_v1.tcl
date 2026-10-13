# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::Native3DGeometryExport {}
proc ::GX::Native3DGeometryExport::step {context} {return [::GX::native3DGeometryExportData $context step]}
proc ::GX::Native3DGeometryExport::stl {context} {return [::GX::native3DGeometryExportData $context stl]}
proc ::GX::Native3DGeometryExport::vtp {context} {return [::GX::native3DGeometryExportData $context vtp]}
proc ::GX::Native3DGeometryExport::publish {context} {return [::GX::native3DGeometryPublishDataset $context [dict get $context parameters format] [dict get $context parameters dataset_id]]}
