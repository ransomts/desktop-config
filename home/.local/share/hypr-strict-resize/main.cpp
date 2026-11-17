// hypr-strict-resize: mouse resizing of tiled windows that does what the pointer suggests.
//
// Stock Hyprland grabs a window *quadrant* when you drag a border or gap, so a drag on the
// edge between two windows also moves whichever other split that quadrant touches. Here a
// press on a tiled window is read once, by decide(), and the hover cursor, the drag and the
// keybind drag (Super+right button) all follow that one reading:
//
//   edge      on the edge between two windows: that edge's direction only (left/right edge
//             -> X, top/bottom edge -> Y); the other direction is dropped.
//   junction  three or more tiled windows within junction_radius px of the pointer: both
//             directions, from the corner of the window whose corner is closest. Every
//             window with a corner on that junction follows, so a four-way cross stays a
//             cross instead of coming apart into two T-junctions.
//   nothing   an edge with no tiled window on its other side (the screen edge), or a
//             direction the desktop's layout cannot resize (see axes() below): no resize
//             cursor, and a press does not start a drag.
//
// Keyboard resizing (Super+Ctrl+arrows, `hyprctl dispatch resizeactive`): Hyprland's
// dwindle and main-and-stack move the divider in the arrow's direction, so "wider" on a
// window against the right edge of the screen made it narrower. Here the direction is
// turned round for such a window, so wider / taller always grows the focused window.
//
// A keybind drag started inside a window uses the window's thirds: the middle of an edge
// strip is that edge, a corner cell is that corner, the centre cell is Hyprland's own
// nearest-quadrant behaviour. Floating windows are left alone throughout.
//
// For ~/.config/hypr/layouts.lua, as Lua functions under hl.plugin.strictresize:
//   take()         Hyprland gives a Lua layout no resize information, only a redraw. While
//                  that redraw runs, take() returns the resize in progress: window address,
//                  dx, dy and the grabbed edges (1 top, 2 bottom, 4 left, 8 right; 0 =
//                  keyboard resize), so the layout can move its own dividers. Returns
//                  nothing outside a resize.
//   axes(ws, "xy") which directions the layout on workspace id `ws` can resize: "xy"
//                  (default, and what the built-in layouts get), "x", "y" or "".
//   reset()        puts the built-in dwindle / main-and-stack layout of the desktop in
//                  front back to its default proportions; returns "dwindle", "master" or
//                  "none".
//
// Moving a tiled window by dragging it shows where it will land before you let go (see
// "moving a tiled window" below).
//
// Internal functions hooked (no stable API covers this):
//   Layout::CLayoutManager::beginDragTarget  - apply decide() when a drag starts
//   Layout::CLayoutManager::resizeTarget     - drop the locked direction, move the junction
//   CInputManager::setCursorIconOnBorder     - make the hover cursor show decide()'s answer
//   Layout::CLayoutManager::moveMouse / endDragTarget, CDragStateController::updateDragWindow
//                                            - keep a moved tiled window tiled, preview, drop

#define WLR_USE_UNSTABLE

#include <algorithm>
#include <cmath>
#include <format>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/algorithm/tiled/dwindle/DwindleAlgorithm.hpp>
#include <hyprland/src/layout/algorithm/tiled/master/MasterAlgorithm.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/pointer/cursor/CursorShapeOverrideController.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Context.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>

// reset() rewrites split ratios kept in private members, and the cursor hook has to
// invalidate the input manager's cached border direction. Naming a private member in an
// explicit template instantiation is allowed, which is what hands these pointers out.
template <typename Tag, typename Tag::type M>
struct SExpose {
    friend typename Tag::type exposed(Tag) {
        return M;
    }
};
struct SBorderIconTag {
    using type = eBorderIconDirection CInputManager::*;
    friend type exposed(SBorderIconTag);
};
struct SDwindleNodesTag {
    using type = std::vector<SP<Layout::Tiled::SDwindleNodeData>> Layout::Tiled::CDwindleAlgorithm::*;
    friend type exposed(SDwindleNodesTag);
};
struct SMasterNodesTag {
    using type = std::vector<SP<Layout::Tiled::SMasterNodeData>> Layout::Tiled::CMasterAlgorithm::*;
    friend type exposed(SMasterNodesTag);
};
template struct SExpose<SBorderIconTag, &CInputManager::m_borderIconDirection>;
template struct SExpose<SDwindleNodesTag, &Layout::Tiled::CDwindleAlgorithm::m_dwindleNodesData>;
template struct SExpose<SMasterNodesTag, &Layout::Tiled::CMasterAlgorithm::m_masterNodesData>;

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

using namespace Layout;

inline HANDLE                        PHANDLE = nullptr;

static CFunctionHook*                g_beginHook  = nullptr;
static CFunctionHook*                g_resizeHook = nullptr;
static CFunctionHook*                g_cursorHook = nullptr;
static SP<Config::Values::CIntValue> g_radius;

enum eAxes : uint8_t {
    AXIS_X  = 1,
    AXIS_Y  = 2,
    AXIS_XY = 3,
};

// workspace id -> directions its layout can resize (absent = both)
static std::unordered_map<int64_t, uint8_t> g_axes;

// ---- the drag in progress ----
struct SFollower {
    WP<ITarget> target;
    eRectCorner corner = CORNER_NONE;
    Vector2D    offset; // its corner point minus the leader's, at press
};

static struct {
    WP<ITarget>            target;
    eRectCorner            corner = CORNER_NONE;
    uint8_t                axes   = AXIS_XY; // directions that count for this drag
    std::vector<SFollower> followers;        // the other windows with a corner on the junction
} g_drag;

// the resize being applied right now, for take()
static struct {
    bool        active = false;
    std::string address;
    double      dx = 0, dy = 0;
    int         edges = 0;
} g_current;

using beginDragFn = void (*)(void*, SP<ITarget>, eMouseBindMode, std::optional<eRectCorner>, bool);
using resizeFn    = void (*)(void*, const Vector2D&, SP<ITarget>, eRectCorner);
using cursorFn    = void (*)(void*, PHLWINDOW);

// ---- geometry ----
static double distToBox(const CBox& b, const Vector2D& p) {
    const double dx = std::max({b.x - p.x, 0.0, p.x - (b.x + b.w)});
    const double dy = std::max({b.y - p.y, 0.0, p.y - (b.y + b.h)});
    return std::hypot(dx, dy);
}

static Vector2D cornerPoint(const CBox& b, eRectCorner c) {
    return {edgeLeft(c) ? b.x : b.x + b.w, edgeTop(c) ? b.y : b.y + b.h};
}

