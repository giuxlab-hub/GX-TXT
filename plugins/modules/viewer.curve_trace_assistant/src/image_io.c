// SPDX-License-Identifier: GPL-3.0-or-later
#include "image_io.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>
#include <setjmp.h>

#include <png.h>
#include <jpeglib.h>
#ifdef HAVE_TIFF
#include <tiffio.h>
#endif
#ifdef HAVE_WEBP
#include <webp/decode.h>
#endif
#ifdef HAVE_GIF
#include <gif_lib.h>
#endif

static const uint8_t *ipixel(const GXImage *im,int x,int y){return im->rgb+(size_t)y*im->stride+(size_t)x*3;}

static int alloc_rgb(GXImage *im, int w, int h, char *err, size_t errcap) {
    if (w <= 0 || h <= 0 || w > 100000 || h > 100000) { snprintf(err, errcap, "Invalid image dimensions."); return 0; }
    if ((size_t)w > SIZE_MAX / 3 || (size_t)w * 3 > SIZE_MAX / (size_t)h) { snprintf(err, errcap, "Image dimensions overflow memory limits."); return 0; }
    im->width=w; im->height=h; im->stride=w*3; im->rgb=(uint8_t*)malloc((size_t)im->stride*h);
    if (!im->rgb) { snprintf(err, errcap, "Out of memory while allocating image."); return 0; }
    return 1;
}
void gx_image_free(GXImage *im){if(!im)return;free(im->rgb);memset(im,0,sizeof(*im));}

static int load_png(const char *path, GXImage *out, char *err, size_t errcap) {
    FILE *fp=fopen(path,"rb"); if(!fp){snprintf(err,errcap,"Unable to open PNG image.");return 0;}
    png_structp png=png_create_read_struct(PNG_LIBPNG_VER_STRING,NULL,NULL,NULL); png_infop info=png?png_create_info_struct(png):NULL;
    if(!png||!info){if(png)png_destroy_read_struct(&png,NULL,NULL);fclose(fp);snprintf(err,errcap,"Unable to initialize libpng.");return 0;}
    if(setjmp(png_jmpbuf(png))){png_destroy_read_struct(&png,&info,NULL);fclose(fp);gx_image_free(out);snprintf(err,errcap,"Unable to decode PNG image.");return 0;}
    png_init_io(png,fp);png_read_info(png,info);png_uint_32 w=png_get_image_width(png,info),h=png_get_image_height(png,info);int ct=png_get_color_type(png,info),bd=png_get_bit_depth(png,info);
    if(bd==16)png_set_strip_16(png);if(ct==PNG_COLOR_TYPE_PALETTE)png_set_palette_to_rgb(png);if(ct==PNG_COLOR_TYPE_GRAY&&bd<8)png_set_expand_gray_1_2_4_to_8(png);if(png_get_valid(png,info,PNG_INFO_tRNS))png_set_tRNS_to_alpha(png);if(ct==PNG_COLOR_TYPE_GRAY||ct==PNG_COLOR_TYPE_GRAY_ALPHA)png_set_gray_to_rgb(png);if(ct&PNG_COLOR_MASK_ALPHA)png_set_strip_alpha(png);png_read_update_info(png,info);
    if(!alloc_rgb(out,(int)w,(int)h,err,errcap)){png_destroy_read_struct(&png,&info,NULL);fclose(fp);return 0;}
    png_bytep *rows=(png_bytep*)malloc(sizeof(png_bytep)*h);if(!rows){gx_image_free(out);png_destroy_read_struct(&png,&info,NULL);fclose(fp);snprintf(err,errcap,"Out of memory while decoding PNG.");return 0;}
    for(png_uint_32 y=0;y<h;y++)rows[y]=out->rgb+(size_t)y*out->stride;png_read_image(png,rows);free(rows);png_destroy_read_struct(&png,&info,NULL);fclose(fp);return 1;
}

