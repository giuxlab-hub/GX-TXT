// SPDX-License-Identifier: GPL-3.0-or-later
// Internal precompiled CORE browser host. No public Tcl/SDK contract is adopted here.
#include <QApplication>
#include <QBuffer>
#include <QCryptographicHash>
#include <QDir>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QFile>
#include <QReadWriteLock>
#include <QWebEngineLoadingInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeDatabase>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSocketNotifier>
#include <QTimer>
#include <QUrl>
#include <QWebEngineCertificateError>
#include <QWebEngineDownloadRequest>
#include <QWebEngineHistory>
#include <QWebEngineFileSystemAccessRequest>
#include <tcl.h>
#include <QWebEnginePage>
#include <QWebEnginePermission>
#include <QWebEngineProfile>
#include <QWebEngineSettings>
#include <QWebEngineUrlRequestInfo>
#include <QWebEngineUrlRequestInterceptor>
#include <QWebEngineUrlRequestJob>
#include <QWebEngineUrlScheme>
#include <QWebEngineUrlSchemeHandler>
#include <QWebEngineView>
#include <QWindow>
#include <cerrno>
#include <csignal>
#include <cmath>
#include <cstdio>
#include <functional>
#include <fcntl.h>
#include <limits>
#include <memory>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __linux__
#include <sys/prctl.h>
#endif

