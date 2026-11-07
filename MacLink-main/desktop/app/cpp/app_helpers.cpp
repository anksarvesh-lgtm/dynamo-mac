// SPDX-License-Identifier: GPL-3.0-or-later
#include "app_helpers.h"
#include "video_view.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFileInfo>
#include <QtCore/QLibraryInfo>
#include <QtCore/QLocale>
#include <QtCore/QMimeData>
#include <QtCore/QPointer>
#include <QtCore/QStorageInfo>
#include <QtCore/QStringList>
#include <QtCore/QTimeZone>
#include <QtCore/QTranslator>
#include <QtCore/QUrl>
#include <QtCore/QtEnvironmentVariables>
#include <QtGui/QDrag>
#include <QtGui/QFontDatabase>
#include <QtGui/QGuiApplication>
#include <QtGui/QIcon>
#include <QtGui/QImage>
#include <QtGui/QPixmap>
#include <QtGui/QPixmapCache>
#include <QtQml/QQmlApplicationEngine>
#include <QtQml/QQmlEngine>
#include <QtQuick/QQuickWindow>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <malloc.h>
#endif

namespace {
QIcon &appIcon()
{
    static QIcon icon;
    return icon;
}

QPointer<QQmlEngine> &qmlEngineRef()
{
    static QPointer<QQmlEngine> engine;
    return engine;
}

// Every QML engine registered, for retranslating them all when the
// language changes (gone ones drop out on their own).
QList<QPointer<QQmlEngine>> &allEngines()
{
    static QList<QPointer<QQmlEngine>> engines;
    return engines;
}

void remember(QQmlEngine *engine)
{
    auto &engines = allEngines();
    engines.removeIf([](const QPointer<QQmlEngine> &e) { return e.isNull(); });
    if (!engines.contains(engine))
        engines.append(engine);
}
} // namespace

void register_qml_engine(QQmlEngine *engine)
{
    if (engine) {
        qmlEngineRef() = engine;
        remember(engine);
    }
}

void register_qml_app_engine(QQmlApplicationEngine &engine)
{
    qmlEngineRef() = &engine;
    remember(&engine);
}

#include <QtCore/QDateTime>
#include <QtCore/QFile>
#include <QtCore/QStandardPaths>
#include <QtCore/QTextStream>

#include <atomic>
#include <cstdio>

namespace {
std::atomic<int> &qmlProblems()
{
    static std::atomic<int> count { 0 };
    return count;
}

// A warning or error from QML: a component that didn't load, a binding or
// a script that failed.
bool isQmlProblem(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    if (type != QtWarningMsg && type != QtCriticalMsg && type != QtFatalMsg)
        return false;
    return (ctx.file && QByteArray(ctx.file).startsWith("qrc:/")) || msg.contains(QStringLiteral("qrc:/"));
}

// `--ui-check`: messages go to stderr, not the log file, and QML problems
// are counted.
void uiCheckMessageHandler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    if (type == QtDebugMsg)
        return;
    if (isQmlProblem(type, ctx, msg))
        qmlProblems().fetch_add(1);
    std::fprintf(stderr, "[%d] %s (%s:%d)\n", int(type), qUtf8Printable(msg), ctx.file ? ctx.file : "", ctx.line);
    std::fflush(stderr);
}

void qtLogMessageHandler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    if (type == QtDebugMsg)
        return;
    const QString dirPath = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QStringLiteral("/MacLink/logs");
    QDir().mkpath(dirPath);
    QFile file(dirPath + QStringLiteral("/qml.log"));
    if (file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        QTextStream ts(&file);
        ts << QDateTime::currentDateTimeUtc().toString(Qt::ISODate) << " [" << type << "] "
           << msg << " (" << (ctx.file ? ctx.file : "") << ":" << ctx.line << ")\n";
    }
}
} // namespace

void prepare_qt()
{
    qInstallMessageHandler(qtLogMessageHandler);
    prepare_qt_without_log();
}

void prepare_qt_for_ui_check()
{
    qInstallMessageHandler(uiCheckMessageHandler);
    prepare_qt_without_log();
}

