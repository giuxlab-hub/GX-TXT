/* Metrohm IC Net CHW native reader API.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#ifndef GX_CHW_READER_H
#define GX_CHW_READER_H
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#define CHW_MAX_FILE_BYTES (128u * 1024u * 1024u)
#define CHW_MAX_SAMPLES 2000000u
#define CHW_SAMPLE_CHUNK 4096u

typedef struct {
    uint32_t sample_count;
    double interval_s;          /* exact promotion from source binary32 */
    double adc_step;            /* exact promotion from source binary32 */
} chw_signal;

typedef struct {
    uint32_t number, start_point, apex_point, end_point;
    double retention_min;
    const char *component;     /* borrowed UTF8, valid only during callback */
    size_t component_bytes;    /* excludes final NUL, includes embedded NUL */
} chw_peak;

typedef struct {
    /* Callback return0 means success; nonzero aborts reading with CHW_CALLBACK.
     * Strings and ADC arrays are borrowed and never retained after callback.
     * A late parse/I/O failure can occur after callbacks; caller must discard
     * partial outputs and must never treat callback delivery as final success.
     */
    int (*metadata)(void *context, const char *key, const char *value);
    int (*warning)(void *context, const char *message);
    int (*samples)(void *context, const chw_signal *signal,
                   uint32_t first_index, const int32_t *adc, size_t count);
    int (*peak)(void *context, const chw_peak *peak);
} chw_callbacks;

typedef struct {
    chw_signal signal;
    uint32_t block_count;
    uint32_t mode_counts[4];   /* mode order0,3,4,5 */
    uint32_t peak_count;
    uint64_t file_bytes;
    int32_t first_adc, last_adc, minimum_adc, maximum_adc;
    int32_t first_12_adc[12];
    size_t first_12_count;
} chw_result;

typedef enum {
    CHW_OK = 0, CHW_IO = 1, CHW_FORMAT = 2, CHW_LIMIT = 3,
    CHW_MEMORY = 4, CHW_CALLBACK = 5
} chw_status;

typedef struct {
    chw_status code;
    uint64_t offset;
    char message[256];
} chw_error;

/* Caller opens a seekable regular binary file and retains ownership of FILE*.
 * Reader rewinds/seeks but never closes or writes it. filename is the original
 * selected basename for metadata, independent of the RAW snapshot pathname.
 * NULL/empty original_filename produces an empty source.original_filename;
 * nonempty original_filename is UTF8 provenance only, never an output path.
 * NULL callbacks are permitted, enabling inspection without CSV output.
 * Samples arrive in contiguous increasing chunks starting at index0; successful
 * calls deliver exactly sample_count ADCs if a samples callback is supplied.
 * The signal descriptor accompanies every chunk. Metadata may follow samples;
 * all D indices are validated before any peak callback. Callbacks must not
 * modify/seek/close input. Result/error are initialized at entry; result is zero
 * unless the entire read succeeds. FILE remains owned by caller on every exit.
 * All parsing/read/decode work stays in this C library; no registry/publication,
 * shell, Python, compilation, or GUI invocation occurs here.
 * Result is fully valid only after CHW_OK. Internal allocations are freed on
 * every exit, including callback cancellation. Numeric locale is caller-owned:
 * caller guarantees LC_NUMERIC=C (standalone native CLI does so once before
 * processing). Reader does not mutate process locale.
 */
chw_status chw_read(FILE *input, const char *original_filename,
                    const chw_callbacks *callbacks, void *context,
                    chw_result *result, chw_error *error);
#endif
