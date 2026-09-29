.pragma library

// Settings live in this plugin's entry of ~/.config/omarchy/shell.json.
// normalize() turns whatever is there into a complete, valid set.

var DEFAULTS = {
    scope: "all",              // all | workspace | monitor
    showDelay: 120,            // ms before the switcher appears; quick taps never flash it
    previews: true,            // live window previews, or app icons only
    workspaceBadges: true,     // show each window's workspace on its card
    includeSpecial: true       // include scratchpad / special-workspace windows
};

var SCOPE_OPTIONS = [
    { value: "all", label: "All workspaces" },
    { value: "workspace", label: "Current workspace" },
    { value: "monitor", label: "Current monitor" }
];

var DELAY_OPTIONS = [
    { value: "0", label: "Instantly" },
    { value: "120", label: "120 ms" },
    { value: "250", label: "250 ms" },
    { value: "400", label: "400 ms" }
];

var STYLE_OPTIONS = [
    { value: "previews", label: "Live previews" },
    { value: "icons", label: "App icons" }
];

function scopeLabel(scope) {
    for (var i = 0; i < SCOPE_OPTIONS.length; i++)
        if (SCOPE_OPTIONS[i].value === scope)
            return SCOPE_OPTIONS[i].label;
    return "";
}

function normalize(raw) {
    var entry = raw && typeof raw === "object" ? raw : {};
    var scope = String(entry.scope || DEFAULTS.scope);
    if (scope !== "all" && scope !== "workspace" && scope !== "monitor")
        scope = DEFAULTS.scope;
    var delay = Number(entry.showDelay);
    delay = isFinite(delay) ? Math.max(0, Math.min(1000, Math.round(delay))) : DEFAULTS.showDelay;
    return {
        scope: scope,
        showDelay: delay,
        previews: entry.previews !== false,
        workspaceBadges: entry.workspaceBadges !== false,
        includeSpecial: entry.includeSpecial !== false
    };
}

function entryFromConfig(config, pluginId) {
    var plugins = config && Array.isArray(config.plugins) ? config.plugins : [];
    for (var i = 0; i < plugins.length; i++)
        if (plugins[i] && String(plugins[i].id || "") === pluginId)
            return plugins[i];
    return null;
}

if (typeof module !== "undefined")
    module.exports = {
        DEFAULTS: DEFAULTS,
        normalize: normalize,
        entryFromConfig: entryFromConfig,
        scopeLabel: scopeLabel
    };
