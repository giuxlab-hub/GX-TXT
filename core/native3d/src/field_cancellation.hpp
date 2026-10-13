/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX3DE_FIELD_CANCELLATION_HPP
#define GX3DE_FIELD_CANCELLATION_HPP
#include <atomic>

/* Internal, caller-thread cancellation scope for native field derivation.
 * The public field ABI is unchanged; animation installs its own token only
 * while it is building a derived layer. */
extern thread_local const std::atomic<bool>* gx3de_field_cancel_flag;
inline bool gx3de_field_cancelled() {
    return gx3de_field_cancel_flag&&gx3de_field_cancel_flag->load(std::memory_order_relaxed);
}
struct gx3de_field_cancel_scope {
    const std::atomic<bool>* previous;
    explicit gx3de_field_cancel_scope(const std::atomic<bool>* flag):previous(gx3de_field_cancel_flag){
        gx3de_field_cancel_flag=flag;
    }
    ~gx3de_field_cancel_scope(){gx3de_field_cancel_flag=previous;}
    gx3de_field_cancel_scope(const gx3de_field_cancel_scope&)=delete;
    gx3de_field_cancel_scope& operator=(const gx3de_field_cancel_scope&)=delete;
};
#endif