static eRectCorner nearestCorner(const CBox& b, const Vector2D& p) {
    const bool left = std::abs(p.x - b.x) < std::abs(p.x - (b.x + b.w));
    const bool top  = std::abs(p.y - b.y) < std::abs(p.y - (b.y + b.h));
    return sc<eRectCorner>((top ? CORNER_TOP : CORNER_BOTTOM) | (left ? CORNER_LEFT : CORNER_RIGHT));
}

static uint8_t axesOf(eRectCorner c) {
    return ((c & (CORNER_LEFT | CORNER_RIGHT)) ? AXIS_X : 0) | ((c & (CORNER_TOP | CORNER_BOTTOM)) ? AXIS_Y : 0);
}

static eRectCorner restrict(eRectCorner c, uint8_t axes) {
    int bits = c;
    if (!(axes & AXIS_X))
        bits &= ~(CORNER_LEFT | CORNER_RIGHT);
    if (!(axes & AXIS_Y))
        bits &= ~(CORNER_TOP | CORNER_BOTTOM);
    return sc<eRectCorner>(bits);
}

static bool tiledOn(const PHLWINDOW& w, const PHLWORKSPACE& ws) {
    if (!w || !w->mapped() || w->isHidden() || w->m_workspace != ws)
        return false;
    const auto T = w->layoutTarget();
    return T && !T->floating();
}

static bool overlaps(const CBox& a, const CBox& b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}

// Is there a tiled window just across this single edge of `w`, level with the pointer?
static bool edgeHasNeighbour(const PHLWINDOW& w, eRectCorner edge, const Vector2D& mouse) {
    constexpr double REACH = 48;
    const CBox       B     = w->getWindowMainSurfaceBox();
    CBox             probe;

    if (edge == CORNER_LEFT)
        probe = {B.x - REACH, mouse.y - 1, REACH, 2};
    else if (edge == CORNER_RIGHT)
        probe = {B.x + B.w, mouse.y - 1, REACH, 2};
    else if (edge == CORNER_TOP)
        probe = {mouse.x - 1, B.y - REACH, 2, REACH};
    else
        probe = {mouse.x - 1, B.y + B.h, 2, REACH};

    for (const auto& o : Desktop::viewState()->windows()) {
        if (o == w || !tiledOn(o, w->m_workspace))
            continue;
        if (overlaps(o->getWindowMainSurfaceBox(), probe))
            return true;
    }
    return false;
}

// ---- the one reading of a press ----
enum eDecision : uint8_t {
    DECIDE_STOCK = 0, // not ours (floating etc.): leave Hyprland alone
    DECIDE_NOTHING,   // nothing to resize here
    DECIDE_GRAB,      // resize `target` from `corner` (one edge bit = one direction only)
};

struct SDecision {
    eDecision              kind = DECIDE_STOCK;
    SP<ITarget>            target;
    eRectCorner            corner = CORNER_NONE;
    std::vector<SFollower> followers;
};

static SDecision decide(const PHLWINDOW& w, const Vector2D& mouse) {
    SDecision d;

    const auto TARGET = w ? w->layoutTarget() : nullptr;
    if (!TARGET || !w->mapped() || TARGET->floating() || !w->m_workspace)
        return d;

    uint8_t axes = AXIS_XY;
    if (const auto ID = w->m_workspace->numberedID()) { // special workspaces have none: both directions
        if (const auto it = g_axes.find(sc<int64_t>(*ID)); it != g_axes.end())
            axes = it->second;
    }

    const CBox REAL = w->getWindowMainSurfaceBox();
    d.target        = TARGET;

    if (REAL.containsPoint(mouse)) {
        // keybind drag inside the window: by thirds
        const double FX = (mouse.x - REAL.x) / std::max(REAL.w, 1.0), FY = (mouse.y - REAL.y) / std::max(REAL.h, 1.0);
        const int    CX = FX < 1.0 / 3 ? -1 : (FX > 2.0 / 3 ? 1 : 0), CY = FY < 1.0 / 3 ? -1 : (FY > 2.0 / 3 ? 1 : 0);

        eRectCorner  c = sc<eRectCorner>((CX < 0 ? CORNER_LEFT : CX > 0 ? CORNER_RIGHT : 0) | (CY < 0 ? CORNER_TOP : CY > 0 ? CORNER_BOTTOM : 0));
        // the centre cell, or an edge strip facing the screen edge: nearest quadrant, as stock
        if (c == CORNER_NONE || (axesOf(c) != AXIS_XY && !edgeHasNeighbour(w, c, mouse)))
            c = nearestCorner(REAL, mouse);

        d.corner = restrict(c, axes);
        d.kind   = d.corner == CORNER_NONE ? DECIDE_NOTHING : DECIDE_GRAB;
        return d;
    }

    // border / gap press. Tiled windows that reach to within RADIUS of the pointer:
    const double RADIUS = std::max<double>(g_radius ? g_radius->value() : 48, 0);

    struct SNear {
        PHLWINDOW   w;
        eRectCorner corner;
        double      cornerDist;
    };
    std::vector<SNear> nearby;

    for (const auto& o : Desktop::viewState()->windows()) {
        if (!tiledOn(o, w->m_workspace))
            continue;
        const CBox BOX = o->getWindowMainSurfaceBox();
        if (distToBox(BOX, mouse) > RADIUS)
            continue;
        const auto C = nearestCorner(BOX, mouse);
        nearby.push_back({o, C, cornerPoint(BOX, C).distance(mouse)});
    }

    if (nearby.size() >= 3) {
        // junction: lead with the window whose corner is closest
        const auto LEAD = std::ranges::min_element(nearby, {}, &SNear::cornerDist);
        d.target        = LEAD->w->layoutTarget();
        d.corner        = restrict(LEAD->corner, axes);
        if (d.corner == CORNER_NONE) {
            d.kind = DECIDE_NOTHING;
            return d;
        }
        d.kind = DECIDE_GRAB;

        // everyone else with a corner on the same junction follows
        const Vector2D LEADPT = cornerPoint(LEAD->w->getWindowMainSurfaceBox(), LEAD->corner);
        const Vector2D LEADTP = cornerPoint(d.target->position(), LEAD->corner);
        for (const auto& n : nearby) {
            if (n.w == LEAD->w)
                continue;
            if (cornerPoint(n.w->getWindowMainSurfaceBox(), n.corner).distance(LEADPT) > RADIUS)
                continue;
            const auto T = n.w->layoutTarget();
            if (T == d.target)
                continue;
            d.followers.push_back({T, n.corner, cornerPoint(T->position(), n.corner) - LEADTP});
        }
        return d;
    }

    // plain edge: which side of the window was pressed?
    const double OVER_L = REAL.x - mouse.x, OVER_R = mouse.x - (REAL.x + REAL.w);
    const double OVER_T = REAL.y - mouse.y, OVER_B = mouse.y - (REAL.y + REAL.h);

    eRectCorner  edge;
    if (std::max(OVER_L, OVER_R) >= std::max(OVER_T, OVER_B))
        edge = OVER_L > OVER_R ? CORNER_LEFT : CORNER_RIGHT;
    else
        edge = OVER_T > OVER_B ? CORNER_TOP : CORNER_BOTTOM;

    d.corner = restrict(edge, axes);
    d.kind   = (d.corner == CORNER_NONE || !edgeHasNeighbour(w, edge, mouse)) ? DECIDE_NOTHING : DECIDE_GRAB;
    return d;
}

