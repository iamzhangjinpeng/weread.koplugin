-- Shared bottom navigation for the WeRead bookshelf, statistics, and account pages.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local I18n = require("weread.lib.i18n")

local Screen = Device.screen
local M = {}

local icons_dir = debug.getinfo(1, "S").source:match("^@(.*/)") .. "../../icons/"

local BAR_HEIGHT = 64
local ICON_SIZE = 24
local ICON_GAP = 3
local LABEL_FONT_SIZE = 16

local function _(text)
    return I18n.tr(text)
end

-- Icon above label. A plain Button cannot do this: it keeps only the text when
-- both text and icon are given, and its label sits in one fixed-height line.
-- The tab is therefore composed here, but it follows Button's contract so
-- FocusManager (onFocus/onUnfocus plus a synthetic tap gesture) keeps working.
local NavItem = InputContainer:extend{
    text = nil,
    icon_file = nil,
    selected = false,
    callback = nil,
    bordersize = Size.border.thin,
}

function NavItem:init()
    local icon = IconWidget:new{
        file = icons_dir .. self.icon_file,
        width = Screen:scaleBySize(ICON_SIZE),
        height = Screen:scaleBySize(ICON_SIZE),
    }
    local label = TextWidget:new{
        text = self.text,
        face = Font:getFace("cfont", LABEL_FONT_SIZE),
        bold = self.selected,
        max_width = math.max(1, self.width - 2 * self.bordersize - 2 * Size.padding.small),
    }
    -- Inner box is sized explicitly: the frame then ends up exactly as tall as
    -- the row, which is what HomeNav.getHeight() promises to the shelf layout.
    local inner = CenterContainer:new{
        dimen = Geom:new{
            w = self.width - 2 * self.bordersize,
            h = self.height - 2 * self.bordersize,
        },
        VerticalGroup:new{
            align = "center",
            icon,
            VerticalSpan:new{ width = Screen:scaleBySize(ICON_GAP) },
            label,
        },
    }
    self.frame = FrameContainer:new{
        margin = 0,
        bordersize = self.bordersize,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        inner,
    }
    if self.selected then self.frame.invert = true end
    self.label_widget = label
    self.dimen = self.frame:getSize()
    self[1] = self.frame
    self.ges_events = {
        TapNavItem = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
    }
end

function NavItem:onTapNavItem()
    if self.selected or not self.callback then return true end
    UIManager:nextTick(function() self.callback() end)
    return true
end

function NavItem:onFocus()
    self.frame.invert = true
    return true
end

-- The active tab keeps its inverted look: leaving focus must not clear it.
function NavItem:onUnfocus()
    self.frame.invert = self.selected
    return true
end

function M.getHeight()
    return Screen:scaleBySize(BAR_HEIGHT) + Size.border.thin
end

function M.create(active, parent, on_select)
    local entries = {
        { route = "shelf", label = "Bookshelf", icon = "nav-shelf.svg" },
        { route = "stats", label = "Statistics", icon = "nav-stats.svg" },
        { route = "me", label = "My", icon = "nav-me.svg" },
    }
    local width = Screen:getWidth()
    local cell_width = math.floor(width / #entries)
    local buttons = {}

    for index, item in ipairs(entries) do
        local entry = item
        local selected = entry.route == active
        buttons[#buttons + 1] = NavItem:new{
            text = _(entry.label),
            icon_file = entry.icon,
            width = index == #entries and width - cell_width * (#entries - 1) or cell_width,
            height = Screen:scaleBySize(BAR_HEIGHT),
            selected = selected,
            callback = function()
                if selected or not on_select then return end
                on_select(entry.route)
            end,
        }
    end

    local row = HorizontalGroup:new(buttons)
    local widget = VerticalGroup:new{
        align = "left",
        LineWidget:new{
            dimen = Geom:new{ w = width, h = Size.border.thin },
            background = Blitbuffer.COLOR_GRAY,
        },
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
            margin = 0,
            row,
        },
    }

    return widget, buttons
end

return M