int32_t qml_problem_count()
{
    return qmlProblems().load();
}

void prepare_qt_without_log()
{
    // Windows get an alpha channel so the Mica backdrop can show through, and
    // D3D swap chains are presented with DirectComposition, without which
    // transparent pixels render white (see spikes/s1-qt-rust, lesson 7).
    QQuickWindow::setDefaultAlphaBuffer(true);
    qputenv("QT_QPA_DISABLE_REDIRECTION_SURFACE", "1");
    qputenv("QSG_RENDER_LOOP", "basic");
    // Qt's V4 JS engine reserves 2 x QV4_JS_MAX_STACK_SIZE of committed RW
    // memory (8 MB by default). 512 KB per stack (1 MB total) is plenty for
    // UI bindings and saves 7 MB of private commit in the tray.
    qputenv("QV4_JS_MAX_STACK_SIZE", "524288");
}

void add_app_icon_image(int32_t size, rust::Slice<const uint8_t> rgba)
{
    if (size <= 0 || rgba.size() != static_cast<size_t>(size) * size * 4)
        return;
    // Copy: the image must not reference Rust memory after this call.
    const QImage image =
        QImage(rgba.data(), size, size, size * 4, QImage::Format_RGBA8888).copy();
    appIcon().addPixmap(QPixmap::fromImage(image));
}

void apply_app_icon()
{
    QGuiApplication::setWindowIcon(appIcon());
}

void keep_running_without_windows()
{
    QGuiApplication::setQuitOnLastWindowClosed(false);
}

int32_t load_bundled_fonts()
{
    int32_t loaded = 0;
    const QDir dir(QStringLiteral(":/fonts"));
    for (const QString &name : dir.entryList({QStringLiteral("*.ttf")}, QDir::Files)) {
        if (QFontDatabase::addApplicationFont(dir.filePath(name)) >= 0)
            ++loaded;
    }
    return loaded;
}

void trim_memory_caches()
{
    clear_idle_video_frames();
    QPixmapCache::clear();
    if (QQmlEngine *engine = qmlEngineRef().data()) {
        engine->collectGarbage();
        engine->trimComponentCache();
        engine->collectGarbage();
    }
#ifdef _WIN32
    _heapmin();
    HANDLE heaps[64];
    const DWORD count = GetProcessHeaps(64, heaps);
    for (DWORD i = 0; i < count && i < 64; ++i) {
        HeapCompact(heaps[i], 0);
    }
    SetProcessWorkingSetSize(GetCurrentProcess(), static_cast<SIZE_T>(-1), static_cast<SIZE_T>(-1));
#endif
}

bool start_external_drag(rust::Str file_path, rust::Str text_fallback)
{
    const QString path = QString::fromUtf8(file_path.data(), static_cast<qsizetype>(file_path.size())).trimmed();
    const QString text = QString::fromUtf8(text_fallback.data(), static_cast<qsizetype>(text_fallback.size()));
    if (path.isEmpty() && text.isEmpty())
        return false;

    auto *mime = new QMimeData();
    QPixmap dragPixmap;
    if (!path.isEmpty() && QFileInfo::exists(path)) {
        mime->setUrls({QUrl::fromLocalFile(path)});
        QImage img(path);
        if (!img.isNull()) {
            mime->setImageData(img);
            dragPixmap = QPixmap::fromImage(img.scaled(96, 96, Qt::KeepAspectRatio, Qt::SmoothTransformation));
        }
    } else if (!text.isEmpty()) {
        mime->setText(text);
    } else {
        delete mime;
        return false;
    }

    QDrag drag(QGuiApplication::instance());
    drag.setMimeData(mime);
    if (!dragPixmap.isNull())
        drag.setPixmap(dragPixmap);
    return drag.exec(Qt::CopyAction) != Qt::IgnoreAction;
}

namespace {
// The translators installed now, replaced when the language changes.
QPointer<QTranslator> &qtTranslator()
{
    static QPointer<QTranslator> t;
    return t;
}
QPointer<QTranslator> &appTranslator()
{
    static QPointer<QTranslator> t;
    return t;
}

void drop(QPointer<QTranslator> &translator)
{
    if (translator) {
        QCoreApplication::removeTranslator(translator);
        delete translator.data();
    }
    translator = nullptr;
}
} // namespace

