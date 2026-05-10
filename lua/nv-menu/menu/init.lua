local M = {}
M.__index = M

local Window   = require("nv-menu.menu.window")
local Renderer = require("nv-menu.menu.renderer")
local utils    = require("nv-menu.utils")

function M.new(opts)
    local self = setmetatable({}, M)

    self.name         = opts.name or "Menu"
    self.items        = opts.items or {}
    self.item_actions = opts.item_actions or {}
    self.config       = vim.tbl_deep_extend("force", { auto_preview = false }, require("nv-menu").config, opts or {})
    self.index        = 1
    self.scroll       = 0
    self.history      = {}
    self._panel_cache = setmetatable({}, { __mode = "k" })

    local raw = opts.footer
    self.footer = type(raw) == "string" and { raw }
              or type(raw) == "table"  and raw
              or {}

    self:_recalc_meta()

    self.window   = Window.new(self.config)
    self.renderer = Renderer.new(self)

    return self
end

function M:get_current_item()
    return self.items[self.index]
end

function M:get_item_actions(item)
    if not item then return {} end
    local merged = {}
    local seen   = {}
    for _, action in ipairs(item.actions or {}) do
        merged[action.key] = action
        seen[action.key]   = true
    end
    for _, action in ipairs(self.item_actions) do
        if not seen[action.key] then
            merged[action.key] = action
        end
    end
    local result = {}
    for _, action in pairs(merged) do
        table.insert(result, action)
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

function M:move_down()
    if self.index < #self.items then
        self.index = self.index + 1
        self:ensure_visible()
        return true
    end
    return false
end

function M:move_up()
    if self.index > 1 then
        self.index = self.index - 1
        self:ensure_visible()
        return true
    end
    return false
end

function M:ensure_visible()
    local max_height    = self.config.max_height
    local visible_start = self.scroll + 1
    local visible_end   = self.scroll + max_height

    if self.index < visible_start then
        self.scroll = self.index - 1
    elseif self.index > visible_end then
        self.scroll = self.index - max_height
    end

    self.scroll = math.max(0, self.scroll)
end

function M:jump_to_index(idx)
    if idx >= 1 and idx <= #self.items then
        self.index = idx
        self:ensure_visible()
        return true
    end
    return false
end

function M:jump_by_key(key)
    local idx = self.nav_keys[key]
    if idx then
        return self:jump_to_index(idx)
    end
    return false
end

function M:push_history()
    table.insert(self.history, {
        items  = self.items,
        index  = self.index,
        scroll = self.scroll,
    })
end

function M:pop_history()
    if #self.history > 0 then
        local state = table.remove(self.history)
        self.items  = state.items
        self.index  = math.max(1, math.min(state.index, #state.items))
        self.scroll = state.scroll
        self:_recalc_meta()
        self:_sync_title()
        return true
    end
    return false
end

function M:_sync_title()
    local prefix = self:has_history() and "◀ " or ""
    self.window:update_title(prefix .. (self.name or ""))
end

function M:has_history()
    return #self.history > 0
end

function M:_recalc_meta()
    self.nav_keys = utils.generate_nav_keys(self.items, self.config.nav_keys)

    local has_actions = #self.item_actions > 0
    if not has_actions then
        for _, item in ipairs(self.items) do
            if item.actions and #item.actions > 0 then
                has_actions = true
                break
            end
        end
    end
    self._has_action_footer = has_actions
    self._footer_height     = (has_actions and 1 or 0) + #self.footer
end

function M:resize()
    local win_id = self.window:get_win_id()
    if not win_id or not vim.api.nvim_win_is_valid(win_id) then return end

    local actual_width, _ = self:get_actual_dimensions()
    local item_count      = #self.items
    local visible_count   = math.min(item_count, self.config.max_height)
    local content_height  = (item_count > 0 and visible_count + 2 or 3) + self._footer_height

    local current = vim.api.nvim_win_get_config(win_id)
    vim.api.nvim_win_set_config(win_id, vim.tbl_extend("force", current, {
        width  = actual_width,
        height = content_height,
    }))
end

function M:open_submenu(submenu)
    if submenu.type == "nested" then
        return { action = "nested", items = submenu.items }
    elseif submenu.type == "replace" then
        self:push_history()
        self.items  = submenu.items
        self.index  = 1
        self.scroll = 0
        self:_recalc_meta()
        self:_sync_title()
        return { action = "replace" }
    end
    return nil
end

function M:has_panel()
    return self.window.panel_win_id ~= nil
end

function M:get_panel_content(item)
    if type(item.panel_content) == "function" then
        if not self._panel_cache[item] then
            local content, ft, pos = item.panel_content()
            self._panel_cache[item] = { content = content or "", ft = ft or item.panel_ft, pos = pos }
        end
        local cached = self._panel_cache[item]
        return cached.content, cached.ft, cached.pos
    end
    return item.panel_content, item.panel_ft, nil
end

function M:open_panel(content, ft, pos)
    local width  = self.config.panel_width
    local height = math.max(#vim.split(content, "\n") + 2, self.config.max_height)
    self.window:open_panel(content, ft, width, height, self.config.panel_wrap, pos)
end

function M:update_panel(content, ft, pos)
    if not self.window:update_panel_content(content, ft, pos) then
        self:open_panel(content, ft, pos)
    end
end

function M:close_panel()
    self.window:close_panel()
end

function M:get_actual_dimensions()
    local actual_width = 10

    if self.name and self.name ~= "" then
        actual_width = math.max(actual_width, #self.name + 4)
    end

    for _, item in ipairs(self.items) do
        local key_prefix = item.nav_key and ("[" .. item.nav_key .. "] ") or "    "
        local item_width = #key_prefix + #item.label + 4
        if item.submenu or (item.panel_content and self.config.auto_preview) then
            item_width = item_width + 2
        end
        actual_width = math.max(actual_width, item_width)
    end
    actual_width = math.min(actual_width, self.config.max_width) + 4

    local actual_height = math.max(1, math.min(#self.items, self.config.max_height))

    return actual_width, actual_height + self._footer_height
end

function M:show()
    local actual_width, actual_height = self:get_actual_dimensions()
    local item_count    = #self.items
    local visible_count = math.min(item_count, self.config.max_height)

    local content_height
    if item_count > 0 then
        content_height = visible_count + 2
    else
        content_height = 3
    end
    content_height = content_height + self._footer_height

    local cursor_pos = utils.get_cursor_pos()
    local win_config = utils.get_win_config(actual_width, content_height, self.config.position, cursor_pos)

    self.window:create()
    self.window:set_title(self.name)
    self.window:open_floating(win_config)

    self.renderer:render()

    return self.window:get_win_id()
end

function M:close()
    self.window:close()
end

function M:redraw()
    self.renderer:render()
end

return M
