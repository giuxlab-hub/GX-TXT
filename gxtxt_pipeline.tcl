#!/usr/bin/env tclsh
# GX-TXT measurement pipeline orchestrator / Tk front-end
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.

# Source changelog (recent)
# - 0.9.8.10-dev-022: text family/filter value selection and refresh through all GUI input paths.
# - 0.9.8.10-dev-021: repaired Plot Dataset selectors and Curve Workbench generation/error recovery in real GUI workflows.
# - 0.9.8.10-dev-020: repaired GUI workflows for Plot Dataset, Curve Workbench, scientific libraries, and Session generators.
# - 0.9.8.10-dev: version and source-tree stabilization after the 0.9.8.09 audit.
# - 0.9.8.09: numerical operation catalog and focused statistics/data-analysis modules.
# - 0.9.8.08: Native 3D integration and canonical Acquisition Handler schema.
# - 0.9.8.07: Graphs controls and detached Clones.
# - 0.9.8.06: Graph Series row filters/family expansion, Octave Script Bridge and managed Scientific Libraries.
# - 0.9.8.05: public numerical and Plot.dataset migration, large-data rendering and stable release validation.
# - 0.9.8.04: time-dependent FFT numerical-stage checkpoint; graphical migration remains open.
# - 0.9.8.03: UV/Vis plot.dataset migration and public 2-D family grouping.
# - 0.9.8.01: spectral-features NUMERIC_API/plot.dataset migration and mandatory numeric-vs-analysis architecture rule.
# - 0.9.8.00: harmonic-analysis NUMERIC_API and plot.dataset migration.
# - 0.9.7.99: fractional-octave plot.dataset migration and generic exact X-interval bar support.
# - 0.9.7.98: NUMERIC_API analytic-signal primitive and completed envelope-spectrum numerical/plot.dataset migration.
# - 0.9.7.97: NUMERIC_API transform primitives, completed cepstrum/cross-spectral numerical migration, and runtime dependency public-API discovery.
# - 0.9.7.86: public standard_octave bridge to persistent PLOT_DATASET_API_v2 operations and the validated uncertainty/Welch/viewer package set.
# - 0.9.7.91: binary Preview guards CSV input and renders media samples without blocking Tk or reading SSH stdin.
# - 0.9.7.90: private archive bundles real IR libraries; versioned reference updates and recoverable removal.
# - 0.9.7.89: parse real OpenSpecy/PNNL signed-packed AFFN JCAMP XYDATA without losing provenance.
# - 0.9.7.88: IR production consumer, spectral Viewer, additional numerical plug-ins and HTML archive-name repair.
# - 0.9.7.87: CORE scientific Spectrum/Reference Library/Import APIs, CORE OCR and headless box-plot repair.
# - 0.9.7.85: central Workspace-profile chooser policy plus the tested external Peaks, cross-spectral and Curve companion set.
# - 0.9.7.84: atomic generic-file Dataset publication plus public plot.dataset histogram and box/whisker representations.
# - 0.9.7.83: generic CORE Dataset Preview for binary/tabular/media datasets with user-local settings and system-open action.
# - 0.9.7.82: module-cache plot variants use base scientific cache without synthetic X/Y Series or recomputation.
# - 0.9.7.81: atomic acquisition staging, rollback and row-local batch failures.
# - 0.9.7.80: bundle the validated Session HTML exporter as a protected CORE module.
# - 0.9.7.79: add portable Session import/export and Session export action hosting.
# - 0.9.7.78: add lazy Viewer backend activation and CORE-owned Session-scoped Interactive Document state.
# - 0.9.7.77: make standard_octave popen2 protocol readers accumulate complete newline-framed records.
# - 0.9.7.76: fix Temporal Set selector None fallback for standard module configuration widgets.
# - 0.9.7.75: add the Dataset-scoped Variables Temporal Set editor over Temporal Set API v1.
# - 0.9.7.74: add Dataset Metadata UTF-8 key=value Import/Export in the existing editor.
# - 0.9.7.71: add Session Generator Library API v1, New Session generator browser/manager and deterministic numerical examples.
# - 0.9.7.70: consolidate the 0.9.7.69 baseline after real-server validation and correct two math.numeric regression tests.
# - 0.9.7.69: restore the 0.9.7.67 Experiment interface while preserving 0.9.7.68 Projects and Instrument Library work.
# - 0.9.7.68: add Projects GUI, reusable scientific notes editor and persistent Instrument Library.
# - 0.9.7.67: add public CORE Parallel Execution API v1.
# - 0.9.7.66: add persistent Project API v1 above Experiment.
# - 0.9.7.65: integrate math.numeric 1.1.0 and refine the Session bar / empty-session creation.
# - 0.9.7.64: integrate acq.image_binary 1.2.0 with public Dataset Metadata image/container metadata.
# - 0.9.7.63: integrate acq.audio 1.0.1 as CORE / OFF with public Audio Decode + Dataset Metadata runtime paths.
# - 0.9.7.62: validated consolidation, safe same-owner Publication v2 replacement,
#   runtime/cache recovery guidance, and current API inventory.
# - 0.9.7.61: analysis.fft_spectrum 2.1.0 consumes public Temporal Set API v1 members.
# - 0.9.7.60: public elapsed_time requested-unit conversion backed by Unit Registry API v1.
# - 0.9.7.59: formal public elapsed_time numeric-seconds contract and cross-path regression protection.
# - 0.9.7.58: public Temporal Set API v1 for reusable segments/windows and standard_octave runtime binding.
# - 0.9.7.57: public Dataset Metadata -> standard_octave Analysis Source runtime bridge.
# - 0.9.7.46: multi-panel shared-X/right-Y reuse the single-panel axis synchronization path.
# - 0.9.7.45: preserve full base/variant graph keys in variant artifact axis maps.
# - 0.9.7.44: recognize panel-scoped right-Y overlay axes during stacked output finalization.
# - 0.9.7.43: notebook-safe scrollable plot editors and independent per-panel Y validation.
# - 0.9.7.42: stale Graph Series pruning plus scrollable/provider-annotated Series editor.
# - 0.9.7.41: multi-panel controls in the shared Axes dialog plus provider-specific panel presentation extensions.
# - 0.9.7.40: plot.dataset multi-panel title/legend fixes and public panel discovery in stackedGraphPanels.
# - 0.9.7.39: Graph Configuration Extension API v1 for plot.dataset multi-panel configuration.
# - 0.9.7.38: Acquisition Dataset Metadata handoff, audio tags and explicit raw PCM hints.
# - 0.9.7.37: typed binary numeric reads through Canonical Dataset v2 and Table Stream v3.
# - 0.9.7.36: generic persistent Dataset Metadata API and Variables editor.
# - 0.9.7.35: safe session-scoped canonical dataset deletion and Variables GUI action.
# - 0.9.7.34: shared-display Dataset Selection for heterogeneous Graph Series X bindings.
# - 0.9.7.33: integrated plot.dataset 2.1.6.
# - 0.9.7.32: integrated plot.dataset 2.1.5.
# - 0.9.7.31: Variant Editor commits embedded Series Editor provider state.
# - 0.9.7.30: typed Publication v2 numeric transport and analysis.audio_decode 2.0.0.
# - 0.9.7.29: plot.dataset 2.1.4 and robust variant/dual-Y Region Selection calibration.
# - 0.9.7.28: standard_octave Publication v2 bridge and Audio Decode API v1.
# - 0.9.7.27: Final Large Dataset architecture audit and validation.
# - 0.9.7.26: CORE Storage Auto policy and reusable Dataset materialization cache.
# - 0.9.7.25: Table Stream API v3 backend-neutral table-shaped streaming facade.
# - 0.9.7.24: Dataset Publication API v2 and backend-neutral transactional writers.
# - 0.9.7.23: dual-Y grid ownership and Canonical Dataset API v2 large-data foundation.
# - 0.9.7.22: deterministic provider activation, graph-addressed axes and stable graph USE.
# - 0.9.7.21: generic provider extensions for the standard Series Editor.
# - 0.9.7.20: dataset.extract 1.2.0 promoted to protected CORE / OFF.
# - 0.9.7.8: Graph Series API for independent multi-dataset bindings.
# - 0.9.7.7: Unit Registry API, explicit safe conversions and Variables help.
# - 0.9.7.6: Semantic Registry API and visible role provenance/inference.
# - 0.9.7.5: FFT single-sided normalization preserves the even-N Nyquist bin.
# - 0.9.7.4: immutable canonical schema snapshots make Use reversible
#   for CSV datasets whose importer has no RAW regeneration provider.
# - 0.9.7.3: Dataset Variable Schema API v2 and Table Stream API v2 add
#   stable variable identities, editable imported schema and typed table input.
# - 0.9.7.2: Curve Family Fitting and Sequential Table Join promoted to
#   protected CORE / OFF; scientific implementations unchanged.
# - 0.9.7.1: Unit/Dimension API accepts semantic level units dB, dBFS and FS
#   as identity-preserved, non-linear/non-SI metadata; Tektronix current-log
#   importer promoted from ALWAYS to protected CORE / OFF.
# - 0.9.7: acq.image_binary v1.1.0 promoted to CORE.
# Full release history: CHANGELOG.md

