// SPDX-License-Identifier: GPL-3.0-or-later
#include "native_trace.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

typedef struct { double v[3]; } GXSignature;

typedef struct {
    int start;
    int end;
    double best;
    double center;
} GXCluster;

void gx_trace_settings_default(GXTraceSettings *s) {
    if (!s) return;
    s->step_px = 2.0;
    s->search_radius_px = 8;
    s->match_tolerance = 32.0;
    s->sample_radius_px = 1;
    s->contrast_ring_px = 5;
    s->ambiguity_margin = 8.0;
    s->thickness_factor = 2.4;
    s->noise_gap_steps = 1;
    s->max_steps = 2000;
    s->direction_mode = GX_DIR_BOTH_X;
    s->match_mode = GX_MATCH_GRAY;
}

int gx_trace_settings_validate(const GXTraceSettings *s, char *err, size_t errcap) {
#define BAD(msg) do { if (err && errcap) snprintf(err, errcap, "%s", msg); return 0; } while (0)
    if (!s) BAD("Trace settings are missing.");
    if (s->step_px < 0.5 || s->step_px > 20.0) BAD("Step size must be between 0.5 and 20 pixels.");
    if (s->search_radius_px < 1 || s->search_radius_px > 80) BAD("Search radius must be between 1 and 80 pixels.");
    if (s->match_tolerance < 0.5 || s->match_tolerance > 512.0) BAD("Match tolerance must be between 0.5 and 512.");
    if (s->sample_radius_px < 0 || s->sample_radius_px > 8) BAD("Sample radius must be between 0 and 8 pixels.");
    if (s->contrast_ring_px < 2 || s->contrast_ring_px > 30) BAD("Contrast ring radius must be between 2 and 30 pixels.");
    if (s->ambiguity_margin < 0.0 || s->ambiguity_margin > 128.0) BAD("Ambiguity margin must be between 0 and 128.");
    if (s->thickness_factor < 1.2 || s->thickness_factor > 8.0) BAD("Thickness factor must be between 1.2 and 8.0.");
    if (s->noise_gap_steps < 0 || s->noise_gap_steps > 3) BAD("Noise-gap lookahead must be between 0 and 3 steps.");
    if (s->max_steps < 1 || s->max_steps > 20000) BAD("Maximum step count must be between 1 and 20000.");
    if (s->contrast_ring_px <= s->sample_radius_px) BAD("Contrast ring radius must be larger than the sample radius.");
    if (s->match_mode < GX_MATCH_GRAY || s->match_mode > GX_MATCH_CONTRAST) BAD("Unsupported trace match mode.");
    if (s->direction_mode < GX_DIR_BOTH_X || s->direction_mode > GX_DIR_SEED_FORWARD) BAD("Unsupported trace direction mode.");
    return 1;
#undef BAD
}

void gx_trace_result_init(GXTraceResult *r) { if (r) memset(r, 0, sizeof(*r)); }
void gx_trace_result_free(GXTraceResult *r) {
    if (!r) return;
    free(r->points); free(r->gaps); memset(r, 0, sizeof(*r));
}

static int push_point(GXTraceResult *r, GXPoint p) {
    if (r->point_count == r->point_capacity) {
        size_t nc = r->point_capacity ? r->point_capacity * 2 : 256;
        GXPoint *np = (GXPoint *)realloc(r->points, nc * sizeof(*np));
        if (!np) return 0;
        r->points = np; r->point_capacity = nc;
    }
    r->points[r->point_count++] = p; return 1;
}
static int push_gap(GXTraceResult *r, GXPoint a, GXPoint b) {
    if (r->gap_count == r->gap_capacity) {
        size_t nc = r->gap_capacity ? r->gap_capacity * 2 : 32;
        GXGap *ng = (GXGap *)realloc(r->gaps, nc * sizeof(*ng));
        if (!ng) return 0;
        r->gaps = ng; r->gap_capacity = nc;
    }
    r->gaps[r->gap_count++] = (GXGap){a,b}; return 1;
}

static int inside(const GXImage *im, double x, double y, int margin) {
    return im && im->rgb && x >= margin && y >= margin && x < im->width - margin && y < im->height - margin;
}
static const uint8_t *pixel(const GXImage *im, int x, int y) { return im->rgb + (size_t)y * im->stride + (size_t)x * 3; }
static int luma8(const uint8_t *p) { return (77 * p[0] + 150 * p[1] + 29 * p[2] + 128) >> 8; }

