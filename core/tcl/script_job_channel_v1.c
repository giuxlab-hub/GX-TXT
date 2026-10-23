/* SPDX-License-Identifier: GPL-3.0-or-later
 * Private leaf of the existing ScriptJob owner, SOURCE PREPARATION ONLY.
 * No Tcl evaluation, channel/process creation, cancellation or diagnostics copy.
 * Expected refusals return TCL_OK. Load only during NONSECRET initialization.
 */
#include <tcl.h>
#include <string.h>

#if TCL_MAJOR_VERSION != 8 || TCL_MINOR_VERSION != 6
#error "The private protected ScriptJob source requires Tcl 8.6 headers"
#endif
#if defined(_WIN32)
#error "The private protected ScriptJob source requires a reviewed Unix pipe driver"
#endif

#define GX_SEND "::GX::ScriptJob::_protectedSend"
#define GX_INFO "::GX::ScriptJob::_protectedSendInfo"
#define GX_REQUESTS "::GX::scriptJobRequests"
#define GX_PENDING_LIMIT 65536

typedef enum {
    GX_ARITY, GX_INACTIVE, GX_FRAME, GX_CHANNEL, GX_BUSY, GX_WRITE_FAILED
} GxFailure;

static void
put(Tcl_Obj *dict, const char *key, Tcl_Obj *value)
{
    /* A new, unshared dictionary with fixed keys cannot have a type error. */
    (void)Tcl_DictObjPut(NULL, dict, Tcl_NewStringObj(key, -1), value);
}

static int
refuse(Tcl_Interp *ip, GxFailure failure, int attempted)
{
    static const char *const codes[] = {
        "ARITY", "INACTIVE", "FRAME", "CHANNEL", "BUSY", "WRITE_FAILED"
    };
    static const char *const messages[] = {
        "Protected send requires a request and one complete frame.",
        "Protected managed request is not active.",
        "Protected frame contains a forbidden character.",
        "Protected managed channel is unavailable or unsupported.",
        "Protected pending-output budget would be exceeded.",
        "Protected managed channel write failed."
    };
    Tcl_Obj *result = Tcl_NewDictObj();
    put(result, "ok", Tcl_NewBooleanObj(0));
    put(result, "code", Tcl_NewStringObj(codes[failure], -1));
    put(result, "message", Tcl_NewStringObj(messages[failure], -1));
    if (attempted) {
        put(result, "mutation_outcome", Tcl_NewStringObj("unknown", -1));
    }
    /* This replaces the ordinary result, never errorInfo/errorstack/options. */
    Tcl_SetObjResult(ip, result);
    return TCL_OK;
}

static Tcl_Obj *
field(Tcl_Obj *dict, const char *name)
{
    Tcl_Obj *key = Tcl_NewStringObj(name, -1), *value = NULL;
    Tcl_IncrRefCount(key);
    if (Tcl_DictObjGet(NULL, dict, key, &value) != TCL_OK) {
        value = NULL;
    }
    Tcl_DecrRefCount(key);
    return value;
}

static int
equal_option(Tcl_Channel channel, const char *name, const char *expected)
{
    Tcl_DString value;
    int matched;
    size_t size = strlen(expected);
    Tcl_DStringInit(&value);
    matched = Tcl_GetChannelOption(NULL, channel, name, &value) == TCL_OK
            && Tcl_DStringLength(&value) == (int)size
            && memcmp(Tcl_DStringValue(&value), expected, size) == 0;
    Tcl_DStringFree(&value);
    return matched;
}

static int
request_name(Tcl_Obj *value)
{
    const char *name;
    int length, index;
    /* Normal owner IDs are job-request- followed by a positive decimal serial.
     * The bounded private leaf does not accept arbitrary foreign map keys.
     */
    if (Tcl_GetCharLength(value) < 13 || Tcl_GetCharLength(value) > 64) {
        return 0;
    }
    name = Tcl_GetStringFromObj(value, &length);
    if (length < 13 || length > 64 || memcmp(name, "job-request-", 12) != 0
            || name[12] < '1' || name[12] > '9') {
        return 0;
    }
    for (index = 13; index < length; ++index) {
        if (name[index] < '0' || name[index] > '9') {
            return 0;
        }
    }
    return 1;
}

