# nv-menu

Floating popup menu for Neovim. Support submenus, side-panel previews, per-item context actions, fast navigation via keys, and more.

[![nv-menu-demo](https://i.postimg.cc/0rRShvn6/nv-menu-demo1.gif)](https://postimg.cc/0KnrJLLx)

> At first, I built this for my own simple scenarios. After a while, it grew into something bigger, 
> so I decided to turn it into a proper plugin(I hope so). Maybe someone will find it useful.

## Installation

### lazy.nvim

```lua
{
    "your-username/nv-menu",
    config = function()
        require("nv-menu").setup({
            position   = "cursor",
            max_height = 10,
        })
    end,
}
```

### packer.nvim

```lua
use {
    "your-username/nv-menu",
    config = function()
        require("nv-menu").setup({})
    end,
}
```

---

## Setup

All fields are optional defaults are shown below.

```lua
require("nv-menu").setup({
    position     = "cursor",   -- where the menu spawns. Options: (see Positions)
    max_height   = 10,         -- max visible items; list scrolls when exceeded
    max_width    = 40,         -- labels longer than this are truncated
    border       = "single",   -- "single" | "double" | "rounded" | "none"
    panel_width  = 40,         -- width of the side preview panel
    panel_wrap   = false,      -- wrap text in the side panel
    close_keys   = { "<Esc>", "q" },
    nav_keys     = {},         -- see Nav keys section

    -- selected-item highlight (the group is auto-created from these colors)
    highlight    = "NvMenuCursor",
    highlight_bg = "#3a3a4a",
    highlight_fg = "#ffffff",

    -- override border and title colors; nil = use colorscheme defaults
    -- point these at any existing highlight group in your colorscheme
    border_hl = nil,
    title_hl  = nil,
})
```

### Positions

```
"cursor"                    -- directly below the cursor (default)
"center"
"centerleft"  "centerright" -- vertically centered, pinned to left/right edge
"topleft"     "topright"  
"bottomleft"  "bottomright"
```

---

## Module API

```lua
local nv = require("nv-menu")

nv.setup(opts)            -- merge opts into global config
nv.show(opts)             -- open a menu; returns the menu instance
nv.show_loading(opts)     -- open immediately with a "Loading…" placeholder item
nv.update_items(items)    -- swap items in the currently open menu and redraw
nv.close()                -- close the current menu
nv.close_all()            -- close all menus, including any orphaned windows
```

---

## Basic menu

```lua
require("nv-menu").show({
    name  = "My Menu",          -- shown as the window title
    items = {
        {
            label = "Say hello",
            fn    = function(ctx)
                print("word under cursor was: " .. ctx.word)
            end,
        },
    },
})
```

### Context (ctx)

Every item `fn` receives a `ctx` table that captures the editor state at the moment the menu was opened before menu is created, so the cursor is still in the source buffer. This is useful for LSP calls, rename workflows, acting on selections, etc.

```lua
---@field bufnr  integer     source buffer number
---@field winnr  integer     source window handle
---@field cursor number[]    { row 1-indexed, col 0-indexed }
---@field word   string      word under cursor
---@field visual string|nil  selected text non-nil only when opened from visual mode
---@field mode   string      vim mode at menu open time ("n", "v", "V", ...)

-- example: jump back to source and trigger LSP rename
fn = function(ctx)
    vim.api.nvim_set_current_win(ctx.winnr)
    vim.api.nvim_win_set_cursor(ctx.winnr, ctx.cursor)
    vim.lsp.buf.rename()
end,
```

---

## All item fields

```lua
{
    label   = "Name",    -- required; displayed in the list

    -- called when item is activated (<Enter>)
    -- menu closes before fn runs, unless keep_open = true
    fn      = function(ctx) end,

    -- when true the menu stays open and fn receives a second ctrl argument
    keep_open = false,

    -- single character for instant jump + activate (see Nav keys)
    nav_key = "n",

    -- static string or lazy function (called on first hover, result cached)
    -- function can return (content, filetype, pos) — see Side panel
    panel_content = "preview text",
    panel_ft      = "lua",       -- filetype hint for syntax highlighting

    -- opens a child menu; see Submenus
    submenu = { type = "nested", items = { ... } },

    -- per-item context actions shown in the footer; see Actions
    actions = {
        { key = "d", label = "delete", fn = function(ctx, item) end },
    },
}
```

---

## Nav keys

Nav keys let you jump directly to an item and activate it with a single keypress.

**Item-level** — set `nav_key` on individual items. That key is reserved for that item and is never overridden:

```lua
{ label = "Vertical split",   nav_key = "v", fn = ... },
{ label = "Horizontal split", nav_key = "h", fn = ... },
{ label = "Open in tab",      nav_key = "t", fn = ... },
```

**Auto-numbering** — items without a `nav_key` are automatically assigned `1`–`9` in order. Items that already have an explicit `nav_key` are skipped so numbers never conflict with them:

```lua
items = {
    { label = "Alpha",   nav_key = "a", fn = ... },  -- key: "a"
    { label = "Beta",    nav_key = "b", fn = ... },  -- key: "b"
    { label = "Gamma",   fn = ... },                 -- auto: "1"
    { label = "Delta",   fn = ... },                 -- auto: "2"
}
```

**Custom key set** — set `nav_keys` in setup or per-menu to replace the default 1–9:

```lua
require("nv-menu").show({
    nav_keys = { "f", "g", "h" },   -- items without nav_key get f, g, h instead
    items = { ... },
})
```

---

## keep_open + ctrl

By default activating an item or action closes the menu before calling `fn`. Set `keep_open = true` to keep the menu open, useful when an action should run multiple times without reopening (e.g. deleting several buffers one by one).

When `keep_open = true`, `fn` receives a `ctrl` object as its second argument (third for actions, after `ctx` and `item`):

```lua
{
    label     = "Delete item",
    keep_open = true,
    fn        = function(ctx, ctrl)
        -- remove this item from the list and redraw in place
        ctrl.remove()

        -- close the menu programmatically (e.g. after the last item is removed)
        -- ctrl.close()

        -- just redraw without any structural changes
        -- ctrl.redraw()

        -- open a large read-only floating preview for the given item
        -- ctrl.peek(item)
    end,
}

-- actions follow the same pattern: (ctx, item, ctrl)
{ key = "d", label = "delete", keep_open = true,
  fn = function(ctx, item, ctrl)
      delete_thing(item)
      ctrl.remove()
  end,
}
```

`ctrl.remove()` is aware of replace-submenu history if you're inside a replace submenu when it's called, it removes the parent item and pops back to the parent list.

---

## Submenus

```lua
-- nested: opens as a separate floating window beside the parent
-- h /<left> closes the child and returns focus to the parent
{ label = "Refactor", submenu = { type = "nested", items = {
    { label = "Extract function", fn = ... },
    { label = "Inline variable",  fn = ... },
}}}

-- replace: the current item list is replaced in the same window
-- history is kept; h / <left> navigates back to the previous list
-- the window resizes automatically when switching back and forth
{ label = "Options", submenu = { type = "replace", items = {
    { label = "Vertical split",   nav_key = "v", fn = ... },
    { label = "Horizontal split", nav_key = "h", fn = ... },
    { label = "Open in tab",      nav_key = "t", fn = ... },
}}}
```

---

## Side panel

A side panel is a read-only floating window that opens beside the menu to show additional content for the selected item file previews, documentation, etc.

```lua
{
    label = "View file",
    -- called lazily on first access and cached; won't re-read on every cursor move
    panel_content = function()
        local lines = vim.fn.readfile("path/to/file.lua")
        return table.concat(lines, "\n"), "lua"   -- content, filetype
    end,
}
```

The function can return a third `pos` value to scroll the panel to a specific location and add a highlight (useful for showing exact match positions):

```lua
panel_content = function()
    return content, "lua", {
        line     = 10,   -- 1-indexed line to scroll to
        col      = 5,    -- cursor column inside the panel
        hl_start = 5,    -- start col of the highlight (uses Search group)
        hl_end   = 12,   -- end col of the highlight
    }
end
```

**`auto_preview = false`** (default) — `<Enter>` / `l` toggles the panel for the selected item. Press `h` to close it.

**`auto_preview = true`** — panel opens and updates automatically as the cursor moves through items. `j`/`k` are locked while the panel is open unless `auto_preview` is on.

---

## Actions

Actions are per-item context keys shown as hints in the footer. They are only active when the item they belong to is selected — pressing the key runs the action without closing the menu unless `keep_open = false`.

```lua
{
    label   = "Build",
    fn      = function(ctx) vim.cmd("make") end,
    actions = {
        -- key: single character trigger shown in footer
        -- label: short description shown in footer hint
        { key = "c", label = "clean",   fn = function(ctx, item) vim.cmd("make clean")   end },
        { key = "r", label = "release", fn = function(ctx, item) vim.cmd("make release") end },
    },
}
```

**Menu-level actions** via `item_actions` apply to every item in the menu. Item-level
`actions` take priority on key conflicts:

```lua
require("nv-menu").show({
    -- this "p" peek action will appear for every item that has panel_content
    item_actions = {
        { key = "p", label = "peek", keep_open = true,
          fn = function(ctx, item, ctrl) ctrl.peek(item) end },
    },
    items = { ... },
})
```

Actions can open a replace submenu instead of calling `fn`:

```lua
{ key = "o", label = "options", items = {
    { label = "Vertical split",   nav_key = "v", fn = ... },
    { label = "Horizontal split", nav_key = "h", fn = ... },
}}
```

---

## Losding in menus(async)

Some operations — like querying LSP — take time and would freeze the UI if awaited before opening the menu. `show_loading` opens the menu immediately with a placeholder, then `update_items` swaps in the real results when they arrive. The menu is fully interactive during the wait (you can close it, scroll, etc.).

```lua
local nv = require("nv-menu")

-- open instantly with a placeholder so the user sees something right away
nv.show_loading({ name = "References", position = "cursor" })

-- query runs async; the menu is already visible at this point
vim.lsp.buf_request_all(bufnr, "textDocument/references", params, function(results)
    local items = build_items(results)
    if #items == 0 then
        nv.close()
        vim.notify("No references found", vim.log.levels.WARN)
        return
    end
    -- swap placeholder with real items; window resizes automatically
    nv.update_items(items)
end)
```

---

## Built-ins
Predifined menues

### Buffers
Menu to navigate and manage current buffers. 

[![buffers-preview.png](https://i.postimg.cc/fbxfzv5p/buffers-preview.png)](https://postimg.cc/PL5wKYgQ)

```lua
require("nv-menu").builtins.buffers()

require("nv-menu").builtins.buffers({
    position     = "centerleft",
    auto_preview = true,
    panel_width  = 60,
})

-- custom buffer list — feed any source (e.g. quickfix, LSP locations)
require("nv-menu").builtins.buffers({
    bufs = {
        {
            label         = "src/foo.lua:42",
            panel_content = function() return content, "lua", pos end,
            fn            = function() vim.cmd("edit src/foo.lua") end,
        },
    },
})
```

Contains actions: `p` peek buffer in flating window,  `o` options submenu (`v` vsplit / `h` hsplit /`t` tab / `d` delete).

Deleting a buffer with unsaved changes opens a native `vim.fn.confirm` prompt to confirm. Deleting the current buffer switches to the next available buffer (or `enew`).

### LSP References
Show all LSP references, at text object under the cursor.

[![lsp-ref-preview.png](https://i.postimg.cc/sg8GkZzs/lsp-ref-preview.png)](https://postimg.cc/QFQM5CVy)

Opens immediately with a loading placeholder and queries all LSP clients asynchronously.

```lua
require("nv-menu").builtins.lsp_references()

require("nv-menu").builtins.lsp_references({
    position    = "center",
    panel_width = 80,
})
```

### peek_action

A pre-built `item_actions` entry that adds `p` peek to any menu with preview items. Both built-ins include it automatically. To add it to a custom menu:

```lua
require("nv-menu").show({
    item_actions = { require("nv-menu.builtins").peek_action },
    items = { ... },
})
```

Peek opens floating window centered on screen. Closes with `q` / `<Esc>`, then returning focus to the menu.

---
## Custom highlights example

```lua
vim.api.nvim_set_hl(0, "MyBorder", { fg = "#7aa2f7" })
vim.api.nvim_set_hl(0, "MyTitle",  { fg = "#bb9af7", bold = true })
require("nv-menu").setup({ border_hl = "MyBorder", title_hl = "MyTitle" })
```

---
## Keyboard reference

| Key | Action |
|-----|--------|
| `j` / `<Down>` | move down |
| `k` / `<Up>` | move up |
| `<C-d>` | half page down |
| `<C-u>` | half page up |
| `<C-f>` | full page down |
| `<C-b>` | full page up |
| `gg` | jump to first item |
| `G` | jump to last item |
| `<Enter>` / `l` / `→` | activate item · open submenu · toggle panel |
| `h` / `<Left>` | close panel → pop replace history → close nested menu |
| `1` - `9` | jump to first 9 item by nav key and activate |
| `q` / `<Esc>` | close menu |

---

## Identifying menu buffers

Every menu buffer has `vim.b[buf].nv_menu = true`, which lets you target them in
autocmds or from keymaps:

```lua
-- close all menus from anywhere (e.g. a global keymap)
require("nv-menu").close_all()

-- prevent accidental writes to menu buffers
vim.api.nvim_create_autocmd("BufWritePre", {
    callback = function(e)
        if vim.b[e.buf].nv_menu then return true end
    end,
})
```
