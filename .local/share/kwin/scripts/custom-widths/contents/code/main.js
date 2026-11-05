// Width rules for Karousel, per desktop: one tiled window fills the screen, a
// second makes both 50%, and later windows open at 50% and scroll sideways.
// Acts only when a desktop's tiled window count changes, so widths set by hand stick.
// Meta+M switches a tiled window between full width and its previous width.
// Karousel follows any width set here, and keeps tiled windows below the rest.
// New windows stay invisible until sized, so they don't visibly snap.

const GAP = 6; // same as Karousel's gaps in ~/.setup/install.sh

// Give the app a moment to redraw at its new size.
const revealTimer = new QTimer();
revealTimer.singleShot = true;
revealTimer.interval = 60;

const counts = {};
let added = [];
let hidden = [];
let floated = [];
let tiledBefore = [];
const previousWidth = new Map();

// Karousel also clears keepBelow on fullscreen and maximized windows, but they
// stay in the row and return to their width, so they must keep counting as tiled.
function isTiled(w) {
    if (w.keepBelow) {
        if (tiledBefore.indexOf(w) === -1) {
            tiledBefore.push(w);
        }
        return true;
    }
    const area = workspace.clientArea(KWin.MaximizeArea, w);
    const g = w.frameGeometry;
    if (w.fullScreen || (g.width >= area.width - 2 && g.height >= area.height - 2)) {
        return tiledBefore.indexOf(w) !== -1;
    }
    tiledBefore = tiledBefore.filter(function (other) { return other !== w; });
    return false;
}

function tiledOn(desktop) {
    return workspace.windowList().filter(function (w) {
        return w.normalWindow && isTiled(w) && !w.minimized
            && w.desktops.indexOf(desktop) !== -1;
    });
}

function setWidth(w, width) {
    if (!w.keepBelow) {
        return; // fullscreen or maximized: Karousel restores its column width later
    }
    const g = w.frameGeometry;
    w.frameGeometry = { x: g.x, y: g.y, width: width, height: g.height };
}

function settle() {
    try {
        const open = workspace.windowList();
        function isOpen(w) { return open.indexOf(w) !== -1; }
        added = added.filter(isOpen); // windows may have closed during the wait
        tiledBefore = tiledBefore.filter(isOpen);
        floated = floated.filter(isOpen);
        applyWidths();
    } finally {
        added = [];
        floated = [];
        revealTimer.start(); // never leave a new window invisible
    }
}

function applyWidths() {
    workspace.desktops.forEach(function (desktop) {
        const tiled = tiledOn(desktop);
        const before = counts[desktop.id] || 0;
        counts[desktop.id] = tiled.length;
        if (tiled.length === before || tiled.length === 0) {
            return;
        }
        const area = workspace.clientArea(KWin.MaximizeArea, tiled[0]);
        const full = area.width - 2 * GAP;
        const half = Math.floor((full - GAP) / 2);
        if (tiled.length === 1) {
            setWidth(tiled[0], full);
        } else if (tiled.length === 2 && before === 1) {
            tiled.forEach(function (w) { setWidth(w, half); });
        } else {
            tiled.filter(function (w) { return added.indexOf(w) !== -1; })
                .forEach(function (w) { setWidth(w, half); });
        }
    });
    added.filter(function (w) {
        // Spectacle sizes itself to the capture; others just floated by key, not by dragging.
        return isSpectacle(w) || (!w.keepBelow && !w.move && floated.indexOf(w) !== -1
            && workspace.activeWindow === w);
    }).forEach(function (w) { shrinkFloating(w, false); });
}

function reveal() {
    const open = workspace.windowList();
    hidden.forEach(function (w) {
        if (open.indexOf(w) !== -1) {
            w.opacity = 1;
        }
    });
    hidden = [];
}

revealTimer.timeout.connect(reveal);