static double hist_median(const unsigned *hist, unsigned total) {
    if (!total) return NAN;
    unsigned a = (total - 1) / 2, b = total / 2, acc = 0;
    int va = -1, vb = -1;
    for (int i=0;i<256;i++) {
        unsigned next = acc + hist[i];
        if (va < 0 && a < next) va = i;
        if (b < next) { vb = i; break; }
        acc = next;
    }
    if (va < 0) va = vb; if (vb < 0) vb = va;
    return 0.5 * (va + vb);
}

static int patch_median_rgb(const GXImage *im, double x, double y, int radius, double out[3]) {
    int ix=(int)llround(x), iy=(int)llround(y);
    int x0=ix-radius, x1=ix+radius, y0=iy-radius, y1=iy+radius;
    if (x0<0)x0=0; if(y0<0)y0=0; if(x1>=im->width)x1=im->width-1; if(y1>=im->height)y1=im->height-1;
    if (x0>x1 || y0>y1) return 0;
    unsigned hr[256]={0}, hg[256]={0}, hb[256]={0}, n=0;
    for(int yy=y0;yy<=y1;yy++) for(int xx=x0;xx<=x1;xx++) { const uint8_t *p=pixel(im,xx,yy); hr[p[0]]++;hg[p[1]]++;hb[p[2]]++;n++; }
    out[0]=hist_median(hr,n);out[1]=hist_median(hg,n);out[2]=hist_median(hb,n); return 1;
}
static int patch_median_gray(const GXImage *im, double x, double y, int radius, double *out) {
    int ix=(int)llround(x), iy=(int)llround(y);
    int x0=ix-radius, x1=ix+radius, y0=iy-radius, y1=iy+radius;
    if (x0<0)x0=0; if(y0<0)y0=0; if(x1>=im->width)x1=im->width-1; if(y1>=im->height)y1=im->height-1;
    if (x0>x1 || y0>y1) return 0;
    unsigned h[256]={0}, n=0;
    for(int yy=y0;yy<=y1;yy++) for(int xx=x0;xx<=x1;xx++) { h[luma8(pixel(im,xx,yy))]++;n++; }
    *out=hist_median(h,n); return 1;
}

static void rgb_to_ycbcr(const double rgb[3], double out[3]) {
    double r=rgb[0],g=rgb[1],b=rgb[2];
    out[0]=0.299*r+0.587*g+0.114*b;
    out[1]=128.0-0.168736*r-0.331264*g+0.5*b;
    out[2]=128.0+0.5*r-0.418688*g-0.081312*b;
}

static int sample_signature(const GXImage *im, double x,double y,const GXTraceSettings *s,GXSignature *sig) {
    if (s->match_mode==GX_MATCH_CONTRAST) {
        double center;
        if(!patch_median_gray(im,x,y,s->sample_radius_px,&center)) return 0;
        int ix=(int)llround(x),iy=(int)llround(y),r=s->contrast_ring_px,sr=s->sample_radius_px;
        unsigned h[256]={0},n=0;
        int x0=ix-r,x1=ix+r,y0=iy-r,y1=iy+r;
        if(x0<0)x0=0;if(y0<0)y0=0;if(x1>=im->width)x1=im->width-1;if(y1>=im->height)y1=im->height-1;
        for(int yy=y0;yy<=y1;yy++) for(int xx=x0;xx<=x1;xx++) {
            int d=abs(xx-ix)>abs(yy-iy)?abs(xx-ix):abs(yy-iy);
            if(d>sr && d<=r){h[luma8(pixel(im,xx,yy))]++;n++;}
        }
        double bg=n?hist_median(h,n):center;
        sig->v[0]=center;sig->v[1]=bg-center;sig->v[2]=0;return 1;
    }
    double rgb[3];
    if(!patch_median_rgb(im,x,y,s->sample_radius_px,rgb)) return 0;
    if(s->match_mode==GX_MATCH_GRAY){sig->v[0]=0.299*rgb[0]+0.587*rgb[1]+0.114*rgb[2];sig->v[1]=sig->v[2]=0;return 1;}
    if(s->match_mode==GX_MATCH_RGB){memcpy(sig->v,rgb,sizeof(rgb));return 1;}
    rgb_to_ycbcr(rgb,sig->v);return 1;
}