bool install_translator(rust::Str dir, rust::Str language)
{
    const QString folder = QString::fromUtf8(dir.data(), static_cast<qsizetype>(dir.size()));
    const QString chosen = QString::fromUtf8(language.data(), static_cast<qsizetype>(language.size()));
    const QLocale locale = chosen.isEmpty() ? QLocale::system() : QLocale(chosen);
    QLocale::setDefault(locale);
    drop(qtTranslator());
    drop(appTranslator());

    // Qt's own strings: file dialogs, context menus, the standard buttons.
    // windeployqt stages a merged `qt_<locale>.qm` in `translations/` beside the
    // executable, while a build from source finds `qtbase_<locale>.qm` in Qt's
    // own folder, so try both names in both places.
    const QStringList qtDirs{
        folder + QStringLiteral("/translations"),
        QLibraryInfo::path(QLibraryInfo::TranslationsPath),
    };
    for (const QString &qtDir : qtDirs) {
        for (const char *name : {"qtbase", "qt"}) {
            auto *qt = new QTranslator(QCoreApplication::instance());
            if (qt->load(locale, QString::fromLatin1(name), QStringLiteral("_"), qtDir)) {
                QCoreApplication::installTranslator(qt);
                qtTranslator() = qt;
                break;
            }
            delete qt;
        }
        if (qtTranslator())
            break;
    }

    // MacLink's own strings, staged beside the executable. A locale with no
    // translation (`maclink_es_ES.qm` missing), or English, stays English.
    bool installed = false;
    auto *app = new QTranslator(QCoreApplication::instance());
    if (app->load(locale, QStringLiteral("maclink"), QStringLiteral("_"), folder)) {
        installed = QCoreApplication::installTranslator(app);
        appTranslator() = app;
    } else {
        delete app;
    }

    // Windows already open show the new language at once.
    for (const QPointer<QQmlEngine> &engine : allEngines()) {
        if (engine)
            engine->retranslate();
    }
    return installed;
}

rust::String translate(rust::Str context, rust::Str text)
{
    const std::string c(context.data(), context.size());
    const std::string t(text.data(), text.size());
    return rust::String(QCoreApplication::translate(c.c_str(), t.c_str()).toStdString());
}

rust::Vec<uint8_t> decode_image(rust::Slice<const uint8_t> bytes)
{
    rust::Vec<uint8_t> result;
    if (bytes.empty())
        return result;
    QImage img;
    if (!img.loadFromData(bytes.data(), static_cast<int>(bytes.size())))
        return result;
    const QImage argb = img.convertToFormat(QImage::Format_ARGB32);
    const uint32_t width = static_cast<uint32_t>(argb.width());
    const uint32_t height = static_cast<uint32_t>(argb.height());
    const size_t byteCount = static_cast<size_t>(argb.sizeInBytes());
    result.reserve(8 + byteCount);
    for (int i = 0; i < 4; ++i)
        result.push_back(static_cast<uint8_t>((width >> (i * 8)) & 0xFF));
    for (int i = 0; i < 4; ++i)
        result.push_back(static_cast<uint8_t>((height >> (i * 8)) & 0xFF));
    const uint8_t *bits = argb.constBits();
    for (size_t i = 0; i < byteCount; ++i)
        result.push_back(bits[i]);
    return result;
}

#ifdef __APPLE__
#include <objc/runtime.h>
#include <objc/message.h>

extern "C" void *objc_autoreleasePoolPush(void);
extern "C" void objc_autoreleasePoolPop(void *pool);

namespace {
struct AutoReleasePool {
    void *pool;
    AutoReleasePool() : pool(objc_autoreleasePoolPush()) {}
    ~AutoReleasePool() { objc_autoreleasePoolPop(pool); }
};
} // namespace

