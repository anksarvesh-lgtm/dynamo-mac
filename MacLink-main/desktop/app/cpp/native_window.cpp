// SPDX-License-Identifier: GPL-3.0-or-later
#include "native_window.h"
#include "app_helpers.h"

#include <QtGui/QPlatformSurfaceEvent>
#include <QtQml/QtQml>
#include <QtQuick/QSGRendererInterface>

#include <algorithm>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <dwmapi.h>
#include <dxgi1_3.h>
#include <windowsx.h>

namespace {

// Values from the Windows 11 SDK, defined here so older SDK headers work.
constexpr DWORD kUseImmersiveDarkMode = 20;  // DWMWA_USE_IMMERSIVE_DARK_MODE
constexpr DWORD kCaptionColor = 35;          // DWMWA_CAPTION_COLOR
constexpr DWORD kSystemBackdropType = 38;    // DWMWA_SYSTEMBACKDROP_TYPE
constexpr int kBackdropNone = 1;             // DWMSBT_NONE
constexpr int kBackdropMica = 2;             // DWMSBT_MAINWINDOW
constexpr int kBackdropAcrylic = 3;          // DWMSBT_TRANSIENTWINDOW (Desktop Acrylic blur)
constexpr COLORREF kColorNone = 0xFFFFFFFE;  // DWMWA_COLOR_NONE

HWND hwndOf(const QWindow *window)
{
    return reinterpret_cast<HWND>(window->winId());
}

void trimD3DResources(QQuickWindow *window)
{
    if (!window)
        return;
    QSGRendererInterface *rif = window->rendererInterface();
    if (!rif)
        return;
    auto *device = static_cast<ID3D11Device *>(
        rif->getResource(window, QSGRendererInterface::DeviceResource));
    if (!device)
        return;
    IDXGIDevice3 *dxgi3 = nullptr;
    if (SUCCEEDED(device->QueryInterface(__uuidof(IDXGIDevice3), reinterpret_cast<void **>(&dxgi3))) && dxgi3) {
        dxgi3->Trim();
        dxgi3->Release();
    }
}

} // namespace
#else
namespace {
void trimD3DResources(QQuickWindow * /*window*/) {}
} // namespace
#endif

NativeWindow::NativeWindow(QWindow *parent)
    : QQuickWindow(parent)
{
#ifdef _WIN32
    // Qt removes the system title bar and lets content fill the window on Windows.
    setFlags(flags() | Qt::ExpandedClientAreaHint);
#endif
    setColor(Qt::transparent);
    // Drop the scene graph and D3D/RHI resources when the window is hidden or
    // closed to the tray instead of keeping GPU buffers in private commit.
    setPersistentSceneGraph(false);
    setPersistentGraphics(false);
}

void NativeWindow::setBackdrop(bool on)
{
    if (m_backdrop == on)
        return;
    m_backdrop = on;
    applyFrame();
    emit backdropChanged();
}

void NativeWindow::setAcrylic(bool on)
{
    if (m_acrylic == on)
        return;
    m_acrylic = on;
    applyFrame();
    emit acrylicChanged();
}

void NativeWindow::setDarkFrame(bool dark)
{
    if (m_darkFrame == dark)
        return;
    m_darkFrame = dark;
    applyFrame();
    emit darkFrameChanged();
}

void NativeWindow::setCaptionHeight(qreal height)
{
    if (qFuzzyCompare(m_captionHeight, height))
        return;
    m_captionHeight = height;
    emit captionHeightChanged();
}

void NativeWindow::setMaximizeButton(QQuickItem *item)
{
    if (m_maximizeButton == item)
        return;
    m_maximizeButton = item;
    emit maximizeButtonChanged();
}

void NativeWindow::setMaximizeState(bool hovered, bool pressed)
{
    if (m_maximizeHovered == hovered && m_maximizePressed == pressed)
        return;
    m_maximizeHovered = hovered;
    m_maximizePressed = pressed;
    emit maximizeStateChanged();
}

