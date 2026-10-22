/* Metrohm IC Net CHW reader. SPDX-License-Identifier: GPL-3.0-or-later
 */
#define _POSIX_C_SOURCE 200809L
#include "chw_reader.h"
#include <sys/stat.h>
#include <sys/types.h>
#include <float.h>
#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <inttypes.h>
#include <unistd.h>

typedef struct { uint16_t code; uint32_t start, length; } section;
typedef struct {
    FILE *file; const chw_callbacks *cb; void *user;
    chw_result value; chw_error *error;
    section sections[12]; size_t section_count;
    uint32_t *labels; char *line; size_t line_cap;
} reader;
typedef struct {
    reader *owner; uint64_t pos, end;
    unsigned char bytes[8192]; size_t next, available;
} stream;

static chw_status fail(reader *r, chw_status code, uint64_t offset, const char *fmt, ...) {
    va_list args;
    r->error->code=code; r->error->offset=offset;
    va_start(args,fmt); vsnprintf(r->error->message,sizeof(r->error->message),fmt,args); va_end(args);
    return code;
}
static uint16_t le16(const unsigned char *p) { return (uint16_t)((uint16_t)p[0]|((uint16_t)p[1]<<8)); }
static uint32_t le32(const unsigned char *p) {
    return (uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);
}
static int64_t signed_value(uint32_t v, unsigned bits) {
    uint64_t top=UINT64_C(1)<<(bits-1);
    return ((uint64_t)v & top) ? (int64_t)(uint64_t)v-(int64_t)(UINT64_C(1)<<bits) : (int64_t)v;
}
static double binary32(const unsigned char *p) { uint32_t v=le32(p); float f; memcpy(&f,&v,4); return (double)f; }
static section *find_section(reader *r, unsigned code) {
    size_t i; for(i=0;i<r->section_count;i++) if(r->sections[i].code==code) return &r->sections[i];
    return NULL;
}
static chw_status read_at(reader *r,uint64_t offset,void *target,size_t count) {
    if(offset>r->value.file_bytes || (uint64_t)count>r->value.file_bytes-offset)
        return fail(r,CHW_FORMAT,offset,"Read exceeds CHW bounds");
    /* The admitted file is <=128MiB, representable by supported POSIX off_t. */
    if((uint64_t)(off_t)offset!=offset || fseeko(r->file,(off_t)offset,SEEK_SET))
        return fail(r,CHW_IO,offset,"CHW seek failed");
    if(count && fread(target,1,count,r->file)!=count)
        return fail(r,CHW_IO,offset,"CHW read failed or source changed");
    return CHW_OK;
}
static chw_status begin_stream(reader *r,section *s,stream *st) {
    memset(st,0,sizeof(*st)); st->owner=r;
    if(!s) return CHW_OK;
    st->pos=s->start; st->end=(uint64_t)s->start+s->length;
    return CHW_OK;
}
static int get_byte(stream *s,unsigned char *out) {
    size_t n; chw_status rc;
    if(s->pos==s->end) return 0;
    if(s->next==s->available) {
        n=(size_t)(s->end-s->pos); if(n>sizeof(s->bytes)) n=sizeof(s->bytes);
        rc=read_at(s->owner,s->pos,s->bytes,n); if(rc) return -1;
        s->next=0; s->available=n;
    }
    *out=s->bytes[s->next++]; s->pos++; return 1;
}
static chw_status take(stream *s,unsigned char *p,size_t n) {
    size_t i; int state;
    if((uint64_t)n>s->end-s->pos) return fail(s->owner,CHW_FORMAT,s->pos,"Truncated CHW section field");
    for(i=0;i<n;i++) { state=get_byte(s,p+i); if(state<0) return s->owner->error->code; }
    return CHW_OK;
}
static chw_status meta(reader *r,const char *key,const char *value) {
    if(r->cb && r->cb->metadata && r->cb->metadata(r->user,key,value))
        return fail(r,CHW_CALLBACK,0,"Metadata callback cancelled CHW reader");
    return CHW_OK;
}
static chw_status number(reader *r,const char *key,const char *fmt,...) {
    char v[128]; va_list args; int n;
    va_start(args,fmt); n=vsnprintf(v,sizeof(v),fmt,args); va_end(args);
    if(n<0 || (size_t)n>=sizeof(v)) return fail(r,CHW_LIMIT,0,"Numeric metadata format failed");
    return meta(r,key,v);
}
static chw_status warning(reader *r,const char *message) {
    if(r->cb && r->cb->warning && r->cb->warning(r->user,message))
        return fail(r,CHW_CALLBACK,0,"Warning callback cancelled CHW reader");
    return CHW_OK;
}
static int label_space(unsigned char c,int component) {
    if(component) return (c>=9 && c<=13) || (c>=28 && c<=32) || c==160;
    return c==0 || c==32 || c==13 || c==10 || c==9;
}
static const uint16_t cp1252_high[32]={
    0x20ac,0xfffd,0x201a,0x0192,0x201e,0x2026,0x2020,0x2021,
    0x02c6,0x2030,0x0160,0x2039,0x0152,0xfffd,0x017d,0xfffd,
    0xfffd,0x2018,0x2019,0x201c,0x201d,0x2022,0x2013,0x2014,
    0x02dc,0x2122,0x0161,0x203a,0x0153,0xfffd,0x017e,0x0178
};
/* Max source label length80, UTF8 max240 plus terminator. */
static chw_status text_label(reader *r,const unsigned char *p,size_t n,int component,char out[241],size_t *bytes) {
    size_t a=0,b=n,j=0,i; uint32_t c;
    (void)r;
    if(!component) for(i=0;i<n;i++) if(!p[i]) { b=i; break; }
    while(a<b && label_space(p[a],component)) a++;
    while(b>a && label_space(p[b-1],component)) b--;
    for(i=a;i<b;i++) {
        c=p[i];
        if(c>=128 && c<160) c=cp1252_high[c-128];
        if(c<128) out[j++]=(char)c;
        else if(c<2048) { out[j++]=(char)(192|(c>>6)); out[j++]=(char)(128|(c&63)); }
        else { out[j++]=(char)(224|(c>>12)); out[j++]=(char)(128|((c>>6)&63)); out[j++]=(char)(128|(c&63)); }
    }
    out[j]=0; if(bytes) *bytes=j; return CHW_OK;
}
static chw_status directory(reader *r) {
    unsigned char header[298]; size_t i,j; uint64_t largest=0; int ended=0; chw_status rc;
    if(r->value.file_bytes<298) return fail(r,CHW_FORMAT,0,"Unrecognized or truncated Metrohm IC Net CHW header");
    if((rc=read_at(r,0,header,sizeof(header)))) return rc;
    if(header[0]!=255 || header[1]!=38) return fail(r,CHW_FORMAT,0,"Unrecognized or truncated Metrohm IC Net CHW header");
    for(i=0;i<13;i++) {
        const unsigned char *p=header+8+16*i; section s;
        s.code=le16(p); s.start=le32(p+2); s.length=le32(p+6);
        if(!s.code) { ended=1; break; }
        if(s.code!=12 && (s.code<'A' || s.code>'Z')) return fail(r,CHW_FORMAT,8+16*i,"Unrecognized CHW section code");
        if(find_section(r,s.code)) return fail(r,CHW_FORMAT,8+16*i,"Duplicate CHW section code");
        if(s.code=='Y' && !s.start && !s.length) { ended=1; break; }
        if(s.start<298 || !s.length || s.start>r->value.file_bytes || s.length>r->value.file_bytes-s.start)
            return fail(r,CHW_FORMAT,8+16*i,"Invalid CHW section bounds");
        if(i==12) return fail(r,CHW_FORMAT,8+16*i,"No valid end of CHW directory");
        for(j=0;j<r->section_count;j++) {
            section *a=&r->sections[j];
            if((uint64_t)s.start<(uint64_t)a->start+a->length && (uint64_t)a->start<(uint64_t)s.start+s.length)
                return fail(r,CHW_FORMAT,s.start,"Overlapping CHW sections");
        }
        r->sections[r->section_count++]=s;
        if((uint64_t)s.start+s.length>largest) largest=(uint64_t)s.start+s.length;
    }
    if(!ended || !find_section(r,'S') || !find_section(r,'T'))
        return fail(r,CHW_FORMAT,0,"Required signal/trace sections or directory terminator absent");
    if(largest!=r->value.file_bytes) return fail(r,CHW_FORMAT,largest,"CHW section directory does not account for complete file");
    return CHW_OK;
}
static chw_status signal_info(reader *r,char channel[241],char unit[241]) {
    unsigned char s[72]; section *p=find_section(r,'S'); chw_status rc;
    if(p->length!=72) return fail(r,CHW_FORMAT,p->start,"Unvalidated signal descriptor variant (S section length is not 72)");
    if((rc=read_at(r,p->start,s,sizeof(s))) || (rc=text_label(r,s,9,0,channel,NULL)) || (rc=text_label(r,s+9,8,0,unit,NULL))) return rc;
    if(!*channel || !*unit) return fail(r,CHW_FORMAT,p->start,"Invalid channel or unit label in signal descriptor");
    r->value.signal.sample_count=le32(s+46); r->value.signal.interval_s=binary32(s+68); r->value.signal.adc_step=binary32(s+18);
    if(!r->value.signal.sample_count || r->value.signal.sample_count>CHW_MAX_SAMPLES ||
       !(r->value.signal.interval_s>0 && r->value.signal.interval_s<3600))
        return fail(r,CHW_FORMAT,p->start+46,"Invalid acquisition count or sampling interval");
    if(!isfinite(r->value.signal.adc_step) || r->value.signal.adc_step<=0)
        return fail(r,CHW_FORMAT,p->start+18,"Unrecognized or invalid CHW ADC scale");
    return CHW_OK;
}
static chw_status emit_samples(reader *r,uint32_t first,int32_t *buffer,size_t count) {
    if(r->cb && r->cb->samples && r->cb->samples(r->user,&r->value.signal,first,buffer,count))
        return fail(r,CHW_CALLBACK,0,"Sample callback cancelled CHW reader");
    return CHW_OK;
}
static chw_status trace_data(reader *r) {
    section *t=find_section(r,'T'); stream s; unsigned char p[12]; int32_t chunk[CHW_SAMPLE_CHUNK];
    uint32_t i,j,run,mode,width,blocks,index=1,first=0; size_t used=1; int64_t current,delta;
    chw_status rc; int slot;
    if(t->length<14) return fail(r,CHW_FORMAT,t->start,"CHW trace byte count disagrees with signal descriptor");
    begin_stream(r,t,&s); if((rc=take(&s,p,12))) return rc;
    if(le32(p)!=4*r->value.signal.sample_count) return fail(r,CHW_FORMAT,t->start,"CHW trace byte count disagrees with signal descriptor");
    blocks=le32(p+4); if(!blocks || blocks>r->value.signal.sample_count) return fail(r,CHW_FORMAT,t->start+4,"Invalid CHW trace block count");
    r->value.block_count=blocks; current=signed_value(le32(p+8),32); chunk[0]=(int32_t)current;
    r->value.first_adc=r->value.minimum_adc=r->value.maximum_adc=(int32_t)current;
    r->value.first_12_adc[0]=(int32_t)current; r->value.first_12_count=1;
    for(i=0;i<blocks;i++) {
        if((rc=take(&s,p,2))) return rc;
        run=le16(p)>>4; mode=le16(p)&15;
        slot=mode==0?0:mode==3?1:mode==4?2:mode==5?3:-1;
        if(!run || slot<0) return fail(r,CHW_FORMAT,s.pos-2,"Unsupported CHW compression block %" PRIu32 ": length=%" PRIu32 ", mode=%" PRIu32,i,run,mode);
        if(run>r->value.signal.sample_count-index) return fail(r,CHW_FORMAT,s.pos-2,"CHW run extends beyond declared sample count");
        width=mode==0?0:mode==3?1:mode==4?2:4;
        if((uint64_t)width*run>s.end-s.pos) return fail(r,CHW_FORMAT,s.pos,"Truncated CHW compressed run");
        r->value.mode_counts[slot]++;
        for(j=0;j<run;j++) {
            if(width) {
                if((rc=take(&s,p,width))) return rc;
                delta=signed_value(width==1?p[0]:width==2?le16(p):le32(p),width*8); current+=delta;
                if(current<INT32_MIN || current>INT32_MAX) return fail(r,CHW_FORMAT,s.pos-width,"ADC cumulative value exceeds signed 32-bit range");
            }
            chunk[used++]=(int32_t)current;
            if(current<r->value.minimum_adc) r->value.minimum_adc=(int32_t)current;
            if(current>r->value.maximum_adc) r->value.maximum_adc=(int32_t)current;
            if(index<12) { r->value.first_12_adc[index]=(int32_t)current; r->value.first_12_count=index+1; }
            index++;
            if(used==CHW_SAMPLE_CHUNK) { if((rc=emit_samples(r,first,chunk,used))) return rc; first=index; used=0; }
        }
    }
    if(index!=r->value.signal.sample_count || s.pos!=s.end) return fail(r,CHW_FORMAT,s.pos,"CHW compressed trace has extra bytes or incomplete samples");
    r->value.last_adc=(int32_t)current;
    if(used && (rc=emit_samples(r,first,chunk,used))) return rc;
    return CHW_OK;
}
static chw_status validate_peaks(reader *r) {
    section *d=find_section(r,'D'); stream s; unsigned char p[32]; uint32_t count,i,a,b,c; chw_status rc;
    if(!d) return CHW_OK;
    if(d->length<32 || (d->length-32)%32) return warning(r,"Unknown integration section record layout; peaks not decoded.");
    count=(d->length-32)/32; begin_stream(r,d,&s); if((rc=take(&s,p,32))) return rc;
    for(i=0;i<count;i++) {
        if((rc=take(&s,p,32))) return rc;
        a=le32(p); b=le32(p+4); c=le32(p+8);
        if(a>b || b>c || c>=r->value.signal.sample_count) return warning(r,"Peak-point bounds are inconsistent; all peak records ignored.");
    }
    r->value.peak_count=count;
    return CHW_OK;
}
static int digit(unsigned char c) { return c>='0' && c<='9'; }
static int ascii_space(unsigned char c) { return c==32 || (c>=9 && c<=13); }
static unsigned char lower_ascii(unsigned char c) { return c>='A' && c<='Z'?(unsigned char)(c+32):c; }
static int suffix_ci(const char *s,size_t n,const char *tail) {
    size_t i,m=strlen(tail); if(n<m) return 0;
    for(i=0;i<m;i++) if(lower_ascii((unsigned char)s[n-m+i])!=(unsigned char)tail[i]) return 0;
    return 1;
}
/* Reusable run buffer; capacity never exceeds file_bytes+1. */
static chw_status grow(reader *r,size_t need) {
    size_t cap; char *p;
    if(need>r->value.file_bytes+1) return fail(r,CHW_LIMIT,0,"Metadata run exceeds admitted file size");
    if(need<=r->line_cap) return CHW_OK;
    cap=r->line_cap?r->line_cap:256;
    while(cap<need) { if(cap>(r->value.file_bytes+1)/2) { cap=(size_t)r->value.file_bytes+1; break; } cap*=2; }
    if(cap>r->value.file_bytes+1) cap=(size_t)r->value.file_bytes+1;
    p=realloc(r->line,cap); if(!p) return fail(r,CHW_MEMORY,0,"Cannot allocate bounded metadata run");
    r->line=p; r->line_cap=cap; return CHW_OK;
}
/* Source-hint ASCII runs, with a separate byte-level software matcher. */
typedef struct { int model,method,column,software; int sw_state; size_t sw_prefix,sw_length; char *version; size_t version_cap; } hint_state;
static chw_status version_push(reader *r,hint_state *h,unsigned char c) {
    char *p; size_t cap;
    if(h->sw_length+1>=h->version_cap) {
        cap=h->version_cap?h->version_cap*2:64;
        if(cap>r->value.file_bytes+8) cap=(size_t)r->value.file_bytes+8;
        if(cap<=h->sw_length+1) return fail(r,CHW_LIMIT,0,"Software version exceeds source bounds");
        p=realloc(h->version,cap); if(!p) return fail(r,CHW_MEMORY,0,"Cannot allocate software version");
        h->version=p; h->version_cap=cap;
    }
    if(!h->sw_length) { memcpy(h->version,"IC Net ",7); h->sw_length=7; }
    h->version[h->sw_length++]=(char)c; h->version[h->sw_length]=0; return CHW_OK;
}
static chw_status software_done(reader *r,hint_state *h) {
    chw_status rc;
    if(h->software || !h->sw_length) return CHW_OK;
    /* A dot without a following digit is not part of Python's match. */
    if(h->version[h->sw_length-1]=='.') h->version[--h->sw_length]=0;
    rc=meta(r,"instrument.software",h->version);
    free(h->version); h->version=NULL; h->version_cap=0; h->sw_length=0;
    h->software=1; return rc;
}
static chw_status software_byte(reader *r,hint_state *h,unsigned char c) {
    static const char prefix[]="ic net"; chw_status rc;
    if(h->software) return CHW_OK;
    if(h->sw_state==0) {
        if(lower_ascii(c)==(unsigned char)prefix[h->sw_prefix]) { if(++h->sw_prefix==6) { h->sw_state=1; h->sw_prefix=0; } }
        else h->sw_prefix=lower_ascii(c)=='i'?1:0;
    } else if(h->sw_state==1) {
        if(ascii_space(c)) h->sw_state=2;
        else { h->sw_state=0; h->sw_prefix=lower_ascii(c)=='i'?1:0; }
    } else if(h->sw_state==2) {
        if(digit(c)) { h->sw_state=3; if((rc=version_push(r,h,c))) return rc; }
        else if(!ascii_space(c)) { h->sw_state=0; h->sw_prefix=lower_ascii(c)=='i'?1:0; }
    } else if(h->sw_state==3) {
        if(digit(c)) { if((rc=version_push(r,h,c))) return rc; }
        else if(c=='.') { h->sw_state=4; if((rc=version_push(r,h,c))) return rc; }
        else return software_done(r,h);
    } else if(h->sw_state==4) {
        if(digit(c)) { h->sw_state=5; if((rc=version_push(r,h,c))) return rc; }
        else return software_done(r,h);
    } else if(digit(c)) { if((rc=version_push(r,h,c))) return rc; }
    else return software_done(r,h);
    return CHW_OK;
}
static chw_status ascii_run(reader *r,hint_state *h,size_t n) {
    char *s=r->line; size_t a=0,b=n,i,j; int model=0; chw_status rc;
    if(n<4) return CHW_OK;
    while(a<b && s[a]==' ') a++;
    while(b>a && s[b-1]==' ') b--;
    s[b]=0; s+=a; n=b-a;
    if(!h->model && n>=7 && digit((unsigned char)s[0]) && digit((unsigned char)s[1]) && digit((unsigned char)s[2]) && s[n-2]=='I' && s[n-1]=='C') {
        for(i=4;i+2<=n && s[i-1]==' ';i++) {
            if(n-2-i<1 || n-2-i>50) continue;
            model=1; for(j=i;j<n;j++) if(s[j]=='/' || s[j]=='\\') model=0;
            if(model) break;
        }
        if(model) { if((rc=meta(r,"instrument.model",s))) return rc; h->model=1; }
    }
    if(!h->method && suffix_ci(s,n,".mtw")) {
        char *last=strrchr(s,'\\'); if((rc=meta(r,"chromatography.method_filename",last?last+1:s))) return rc; h->method=1;
    }
    if(!h->column) for(i=0;i+8<=n;i++) {
        static const char target[]="metrosep";
        for(j=0;j<8;j++) if(lower_ascii((unsigned char)s[i+j])!=(unsigned char)target[j]) break;
        if(j==8) { if((rc=meta(r,"chromatography.column_description",s))) return rc; h->column=1; break; }
    }
    return CHW_OK;
}
static chw_status hints(reader *r) {
    hint_state h; stream s; unsigned char c; unsigned codes[2]={12,'H'}; size_t k,n=0; int state; chw_status rc=CHW_OK;
    memset(&h,0,sizeof(h));
    for(k=0;k<2;k++) {
        begin_stream(r,find_section(r,codes[k]),&s);
        while((state=get_byte(&s,&c))>0) {
            if((rc=software_byte(r,&h,c))) goto done;
            if(c>=32 && c<=126) { if((rc=grow(r,n+2))) goto done; r->line[n++]=(char)c; }
            else { if((rc=ascii_run(r,&h,n))) goto done; n=0; }
        }
        if(state<0) { rc=r->error->code; goto done; }
        if((rc=ascii_run(r,&h,n))) goto done;
        n=0;
        /* header12 and H are separated by one NUL in the reference parser. */
        if((rc=software_byte(r,&h,0))) goto done;
    }
    if(!h.software && h.sw_state>=3) rc=software_done(r,&h);
done:
    free(h.version); free(r->line); r->line=NULL; r->line_cap=0; return rc;
}
/* U-log scanning: fixed circular history for labels; at most128 timestamp
 * candidates. A live fraction can grow to source size, but contains no colon,
 * so it cannot create more time candidates until it finishes or fails. */
