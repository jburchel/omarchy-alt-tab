.pragma library

// Pure helpers for the switcher: parsing the snapshot Hyprland sends with
// the opening Alt+Tab, filtering it by scope, moving the selection, and
// fitting the cards on screen. No QML types here so tests can run under node.

var SCOPES = ["all", "workspace", "monitor"];

function normalizeAddress(value) {
    var text = String(value === undefined || value === null ? "" : value).trim().toLowerCase();
    if (!text)
        return "";
    if (text.indexOf("0x") !== 0)
        text = "0x" + text;
    return /^0x[0-9a-f]+$/.test(text) ? text : "";
}

// Payload written by hypr/omarchy-alt-tab.lua:
//   ws=<id>;mon=<name>;act=<address>;w=<address>@<ws id>@<monitor>@<flags>,...
// Windows arrive most-recently-used first (Hyprland focus_history_id order).
function parseSnapshot(text) {
    var snapshot = { workspaceId: NaN, monitor: "", active: "", windows: [] };
    var fields = String(text || "").split(";");
    for (var i = 0; i < fields.length; i++) {
        var eq = fields[i].indexOf("=");
        if (eq < 0)
            continue;
        var key = fields[i].slice(0, eq);
        var value = fields[i].slice(eq + 1);
        if (key === "ws")
            snapshot.workspaceId = value === "" ? NaN : Number(value);
        else if (key === "mon")
            snapshot.monitor = value;
        else if (key === "act")
            snapshot.active = normalizeAddress(value);
        else if (key === "w")
            snapshot.windows = parseWindows(value);
    }
    return snapshot;
}

function parseWindows(text) {
    var seen = {};
    var windows = [];
    var items = String(text || "").split(",");
    for (var i = 0; i < items.length; i++) {
        var parts = items[i].split("@");
        var address = normalizeAddress(parts[0]);
        if (!address || seen[address])
            continue;
        seen[address] = true;
        var workspaceId = Number(parts[1]);
        windows.push({
            address: address,
            workspaceId: isFinite(workspaceId) ? workspaceId : NaN,
            monitor: String(parts[2] || ""),
            pinned: String(parts[3] || "").indexOf("p") !== -1
        });
    }
    return windows;
}

function isSpecialWorkspace(workspaceId) {
    return isFinite(workspaceId) && workspaceId < 0;
}

function filterWindows(windows, scope, snapshot, includeSpecial) {
    var result = [];
    for (var i = 0; i < windows.length; i++) {
        var w = windows[i];
        if (!includeSpecial && isSpecialWorkspace(w.workspaceId))
            continue;
        if (scope === "workspace" && !(w.pinned || w.workspaceId === snapshot.workspaceId))
            continue;
        if (scope === "monitor" && w.monitor !== snapshot.monitor)
            continue;
        result.push(w);
    }
    return result;
}

function indexOfAddress(windows, address) {
    for (var i = 0; i < windows.length; i++)
        if (windows[i].address === address)
            return i;
    return -1;
}

// Like Windows: the first Alt+Tab lands on the previously used window, which
// is index 1 when the focused window heads the list. With nothing focused
// (an empty workspace) the most recent window is already a switch, so start
// at 0. Alt+Shift+Tab starts from the other end.
function initialIndex(windows, active, direction) {
    var count = windows.length;
    if (count === 0)
        return -1;
    if (direction === "prev")
        return count - 1;
    var headIsActive = active !== "" && windows[0].address === active;
    return headIsActive ? Math.min(1, count - 1) : 0;
}

function step(index, count, delta) {
    if (count <= 0)
        return -1;
    var next = (index + delta) % count;
    return next < 0 ? next + count : next;
}

function nextScope(scope) {
    var i = SCOPES.indexOf(scope);
    return SCOPES[(i + 1) % SCOPES.length];
}

// Fit `count` cards of cardWidth x cardHeight into maxWidth x maxHeight,
// shrinking uniformly (never below minScale) until the grid fits.
function layout(count, maxWidth, maxHeight, cardWidth, cardHeight, gap, minScale) {
    var floor = minScale > 0 ? minScale : 0.35;
    var scale = 1;
    var cols = 1;
    var rows = 1;
    for (var attempt = 0; attempt < 40; attempt++) {
        var w = cardWidth * scale;
        var h = cardHeight * scale;
        cols = Math.max(1, Math.min(count, Math.floor((maxWidth + gap) / (w + gap))));
        rows = Math.max(1, Math.ceil(count / cols));
        if (rows * h + (rows - 1) * gap <= maxHeight || scale <= floor)
            break;
        scale = Math.max(floor, scale * 0.92);
    }
    return { cols: cols, rows: rows, scale: scale };
}

// Chrome web apps (omarchy-launch-webapp) get a window class derived from
// their URL, e.g. chrome-mail.google.com__mail_u_0_-Profile_1, and their
// .desktop files carry no StartupWMClass. Score how well a desktop entry's
// Exec URL matches such a class: 2 = host and path, 1 = host only, 0 = no.
function webappMatch(appId, execString) {
    var cls = /^chrome-(.+?)__(.*)-(Default|Profile_\d+)$/.exec(String(appId || ""));
    var url = /https?:\/\/([^\/?#"' ]+)([^?#"' ]*)/.exec(String(execString || ""));
    if (!cls || !url)
        return 0;
    if (cls[1].toLowerCase() !== url[1].toLowerCase())
        return 0;
    var path = url[2].replace(/^\//, "").replace(/\//g, "_");
    return path !== "" && cls[2] === path ? 2 : 1;
}

if (typeof module !== "undefined")
    module.exports = {
        SCOPES: SCOPES,
        normalizeAddress: normalizeAddress,
        parseSnapshot: parseSnapshot,
        filterWindows: filterWindows,
        indexOfAddress: indexOfAddress,
        initialIndex: initialIndex,
        step: step,
        nextScope: nextScope,
        layout: layout,
        isSpecialWorkspace: isSpecialWorkspace,
        webappMatch: webappMatch
    };
