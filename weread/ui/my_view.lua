-- Account summary and exit page for the WeRead home navigation.

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local FocusNav = require("weread.ui.focus_nav")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HomeNav = require("weread.ui.home_nav")
local I18n = require("weread.lib.i18n")

local Screen = Device.screen
local _ = I18n.tr

local MyView = FocusManager:extend{
    account = nil,
    account_name = nil,
    account_status = nil,
    on_exit = nil,
    on_home_nav = nil,
    on_closed = nil,
}

function MyView:init()
    self.screen_w = Screen:getWidth()
    self.screen_h = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.screen_w, h = self.screen_h }
    self.covers_fullscreen = true
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    local account = self.account or {}
    local account_name = self.account_name or (type(account.name) == "string" and account.name or "")
    if account_name == "" then account_name = _("Not logged in") end
    local exit_button = Button:new{
        text = _("Exit WeRead"),
        width = self.screen_w - 2 * Size.padding.large,
        height = Screen:scaleBySize(58),
        show_parent = self,
        callback = function()
            UIManager:nextTick(function()
                if self.on_exit then self.on_exit(self) else self:onClose() end
            end)
        end,
    }

    local nav, nav_buttons = HomeNav.create("me", self, function(route)
        if self.on_home_nav then self.on_home_nav(route, self) end
    end)
    local name = TextWidget:new{
        text = account_name,
        face = Font:getFace("cfont", 24),
        max_width = self.screen_w - 2 * Size.padding.large,
    }
    local status = TextWidget:new{
        text = self.account_status or _("WeRead account"),
        face = Font:getFace("cfont", 17),
        max_width = self.screen_w - 2 * Size.padding.large,
    }

    local content = VerticalGroup:new{
        align = "left",
        HorizontalSpan:new{ width = self.screen_w },
        VerticalSpan:new{ width = Size.padding.large },
        TextWidget:new{
            text = _("My"),
            face = Font:getFace("tfont", 26),
            max_width = self.screen_w - 2 * Size.padding.large,
        },
        VerticalSpan:new{ width = Size.padding.large },
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = Size.padding.large,
            margin = 0,
            VerticalGroup:new{
                align = "left",
                name,
                VerticalSpan:new{ width = Size.padding.small },
                status,
            },
        },
        VerticalSpan:new{ width = Size.padding.large },
        exit_button,
    }

    self.exit_button = exit_button
    self.nav_buttons = nav_buttons
    FocusNav.apply(self, { { exit_button }, nav_buttons })
    FocusNav.initialFocus(self, 1, 1)
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        dimen = self.dimen:copy(),
        VerticalGroup:new{
            align = "left",
            content,
            VerticalSpan:new{ width = math.max(0, self.screen_h - content:getSize().h - nav:getSize().h) },
            nav,
        },
    }
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
        on_exit = callbacks.on_exit,
        on_home_nav = callbacks.on_home_nav,
        on_closed = callbacks.on_closed,
    }
    UIManager:show(view)
    return view
end

return M
