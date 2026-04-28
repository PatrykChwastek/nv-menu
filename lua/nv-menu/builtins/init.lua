-- Built-in menus, loaded lazily on first call
local M = {}

local function lazy(name)
    return function(opts)
        return require("nv-menu.builtins." .. name)(opts)
    end
end

M.buffers        = lazy("buffers")
M.lsp_references = lazy("lsp_references")

M.peek_action = {
    key       = "p",
    label     = "peek",
    keep_open = true,
    fn        = function(ctx, item, ctrl) ctrl.peek(item) end,
}

return M
