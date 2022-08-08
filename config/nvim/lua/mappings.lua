local cmd = vim.cmd
local wk = require("which-key")

--  write/quit typos
cmd("command! WQ wq")
cmd("command! Wq wq")
cmd("command! W w")
cmd("command! Q q")

vim.g.mapleader = ","
vim.g.maplocalleader = "\\"

localLeader = '<localleader>'
leader = '<Leader>'
endl = '<CR>'

set_keymap = vim.api.nvim_set_keymap

-- Window Movement
set_keymap('n', '<C-J>', '<C-W><C-J>', {noremap = true, desc = "move to split south"})
set_keymap('n', '<C-H>', '<C-W><C-H>', {noremap = true, desc = "move to split west"})
set_keymap('n', '<C-K>', '<C-W><C-K>', {noremap = true, desc = "move to split north"})
set_keymap('n', '<C-L>', '<C-W><C-L>', {noremap = true, desc = "move to split east"})

-- leader commands
wk.register({
    f = {
        name = " Find",
        a = { ":Ag" .. endl, "Find All Files" },
        b = { ':Buffers' .. endl, "Find Buffer" },
        h = { ':BLines' .. endl, "Find Here (in this file)"},
        l = { ':Lines' .. endl, "Find Line (in open files)"},
        f = { ':Files' .. endl, "Find File"},
    },
}, { prefix = leader })
-- leader commands that are recursive for normal and visual
wk.register({
    c = {
        name = " Comment",
        ["<space>"] = { "gcc", "Toggle" },
        a = { "gcgc", "Toggle Section" },
    },
}, { mode = "n", prefix = leader , noremap = false })
wk.register({
    c = {
        ["<space>"] = { ":Commentary" .. endl, "Toggle" },
    },

}, { mode = "v", prefix = leader , noremap = false })

-- local-leader commands
wk.register({
    e = {
        name = " edit",
        v = {
            name = " vim files",
            v = { ':edit ~/.config/nvim/init.vim' .. endl, "init.vim" },
            i = { ':edit ~/.config/nvim/lua/lua_init.lua' .. endl, "init_lua.lua" },
            m = { ':edit ~/.config/nvim/lua/mappings.lua' .. endl, "mappings.lua" },
            p = { ':edit ~/.config/nvim/lua/plugins.lua' .. endl, "plugins.lua" },
            o = { ':edit ~/.config/nvim/lua/options.lua' .. endl, "options.lua" },
            l = { ':edit ~/.config/nvim/lua/lsp.lua' .. endl, "lsp.lua" },
        },
        b = {
            name = " bash files",
            e = { ':edit ~/.bash_profile' .. endl, "~/.bash_profile" },
            b = { ':edit ~/.config/bash/bash_profile.sh' .. endl, "bash_profile.sh" },
            s = { ':edit ~/.config/bash/sanity_check.sh' .. endl, "sanity_check.sh" },
        },
    },
    r = {
        name = " reload",
        v = {
            name = " vim files",
            v = { ':source ~/.config/nvim/init.vim' .. endl, "init.vim" },
            i = { ':lua alp.utils.reload_module(lua_init)' .. endl, "init_lua.lua" },
            m = { ':lua alp.utils.reload_module(mappings)' .. endl, "mappings.lua" },
            p = { ':lua alp.utils.reload_module(plugins)' .. endl, "plugins.lua" },
            o = { ':lua alp.utils.reload_module(options)' .. endl, "options.lua" },
            l = { ':lua alp.utils.reload_module(lsp)' .. endl, "lsp.lua" },
        },
    },
    b = {
        name = " buffers",
        -- This function is still defined in init.vim
        d = { ':call DeleteHiddenBuffers()', "Delete Hidden Buffers" },
    },
    t = {
        name = " tabs",
        n = { ":tabnew"..endl, "New Tab"},
    },
}, { prefix = localLeader })