typedef struct {
    char *value; size_t length,capacity,after_count;
    unsigned phase; unsigned char after[96];
} time_candidate;
typedef struct {
    unsigned char ring[256]; size_t seen,next;
    time_candidate times[128]; size_t time_count; int time_done;
} audit_state;
static unsigned char back_byte(const audit_state *a,size_t back) { return a->ring[(a->next+255-back)%256]; }
static int back_literal(const audit_state *a,size_t back,const char *literal) {
    size_t n=strlen(literal),i;
    if(back+n>a->seen) return 0;
    for(i=0;i<n;i++) if(back_byte(a,back+i)!=(unsigned char)literal[n-1-i]) return 0;
    return 1;
}
static void label_match(reader *r,audit_state *a,uint64_t absolute) {
    static const char suffix[]="\\component", prefix[]="Chromatogram\\Peaks\\# ";
    size_t b=sizeof(suffix)-1,end,first,n=0,k; uint32_t number=0,multiplier=1; unsigned char c;
    if(!r->value.peak_count || !back_literal(a,0,suffix)) return;
    end=b;
    while(b<a->seen && digit(back_byte(a,b))) { if(b-end==10) return; b++; }
    if(b==end || back_byte(a,b-1)=='0') return;
    first=b;
    if(!back_literal(a,b,prefix)) return;
    b+=sizeof(prefix)-1;
    if(b+2>a->seen || back_byte(a,b)!=9 || back_byte(a,b+1)!=9) return;
    b+=2;
    while(b<a->seen) {
        c=back_byte(a,b);
        if(c==9) break;
        if(c==10 || c==13 || ++n>80) return;
        b++;
    }
    if(!n || b==a->seen || back_byte(a,b)!=9) return;
    for(k=end;k<first;k++) {
        unsigned d=back_byte(a,k)-'0';
        if(d && multiplier>(UINT32_MAX-number)/d) return;
        number+=d*multiplier;
        if(k+1<first) { if(multiplier>UINT32_MAX/10) return; multiplier*=10; }
    }
    if(!number || number>r->value.peak_count || r->labels[number-1]) return;
    r->labels[number-1]=(uint32_t)(absolute-b+1);
}
static chw_status time_push(reader *r,time_candidate *t,unsigned char c) {
    size_t cap; char *p;
    if(t->length+1>=t->capacity) {
        cap=t->capacity?t->capacity*2:32;
        if(cap>r->value.file_bytes+1) cap=(size_t)r->value.file_bytes+1;
        if(cap<=t->length+1) return fail(r,CHW_LIMIT,0,"Audit timestamp exceeds source bounds");
        p=realloc(t->value,cap); if(!p) return fail(r,CHW_MEMORY,0,"Cannot allocate audit timestamp");
        t->value=p; t->capacity=cap;
    }
    t->value[t->length++]=(char)c; t->value[t->length]=0; return CHW_OK;
}
/* Returns1 to retain,0 to drop,2 when matched, or-1 on resource failure. */
static int time_step(reader *r,time_candidate *t,unsigned char c) {
    static const char marker[]="Chromatogram\\Sample\\sample time";
    const size_t m=sizeof(marker)-1; chw_status rc;
    if(t->phase==0) {
        if(c=='.') { t->phase=1; if((rc=time_push(r,t,c))) return -1; }
        else if(c==9) t->phase=3;
        else return 0;
    } else if(t->phase==1) {
        if(!digit(c)) return 0;
        t->phase=2; if((rc=time_push(r,t,c))) return -1;
    } else if(t->phase==2) {
        if(digit(c)) { if((rc=time_push(r,t,c))) return -1; }
        else if(c==9) t->phase=3;
        else return 0;
    } else {
        if(!c || c==13 || c==10 || t->after_count>=50+m) return 0;
        t->after[t->after_count++]=c;
        if(t->after_count>=m && !memcmp(t->after+t->after_count-m,marker,m)) return 2;
    }
    return 1;
}
static chw_status audit_byte(reader *r,audit_state *a,unsigned char c,uint64_t pos) {
    size_t i=0,j; int status; time_candidate *t; chw_status rc;
    a->ring[a->next]=c; a->next=(a->next+1)%256; if(a->seen<256) a->seen++;
    if(c=='t') label_match(r,a,pos);
    if(a->time_done) return CHW_OK;
    while(i<a->time_count) {
        t=&a->times[i]; status=time_step(r,t,c);
        if(status<0) return r->error->code;
        if(status==2) {
            if((rc=meta(r,"chromatography.sample_time_local",t->value))) return rc;
            a->time_done=1;
            for(j=0;j<a->time_count;j++) free(a->times[j].value);
            a->time_count=0; return CHW_OK;
        }
        if(!status) { free(t->value); memmove(t,t+1,(a->time_count-i-1)*sizeof(*t)); a->time_count--; }
        else i++;
    }
    if(a->seen>=8 && digit(back_byte(a,7)) && digit(back_byte(a,6)) && back_byte(a,5)==':' &&
       digit(back_byte(a,4)) && digit(back_byte(a,3)) && back_byte(a,2)==':' && digit(back_byte(a,1)) && digit(c)) {
        if(a->time_count==128) return fail(r,CHW_LIMIT,pos,"Too many overlapping timestamp candidates");
        t=&a->times[a->time_count++]; memset(t,0,sizeof(*t));
        for(j=8;j>0;j--) if((rc=time_push(r,t,back_byte(a,j-1)))) return rc;
    }
    return CHW_OK;
}
static chw_status audit_log(reader *r) {
    section *u=find_section(r,'U'); stream s; audit_state a; unsigned char c; size_t i; int state; chw_status rc=CHW_OK;
    if(r->value.peak_count) {
        if((uint64_t)r->value.peak_count*sizeof(*r->labels)>SIZE_MAX)
            return fail(r,CHW_MEMORY,0,"Peak offset index exceeds address space");
        r->labels=calloc(r->value.peak_count,sizeof(*r->labels));
        if(!r->labels) return fail(r,CHW_MEMORY,0,"Cannot allocate bounded peak label index");
    }
    memset(&a,0,sizeof(a)); begin_stream(r,u,&s);
    while((state=get_byte(&s,&c))>0) if((rc=audit_byte(r,&a,c,s.pos-1))) break;
    if(state<0) rc=r->error->code;
    for(i=0;i<a.time_count;i++) free(a.times[i].value);
    return rc;
}
static chw_status emit_peaks(reader *r) {
    section *d=find_section(r,'D'),*u=find_section(r,'U'); uint32_t i; unsigned char p[12],label[80];
    chw_peak peak; char utf8[241]; size_t j,n,bytes; chw_status rc;
    for(i=0;i<r->value.peak_count;i++) {
        if((rc=read_at(r,(uint64_t)d->start+32+32*(uint64_t)i,p,12))) return rc;
        memset(&peak,0,sizeof(peak)); peak.number=i+1; peak.start_point=le32(p); peak.apex_point=le32(p+4); peak.end_point=le32(p+8);
        peak.retention_min=(double)peak.apex_point*r->value.signal.interval_s/60.0;
        n=0;
        if(r->labels[i]) {
            if(!u || r->labels[i]<u->start || r->labels[i]>=(uint64_t)u->start+u->length)
                return fail(r,CHW_FORMAT,r->labels[i],"Invalid internal peak label offset");
            n=(size_t)((uint64_t)u->start+u->length-r->labels[i]); if(n>80) n=80;
            if((rc=read_at(r,r->labels[i],label,n))) return rc;
            for(j=0;j<n;j++) if(label[j]==9 || label[j]==10 || label[j]==13) { n=j; break; }
        }
        if((rc=text_label(r,label,n,1,utf8,&bytes))) return rc;
        peak.component=utf8; peak.component_bytes=bytes;
        if(r->cb && r->cb->peak && r->cb->peak(r->user,&peak)) return fail(r,CHW_CALLBACK,0,"Peak callback cancelled CHW reader");
    }
    return CHW_OK;
}
/* Python reference filename regex uses Unicode \d, not only ASCII digits.
 * Nd ranges generated as source text from host Python unicodedata 15.1.0.
 * This is a metadata lexical table; no numeric/scientific interpretation. */