static int
protected_send(ClientData data, Tcl_Interp *ip, int objc,
        Tcl_Obj *const objv[])
{
    Tcl_Obj *requests, *entry = NULL, *options, *duplex, *cancelled, *pipe;
    Tcl_Channel channel;
    const Tcl_ChannelType *type;
    Tcl_Encoding utf8 = (Tcl_Encoding)data;
    Tcl_DString external, framed;
    const Tcl_UniChar *characters;
    const char *source, *pipe_name;
    int character_count, source_bytes, pipe_bytes, index, mode, flag;
    int payload_bytes, pending, written, code;

    if (objc != 3) {
        return refuse(ip, GX_ARITY, 0);
    }
    if (!request_name(objv[1])) {
        return refuse(ip, GX_INACTIVE, 0);
    }
    /* Read exactly the current owner map. No LEAVE_ERR_MSG and no map copy
     * containing a payload. Hostile variable traces are outside this boundary.
     */
    requests = Tcl_GetVar2Ex(ip, GX_REQUESTS, NULL, TCL_GLOBAL_ONLY);
    if (requests == NULL) {
        return refuse(ip, GX_INACTIVE, 0);
    }
    Tcl_IncrRefCount(requests);
    if (Tcl_DictObjGet(NULL, requests, objv[1], &entry) != TCL_OK
            || entry == NULL
            || (options = field(entry, "options")) == NULL
            || (duplex = field(options, "duplex")) == NULL
            || Tcl_GetBooleanFromObj(NULL, duplex, &flag) != TCL_OK || !flag
            || (cancelled = field(entry, "cancelled")) == NULL
            || Tcl_GetCharLength(cancelled) != 0
            || (pipe = field(entry, "pipe")) == NULL) {
        Tcl_DecrRefCount(requests);
        return refuse(ip, GX_INACTIVE, 0);
    }
    /* Actual Unix command channels use fileN; refuse unrelated names before
     * Tcl_GetChannel can put their text into its ordinary lookup diagnostic.
     */
    if (Tcl_GetCharLength(pipe) < 5 || Tcl_GetCharLength(pipe) > 32) {
        Tcl_DecrRefCount(requests);
        return refuse(ip, GX_CHANNEL, 0);
    }
    pipe_name = Tcl_GetStringFromObj(pipe, &pipe_bytes);
    if (pipe_bytes < 5 || pipe_bytes > 32
            || memcmp(pipe_name, "file", 4) != 0) {
        Tcl_DecrRefCount(requests);
        return refuse(ip, GX_CHANNEL, 0);
    }
    for (index = 4; index < pipe_bytes; ++index) {
        if (pipe_name[index] < '0' || pipe_name[index] > '9') {
            Tcl_DecrRefCount(requests);
            return refuse(ip, GX_CHANNEL, 0);
        }
    }
    /* The real interpreter is required for its registered-channel table.
     * A failed C lookup is not a payload-bearing Tcl command exception.
     */
    channel = Tcl_GetChannel(ip, pipe_name, &mode);
    if (channel == NULL
            || (mode & (TCL_READABLE | TCL_WRITABLE))
                    != (TCL_READABLE | TCL_WRITABLE)
            || Tcl_GetChannelThread(channel) != Tcl_GetCurrentThread()
            || Tcl_GetTopChannel(channel) != channel
            || (type = Tcl_GetChannelType(channel)) == NULL
            || type->typeName == NULL || strcmp(type->typeName, "pipe") != 0
            || !equal_option(channel, "-blocking", "0")
            || !equal_option(channel, "-buffering", "none")
            || !equal_option(channel, "-encoding", "utf-8")
            || !equal_option(channel, "-translation", "lf lf")) {
        Tcl_DecrRefCount(requests);
        return refuse(ip, GX_CHANNEL, 0);
    }
    /* The untransformed native pipe cannot evaluate Tcl or yield here.
     * ScriptJob remains the sole legitimate creator/closer of its map channel.
     */
    character_count = Tcl_GetCharLength(objv[2]);
    if (character_count > GX_PENDING_LIMIT - 1) {
        Tcl_DecrRefCount(requests);
        return refuse(ip, GX_BUSY, 0);
    }
    characters = Tcl_GetUnicodeFromObj(objv[2], &character_count);
    for (index = 0; index < character_count; ++index) {
        if (characters[index] == 0 || characters[index] == '\r'
                || characters[index] == '\n') {
            Tcl_DecrRefCount(requests);
            return refuse(ip, GX_FRAME, 0);
        }
    }
    source = Tcl_GetStringFromObj(objv[2], &source_bytes);
    Tcl_DStringInit(&external);
    Tcl_DStringInit(&framed);
    /* The same Tcl utf-8 encoder as encoding convertto, including non-BMP
     * characters. Internal modified-UTF8 length is not the output byte count.
     */
    (void)Tcl_UtfToExternalDString(utf8, source, source_bytes, &external);
    payload_bytes = Tcl_DStringLength(&external);
    pending = Tcl_OutputBuffered(channel);
    if (pending < 0 || pending > GX_PENDING_LIMIT
            || payload_bytes > GX_PENDING_LIMIT - 1 - pending) {
        code = refuse(ip, GX_BUSY, 0);
    } else {
        Tcl_DStringAppend(&framed, source, source_bytes);
        Tcl_DStringAppend(&framed, "\n", 1);
        /* One attempt only; Tcl owns conversion/buffering/background flush.
         * WriteChars reports encoded output bytes, not source-string bytes.
         */
        written = Tcl_WriteChars(channel, Tcl_DStringValue(&framed),
                Tcl_DStringLength(&framed));
        if (written != payload_bytes + 1 || Tcl_Flush(channel) != TCL_OK) {
            code = refuse(ip, GX_WRITE_FAILED, 1);
        } else {
            Tcl_Obj *result = Tcl_NewDictObj(), *receipt = Tcl_NewDictObj();
            put(receipt, "request_id", objv[1]);
            put(receipt, "accepted", Tcl_NewBooleanObj(1));
            put(receipt, "payload_bytes", Tcl_NewIntObj(payload_bytes));
            put(result, "ok", Tcl_NewBooleanObj(1));
            put(result, "result", receipt);
            Tcl_SetObjResult(ip, result);
            code = TCL_OK;
        }
    }
    Tcl_DStringFree(&framed);
    Tcl_DStringFree(&external);
    Tcl_DecrRefCount(requests);
    /* No Tcl callback/cancel/signal, no diagnostic harvesting or error reset.
     * Caller MUST retire a failed channel after this call completely returns.
     */
    return code;
}