// Group changes that arrive together.
const timer = new QTimer();
timer.singleShot = true;
timer.interval = 150; // Karousel overwrites widths set sooner than this
timer.timeout.connect(settle);

function isSpectacle(w) {
    return w.resourceClass.indexOf("spectacle") !== -1;
}

// A window floated from full width would stay a wide, short strip. Only the active
// window counts, so reloading Karousel doesn't shrink every window at once.
function shrinkFloating(w, dragged) {
    const area = workspace.clientArea(KWin.MaximizeArea, w);
    const g = w.frameGeometry;
    // Maximized windows fill the height too, except Spectacle sizing itself to a capture.
    const filled = g.height >= area.height - 2 && !isSpectacle(w);
    if (w.keepBelow || w.fullScreen || g.width < area.width * 0.7 || filled) {
        return;
    }
    const width = Math.floor(area.width * 0.6);
    const height = Math.floor(area.height * 0.75);
    const centerX = dragged ? workspace.cursorPos.x : area.x + area.width / 2;
    const left = Math.max(area.x, Math.min(centerX - width / 2, area.x + area.width - width));
    const top = dragged ? Math.max(area.y, Math.min(g.y, area.y + area.height - height))
        : area.y + (area.height - height) / 2;
    w.frameGeometry = { x: Math.round(left), y: Math.round(top), width: width, height: height };
}

// Shrink as a drag starts, not when it ends. Karousel sets a floating window's size
// right after clearing keepBelow, so this has to run once it has finished.
let justDragged = null;
const dragTimer = new QTimer();
dragTimer.singleShot = true;
dragTimer.interval = 0;
dragTimer.timeout.connect(function () {
    if (justDragged && justDragged.move) {
        shrinkFloating(justDragged, true);
    }
    justDragged = null;
});

function watch(w) {
    function changed() {
        added.push(w);
        timer.start();
    }
    w.desktopsChanged.connect(changed);
    let draggedOut = false; // pulled out of the row, not just moved while floating
    w.keepBelowChanged.connect(function () {
        if (!w.keepBelow) {
            floated.push(w);
            draggedOut = w.move;
            if (draggedOut) {
                justDragged = w;
                dragTimer.start();
            }
        }
        changed(); // Karousel has just tiled or floated it
    });
    w.interactiveMoveResizeFinished.connect(function () {
        if (draggedOut) {
            draggedOut = false;
            shrinkFloating(w, true);
        }
    });
}

workspace.windowAdded.connect(function (w) {
    if (!w.normalWindow) {
        return;
    }
    w.opacity = 0;
    hidden.push(w);
    watch(w);
    added.push(w);
    timer.start();
});
workspace.windowRemoved.connect(function (w) {
    previousWidth.delete(w);
    timer.start();
});

function toggleFullWidth() {
    const w = workspace.activeWindow;
    if (!w || !w.normalWindow || w.fullScreen) {
        return;
    }
    const area = workspace.clientArea(KWin.MaximizeArea, w);
    const g = w.frameGeometry;
    if (!w.keepBelow) { // floating, or tiled and maximized: an ordinary maximize toggle
        const filled = g.width >= area.width - 2 && g.height >= area.height - 2;
        w.setMaximize(!filled, !filled);
        return;
    }
    const full = area.width - 2 * GAP;
    if (g.width >= full - 2) {
        setWidth(w, previousWidth.get(w) || Math.floor((full - GAP) / 2));
        previousWidth.delete(w);
    } else {
        previousWidth.set(w, g.width);
        setWidth(w, full);
    }
}

registerShortcut("custom-widths-toggle-full", "Custom Widths: Toggle full width", "Meta+M", toggleFullWidth);

workspace.windowList().forEach(function (w) {
    if (w.normalWindow) {
        watch(w);
        if (w.opacity === 0) {
            w.opacity = 1; // left hidden if this script stopped mid-way
        }
    }
});
workspace.desktops.forEach(function (desktop) {
    counts[desktop.id] = tiledOn(desktop).length;
});
