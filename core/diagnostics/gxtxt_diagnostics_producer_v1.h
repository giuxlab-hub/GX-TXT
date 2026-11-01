/* SPDX-License-Identifier: GPL-3.0-or-later
 * Trusted CORE producer attachment. No Tcl/Tk calls, threads, queues or disk I/O.
 * Descriptor is a per-generation capability supplied only by the CORE host.
 */
#ifndef GXTXT_DIAGNOSTICS_PRODUCER_V1_H
#define GXTXT_DIAGNOSTICS_PRODUCER_V1_H
#define GXDIAG_PRODUCER_ABI_V1 1
#define GXDIAG_MAX_PAYLOAD_BYTES_V1 32768
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct gxdiag_producer_v1 gxdiag_producer_v1;
typedef struct gxdiag_origin_v1 {
    const char *source, *component, *module_id, *viewer_id, *job_id, *api_id;
    const char *operation, *process_id, *stream, *severity, *chunk_id, *chunk_index;
} gxdiag_origin_v1;
enum gxdiag_result_v1 {
    GXDIAG_QUEUED_V1=0, GXDIAG_OFF_V1=1, GXDIAG_OVERLOAD_V1=2,
    GXDIAG_OVERSIZE_V1=3, GXDIAG_BROKEN_IPC_V1=4, GXDIAG_INVALID_V1=5
};
/* Attach maps only the fixed-format descriptor's private status page and connects
 * one nonblocking UNIX endpoint. No retry or acknowledgement wait. *out=NULL on
 * failure; error is optional caller-owned storage. OFF means stale/not running.
 */
int gxdiag_producer_attach_v1(const char *descriptor, gxdiag_producer_v1 **out,
                             char *error, size_t error_capacity);
/* UTF-8 origins: <=512 bytes each/2048 total; NULL fields become "unknown".
 * Raw payload <=32768 bytes. process_id is the actual captured child's identity,
 * supplied by its owner; capture_pid is always getpid() of this calling process.
 * Calls for a handle must be serialized by its owner. There is no hidden retry.
 */
int gxdiag_producer_emit_v1(gxdiag_producer_v1 *producer,
                          const gxdiag_origin_v1 *origin,
                          const void *payload, size_t payload_bytes);
void gxdiag_producer_close_v1(gxdiag_producer_v1 *producer);
#ifdef __cplusplus
}
#endif
#endif
