#pragma once
struct gx3de_scene;
/* Called by native engine scene teardown before views and objects are freed. */
extern "C" void gx3de_animation_scene_cleanup(gx3de_scene* scene);