void NativeWindow::addCaptionHole(QQuickItem *item)
{
    if (item && std::none_of(m_holes.begin(), m_holes.end(), [item](const auto &h) { return h == item; }))
        m_holes.emplace_back(item);
}

void NativeWindow::removeCaptionHole(QQuickItem *item)
{
    m_holes.erase(std::remove_if(m_holes.begin(), m_holes.end(),
                                 [item](const auto &h) { return h.isNull() || h == item; }),
                  m_holes.end());
}

void NativeWindow::toggleMaximized()
{
    if (visibility() == QWindow::Maximized)
        showNormal();
    else
        showMaximized();
}

void NativeWindow::bringToFront()
{
    if (visibility() == QWindow::Minimized || !isVisible())
        showNormal();
    raise();
    requestActivate();
#ifdef _WIN32
    if (!handle())
        return;
    const HWND hwnd = hwndOf(this);
    if (SetForegroundWindow(hwnd) || GetForegroundWindow() == hwnd)
        return;
    // Windows only lets the process the user is working in change the
    // foreground window, so a copy opened from the background (after an
    // update, or by another instance) would stay behind. Sharing the
    // foreground thread's input state for a moment lets it come forward.
    const HWND foreground = GetForegroundWindow();
    const DWORD foregroundThread = foreground ? GetWindowThreadProcessId(foreground, nullptr) : 0;
    const DWORD thisThread = GetCurrentThreadId();
    const bool attached = foregroundThread != 0 && foregroundThread != thisThread
        && AttachThreadInput(thisThread, foregroundThread, TRUE);
    BringWindowToTop(hwnd);
    SetForegroundWindow(hwnd);
    if (attached)
        AttachThreadInput(thisThread, foregroundThread, FALSE);
#endif
}

void NativeWindow::flash()
{
#ifdef _WIN32
    if (!handle())
        return;
    FLASHWINFO info { sizeof(FLASHWINFO), hwndOf(this), FLASHW_TRAY | FLASHW_TIMERNOFG, 0, 0 };
    FlashWindowEx(&info);
#else
    alert(0);
#endif
}

void NativeWindow::releaseAndTeardown()
{
    if (QQmlEngine *engine = qmlEngine(this))
        register_qml_engine(engine);
    m_holes.clear();
    m_maximizeButton = nullptr;
    trimD3DResources(this);
    releaseResources();
    hide();
    trimD3DResources(this);
    destroy();
}

bool NativeWindow::event(QEvent *event)
{
    if (QQmlEngine *engine = qmlEngine(this))
        register_qml_engine(engine);
    if (event->type() == QEvent::Close) {
        trimD3DResources(this);
        event->accept();
        emit closeRequested();
        return true;
    }
    if (event->type() == QEvent::Hide) {
        trimD3DResources(this);
    }
    if (event->type() == QEvent::PlatformSurface
        && static_cast<QPlatformSurfaceEvent *>(event)->surfaceEventType()
            == QPlatformSurfaceEvent::SurfaceCreated) {
        const bool handled = QQuickWindow::event(event);
        applyFrame();
        return handled;
    }
    return QQuickWindow::event(event);
}

void NativeWindow::applyFrame()
{
#ifdef _WIN32
    if (!handle())
        return;
    const HWND hwnd = hwndOf(this);
    // No frame extension: Mica/Acrylic still shows behind transparent pixels (the
    // swap chain is composited with DirectComposition), and DWM doesn't draw
    // its own caption buttons over the app's.
    const MARGINS margins { 0, 0, 0, 0 };
    DwmExtendFrameIntoClientArea(hwnd, &margins);
    const BOOL dark = m_darkFrame;
    DwmSetWindowAttribute(hwnd, kUseImmersiveDarkMode, &dark, sizeof(dark));
    const int backdrop = m_backdrop ? (m_acrylic ? kBackdropAcrylic : kBackdropMica) : kBackdropNone;
    DwmSetWindowAttribute(hwnd, kSystemBackdropType, &backdrop, sizeof(backdrop));
    const COLORREF none = kColorNone;
    DwmSetWindowAttribute(hwnd, kCaptionColor, &none, sizeof(none));
#endif
}