static double signature_error(const GXSignature *a,const GXSignature *b,GXMatchMode mode){
    if(mode==GX_MATCH_GRAY)return fabs(a->v[0]-b->v[0]);
    if(mode==GX_MATCH_RGB){double x=a->v[0]-b->v[0],y=a->v[1]-b->v[1],z=a->v[2]-b->v[2];return sqrt(x*x+y*y+z*z);}
    if(mode==GX_MATCH_LUMA_CHROMA){double x=a->v[0]-b->v[0],y=a->v[1]-b->v[1],z=a->v[2]-b->v[2];return sqrt(x*x+0.65*y*y+0.65*z*z);}
    return fabs(a->v[1]-b->v[1])+0.18*fabs(a->v[0]-b->v[0]);
}
static int normalize(double *x,double *y){double n=hypot(*x,*y);if(n<1e-9)return 0;*x/=n;*y/=n;return 1;}

static int target_from_seeds(const GXImage *im,GXPoint s1,const GXPoint *s2,const GXTraceSettings *s,GXSignature *target,char *err,size_t errcap){
    int margin=s->match_mode==GX_MATCH_CONTRAST?s->contrast_ring_px:s->sample_radius_px;
    if(!inside(im,s1.x,s1.y,margin) || (s2 && !inside(im,s2->x,s2->y,margin))){snprintf(err,errcap,"A seed point is outside the usable source-image area.");return 0;}
    GXSignature a,b;if(!sample_signature(im,s1.x,s1.y,s,&a)){snprintf(err,errcap,"Unable to sample seed appearance.");return 0;}
    if(s2){if(!sample_signature(im,s2->x,s2->y,s,&b)){snprintf(err,errcap,"Unable to sample second seed appearance.");return 0;}for(int i=0;i<3;i++)target->v[i]=0.5*(a.v[i]+b.v[i]);}
    else *target=a;
    return 1;
}

static void describe_target(const GXSignature *t,GXMatchMode mode,char *buf,size_t cap){
    if(mode==GX_MATCH_GRAY)snprintf(buf,cap,"gray=%.1f",t->v[0]);
    else if(mode==GX_MATCH_RGB)snprintf(buf,cap,"RGB=(%.0f, %.0f, %.0f)",t->v[0],t->v[1],t->v[2]);
    else if(mode==GX_MATCH_LUMA_CHROMA)snprintf(buf,cap,"Y/Cb/Cr=(%.1f, %.1f, %.1f)",t->v[0],t->v[1],t->v[2]);
    else {const char *p=t->v[1]>0?"dark-on-light":t->v[1]<0?"light-on-dark":"neutral";snprintf(buf,cap,"local contrast=%.1f (%s), center=%.1f",t->v[1],p,t->v[0]);}
}

static int build_profile(const GXImage *im,double cx,double cy,double tx,double ty,const GXSignature *target,const GXTraceSettings *s,double *errors){
    double nx=-ty,ny=tx;int r=s->search_radius_px,margin=s->match_mode==GX_MATCH_CONTRAST?s->contrast_ring_px:s->sample_radius_px;
    for(int o=-r;o<=r;o++) {double x=cx+nx*o,y=cy+ny*o; if(!inside(im,x,y,margin)){errors[o+r]=INFINITY;continue;} GXSignature a;if(!sample_signature(im,x,y,s,&a)){errors[o+r]=INFINITY;continue;}errors[o+r]=signature_error(&a,target,s->match_mode);}return 1;
}

static int clusters_from_profile(const double *errors,int r,double threshold,GXCluster *clusters,int cap){
    int n=0,in=0,start=0;double best=INFINITY,sum=0;int count=0;
    for(int i=0;i<2*r+1;i++){
        int ok=isfinite(errors[i])&&errors[i]<=threshold;
        if(ok&&!in){in=1;start=i;best=errors[i];sum=(i-r);count=1;}
        else if(ok){if(errors[i]<best)best=errors[i];sum+=(i-r);count++;}
        if((!ok||i==2*r)&&in){int end=ok?i:i-1;if(n<cap)clusters[n++]=(GXCluster){start-r,end-r,best,sum/count};in=0;}
    }return n;
}