struct jpeg_err { struct jpeg_error_mgr pub; jmp_buf jb; };
static void jpeg_fail(j_common_ptr c){struct jpeg_err *e=(struct jpeg_err*)c->err;longjmp(e->jb,1);}
static int load_jpeg(const char *path,GXImage *out,char *err,size_t errcap){
    FILE *fp=fopen(path,"rb");if(!fp){snprintf(err,errcap,"Unable to open JPEG image.");return 0;}struct jpeg_decompress_struct c;struct jpeg_err je;c.err=jpeg_std_error(&je.pub);je.pub.error_exit=jpeg_fail;
    if(setjmp(je.jb)){jpeg_destroy_decompress(&c);fclose(fp);gx_image_free(out);snprintf(err,errcap,"Unable to decode JPEG image.");return 0;}jpeg_create_decompress(&c);jpeg_stdio_src(&c,fp);jpeg_read_header(&c,TRUE);c.out_color_space=JCS_RGB;jpeg_start_decompress(&c);
    if(!alloc_rgb(out,(int)c.output_width,(int)c.output_height,err,errcap)){jpeg_destroy_decompress(&c);fclose(fp);return 0;}while(c.output_scanline<c.output_height){JSAMPROW row=out->rgb+(size_t)c.output_scanline*out->stride;jpeg_read_scanlines(&c,&row,1);}jpeg_finish_decompress(&c);jpeg_destroy_decompress(&c);fclose(fp);return 1;
}

#ifdef HAVE_TIFF
static int load_tiff(const char *path,GXImage *out,char *err,size_t errcap){TIFF *t=TIFFOpen(path,"r");if(!t){snprintf(err,errcap,"Unable to open TIFF image.");return 0;}uint32_t w=0,h=0;TIFFGetField(t,TIFFTAG_IMAGEWIDTH,&w);TIFFGetField(t,TIFFTAG_IMAGELENGTH,&h);if(!w||!h||!alloc_rgb(out,(int)w,(int)h,err,errcap)){TIFFClose(t);return 0;}uint32_t *r=(uint32_t*)_TIFFmalloc((tmsize_t)w*h*sizeof(uint32_t));if(!r){gx_image_free(out);TIFFClose(t);snprintf(err,errcap,"Out of memory while decoding TIFF.");return 0;}if(!TIFFReadRGBAImageOriented(t,w,h,r,ORIENTATION_TOPLEFT,0)){_TIFFfree(r);gx_image_free(out);TIFFClose(t);snprintf(err,errcap,"Unable to decode TIFF image.");return 0;}for(uint32_t y=0;y<h;y++)for(uint32_t x=0;x<w;x++){uint32_t v=r[(size_t)y*w+x];uint8_t *p=out->rgb+(size_t)y*out->stride+x*3;p[0]=TIFFGetR(v);p[1]=TIFFGetG(v);p[2]=TIFFGetB(v);}_TIFFfree(r);TIFFClose(t);return 1;}
#endif

#ifdef HAVE_WEBP
static int load_webp(const char *path,GXImage *out,char *err,size_t errcap){FILE *fp=fopen(path,"rb");if(!fp){snprintf(err,errcap,"Unable to open WebP image.");return 0;}fseek(fp,0,SEEK_END);long n=ftell(fp);rewind(fp);if(n<=0){fclose(fp);snprintf(err,errcap,"Empty WebP image.");return 0;}uint8_t *buf=malloc((size_t)n);if(!buf||fread(buf,1,(size_t)n,fp)!=(size_t)n){free(buf);fclose(fp);snprintf(err,errcap,"Unable to read WebP image.");return 0;}fclose(fp);int w,h;uint8_t *rgb=WebPDecodeRGB(buf,(size_t)n,&w,&h);free(buf);if(!rgb){snprintf(err,errcap,"Unable to decode WebP image.");return 0;}if(!alloc_rgb(out,w,h,err,errcap)){WebPFree(rgb);return 0;}memcpy(out->rgb,rgb,(size_t)out->stride*h);WebPFree(rgb);return 1;}
#endif

