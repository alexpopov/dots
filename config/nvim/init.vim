" private fb stuff
if filereadable(expand("$ADMIN_SCRIPTS/master.vimrc"))
  source $ADMIN_SCRIPTS/master.vimrc
endif

lua << EOF
config = require('lua_init')
EOF

" adds highlighting for Buck
autocmd BufRead,BufNewFile *.histedit.hg.txt set filetype=conf
autocmd BufRead,BufNewFile *.gitconfig set filetype=gitconfig
autocmd BufRead,BufNewFile skhdrc call SetSkhdrcSettings()
autocmd BufRead,BufNewFile *.json set filetype=jsonc

function! SetSkhdrcSettings()
    syntax match alert_text 'alert\.sh \w\+ \(\w\+\)?'
    syntax match yabai_text 'yabai_utils\.sh \w\+ \(\w\+\)?'
    hi link alert_text XcodePink
    hi link yabai_text XcodeTeal
endfunction

let g:python3_host_prog = $NVIM_PYTHON
let g:loaded_node_provider = 0
let g:loaded_perl_provider = 0
let g:loaded_ruby_provider = 0 " this probaby doesn't do anything

set list
set listchars=tab:>-
match Error /\t/

" Clear search
map <silent> <C-x> :nohl<CR>
map <silent> <leader>r :nohl<CR>


"
function! RegisterAntlrCommands()
    " Add command mappings for Antlr

    " Jump to definition of current symbol under cursor;
    " search for word but for line starting with it
    nnoremap <Leader>ad /^\<<C-r><C-w>\>/<CR>
endfunction

map <leader>afc :%py3f /usr/local/share/clang/clang-format.py<CR>