static int seed_thickness(const GXImage *im,GXPoint start,double tx,double ty,const GXSignature *target,const GXTraceSettings *s){
    int r=s->search_radius_px;double *e=(double*)malloc((2*r+1)*sizeof(double));if(!e)return 1;build_profile(im,start.x,start.y,tx,ty,target,s,e);GXCluster c[32];int n=clusters_from_profile(e,r,s->match_tolerance,c,32);free(e);for(int i=0;i<n;i++)if(c[i].start<=0&&c[i].end>=0)return c[i].end-c[i].start+1;return 1;
}

static const char *profile_ambiguity(const double *errors,int r,int thick,const GXTraceSettings *s){
    GXCluster c[64];int n=clusters_from_profile(errors,r,s->match_tolerance,c,64);if(!n)return NULL;
    for(int i=0;i<n-1;i++)for(int j=i+1;j<n;j++)if(c[j].best<c[i].best){GXCluster t=c[i];c[i]=c[j];c[j]=t;}
    int width=c[0].end-c[0].start+1;int limit=(int)ceil(thick*s->thickness_factor);if(limit<thick+3)limit=thick+3;if(thick>0&&width>limit)return "ambiguous line thickening/intersection";
    if(n>=2){double sep=fabs(c[1].center-c[0].center),minsep=fmax(3.0,thick+1.0);if(sep>=minsep&&c[1].best<=c[0].best+s->ambiguity_margin)return "ambiguous competing trace";}
    return NULL;
}

static int trace_direction(const GXImage *im,GXPoint start,double tx,double ty,const GXSignature *target,const GXTraceSettings *s,const atomic_int *cancel,GXTraceResult *tmp,char *stop,size_t stopcap,char *err,size_t errcap){
    if(!normalize(&tx,&ty)){snprintf(err,errcap,"Seed direction is too short to define a trace direction.");return 0;}
    double x=start.x,y=start.y,step=s->step_px;int r=s->search_radius_px,thick=seed_thickness(im,start,tx,ty,target,s);double *errors=(double*)malloc((2*r+1)*sizeof(double));if(!errors){snprintf(err,errcap,"Out of memory.");return 0;}
    for(int iter=0;iter<s->max_steps;iter++){
        if(cancel&&atomic_load(cancel)){tmp->cancelled=1;snprintf(stop,stopcap,"cancelled");free(errors);return 1;}
        int found=0,used=1;GXPoint chosen={0,0};const char *reason="no candidate";
        for(int mult=1;mult<=1+s->noise_gap_steps;mult++){
            double px=x+tx*step*mult,py=y+ty*step*mult;int margin=s->match_mode==GX_MATCH_CONTRAST?s->contrast_ring_px:s->sample_radius_px;
            if(!inside(im,px,py,margin)){reason="image boundary";break;}
            build_profile(im,px,py,tx,ty,target,s,errors);const char *amb=profile_ambiguity(errors,r,thick,s);if(amb){reason=amb;break;}
            double nx=-ty,ny=tx,best=INFINITY,best_match=INFINITY;int besto=0;
            for(int o=-r;o<=r;o++){double me=errors[o+r];if(!isfinite(me))continue;double penalty=0.22*(fabs((double)o)/fmax(1.0,r))*fmin(255.0,s->match_tolerance*2.0);double score=me+penalty;if(score<best){best=score;best_match=me;besto=o;}}
            if(!isfinite(best_match)){reason="no candidate";continue;} if(best_match>s->match_tolerance){reason="match tolerance exceeded";continue;}
            chosen.x=px+nx*besto;chosen.y=py+ny*besto;found=1;used=mult;break;
        }
        if(!found){snprintf(stop,stopcap,"%s",reason);free(errors);return 1;}
        double dx=chosen.x-x,dy=chosen.y-y;if(hypot(dx,dy)<0.25){snprintf(stop,stopcap,"trace stalled");free(errors);return 1;}
        if(used>1&&!push_gap(tmp,(GXPoint){x,y},chosen)){snprintf(err,errcap,"Out of memory.");free(errors);return 0;}
        double ndx=dx,ndy=dy;if(!normalize(&ndx,&ndy)){snprintf(stop,stopcap,"trace stalled");free(errors);return 1;}
        tx=0.72*tx+0.28*ndx;ty=0.72*ty+0.28*ndy;normalize(&tx,&ty);x=chosen.x;y=chosen.y;if(!push_point(tmp,chosen)){snprintf(err,errcap,"Out of memory.");free(errors);return 0;}
    }
    snprintf(stop,stopcap,"maximum steps reached");free(errors);return 1;
}