#ifdef HAVE_GIF
static int load_gif(const char *path,GXImage *out,char *err,size_t errcap){int ec=0;GifFileType *g=DGifOpenFileName(path,&ec);if(!g){snprintf(err,errcap,"Unable to open GIF image.");return 0;}if(DGifSlurp(g)!=GIF_OK||g->ImageCount<1){DGifCloseFile(g,&ec);snprintf(err,errcap,"Unable to decode GIF image.");return 0;}SavedImage *si=&g->SavedImages[0];int w=g->SWidth,h=g->SHeight;if(!alloc_rgb(out,w,h,err,errcap)){DGifCloseFile(g,&ec);return 0;}memset(out->rgb,255,(size_t)out->stride*h);ColorMapObject *cm=si->ImageDesc.ColorMap?si->ImageDesc.ColorMap:g->SColorMap;if(!cm){gx_image_free(out);DGifCloseFile(g,&ec);snprintf(err,errcap,"GIF image has no color map.");return 0;}for(int y=0;y<si->ImageDesc.Height;y++)for(int x=0;x<si->ImageDesc.Width;x++){int dx=si->ImageDesc.Left+x,dy=si->ImageDesc.Top+y;if(dx<0||dy<0||dx>=w||dy>=h)continue;int idx=si->RasterBits[y*si->ImageDesc.Width+x];if(idx>=cm->ColorCount)continue;GifColorType c=cm->Colors[idx];uint8_t *p=out->rgb+(size_t)dy*out->stride+dx*3;p[0]=c.Red;p[1]=c.Green;p[2]=c.Blue;}DGifCloseFile(g,&ec);return 1;}
#endif

static int load_bmp(const char *path,GXImage *out,char *err,size_t errcap){FILE *f=fopen(path,"rb");if(!f)return 0;uint8_t h[54];if(fread(h,1,54,f)!=54||h[0]!='B'||h[1]!='M'){fclose(f);return 0;}uint32_t off=*(uint32_t*)&h[10],dib=*(uint32_t*)&h[14];int32_t w=*(int32_t*)&h[18],hh=*(int32_t*)&h[22];uint16_t planes=*(uint16_t*)&h[26],bpp=*(uint16_t*)&h[28];uint32_t comp=*(uint32_t*)&h[30];if(dib<40||w<=0||hh==0||planes!=1||(bpp!=24&&bpp!=32)||comp!=0){fclose(f);return 0;}int top=hh<0;int height=hh<0?-hh:hh;if(!alloc_rgb(out,w,height,err,errcap)){fclose(f);return 0;}int row=((w*bpp+31)/32)*4;uint8_t *buf=malloc(row);if(!buf){gx_image_free(out);fclose(f);return 0;}fseek(f,(long)off,SEEK_SET);for(int sy=0;sy<height;sy++){if(fread(buf,1,row,f)!=(size_t)row){free(buf);gx_image_free(out);fclose(f);return 0;}int y=top?sy:height-1-sy;for(int x=0;x<w;x++){uint8_t *p=out->rgb+(size_t)y*out->stride+x*3;uint8_t *q=buf+x*(bpp/8);p[0]=q[2];p[1]=q[1];p[2]=q[0];}}free(buf);fclose(f);return 1;}

static int load_pnm(const char *path,GXImage *out,char *err,size_t errcap){FILE *f=fopen(path,"rb");if(!f)return 0;char magic[3]={0};if(fscanf(f,"%2s",magic)!=1||(strcmp(magic,"P6")&&strcmp(magic,"P5"))){fclose(f);return 0;}int c;do{c=fgetc(f);if(c=='#')while((c=fgetc(f))!='\n'&&c!=EOF){}}while(isspace(c));ungetc(c,f);int w,h,maxv;if(fscanf(f,"%d %d %d",&w,&h,&maxv)!=3||maxv<=0||maxv>255){fclose(f);return 0;}fgetc(f);if(!alloc_rgb(out,w,h,err,errcap)){fclose(f);return 0;}if(!strcmp(magic,"P6")){if(fread(out->rgb,1,(size_t)out->stride*h,f)!=(size_t)out->stride*h){gx_image_free(out);fclose(f);return 0;}}else{for(int y=0;y<h;y++)for(int x=0;x<w;x++){int v=fgetc(f);if(v==EOF){gx_image_free(out);fclose(f);return 0;}uint8_t *p=out->rgb+(size_t)y*out->stride+x*3;p[0]=p[1]=p[2]=(uint8_t)v;}}fclose(f);return 1;}

