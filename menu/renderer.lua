local M = {}
M.__index = M

local utils = require("nv-menu.utils")

function M.new(menu)
    local self = setmetatable({}, M)
    self.menu   = menu
    self.hl_ns  = vim.api.nvim_create_namespace("nvmenu_menu")

    local cfg = menu.config
    vim.api.nvim_set_hl(0, cfg.highlight, {
        bg   = cfg.highlight_bg,
        fg   = cfg.highlight_fg,
        bold = true,
    })

    return self
end

function M:render()
    local menu          = self.menu
    local items         = menu.items
    local scroll        = menu.scroll
    local index         = menu.index
    local visible_count = math.min(#items, menu.config.max_height)

    local win_id = menu.window:get_win_id()
    local win_width = 30
    if win_id and vim.api.nvim_win_is_valid(win_id) then
        win_width = vim.api.nvim_win_get_width(win_id)
    end

    local lines = {}

    table.insert(lines, scroll > 0 and " ▲ " or "   ")

    for i = scroll + 1, math.min(#items, scroll + visible_count) do
        local item    = items[i]
        local key_str = ""

        if menu.nav_keys then
            for k, v in pairs(menu.nav_keys) do
                if v == i and k:len() == 1 then
                    key_str = "[" .. k .. "] "
                    break
                end
            end
        end

        local has_expand = item.submenu or (item.panel_content and menu.config.auto_preview)
        local line       = " " .. key_str .. item.label
        local padding    = win_width - #line - (has_expand and 1 or 0)

        if padding > 0 then
            line = line .. string.rep(" ", padding)
        end
        if has_expand then
            line = line .. "▶"
        end

        table.insert(lines, line)
    end

    table.insert(lines, (#items > scroll + visible_count) and " ▼ " or "")

    while #lines < visible_count + 2 do
        table.insert(lines, "")
    end

    if menu._footer_height > 0 then
        if menu._has_action_footer then
            table.insert(lines, M._build_action_line(menu))
        end
        for _, text in ipairs(menu.footer) do
            table.insert(lines, "  " .. text)
        end
    end

    menu.window:set_lines(lines)

    local buf_id      = menu.window:get_buf_id()
    local sel_line    = index - scroll + 1
    local line_text   = lines[sel_line] or ""

    vim.api.nvim_buf_clear_namespace(buf_id, self.hl_ns, 0, -1)

    if #line_text > 0 then
        vim.api.nvim_buf_add_highlight(buf_id, self.hl_ns, menu.config.highlight, sel_line - 1, 0, #line_text)
        if win_id and vim.api.nvim_win_is_valid(win_id) then
            vim.api.nvim_win_set_cursor(win_id, { sel_line, 0 })
        end
    end
end

function M:update_highlight()
    local menu   = self.menu
    local buf_id = menu.window:get_buf_id()
    if not buf_id then return end

    local sel_line   = menu.index - menu.scroll + 1
    local line_count = vim.api.nvim_buf_line_count(buf_id)
    if sel_line < 1 or sel_line > line_count then return end

    local line_text = vim.api.nvim_buf_get_lines(buf_id, sel_line - 1, sel_line, false)[1] or ""
    if #line_text == 0 then return end

    vim.api.nvim_buf_clear_namespace(buf_id, self.hl_ns, 0, -1)
    vim.api.nvim_buf_add_highlight(buf_id, self.hl_ns, menu.config.highlight, sel_line - 1, 0, #line_text)

    if menu._has_action_footer then
        local action_line_idx = math.min(#menu.items, menu.config.max_height) + 2
        if action_line_idx < line_count then
            vim.bo[buf_id].modifiable = true
            vim.api.nvim_buf_set_lines(buf_id, action_line_idx, action_line_idx + 1, false, { M._build_action_line(menu) })
            vim.bo[buf_id].modifiable = false
        end
    end
end

function M._build_action_line(menu)
    local actions = menu:get_item_actions(menu:get_current_item())
    if #actions == 0 then return "" end
    local parts = {}
    for _, a in ipairs(actions) do
        table.insert(parts, a.key .. " - " .. a.label)
    end
    return "  " .. table.concat(parts, "   ")
end

return M
