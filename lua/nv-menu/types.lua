---@class NvMenuContext
---@field bufnr integer Source buffer number
---@field winnr integer Source window handle
---@field cursor number[] Cursor position {row 1-indexed, col 0-indexed}
---@field word string Word under cursor at open time
---@field visual string|nil Selected text (non-nil when opened from visual mode)
---@field mode string Vim mode at open time

---@class NvMenuCtrl
---@field remove fun() Remove the current item from the list and redraw
---@field close  fun() Close the menu entirely
---@field redraw fun() Redraw the menu in place
---@field peek   fun(item?: NvMenuItem) Open a large centered read-only preview for item (q/Esc to close)

---@class NvMenuAction
---@field key string Single character trigger key (active only when cursor is on the item)
---@field label string Short display label shown as hint on the selected item
---@field fn? fun(ctx: NvMenuContext, item: NvMenuItem, ctrl?: NvMenuCtrl) Called when action key is pressed
---@field items? NvMenuItem[] Open as a replace submenu instead of running fn
---@field keep_open? boolean Keep menu open after fn runs (fn receives ctrl as third arg)

---@class NvMenuItem
---@field label string Item display label
---@field fn? fun(ctx: NvMenuContext, ctrl?: NvMenuCtrl) Callback when item is activated (Enter); receives ctrl only when keep_open=true
---@field keep_open? boolean Keep menu open after fn runs; fn receives ctrl as second arg
---@field nav_key? string Single character key to jump to and activate this item instantly
---@field submenu? NvMenuSubmenu Submenu configuration
---@field panel_content? string|fun(): string, string?, {line?:integer,col?:integer,hl_start?:integer,hl_end?:integer}? Side panel content; function is lazily called on first hover and cached
---@field panel_ft? string Filetype hint for syntax highlighting (ignored when panel_content fn returns ft)
---@field actions? NvMenuAction[] Per-item context actions shown as footer hints; active only when this item is selected

---@class NvMenuSubmenu
---@field type "nested"|"replace" Submenu behavior
---@field items NvMenuItem[] Items in submenu

---@class NvMenuConfig
---@field position "cursor"|"center"|"centerleft"|"centerright"|"topleft"|"topright"|"bottomleft"|"bottomright" Menu anchor position
---@field max_height number Maximum visible items
---@field max_width number Maximum label width (before truncation)
---@field highlight string Highlight group for selected item
---@field highlight_bg string Highlight background color
---@field highlight_fg string Highlight foreground color
---@field border "single"|"none"|"double"|"rounded" Border style
---@field border_hl string|nil Highlight group for window borders (nil = colorscheme default)
---@field title_hl string|nil Highlight group for window titles (nil = colorscheme default)
---@field close_keys string[] Keys to close menu
---@field nav_keys string[] Keys for quick nav (auto-filled with 1-9 if empty)
---@field panel_width number Width of side panel buffer
---@field panel_wrap boolean Wrap text in the side panel (default false)
---@field item_actions NvMenuAction[] Menu-level actions applied to every item; item-level actions override by key

---@class NvMenuOpts : NvMenuConfig
---@field name? string Menu window title
---@field items? NvMenuItem[] Items to display
---@field footer? string|string[] Static footer text shown below the list
---@field auto_preview? boolean Automatically open/update panel as cursor moves (default false)
---@field bufs? nil Internal — cleared before passing to show(); do not set

---@class NvMenuInstance
---@field name string Menu display name
---@field items NvMenuItem[] Current items being displayed
---@field config NvMenuConfig Merged config
---@field index number Current selection index (1-based)
---@field scroll number Current scroll offset
---@field nav_keys table<string, number> Map of key -> item index
---@field history NvMenuItem[][] Stack of previous item lists (for replace navigation)

---@class NvMenu
---@field config NvMenuConfig
local M = {}

---@type NvMenuConfig
M.config = {
    position = "cursor",
    max_height = 10,
    max_width = 40,
    highlight = "NvMenuCursor",
    highlight_bg = "#3a3a4a",
    highlight_fg = "#ffffff",
    border    = "single",
    border_hl = nil,
    title_hl  = nil,
    close_keys = { "<Esc>", "q" },
    nav_keys = {},
    panel_width = 40,
    panel_wrap = false,
    item_actions = {},
}

---@param opts? NvMenuConfig
function M.setup(opts)
    if opts then
        M.config = vim.tbl_deep_extend("force", M.config, opts)
    end
end

return M
