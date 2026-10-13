/* Internal bounded typed-column marshalling; geometry remains in gx2d.c. */
typedef struct {const unsigned char *bytes;Tcl_Obj **values;size_t count,width;int kind,big;} numeric_column;
static int column_field(Tcl_Interp *ip,Tcl_Obj *arg,const char *name,Tcl_Obj **out) {
    Tcl_Obj *key=Tcl_NewStringObj(name,-1);int code;Tcl_IncrRefCount(key);
    code=Tcl_DictObjGet(ip,arg,key,out);Tcl_DecrRefCount(key);return code;
}
static int numeric_column_read(Tcl_Interp *ip,Tcl_Obj *arg,numeric_column *out) {
    Tcl_Obj *values=NULL,*raw=NULL,*dtype=NULL,*endian=NULL;int n;const char *type;
    memset(out,0,sizeof(*out));
    if(column_field(ip,arg,"values",&values)!=TCL_OK)return TCL_ERROR;
    if(values){
        if(Tcl_ListObjGetElements(ip,values,&n,&out->values)!=TCL_OK)return TCL_ERROR;out->count=(size_t)n;
        if(column_field(ip,arg,"dtype",&dtype)!=TCL_OK)return TCL_ERROR;
        if(dtype){type=Tcl_GetString(dtype);
            if(strncmp(type,"uint",4)==0)out->kind=5;else if(strncmp(type,"int",3)==0)out->kind=6;
            else if(strcmp(type,"bool")==0)out->kind=4;}
    }
    else{
        if(column_field(ip,arg,"raw",&raw)!=TCL_OK||!raw||
           column_field(ip,arg,"dtype",&dtype)!=TCL_OK||!dtype||
           column_field(ip,arg,"endian",&endian)!=TCL_OK||!endian)return fail(ip,"Numeric column needs values or raw/dtype/endian");
        type=Tcl_GetString(dtype);
        if(strcmp(type,"float64")==0){out->kind=1;out->width=8;}
        else if(strcmp(type,"float32")==0){out->kind=2;out->width=4;}
        else if(strcmp(type,"float16")==0){out->kind=3;out->width=2;}
        else if(strcmp(type,"bool")==0){out->kind=4;out->width=1;}
        else if(strncmp(type,"uint",4)==0||strncmp(type,"int",3)==0){
            const char *bits=type+(type[0]=='u'?4:3);
            if(strcmp(bits,"8")==0)out->width=1;else if(strcmp(bits,"16")==0)out->width=2;
            else if(strcmp(bits,"32")==0)out->width=4;else if(strcmp(bits,"64")==0)out->width=8;
            else return fail(ip,"Unsupported integer column dtype");out->kind=type[0]=='u'?5:6;
        }else return fail(ip,"Native2D requires a numeric column dtype");
        if(strcmp(Tcl_GetString(endian),"big")==0)out->big=1;
        else if(strcmp(Tcl_GetString(endian),"little")!=0)return fail(ip,"Numeric column endian must be little or big");
        out->bytes=Tcl_GetByteArrayFromObj(raw,&n);
        if((size_t)n%out->width)return fail(ip,"Numeric column byte count is inconsistent");out->count=(size_t)n/out->width;
    }
    if(out->count>65536)return fail(ip,"Native2D numeric chunk exceeds 65536 rows");return TCL_OK;
}
static int numeric_column_value(Tcl_Interp *ip,const numeric_column *c,size_t index,double *out) {
    uint64_t bits=0;size_t j;const unsigned char *p;int64_t signed_value;
    if(c->values){
        /* Canonical value transport preserves missing cells as empty tokens.
         * Mark the pair nonfinite without coercing exact integer coordinates. */
        if(Tcl_GetCharLength(c->values[index])==0){*out=NAN;return TCL_OK;}
        if(c->kind==5||c->kind==6){
            Tcl_WideInt value;double check;
            if(Tcl_GetWideIntFromObj(ip,c->values[index],&value)!=TCL_OK||Tcl_GetDoubleFromObj(ip,c->values[index],&check)!=TCL_OK)return TCL_ERROR;
            signed_value=(int64_t)value;
            if(check!=(double)signed_value)return fail(ip,"Integer coordinate is outside its declared 64-bit range");
            if(signed_value>INT64_C(9007199254740992)||signed_value<-INT64_C(9007199254740992)||(c->kind==5&&signed_value<0))return fail(ip,"Integer coordinate exceeds exact Native2D double range");
            *out=(double)signed_value;return TCL_OK;
        }
        if(c->kind==4){int value;if(Tcl_GetBooleanFromObj(ip,c->values[index],&value)!=TCL_OK)return TCL_ERROR;*out=value;return TCL_OK;}
        {const char *word=Tcl_GetString(c->values[index]);
            if(Tcl_StringCaseMatch(word,"nan",1)||Tcl_StringCaseMatch(word,"+nan",1)||Tcl_StringCaseMatch(word,"-nan",1)){*out=NAN;return TCL_OK;}}
        return Tcl_GetDoubleFromObj(ip,c->values[index],out);
    }
    p=c->bytes+index*c->width;
    for(j=0;j<c->width;++j)bits|=(uint64_t)p[c->big?c->width-j-1:j]<<(8*j);
    if(c->kind==1)memcpy(out,&bits,8);
    else if(c->kind==2){uint32_t word=(uint32_t)bits;float value;memcpy(&value,&word,4);*out=value;}
    else if(c->kind==3){unsigned exponent=(unsigned)(bits>>10)&31,mantissa=(unsigned)bits&1023;
        double value=exponent==31?(mantissa?NAN:INFINITY):exponent?ldexp(1+mantissa/1024.,(int)exponent-15):ldexp(mantissa/1024.,-14);
        *out=(bits&32768)?-value:value;}
    else if(c->kind==4)*out=bits?1:0;
    else if(c->kind==5){if(bits>UINT64_C(9007199254740992))return fail(ip,"Integer coordinate exceeds exact Native2D double range");*out=(double)bits;}
    else{
        if(c->width<8&&(bits&(UINT64_C(1)<<(8*c->width-1))))bits|=UINT64_MAX<<(8*c->width);
        memcpy(&signed_value,&bits,8);
        if(signed_value>INT64_C(9007199254740992)||signed_value<-INT64_C(9007199254740992))return fail(ip,"Integer coordinate exceeds exact Native2D double range");
        *out=(double)signed_value;
    }
    return TCL_OK;
}
static int numeric_column_row(Tcl_Interp *ip,const numeric_column *c,size_t index,uint64_t *out) {
    uint64_t value=0;size_t j;Tcl_WideInt row;
    if(c->values){double check;if(Tcl_GetWideIntFromObj(ip,c->values[index],&row)!=TCL_OK||row<0||Tcl_GetDoubleFromObj(ip,c->values[index],&check)!=TCL_OK||check!=(double)row)return fail(ip,"Source-row identity must be a nonnegative signed 64-bit integer");*out=(uint64_t)row;return TCL_OK;}
    if(c->kind!=5&&c->kind!=6)return fail(ip,"Source-row identity requires an integer dtype");
    for(j=0;j<c->width;++j)value|=(uint64_t)c->bytes[index*c->width+(c->big?c->width-j-1:j)]<<(8*j);
    if((c->kind==6&&(value&(UINT64_C(1)<<(8*c->width-1))))||value>INT64_MAX)return fail(ip,"Source-row identity is outside the signed 64-bit nonnegative range");
    *out=value;return TCL_OK;
}
