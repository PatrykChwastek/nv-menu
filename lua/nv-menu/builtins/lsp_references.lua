local utils = require("nv-menu.utils")

local CONTEXT_LINES = 25

local function file_preview(fname, line, col, end_col)
    local ok, lines = pcall(vim.fn.readfile, fname)
    if not ok or not lines then return "", nil, nil end
    local top    = math.max(1, line + 1 - CONTEXT_LINES)
    local bottom = math.min(#lines, line + 1 + CONTEXT_LINES)
    local slice  = vim.list_slice(lines, top, bottom)
    local ft     = vim.filetype.match({ filename = fname }) or ""
    local pos    = { line = line + 2 - top, col = col, hl_start = col, hl_end = end_col }
    return table.concat(slice, "\n"), ft, pos
end

local function build_items(locations, max_label)
    local items = {}
    for _, loc in ipairs(locations) do
        local fname   = vim.uri_to_fname(loc.uri)
        local line    = loc.range.start.line
        local col     = loc.range.start.character
        local end_col = loc.range["end"].character
        local rel   = vim.fn.fnamemodify(fname, ":.")
        local label = utils.fit_path(rel, max_label) .. ":" .. (line + 1)
        table.insert(items, {
            label         = label,
            panel_content = function() return file_preview(fname, line, col, end_col) end,
            fn            = function()
                vim.cmd("edit " .. vim.fn.fnameescape(fname))
                vim.api.nvim_win_set_cursor(0, { line + 1, col })
            end,
            actions = {
                { key = "o", label = "options", items = {
                    { label = "Vertical split",   nav_key = "v", fn = function()
                        vim.cmd("vsplit " .. vim.fn.fnameescape(fname))
                        vim.api.nvim_win_set_cursor(0, { line + 1, col })
                    end },
                    { label = "Horizontal split", nav_key = "h", fn = function()
                        vim.cmd("split " .. vim.fn.fnameescape(fname))
                        vim.api.nvim_win_set_cursor(0, { line + 1, col })
                    end },
                    { label = "Open in tab",      nav_key = "t", fn = function()
                        vim.cmd("tabnew " .. vim.fn.fnameescape(fname))
                        vim.api.nvim_win_set_cursor(0, { line + 1, col })
                    end },
                }},
            },
        })
    end
    return items
end

return function(opts)
    opts = opts or {}

    local bufnr  = vim.api.nvim_get_current_buf()
    local params = vim.lsp.util.make_position_params()
    params.context = { includeDeclaration = true }

    local max_label = (opts.max_width or 40) - 10
    local nv_menu   = require("nv-menu")

    nv_menu.show_loading(vim.tbl_extend("force", {
        name         = "References",
        panel_width  = 60,
        auto_preview = false,
        item_actions = { require("nv-menu.builtins").peek_action },
    }, opts))

    vim.lsp.buf_request_all(bufnr, "textDocument/references", params, function(results)
        local locations = {}
        for _, res in pairs(results or {}) do
            if res.result then
                vim.list_extend(locations, res.result)
            end
        end

        if #locations == 0 then
            nv_menu.close()
            vim.notify("No LSP references found", vim.log.levels.WARN)
            return
        end

        nv_menu.update_items(build_items(locations, max_label))
    end)
end
