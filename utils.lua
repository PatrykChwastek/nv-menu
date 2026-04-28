local M = {}

---@param text string
---@param max_width integer
---@return string
function M.truncate(text, max_width)
    if #text <= max_width then
        return text
    end
    return text:sub(1, max_width - 2) .. ".."
end

---@param path string
---@param max_width integer
---@return string
function M.fit_path(path, max_width)
    local p = path:gsub("\\", "/")
    if #p <= max_width then return p end

    local parts = vim.split(p, "/", { plain = true })
    local name  = parts[#parts]

    local abbrev = {}
    for i = 1, #parts - 1 do
        local seg  = parts[i]
        abbrev[i]  = seg ~= "" and seg:sub(1, 1) or ""
    end
    abbrev[#parts] = name
    local short = table.concat(abbrev, "/"):gsub("^/", "")

    if #short <= max_width then return short end
    return name
end

---@param items NvMenuItem[]
---@param custom_keys string[]
---@return table<string, integer>
function M.generate_nav_keys(items, custom_keys)
    local keys   = {}
    local auto_n = 1
    for i, item in ipairs(items) do
        if item.nav_key then
            keys[item.nav_key] = i
        else
            if #custom_keys > 0 then
                local k = custom_keys[auto_n]
                if k then keys[k] = i end
            elseif auto_n <= 9 then
                keys[tostring(auto_n)] = i
            end
            auto_n = auto_n + 1
        end
    end
    return keys
end

---@return NvMenuContext
function M.capture_context()
    local mode   = vim.fn.mode()
    local bufnr  = vim.api.nvim_get_current_buf()
    local winnr  = vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local word   = vim.fn.expand("<cword>")

    local visual = nil
    if mode == "v" or mode == "V" or mode == "\22" then
        local ok, lines = pcall(vim.fn.getregion,
            vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
        if ok and lines then
            visual = table.concat(lines, "\n")
        end
    end

    return { bufnr = bufnr, winnr = winnr, cursor = cursor, word = word, visual = visual, mode = mode }
end

function M.get_cursor_pos()
    return {
        row = vim.fn.winline() - 1,
        col = vim.fn.wincol()  - 1,
        win = vim.api.nvim_get_current_win(),
    }
end

---@param menu_width integer
---@param menu_height integer
---@param position string
---@param cursor_override? {row:integer,col:integer,win:integer}
---@return vim.api.keyset.win_config
function M.get_win_config(menu_width, menu_height, position, cursor_override)
    local win_height = vim.o.lines
    local win_width  = vim.o.columns
    local cursor     = cursor_override or M.get_cursor_pos()

    local config = {
        relative = "editor",
        width    = menu_width,
        height   = menu_height,
        border   = "single",
        style    = "minimal",
    }

    local total_w    = menu_width  + 2
    local total_h    = menu_height + 2
    local bottom_row = win_height - total_h - vim.o.cmdheight - 1
    local center_row = math.floor((win_height - total_h) / 2) - vim.o.cmdheight

    if position == "center" then
        config.row = center_row
        config.col = math.floor((win_width - total_w) / 2)

    elseif position == "centerleft" then
        config.row = center_row
        config.col = 0

    elseif position == "centerright" then
        config.row = center_row
        config.col = win_width - total_w

    elseif position == "topleft" then
        config.row = 0
        config.col = 0

    elseif position == "topright" then
        config.row = 0
        config.col = win_width - total_w

    elseif position == "bottomleft" then
        config.row = bottom_row
        config.col = 0

    elseif position == "bottomright" then
        config.row = bottom_row
        config.col = win_width - total_w

    elseif position == "cursor" then
        config.relative = "cursor"
        config.anchor   = "NW"
        config.row      = 1

        local screen_col = vim.fn.screencol()
        local col        = -math.floor(total_w / 2)
        col = math.max(col, 1 - screen_col)
        col = math.min(col, win_width - screen_col - total_w + 1)
        config.col = col
    end

    return config
end

return M
