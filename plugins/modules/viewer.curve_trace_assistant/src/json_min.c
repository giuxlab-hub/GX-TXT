// SPDX-License-Identifier: GPL-3.0-or-later
#include "json_min.h"
#include <ctype.h>
#include <string.h>

static int alloc_tok(JTok *t,int cap,int *n,JType type,int start,int parent){if(*n>=cap)return -1;int i=(*n)++;t[i]=(JTok){type,start,-1,0,parent};if(parent>=0)t[parent].size++;return i;}
int j_parse(const char *js,JTok *t,int cap){int n=0,parent=-1;for(int p=0;js[p];){char c=js[p];if(isspace((unsigned char)c)||c==':'||c==','){p++;continue;}if(c=='{'||c=='['){int i=alloc_tok(t,cap,&n,c=='{'?J_OBJECT:J_ARRAY,p,parent);if(i<0)return -1;parent=i;p++;continue;}if(c=='}'||c==']'){JType want=c=='}'?J_OBJECT:J_ARRAY;int i=parent;if(i<0||t[i].type!=want)return -2;t[i].end=p+1;parent=t[i].parent;p++;continue;}if(c=='"'){int s=++p;for(;js[p];p++){if(js[p]=='\\'){if(js[p+1])p++;continue;}if(js[p]=='"')break;}if(!js[p])return -2;int i=alloc_tok(t,cap,&n,J_STRING,s,parent);if(i<0)return -1;t[i].end=p;p++;continue;}int s=p;for(;js[p]&&!isspace((unsigned char)js[p])&&js[p]!=','&&js[p]!=']'&&js[p]!='}';p++);int i=alloc_tok(t,cap,&n,J_PRIMITIVE,s,parent);if(i<0)return -1;t[i].end=p;}if(parent!=-1)return -2;return n;}
int j_skip(const JTok *t,int i){int end=t[i].end;i++;while(t[i].start>=0&&t[i].start<end)i++;return i;}
static int eq(const char *js,const JTok *t,const char *s){size_t n=strlen(s);return t->type==J_STRING&&(size_t)(t->end-t->start)==n&&!strncmp(js+t->start,s,n);}
int j_obj_get(const char *js,const JTok *t,int obj,const char *key){if(t[obj].type!=J_OBJECT)return -1;int i=obj+1;while(t[i].start<t[obj].end-1){int k=i;if(t[k].type!=J_STRING)return -1;int v=k+1;if(eq(js,&t[k],key))return v;i=j_skip(t,v);}return -1;}
int j_array_nth(const JTok *t,int arr,int n){if(t[arr].type!=J_ARRAY)return -1;int i=arr+1;for(int k=0;k<n;k++){if(t[i].start>=t[arr].end-1)return -1;i=j_skip(t,i);}return t[i].start<t[arr].end-1?i:-1;}
int j_token_str(const char *js,const JTok *tok,char *out,size_t cap){if(!out||cap==0)return 0;size_t o=0;for(int i=tok->start;i<tok->end&&o+1<cap;i++){char c=js[i];if(c=='\\'&&i+1<tok->end){char n=js[++i];switch(n){case 'n':c='\n';break;case 'r':c='\r';break;case 't':c='\t';break;case 'b':c='\b';break;case 'f':c='\f';break;case '"':c='"';break;case '\\':c='\\';break;case '/':c='/';break;default:c=n;break;}}out[o++]=c;}out[o]=0;return 1;}
