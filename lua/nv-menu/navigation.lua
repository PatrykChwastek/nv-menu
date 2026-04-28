local M = {}
M.__index = M

function M.new(menu)
    local self = setmetatable({}, M)
    self.menu               = menu
    self.nested_menus       = {}
    self.augroup            = nil
    self._active_action_keys = {}
    self._active_action_buf  = nil
    return self
end

function M:setup_keymaps()
    local menu   = self.menu
    local buf_id = menu.window:get_buf_id()

    local function map(modes, key, fn)
        vim.keymap.set(modes, key, fn, { buffer = buf_id, silent = true, noremap = true })
    end

    map("n", "<CR>",    function() self:enter() end)
    map("n", "l",       function() self:enter() end)
    map("n", "<Right>", function() self:enter() end)
    map("n", "h",       function() self:back()  end)
    map("n", "<Left>",  function() self:back()  end)
    map("n", "j",       function() self:move_down() end)
    map("n", "<Down>",  function() self:move_down() end)
    map("n", "k",       function() self:move_up()   end)
    map("n", "<Up>",    function() self:move_up()   end)

    local function scroll_by(delta)
        local m   = self.menu
        m.index   = math.max(1, math.min(m.index + delta, #m.items))
        m:ensure_visible()
        m:redraw()
        self:on_selection_changed()
    end
    local half = math.max(1, math.floor(menu.config.max_height / 2))
    map("n", "<C-d>", function() scroll_by( half) end)
    map("n", "<C-u>", function() scroll_by(-half) end)
    map("n", "<C-f>", function() scroll_by( menu.config.max_height) end)
    map("n", "<C-b>", function() scroll_by(-menu.config.max_height) end)

    local function jump_to(idx)
        local m   = self.menu
        m.index   = math.max(1, math.min(idx, #m.items))
        m:ensure_visible()
        m:redraw()
        self:on_selection_changed()
    end
    map("n", "gg", function() jump_to(1) end)
    map("n", "G",  function() jump_to(#self.menu.items) end)

    for _, key in ipairs(menu.config.close_keys) do
        map({ "n", "i" }, key, function() self:close_all() end)
    end

    for key, _ in pairs(menu.nav_keys) do
        map("n", key, function()
            self:jump_by_key(key)
            self:enter()
        end)
    end

    self.augroup = vim.api.nvim_create_augroup("NvMenu_" .. buf_id, { clear = true })

    vim.api.nvim_create_autocmd("CursorMoved", {
        buffer   = buf_id,
        group    = self.augroup,
        callback = function() self:on_cursor_moved() end,
    })
end

function M:on_cursor_moved()
    if self._in_sync then return end

    local menu  = self.menu
    local items = menu.items
    if #items == 0 then return end

    local win_id = menu.window:get_win_id()
    if not win_id or not vim.api.nvim_win_is_valid(win_id) then return end

    local cursor_line = vim.api.nvim_win_get_cursor(win_id)[1]

    if menu._footer_height > 0 then
        local visible_count = math.min(#items, menu.config.max_height)
        if cursor_line > visible_count + 2 then
            self._in_sync = true
            vim.api.nvim_win_set_cursor(win_id, { visible_count + 1, 0 })
            self._in_sync = false
            return
        end
    end

    local new_index = math.max(1, math.min(menu.scroll + (cursor_line - 1), #items))
    if new_index == menu.index then return end

    menu.index = new_index
    local old_scroll = menu.scroll
    menu:ensure_visible()

    self._in_sync = true
    if menu.scroll ~= old_scroll then
        menu:redraw()
    else
        menu.renderer:update_highlight()
        local target_line = new_index - menu.scroll + 1
        if cursor_line ~= target_line then
            vim.api.nvim_win_set_cursor(win_id, { target_line, 0 })
        end
    end
    self._in_sync = false
    self:on_selection_changed()
end

function M:on_selection_changed()
    self:maybe_auto_preview()
    self:update_action_keymaps()
end

function M:maybe_auto_preview()
    local menu = self.menu
    if not menu.config.auto_preview then return end

    local item = menu:get_current_item()
    if not item then return end

    if item.panel_content then
        local content, ft, pos = menu:get_panel_content(item)
        menu:update_panel(content, ft, pos)
    elseif menu:has_panel() then
        menu:close_panel()
    end
end

function M:update_action_keymaps()
    if self._active_action_buf and vim.api.nvim_buf_is_valid(self._active_action_buf) then
        for _, key in ipairs(self._active_action_keys) do
            pcall(vim.keymap.del, "n", key, { buffer = self._active_action_buf })
        end
    end
    self._active_action_keys = {}

    local buf_id = self.menu.window:get_buf_id()
    if not buf_id then return end
    self._active_action_buf = buf_id

    local item    = self.menu:get_current_item()
    local actions = self.menu:get_item_actions(item)
    for _, action in ipairs(actions) do
        local a, it = action, item
        vim.keymap.set("n", a.key, function()
            self:run_action(a, it)
        end, { buffer = buf_id, silent = true, noremap = true })
        table.insert(self._active_action_keys, a.key)
    end
end

function M:_open_peek(item)
    if not item or not item.panel_content then return end

    local content, ft, pos = self.menu:get_panel_content(item)
    if not content or content == "" then return end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    if ft and ft ~= "" then
        vim.bo[buf].filetype = ft
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))

    local max_w   = math.floor(vim.o.columns * 0.92)
    local max_h   = math.floor((vim.o.lines - vim.o.cmdheight) * 0.92)
    local total_w = max_w
    local total_h = math.min(max_h, vim.api.nvim_buf_line_count(buf) + 2)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width    = total_w - 2,
        height   = total_h - 2,
        row      = math.floor((vim.o.lines - total_h) / 2) - vim.o.cmdheight,
        col      = math.floor((vim.o.columns - total_w) / 2),
        border   = "rounded",
        style    = "minimal",
        zindex   = 200,
    })

    vim.bo[buf].modifiable     = false
    vim.wo[win].number         = false
    vim.wo[win].relativenumber = false
    vim.wo[win].foldcolumn     = "0"
    vim.wo[win].signcolumn     = "no"
    vim.wo[win].wrap           = false
    vim.wo[win].cursorline     = true
    vim.wo[win].scrolloff      = 5
    vim.wo[win].sidescrolloff  = 10

    if pos then
        local target = math.max(1, math.min(pos.line or 1, vim.api.nvim_buf_line_count(buf)))
        vim.api.nvim_win_set_cursor(win, { target, pos.col or 0 })
        if pos.hl_start and pos.hl_end then
            vim.api.nvim_buf_add_highlight(
                buf, vim.api.nvim_create_namespace("nvmenu_peek"),
                "Search", target - 1, pos.hl_start, pos.hl_end
            )
        end
    end

    local menu_win = self.menu.window:get_win_id()
    for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function()
            vim.api.nvim_win_close(win, true)
            if menu_win and vim.api.nvim_win_is_valid(menu_win) then
                vim.api.nvim_set_current_win(menu_win)
            end
        end, { buffer = buf, silent = true, noremap = true })
    end
end

function M:make_ctrl()
    local nav  = self
    local menu = self.menu
    return {
        remove = function()
            if menu:has_history() then
                local parent     = menu.history[#menu.history]
                local parent_idx = parent.index
                table.remove(parent.items, parent_idx)
                parent.index = math.max(1, math.min(parent_idx, #parent.items))
                menu:pop_history()
            else
                local idx  = menu.index
                table.remove(menu.items, idx)
                menu.index = math.max(1, math.min(idx, #menu.items))
            end
            menu:_recalc_meta()
            menu:resize()
            menu:redraw()
            nav:refresh_keymaps()
            nav:on_selection_changed()
        end,
        close  = function() nav:close_all() end,
        redraw = function() menu:redraw() end,
        peek   = function(item) nav:_open_peek(item or menu:get_current_item()) end,
    }
end

function M:run_action(action, item)
    if action.fn then
        if action.keep_open then
            action.fn(self.menu.context, item, self:make_ctrl())
        else
            local ctx = self.menu.context
            self:close_all()
            vim.defer_fn(function() action.fn(ctx, item) end, 0)
        end
    elseif action.items then
        self.menu:close_panel()
        local result = self.menu:open_submenu({ type = "replace", items = action.items })
        if result and result.action == "replace" then
            self.menu:resize()
            self.menu:redraw()
            self:refresh_keymaps()
        end
    end
end

function M:move_down()
    if self.menu:has_panel() and not self.menu.config.auto_preview then return end
    if self.menu:move_down() then
        self.menu:redraw()
        self:on_selection_changed()
    end
end

function M:move_up()
    if self.menu:has_panel() and not self.menu.config.auto_preview then return end
    if self.menu:move_up() then
        self.menu:redraw()
        self:on_selection_changed()
    end
end

function M:enter()
    local item = self.menu:get_current_item()
    if not item then return end

    if item.fn then
        if item.keep_open then
            item.fn(self.menu.context, self:make_ctrl())
        else
            local ctx = self.menu.context
            self:close_all()
            vim.defer_fn(function() item.fn(ctx) end, 0)
        end
        return
    end

    if item.panel_content then
        if self.menu.config.auto_preview then return end
        if self.menu:has_panel() then
            self.menu:close_panel()
        else
            local content, ft, pos = self.menu:get_panel_content(item)
            self.menu:open_panel(content, ft, pos)
        end
        return
    end

    if item.submenu then
        self.menu:close_panel()
        local result = self.menu:open_submenu(item.submenu)
        if result and result.action == "nested" then
            self:open_nested(result.items)
        elseif result and result.action == "replace" then
            self.menu:resize()
            self.menu:redraw()
            self:refresh_keymaps()
            self:on_selection_changed()
        end
    end
end

function M:back()
    if self.menu:has_panel() then
        self.menu:close_panel()
        return
    end
    if #self.nested_menus > 0 then
        self:close_nested()
        return
    end
    if self.menu:has_history() then
        self.menu:pop_history()
        self.menu:resize()
        self.menu:redraw()
        self:refresh_keymaps()
        self:on_selection_changed()
    end
end

function M:jump_by_key(key)
    self.menu:jump_by_key(key)
end

function M:open_nested(items)
    local nested_menu = require("nv-menu.menu").new({
        name  = self.menu.name,
        items = items,
    })

    local parent_win = self.menu.window:get_win_id()
    if not parent_win or not vim.api.nvim_win_is_valid(parent_win) then return end

    local parent_width   = vim.api.nvim_win_get_width(parent_win)
    local parent_scr_col = vim.api.nvim_win_call(parent_win, function()
        return vim.fn.win_screenpos(0)[2]
    end) - 1

    local actual_width, actual_height = nested_menu:get_actual_dimensions()
    local sub_total = actual_width + 2

    local sub_col
    if parent_scr_col + parent_width + 2 + sub_total <= vim.o.columns then
        sub_col = parent_width + 1
    elseif parent_scr_col >= sub_total then
        sub_col = -(actual_width + 3)
    else
        sub_col = parent_width + 1
    end

    nested_menu.window:create()

    local win_config = {
        relative = "win",
        win      = parent_win,
        width    = actual_width,
        height   = actual_height + 2,
        anchor   = "NW",
        row      = 0,
        col      = sub_col,
        border   = "single",
        style    = "minimal",
        zindex   = 100,
    }

    if nested_menu.name and nested_menu.name ~= "" then
        win_config.title     = " " .. nested_menu.name .. " "
        win_config.title_pos = "center"
    end

    nested_menu.window:open_floating(win_config)
    nested_menu.renderer:render()
    nested_menu.nav_keys = self.menu.nav_keys

    table.insert(self.nested_menus, { menu = self.menu, nav = self })
    self.menu     = nested_menu
    self.menu.nav = self
    self:setup_keymaps()
    self.menu:redraw()
end

function M:close_nested()
    if #self.nested_menus > 0 then
        local prev = table.remove(self.nested_menus)
        self.menu:close()
        self.menu = prev.menu
        self:setup_keymaps()
        self.menu:redraw()
        self:on_selection_changed()
    end
end

function M:refresh_keymaps()
    self:setup_keymaps()
end

function M:update_items(items)
    self.menu.items  = items
    self.menu.index  = 1
    self.menu.scroll = 0
    self.menu:_recalc_meta()
    self.menu:resize()
    self.menu:redraw()
    self:refresh_keymaps()
    self:on_selection_changed()
end

function M:cleanup()
    if self.augroup then
        vim.api.nvim_del_augroup_by_id(self.augroup)
        self.augroup = nil
    end
    if self._active_action_buf and vim.api.nvim_buf_is_valid(self._active_action_buf) then
        for _, key in ipairs(self._active_action_keys) do
            pcall(vim.keymap.del, "n", key, { buffer = self._active_action_buf })
        end
    end
    self._active_action_keys = {}
    self._active_action_buf  = nil
end

function M:close_all()
    self:cleanup()
    while #self.nested_menus > 0 do
        local prev = table.remove(self.nested_menus)
        self.menu:close()
        self.menu = prev.menu
    end
    self.menu:close()
    if self.close_callback then
        self.close_callback()
    end
end

function M:on_close(cb)
    self.close_callback = cb
end

return M
