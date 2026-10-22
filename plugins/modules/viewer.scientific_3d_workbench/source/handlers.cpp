// SPDX-License-Identifier: GPL-3.0-or-later
// Declared presentation dispatch only. All geometry, source captures, resource
// ownership, selection, History, recovery and publication stay in public CORE.
namespace workbench {
constexpr unsigned form = 48;
constexpr unsigned purpose_first = 76;
constexpr const char* purpose_commands[] = {
    "import_dataset_form", "combine_form", "extrusion_targets_form", "mesh_pair_form",
    "details_form", "measurement_form", "constraint_form", "measurements_manager",
    "constraints_manager", "organization_manager", "comparison_manager", "texture_form",
    "texture_clear", "export_form", "recipe_manager", "extensions_manager",
    "documents_manager", "translate_form", "rotate_form", "scale_form",
    "reset_transform_form", "tessellate_form", "mesh_clean_form", "mesh_weld_form",
    "mesh_orient_form", "brep_heal_form", "mesh_seam_form", "mesh_lod_form",
    "mesh_boundaries_form", "mesh_intersections_form", "align_three_points_form",
    "clip_form", "clip_cap_form", "section_profile_form", "group_create",
    "group_duplicate", "group_ungroup", "group_translate_form", "group_rotate_form",
    "group_scale_form", "planar_section", "planar_projection", "preview_accept",
    "preview_cancel", "profile_source_form", "extrusion_form", "working_unit_form",
    "working_plane_form", "publish_dataset_form"
};
constexpr unsigned purpose_count = sizeof(purpose_commands) / sizeof(purpose_commands[0]);
static_assert(purpose_count == 49, "The declared purpose actions must match the public finite contract");
}
void on_event(gx::Host& host, gx::State&, const gx::Event& event) {
    if (event.kind == gx::EventKind::open) {
        host.workbench_command(workbench::form, "refresh");
        return;
    }
    if (event.kind != gx::EventKind::invoke) return;
    if (event.component >= workbench::purpose_first &&
        event.component < workbench::purpose_first + workbench::purpose_count) {
        host.workbench_command(workbench::form,
            workbench::purpose_commands[event.component - workbench::purpose_first]);
        return;
    }
    switch (event.component) {
        case 55: host.workbench_command(workbench::form, "refresh"); break;
        case 56: host.workbench_command(workbench::form, "new"); break;
        case 57: host.workbench_command(workbench::form, "open"); break;
        case 58: host.workbench_command(workbench::form, "inspect"); break;
        case 59: host.workbench_command(workbench::form, "primitive"); break;
        case 60: host.workbench_command(workbench::form, "select"); break;
        case 61: host.workbench_command(workbench::form, "save"); break;
        case 62: host.workbench_command(workbench::form, "undo"); break;
        case 63: host.workbench_command(workbench::form, "redo"); break;
        case 64: host.workbench_command(workbench::form, "close"); break;
        case 136: host.workbench_command(workbench::form, "duplicate_object"); break;
        default: break;
    }
}