namespace eval ::GX {
    variable version "0.9.8.10-dev-104"
    variable scriptDir [file dirname [file normalize [info script]]]
    variable cfg
    variable ch
    variable probe
    variable extra
    variable ui
    variable pipe ""
    variable pipePids {}
    variable currentSession ""
    variable cliMode 0
    variable analysisPipe ""
    variable analysisPids {}
    variable analysisQueue {}
    variable analysisTotal 0
    variable analysisDone 0
    variable graphUse
    variable runAllPending 0
    variable moduleCatalog
    variable moduleOrder {}
    variable moduleSearch ""
    variable moduleKindFilter "All"
    variable moduleGroupFilter "All"
    variable customCompare
    variable customCompareCount 0
    variable legendOverride
    variable axisOverride
    variable analysisOperation "Analysis"
    variable legendPickActive 0
}

source [file join $::GX::scriptDir app configuration_manifest.tcl]
source [file join $::GX::scriptDir app module_catalog.tcl]
source [file join $::GX::scriptDir app legacy_session_runtime.tcl]
source [file join $::GX::scriptDir app legacy_run_controller.tcl]
source [file join $::GX::scriptDir app acquisition_controller.tcl]
source [file join $::GX::scriptDir app session_controller.tcl]
source [file join $::GX::scriptDir app plot_runtime.tcl]
source [file join $::GX::scriptDir app graph_dialogs.tcl]
source [file join $::GX::scriptDir app analysis_controller.tcl]
source [file join $::GX::scriptDir app graph_browser.tcl]
source [file join $::GX::scriptDir app print_controller.tcl]
source [file join $::GX::scriptDir app modules_page_controller.tcl]
source [file join $::GX::scriptDir app plot_comparison.tcl]
source [file join $::GX::scriptDir app run_page_controller.tcl]
source [file join $::GX::scriptDir app main_window.tcl]
source [file join $::GX::scriptDir app cli_usage.tcl]
source [file join $::GX::scriptDir core tcl module_api_v1.tcl]
source [file join $::GX::scriptDir core tcl plot_layout_controls_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_inspection_api_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_publication_api_v1.tcl]
source [file join $::GX::scriptDir core tcl workspace_profiles_api_v1.tcl]
source [file join $::GX::scriptDir core tcl preview_descriptor_api_v1.tcl]
source [file join $::GX::scriptDir core tcl acquisition_handler_api_v1.tcl]
source [file join $::GX::scriptDir core tcl session_file_explorer_api_v1.tcl]
source [file join $::GX::scriptDir core tcl session_portable_api_v1.tcl]
source [file join $::GX::scriptDir core tcl session_inspection_api_v1.tcl]
source [file join $::GX::scriptDir core tcl analysis_source_metadata_api_v1.tcl]
source [file join $::GX::scriptDir core tcl plot_region_selection_api_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_notes_api_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_metadata_api_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_private_metadata_api_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_namespace_api_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_selection_api_v1.tcl]
source [file join $::GX::scriptDir core tcl repeatable_config_api_v1.tcl]
source [file join $::GX::scriptDir core tcl numeric_expression_browser_v1.tcl]
source [file join $::GX::scriptDir core tcl plugin_install_api_v1.tcl]
source [file join $::GX::scriptDir core tcl plugin_bundle_api_v1.tcl]
source [file join $::GX::scriptDir core tcl session_generator_library_api_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_plot_framework_api_v1.tcl]
source [file join $::GX::scriptDir core tcl computed_data_annotation_api_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_variable_schema_api_v2.tcl]
source [file join $::GX::scriptDir core tcl semantic_registry_api_v1.tcl]
source [file join $::GX::scriptDir core tcl unit_registry_api_v1.tcl]
source [file join $::GX::scriptDir core tcl elapsed_time_requested_unit_api_v1.tcl]
source [file join $::GX::scriptDir core tcl graph_series_api_v1.tcl]
source [file join $::GX::scriptDir core tcl series_editor_extension_api_v1.tcl]
# plot.dataset multi-panel: load the public Graph Configuration Extension API v1.
source [file join $::GX::scriptDir core tcl graph_config_extension_api_v1.tcl]
# plot.dataset multi-panel: expose provider-specific controls inside the shared Axes dialog.
source [file join $::GX::scriptDir core tcl axis_config_extension_api_v1.tcl]
source [file join $::GX::scriptDir core tcl level_scale_api_v1.tcl]
source [file join $::GX::scriptDir core tcl interactive_document_api_v1.tcl]
source [file join $::GX::scriptDir core tcl viewer_provider_api_v1.tcl]
source [file join $::GX::scriptDir core tcl viewer_provider_catalog.tcl]
source [file join $::GX::scriptDir app gui viewer_catalog.tcl]
source [file join $::GX::scriptDir core tcl plot_module_variants.tcl]
source [file join $::GX::scriptDir core tcl graph_workflow_api_v1.tcl]
source [file join $::GX::scriptDir core tcl session_action_provider_api_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_variable_schema_api_v3.tcl]
source [file join $::GX::scriptDir core tcl canonical_dataset_api_v2.tcl]
source [file join $::GX::scriptDir core tcl dataset_publication_api_v2.tcl]
source [file join $::GX::scriptDir core tcl dataset_file_publication_api_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_storage_policy_v1.tcl]
source [file join $::GX::scriptDir core tcl audio_decode_api_v1.tcl]
source [file join $::GX::scriptDir core tcl analysis_source_access_api_v2.tcl]
source [file join $::GX::scriptDir core tcl table_stream_api_v3.tcl]
source [file join $::GX::scriptDir core tcl tabular_text_api_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_preview_api_v1.tcl]
source [file join $::GX::scriptDir core tcl analysis_source_dataset_metadata_runtime_v1.tcl]
source [file join $::GX::scriptDir core tcl temporal_set_api_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_rename_api_v1.tcl]
source [file join $::GX::scriptDir core tcl temporal_set_gui_v1.tcl]
source [file join $::GX::scriptDir core tcl project_api_v1.tcl]
source [file join $::GX::scriptDir core tcl session_persistence_api_v1.tcl]
source [file join $::GX::scriptDir core tcl parallel_execution_api_v1.tcl]
source [file join $::GX::scriptDir core tcl parallel_execution_octave_service_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_notes_editor_v1.tcl]
source [file join $::GX::scriptDir core tcl instrument_library_api_v1.tcl]
source [file join $::GX::scriptDir core tcl project_gui_v1.tcl]
source [file join $::GX::scriptDir core tcl detached_plot_clone.tcl]
source [file join $::GX::scriptDir core tcl graph_selection_api_v1.tcl]
source [file join $::GX::scriptDir core tcl graph_selection_gui_v1.tcl]
source [file join $::GX::scriptDir core tcl configuration_api_v1.tcl]
source [file join $::GX::scriptDir core tcl resource_management_api_v1.tcl]
source [file join $::GX::scriptDir app gui cache_storage_panel.tcl]
source [file join $::GX::scriptDir core tcl importer_builder_api_v1.tcl]
source [file join $::GX::scriptDir core tcl script_execution_api_v1.tcl]
source [file join $::GX::scriptDir core tcl script_job_api_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_execution_api_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_io_api_v1.tcl]
source [file join $::GX::scriptDir core tcl resource_lifecycle_api_v1.tcl]
source [file join $::GX::scriptDir core tcl script_module_runner_v1.tcl]
source [file join $::GX::scriptDir core tcl ui_surface_api_v1.tcl]
source [file join $::GX::scriptDir core tcl documentation_browser_api_v1.tcl]
source [file join $::GX::scriptDir app gui scientific_text_editor.tcl]

