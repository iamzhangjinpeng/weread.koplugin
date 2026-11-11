package.path = "./?.lua;./?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message) end
end

local events, stats_shown, stats_fetches, shelf_fetches = {}, 0, 0, 0
local stats_modes = {}
local stats_fetch_hook
local existing_files, book_records = {}, {}
package.preload["ui/uimanager"] = function()
    return { close = function(_, view)
        events[#events + 1] = "close:" .. view.name
        if view.callbacks and view.callbacks.on_closed then view.callbacks.on_closed(view) end
    end }
end
for _, name in ipairs({
    "weread.lib.book_reviews", "weread.ui.book_reviews_view", "ui/widget/confirmbox",
    "weread.lib.content", "weread.lib.shelf_groups", "ui/widget/inputdialog",
    "ui/widget/progressbardialog", "ui/widget/textviewer", "weread.lib.protocol",
}) do
    package.preload[name] = function() return {} end
end
package.preload["weread.lib.logger"] = function() return { err = function() end } end
package.preload["weread.lib.plugin_util"] = function()
    return { tr = function(text) return text end, T = function(text) return text end,
        log_error = tostring, display_error = tostring,
        file_exists = function(path) return existing_files[path] == true end }
end
package.preload["weread.lib.read_stats"] = function()
    return { fetch = function(_, mode)
        stats_fetches = stats_fetches + 1
        stats_modes[#stats_modes + 1] = mode
        if stats_fetch_hook then stats_fetch_hook() end
        return { mode = mode, total_read_time = 3600, read_days = 12, day_average = 60 }
    end }
end
package.preload["weread.ui.read_stats_view"] = function()
    return { show = function(_, callbacks)
        stats_shown = stats_shown + 1
        events[#events + 1] = "show:stats"
        return { name = "stats", callbacks = callbacks }
    end }
end
local shown_account
package.preload["weread.ui.my_view"] = function()
    return { show = function(data, callbacks)
        shown_account = data
        events[#events + 1] = "show:my"
        return { name = "my", callbacks = callbacks,
            setReadingStats = function(self, stats) self.stats = stats end }
    end }
end

local HomeRequest = require("weread.ui.home_request")
local Library = require("weread.ui.library")
local Report = require("weread.ui.read_report")
local function take(host)
    local pending = host.pendings and table.remove(host.pendings, 1)
    assert(pending, "no pending online task")
    return pending
end

local function newHost()
    local account = { name = "Reader", login_method = "qr", login_time = 1 }
    local host = {
        account = account,
        settings = {
            get = function(_, key, default)
                if key == "account" then return account end
                if key == "books" then return book_records end
                return default
            end,
            is_cookie_configured = function() return true end,
            is_api_configured = function() return true end,
        },
        client = { get_shelf = function()
            shelf_fetches = shelf_fetches + 1
            return { books = {}, archive = {} }
        end },
        requireLogin = function() return true end,
        showBusy = function(self) self.busy_message = {} end,
        closeBusy = function(self) self.busy_message = nil end,
        runOnlineTask = function(self, _, callback)
            self.pendings = self.pendings or {}
            table.insert(self.pendings, callback)
            return true
        end,
        showInfo = function() end,
        applyShelfSnapshot = function(self) self.snapshot_applied = true end,
        showShelfView = function(self) self.shelf_shown = true end,
    }
    return setmetatable(host, { __index = function(_, key) return Library[key] or Report[key] end })
end

-- A later page selection must win over a pending statistics request.
local host = newHost()
local shelf = { name = "shelf" }
host.home_view, host.shelf_view = shelf, shelf
host:showReadStats(shelf)
local pending = take(host)
host:showMyPage(shelf)
local my_page = host.home_view
host:showBusy("newer operation")
local newer_busy = host.busy_message
pending()
expect(host.home_view == my_page and stats_shown == 0 and stats_fetches == 0,
    "a stale statistics request reopened the page")
expect(host.busy_message == newer_busy, "a stale request closed a newer busy dialog")
expect(shown_account.account_name == "Reader", "the stored account nickname was not used")

local closed = newHost()
closed:showReadStats()
local closed_pending = take(closed)
closed:closeWeReadUI()
closed_pending()
expect(stats_shown == 0 and stats_fetches == 0,
    "closing WeRead did not cancel a pending first statistics page")

-- Account metadata may omit a name even with valid saved credentials.
local unnamed = newHost()
unnamed.account.name = ""
unnamed:showMyPage()
expect(shown_account.account_name == "Unknown account"
    and shown_account.account_status == "Logged in", "missing nickname was treated as logged out")

-- A page change during the fetch also invalidates its eventual result.
local during_fetch = newHost()
during_fetch.home_view = { name = "shelf" }
stats_fetch_hook = function() HomeRequest.begin(during_fetch) end
during_fetch:showReadStats(during_fetch.home_view)
take(during_fetch)()
stats_fetch_hook = nil
expect(stats_shown == 0, "a result invalidated during fetch displayed statistics")

-- Normal navigation still shows the destination before closing its source.
events = {}
local current = newHost()
local source = { name = "shelf" }
current.home_view, current.shelf_view = source, source
current:showReadStats(source)
take(current)()
expect(current.home_view.name == "stats" and events[1] == "show:stats" and events[2] == "close:shelf",
    "successful navigation did not show statistics before closing the shelf")

-- A cover completion rebuilds the same shelf while statistics are loading.
package.loaded["weread.lib.shelf_groups"].find = function() return nil end
package.preload["weread.ui.library_view"] = function()
    return {
        getLayout = function() return { page_size = 10 } end,
        show = function(_, callbacks)
            events[#events + 1] = "show:redrawn shelf"
            return { name = "redrawn shelf", page = 1, callbacks = callbacks }
        end,
    }
end
local function redrawWhileStatsPending()
    local probe = newHost()
    probe.settings.get = function(_, key, default)
        if key == "account" then return probe.account end
        if key == "books" then return {} end
        if key == "shelf" then
            return { sort_order = "default", view_mode = "list", paginated = true }
        end
        return default
    end
    probe.shelf_regular, probe.shelf_mp = {}, {}
    probe.shelfSortSummary = function() return "" end
    probe.shelfFilterSummary = function() return "" end
    local original = { name = "shelf" }
    probe.home_view, probe.shelf_view = original, original
    probe:showReadStats(original)
    local pending_stats = take(probe)
    probe.showShelfView = nil
    probe:showShelfView("books", nil, original, {
        skip_cover_fetch_once = true, preserve_home_request = true,
    })
    return probe, pending_stats
end

events = {}
local cover_redraw, cover_pending = redrawWhileStatsPending()
local redrawn_shelf = cover_redraw.home_view
cover_pending()
expect(cover_redraw.home_view.name == "stats" and events[#events] == "close:redrawn shelf",
    "cover redraw cancelled statistics or left the replacement shelf open")
expect(redrawn_shelf ~= cover_redraw.home_view,
    "statistics did not replace the refreshed shelf")

events = {}
local cover_then_exit, cancelled_stats = redrawWhileStatsPending()
cover_then_exit:showMyPage(cover_then_exit.home_view)
local selected_my = cover_then_exit.home_view
local shown_before = stats_shown
cancelled_stats()
expect(cover_then_exit.home_view == selected_my and stats_shown == shown_before,
    "cover redraw allowed a stale statistics request to override My")

events = {}
local cover_failure, failed_stats = redrawWhileStatsPending()
local available_shelf = cover_failure.home_view
stats_fetch_hook = function() error("simulated statistics failure") end
failed_stats()
stats_fetch_hook = nil
expect(cover_failure.home_view == available_shelf,
    "failed statistics load did not leave the refreshed shelf available")

-- A queued bottom navigation must follow a cover-only shelf replacement.
local function makeShelfHost()
    local probe = newHost()
    probe.showShelfView = nil
    probe.settings.get = function(_, key, default)
        if key == "account" then return probe.account end
        if key == "books" then return {} end
        if key == "shelf" then return { sort_order = "default", view_mode = "list", paginated = true } end
        return default
    end
    probe.shelf_regular, probe.shelf_mp = {}, {}
    probe.shelfSortSummary = function() return "" end
    probe.shelfFilterSummary = function() return "" end
    probe:showShelfView("books", nil, nil, { skip_cover_fetch_once = true })
    return probe
end

events = {}
local queued = makeShelfHost()
local queued_source = queued.home_view
queued:showShelfView("books", nil, queued_source, {
    skip_cover_fetch_once = true, preserve_home_request = true,
})
local queued_replacement = queued.home_view
events = {}
queued_source.callbacks.on_home_nav("me", queued_source)
expect(queued.home_view.name == "my" and events[1] == "show:my"
    and events[2] == "close:redrawn shelf" and queued.shelf_view == nil,
    "queued navigation did not replace the cover-redrawn shelf")

-- An obsolete callback must not close or replace a later, unrelated page.
events = {}
local stale = makeShelfHost()
local stale_source = stale.home_view
stale:showMyPage(stale_source)
local retained = stale.home_view
events = {}
local pendings_before = #(stale.pendings or {})
stale_source.callbacks.on_home_nav("stats", stale_source)
expect(stale.home_view == retained and #(stale.pendings or {}) == pendings_before
    and #events == 0, "an obsolete navigation callback replaced a newer page")

-- Closing a source page cancels its pending shelf refresh without touching it.
local refresh = newHost()
local refresh_calls = 0
local closed_shelf = { name = "shelf", setRefreshing = function() refresh_calls = refresh_calls + 1 end }
refresh.home_view, refresh.shelf_view = closed_shelf, closed_shelf
refresh:refreshBookshelf(closed_shelf)
local refresh_pending = take(refresh)
refresh:closeWeReadHomeView(closed_shelf)
refresh_pending()
expect(shelf_fetches == 0 and not refresh.shelf_shown and refresh_calls == 1,
    "a closed shelf was refreshed or reopened by a stale request")

local cancelled_refresh = newHost()
local refresh_states = {}
local retained_shelf = { name = "shelf", setRefreshing = function(_, busy)
    refresh_states[#refresh_states + 1] = busy
end }
cancelled_refresh.home_view, cancelled_refresh.shelf_view = retained_shelf, retained_shelf
cancelled_refresh:refreshBookshelf(retained_shelf)
HomeRequest.begin(cancelled_refresh)
take(cancelled_refresh)()
expect(refresh_states[1] == true and refresh_states[2] == false
    and cancelled_refresh.home_view == retained_shelf,
    "cancelled refresh left the retained shelf's refresh button disabled")

-- An uninterrupted shelf refresh keeps the original behavior.
local valid_refresh = newHost()
local active_shelf = { name = "shelf", setRefreshing = function() end }
valid_refresh.home_view, valid_refresh.shelf_view = active_shelf, active_shelf
valid_refresh:refreshBookshelf(active_shelf)
take(valid_refresh)()
expect(shelf_fetches == 1 and valid_refresh.snapshot_applied and valid_refresh.shelf_shown,
    "a valid shelf refresh did not display the updated shelf")

-- The account page shows at once and fills its totals afterwards.
local my_stats = newHost()
my_stats:showMyPage({ name = "shelf" })
local account_page = my_stats.home_view
take(my_stats)()
expect(account_page.stats ~= nil and stats_modes[#stats_modes] == "overall",
    "account page did not load overall reading totals")

-- Shelf counts are local only: a record with cached chapters counts as
-- downloaded without stat'ing every chapter file, and a record whose single
-- file is gone does not count at all.
local summary_host = newHost()
summary_host.shelf_regular = {
    { book_id = "a", finishReading = 1 },
    { book_id = "b" },
    { book_id = 3, finishReading = 1 },
    { book_id = "d" },
}
book_records = {
    a = { cached_full_book = "/cache/a.epub" },
    b = { cached_chapters = { ["1"] = "/cache/b-1.html" } },
    [3] = { cached_file = "/gone/c.html" },
    d = {},
}
existing_files["/cache/a.epub"] = true
summary_host:showMyPage()
local summary = shown_account.shelf_summary
expect(summary ~= nil and summary.total == 4, "account page did not count the shelf")
expect(summary.downloaded == 2,
    "account page counted downloads wrong: " .. tostring(summary.downloaded))
expect(summary.finished == 2,
    "account page counted finished books wrong: " .. tostring(summary.finished))

print("home_navigation_requests_spec: " .. checks .. " checks")
