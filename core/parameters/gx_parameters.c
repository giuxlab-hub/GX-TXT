/* SPDX-License-Identifier: GPL-3.0-or-later
 * Portable C99 numeric expressions. No Tcl, filesystem, process or UI authority.
 * DFS colors detect cycles; sorted names make batch recalculation deterministic. */
#include "gx_parameters.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <math.h>
#include <stdarg.h>
#define GP_LIMIT 4096
#define GP_DEPTH 128
typedef struct {char *name,*formula,*dependencies;double value;int color;} parameter;
struct gp_context {parameter *items;size_t count;gp_context *session;char error[512];unsigned depth;};
typedef struct {gp_context *context;const char *at;parameter *owner;unsigned depth;} parser;
static char *copy(const char *s){size_t n=strlen(s)+1;char *p=malloc(n);if(p)memcpy(p,s,n);return p;}
static int fail(gp_context *c,const char *format,...){if(!c->error[0]){va_list ap;va_start(ap,format);vsnprintf(c->error,sizeof(c->error),format,ap);va_end(ap);}return 0;}
static int valid_name(const char *s){if(!s||!(isalpha((unsigned char)*s)||*s=='_'))return 0;for(s++;*s;s++)if(!(isalnum((unsigned char)*s)||*s=='_'))return 0;return 1;}
static parameter *find(gp_context *c,const char *name){for(size_t i=0;i<c->count;i++)if(!strcmp(c->items[i].name,name))return &c->items[i];return NULL;}
gp_context *gp_create(gp_context *session){gp_context *c=calloc(1,sizeof(*c));if(c)c->session=session;return c;}
void gp_destroy(gp_context *c){if(!c)return;for(size_t i=0;i<c->count;i++){free(c->items[i].name);free(c->items[i].formula);free(c->items[i].dependencies);}free(c->items);free(c);}
static int compare(const void *a,const void *b){return strcmp(((const parameter *)a)->name,((const parameter *)b)->name);}
int gp_define(gp_context *c,const char *name,const char *formula){
    if(!c)return 0;c->error[0]=0;
    if(!valid_name(name)||strlen(name)>127||!strcmp(name,"pi")||!strcmp(name,"e")||!strcmp(name,"session"))return fail(c,"Invalid or reserved parameter name");
    if(!formula||!formula[0]||strlen(formula)>GP_LIMIT)return fail(c,"Expression must contain 1..4096 characters");
    char *text=copy(formula);if(!text)return fail(c,"Out of memory");parameter *p=find(c,name);
    if(p){free(p->formula);p->formula=text;}
    else {if(c->count==GP_LIMIT){free(text);return fail(c,"Parameter limit reached");}char *id=copy(name);parameter *items=id?realloc(c->items,(c->count+1)*sizeof(*items)):NULL;if(!items){free(id);free(text);return fail(c,"Out of memory");}c->items=items;c->items[c->count++]=(parameter){id,text,NULL,0,0};qsort(c->items,c->count,sizeof(*items),compare);}
    for(size_t i=0;i<c->count;i++)c->items[i].color=0;return 1;
}
int gp_remove(gp_context *c,const char *name){if(!c||!name)return 0;parameter *p=find(c,name);if(!p)return fail(c,"Unknown parameter '%s'",name);size_t i=(size_t)(p-c->items);free(p->name);free(p->formula);free(p->dependencies);memmove(p,p+1,(c->count-i-1)*sizeof(*p));c->count--;for(i=0;i<c->count;i++)c->items[i].color=0;return 1;}
static void spaces(parser *p){while(isspace((unsigned char)*p->at))p->at++;}
static double expression(parser *);
static int evaluate_parameter(gp_context *c,parameter *p);
static void dependency(parser *p,const char *name){if(!p->owner)return;char **d=&p->owner->dependencies;size_t n=*d?strlen(*d):0;if(n>GP_LIMIT*128u){fail(p->context,"Dependency list exceeds limit");return;}char *next=realloc(*d,n+strlen(name)+2);if(!next){fail(p->context,"Out of memory");return;}*d=next;snprintf(next+n,strlen(name)+2,"%s%s",n?" ":"",name);}
static double primary(parser *p){
    gp_context *c=p->context;spaces(p);if(++p->depth>GP_DEPTH){fail(c,"Expression nesting limit exceeded");p->depth--;return 0;}double value=0;
    if(*p->at=='('){p->at++;value=expression(p);spaces(p);if(*p->at!=')')fail(c,"Expected ')' near %.24s",p->at);else p->at++;}
    else if(isdigit((unsigned char)*p->at)||*p->at=='.'){char *end;value=strtod(p->at,&end);if(end==p->at)fail(c,"Invalid number");else p->at=end;}
    else if(isalpha((unsigned char)*p->at)||*p->at=='_'){
        char name[256];size_t n=0;while(isalnum((unsigned char)*p->at)||*p->at=='_'||*p->at=='.'){if(n<sizeof(name)-1)name[n++]=*p->at;else fail(c,"Identifier exceeds limit");p->at++;}name[n]=0;spaces(p);
        if(*p->at=='('){p->at++;double a=expression(p),b=0;int two=0;spaces(p);if(*p->at==','){two=1;p->at++;b=expression(p);spaces(p);}if(*p->at!=')')fail(c,"Expected ')' after function %s",name);else p->at++;
#define FN1(n,f) if(!strcmp(name,n)&&!two)value=f(a)
#define FN2(n,f) if(!strcmp(name,n)&&two)value=f(a,b)
            FN1("sqrt",sqrt);else FN1("abs",fabs);else FN1("sin",sin);else FN1("cos",cos);else FN1("tan",tan);else FN1("asin",asin);else FN1("acos",acos);else FN1("atan",atan);else FN1("exp",exp);else FN1("log",log);else FN1("log10",log10);else FN1("floor",floor);else FN1("ceil",ceil);else FN2("min",fmin);else FN2("max",fmax);else FN2("pow",pow);else FN2("atan2",atan2);else fail(c,"Unknown function or arity: %s",name);
#undef FN1
#undef FN2
        }else if(!strcmp(name,"pi"))value=acos(-1.0);else if(!strcmp(name,"e"))value=exp(1.0);
        else {dependency(p,name);gp_context *scope=c;const char *key=name;if(!strncmp(name,"session.",8)){scope=c->session;key=name+8;}if(!scope){fail(c,"Session parameter scope unavailable: %s",name);}else {parameter *item=find(scope,key);if(!item)fail(c,"Unknown parameter '%s'",name);else if(evaluate_parameter(scope,item))value=item->value;else fail(c,"%s",scope->error);}}
    }else fail(c,"Expected number, parameter or '(' near %.24s",p->at);
    p->depth--;if(!isfinite(value))fail(c,"Non-finite result or function domain error");return value;
}
static double unary(parser *p);
static double power(parser *p){double a=primary(p);spaces(p);if(*p->at=='^'&&!p->context->error[0]){p->at++;if(++p->depth>GP_DEPTH){fail(p->context,"Expression nesting limit exceeded");p->depth--;return 0;}a=pow(a,unary(p));p->depth--;}return a;}
static double unary(parser *p){spaces(p);if(*p->at=='+'||*p->at=='-'){int negative=*p->at++=='-';if(++p->depth>GP_DEPTH){fail(p->context,"Expression nesting limit exceeded");p->depth--;return 0;}double v=unary(p);p->depth--;return negative?-v:v;}return power(p);}
static double product(parser *p){double a=unary(p);for(;;){spaces(p);char op=*p->at;if((op!='*'&&op!='/')||p->context->error[0])break;p->at++;double b=unary(p);if(op=='/'&&b==0)fail(p->context,"Division by zero");else a=op=='*'?a*b:a/b;}return a;}
static double expression(parser *p){double a=product(p);for(;;){spaces(p);char op=*p->at;if((op!='+'&&op!='-')||p->context->error[0])break;p->at++;double b=product(p);a=op=='+'?a+b:a-b;}return a;}
static int parse(gp_context *c,const char *text,parameter *owner,double *out){parser p={c,text,owner,0};double v=expression(&p);spaces(&p);if(*p.at)fail(c,"Unexpected text near %.24s",p.at);if(!isfinite(v))fail(c,"Non-finite result");if(c->error[0])return 0;*out=v;return 1;}
static int evaluate_parameter(gp_context *c,parameter *p){if(p->color==2)return 1;if(p->color==1)return fail(c,"Dependency cycle at '%s'",p->name);if(c->depth>=GP_DEPTH)return fail(c,"Dependency depth limit at '%s'",p->name);c->depth++;p->color=1;free(p->dependencies);p->dependencies=NULL;int ok=parse(c,p->formula,p,&p->value);p->color=ok?2:0;c->depth--;return ok;}
int gp_recalculate(gp_context *c){if(!c)return 0;c->error[0]=0;c->depth=0;for(size_t i=0;i<c->count;i++)c->items[i].color=0;for(size_t i=0;i<c->count;i++)if(!evaluate_parameter(c,&c->items[i]))return 0;return 1;}
int gp_evaluate(gp_context *c,const char *expression,double *value){if(!c||!expression||!value)return 0;if(strlen(expression)>GP_LIMIT)return fail(c,"Expression exceeds limit");if(!gp_recalculate(c))return 0;return parse(c,expression,NULL,value);}
int gp_lookup(gp_context *c,const char *name,double *value){if(!c||!name||!value||!gp_recalculate(c))return 0;parameter *p=find(c,name);if(!p)return fail(c,"Unknown parameter '%s'",name);*value=p->value;return 1;}
size_t gp_count(const gp_context *c){return c?c->count:0;}
const char *gp_name(const gp_context *c,size_t i){return c&&i<c->count?c->items[i].name:NULL;}
const char *gp_formula(const gp_context *c,size_t i){return c&&i<c->count?c->items[i].formula:NULL;}
const char *gp_dependencies(const gp_context *c,size_t i){return c&&i<c->count&&c->items[i].dependencies?c->items[i].dependencies:"";}
const char *gp_diagnostic(const gp_context *c){return c?c->error:"Missing parameter context";}
