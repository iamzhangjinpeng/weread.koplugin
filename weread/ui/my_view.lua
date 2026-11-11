-- Account summary, reading overview, and exit page for the WeRead home navigation.

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local FocusNav = require("weread.ui.focus_nav")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ScrollableContainer = require("ui/widget/scrollablecontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HomeNav = require("weread.ui.home_nav")
local I18n = require("weread.lib.i18n")

local Screen = Device.screen
local _ = I18n.tr
local T = require("ffi/util").template
local icons_dir = debug.getinfo(1, "S").source:match("^@(.*/)") .. "../../icons/"

local PLACEHOLDER = "—"

-- Same wording as the statistics page, so totals never read differently
-- on two screens.
local function format_duration(seconds)
    if seconds == nil then return PLACEHOLDER end
    local total = math.max(0, math.floor(tonumber(seconds) or 0))
    if total < 60 then return _("< 1 min") end
    local hours = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    if hours > 0 and minutes > 0 then return T(_("%1 h %2 min"), hours, minutes) end
    if hours > 0 then return T(_("%1 h"), hours) end
    return T(_("%1 min"), minutes)
end

local function book_count(value)
    if value == nil then return PLACEHOLDER end
    return T(_("%1 books"), value)
end

local MyView = FocusManager:extend{
    account = nil,
    account_name = nil,
    account_status = nil,
    shelf_summary = nil,
    reading_stats = nil,
    on_exit = nil,
    on_home_nav = nil,
    on_closed = nil,
}

function MyView:sectionHeader(text)
    return TextWidget:new{
        text = text,
        face = Font:getFace("cfont", 17),
        max_width = self.screen_w - 2 * Size.padding.large,
    }
end

-- Label column width is fixed, so a value arriving later never shifts the
-- row: only the value widget itself is replaced.
function MyView:metricRow(label_text, value_text, key, icon_file)
    local row_width = self.screen_w - 2 * Size.padding.large
    local icon_size = Screen:scaleBySize(22)
    local icon_gap = Screen:scaleBySize(8)
    local text_width = row_width - icon_size - icon_gap
    local label_width = math.floor(text_width * 0.52)
    local icon = IconWidget:new{
        file = icons_dir .. icon_file,
        width = icon_size,
        height = icon_size,
    }
    local label = TextWidget:new{
        text = label_text,
        face = Font:getFace("cfont", 18),
        max_width = label_width,
    }
    local gap = math.max(Size.padding.small, label_width - label:getSize().w)
    local value = TextWidget:new{
        text = value_text,
        face = Font:getFace("cfont", 18),
        max_width = math.max(1, text_width - label_width - gap),
    }
    if key then
        self._metric_values = self._metric_values or {}
        self._metric_values[key] = value
    end
    return HorizontalGroup:new{
        align = "center",
        icon,
        HorizontalSpan:new{ width = icon_gap },
        label,
        HorizontalSpan:new{ width = gap },
        value,
    }
end

function MyView:buildContent()
    local stats = self.reading_stats
    local shelf = self.shelf_summary
    local account = self.account or {}
    local account_name = self.account_name or (type(account.name) == "string" and account.name or "")
    if account_name == "" then account_name = _("Not logged in") end

    self.exit_button = Button:new{
        text = _("Back to KOReader"),
        width = self.screen_w - 2 * Size.padding.large,
        height = Screen:scaleBySize(58),
        show_parent = self,
        callback = function()
            UIManager:nextTick(function()
                if self.on_exit then self.on_exit(self) else self:onClose() end
            end)
        end,
    }

    local avatar_size = Screen:scaleBySize(52)
    local account_text_width = math.max(1, self.screen_w - 3 * Size.padding.large - avatar_size)
    local name = TextWidget:new{
        text = account_name,
        face = Font:getFace("cfont", 24),
        max_width = account_text_width,
    }
    local status = TextWidget:new{
        text = self.account_status or _("WeRead account"),
        face = Font:getFace("cfont", 17),
        max_width = account_text_width,
    }

    local function padded(widget)
        return HorizontalGroup:new{
            HorizontalSpan:new{ width = Size.padding.large },
            widget,
        }
    end

    self._metric_values = {}

    local content = VerticalGroup:new{
        align = "left",
        HorizontalSpan:new{ width = self.screen_w },
        VerticalSpan:new{ width = Size.padding.large },
        padded(TextWidget:new{
            text = _("My"),
            face = Font:getFace("tfont", 26),
            max_width = self.screen_w - 2 * Size.padding.large,
        }),
        VerticalSpan:new{ width = Size.padding.large },
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = Size.padding.large,
            margin = 0,
            HorizontalGroup:new{
                align = "center",
                IconWidget:new{
                    file = icons_dir .. "account-avatar.svg",
                    width = avatar_size,
                    height = avatar_size,
                },
                HorizontalSpan:new{ width = Size.padding.large },
                VerticalGroup:new{
                    align = "left",
                    name,
                    VerticalSpan:new{ width = Size.padding.small },
                    status,
                },
            },
        },
        VerticalSpan:new{ width = Size.padding.large },
        padded(self:sectionHeader(_("Reading overview"))),
        VerticalSpan:new{ width = Size.padding.small },
        padded(self:metricRow(_("Total reading time"),
            format_duration(stats and stats.total_read_time), "total", "metric-time.svg")),
        VerticalSpan:new{ width = Size.padding.small },
        padded(self:metricRow(_("Reading days"),
            stats and T(_("%1 days"), stats.read_days or 0) or PLACEHOLDER, "days", "metric-days.svg")),
        VerticalSpan:new{ width = Size.padding.small },
        padded(self:metricRow(_("Daily average"),
            format_duration(stats and stats.day_average), "average", "metric-average.svg")),
        VerticalSpan:new{ width = Size.padding.large },
        padded(self:sectionHeader(_("Bookshelf"))),
        VerticalSpan:new{ width = Size.padding.small },
        padded(self:metricRow(_("On shelf"),
            book_count(shelf and shelf.total), "shelf_total", "metric-shelf.svg")),
        VerticalSpan:new{ width = Size.padding.small },
        padded(self:metricRow(_("Downloaded"),
            book_count(shelf and shelf.downloaded), "shelf_downloaded", "metric-download.svg")),
        VerticalSpan:new{ width = Size.padding.small },
        padded(self:metricRow(_("Finished"),
            book_count(shelf and shelf.finished), "shelf_finished", "metric-finished.svg")),
        VerticalSpan:new{ width = Size.padding.large },
        padded(self.exit_button),
        VerticalSpan:new{ width = Size.padding.large },
    }

    self.scroll = ScrollableContainer:new{
        dimen = Geom:new{ w = self.screen_w, h = self.scroll_height },
        show_parent = self,
        content,
    }
    return self.scroll
