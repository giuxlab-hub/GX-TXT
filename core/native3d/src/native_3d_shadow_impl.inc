// SPDX-License-Identifier: GPL-3.0-or-later
// Public shadow policy; VTK pass implementation is in the renderer include.
gx3de_result gx3de_scene_shadows_set(gx3de_scene* scene,uint32_t enabled) {
    if(!scene||enabled>1)return GX3DE_INVALID_ARGUMENT;
    scene->shadows_enabled=enabled!=0;return GX3DE_OK;
}
gx3de_result gx3de_scene_shadows_get(gx3de_scene* scene,uint32_t* enabled) {
    if(!scene||!enabled)return GX3DE_INVALID_ARGUMENT;
    *enabled=scene->shadows_enabled;return GX3DE_OK;
}
gx3de_result gx3de_object_shadow_flags_set(gx3de_object* object,uint32_t casts,
                                             uint32_t receives) {
    if(!object||casts>1||receives>1)return GX3DE_INVALID_ARGUMENT;
    object->casts_shadows=casts!=0;object->receives_shadows=receives!=0;return GX3DE_OK;
}
gx3de_result gx3de_object_shadow_flags_get(gx3de_object* object,uint32_t* casts,
                                             uint32_t* receives) {
    if(!object||!casts||!receives)return GX3DE_INVALID_ARGUMENT;
    *casts=object->casts_shadows;*receives=object->receives_shadows;return GX3DE_OK;
}
gx3de_result gx3de_view_light_shadow_set(gx3de_view* view,uint32_t index,uint32_t enabled) {
    if(!view||index>=4||enabled>1)return GX3DE_INVALID_ARGUMENT;
    const uint32_t bit=1u<<index;
    view->shadow_light_mask=(view->shadow_light_mask&~bit)|(enabled?bit:0);
    return GX3DE_OK;
}
gx3de_result gx3de_view_light_shadow_get(gx3de_view* view,uint32_t index,uint32_t* enabled) {
    if(!view||index>=4||!enabled)return GX3DE_INVALID_ARGUMENT;
    *enabled=(view->shadow_light_mask>>index)&1u;return GX3DE_OK;
}
