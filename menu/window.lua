local M = {}
M.__index = M

function M.new(config)
    local self = setmetatable({}, M)
    self.win_id       = nil
    self.buf_id       = nil
    self.panel_win_id = nil
    self.panel_buf_id = nil
    self.config       = config
    self.title        = ""
    self.panel_hl_ns  = vim.api.nvim_create_namespace("nvmenu_panel")
    return self
end

function M:create()
    self.buf_id = vim.api.nvim_create_buf(false, true)
    vim.bo[self.buf_id].bufhidden  = "wipe"
    vim.bo[self.buf_id].modifiable = false
    vim.b[self.buf_id].nv_menu     = true
    return self.buf_id
end

function M:set_title(title)
    self.title = title or ""
end

function M:_build_winhighlight()
    local parts = {}
    if self.config.border_hl then table.insert(parts, "FloatBorder:" .. self.config.border_hl) end
    if self.config.title_hl  then table.insert(parts, "FloatTitle:"  .. self.config.title_hl)  end
    return #parts > 0 and table.concat(parts, ",") or nil
end

function M:open_floating(config)
    if not self.buf_id then
        self:create()
    end

    local float_config       = vim.deepcopy(config)
    float_config.border      = self.config.border
    float_config.style       = "minimal"
    float_config.zindex      = 100

    if self.title and self.title ~= "" then
        float_config.title     = " " .. self.title .. " "
        float_config.title_pos = "center"
    end

    self.win_id = vim.api.nvim_open_win(self.buf_id, true, float_config)

    vim.wo[self.win_id].number         = false
    vim.wo[self.win_id].relativenumber = false
    vim.wo[self.win_id].foldcolumn     = "0"
    vim.wo[self.win_id].signcolumn     = "no"
    vim.wo[self.win_id].spell          = false
    vim.wo[self.win_id].wrap           = false
    vim.wo[self.win_id].cursorline     = false

    local whl = self:_build_winhighlight()
    if whl then vim.wo[self.win_id].winhighlight = whl end

    return self.win_id
end

function M:_apply_panel_pos(pos)
    if not pos then return end
    if not self.panel_win_id or not vim.api.nvim_win_is_valid(self.panel_win_id) then return end

    local line_count  = vim.api.nvim_buf_line_count(self.panel_buf_id)
    local target_line = math.max(1, math.min(pos.line or 1, line_count))

    vim.api.nvim_win_set_cursor(self.panel_win_id, { target_line, pos.col or 0 })

    vim.api.nvim_buf_clear_namespace(self.panel_buf_id, self.panel_hl_ns, 0, -1)
    if pos.hl_start and pos.hl_end then
        vim.api.nvim_buf_add_highlight(
            self.panel_buf_id, self.panel_hl_ns,
            "Search", target_line - 1, pos.hl_start, pos.hl_end
        )
    end
end

function M:open_panel(content, ft, width, height, wrap, pos)
    self.panel_buf_id = vim.api.nvim_create_buf(false, true)
    vim.bo[self.panel_buf_id].bufhidden = "wipe"
    if ft then
        vim.bo[self.panel_buf_id].filetype = ft
    end

    vim.api.nvim_buf_set_lines(self.panel_buf_id, 0, -1, false, vim.split(content, "\n"))

    local parent_win     = self.win_id
    local parent_width   = vim.api.nvim_win_get_width(parent_win)
    local parent_scr_col = vim.api.nvim_win_call(parent_win, function()
        return vim.fn.win_screenpos(0)[2]
    end) - 1

    local panel_col
    if parent_scr_col + parent_width + 2 + width + 2 <= vim.o.columns then
        panel_col = parent_width + 1
    else
        panel_col = -(width + 3)
    end

    self.panel_win_id = vim.api.nvim_open_win(self.panel_buf_id, false, {
        width    = width,
        height   = height or 20,
        relative = "win",
        win      = parent_win,
        anchor   = "NW",
        row      = 0,
        col      = panel_col,
        border   = "single",
        style    = "minimal",
        zindex   = 110,
    })

    vim.wo[self.panel_win_id].number         = false
    vim.wo[self.panel_win_id].relativenumber = false
    vim.wo[self.panel_win_id].foldcolumn     = "0"
    vim.wo[self.panel_win_id].signcolumn     = "no"
    vim.wo[self.panel_win_id].spell          = false
    vim.wo[self.panel_win_id].wrap           = wrap or false
    vim.wo[self.panel_win_id].cursorline     = true
    vim.wo[self.panel_win_id].scrolloff      = 4
    vim.wo[self.panel_win_id].sidescrolloff  = 25

    local whl = self:_build_winhighlight()
    if whl then vim.wo[self.panel_win_id].winhighlight = whl end

    self:_apply_panel_pos(pos)

    return self.panel_win_id
end

function M:update_panel_content(content, ft, pos)
    if not self.panel_buf_id or not vim.api.nvim_buf_is_valid(self.panel_buf_id) then
        return false
    end
    vim.api.nvim_buf_set_lines(self.panel_buf_id, 0, -1, false, vim.split(content, "\n"))
    if ft then
        vim.bo[self.panel_buf_id].filetype = ft
    end
    self:_apply_panel_pos(pos)
    return true
end

function M:close_panel()
    if self.panel_win_id and vim.api.nvim_win_is_valid(self.panel_win_id) then
        vim.api.nvim_win_close(self.panel_win_id, true)
        self.panel_win_id = nil
    end
    if self.panel_buf_id and vim.api.nvim_buf_is_valid(self.panel_buf_id) then
        vim.api.nvim_buf_delete(self.panel_buf_id, { force = true })
        self.panel_buf_id = nil
    end
end

function M:close()
    self:close_panel()
    if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
        vim.api.nvim_win_close(self.win_id, true)
        self.win_id = nil
    end
    if self.buf_id and vim.api.nvim_buf_is_valid(self.buf_id) then
        vim.api.nvim_buf_delete(self.buf_id, { force = true })
        self.buf_id = nil
    end
end

function M:get_win_id() return self.win_id end
function M:get_buf_id() return self.buf_id end

function M:set_lines(lines)
    if self.buf_id then
        vim.bo[self.buf_id].modifiable = true
        vim.api.nvim_buf_set_lines(self.buf_id, 0, -1, false, lines)
        vim.bo[self.buf_id].modifiable = false
    end
end

function M:add_highlight(line_idx, start_col, end_col, hl_group)
    if self.buf_id then
        vim.api.nvim_buf_add_highlight(self.buf_id, -1, hl_group, line_idx, start_col, end_col)
    end
end

function M:clear_highlights()
    if self.buf_id then
        vim.api.nvim_buf_clear_namespace(self.buf_id, -1, 0, -1)
    end
end

return M