# Short labels keep both Plots toolbar rows horizontal; full actions remain
source [file join $::GX::scriptDir app graph_toolbar_tips.tcl]
source [file join $::GX::scriptDir app dataset_page_actions.tcl]
source [file join $::GX::scriptDir app dataset_coordinate_surface.tcl]
source [file join $::GX::scriptDir app gui dataset_browser.tcl]
source [file join $::GX::scriptDir app gui importer_builder_dialog.tcl]
source [file join $::GX::scriptDir app gui script_library_dialog.tcl]
source [file join $::GX::scriptDir app gui resource_lifecycle_dialog.tcl]
source [file join $::GX::scriptDir app acquisition_workflow.tcl]
source [file join $::GX::scriptDir app script_workspace_surface.tcl]
source [file join $::GX::scriptDir app script_jobs_surface.tcl]
source [file join $::GX::scriptDir core tcl script_source_declaration_api_v1.tcl]
source [file join $::GX::scriptDir app gui documentation_browser.tcl]
source [file join $::GX::scriptDir app sessions_page_redesign.tcl]
source [file join $::GX::scriptDir app run_page_redesign.tcl]
source [file join $::GX::scriptDir core tcl single_analysis_module_api_v1.tcl]
source [file join $::GX::scriptDir core tcl graph_resource_api_v1.tcl]
source [file join $::GX::scriptDir core tcl portable_resource_api_v1.tcl]
source [file join $::GX::scriptDir core tcl graph_renderer_dispatch_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_catalog_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_preview_paging_v1.tcl]
source [file join $::GX::scriptDir core tcl native2d_host_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_transform_api_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_transform_responsive_v1.tcl]
source [file join $::GX::scriptDir core tcl ui_field_api_v1.tcl]
source [file join $::GX::scriptDir core tcl viewer_gui_host_api_v1.tcl]
source [file join $::GX::scriptDir core tcl curve_source_api_v1.tcl]
source [file join $::GX::scriptDir core tcl curve_source_async_v1.tcl]
source [file join $::GX::scriptDir core tcl native2d_presentation_v1.tcl]
source [file join $::GX::scriptDir core tcl interactive_document_resource_api_v1.tcl]
source [file join $::GX::scriptDir core tcl session_workspace_api_v1.tcl]
source [file join $::GX::scriptDir core tcl file_publication_api_v1.tcl]
source [file join $::GX::scriptDir core tcl native3d_gui_host_v1.tcl]
source [file join $::GX::scriptDir core tcl statistical_result_semantics_api_v1.tcl]
source [file join $::GX::scriptDir core tcl native3d_geometry_api_v1.tcl]
source [file join $::GX::scriptDir core tcl native3d_organization_v1.tcl]
source [file join $::GX::scriptDir core tcl native3d_section_comparison_v1.tcl]
source [file join $::GX::scriptDir core tcl native3d_geometry_export_v1.tcl]
source [file join $::GX::scriptDir core tcl native2d_geometry_api_v1.tcl]
source [file join $::GX::scriptDir core tcl native2d_viewport_host_v1.tcl]
source [file join $::GX::scriptDir core tcl native2d_preview_v1.tcl]
source [file join $::GX::scriptDir core tcl workbench_extension_api_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_recipe_api_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_recipe_gui_v1.tcl]
source [file join $::GX::scriptDir core tcl workbench_extension_gui_v1.tcl]
source [file join $::GX::scriptDir core tcl workbench_recovery_api_v1.tcl]
source [file join $::GX::scriptDir core tcl interactive_document_lifecycle_v1.tcl]
source [file join $::GX::scriptDir app gui interactive_document_manager.tcl]
source [file join $::GX::scriptDir app gui configuration_modules.tcl]
source [file join $::GX::scriptDir core tcl parameter_service_api_v1.tcl]
source [file join $::GX::scriptDir core tcl sketch_dataset_api_v1.tcl]
source [file join $::GX::scriptDir core tcl parameter_editor.tcl]
source [file join $::GX::scriptDir core tcl experiment_duplication_policy_api_v1.tcl]
source [file join $::GX::scriptDir core tcl session_experiment_api_v1.tcl]
source [file join $::GX::scriptDir app session_experiment_gui.tcl]
source [file join $::GX::scriptDir app session_menus_dev065.tcl]
proc ::GX::main {} {
    ::GX::defaults
    ::GX::loadModuleCatalog

    set args $::argv
    if {[lsearch -exact $args --help] >= 0 || [lsearch -exact $args -h] >= 0} {
        ::GX::usage
        return 0
    }

    set mpos [lsearch -exact $args --manifest]
    if {$mpos >= 0 && [lsearch -exact $args --run] >= 0} {
        if {$mpos + 1 >= [llength $args]} { puts stderr "Missing file after --manifest"; return 2 }
        set mf [lindex $args [expr {$mpos + 1}]]
        if {[catch {::GX::runSync $mf} err opts]} {
            puts stderr $err
            return 1
        }
        return 0
    }

    ::GX::launchGui
    return 0
}