// ---- hooks ----
static void clearDrag() {
    g_drag.target.reset();
    g_drag.corner = CORNER_NONE;
    g_drag.axes   = AXIS_XY;
    g_drag.followers.clear();
}

static bool startMove(const SP<ITarget>& target);
static void cancelMove();

static void hkBeginDragTarget(void* thisptr, SP<ITarget> target, eMouseBindMode mode, std::optional<eRectCorner> forcedEdge, bool exclusiveDeviceGrab) {
    const auto ORIGINAL = (beginDragFn)g_beginHook->m_original;

    clearDrag();

    if (mode == MBIND_MOVE && target && startMove(target)) {
        ORIGINAL(thisptr, target, mode, forcedEdge, exclusiveDeviceGrab);
        if (!g_layoutManager->dragController()->target())
            cancelMove(); // the drag controller refused it
        return;
    }

    if (mode != MBIND_RESIZE || forcedEdge.has_value() || !target) {
        ORIGINAL(thisptr, target, mode, forcedEdge, exclusiveDeviceGrab);
        return;
    }

    auto d = decide(target->window(), g_pInputManager->getMouseCoordsInternal());

    if (d.kind == DECIDE_STOCK) {
        ORIGINAL(thisptr, target, mode, forcedEdge, exclusiveDeviceGrab);
        return;
    }

    if (d.kind == DECIDE_NOTHING)
        return; // nothing to resize from here: no drag

    g_drag.target    = d.target;
    g_drag.corner    = d.corner;
    g_drag.axes      = axesOf(d.corner);
    g_drag.followers = std::move(d.followers);

    ORIGINAL(thisptr, d.target, mode, d.corner, exclusiveDeviceGrab);
}

// one resize step, visible to take() while the layout handles it
static void applyResize(void* thisptr, const Vector2D& delta, const SP<ITarget>& target, eRectCorner corner) {
    const auto ORIGINAL = (resizeFn)g_resizeHook->m_original;

    const auto WINDOW = target ? target->window() : nullptr;
    if (WINDOW && !target->floating()) {
        g_current.active  = true;
        g_current.address = std::format("0x{:x}", rc<uintptr_t>(WINDOW.get()));
        g_current.dx      = delta.x;
        g_current.dy      = delta.y;
        g_current.edges   = sc<int>(corner);
    }

    ORIGINAL(thisptr, delta, target, corner);

    g_current.active = false;
}

// Is there a tiled window just beyond this whole edge of `w` (anywhere along it)?
static bool sideHasNeighbour(const PHLWINDOW& w, eRectCorner edge) {
    constexpr double REACH = 48;
    const CBox       B = w->getWindowMainSurfaceBox();
    CBox             probe;
    if (edge == CORNER_LEFT)
        probe = {B.x - REACH, B.y + 1, REACH, B.h - 2};
    else if (edge == CORNER_RIGHT)
        probe = {B.x + B.w, B.y + 1, REACH, B.h - 2};
    else if (edge == CORNER_TOP)
        probe = {B.x + 1, B.y - REACH, B.w - 2, REACH};
    else
        probe = {B.x + 1, B.y + B.h, B.w - 2, REACH};

    for (const auto& o : Desktop::viewState()->windows()) {
        if (o == w || !tiledOn(o, w->m_workspace))
            continue;
        if (overlaps(o->getWindowMainSurfaceBox(), probe))
            return true;
    }
    return false;
}

// A keyboard resize of a window in dwindle or main-and-stack: flip the parts of `delta`
// whose divider sits on the window's near side (a neighbour on the left / top and none on
// the right / bottom), so a positive x / y always grows the window.
static Vector2D growFocused(const SP<ITarget>& target, Vector2D delta) {
    if (!target || target->floating() || target->isPseudo() || !target->space())
        return delta;

    const auto ALGO  = target->space()->algorithm();
    const auto TILED = ALGO ? ALGO->tiledAlgo().get() : nullptr;
    if (!dynamic_cast<Layout::Tiled::CDwindleAlgorithm*>(TILED))
        return delta; // the Lua layouts already grow the window (layouts.lua); main-and-stack: masterKeyboard()

    // dwindle moves the first split above the window in each direction, growing that split's
    // first child: flip when the window sits in the second one.
    if (auto* dwindle = dynamic_cast<Layout::Tiled::CDwindleAlgorithm*>(TILED)) {
        SP<Layout::Tiled::SDwindleNodeData> node;
        for (const auto& n : dwindle->*exposed(SDwindleNodesTag{})) {
            if (n && !n->isNode && n->pTarget.lock() == target) {
                node = n;
                break;
            }
        }
        if (!node)
            return delta;
        bool doneX = false, doneY = false;
        for (auto cur = node; cur && !(doneX && doneY);) {
            const auto PARENT = cur->pParent.lock();
            if (!PARENT)
                break;
            const bool SECOND = PARENT->children[1].lock() == cur;
            if (PARENT->splitTop && !doneY) {
                if (SECOND)
                    delta.y = -delta.y;
                doneY = true;
            } else if (!PARENT->splitTop && !doneX) {
                if (SECOND)
                    delta.x = -delta.x;
                doneX = true;
            }
            cur = PARENT;
        }
        return delta;
    }

    return delta;
}