static int ends(const char *p,const char *ext){size_t a=strlen(p),b=strlen(ext);if(a<b)return 0;p+=a-b;for(size_t i=0;i<b;i++)if(tolower((unsigned char)p[i])!=tolower((unsigned char)ext[i]))return 0;return 1;}
int gx_image_load(const char *path,GXImage *out,char *err,size_t errcap){memset(out,0,sizeof(*out));
    if(ends(path,".png")&&load_png(path,out,err,errcap))return 1;if((ends(path,".jpg")||ends(path,".jpeg"))&&load_jpeg(path,out,err,errcap))return 1;
#ifdef HAVE_TIFF
    if((ends(path,".tif")||ends(path,".tiff"))&&load_tiff(path,out,err,errcap))return 1;
#endif
#ifdef HAVE_WEBP
    if(ends(path,".webp")&&load_webp(path,out,err,errcap))return 1;
#endif
#ifdef HAVE_GIF
    if(ends(path,".gif")&&load_gif(path,out,err,errcap))return 1;
#endif
    if(ends(path,".bmp")&&load_bmp(path,out,err,errcap))return 1;if((ends(path,".ppm")||ends(path,".pgm")||ends(path,".pnm"))&&load_pnm(path,out,err,errcap))return 1;
    // Signature fallback for canonical resources whose extension is not descriptive.
    if(load_png(path,out,err,errcap))return 1; if(load_jpeg(path,out,err,errcap))return 1;
#ifdef HAVE_TIFF
    if(load_tiff(path,out,err,errcap))return 1;
#endif
#ifdef HAVE_WEBP
    if(load_webp(path,out,err,errcap))return 1;
#endif
#ifdef HAVE_GIF
    if(load_gif(path,out,err,errcap))return 1;
#endif
    if(load_bmp(path,out,err,errcap))return 1;if(load_pnm(path,out,err,errcap))return 1;snprintf(err,errcap,"Unsupported or invalid image format: %s",path);return 0;}

int gx_pyramid_build(const GXImage *base,GXPyramid *p,char *err,size_t errcap){memset(p,0,sizeof(*p));int count=1,w=base->width,h=base->height;while((w>512||h>512)&&count<16){w=(w+1)/2;h=(h+1)/2;count++;}p->levels=calloc((size_t)count,sizeof(GXImage));if(!p->levels){snprintf(err,errcap,"Out of memory while creating image pyramid.");return 0;}p->count=count;if(!alloc_rgb(&p->levels[0],base->width,base->height,err,errcap)){gx_pyramid_free(p);return 0;}memcpy(p->levels[0].rgb,base->rgb,(size_t)base->stride*base->height);
    for(int l=1;l<count;l++){GXImage *src=&p->levels[l-1],*dst=&p->levels[l];int dw=(src->width+1)/2,dh=(src->height+1)/2;if(!alloc_rgb(dst,dw,dh,err,errcap)){gx_pyramid_free(p);return 0;}for(int y=0;y<dh;y++)for(int x=0;x<dw;x++){int sum[3]={0},n=0;for(int yy=0;yy<2;yy++)for(int xx=0;xx<2;xx++){int sx=x*2+xx,sy=y*2+yy;if(sx<src->width&&sy<src->height){const uint8_t *q=ipixel(src,sx,sy);sum[0]+=q[0];sum[1]+=q[1];sum[2]+=q[2];n++;}}uint8_t *d=dst->rgb+(size_t)y*dst->stride+x*3;d[0]=sum[0]/n;d[1]=sum[1]/n;d[2]=sum[2]/n;}}
    return 1;}
void gx_pyramid_free(GXPyramid *p){if(!p)return;for(int i=0;i<p->count;i++)gx_image_free(&p->levels[i]);free(p->levels);memset(p,0,sizeof(*p));}
