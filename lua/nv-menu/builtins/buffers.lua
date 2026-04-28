local utils = require("nv-menu.utils")

local CONTEXT_LINES = 25

local function get_preview(buf, line)
    if not vim.api.nvim_buf_is_loaded(buf) then
        vim.fn.bufload(buf)
    end
    local line_count = vim.api.nvim_buf_line_count(buf)

    local cursor
    if line then
        cursor = math.max(1, math.min(line + 1, line_count))
    else
        local mark = vim.api.nvim_buf_get_mark(buf, '"')
        cursor = math.max(1, math.min(mark[1], line_count))
    end

    local top    = math.max(0, cursor - CONTEXT_LINES - 1)
    local bottom = math.min(line_count, cursor + CONTEXT_LINES)
    local pos    = { line = cursor - top }
    return table.concat(vim.api.nvim_buf_get_lines(buf, top, bottom, false), "\n"), vim.bo[buf].filetype, pos
end

return function(opts)
    opts = opts or {}

    local max_label = (opts.max_width or 40) - 6
    local items     = {}

    if opts.bufs then
        for _, entry in ipairs(opts.bufs) do
            local buf  = entry.bufnr
            local lbl  = entry.label
            if not lbl then
                lbl = utils.fit_path(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":."), max_label)
            end
            local line = entry.line
            local col  = entry.col or 0
            table.insert(items, {
                label         = lbl,
                panel_content = entry.panel_content or function() return get_preview(buf, line) end,
                fn            = entry.fn or function()
                    vim.api.nvim_set_current_buf(buf)
                    if line then
                        vim.api.nvim_win_set_cursor(0, { line + 1, col })
                    end
                end,
                actions = entry.actions,
            })
        end
    else
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
                local label = utils.fit_path(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":."), max_label)
                table.insert(items, {
                    label         = label,
                    panel_content = function() return get_preview(buf) end,
                    fn            = function() vim.api.nvim_set_current_buf(buf) end,
                    actions = {
                        { key = "o", label = "options", items = {
                            { label = "Vertical split",   nav_key = "v", fn = function() vim.cmd("vsplit"); vim.api.nvim_set_current_buf(buf) end },
                            { label = "Horizontal split", nav_key = "h", fn = function() vim.cmd("split");  vim.api.nvim_set_current_buf(buf) end },
                            { label = "Open in tab",      nav_key = "t", fn = function() vim.cmd("tabnew"); vim.api.nvim_set_current_buf(buf) end },
                            { label = "Delete", nav_key = "d", keep_open = true, fn = function(ctx, ctrl)
                                if vim.bo[buf].modified then
                                    local name   = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
                                    local choice = vim.fn.confirm("Save changes to " .. name .. "?", "&Yes\n&No\n&Cancel", 3)
                                    if choice == 0 or choice == 3 then return end
                                    if choice == 1 then
                                        vim.api.nvim_buf_call(buf, function() vim.cmd("silent write") end)
                                    end
                                end
                                if ctx.bufnr == buf then
                                    local others = vim.tbl_filter(function(b)
                                        return vim.api.nvim_buf_is_loaded(b)
                                            and vim.api.nvim_buf_get_name(b) ~= ""
                                            and b ~= buf
                                    end, vim.api.nvim_list_bufs())
                                    ctrl.close()
                                    if #others > 0 then
                                        vim.api.nvim_set_current_buf(others[1])
                                    else
                                        vim.cmd("enew")
                                    end
                                    vim.api.nvim_buf_delete(buf, { force = true })
                                else
                                    vim.api.nvim_buf_delete(buf, { force = true })
                                    ctrl.remove()
                                end
                            end },
                        }},
                    },
                })
            end
        end
    end

    if #items == 0 then
        vim.notify("No buffers", vim.log.levels.WARN)
        return
    end

    require("nv-menu").show(vim.tbl_extend("force", {
        name         = "Buffers",
        position     = "centerleft",
        auto_preview = false,
        panel_width  = 60,
        item_actions = { require("nv-menu.builtins").peek_action },
    }, opts, { items = items, bufs = nil }))
end