// A keyboard resize in main-and-stack. Hyprland's own handling decides by whether the
// window touches the screen edge, which the outer gap defeats (the last window in a stack
// could not grow, the centred layout's side columns went the wrong way). Here:
//   along the main / stack split: the main area's share moves (wider main window = more
//     main area; wider stack window = less), whatever the orientation;
//   along a column: the edge toward a neighbour moves, as if that edge were dragged.
static void masterKeyboard(void* thisptr, Layout::Tiled::CMasterAlgorithm* master, const SP<ITarget>& target, const Vector2D& delta) {
    auto&                               nodes = master->*exposed(SMasterNodesTag{});
    SP<Layout::Tiled::SMasterNodeData> node;
    for (const auto& n : nodes) {
        if (n && n->pTarget.lock() == target) {
            node = n;
            break;
        }
    }
    const auto W   = target->window();
    const auto MON = target->workspace() ? target->workspace()->m_monitor.lock() : nullptr;
    if (!node || !W || !MON) {
        applyResize(thisptr, delta, target, CORNER_NONE);
        return;
    }

    // which axis separates main and stack: look at any window of the other group
    std::optional<bool> sideBySide;
    const CBox          A = W->getWindowMainSurfaceBox();
    for (const auto& n : nodes) {
        if (!n || n->isMaster == node->isMaster)
            continue;
        const auto T = n->pTarget.lock();
        const auto O = T ? T->window() : nullptr;
        if (!O)
            continue;
        const CBox B = O->getWindowMainSurfaceBox();
        sideBySide   = A.y < B.y + B.h && B.y < A.y + A.h;
        break;
    }

    const CBox WORK  = MON->logicalBoxMinusReserved();
    double     mainD = 0, crossD = 0;
    if (sideBySide) {
        mainD  = *sideBySide ? delta.x : delta.y;
        crossD = *sideBySide ? delta.y : delta.x;
    } else
        crossD = std::abs(delta.x) > std::abs(delta.y) ? delta.x : delta.y; // only one group: nothing to share

    if (mainD != 0) {
        const double STEP = mainD / std::max(1.0, *sideBySide ? WORK.w : WORK.h) * (node->isMaster ? 1 : -1);
        for (auto& n : nodes) {
            if (n && n->isMaster)
                n->percMaster = std::clamp(n->percMaster + STEP, 0.05, 0.95);
        }
    }

    if (crossD != 0) {
        const bool        COLUMN_IS_VERTICAL = sideBySide.value_or(std::abs(delta.y) >= std::abs(delta.x));
        const eRectCorner AFTER = COLUMN_IS_VERTICAL ? CORNER_BOTTOM : CORNER_RIGHT, BEFORE = COLUMN_IS_VERTICAL ? CORNER_TOP : CORNER_LEFT;
        eRectCorner       edge  = CORNER_NONE;
        double            d     = crossD;
        if (sideHasNeighbour(W, AFTER))
            edge = AFTER;
        else if (sideHasNeighbour(W, BEFORE)) {
            edge = BEFORE;
            d    = -crossD;
        }
        if (edge != CORNER_NONE) {
            applyResize(thisptr, COLUMN_IS_VERTICAL ? Vector2D{0.0, d} : Vector2D{d, 0.0}, target, edge);
            return; // that recalculates
        }
    }

    master->recalculate();
}

static void hkResizeTarget(void* thisptr, const Vector2D& delta, SP<ITarget> target, eRectCorner corner) {
    const auto LEADER  = g_drag.target.lock();
    const auto DRAGGED = g_layoutManager->dragController()->target();

    if (!DRAGGED) { // keyboard or dispatcher resize
        if (LEADER)
            clearDrag();
        const auto SPACE = target && !target->floating() && !target->isPseudo() ? target->space() : nullptr;
        const auto ALGO  = SPACE ? SPACE->algorithm() : nullptr;
        auto*      MASTER = ALGO ? dynamic_cast<Layout::Tiled::CMasterAlgorithm*>(ALGO->tiledAlgo().get()) : nullptr;
        if (MASTER && corner == CORNER_NONE)
            masterKeyboard(thisptr, MASTER, target, delta);
        else
            applyResize(thisptr, corner == CORNER_NONE ? growFocused(target, delta) : delta, target, corner);
        return;
    }

    if (LEADER && (!DRAGGED || DRAGGED != LEADER)) // that drag is over; this is some other resize
        clearDrag();

    if (!LEADER || !DRAGGED || DRAGGED != LEADER || target != LEADER) {
        applyResize(thisptr, delta, target, corner);
        return;
    }

    const Vector2D MASKED = {(g_drag.axes & AXIS_X) ? delta.x : 0.0, (g_drag.axes & AXIS_Y) ? delta.y : 0.0};
    applyResize(thisptr, MASKED, target, corner);

    // keep every corner that met at the junction on the junction
    for (const auto& f : g_drag.followers) {
        const auto T = f.target.lock();
        if (!T || T->floating() || T->space() != LEADER->space())
            continue;

        for (const bool horizontal : {true, false}) {
            const Vector2D WANT = cornerPoint(LEADER->position(), g_drag.corner) + f.offset;
            const Vector2D HAVE = cornerPoint(T->position(), f.corner);
            const Vector2D ERR  = horizontal ? Vector2D{WANT.x - HAVE.x, 0.0} : Vector2D{0.0, WANT.y - HAVE.y};

            if (std::abs(ERR.x) + std::abs(ERR.y) < 1.0 || !(g_drag.axes & (horizontal ? AXIS_X : AXIS_Y)))
                continue;

            applyResize(thisptr, ERR, T, restrict(f.corner, horizontal ? AXIS_X : AXIS_Y));
        }
    }
}

static const char* shapeFor(eRectCorner c) {
    switch (sc<int>(c)) {
        case CORNER_TOPLEFT: return "top_left_corner";
        case CORNER_TOPRIGHT: return "top_right_corner";
        case CORNER_BOTTOMLEFT: return "bottom_left_corner";
        case CORNER_BOTTOMRIGHT: return "bottom_right_corner";
        case CORNER_TOP: return "top_side";
        case CORNER_BOTTOM: return "bottom_side";
        case CORNER_LEFT: return "left_side";
        case CORNER_RIGHT: return "right_side";
        default: return nullptr;
    }
}

