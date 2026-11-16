-- Unit tests for shared network task behavior.

package.path = "./?.lua;" .. package.path

local checks = 0

local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then
        error(string.format("%s: got %s, want %s",
            label, tostring(got), tostring(want)))
    end
end

package.preload["ui/bidi"] = function() return {} end
package.preload["ui/widget/confirmbox"] = function() return {} end
package.preload["ui/widget/infomessage"] = function() return {} end
package.preload["ui/widget/menu"] = function() return {} end
package.preload["ui/uimanager"] = function()
    return {
        scheduleIn = function(_self, _delay, callback) callback() end,
    }
end
local online = false
local linked = false
package.preload["ui/network/manager"] = function()
    return {
        isOnline = function() return online end,
        isConnected = function() return linked end,
    }
end
package.preload["weread.lib.logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end
package.preload["weread.lib.plugin_util"] = function()
    return {
        tr = function(text) return text end,
        T = function(text) return text end,
        log_error = tostring,
        display_error = tostring,
        unpack_args = function(args) return unpack(args) end,
    }
end

local Common = require("weread.ui.common")
local offline_notices = 0
local started = 0
local host = setmetatable({
    showOffline = function()
        offline_notices = offline_notices + 1
    end,
}, { __index = Common })

eq(host:runOnlineTask("automatic", function() end, nil, {
    silent_offline = true,
}), false, "silent offline task does not start")
eq(offline_notices, 0, "silent offline task does not show a notice")

eq(host:runOnlineTask("manual", function() end), false,
    "regular offline task does not start")
eq(offline_notices, 1, "regular offline task still shows a notice")

linked = true
online = false
eq(host:runOnlineTask("download", function()
    started = started + 1
end, nil, { link_only = true }), true,
    "link_only download starts from interface state without DNS")
eq(started, 1, "link_only callback ran")
eq(offline_notices, 1, "link_only success did not show an offline notice")

linked = false
eq(host:runOnlineTask("download", function()
    started = started + 1
end, nil, { link_only = true }), false,
    "link_only download stays offline when the link is down")
eq(started, 1, "offline link_only callback must not run")
eq(offline_notices, 2, "offline link_only still shows a notice")

eq(host:runOnlineTask("trusted", function()
    started = started + 1
end, nil, { skip_online_check = true }), true,
    "skip_online_check bypasses connectivity gates")
eq(started, 2, "skip_online_check callback ran")

print(string.format("common_network_spec: %d checks", checks))
