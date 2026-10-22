/* Metrohm CHW process/CSV adapter. SPDX-License-Identifier: GPL-3.0-or-later. */
#define _POSIX_C_SOURCE 200809L
#include "chw_reader.h"
#include <errno.h>
#include <inttypes.h>
#include <locale.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define MAX_JOBS 1024

typedef struct {
    const char *input, *original, *csv, *peaks;
} job;

typedef struct {
    FILE *csv, *peaks;
    uint32_t next_sample;
    int summary_peaks;
} output_state;

static int b64n(FILE *f, const char *value, size_t n) {
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const unsigned char *p = (const unsigned char *)value;
    size_t i;
    for (i = 0; i < n; i += 3) {
        unsigned a = p[i], b = i+1 < n ? p[i+1] : 0, c = i+2 < n ? p[i+2] : 0;
        if (fputc(alphabet[a>>2], f) == EOF || fputc(alphabet[((a&3)<<4)|(b>>4)], f) == EOF ||
            fputc(i+1<n ? alphabet[((b&15)<<2)|(c>>6)] : '=', f) == EOF ||
            fputc(i+2<n ? alphabet[c&63] : '=', f) == EOF) return -1;
    }
    return 0;
}

static int b64(FILE *f, const char *value) {
    return b64n(f,value,strlen(value));
}

static int metadata(void *context, const char *key, const char *value) {
    (void)context;
    if (fputs("M\t", stdout) == EOF || b64(stdout,key) || fputc('\t',stdout) == EOF ||
        b64(stdout,value) || fputc('\n',stdout) == EOF) return -1;
    return 0;
}

static int warning(void *context, const char *message) {
    (void)context;
    if (fputs("W\t",stdout) == EOF || b64(stdout,message) || fputc('\n',stdout) == EOF) return -1;
    return 0;
}

static int samples(void *context, const chw_signal *signal, uint32_t first,
                   const int32_t *adc, size_t count) {
    output_state *out = context;
    size_t i;
    if (first != out->next_sample || first > signal->sample_count || count > signal->sample_count - first) return -1;
    if (out->csv) for (i = 0; i < count; ++i) {
        double seconds = (double)(first+(uint32_t)i) * signal->interval_s;
        if (fprintf(out->csv,"%.15g,%.15g,%.15g,%" PRId32 "\n",seconds,seconds/60.,
                    (double)adc[i]*signal->adc_step,adc[i]) < 0) return -1;
    }
    out->next_sample += (uint32_t)count;
    return 0;
}

static int csv_text_n(FILE *f, const char *value, size_t bytes) {
    const unsigned char *p = (const unsigned char *)value;
    size_t i;
    if (fputc('"',f) == EOF) return -1;
    for (i = 0; i < bytes; ++i,++p) {
        if (*p == '"' && fputc('"',f) == EOF) return -1;
        if (fputc(*p == '\r' || *p == '\n' ? ' ' : *p,f) == EOF) return -1;
    }
    return fputc('"',f) == EOF ? -1 : 0;
}

static int peak(void *context, const chw_peak *p) {
    output_state *out = context;
    if (!out->summary_peaks && (fprintf(stdout,"P\t%" PRIu32 "\t%" PRIu32 "\t%" PRIu32 "\t%" PRIu32 "\t%.12g\t",
                p->number,p->start_point,p->apex_point,p->end_point,p->retention_min) < 0 ||
        b64n(stdout,p->component,p->component_bytes) || fputc('\n',stdout) == EOF)) return -1;
    if (out->peaks && (fprintf(out->peaks,"%" PRIu32 ",%" PRIu32 ",%" PRIu32 ",%" PRIu32 ",%.12g,",
         p->number,p->start_point,p->apex_point,p->end_point,p->retention_min) < 0 ||
         csv_text_n(out->peaks,p->component,p->component_bytes) || fputc('\n',out->peaks) == EOF)) return -1;
    return 0;
}

static const char *basename_of(const char *path) {
    const char *start = path, *p;
    for (p = path; *p; ++p) if (*p == '/') start = p+1;
    return start;
}

/* Metadata is UTF8. Reject invalid/overlong/surrogate byte sequences explicitly;
 * an explicit basename never controls an output path. POSIX backslash is literal. */