static void hkSetCursorIconOnBorder(void* thisptr, PHLWINDOW w) {
    ((cursorFn)g_cursorHook->m_original)(thisptr, w);

    // Hyprland decided there is a border icon to show here; make it the one a press would act on.
    if (g_pInputManager.get()->*exposed(SBorderIconTag{}) == BORDERICON_NONE || g_layoutManager->dragController()->target() || !w)
        return;

    const auto MOUSE = g_pInputManager->getMouseCoordsInternal();
    if (w->getWindowMainSurfaceBox().containsPoint(MOUSE))
        return; // rounded-corner area: a click there goes to the stock corner handling

    const auto D = decide(w, MOUSE);
    if (D.kind == DECIDE_STOCK)
        return;

    const char* SHAPE = D.kind == DECIDE_GRAB ? shapeFor(D.corner) : nullptr;
    if (SHAPE)
        Pointer::Cursor::overrideController->setOverride(SHAPE, Pointer::Cursor::CURSOR_OVERRIDE_WINDOW_EDGE);
    else
        Pointer::Cursor::overrideController->unsetOverride(Pointer::Cursor::CURSOR_OVERRIDE_WINDOW_EDGE);

    // Hyprland skips its update when its direction is unchanged; make sure the next one is not skipped.
    g_pInputManager.get()->*exposed(SBorderIconTag{}) = sc<eBorderIconDirection>(0xFF);
}


// ---- moving a tiled window by dragging it (Super + left button, or a title drag) ----
// Stock Hyprland floats the window as soon as it moves, the rest of the layout closes up at
// once, and on release it is tiled again near the pointer: you see the result only after
// letting go. Here the layout stays as it is for the whole drag, the window you hold is
// dimmed in its place, and a highlighted box shows where it will go:
//   - over another window's centre: the two swap places (every layout);
//   - over another window's edge band (dwindle only): that window is split on that side
//     and the dragged window goes into that half;
//   - at the very edge of the desktop (dwindle only): it takes that whole side;
//   - over a window on another monitor's desktop: it moves there (as stock);
//   - over itself, a floating window or nothing: it stays where it was.
// A gap between windows counts as the nearest window, so the box never blinks out on the
// way across. The orange box is where the held window goes; a white frame is where the
// window it displaces goes. Esc while holding cancels: letting go then changes nothing.
// Letting go does what the box showed. Main-and-stack and the Lua layouts swap only;
// a desktop whose layout has axes "" (deck) keeps stock dragging.

enum eDrop : uint8_t {
    DROP_NONE,  // nothing happens
    DROP_STAY,  // back over its own place
    DROP_SWAP,  // swap with `other`
    DROP_SPLIT, // dwindle: split `other` on side `dir`
    DROP_EDGE,  // dwindle: the whole `dir` side of the desktop
    DROP_AWAY,  // onto another monitor's desktop
};

static struct {
    bool              active = false;
    bool              moved  = false;
    bool              cancelled = false; // Esc pressed: show nothing, drop nothing
    WP<ITarget>       target;
    Vector2D          start;
    CBox              origin; // the held window's box
    eDrop             kind = DROP_NONE;
    WP<ITarget>       other;
    Math::eDirection  dir = Math::DIRECTION_DEFAULT;
    CBox              preview; // where the held window goes
    CBox              rest;    // where the displaced window goes (white frame)
    PHLWORKSPACEREF   away;
    Vector2D          point;
} g_move;

static bool g_escSwallowed = false; // the Esc press was ours: swallow its release too

static CFunctionHook* g_moveMouseHook = nullptr;
static CFunctionHook* g_endDragHook   = nullptr;
static CFunctionHook* g_updateHook    = nullptr;
static Hyprutils::Signal::CHyprSignalListener g_renderListener;
static Hyprutils::Signal::CHyprSignalListener g_keyListener;

using moveMouseFn = void (*)(void*, const Vector2D&);
using endDragFn   = bool (*)(void*);
using updateFn    = bool (*)(void*);

static Layout::Tiled::CDwindleAlgorithm* dwindleOf(const SP<ITarget>& t) {
    if (!t || !t->space())
        return nullptr;
    const auto ALGO = t->space()->algorithm();
    return ALGO ? dynamic_cast<Layout::Tiled::CDwindleAlgorithm*>(ALGO->tiledAlgo().get()) : nullptr;
}

static SP<Layout::Tiled::SDwindleNodeData> nodeOf(Layout::Tiled::CDwindleAlgorithm* dw, const SP<ITarget>& t) {
    for (const auto& n : dw->*exposed(SDwindleNodesTag{})) {
        if (n && !n->isNode && n->pTarget.lock() == t)
            return n;
    }
    return nullptr;
}

// can this drag be done the preview way?
static bool moveSupported(const SP<ITarget>& t) {
    if (!t || t->floating() || !t->window() || !t->space())
        return false;
    const auto W  = t->window();
    const auto WS = W->m_workspace;
    if (!WS || Fullscreen::controller()->hasFullscreen(WS))
        return false;
    if (const auto ID = WS->numberedID()) {
        if (const auto it = g_axes.find(sc<int64_t>(*ID)); it != g_axes.end() && it->second == 0)
            return false; // deck: no slots to drop into
    }
    return true;
}

// where the window `h` (a dwindle leaf) will be once the held window's leaf is taken out:
// its sibling's subtree stretches over their parent's box
static CBox boxAfterRemoval(Layout::Tiled::CDwindleAlgorithm* dw, const SP<ITarget>& held, const SP<ITarget>& h) {
    const auto N  = nodeOf(dw, held);
    const auto HN = nodeOf(dw, h);
    if (!N || !HN)
        return h->position();
    const auto P = N->pParent.lock();
    if (!P)
        return HN->box;
    const auto S = (P->children[0].lock() == N ? P->children[1] : P->children[0]).lock();
    if (!S || S->box.w <= 0 || S->box.h <= 0)
        return HN->box;
    bool inside = false;
    for (auto n = HN; n; n = n->pParent.lock()) {
        if (n == S) {
            inside = true;
            break;
        }
    }
    if (!inside)
        return HN->box;
    const double SX = P->box.w / S->box.w, SY = P->box.h / S->box.h;
    return CBox{P->box.x + (HN->box.x - S->box.x) * SX, P->box.y + (HN->box.y - S->box.y) * SY, HN->box.w * SX, HN->box.h * SY};
}

static CBox half(const CBox& b, Math::eDirection d) {
    switch (d) {
        case Math::DIRECTION_LEFT: return {b.x, b.y, b.w / 2, b.h};
        case Math::DIRECTION_RIGHT: return {b.x + b.w / 2, b.y, b.w / 2, b.h};
        case Math::DIRECTION_UP: return {b.x, b.y, b.w, b.h / 2};
        case Math::DIRECTION_DOWN: return {b.x, b.y + b.h / 2, b.w, b.h / 2};
        default: return b;
    }
}

static Math::eDirection opposite(Math::eDirection d) {
    switch (d) {
        case Math::DIRECTION_LEFT: return Math::DIRECTION_RIGHT;
        case Math::DIRECTION_RIGHT: return Math::DIRECTION_LEFT;
        case Math::DIRECTION_UP: return Math::DIRECTION_DOWN;
        case Math::DIRECTION_DOWN: return Math::DIRECTION_UP;
        default: return d;
    }
}