int64_t mac_clipboard_change_count()
{
    AutoReleasePool pool;
    id pboardClass = reinterpret_cast<id>(objc_getClass("NSPasteboard"));
    if (!pboardClass)
        return 0;
    id pboard = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(pboardClass, sel_registerName("generalPasteboard"));
    if (!pboard)
        return 0;
    return reinterpret_cast<int64_t (*)(id, SEL)>(objc_msgSend)(pboard, sel_registerName("changeCount"));
}

rust::String mac_clipboard_read_text(bool &is_private)
{
    AutoReleasePool pool;
    is_private = false;
    id pboardClass = reinterpret_cast<id>(objc_getClass("NSPasteboard"));
    if (!pboardClass)
        return rust::String();
    id pboard = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(pboardClass, sel_registerName("generalPasteboard"));
    if (!pboard)
        return rust::String();

    id strClass = reinterpret_cast<id>(objc_getClass("NSString"));
    if (!strClass)
        return rust::String();

    id concealed = reinterpret_cast<id (*)(id, SEL, const char *)>(objc_msgSend)(
        strClass, sel_registerName("stringWithUTF8String:"), "org.nspasteboard.ConcealedType");
    id transient = reinterpret_cast<id (*)(id, SEL, const char *)>(objc_msgSend)(
        strClass, sel_registerName("stringWithUTF8String:"), "org.nspasteboard.TransientType");
    id autoGen = reinterpret_cast<id (*)(id, SEL, const char *)>(objc_msgSend)(
        strClass, sel_registerName("stringWithUTF8String:"), "org.nspasteboard.AutoGeneratedType");
    id plainTextType = reinterpret_cast<id (*)(id, SEL, const char *)>(objc_msgSend)(
        strClass, sel_registerName("stringWithUTF8String:"), "public.utf8-plain-text");

    for (int attempt = 0; attempt < 2; ++attempt) {
        int64_t countBefore = reinterpret_cast<int64_t (*)(id, SEL)>(objc_msgSend)(pboard, sel_registerName("changeCount"));

        id types = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(pboard, sel_registerName("types"));
        if (types) {
            if ((concealed && reinterpret_cast<bool (*)(id, SEL, id)>(objc_msgSend)(types, sel_registerName("containsObject:"), concealed))
                || (transient && reinterpret_cast<bool (*)(id, SEL, id)>(objc_msgSend)(types, sel_registerName("containsObject:"), transient))
                || (autoGen && reinterpret_cast<bool (*)(id, SEL, id)>(objc_msgSend)(types, sel_registerName("containsObject:"), autoGen))) {
                int64_t countAfter = reinterpret_cast<int64_t (*)(id, SEL)>(objc_msgSend)(pboard, sel_registerName("changeCount"));
                if (countBefore == countAfter) {
                    is_private = true;
                    return rust::String();
                }
                continue;
            }
        }

        id str = reinterpret_cast<id (*)(id, SEL, id)>(objc_msgSend)(pboard, sel_registerName("stringForType:"), plainTextType);
        int64_t countAfter = reinterpret_cast<int64_t (*)(id, SEL)>(objc_msgSend)(pboard, sel_registerName("changeCount"));
        if (countBefore != countAfter) {
            continue;
        }

        if (str) {
            const char *utf8 = reinterpret_cast<const char * (*)(id, SEL)>(objc_msgSend)(str, sel_registerName("UTF8String"));
            if (utf8)
                return rust::String(utf8);
        }
        return rust::String();
    }

    is_private = false;
    return rust::String();
}