static int valid_basename(const char *value) {
    const unsigned char *p = (const unsigned char *)value;
    if (!*p || strchr(value,'/')) return 0;
    while (*p) {
        unsigned c = *p++, codepoint, minimum;
        int more, i;
        if (c < 0x80) continue;
        if (c >= 0xc2 && c <= 0xdf) {more=1;codepoint=c&0x1f;minimum=0x80;}
        else if (c >= 0xe0 && c <= 0xef) {more=2;codepoint=c&0x0f;minimum=0x800;}
        else if (c >= 0xf0 && c <= 0xf4) {more=3;codepoint=c&7;minimum=0x10000;}
        else return 0;
        for (i=0;i<more;++i) {
            if ((*p&0xc0)!=0x80) return 0;
            codepoint=(codepoint<<6)|(*p++&0x3f);
        }
        if (codepoint<minimum || codepoint>0x10ffff || (codepoint>=0xd800 && codepoint<=0xdfff)) return 0;
    }
    return 1;
}

static void diagnostic(char *buffer, size_t n, const char *operation) {
    int saved = errno;
    (void)snprintf(buffer,n,"%s: %s",operation,strerror(saved));
}

/* No output is canonical admission. A late error invalidates all this job's
 * protocol records and removes only exclusive files created by this job. */
static int process(const job *j, int summary_peaks, char *message, size_t capacity) {
    FILE *input = NULL;
    output_state out = {NULL,NULL,0,summary_peaks};
    chw_callbacks callbacks = {metadata,warning,samples,peak};
    chw_result result;
    chw_error error;
    struct stat st;
    int rc = 2, csv_created = 0, peaks_created = 0;
    memset(&result,0,sizeof(result));
    memset(&error,0,sizeof(error));
    if (!valid_basename(j->original ? j->original : basename_of(j->input))) {
        (void)snprintf(message,capacity,"Original filename must be a nonempty UTF8 POSIX basename");goto done;
    }
    input = fopen(j->input,"rb");
    if (!input) {diagnostic(message,capacity,"Cannot open CHW input");goto done;}
    if (fstat(fileno(input),&st) || !S_ISREG(st.st_mode) || st.st_size < 0 ||
        (uint64_t)st.st_size > CHW_MAX_FILE_BYTES) {
        (void)snprintf(message,capacity,"CHW input must be a regular file within the bounded size limit");goto done;
    }
    if (j->csv) {
        out.csv = fopen(j->csv,"wbx");
        if (!out.csv) {diagnostic(message,capacity,"Cannot exclusively create trace CSV");goto done;}
        csv_created = 1;
        if (fputs("time_s,time_min,signal_value,adc_count\n",out.csv) == EOF) {
            diagnostic(message,capacity,"Cannot write trace CSV header");goto done;
        }
    }
    if (j->peaks) {
        out.peaks = fopen(j->peaks,"wbx");
        if (!out.peaks) {diagnostic(message,capacity,"Cannot exclusively create peaks CSV");goto done;}
        peaks_created = 1;
        if (fputs("peak_number,start_point,apex_point,end_point,approx_retention_min,component_label\n",out.peaks) == EOF) {
            diagnostic(message,capacity,"Cannot write peaks CSV header");goto done;
        }
    }
    if (fputs("GXCHW1\n",stdout) == EOF) {
        (void)snprintf(message,capacity,"Cannot write CHW protocol header");goto done;
    }
    if (chw_read(input,j->original ? j->original : basename_of(j->input),&callbacks,&out,&result,&error) != CHW_OK) {
        (void)snprintf(message,capacity,"CHW reader error %d at byte %" PRIu64 ": %s",
                       (int)error.code,error.offset,error.message);goto done;
    }
    if (out.next_sample != result.signal.sample_count) {
        (void)snprintf(message,capacity,"CHW reader delivered an incomplete sample stream");goto done;
    }
    if (out.csv) {
        int close_status = fclose(out.csv);out.csv = NULL;
        if (close_status) {diagnostic(message,capacity,"Cannot finalize trace CSV");goto done;}
    }
    if (out.peaks) {
        int close_status = fclose(out.peaks);out.peaks = NULL;
        if (close_status) {diagnostic(message,capacity,"Cannot finalize peaks CSV");goto done;}
    }
    if (fclose(input)) {input = NULL;diagnostic(message,capacity,"Cannot close CHW input");goto done;}
    input = NULL;
    if (fflush(stdout) || ferror(stdout)) {
        (void)snprintf(message,capacity,"Cannot finalize CHW protocol output");goto done;
    }
    rc = 0;
    message[0] = '\0';
done:
    if (input) (void)fclose(input);
    if (out.csv) (void)fclose(out.csv);
    if (out.peaks) (void)fclose(out.peaks);
    if (rc) {
        if (csv_created && remove(j->csv)) (void)fprintf(stderr,"Cannot remove incomplete trace CSV: %s\n",strerror(errno));
        if (peaks_created && remove(j->peaks)) (void)fprintf(stderr,"Cannot remove incomplete peaks CSV: %s\n",strerror(errno));
    }
    return rc;
}

