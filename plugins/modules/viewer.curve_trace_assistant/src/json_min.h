#ifndef GX_JSON_MIN_H
#define GX_JSON_MIN_H
#include <stddef.h>
typedef enum { J_UNDEF=0,J_OBJECT,J_ARRAY,J_STRING,J_PRIMITIVE } JType;
typedef struct { JType type; int start,end,size,parent; } JTok;
int j_parse(const char *js, JTok *t, int cap);
int j_skip(const JTok *t,int i);
int j_obj_get(const char *js,const JTok *t,int obj,const char *key);
int j_array_nth(const JTok *t,int arr,int n);
int j_token_str(const char *js,const JTok *tok,char *out,size_t cap);
#endif