static int
protected_info(ClientData unused, Tcl_Interp *ip, int objc,
        Tcl_Obj *const objv[])
{
    Tcl_Obj *result, *info;
    int major, minor, patch, release;
    (void)unused;
    (void)objv;
    if (objc != 1) {
        return refuse(ip, GX_ARITY, 0);
    }
    result = Tcl_NewDictObj();
    info = Tcl_NewDictObj();
    Tcl_GetVersion(&major, &minor, &patch, &release);
    put(info, "schema", Tcl_NewStringObj("gxtxt.script_job.protected_channel.v1", -1));
    put(info, "private", Tcl_NewBooleanObj(1));
    put(info, "request_owner", Tcl_NewStringObj(GX_REQUESTS, -1));
    put(info, "platform", Tcl_NewStringObj("unix_native_command_pipe", -1));
    put(info, "max_pending_bytes", Tcl_NewIntObj(GX_PENDING_LIMIT));
    put(info, "encoding", Tcl_NewStringObj("utf-8", -1));
    put(info, "appended_lf_bytes", Tcl_NewIntObj(1));
    put(info, "request_id_max_characters", Tcl_NewIntObj(64));
    put(info, "cancellation", Tcl_NewStringObj("post_return_existing_owner", -1));
    put(info, "provider_ack", Tcl_NewBooleanObj(0));
    put(info, "capability_only", Tcl_NewBooleanObj(1));
    put(info, "tcl_header_version", Tcl_NewStringObj(TCL_PATCH_LEVEL, -1));
    put(info, "tcl_runtime_major", Tcl_NewIntObj(major));
    put(info, "tcl_runtime_minor", Tcl_NewIntObj(minor));
    put(info, "tcl_runtime_patch", Tcl_NewIntObj(patch));
    put(info, "tcl_runtime_release", Tcl_NewIntObj(release));
    put(result, "ok", Tcl_NewBooleanObj(1));
    put(result, "result", info);
    Tcl_SetObjResult(ip, result);
    return TCL_OK;
}

static void
release_encoding(ClientData data)
{
    Tcl_FreeEncoding((Tcl_Encoding)data);
}

/* No SafeInit: no safe-interpreter/Script/SDK exposure is supplied. */
int
Gxtxtscriptjobchannel_Init(Tcl_Interp *ip)
{
    Tcl_Encoding utf8;
    Tcl_CmdInfo existing;
    int major, minor, patch, release;
    if (Tcl_InitStubs(ip, "8.6", 0) == NULL) {
        return TCL_ERROR; /* Nonsecret trusted initialization only. */
    }
    Tcl_GetVersion(&major, &minor, &patch, &release);
    if (major != 8 || minor != 6) {
        Tcl_SetObjResult(ip, Tcl_NewStringObj("Protected ScriptJob requires Tcl 8.6.", -1));
        return TCL_ERROR;
    }
    if (Tcl_GetCommandInfo(ip, GX_SEND, &existing)
            || Tcl_GetCommandInfo(ip, GX_INFO, &existing)) {
        Tcl_SetObjResult(ip, Tcl_NewStringObj("Protected ScriptJob command already exists.", -1));
        return TCL_ERROR;
    }
    if (Tcl_FindNamespace(ip, "::GX", NULL, TCL_GLOBAL_ONLY) == NULL
            && Tcl_CreateNamespace(ip, "::GX", NULL, NULL) == NULL) {
        return TCL_ERROR;
    }
    if (Tcl_FindNamespace(ip, "::GX::ScriptJob", NULL, TCL_GLOBAL_ONLY) == NULL
            && Tcl_CreateNamespace(ip, "::GX::ScriptJob", NULL, NULL) == NULL) {
        return TCL_ERROR;
    }
    utf8 = Tcl_GetEncoding(ip, "utf-8");
    if (utf8 == NULL) {
        return TCL_ERROR;
    }
    (void)Tcl_CreateObjCommand(ip, GX_SEND, protected_send,
            (ClientData)utf8, release_encoding);
    (void)Tcl_CreateObjCommand(ip, GX_INFO, protected_info, NULL, NULL);
    if (Tcl_PkgProvide(ip, "gxtxt_script_job_channel", "1.0") != TCL_OK) {
        (void)Tcl_DeleteCommand(ip, GX_INFO);
        (void)Tcl_DeleteCommand(ip, GX_SEND);
        return TCL_ERROR;
    }
    return TCL_OK;
}