int main(int argc, char **argv) {
    job *jobs = NULL;
    int count = 0, bulk = 0, summary_peaks = 0, failed = 0, i;
    char message[512];
    #ifdef SIGPIPE
    (void)signal(SIGPIPE,SIG_IGN); /* Let broken pipes reach normal cleanup. */
#endif
    if (!setlocale(LC_NUMERIC,"C")) {fputs("Cannot set C numeric locale\n",stderr);return 2;}
    jobs = calloc(MAX_JOBS,sizeof(*jobs));
    if (!jobs) {fputs("Cannot allocate bounded CHW job list\n",stderr);return 2;}
    for (i = 1; i < argc; ++i) {
        const char *arg = argv[i];
        if (!strcmp(arg,"--bulk")) {bulk = 1;continue;}
        if (!strcmp(arg,"--summary-peaks")) {summary_peaks = 1;continue;}
        if (!strcmp(arg,"--help")) {
            puts("chw_worker [--bulk] [--summary-peaks] --input FILE [--original-filename BASENAME] [--csv-output NEW_CSV] [--peaks-output NEW_CSV] [--input FILE ...] [--output protocol]");
            free(jobs);return 0;
        }
        if (i+1 >= argc) {fputs("CHW worker option requires a value\n",stderr);free(jobs);return 2;}
        if (!strcmp(arg,"--input")) {
            if (count == MAX_JOBS) {fputs("CHW bulk exceeds1024 inputs\n",stderr);free(jobs);return 2;}
            jobs[count++].input = argv[++i];
        } else if (!strcmp(arg,"--output")) {
            if (strcmp(argv[++i],"protocol")) {fputs("Only CHW protocol output is supported\n",stderr);free(jobs);return 2;}
        } else if (count && !strcmp(arg,"--original-filename") && !jobs[count-1].original) {
            jobs[count-1].original = argv[++i];
        } else if (count && !strcmp(arg,"--csv-output") && !jobs[count-1].csv) {
            jobs[count-1].csv = argv[++i];
        } else if (count && !strcmp(arg,"--peaks-output") && !jobs[count-1].peaks) {
            jobs[count-1].peaks = argv[++i];
        } else {
            (void)fprintf(stderr,"Unknown, duplicate, or misplaced CHW worker option: %s\n",arg);free(jobs);return 2;
        }
    }
    if (!count || (count > 1 && !bulk)) {
        fputs("Supply --input; multiple sources require explicit --bulk\n",stderr);free(jobs);return 2;
    }
    if (bulk && fputs("GXCHWB1\n",stdout) == EOF) {free(jobs);return 2;}
    for (i = 0; i < count; ++i) {
        int status;
        if (bulk) {
            if (fprintf(stdout,"F\t%d\t",i) < 0 || b64(stdout,jobs[i].input) || fputc('\t',stdout) == EOF ||
                b64(stdout,jobs[i].original ? jobs[i].original : basename_of(jobs[i].input)) || fputc('\n',stdout) == EOF) {
                failed = 1;break;
            }
        }
        status = process(&jobs[i],summary_peaks,message,sizeof(message));
        if (status) {(void)fprintf(stderr,"CHW input %d: %s\n",i,message);failed = 1;}
        if (bulk && (fprintf(stdout,"E\t%d\t%d\t",i,status) < 0 || b64(stdout,message) ||
                     fputc('\n',stdout) == EOF || fflush(stdout))) {
            /* This job had no successful final framing; clean only outputs
             * exclusively created by its successful process() invocation. */
            if (!status) {
                if (jobs[i].csv && remove(jobs[i].csv)) (void)fprintf(stderr,"CHW input %d: cannot remove incomplete trace CSV: %s\n",i,strerror(errno));
                if (jobs[i].peaks && remove(jobs[i].peaks)) (void)fprintf(stderr,"CHW input %d: cannot remove incomplete peaks CSV: %s\n",i,strerror(errno));
            }
            failed = 1;break;
        }
    }
    free(jobs);
    return failed || ferror(stdout) ? 2 : 0;
}
