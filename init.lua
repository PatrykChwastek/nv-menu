local types = require("nv-menu.types")

local M = {
    config   = types.config,
    builtins = require("nv-menu.builtins"),
    _current_menu = nil,
    _current_nav  = nil,
}

---@param opts? NvMenuConfig
function M.setup(opts)
    types.setup(opts)
    M.config = types.config
end

---@param opts NvMenuOpts
---@return NvMenuInstance
function M.show(opts)
    -- must run before any window is created (cursor still in source buffer)
    local ctx = require("nv-menu.utils").capture_context()

    if M._current_menu then
        M._current_menu:close()
        M._current_menu = nil
        M._current_nav  = nil
    end

    local Menu       = require("nv-menu.menu")
    local Navigation = require("nv-menu.navigation")

    local menu = Menu.new(opts)
    menu.context = ctx
    local nav = Navigation.new(menu)

    menu:show()
    nav:setup_keymaps()
    nav:on_selection_changed()

    nav:on_close(function()
        M._current_menu = nil
        M._current_nav  = nil
    end)

    M._current_menu = menu
    M._current_nav  = nav

    return menu
end

---@param opts NvMenuOpts  Same as show(); items are replaced with a "Loading…" placeholder
---@return NvMenuInstance
function M.show_loading(opts)
    return M.show(vim.tbl_extend("force", opts, {
        items = { { label = "Loading…" } },
    }))
end

---@param items NvMenuItem[]  Replaces the item list in the currently open menu and redraws
function M.update_items(items)
    if M._current_nav then
        M._current_nav:update_items(items)
    end
end

--- Close all menus, including any orphaned floating windows with nv_menu buffers
function M.close_all()
    if M._current_nav then
        M._current_nav:close_all()
        return
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].nv_menu then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
end

--- Close the current menu
function M.close()
    if M._current_menu then
        M._current_menu:close()
        M._current_menu = nil
        M._current_nav  = nil
    end
end

return M