end

function MyView:init()
    self.screen_w = Screen:getWidth()
    self.screen_h = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.screen_w, h = self.screen_h }
    self.covers_fullscreen = true
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    self.nav, self.nav_buttons = HomeNav.create("me", self, function(route)
        if self.on_home_nav then self.on_home_nav(route, self) end
    end)
    self.scroll_height = math.max(1, self.screen_h - self.nav:getSize().h)
    local scroll = self:buildContent()

    FocusNav.apply(self, { { self.exit_button }, self.nav_buttons })
    FocusNav.initialFocus(self, 1, 1)
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        dimen = self.dimen:copy(),
        VerticalGroup:new{
            align = "left",
            scroll,
            self.nav,
        },
    }
end

-- Values are fetched after the page is shown; update them in place so the
-- tab switch never waits on the network and never rebuilds the whole page.
function MyView:setReadingStats(stats)
    self.reading_stats = stats or {}
    local values = {
        total = format_duration(self.reading_stats.total_read_time),
        days = T(_("%1 days"), self.reading_stats.read_days or 0),
        average = format_duration(self.reading_stats.day_average),
    }
    for key, widget in pairs(self._metric_values or {}) do
        if values[key] and widget.setText then widget:setText(values[key]) end
    end
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function MyView:onShow()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    return true
end

function MyView:onCloseWidget()
    if self.on_closed then self.on_closed(self) end
    UIManager:setDirty(nil, function() return "ui", self.dimen end)
end

function MyView:onClose()
    UIManager:close(self)
    return true
end

local M = {}

function M.show(data, callbacks)
    data = data or {}
    callbacks = callbacks or {}
    local view = MyView:new{
        account = data.account,
        account_name = data.account_name,
        account_status = data.account_status,
        shelf_summary = data.shelf_summary,
        reading_stats = data.reading_stats,
        on_exit = callbacks.on_exit,
        on_home_nav = callbacks.on_home_nav,
        on_closed = callbacks.on_closed,
    }
    UIManager:show(view)
    return view
end

return M
