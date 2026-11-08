package.path = "./?.lua;./?/init.lua;" .. package.path

local ticks, shown = {}, nil
local UI = {
    nextTick = function(_, callback) ticks[#ticks + 1] = callback end,
    show = function(_, dialog) shown = dialog end,
    close = function(_, dialog) if dialog.owner then dialog.owner._shelf_popup = nil end end,
}
package.preload["ui/uimanager"] = function() return UI end
package.preload["ui/widget/buttondialog"] = function()
    return { new = function(_, data) return data end }
end
for _, name in ipairs({ "ui/widget/confirmbox", "ui/widget/pathchooser",
    "weread.lib.content", "weread.lib.logger", "weread.lib.scan", "weread.lib.protocol" }) do
    package.preload[name] = function() return {} end
end
package.preload["weread.lib.plugin_util"] = function()
    return { tr = function(text) return text end, T = function(text) return text end }
end

local Cache = require("weread.ui.cache")
local prefs = { sort_order = "default" }
local changed, flushes = 0, 0
local host = {
    shelf_filters = { reading = true, download = true },
    settings = {
        get = function() return prefs end,
        set = function() end,
        flush = function() flushes = flushes + 1 end,
    },
    saveShelfFilters = function() flushes = flushes + 1 end,
}
setmetatable(host, { __index = Cache })
local function owner()
    return { showShelfPopup = function(self, dialog)
        dialog.owner = self
        self._shelf_popup = dialog
        UI:show(dialog)
    end }
end
local function runTick()
    local tick = table.remove(ticks, 1)
    assert(tick, "missing queued action")
    tick()
end
local function changedCallback() changed = changed + 1 end

local live_sort = owner()
host:showShelfSortOptions(changedCallback, live_sort)
shown.buttons[1][1].callback()
runTick()
assert(changed == 1 and flushes == 1, "live sort action stopped working")

local stale_sort = owner()
host:showShelfSortOptions(changedCallback, stale_sort)
shown.buttons[1][1].callback()
stale_sort._shelf_closed = true
stale_sort._shelf_popup = nil
runTick()
assert(changed == 1 and flushes == 1, "closed shelf ran queued sort action")

local stale_filter = owner()
host:showShelfFilterOptions(changedCallback, stale_filter)
shown.buttons[1][1].callback()
stale_filter._shelf_popup = nil
runTick()
assert(changed == 1 and flushes == 1 and host.shelf_filters.reading == true,
    "dismissed filter popup ran its queued action")

local live_filter = owner()
host:showShelfFilterOptions(changedCallback, live_filter)
shown.buttons[2][1].callback()
runTick()
assert(changed == 2 and flushes == 2, "live filter action stopped working")

host:showShelfSortOptions(changedCallback)
shown.buttons[1][1].callback()
runTick()
assert(changed == 3 and flushes == 3, "sort action without a shelf owner changed")
host:showShelfSortOptions(changedCallback, {})
shown.buttons[1][1].callback()
runTick()
assert(changed == 4 and flushes == 4, "sort action with an untracked owner changed")
print("shelf_popup_actions_spec: passed")