namespace {
constexpr qsizetype frameLimit = 16384;
constexpr qint64 assetLimit = 16 * 1024 * 1024;
constexpr qint64 documentLimit = 4 * 1024 * 1024;
constexpr qint64 packageLimit = 64 * 1024 * 1024;
bool tclWire = false;
const QString schemeName = QStringLiteral("gxtxt-doc");
const QRegularExpression identifier(QStringLiteral("^[A-Za-z0-9._:-]{1,256}$"));
const QRegularExpression requestIdentifier(QStringLiteral("^[A-Za-z0-9._-]{1,64}$"));
const QRegularExpression digestPattern(QStringLiteral("^[0-9a-f]{64}$"));

struct Failure { QString code; QString message; };
[[noreturn]] void fail(const char *code, const char *message) {
    throw Failure{QString::fromLatin1(code), QString::fromLatin1(message)};
}
void exactKeys(const QJsonObject &object, const QStringList &keys) {
    if (object.size() != keys.size()) fail("INVALID_ARGUMENT", "Unexpected command fields");
    for (const auto &key : keys) if (!object.contains(key)) fail("INVALID_ARGUMENT", "Missing command field");
}
QString text(const QJsonObject &object, const QString &key, qsizetype maximum) {
    if (!object.value(key).isString()) fail("INVALID_ARGUMENT", "Expected bounded text");
    const auto value = object.value(key).toString();
    if (value.isEmpty() || value.contains(QChar(0)) || value.toUtf8().size() > maximum)
        fail("INVALID_ARGUMENT", "Text is empty, oversized or contains NUL");
    return value;
}
int integer(const QJsonObject &object, const QString &key, int minimum, int maximum) {
    const auto value = object.value(key);
    if (!value.isDouble()) fail("INVALID_ARGUMENT", "Expected integer");
    const double number = value.toDouble();
    if (!std::isfinite(number) || number != std::floor(number) || number < minimum || number > maximum)
        fail("INVALID_ARGUMENT", "Integer is outside its admitted range");
    return static_cast<int>(number);
}
QString relativePath(const QString &value) {
    if (value.isEmpty() || value.toUtf8().size() > 2048 || value.startsWith('/') ||
        value.contains('\\') || value.contains('%') || value.contains(':') || value.contains(QChar(0)))
        fail("ASSET_DENIED", "Only unambiguous package-relative paths are admitted");
    const auto parts = value.split('/');
    for (const auto &part : parts) {
        if (part.isEmpty() || part == "." || part == "..")
            fail("ASSET_DENIED", "Package-relative path contains an unsafe component");
    }
    return value;
}
struct Command {
    QString op, request, root, relative, sha, source, media, target;
    int generation = 0, width = 0, height = 0, percent = 100;
    bool visible = true;
};
Command parse(const QByteArray &line) {
    if (line.size() > frameLimit) fail("FRAME_TOO_LARGE", "Control frame exceeds 16 KiB");
    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(line, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        fail("INVALID_JSON", "Control frame must be one JSON object");
    const auto object = document.object();
    Command result;
    result.op = text(object, "op", 32);
    result.request = text(object, "request_id", 64);
    if (!requestIdentifier.match(result.request).hasMatch()) fail("INVALID_ARGUMENT", "Invalid request identity");
    if (result.op == "load") {
        exactKeys(object, {"op", "request_id", "generation", "root", "relative", "sha256", "source_id", "media"});
        result.generation = integer(object, "generation", 1, std::numeric_limits<int>::max());
        result.root = text(object, "root", 4096);
        if (!QDir::isAbsolutePath(result.root)) fail("ASSET_DENIED", "Asset root must be absolute");
        result.relative = relativePath(text(object, "relative", 2048));
        result.sha = text(object, "sha256", 64);
        result.source = text(object, "source_id", 256);
        result.media = text(object, "media", 16);
        if (!digestPattern.match(result.sha).hasMatch() || !identifier.match(result.source).hasMatch())
            fail("INVALID_ARGUMENT", "Invalid source digest or identity");
        if (result.media != "offline" && result.media != "youtube") fail("INVALID_ARGUMENT", "Unknown media policy");
    } else if (result.op == "resize") {
        exactKeys(object, {"op", "request_id", "width", "height"});
        result.width = integer(object, "width", 1, 16384);
        result.height = integer(object, "height", 1, 16384);
    } else if (result.op == "visible") {
        exactKeys(object, {"op", "request_id", "value"});
        if (!object.value("value").isBool()) fail("INVALID_ARGUMENT", "Visibility requires boolean");
        result.visible = object.value("value").toBool();
    } else if (result.op == "zoom") {
        exactKeys(object, {"op", "request_id", "percent"});
        result.percent = integer(object, "percent", 50, 300);
        if (result.percent % 25) fail("INVALID_ARGUMENT", "Zoom uses 25 percent increments");
    } else if (result.op == "find") {
        exactKeys(object, {"op", "request_id", "text"});
        if (!object.value("text").isString()) fail("INVALID_ARGUMENT", "Find requires text");
        result.target = object.value("text").toString();
        if (result.target.contains(QChar(0)) || result.target.toUtf8().size() > 1024) fail("INVALID_ARGUMENT", "Find text is oversized or contains NUL");
    } else if (result.op == "relative") {
        exactKeys(object, {"op", "request_id", "target"});
        result.target = text(object, "target", 2048);
        QUrl target(result.target, QUrl::StrictMode);
        if (!target.isValid() || !target.isRelative() || target.hasQuery() ||
            (target.path().isEmpty() && target.fragment().isEmpty()))
            fail("NAVIGATION_DENIED", "Expected local relative navigation");
        if (!target.path().isEmpty()) relativePath(target.path(QUrl::FullyDecoded));
    } else if (QStringList{"back", "forward", "home", "reload", "stop", "inspect", "close", "focus"}.contains(result.op)) {
        exactKeys(object, {"op", "request_id"});
    } else fail("UNKNOWN_OPERATION", "Unknown native HTML operation");
    return result;
}

class AssetRoot {
    int fd = -1;
    QHash<QString, qint64> served;
    qint64 total = 0;
public:
    explicit AssetRoot(const QString &root) {
        const QFileInfo info(root);
        if (!info.isDir() || info.isSymLink() || info.canonicalFilePath() != QDir::cleanPath(root))
            fail("ASSET_DENIED", "Asset root is missing, linked or noncanonical");
        int current = ::open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
        if (current < 0) fail("ASSET_DENIED", "Asset scope could not be opened");
        for (const auto &component : root.split('/', Qt::SkipEmptyParts)) {
            const auto name = QFile::encodeName(component);
            const int next = ::openat(current, name.constData(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
            ::close(current); current = next;
            if (current < 0) fail("ASSET_DENIED", "Asset root component is missing or linked");
        }
        fd = current;
    }
    ~AssetRoot() { if (fd >= 0) ::close(fd); }
    AssetRoot(const AssetRoot &) = delete;
    QByteArray read(const QString &relative, qint64 maximum = assetLimit) {
        const auto parts = relativePath(relative).split('/');
        int current = ::dup(fd);
        if (current < 0) fail("ASSET_UNAVAILABLE", "Asset scope cannot be read");
        for (qsizetype i = 0; i < parts.size(); ++i) {
            const bool last = i + 1 == parts.size();
            const auto name = QFile::encodeName(parts[i]);
            int next = ::openat(current, name.constData(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK | (last ? 0 : O_DIRECTORY));
            ::close(current); current = next;
            if (current < 0) fail("ASSET_DENIED", "Asset is missing or outside admitted ordinary files");
        }
        struct stat before{}, after{};
        if (::fstat(current, &before) || !S_ISREG(before.st_mode) || before.st_size < 0 || before.st_size > maximum) {
            ::close(current); fail("ASSET_DENIED", "Asset type or size is not admitted");
        }
        const qint64 old = served.value(relative, 0);
        if ((served.size() >= 4096 && !served.contains(relative)) || total - old + before.st_size > packageLimit) {
            ::close(current); fail("ASSET_BUDGET", "Package resource budget exceeded");
        }
        QByteArray bytes;
        bytes.resize(static_cast<qsizetype>(before.st_size));
        qsizetype offset = 0;
        while (offset < bytes.size()) {
            const ssize_t count = ::read(current, bytes.data() + offset, static_cast<size_t>(bytes.size() - offset));
            if (count < 0 && errno == EINTR) continue;
            if (count <= 0) { ::close(current); fail("SOURCE_CHANGED", "Asset changed while being read"); }
            offset += count;
        }
        const bool changed = ::fstat(current, &after) || before.st_size != after.st_size ||
            before.st_mtim.tv_sec != after.st_mtim.tv_sec || before.st_mtim.tv_nsec != after.st_mtim.tv_nsec ||
            before.st_ctim.tv_sec != after.st_ctim.tv_sec || before.st_ctim.tv_nsec != after.st_ctim.tv_nsec;
        ::close(current);
        if (changed) fail("SOURCE_CHANGED", "Asset changed while being read");
        total += before.st_size - old;
        served.insert(relative, before.st_size);
        return bytes;
    }
};

bool mediaHost(const QString &host) {
    for (const QString &base : {QStringLiteral("youtube.com"), QStringLiteral("youtube-nocookie.com"),
                              QStringLiteral("ytimg.com"), QStringLiteral("googlevideo.com"), QStringLiteral("ggpht.com")})
        if (host == base || host.endsWith('.' + base)) return true;
    return false;
}
bool mediaUrl(const QUrl &url) {
    return url.isValid() && url.scheme() == "https" && url.userInfo().isEmpty() &&
        (url.port(-1) == -1 || url.port() == 443) && mediaHost(url.host().toLower());
}
class Policy {
    mutable QReadWriteLock lock;
    QString nonce;
    bool youtube = false;
public:
    void reset(const QString &nextNonce, bool nextYoutube) { QWriteLocker guard(&lock); nonce = nextNonce; youtube = nextYoutube; }
    QString host() const { QReadLocker guard(&lock); return nonce; }
    bool mediaEnabled() const { QReadLocker guard(&lock); return youtube; }
    bool local(const QUrl &url) const {
        QReadLocker guard(&lock);
        return !nonce.isEmpty() && url.scheme() == schemeName && url.host() == nonce && url.userInfo().isEmpty() && url.port(-1) == -1;
    }
};
class Interceptor final : public QWebEngineUrlRequestInterceptor {
    const Policy &policy;
public:
    Interceptor(const Policy &p, QObject *parent) : QWebEngineUrlRequestInterceptor(parent), policy(p) {}
    void interceptRequest(QWebEngineUrlRequestInfo &info) override {
        const auto url = info.requestUrl();
        const auto origin = info.initiator();
        const bool ownInitiator = origin.isEmpty() || policy.local(origin);
        const auto resource = info.resourceType();
        if (resource == QWebEngineUrlRequestInfo::ResourceTypeWorker || resource == QWebEngineUrlRequestInfo::ResourceTypeSharedWorker ||
            resource == QWebEngineUrlRequestInfo::ResourceTypeServiceWorker || resource == QWebEngineUrlRequestInfo::ResourceTypeWebSocket ||
            resource == QWebEngineUrlRequestInfo::ResourceTypePluginResource) { info.block(true); return; }
        const bool embeddedImage = resource == QWebEngineUrlRequestInfo::ResourceTypeImage || resource == QWebEngineUrlRequestInfo::ResourceTypeFontResource;
        if (url.scheme() == "data" && embeddedImage && ownInitiator && url.toEncoded().size() <= 2 * 1024 * 1024) { info.block(false); return; }
        if (url.scheme() == "blob" && embeddedImage && ownInitiator && policy.local(QUrl(url.path()))) { info.block(false); return; }
        if (policy.local(url)) { info.block(!ownInitiator); return; }
        // No general network, local file, worker, WebSocket or request bridge.
        const auto type = info.resourceType();
        const bool passive = type == QWebEngineUrlRequestInfo::ResourceTypeSubFrame ||
            type == QWebEngineUrlRequestInfo::ResourceTypeScript || type == QWebEngineUrlRequestInfo::ResourceTypeStylesheet ||
            type == QWebEngineUrlRequestInfo::ResourceTypeImage || type == QWebEngineUrlRequestInfo::ResourceTypeFontResource ||
            type == QWebEngineUrlRequestInfo::ResourceTypeMedia || type == QWebEngineUrlRequestInfo::ResourceTypeXhr;
        const bool trustedOrigin = ownInitiator || mediaUrl(origin);
        const bool allowed = policy.mediaEnabled() && passive && trustedOrigin && mediaUrl(url) && info.requestMethod() == "GET";
        info.block(!allowed);
        // Client-identification policy is intentionally pending independent review.
        // No fabricated Referer is injected; actual YouTube playback is unverified.
    }
};

bool webAsset(const QString &relative) {
    static const QStringList extensions{"html", "htm", "css", "js", "mjs", "json", "txt", "svg", "png", "jpg", "jpeg", "gif", "webp", "avif", "ico", "bmp", "woff", "woff2", "ttf", "otf", "mp3", "mp4", "m4v", "webm", "ogg", "oga", "ogv", "wav", "flac", "vtt"};
    for (const auto &component : relative.split('/')) if (component.startsWith('.')) return false;
    return extensions.contains(QFileInfo(relative).suffix().toLower());
}

class SchemeHandler final : public QWebEngineUrlSchemeHandler {
public:
    std::shared_ptr<AssetRoot> root;
    Policy &policy;
    QString mainRelative, mainSha;
    std::function<void(const QString &, const QUrl &)> problem;
    SchemeHandler(Policy &p, QObject *parent) : QWebEngineUrlSchemeHandler(parent), policy(p) {}
    void requestStarted(QWebEngineUrlRequestJob *job) override {
        try {
            if (!root || !policy.local(job->requestUrl()) || job->requestMethod() != "GET" ||
                (!job->initiator().isEmpty() && !policy.local(job->initiator())))
                fail("ASSET_DENIED", "Resource is outside the owning presentation");
            const auto url = job->requestUrl();
            if (url.hasQuery()) fail("ASSET_DENIED", "Local asset queries are unsupported");
            const auto path = url.path(QUrl::FullyDecoded);
            if (!path.startsWith('/')) fail("ASSET_DENIED", "Malformed scoped resource");
            const auto relative = relativePath(path.mid(1));
            if (!webAsset(relative)) fail("ASSET_DENIED", "Asset type is outside the public web package");
            const auto bytes = root->read(relative, relative == mainRelative ? documentLimit : assetLimit);
            if (relative == mainRelative && QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex() != mainSha.toLatin1())
                fail("SOURCE_CHANGED", "Bound HTML source changed");
            auto *buffer = new QBuffer(job);
            buffer->setData(bytes); buffer->open(QIODevice::ReadOnly);
            auto mime = QMimeDatabase().mimeTypeForFile(relative, QMimeDatabase::MatchExtension).name().toUtf8();
            if (mime.isEmpty() || mime == "application/octet-stream") mime = "text/plain";
            job->reply(mime, buffer);
        } catch (const Failure &failure) {
            job->fail(QWebEngineUrlRequestJob::RequestDenied);
            if (problem && policy.local(job->requestUrl())) problem(failure.code, job->requestUrl());
        }
    }
};

class Page final : public QWebEnginePage {
public:
    Policy &policy;
    std::function<bool()> activated;
    std::function<void(const QUrl &)> external;
    std::function<bool(const QUrl &)> localNavigation;
    Page(QWebEngineProfile *profile, Policy &p, QObject *parent) : QWebEnginePage(profile, parent), policy(p) {}
protected:
    bool acceptNavigationRequest(const QUrl &url, NavigationType type, bool main) override {
        if (policy.local(url)) {
            try {
                if (url.toEncoded().size() > 4096 || url.hasQuery()) return false;
                relativePath(url.path(QUrl::FullyDecoded).mid(1));
                return !main || !localNavigation || localNavigation(url);
            } catch (const Failure &) { return false; }
        }
        if (!main) return policy.mediaEnabled() && mediaUrl(url);
        if (type == NavigationTypeLinkClicked && activated && activated() && external &&
            (url.scheme() == "https" || url.scheme() == "http") && url.userInfo().isEmpty() && url.toEncoded().size() <= 2048)
            external(url);
        return false;
    }
    QWebEnginePage *createWindow(WebWindowType) override { return nullptr; }
    QStringList chooseFiles(FileSelectionMode, const QStringList &, const QStringList &) override { return {}; }
    void javaScriptAlert(const QUrl &, const QString &) override {}
    bool javaScriptConfirm(const QUrl &, const QString &) override { return false; }
    bool javaScriptPrompt(const QUrl &, const QString &, const QString &, QString *) override { return false; }
    void javaScriptConsoleMessage(JavaScriptConsoleMessageLevel, const QString &, int, const QString &) override {}
};

struct Activation {
    int generation = 0, navigation = 0;
    bool ready = false;
    void clear() { ready = false; }
    void grant(int sourceGeneration, int navigationSequence) { generation = sourceGeneration; navigation = navigationSequence; ready = true; }
    bool consume(int sourceGeneration, int navigationSequence, bool fresh) {
        const bool result = ready && generation == sourceGeneration && navigation == navigationSequence && fresh;
        clear(); return result;
    }
};

// Qt6.8 loading notifications have no navigation ID. Keep one same-source
// navigation in flight, and require its exact source URL and a start notification
// before accepting a terminal notification. Source replacement has a fresh origin.
struct Navigation {
    int sequence = 0, generation = 0;
    QString request;
    QUrl expected;
    bool active = false, started = false, stopping = false, timedOut = false;
    void begin(const QString &nextRequest, const QUrl &url, int nextGeneration, bool replacement = false) {
        if (active && !replacement) fail("NAVIGATION_BUSY", "Wait for the current navigation to finish or stop");
        ++sequence; generation = nextGeneration; request = nextRequest; expected = url;
        active = true; started = false; stopping = false; timedOut = false;
    }
    bool stopRequiresRetirement() { stopping = true; return active && !started; }
    bool drainPending(int expectedSequence) const { return active && sequence == expectedSequence; }
    bool observe(const QUrl &url, int observedGeneration, QWebEngineLoadingInfo::LoadStatus status) {
        if (!active || observedGeneration != generation || url != expected) return false;
        if (status == QWebEngineLoadingInfo::LoadStartedStatus) {
            if (started) return false;
            started = true; return true;
        }
        if (!started) return false;
        active = false; return true;
    }
};

QByteArray tclDictionary(const QJsonObject &object) {
    // Existing Tcl's list encoder only: no interpreter is created or evaluated.
    Tcl_DString result; Tcl_DStringInit(&result);
    for (auto item = object.begin(); item != object.end(); ++item) {
        const auto key = item.key().toUtf8();
        QString value;
        if (item.value().isBool()) value = item.value().toBool() ? QStringLiteral("1") : QStringLiteral("0");
        else if (item.value().isDouble()) value = QString::number(item.value().toDouble(), 'g', 17);
        else value = item.value().toString();
        const auto bytes = value.toUtf8();
        Tcl_DStringAppendElement(&result, key.constData()); Tcl_DStringAppendElement(&result, bytes.constData());
    }
    const QByteArray bytes(Tcl_DStringValue(&result), Tcl_DStringLength(&result)); Tcl_DStringFree(&result); return bytes;
}
QByteArray receiptFrame(const QJsonObject &object) {
    return tclWire ? QByteArray("GXHTML1 ") + tclDictionary(object) + '\n' : QJsonDocument(object).toJson(QJsonDocument::Compact) + '\n';
}

class Runtime final : public QObject {
    Policy policy;
    QWebEngineProfile profile;
    SchemeHandler handler;
    Interceptor interceptor;
    Page page;
    QWebEngineView view;
    std::unique_ptr<QWindow> foreign;
    QSocketNotifier input{STDIN_FILENO, QSocketNotifier::Read};
    QSocketNotifier output{STDOUT_FILENO, QSocketNotifier::Write};
    QByteArray pendingInput, pendingOutput;
    QString state = "empty", source, sha, request, loadRequest;
    QUrl home;
    int generation = 0;
    Navigation navigation;
    bool clearHistoryForSource = false, requestedVisible = true;
    QElapsedTimer gesture;
    Activation activation;
    bool closing = false;
    QTimer loadTimeout;

    void flushOutput() {
        while (!pendingOutput.isEmpty()) {
            const auto count = ::write(STDOUT_FILENO, pendingOutput.constData(), static_cast<size_t>(pendingOutput.size()));
            if (count < 0 && errno == EINTR) continue;
            if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) break;
            if (count <= 0) { QCoreApplication::exit(3); break; }
            pendingOutput.remove(0, count);
        }
        output.setEnabled(!pendingOutput.isEmpty());
    }
    void emitReceipt(const QString &event, const QString &code = {}, const QString &url = {}, const QString &replyRequest = {}) {
        QJsonObject object{{"schema", "gxtxt.html_runtime.v1"}, {"event", event}, {"state", state},
            {"generation", generation}, {"navigation_sequence", navigation.sequence}, {"navigation_pending", navigation.active}, {"request_id", replyRequest.isNull() ? request : replyRequest}, {"source_id", source}, {"source_sha256", sha},
            {"can_back", page.history()->canGoBack() && policy.local(page.history()->backItem().url())}, {"can_forward", page.history()->canGoForward() && policy.local(page.history()->forwardItem().url())},
            {"zoom_percent", qRound(view.zoomFactor() * 100)}};
        if (policy.local(page.url())) object.insert("relative_url", page.url().path(QUrl::FullyEncoded) + (page.url().hasFragment() ? '#' + page.url().fragment(QUrl::FullyEncoded) : QString()));
        if (!code.isEmpty()) object.insert("code", code);
        if (!url.isEmpty()) object.insert("url", url);
        const auto frame = receiptFrame(object);
        if (pendingOutput.size() + frame.size() > 65536) { QCoreApplication::exit(3); return; }
        pendingOutput += frame; flushOutput();
    }
    void shutdown() {
        if (closing) return;
        closing = true; activation.clear(); state = "closed"; navigation.active = false; input.setEnabled(false); loadTimeout.stop();
        page.triggerAction(QWebEnginePage::Stop); view.hide(); emitReceipt("closed");
        QTimer::singleShot(0, qApp, [] { QCoreApplication::quit(); });
    }
    void beginNavigation(const QString &nextRequest, const QUrl &url, bool replacement = false) {
        activation.clear();
        navigation.begin(nextRequest, url, generation, replacement);
        loadTimeout.start(); // Includes the interval before Qt emits LoadStarted.
    }
    void guardDrain() {
        const int sequence = navigation.sequence;
        QTimer::singleShot(500, this, [this, sequence] {
            if (!closing && navigation.drainPending(sequence)) {
                emitReceipt("error", "NAVIGATION_DRAIN_TIMEOUT", {}, navigation.request); shutdown();
            }
        });
    }
    void execute(const Command &command) {
        if (command.op == "load") {
            if (command.generation <= generation) fail("STALE_GENERATION", "Load generation must increase");
            auto candidate = std::make_shared<AssetRoot>(command.root);
            const auto bytes = candidate->read(command.relative, documentLimit);
            if (QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex() != command.sha.toLatin1())
                fail("SOURCE_CHANGED", "HTML source digest does not match admitted owner");
            const auto extension = QFileInfo(command.relative).suffix().toLower();
            if (extension != "html" && extension != "htm") fail("SOURCE_KIND", "HTML presentation requires HTML source");
            if (state == "loading") emitReceipt("cancelled", "CANCELLED", {}, loadRequest);
            page.triggerAction(QWebEnginePage::Stop);
            generation = command.generation; request = command.request; loadRequest = command.request; source = command.source; sha = command.sha;
            const auto nonce = QStringLiteral("%1%2")
                .arg(QRandomGenerator::system()->generate64(), 16, 16, QLatin1Char('0'))
                .arg(QRandomGenerator::system()->generate64(), 16, 16, QLatin1Char('0'));
            policy.reset(nonce, command.media == "youtube"); handler.root = std::move(candidate);
            handler.mainRelative = command.relative; handler.mainSha = command.sha;
            page.settings()->setAttribute(QWebEngineSettings::LocalContentCanAccessRemoteUrls, policy.mediaEnabled());
            home = QUrl(); home.setScheme(schemeName); home.setHost(nonce); home.setPath('/' + command.relative);
            beginNavigation(command.request, home, true);
            clearHistoryForSource = true; view.hide();
            state = "loading"; emitReceipt("accepted");
            if (policy.mediaEnabled()) emitReceipt("policy_notice", "YOUTUBE_PLAYBACK_UNVERIFIED");
            page.load(home); loadTimeout.start(); return;
        }
        request = command.request;
        if (command.op == "close") { shutdown(); return; }
        if (command.op == "resize") view.resize(command.width, command.height);
        else if (command.op == "visible") { if (!command.visible) activation.clear(); requestedVisible = command.visible; view.setVisible(requestedVisible && state == "ready"); }
        else if (command.op == "focus") view.setFocus(Qt::OtherFocusReason);
        else if (command.op == "zoom") view.setZoomFactor(command.percent / 100.0);
        else if (command.op == "find") page.findText(command.target);
        else if (command.op != "inspect") {
            if (home.isEmpty()) fail("UNBOUND", "Bind HTML before navigation");
            if (command.op == "stop") {
                activation.clear();
                if (navigation.active) {
                    const bool retire = navigation.stopRequiresRetirement();
                    page.triggerAction(QWebEnginePage::Stop);
                    if (retire) { emitReceipt("error", "CANCELLED", {}, navigation.request); shutdown(); return; }
                    guardDrain();
                }
                // A started Stop drains or closes this owned host within500ms.
            } else {
                QUrl destination;
                if (command.op == "back") destination = page.history()->backItem().url();
                else if (command.op == "forward") destination = page.history()->forwardItem().url();
                else if (command.op == "reload") destination = page.url();
                else if (command.op == "home") destination = home;
                else destination = page.url().resolved(QUrl(command.target, QUrl::StrictMode));
                if (!policy.local(destination)) fail("NAVIGATION_DENIED", "Navigation left package origin");
                relativePath(destination.path(QUrl::FullyDecoded).mid(1));
                if (navigation.active) fail("NAVIGATION_BUSY", "Wait for current navigation to drain");
                const bool sameDocument = command.op != "reload" && destination.adjusted(QUrl::RemoveFragment) == page.url().adjusted(QUrl::RemoveFragment);
                if (sameDocument) {
                    activation.clear();
                    if (destination != page.url()) page.load(destination);
                    emitReceipt("accepted"); return; // Anchors/no-ops need not emit LoadStarted.
                }
                beginNavigation(command.request, destination);
                loadRequest = command.request;
                if (command.op == "back") page.triggerAction(QWebEnginePage::Back);
                else if (command.op == "forward") page.triggerAction(QWebEnginePage::Forward);
                else if (command.op == "reload") page.triggerAction(QWebEnginePage::Reload);
                else page.load(destination);
            }
        }
        emitReceipt("accepted");
    }
    void readable() {
        char buffer[8192];
        for (;;) {
            const auto count = ::read(STDIN_FILENO, buffer, sizeof buffer);
            if (count < 0 && errno == EINTR) continue;
            if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return;
            if (count <= 0) { shutdown(); return; }
            pendingInput.append(buffer, count);
            if (pendingInput.size() > frameLimit * 2) { emitReceipt("error", "FRAME_TOO_LARGE"); shutdown(); return; }
            qsizetype newline;
            while ((newline = pendingInput.indexOf('\n')) >= 0) {
                const auto line = pendingInput.left(newline); pendingInput.remove(0, newline + 1);
                QString incomingRequest = QStringLiteral("");
                if (line.size() <= frameLimit) {
                    const auto object = QJsonDocument::fromJson(line).object();
                    const auto candidate = object.value("request_id").toString();
                    if (requestIdentifier.match(candidate).hasMatch()) incomingRequest = candidate;
                }
                try { const auto command = parse(line); incomingRequest = command.request; execute(command); }
                catch (const Failure &failure) { emitReceipt("error", failure.code, {}, incomingRequest); }
                if (closing) return;
            }
            if (pendingInput.size() > frameLimit) { emitReceipt("error", "FRAME_TOO_LARGE"); shutdown(); return; }
        }
    }
    bool eventFilter(QObject *object, QEvent *event) override {
        auto *widget = qobject_cast<QWidget *>(object);
        if (widget && (widget == &view || view.isAncestorOf(widget)) && event->spontaneous() &&
            (event->type() == QEvent::MouseButtonRelease || event->type() == QEvent::KeyRelease)) {
            if (state == "ready") { gesture.start(); activation.grant(generation, navigation.sequence); }
        }
        return false;
    }
public:
    explicit Runtime(quintptr parent) : profile(this), handler(policy, this), interceptor(policy, this), page(&profile, policy, this) {
        profile.setHttpCacheType(QWebEngineProfile::MemoryHttpCache);
        profile.setPersistentCookiesPolicy(QWebEngineProfile::NoPersistentCookies);
        profile.setUrlRequestInterceptor(&interceptor); profile.installUrlSchemeHandler(schemeName.toLatin1(), &handler);
        view.setPage(&page); view.setContextMenuPolicy(Qt::NoContextMenu);
        auto *settings = page.settings();
        settings->setAttribute(QWebEngineSettings::JavascriptEnabled, true);
        for (const auto setting : {QWebEngineSettings::JavascriptCanOpenWindows, QWebEngineSettings::JavascriptCanAccessClipboard,
             QWebEngineSettings::JavascriptCanPaste, QWebEngineSettings::LocalContentCanAccessFileUrls,
             QWebEngineSettings::LocalContentCanAccessRemoteUrls, QWebEngineSettings::LocalStorageEnabled,
             QWebEngineSettings::PluginsEnabled, QWebEngineSettings::FullScreenSupportEnabled,
             QWebEngineSettings::ScreenCaptureEnabled, QWebEngineSettings::PdfViewerEnabled}) settings->setAttribute(setting, false);
        settings->setAttribute(QWebEngineSettings::PlaybackRequiresUserGesture, true);
        settings->setUnknownUrlSchemePolicy(QWebEngineSettings::DisallowUnknownUrlSchemes);
        connect(&profile, &QWebEngineProfile::downloadRequested, this, [](QWebEngineDownloadRequest *download) { download->cancel(); });
        connect(&page, &QWebEnginePage::fileSystemAccessRequested, this, [](QWebEngineFileSystemAccessRequest access) { access.reject(); });
        connect(&page, &QWebEnginePage::permissionRequested, this, [](QWebEnginePermission permission) { permission.deny(); });
        connect(&page, &QWebEnginePage::certificateError, this, [](QWebEngineCertificateError error) { error.rejectCertificate(); });
        connect(&page, &QWebEnginePage::renderProcessTerminated, this, [this](QWebEnginePage::RenderProcessTerminationStatus, int) {
            if (closing) return;
            activation.clear(); state = "unavailable"; navigation.active = false; view.hide(); loadTimeout.stop(); emitReceipt("error", "RENDERER_EXITED", {}, loadRequest);
        });
        connect(&page, &QWebEnginePage::urlChanged, this, [this](const QUrl &url) {
            if (!closing && policy.local(url)) emitReceipt("location_changed");
        });
        connect(&page, &QWebEnginePage::loadingChanged, this, [this](const QWebEngineLoadingInfo &info) {
            if (closing || !policy.local(info.url()) || !navigation.observe(info.url(), generation, info.status())) return;
            if (info.status() == QWebEngineLoadingInfo::LoadStartedStatus) {
                state = "loading"; loadTimeout.start(); emitReceipt("loading", {}, {}, navigation.request);
            } else {
                loadTimeout.stop();
                const bool ok = info.status() == QWebEngineLoadingInfo::LoadSucceededStatus && !navigation.stopping && !navigation.timedOut;
                state = ok ? "ready" : "unavailable";
                view.setVisible(ok && requestedVisible);
                if (clearHistoryForSource) { page.history()->clear(); clearHistoryForSource = false; }
                const QString code = navigation.timedOut ? QStringLiteral("LOAD_TIMEOUT") :
                    navigation.stopping || info.status() == QWebEngineLoadingInfo::LoadStoppedStatus ? QStringLiteral("CANCELLED") : QStringLiteral("LOAD_FAILED");
                emitReceipt(ok ? "ready" : "error", ok ? QString() : code, {}, navigation.request);
            }
        });
        loadTimeout.setInterval(30000); loadTimeout.setSingleShot(true);
        connect(&loadTimeout, &QTimer::timeout, this, [this] { activation.clear(); navigation.timedOut = true; page.triggerAction(QWebEnginePage::Stop); state = "unavailable"; view.hide(); emitReceipt("error", "LOAD_TIMEOUT", {}, navigation.request); guardDrain(); });
        handler.problem = [this](const QString &code, const QUrl &origin) {
            if (!closing && policy.local(origin)) emitReceipt("asset_error", code, {}, navigation.request);
        };
        page.localNavigation = [this](const QUrl &url) {
            if (navigation.active) return !navigation.started && url == navigation.expected;
            if (url.adjusted(QUrl::RemoveFragment) == page.url().adjusted(QUrl::RemoveFragment) && url != page.url()) { activation.clear(); return true; }
            beginNavigation(QStringLiteral(""), url); loadRequest = QStringLiteral("");
            return true;
        };
        page.activated = [this] { return activation.consume(generation, navigation.sequence, gesture.isValid() && gesture.elapsed() <= 1000); };
        page.external = [this](const QUrl &url) { emitReceipt("external_link_requested", {}, QString::fromUtf8(url.toEncoded())); };
        connect(&input, &QSocketNotifier::activated, this, [this] { readable(); });
        connect(&output, &QSocketNotifier::activated, this, [this] { flushOutput(); }); output.setEnabled(false);
        qApp->installEventFilter(this);
        foreign.reset(QWindow::fromWinId(static_cast<WId>(parent)));
        if (!foreign) fail("PLATFORM_UNSUPPORTED", "Foreign parent window is unsupported");
        view.setAttribute(Qt::WA_NativeWindow); view.setWindowFlag(Qt::FramelessWindowHint);
        view.winId(); view.windowHandle()->setParent(foreign.get()); view.resize(800, 600); view.show();
        emitReceipt("started");
    }
    ~Runtime() override { view.hide(); view.setPage(nullptr); }
};

QJsonObject errorObject(const Failure &failure) { return {{"ok", false}, {"code", failure.code}, {"message", failure.message}}; }
void writeJson(const QJsonObject &object) {
    const auto bytes = receiptFrame(object);
    std::fwrite(bytes.constData(), 1, static_cast<size_t>(bytes.size()), stdout); std::fflush(stdout);
}
}

int main(int argc, char **argv) {
    // Policy/parser checks intentionally use QCoreApplication: no GUI connection.
    if (argc >= 2 && (QByteArray(argv[1]) == "--check-control" || QByteArray(argv[1]) == "--check-source" || QByteArray(argv[1]) == "--probe" || QByteArray(argv[1]) == "--probe-tcl" || QByteArray(argv[1]) == "--check-navigation")) {
        QCoreApplication app(argc, argv);
        try {
            if (app.arguments()[1] == "--check-navigation") {
                if (argc != 2) fail("INVALID_ARGUMENT", "Navigation check takes no arguments");
                Navigation tracker; const QUrl first("gxtxt-doc://source1/index.html"), second("gxtxt-doc://source1/next.html"), replacement("gxtxt-doc://source2/index.html");
                int checked = 0;
                auto expect = [&checked](bool condition) { if (!condition) fail("STATE_CHECK_FAILED", "Native navigation state invariant failed"); ++checked; };
                tracker.begin("prestart", first, 1);
                expect(tracker.stopRequiresRetirement()); expect(tracker.drainPending(tracker.sequence));
                tracker.active = false; expect(!tracker.drainPending(tracker.sequence));
                tracker.begin("first", first, 1);
                expect(!tracker.observe(first, 1, QWebEngineLoadingInfo::LoadStoppedStatus));
                expect(tracker.observe(first, 1, QWebEngineLoadingInfo::LoadStartedStatus));
                bool busy = false; try { tracker.begin("second", second, 1); } catch (const Failure &error) { busy = error.code == "NAVIGATION_BUSY"; } expect(busy);
                tracker.stopping = true; expect(tracker.active && tracker.request == "first");
                expect(!tracker.observe(second, 1, QWebEngineLoadingInfo::LoadStoppedStatus));
                expect(tracker.observe(first, 1, QWebEngineLoadingInfo::LoadStoppedStatus));
                tracker.begin("second", second, 1);
                expect(!tracker.observe(first, 1, QWebEngineLoadingInfo::LoadStoppedStatus));
                expect(!tracker.observe(second, 1, QWebEngineLoadingInfo::LoadSucceededStatus));
                expect(tracker.observe(second, 1, QWebEngineLoadingInfo::LoadStartedStatus));
                tracker.begin("replacement", replacement, 2, true);
                expect(!tracker.observe(second, 1, QWebEngineLoadingInfo::LoadFailedStatus));
                expect(tracker.observe(replacement, 2, QWebEngineLoadingInfo::LoadStartedStatus));
                expect(tracker.observe(replacement, 2, QWebEngineLoadingInfo::LoadSucceededStatus));
                expect(!tracker.active && tracker.request == "replacement" && tracker.sequence == 4);
                Activation permission;
                permission.grant(1, 1); expect(!permission.consume(2, 1, true));
                permission.grant(1, 1); expect(!permission.consume(1, 2, true));
                permission.grant(1, 1); expect(!permission.consume(1, 1, false));
                permission.grant(1, 1); permission.clear(); expect(!permission.consume(1, 1, true));
                permission.grant(2, 4); expect(permission.consume(2, 4, true)); expect(!permission.consume(2, 4, true));
                expect(webAsset("assets/diagram.svg")); expect(webAsset("app.js")); expect(!webAsset("api/private.tcl")); expect(!webAsset("module.ini")); expect(!webAsset(".git/public.html"));
                Policy origins; origins.reset("source1", false); expect(origins.local(first));
                origins.reset("source2", false); expect(!origins.local(first)); expect(origins.local(replacement));
                writeJson({{"ok", true}, {"checks", checked}, {"gui_started", false}});
            } else if (app.arguments()[1] == "--probe-tcl") {
                if (argc != 2) fail("INVALID_ARGUMENT", "Probe takes no arguments");
                QFile executable(QCoreApplication::applicationFilePath());
                if (!executable.open(QIODevice::ReadOnly)) fail("RUNTIME_UNAVAILABLE", "Cannot fingerprint prebuilt runtime");
                QCryptographicHash hash(QCryptographicHash::Sha256); hash.addData(&executable);
                const auto bytes = tclDictionary({{"schema", "gxtxt.html_runtime.build.v1"}, {"abi", "gxtxt.html_runtime.v1"},
                    {"qt_version", qVersion()}, {"binary_sha256", QString::fromLatin1(hash.result().toHex())},
                    {"gui_started", false}, {"rendering_verified", false}}) + '\n';
                std::fwrite(bytes.constData(), 1, static_cast<size_t>(bytes.size()), stdout); std::fflush(stdout);
            } else if (app.arguments()[1] == "--probe") {
                if (argc != 2) fail("INVALID_ARGUMENT", "Probe takes no arguments");
                writeJson({{"schema", "gxtxt.html_runtime.build.v1"}, {"qt_version", qVersion()}, {"gui_started", false}, {"rendering_verified", false}});
            } else if (app.arguments()[1] == "--check-source") {
                if (argc != 5) fail("INVALID_ARGUMENT", "Source check requires root, relative and digest");
                AssetRoot root(app.arguments()[2]); const auto bytes = root.read(app.arguments()[3], documentLimit);
                const auto sha = QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex();
                if (sha != app.arguments()[4].toLatin1()) fail("SOURCE_CHANGED", "HTML source digest mismatch");
                writeJson({{"ok", true}, {"bytes", static_cast<qint64>(bytes.size())}, {"sha256", QString::fromLatin1(sha)}});
            } else {
                if (argc != 2) fail("INVALID_ARGUMENT", "Control check takes no arguments");
                QFile input; input.open(stdin, QIODevice::ReadOnly);
                for (;;) {
                    auto line = input.readLine(frameLimit + 2);
                    if (line.isEmpty() && input.atEnd()) break;
                    if (!line.endsWith('\n') && line.size() > frameLimit) {
                        auto remainder = line;
                        while (!remainder.endsWith('\n') && !input.atEnd()) remainder = input.readLine(frameLimit + 2);
                        writeJson(errorObject(Failure{QStringLiteral("FRAME_TOO_LARGE"), QStringLiteral("Control frame exceeds 16 KiB")}));
                        continue;
                    }
                    if (line.endsWith('\n')) line.chop(1);
                    try { const auto command = parse(line); writeJson({{"ok", true}, {"op", command.op}, {"request_id", command.request}}); }
                    catch (const Failure &failure) { writeJson(errorObject(failure)); }
                }
            }
            return 0;
        } catch (const Failure &failure) { writeJson(errorObject(failure)); return 2; }
    }
    if (argc == 4 && QByteArray(argv[3]) == "--tcl") { tclWire = true; argc = 3; }
    try {
        if (argc != 3 || QByteArray(argv[1]) != "--parent-window") fail("INVALID_ARGUMENT", "Runtime requires its authorized native parent window");
        bool valid = false; const auto parent = QString::fromLocal8Bit(argv[2]).toULongLong(&valid, 0);
        if (!valid || parent == 0 || parent > std::numeric_limits<quintptr>::max()) fail("INVALID_ARGUMENT", "Invalid native parent identity");
        if (::geteuid() == 0 || qEnvironmentVariableIsSet("QTWEBENGINE_DISABLE_SANDBOX") ||
            !qEnvironmentVariable("QTWEBENGINE_CHROMIUM_FLAGS").isEmpty() || qEnvironmentVariableIsSet("QTWEBENGINE_REMOTE_DEBUGGING"))
            fail("SANDBOX_UNAVAILABLE", "Unsupported privilege, sandbox override or debug environment");
#ifdef __linux__
        const auto parentPid = ::getppid();
        if (::prctl(PR_SET_PDEATHSIG, SIGTERM) != 0 || ::getppid() != parentPid) fail("PARENT_GONE", "Parent lifetime could not be retained");
#endif
        if (::getpgrp() != ::getpid() && ::setsid() < 0) fail("CONTROL_UNAVAILABLE", "Cannot establish owned process group");
        std::signal(SIGPIPE, SIG_IGN);
        if (::fcntl(STDIN_FILENO, F_SETFL, ::fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK) < 0 ||
            ::fcntl(STDOUT_FILENO, F_SETFL, ::fcntl(STDOUT_FILENO, F_GETFL) | O_NONBLOCK) < 0)
            fail("CONTROL_UNAVAILABLE", "Control pipes cannot be configured");
        QWebEngineUrlScheme scheme(schemeName.toLatin1()); scheme.setSyntax(QWebEngineUrlScheme::Syntax::Host);
        scheme.setFlags(QWebEngineUrlScheme::SecureScheme | QWebEngineUrlScheme::LocalScheme |
                        QWebEngineUrlScheme::LocalAccessAllowed | QWebEngineUrlScheme::CorsEnabled | QWebEngineUrlScheme::FetchApiAllowed);
        QWebEngineUrlScheme::registerScheme(scheme);
        // Consume only our own startup flags; Chromium receives no authored argv.
        int qtArgc = 1; QApplication app(qtArgc, argv);
        if (QGuiApplication::platformName() != "xcb") fail("PLATFORM_UNSUPPORTED", "Only Debian X11 embedding is currently supported");
        Runtime runtime(static_cast<quintptr>(parent)); return app.exec();
    } catch (const Failure &failure) { writeJson(errorObject(failure)); return 2; }
}