// the tiled window of `ws` nearest the pointer, if one is within `reach` (a gap or a border)
static PHLWINDOW nearestTiled(const PHLWORKSPACE& ws, const Vector2D& mouse, double reach) {
    PHLWINDOW best;
    double    bestD = reach;
    for (const auto& o : Desktop::viewState()->windows()) {
        if (!tiledOn(o, ws))
            continue;
        const double D = distToBox(o->layoutTarget()->position(), mouse);
        if (D <= bestD) {
            bestD = D;
            best  = o;
        }
    }
    return best;
}

static void decideDrop(const Vector2D& mouse) {
    const auto HELD = g_move.target.lock();
    g_move.kind     = DROP_NONE;
    g_move.other.reset();
    g_move.away.reset();
    g_move.dir     = Math::DIRECTION_DEFAULT;
    g_move.preview = {};
    g_move.rest    = {};
    g_move.point   = mouse;
    if (!HELD || !HELD->window() || g_move.cancelled)
        return;

    const auto MYWS  = HELD->window()->m_workspace;
    auto*      DW    = dwindleOf(HELD);
    const auto MON   = State::monitorState()->query().vec(mouse).run();
    const bool MINE  = MON && (MON->m_activeWorkspace == MYWS || MON->m_activeSpecialWorkspace == MYWS);

    // dwindle, its own monitor, pressed against an edge (or over the bar): that whole side
    if (DW && MINE && HELD->space()) {
        bool others = false;
        for (const auto& o : Desktop::viewState()->windows())
            others = others || (o != HELD->window() && tiledOn(o, MYWS));
        const CBox   WA   = HELD->space()->workArea();
        constexpr double EDGE = 32;
        const double L = mouse.x - WA.x, R = WA.x + WA.w - mouse.x, T = mouse.y - WA.y, B = WA.y + WA.h - mouse.y;
        const double NEAREST = std::min({L, R, T, B});
        if (others && NEAREST < EDGE) {
            g_move.kind    = DROP_EDGE;
            g_move.dir     = NEAREST == L ? Math::DIRECTION_LEFT : NEAREST == R ? Math::DIRECTION_RIGHT : NEAREST == T ? Math::DIRECTION_UP : Math::DIRECTION_DOWN;
            g_move.preview = half(WA, g_move.dir);
            g_move.rest    = half(WA, opposite(g_move.dir));
            return;
        }
    }

    auto HIT = Desktop::viewState()->hitTest().windowAt(mouse, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::SKIP_FULLSCREEN_PRIORITY);
    if (HIT && (!HIT->layoutTarget() || HIT->layoutTarget()->floating() || !HIT->m_workspace))
        HIT.reset();
    if (!HIT && MINE)
        HIT = nearestTiled(MYWS, mouse, 64); // in a gap: the window beside it

    if (!HIT) {
        // an empty desktop on another monitor
        if (MON && MON->m_activeWorkspace && MON->m_activeWorkspace != MYWS && !nearestTiled(MON->m_activeWorkspace, mouse, 0)) {
            g_move.kind    = DROP_AWAY;
            g_move.away    = MON->m_activeWorkspace;
            g_move.preview = MON->m_activeWorkspace->space()->workArea();
        }
        return;
    }

    const auto OTHER = HIT->layoutTarget();
    if (OTHER == HELD) {
        g_move.kind    = DROP_STAY;
        g_move.preview = g_move.origin;
        return;
    }
    if (HIT->m_workspace != MYWS) {
        g_move.kind    = DROP_AWAY;
        g_move.away    = HIT->m_workspace;
        g_move.other   = OTHER;
        g_move.preview = OTHER->position();
        return;
    }

    g_move.other     = OTHER;
    const CBox B     = OTHER->position();
    const double U   = B.w > 0 ? (mouse.x - B.x) / B.w - 0.5 : 0, V = B.h > 0 ? (mouse.y - B.y) / B.h - 0.5 : 0;
    const bool CENTRE = std::abs(U) < 0.2 && std::abs(V) < 0.2;

    if (!DW || CENTRE) {
        g_move.kind    = DROP_SWAP;
        g_move.preview = B;
        g_move.rest    = g_move.origin;
        return;
    }

    g_move.kind = DROP_SPLIT;
    if (std::abs(U) > std::abs(V))
        g_move.dir = U < 0 ? Math::DIRECTION_LEFT : Math::DIRECTION_RIGHT;
    else
        g_move.dir = V < 0 ? Math::DIRECTION_UP : Math::DIRECTION_DOWN;
    const CBox AFTER = boxAfterRemoval(DW, HELD, OTHER);
    g_move.preview   = half(AFTER, g_move.dir);
    g_move.rest      = half(AFTER, opposite(g_move.dir));
}


static void damageMove() {
    for (const auto& b : {g_move.origin, g_move.preview, g_move.rest}) {
        if (b.w > 0 && b.h > 0)
            g_pHyprRenderer->damageBox(b.copy().expand(8));
    }
}

static void addRect(Render::CRenderContext& ctx, const PHLMONITOR& mon, CBox b, const CHyprColor& c, int round) {
    if (b.w <= 0 || b.h <= 0)
        return;
    b.translate(-mon->m_position).scale(mon->m_scale).round();
    CRectPassElement::SRectData d;
    d.box   = b;
    d.color = c;
    d.round = round;
    Render::IHyprRenderer::addPassElement(ctx, makeUnique<CRectPassElement>(d));
}

static void addFrame(Render::CRenderContext& ctx, const PHLMONITOR& mon, const CBox& b, const CHyprColor& c, double t) {
    addRect(ctx, mon, {b.x, b.y, b.w, t}, c, 0);
    addRect(ctx, mon, {b.x, b.y + b.h - t, b.w, t}, c, 0);
    addRect(ctx, mon, {b.x, b.y + t, t, b.h - 2 * t}, c, 0);
    addRect(ctx, mon, {b.x + b.w - t, b.y + t, t, b.h - 2 * t}, c, 0);
}