source [file join $::GX::scriptDir core tcl dataset_viewer_api_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_dataset_coordinates_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_dataset_filters_v1.tcl]
source [file join $::GX::scriptDir core tcl dataset_preview_cache.tcl]
source [file join $::GX::scriptDir core tcl dataset_scientific_profile_api_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_dataset_series_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_dataset_preview_v1.tcl]

source [file join $::GX::scriptDir core tcl mesh_dataset_viewer_v1.tcl]
source [file join $::GX::scriptDir core tcl native3d_compact_preview_v1.tcl]

source [file join $::GX::scriptDir app gui dataset_preview_sync.tcl]
source [file join $::GX::scriptDir app gui dataset_preview_live.tcl]
source [file join $::GX::scriptDir app gui session_preview_cache_page.tcl]
source [file join $::GX::scriptDir app gui compute_nodes.tcl]

source [file join $::GX::scriptDir core tcl geometry_exchange_api_v1.tcl]
source [file join $::GX::scriptDir core tcl native3d_planar_workflow_v1.tcl]
source [file join $::GX::scriptDir core tcl native3d_planar_gui_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_multiview_host_api_v1.tcl]
source [file join $::GX::scriptDir app session_instrumentation_gui.tcl]

source [file join $::GX::scriptDir core tcl installation_identity_api_v1.tcl]
source [file join $::GX::scriptDir core tcl session_storage_profiles_api_v1.tcl]
source [file join $::GX::scriptDir app storage_identity_gui.tcl]

source [file join $::GX::scriptDir core tcl project_experiment_management_v1.tcl]
source [file join $::GX::scriptDir core tcl scientific_origin_v1.tcl]
source [file join $::GX::scriptDir core tcl project_portable_api_v1.tcl]
source [file join $::GX::scriptDir app project_experiment_browser.tcl]

# Source-safe entry point: tests and external tools may source this file in place
# without relocating it and therefore without corrupting ::GX::scriptDir.
if {[file normalize [info script]] eq [file normalize $argv0]} {
    set rc [::GX::main]
    if {$rc != 0} { exit $rc }
}
