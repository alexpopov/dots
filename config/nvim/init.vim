" private fb stuff
if filereadable(expand("$ADMIN_SCRIPTS/master.vimrc"))
  source $ADMIN_SCRIPTS/master.vimrc
endif

" I don't know why, but iTerm2 on Mac just makes my xcode theme do nothing
" as of nvim 0.10.0 when it auto-detects that termguicolors is true
" this goes back to pre-0.10 behavior where cterm values are used by default
set notermguicolors
colorscheme xcode

" TODO: set this in lua
set noswapfile " recovery files are just a pain
set nobackup
set nowb

lua << EOF
config = require('lua_init')
EOF

" below: adds comment highlighting to JSON
" autocmd FileType json syntax match Comment +\/\/.\+$+
" adds highlighting for Buck
autocmd BufRead,BufNewFile *.histedit.hg.txt set filetype=conf
autocmd BufRead,BufNewFile *.gitconfig set filetype=gitconfig
autocmd BufRead,BufNewFile skhdrc call SetSkhdrcSettings()
autocmd BufRead,BufNewFile *.json set filetype=jsonc

" C++ specific
autocmd FileType cpp call SetIndentTwo()
autocmd FileType cpp setlocal commentstring=//\ %s

autocmd FileType json call SetIndentFour()
autocmd FileType java call SetIndentTwo()
autocmd FileType bash call SetIndentTwo()
autocmd FileType sh call SetIndentTwo()

function! SetIndentTwo()
    set tabstop=2
    set shiftwidth=2
endfunction
function! SetIndentFour()
    set tabstop=4
    set shiftwidth=4
endfunction

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

" TODO: move to lua?
" Delete Buffers
function! DeleteHiddenBuffers()
    let tpbl=[]
    call map(range(1, tabpagenr('$')), 'extend(tpbl, tabpagebuflist(v:val))')
    for buf in filter(range(1, bufnr('$')), 'bufexists(v:val) && index(tpbl, v:val)==-1')
        silent execute 'bwipeout' buf
    endfor
endfunction

" TODO: remove
function! ViewDiff()
    enew
    1,$ !hg diff
    setf diff
endfunction

map <localleader>hd :call ViewDiff()<CR>

map <leader>afc :%py3f /usr/local/share/clang/clang-format.py<CR>