static void orient_x(double *tx,double *ty,int positive){normalize(tx,ty);if(((*tx>=0)?1:0)!=positive){*tx=-*tx;*ty=-*ty;}if(fabs(*tx)<0.08){*tx=positive?1.0:-1.0;*ty=0.0;}}

static int append_result_points(GXTraceResult *dst,const GXTraceResult *src,int reverse){
    if(reverse){for(size_t i=src->point_count;i>0;i--)if(!push_point(dst,src->points[i-1]))return 0;}else{for(size_t i=0;i<src->point_count;i++)if(!push_point(dst,src->points[i]))return 0;}for(size_t i=0;i<src->gap_count;i++)if(!push_gap(dst,src->gaps[i].a,src->gaps[i].b))return 0;return 1;
}

int gx_trace_seed_guided(const GXImage *im,GXPoint seed1,const GXPoint *seed2,const GXTraceSettings *s,const atomic_int *cancel,GXTraceResult *out,char *err,size_t errcap){
    if(!im||!im->rgb||im->width<=0||im->height<=0){snprintf(err,errcap,"Source image is empty.");return 0;} if(!gx_trace_settings_validate(s,err,errcap))return 0;
    GXSignature target;if(!target_from_seeds(im,seed1,seed2,s,&target,err,errcap))return 0;describe_target(&target,s->match_mode,out->target_description,sizeof(out->target_description));
    double tx=1,ty=0;if(seed2){tx=seed2->x-seed1.x;ty=seed2->y-seed1.y;if(!normalize(&tx,&ty)){snprintf(err,errcap,"Seed direction is too short to define a trace direction.");return 0;}}
    GXTraceResult a,b;gx_trace_result_init(&a);gx_trace_result_init(&b);int ok=1;
    if(s->direction_mode==GX_DIR_SEED_FORWARD){GXPoint start=seed2?*seed2:seed1;if(!push_point(out,seed1)||(seed2&&!push_point(out,*seed2)))ok=0; if(ok)ok=trace_direction(im,start,tx,ty,&target,s,cancel,&a,out->stop_right,sizeof(out->stop_right),err,errcap);if(ok)ok=append_result_points(out,&a,0);}
    else if(s->direction_mode==GX_DIR_POSITIVE_X||s->direction_mode==GX_DIR_NEGATIVE_X){int pos=s->direction_mode==GX_DIR_POSITIVE_X;double ox=tx;orient_x(&tx,&ty,pos);GXPoint start=seed1;if(seed2&&tx*ox>=0)start=*seed2;if(!push_point(out,start))ok=0;char *stop=pos?out->stop_right:out->stop_left;size_t cap=pos?sizeof(out->stop_right):sizeof(out->stop_left);if(ok)ok=trace_direction(im,start,tx,ty,&target,s,cancel,&a,stop,cap,err,errcap);if(ok)ok=append_result_points(out,&a,0);}
    else {double ptx=tx,pty=ty,ntx=tx,nty=ty;orient_x(&ptx,&pty,1);orient_x(&ntx,&nty,0);GXPoint ps=seed1,ns=seed1;if(seed2){ps=seed2->x>=seed1.x?*seed2:seed1;ns=seed1.x<=seed2->x?seed1:*seed2;}ok=trace_direction(im,ns,ntx,nty,&target,s,cancel,&a,out->stop_left,sizeof(out->stop_left),err,errcap);if(ok)ok=trace_direction(im,ps,ptx,pty,&target,s,cancel,&b,out->stop_right,sizeof(out->stop_right),err,errcap);if(ok)ok=append_result_points(out,&a,1);if(ok){if(seed2){GXPoint l=seed1.x<=seed2->x?seed1:*seed2,r=seed1.x<=seed2->x?*seed2:seed1;ok=push_point(out,l)&&push_point(out,r);}else ok=push_point(out,seed1);}if(ok)ok=append_result_points(out,&b,0);}
    if(a.cancelled||b.cancelled)out->cancelled=1;gx_trace_result_free(&a);gx_trace_result_free(&b);if(!ok&&err&&!*err)snprintf(err,errcap,"Out of memory.");return ok;
}