bool mac_clipboard_write_text(rust::Str text, bool is_private)
{
    AutoReleasePool pool;
    id pboardClass = reinterpret_cast<id>(objc_getClass("NSPasteboard"));
    if (!pboardClass)
        return false;
    id pboard = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(pboardClass, sel_registerName("generalPasteboard"));
    if (!pboard)
        return false;

    reinterpret_cast<void (*)(id, SEL)>(objc_msgSend)(pboard, sel_registerName("clearContents"));

    id strClass = reinterpret_cast<id>(objc_getClass("NSString"));
    if (!strClass)
        return false;

    const std::string text_str(text.data(), text.size());
    id nsStr = reinterpret_cast<id (*)(id, SEL, const char *)>(objc_msgSend)(
        strClass, sel_registerName("stringWithUTF8String:"), text_str.c_str());
    if (!nsStr)
        return false;

    id plainTextType = reinterpret_cast<id (*)(id, SEL, const char *)>(objc_msgSend)(
        strClass, sel_registerName("stringWithUTF8String:"), "public.utf8-plain-text");

    id arrClass = reinterpret_cast<id>(objc_getClass("NSArray"));
    if (!arrClass)
        return false;

    if (is_private) {
        id concealed = reinterpret_cast<id (*)(id, SEL, const char *)>(objc_msgSend)(
            strClass, sel_registerName("stringWithUTF8String:"), "org.nspasteboard.ConcealedType");
        id transient = reinterpret_cast<id (*)(id, SEL, const char *)>(objc_msgSend)(
            strClass, sel_registerName("stringWithUTF8String:"), "org.nspasteboard.TransientType");
        const id items[] = { plainTextType, concealed, transient };
        id types = reinterpret_cast<id (*)(id, SEL, const id *, unsigned long)>(objc_msgSend)(
            arrClass, sel_registerName("arrayWithObjects:count:"), items, 3);
        reinterpret_cast<void (*)(id, SEL, id, id)>(objc_msgSend)(
            pboard, sel_registerName("declareTypes:owner:"), types, nullptr);
        bool ok = reinterpret_cast<bool (*)(id, SEL, id, id)>(objc_msgSend)(
            pboard, sel_registerName("setString:forType:"), nsStr, plainTextType);
        if (!ok)
            return false;
        id dataClass = reinterpret_cast<id>(objc_getClass("NSData"));
        if (dataClass) {
            id emptyData = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(dataClass, sel_registerName("data"));
            reinterpret_cast<bool (*)(id, SEL, id, id)>(objc_msgSend)(
                pboard, sel_registerName("setData:forType:"), emptyData, concealed);
            reinterpret_cast<bool (*)(id, SEL, id, id)>(objc_msgSend)(
                pboard, sel_registerName("setData:forType:"), emptyData, transient);
        }
        return true;
    } else {
        const id items[] = { plainTextType };
        id types = reinterpret_cast<id (*)(id, SEL, const id *, unsigned long)>(objc_msgSend)(
            arrClass, sel_registerName("arrayWithObjects:count:"), items, 1);
        reinterpret_cast<void (*)(id, SEL, id, id)>(objc_msgSend)(
            pboard, sel_registerName("declareTypes:owner:"), types, nullptr);
        return reinterpret_cast<bool (*)(id, SEL, id, id)>(objc_msgSend)(
            pboard, sel_registerName("setString:forType:"), nsStr, plainTextType);
    }
}
#else
int64_t mac_clipboard_change_count()
{
    return 0;
}

rust::String mac_clipboard_read_text(bool &is_private)
{
    is_private = false;
    return rust::String();
}

bool mac_clipboard_write_text(rust::Str /*text*/, bool /*is_private*/)
{
    return false;
}
#endif

int64_t mac_local_offset_ms(int64_t at_ms)
{
    const QDateTime dt = QDateTime::fromMSecsSinceEpoch(at_ms, QTimeZone::systemTimeZone());
    return static_cast<int64_t>(dt.offsetFromUtc()) * 1000;
}

uint64_t mac_free_space(rust::Str path, bool &ok)
{
    ok = false;
    const std::string pathStr(path.data(), path.size());
    QString qpath = QString::fromStdString(pathStr);
    QFileInfo info(qpath);
    while (!info.exists() && !qpath.isEmpty()) {
        const QString parent = info.dir().absolutePath();
        if (parent == qpath)
            break;
        qpath = parent;
        info.setFile(qpath);
    }
    const QStorageInfo storage(qpath);
    if (!storage.isValid() || !storage.isReady())
        return 0;
    const qint64 available = storage.bytesAvailable();
    if (available < 0)
        return 0;
    ok = true;
    return static_cast<uint64_t>(available);
}