bool NativeWindow::itemContains(const QQuickItem *item, const QPointF &scenePoint) const
{
    if (!item || !item->isVisible())
        return false;
    return item->mapRectToScene(QRectF(0, 0, item->width(), item->height())).contains(scenePoint);
}

long NativeWindow::hitTest(int screenX, int screenY) const
{
#ifdef _WIN32
    const HWND hwnd = hwndOf(this);
    POINT pt { screenX, screenY };
    ScreenToClient(hwnd, &pt);

    // The system title bar is gone, and with it the top resize border.
    // A window of fixed size has none.
    if (!IsZoomed(hwnd) && minimumSize() != maximumSize()) {
        const UINT dpi = GetDpiForWindow(hwnd);
        const int border = GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
        if (pt.y < border) {
            RECT client {};
            GetClientRect(hwnd, &client);
            if (pt.x < border * 2)
                return HTTOPLEFT;
            if (pt.x >= client.right - border * 2)
                return HTTOPRIGHT;
            return HTTOP;
        }
    }

    const qreal dpr = devicePixelRatio();
    const QPointF point(pt.x / dpr, pt.y / dpr);
    if (itemContains(m_maximizeButton, point))
        return HTMAXBUTTON;
    if (point.y() >= m_captionHeight)
        return HTCLIENT;
    for (const auto &hole : m_holes) {
        if (itemContains(hole, point))
            return HTCLIENT;
    }
    return HTCAPTION;
#else
    Q_UNUSED(screenX);
    Q_UNUSED(screenY);
    return 0;
#endif
}

bool NativeWindow::nativeEvent(const QByteArray &eventType, void *message, qintptr *result)
{
#ifdef _WIN32
    if (eventType != "windows_generic_MSG")
        return QQuickWindow::nativeEvent(eventType, message, result);
    const MSG *msg = static_cast<const MSG *>(message);

    switch (msg->message) {
    case WM_NCHITTEST: {
        const long hit = hitTest(GET_X_LPARAM(msg->lParam), GET_Y_LPARAM(msg->lParam));
        if (hit != HTCLIENT) {
            *result = hit;
            return true;
        }
        break;
    }
    // The maximize button reports HTMAXBUTTON, so its input arrives as
    // non-client messages. Handle them here and keep DefWindowProc from
    // drawing and tracking a classic button.
    case WM_NCMOUSEMOVE: {
        QEvent leaveEvent(QEvent::Leave);
        QCoreApplication::sendEvent(this, &leaveEvent);
        if (msg->wParam == HTMAXBUTTON) {
            if (!m_maximizeHovered) {
                TRACKMOUSEEVENT track { sizeof(track), TME_LEAVE | TME_NONCLIENT, msg->hwnd, 0 };
                TrackMouseEvent(&track);
            }
            setMaximizeState(true, m_maximizePressed);
            *result = 0;
            return true;
        }
        setMaximizeState(false, false);
        break;
    }
    case WM_NCMOUSELEAVE:
    case WM_MOUSEMOVE:
        setMaximizeState(false, false);
        break;
    case WM_NCLBUTTONDOWN:
    case WM_NCLBUTTONDBLCLK:
        if (msg->wParam == HTMAXBUTTON) {
            setMaximizeState(true, true);
            *result = 0;
            return true;
        }
        break;
    case WM_NCLBUTTONUP:
        if (msg->wParam == HTMAXBUTTON) {
            const bool wasPressed = m_maximizePressed;
            setMaximizeState(true, false);
            if (wasPressed)
                toggleMaximized();
            *result = 0;
            return true;
        }
        setMaximizeState(false, false);
        break;
    default:
        break;
    }
#else
    Q_UNUSED(eventType);
    Q_UNUSED(message);
    Q_UNUSED(result);
#endif
    return QQuickWindow::nativeEvent(eventType, message, result);
}
