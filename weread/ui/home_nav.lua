-- Shared bottom navigation for the WeRead bookshelf, statistics, and account pages.

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local I18n = require("weread.lib.i18n")

local Screen = Device.screen
local M = {}

local function _(text)
    return I18n.tr(text)
end

-- Must match what create() actually measures, or getLayout() reserves the wrong
-- height and the shelf paginates against a space it does not have. The bar is a
-- LineWidget plus a row of Buttons, and FrameContainer counts both of a Button's
-- borders on top of its content height: 1 * thin for the line, 2 * thin for the
-- row. Adding only one left the estimate 2px short.
function M.getHeight()
    return Screen:scaleBySize(52) + 3 * Size.border.thin
end

function M.create(active, parent, on_select)
    local entries = {
        { route = "shelf", label = "Bookshelf" },
        { route = "stats", label = "Statistics" },
        { route = "me", label = "My" },
    }
    local width = Screen:getWidth()
    local cell_width = math.floor(width / #entries)
    local buttons = {}

    for index, item in ipairs(entries) do
        local entry = item
        local selected = entry.route == active
        local button = Button:new{
            text = _(entry.label),
            width = index == #entries and width - cell_width * (#entries - 1) or cell_width,
            height = Screen:scaleBySize(52),
            radius = 0,
            margin = 0,
            bordersize = Size.border.thin,
            padding = 0,
            background = Blitbuffer.COLOR_WHITE,
            preselect = selected,
            text_font_size = 18,
            text_font_bold = selected,
            show_parent = parent,
            callback = function()
                if selected or not on_select then return end
                UIManager:nextTick(function() on_select(entry.route) end)
            end,
        }
        if selected then
            button.onUnfocus = function(self)
                self.frame.invert = true
                return true
            end
        end
        buttons[#buttons + 1] = button
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