static int unicode_decimal(uint32_t c) {
    static const uint32_t ranges[][2]={
        {0x30,0x39},
        {0x660,0x669},
        {0x6f0,0x6f9},
        {0x7c0,0x7c9},
        {0x966,0x96f},
        {0x9e6,0x9ef},
        {0xa66,0xa6f},
        {0xae6,0xaef},
        {0xb66,0xb6f},
        {0xbe6,0xbef},
        {0xc66,0xc6f},
        {0xce6,0xcef},
        {0xd66,0xd6f},
        {0xde6,0xdef},
        {0xe50,0xe59},
        {0xed0,0xed9},
        {0xf20,0xf29},
        {0x1040,0x1049},
        {0x1090,0x1099},
        {0x17e0,0x17e9},
        {0x1810,0x1819},
        {0x1946,0x194f},
        {0x19d0,0x19d9},
        {0x1a80,0x1a89},
        {0x1a90,0x1a99},
        {0x1b50,0x1b59},
        {0x1bb0,0x1bb9},
        {0x1c40,0x1c49},
        {0x1c50,0x1c59},
        {0xa620,0xa629},
        {0xa8d0,0xa8d9},
        {0xa900,0xa909},
        {0xa9d0,0xa9d9},
        {0xa9f0,0xa9f9},
        {0xaa50,0xaa59},
        {0xabf0,0xabf9},
        {0xff10,0xff19},
        {0x104a0,0x104a9},
        {0x10d30,0x10d39},
        {0x11066,0x1106f},
        {0x110f0,0x110f9},
        {0x11136,0x1113f},
        {0x111d0,0x111d9},
        {0x112f0,0x112f9},
        {0x11450,0x11459},
        {0x114d0,0x114d9},
        {0x11650,0x11659},
        {0x116c0,0x116c9},
        {0x11730,0x11739},
        {0x118e0,0x118e9},
        {0x11950,0x11959},
        {0x11c50,0x11c59},
        {0x11d50,0x11d59},
        {0x11da0,0x11da9},
        {0x11f50,0x11f59},
        {0x16a60,0x16a69},
        {0x16ac0,0x16ac9},
        {0x16b50,0x16b59},
        {0x1d7ce,0x1d7ff},
        {0x1e140,0x1e149},
        {0x1e2f0,0x1e2f9},
        {0x1e4f0,0x1e4f9},
        {0x1e950,0x1e959},
        {0x1fbf0,0x1fbf9},
    };
    size_t i; for(i=0;i<sizeof(ranges)/sizeof(ranges[0]);i++) if(c>=ranges[i][0] && c<=ranges[i][1]) return 1;
    return 0;
}
static size_t utf8_rune(const unsigned char *p,size_t n,uint32_t *out) {
    size_t k,i; uint32_t c;
    if(!n) return 0;
    if(p[0]<128) { *out=p[0]; return 1; }
    if(p[0]>=194 && p[0]<=223) { k=2; c=p[0]&31; }
    else if(p[0]>=224 && p[0]<=239) { k=3; c=p[0]&15; }
    else if(p[0]>=240 && p[0]<=244) { k=4; c=p[0]&7; }
    else return 0;
    if(k>n) return 0;
    for(i=1;i<k;i++) { if((p[i]&192)!=128) return 0; c=(c<<6)|(p[i]&63); }
    if((k==2 && c<128) || (k==3 && c<2048) || (k==4 && c<65536) || c>0x10ffff || (c>=0xd800 && c<=0xdfff)) return 0;
    *out=c; return k;
}
static chw_status filename_date(reader *r,const char *name) {
    size_t n=strlen(name),i,j,pos,width; uint32_t code; char date[29];
    for(i=0;i+10<=n;i++) {
        if(name[i]!='2' || name[i+1]!='0') continue;
        pos=i+2;
        for(j=0;j<8;j++) {
            if(j==2 || j==5) { if(pos>=n || name[pos]!='-') break; pos++; }
            else {
                width=utf8_rune((const unsigned char *)name+pos,n-pos,&code);
                if(!width || !unicode_decimal(code)) break;
                pos+=width;
            }
        }
        if(j==8) { memcpy(date,name+i,pos-i); date[pos-i]=0; return meta(r,"chromatography.filename_date",date); }
    }
    return CHW_OK;
}
static chw_status base_metadata(reader *r,const char *name,const char *channel,const char *unit) {
    char sections[128],modes[128]; size_t i,n=0; int written; chw_status rc; section *t=find_section(r,'T');
#define META(k,v) do { if((rc=meta(r,k,v))) return rc; } while(0)
#define NUMBER(k,f,v) do { if((rc=number(r,k,f,v))) return rc; } while(0)
    META("source.original_filename",name);
    NUMBER("source.file_size_bytes","%" PRIu64,r->value.file_bytes);
    META("chromatography.format","metrohm.icnet.chw");
    META("chromatography.signal_decode_status","decoded_integer_exact");
    NUMBER("chromatography.adc_step_raw_float32","%.17g",r->value.signal.adc_step);
    NUMBER("chromatography.trace_block_count","%" PRIu32,r->value.block_count);
    written=snprintf(modes,sizeof(modes),"0:%" PRIu32 ";3:%" PRIu32 ";4:%" PRIu32 ";5:%" PRIu32,
                     r->value.mode_counts[0],r->value.mode_counts[1],r->value.mode_counts[2],r->value.mode_counts[3]);
    if(written<0 || (size_t)written>=sizeof(modes)) return fail(r,CHW_LIMIT,0,"Mode metadata format failed");
    META("chromatography.trace_mode_counts",modes);
    NUMBER("chromatography.declared_sample_count","%" PRIu32,r->value.signal.sample_count);
    NUMBER("chromatography.sample_interval_s","%.17g",r->value.signal.interval_s);
    NUMBER("chromatography.trace_payload_bytes","%" PRIu32,t->length);
    NUMBER("chromatography.unpacked_trace_bytes","%" PRIu32,4*r->value.signal.sample_count);
    NUMBER("chromatography.integration_peak_count","%" PRIu32,r->value.peak_count);
    META("chromatography.signal_channel",channel); META("chromatography.signal_unit",unit);
    for(i=0;i<r->section_count;i++) {
        if(i) sections[n++]=';';
        if(r->sections[i].code==12) { memcpy(sections+n,"header12",8); n+=8; }
        else sections[n++]=(char)r->sections[i].code;
    }
    sections[n]=0; META("chromatography.section_ids",sections);
#undef META
#undef NUMBER
    return filename_date(r,name);
}
chw_status chw_read(FILE *input,const char *original_filename,const chw_callbacks *callbacks,void *context,
                    chw_result *result,chw_error *error) {
    reader r; chw_error local_error; struct stat before,after; uint32_t ieee_one; float one=1.0f;
    chw_status rc=CHW_OK; char channel[241],unit[241]; const char *name=original_filename?original_filename:"";
    memset(&r,0,sizeof(r)); r.file=input; r.cb=callbacks; r.user=context; r.error=error?error:&local_error;
    memset(r.error,0,sizeof(*r.error)); if(result) memset(result,0,sizeof(*result));
    if(!input || fstat(fileno(input),&before) || !S_ISREG(before.st_mode) || before.st_size<0) {
        rc=fail(&r,CHW_IO,0,"Input must be an opened seekable regular file"); goto done;
    }
    r.value.file_bytes=(uint64_t)before.st_size;
    if(r.value.file_bytes>CHW_MAX_FILE_BYTES) { rc=fail(&r,CHW_LIMIT,0,"CHW file exceeds bounded inspection limit"); goto done; }
    if(sizeof(float)!=4 || FLT_RADIX!=2 || FLT_MANT_DIG!=24 || FLT_MAX_EXP!=128 || CHAR_BIT!=8) {
        rc=fail(&r,CHW_LIMIT,0,"Native platform requires IEEE754 binary32 and eight-bit bytes"); goto done;
    }
    memcpy(&ieee_one,&one,4);
    if(ieee_one!=UINT32_C(0x3f800000)) { rc=fail(&r,CHW_LIMIT,0,"Unsupported binary32 representation"); goto done; }
    if((rc=directory(&r)) || (rc=signal_info(&r,channel,unit)) || (rc=trace_data(&r))) goto done;
    if((rc=warning(&r,"Historical source-package 0.2.2 assertion: CHW compression decoding was validated on seven IC Net 2.3 conductivity files. Current native/source parity is separate from independent vendor scientific validation; other vendor versions and instruments require individual validation.")) ||
       (rc=warning(&r,"Raw CHW integration labels may be absent even when the CDF exporter supplies names from the method.")) ||
       (rc=validate_peaks(&r)) || (rc=hints(&r)) || (rc=audit_log(&r)) || (rc=emit_peaks(&r)) ||
       (rc=base_metadata(&r,name,channel,unit))) goto done;
    if(ferror(input) || fstat(fileno(input),&after) || before.st_dev!=after.st_dev || before.st_ino!=after.st_ino ||
       before.st_size!=after.st_size || before.st_mtim.tv_sec!=after.st_mtim.tv_sec || before.st_mtim.tv_nsec!=after.st_mtim.tv_nsec ||
       before.st_ctim.tv_sec!=after.st_ctim.tv_sec || before.st_ctim.tv_nsec!=after.st_ctim.tv_nsec) {
        rc=fail(&r,CHW_IO,0,"CHW source changed or failed during read"); goto done;
    }
    if(result) *result=r.value;
done:
    free(r.labels); free(r.line); return rc;
}