static void renderMove(const Event::SRenderStageEvent& e) {
    if (e.stage != RENDER_POST_WINDOWS || !g_move.active || !g_move.moved || g_move.cancelled || !e.context || !e.monitor)
        return;
    auto&      ctx = e.context->get();
    const auto MON = e.monitor;

    const CHyprColor ACCENT{0.961, 0.400, 0.0, 1.0}; // Clemson orange, as the rice
    // the held window: dimmed in its place
    addRect(ctx, MON, g_move.origin, CHyprColor{0, 0, 0, g_move.kind == DROP_STAY ? 0.15 : 0.45}, 0);
    // where the window it displaces goes
    addFrame(ctx, MON, g_move.rest.copy().expand(-6), CHyprColor{1, 1, 1, 0.55}, 2);

    if (g_move.kind == DROP_NONE)
        return;
    const CBox P = g_move.preview.copy().expand(-6);
    addRect(ctx, MON, P, CHyprColor{ACCENT.r, ACCENT.g, ACCENT.b, g_move.kind == DROP_STAY ? 0.10 : 0.22}, 0);
    addFrame(ctx, MON, P, CHyprColor{ACCENT.r, ACCENT.g, ACCENT.b, 0.95}, 3);
}

static void hkMoveMouse(void* thisptr, const Vector2D& pos) {
    const auto ORIGINAL = (moveMouseFn)g_moveMouseHook->m_original;
    if (!g_move.active) {
        ORIGINAL(thisptr, pos);
        return;
    }
    const auto HELD = g_move.target.lock();
    if (!HELD || !validMapped(HELD->window())) {
        g_layoutManager->endDragTarget();
        return;
    }
    if (!g_move.moved) {
        if (pos.distance(g_move.start) < 12)
            return;
        g_move.moved = true;
    }
    damageMove(); // where the boxes were
    decideDrop(pos);
    damageMove(); // and where they are now
}

// dwindle: take `held` out and put it beside `other`'s leaf on side `dir`, or (no `other`)
// beside the whole tree, so it gets that side of the desktop
static void dropSplit(const SP<ITarget>& held, const SP<ITarget>& other, Math::eDirection dir) {
    auto* dw = dwindleOf(held);
    if (!dw || (other && !nodeOf(dw, other)) || !nodeOf(dw, held))
        return;
    dw->removeTarget(held);
    auto& nodes = dw->*exposed(SDwindleNodesTag{});
    SP<Layout::Tiled::SDwindleNodeData> H;
    if (other)
        H = nodeOf(dw, other);
    else {
        for (const auto& n : nodes) {
            if (n && !n->pParent.lock()) {
                H = n;
                break;
            }
        }
    }
    if (!H) {
        dw->newTarget(held); // nothing to sit beside after all: put it back
        return;
    }

    auto  PNODE   = makeShared<Layout::Tiled::SDwindleNodeData>();
    PNODE->self   = PNODE;
    PNODE->pTarget = held;
    PNODE->isNode = false;
    nodes.push_back(PNODE);

    auto NP = makeShared<Layout::Tiled::SDwindleNodeData>();
    NP->self = NP;
    nodes.push_back(NP);
    static auto PRATIO = CConfigValue<Config::FLOAT>("dwindle:default_split_ratio");
    const bool  VERT   = dir == Math::DIRECTION_UP || dir == Math::DIRECTION_DOWN;
    NP->box            = H->box;
    NP->pParent        = H->pParent;
    NP->isNode         = true;
    NP->splitRatio     = std::clamp(*PRATIO, 0.1F, 1.9F);
    NP->splitTop       = VERT;
    const bool FIRST   = dir == Math::DIRECTION_UP || dir == Math::DIRECTION_LEFT;
    NP->children[0]    = FIRST ? PNODE : H;
    NP->children[1]    = FIRST ? H : PNODE;
    if (const auto PP = H->pParent.lock()) {
        if (PP->children[0].lock() == H)
            PP->children[0] = NP;
        else
            PP->children[1] = NP;
    }
    H->pParent     = NP;
    PNODE->pParent = NP;
    NP->recalcSizePosRecursive(false, !VERT, VERT);
    dw->recalculate();
}

static bool hkEndDragTarget(void* thisptr) {
    const auto ORIGINAL = (endDragFn)g_endDragHook->m_original;
    if (!g_move.active)
        return ORIGINAL(thisptr);

    damageMove();
    const auto M  = g_move;
    g_move.active = false;
    g_move.moved  = false;
    g_move.target.reset();
    g_move.other.reset();
    g_move.away.reset();

    const bool R = ORIGINAL(thisptr);

    const auto HELD  = M.target.lock();
    const auto OTHER = M.other.lock();
    if (!M.moved || M.cancelled || !HELD || !validMapped(HELD->window()))
        return R;

    switch (M.kind) {
        case DROP_SWAP:
            if (OTHER && validMapped(OTHER->window()))
                HELD->swap(OTHER);
            break;
        case DROP_SPLIT:
            if (OTHER && validMapped(OTHER->window()))
                dropSplit(HELD, OTHER, M.dir);
            break;
        case DROP_EDGE: dropSplit(HELD, nullptr, M.dir); break;
        case DROP_AWAY:
            if (const auto WS = M.away.lock(); WS && WS->space())
                HELD->assignToSpace(WS->space(), M.point);
            break;
        default: break;
    }
    if (HELD->space())
        HELD->space()->recalculate();
    return R;
}

// while our drag runs, the drag controller must not float the window
static bool hkUpdateDragWindow(void* thisptr) {
    const auto ORIGINAL = (updateFn)g_updateHook->m_original;
    if (g_move.active)
        return false;
    return ORIGINAL(thisptr);
}

static void cancelMove() {
    g_move = {};
}

// Esc while holding a window: forget the drop (the button is still down; letting go then
// does nothing). The key never reaches the window underneath.
static void onKey(const IKeyboard::SKeyEvent& e, Event::SCallbackInfo& info) {
    constexpr uint32_t KEY_ESCAPE = 1; // evdev
    if (e.keycode != KEY_ESCAPE)
        return;
    if (e.state == WL_KEYBOARD_KEY_STATE_PRESSED && g_move.active && !g_move.cancelled) {
        damageMove();
        g_move.cancelled = true;
        g_move.kind      = DROP_NONE;
        g_escSwallowed   = true;
        info.cancelled   = true;
    } else if (e.state == WL_KEYBOARD_KEY_STATE_RELEASED && g_escSwallowed) {
        g_escSwallowed = false;
        info.cancelled = true;
    }
}

static bool startMove(const SP<ITarget>& target) {
    if (!g_moveMouseHook || !moveSupported(target))
        return false;
    g_move        = {};
    g_move.active = true;
    g_move.target = target;
    g_move.start  = g_pInputManager->getMouseCoordsInternal();
    g_move.origin = target->position();
    return true;
}

// ---- Lua ----
static int luaTake(lua_State* L) {
    if (!g_current.active)
        return 0;

    g_current.active = false; // one layout pass consumes it
    lua_pushstring(L, g_current.address.c_str());
    lua_pushnumber(L, g_current.dx);
    lua_pushnumber(L, g_current.dy);
    lua_pushinteger(L, g_current.edges);
    return 4;
}

static int luaAxes(lua_State* L) {
    const auto        WS = sc<int64_t>(luaL_checkinteger(L, 1));
    const std::string S  = luaL_optstring(L, 2, "xy");
    const uint8_t     A  = (S.contains('x') ? AXIS_X : 0) | (S.contains('y') ? AXIS_Y : 0);

    if (A == AXIS_XY)
        g_axes.erase(WS);
    else
        g_axes[WS] = A;
    return 0;
}

static int luaReset(lua_State* L) {
    const char* kind = "none";

    const auto  MONITOR = Desktop::focusState()->monitor();
    const auto  WS      = MONITOR ? (MONITOR->m_activeSpecialWorkspace ? MONITOR->m_activeSpecialWorkspace : MONITOR->m_activeWorkspace) : nullptr;
    const auto  SPACE   = WS ? WS->space() : nullptr;
    const auto  ALGO    = SPACE ? SPACE->algorithm() : nullptr;
    const auto  TILED   = ALGO ? ALGO->tiledAlgo().get() : nullptr;

    if (auto* dwindle = dynamic_cast<Layout::Tiled::CDwindleAlgorithm*>(TILED)) {
        static auto PRATIO = CConfigValue<Config::FLOAT>("dwindle:default_split_ratio");
        for (auto& n : dwindle->*exposed(SDwindleNodesTag{})) {
            if (n && n->isNode)
                n->splitRatio = *PRATIO;
        }
        dwindle->recalculate();
        kind = "dwindle";
    } else if (auto* master = dynamic_cast<Layout::Tiled::CMasterAlgorithm*>(TILED)) {
        static auto PMFACT = CConfigValue<Config::FLOAT>("master:mfact");
        for (auto& n : master->*exposed(SMasterNodesTag{})) {
            if (!n)
                continue;
            n->percMaster = *PMFACT;
            n->percSize   = 1.F;
        }
        master->recalculate();
        kind = "master";
    }

    lua_pushstring(L, kind);
    return 1;
}

// ---- plugin entry ----
static void* findFn(const std::string& name, const std::string& mustContain) {
    for (const auto& m : HyprlandAPI::findFunctionsByName(PHANDLE, name)) {
        if (m.demangled.contains(mustContain))
            return m.address;
    }
    return nullptr;
}

static void fail(const std::string& why) {
    HyprlandAPI::addNotification(PHANDLE, "[strict-resize] " + why, CHyprColor{1.0, 0.2, 0.2, 1.0}, 10000);
    throw std::runtime_error("[strict-resize] " + why);
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const std::string COMPOSITOR_HASH = __hyprland_api_get_hash();
    const std::string CLIENT_HASH     = __hyprland_api_get_client_hash();
    if (COMPOSITOR_HASH != CLIENT_HASH)
        fail("built for a different Hyprland version; run ~/.local/share/hypr-strict-resize/build.sh");

    g_radius = makeShared<Config::Values::CIntValue>("plugin:strictresize:junction_radius",
                                                     "how close (px) three or more tiled windows must come to the pointer for a border drag to resize in both directions", 48);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_radius);

    void* const BEGIN  = findFn("beginDragTarget", "Layout::CLayoutManager::beginDragTarget(");
    void* const RESIZE = findFn("resizeTarget", "Layout::CLayoutManager::resizeTarget(");
    void* const CURSOR = findFn("setCursorIconOnBorder", "CInputManager::setCursorIconOnBorder(");
    if (!BEGIN || !RESIZE || !CURSOR)
        fail("could not find the functions to hook");

    g_beginHook  = HyprlandAPI::createFunctionHook(PHANDLE, BEGIN, (void*)&hkBeginDragTarget);
    g_resizeHook = HyprlandAPI::createFunctionHook(PHANDLE, RESIZE, (void*)&hkResizeTarget);
    g_cursorHook = HyprlandAPI::createFunctionHook(PHANDLE, CURSOR, (void*)&hkSetCursorIconOnBorder);

    if (!g_beginHook || !g_resizeHook || !g_cursorHook || !g_beginHook->hook() || !g_resizeHook->hook() || !g_cursorHook->hook())
        fail("hooking failed");

    // moving by drag: optional, a failure here leaves resizing working
    void* const MOVEMOUSE = findFn("moveMouse", "Layout::CLayoutManager::moveMouse(");
    void* const ENDDRAG   = findFn("endDragTarget", "Layout::CLayoutManager::endDragTarget(");
    void* const UPDATE    = findFn("updateDragWindow", "CDragStateController::updateDragWindow(");
    if (MOVEMOUSE && ENDDRAG && UPDATE) {
        g_moveMouseHook = HyprlandAPI::createFunctionHook(PHANDLE, MOVEMOUSE, (void*)&hkMoveMouse);
        g_endDragHook   = HyprlandAPI::createFunctionHook(PHANDLE, ENDDRAG, (void*)&hkEndDragTarget);
        g_updateHook    = HyprlandAPI::createFunctionHook(PHANDLE, UPDATE, (void*)&hkUpdateDragWindow);
        if (!g_moveMouseHook || !g_endDragHook || !g_updateHook || !g_updateHook->hook() || !g_endDragHook->hook() || !g_moveMouseHook->hook()) {
            g_moveMouseHook = nullptr;
            HyprlandAPI::addNotification(PHANDLE, "[strict-resize] drag-to-place unavailable (hook failed); stock dragging", CHyprColor{1.0, 0.6, 0.2, 1.0}, 8000);
        } else {
            g_renderListener = Event::bus()->m_events.render.stage.listen([](const Event::SRenderStageEvent& e) { renderMove(e); });
            g_keyListener    = Event::bus()->m_events.input.keyboard.key.listen([](IKeyboard::SKeyEvent e, Event::SCallbackInfo& info) { onKey(e, info); });
        }
    }

    HyprlandAPI::addLuaFunction(PHANDLE, "strictresize", "take", luaTake);
    HyprlandAPI::addLuaFunction(PHANDLE, "strictresize", "axes", luaAxes);
    HyprlandAPI::addLuaFunction(PHANDLE, "strictresize", "reset", luaReset);

    return {"strict-resize", "Tiled-window mouse resizing that follows the pointer: one direction on edges, both at junctions", "Tim Ransom", "1.5"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_renderListener.reset();
    g_keyListener.reset();
    g_move = {};
    clearDrag();
    g_axes.clear();
}
