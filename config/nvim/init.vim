source $ADMIN_SCRIPTS/master.vimrc

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
autocmd BufRead,BufNewFile TARGETS setfiletype conf
autocmd BufRead,BufNewFile *.histedit.hg.txt setfiletype conf
" remove whitespace at end of lines
autocmd BufWritePre * :%s/\s\+$//e
" Python-specific find def/class
autocmd FileType python map <buffer> map <localleader>fc :BLines<CR>^class<space>
autocmd FileType python map <buffer> <localleader>fd :BLines<CR>^def<space>
autocmd FileType antlr4 call RegisterAntlrCommands()

" Use K to show documentation in preview window
nnoremap <silent> K :call <SID>show_documentation()<CR>

let g:python3_host_prog=expand($NVIM_PYTHON)
let g:loaded_node_provider = 0
let g:loaded_perl_provider = 0
let g:loaded_ruby_provider = 0 " this probaby doesn't do anything

" Clear search
map <silent> <C-x> :nohl<CR>
map <silent> <leader>r :nohl<CR>

map <silent> <leader>fc /<<<<<<<\\|=======\\|>>>>>>><CR>


"
" EasyMotion Settings
"
let g:EasyMotion_do_mapping = 0 " Disable default mappings
let g:EasyMotion_smartcase = 1 " Regular vim casing

    " occurence of character
map <Leader>gf <Plug>(easymotion-bd-f)
map <Leader><Leader> <Plug>(easymotion-bd-f)
    " occurence of two characters
map <Leader>gs <Plug>(easymotion-s2)
    " occurence of Line
map <Leader>gl <Plug>(easymotion-bd-jk)
    " occurence of Word
map <leader>gg <Plug>(easymotion-bd-w)
    " occurence on THIS line ('h' for 'here')
map <Leader>gh <Plug>(easymotion-sl)
map <Leader>gr <Plug>(easymotion-repeat)
map <Leader>gn <Plug>(easymotion-next)
map <Leader>gp <Plug>(easymotion-prev)

map  <Leader>/ <Plug>(easymotion-sn)
omap <Leader>/ <Plug>(easymotion-tn)

"
"Python Highlighting with Semshi
"
let g:semshi#error_sign = v:false
let g:semshi#simplify_markup = v:false

function! SemshiOverrides()
    " tangerine-color
    hi semshiLocal           ctermfg=209 guifg=#ff875f cterm=none
    " teal
    hi semshiGlobal          ctermfg=030 guifg=#ffaf00 cterm=none
    hi semshiImported        ctermfg=030 guifg=#ffaf00 cterm=none
    " black
    hi semshiParameter       ctermfg=016 guifg=#5fafff cterm=none
    hi semshiParameterUnused ctermfg=016 guifg=#87d7ff cterm=underline gui=underline
    " brown?
    hi semshiFree            ctermfg=094 guifg=#ffafd7 cterm=none
    " purple
    hi semshiBuiltin         ctermfg=091 guifg=#ff5fff cterm=none
    " self.attribute
    hi semshiAttribute       ctermfg=030  guifg=#00ffaf cterm=none
    " pink
    hi semshiSelf            ctermfg=163 guifg=#b2b2b2 cterm=bold
    " red; errors
    hi semshiUnresolved      ctermfg=196 guifg=#ffff00 cterm=underline gui=underline
    " highlight selected things
    hi semshiSelected        ctermfg=16 guifg=#ffffff ctermbg=255 guibg=#d7005f

    hi semshiErrorSign       ctermfg=015 guifg=#ffffff ctermbg=196 guibg=#d70000
    hi semshiErrorChar       ctermfg=015 guifg=#ffffff ctermbg=196 guibg=#d70000
    syntax keyword semshiSelf True False None

endfunction
autocmd FileType python call SemshiOverrides()
call SemshiOverrides()

function! RegisterAntlrCommands()
    " Add command mappings for Antlr

    " Jump to definition of current symbol under cursor;
    " search for word but for line starting with it
    nnoremap <Leader>ad /^\<<C-r><C-w>\>/<CR>
endfunction


"" Semshi bindings
map <leader>sr  :Semshi rename <CR>
map <leader>sgc :Semshi goto class next <CR>
map <leader>sgC :Semshi goto class prev <CR>
map <leader>sgf :Semshi goto function next <CR>
map <leader>sgF :Semshi goto function prev <CR>

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


" Facebook stuff
source ~/.config/nvim/private/facebook.vim
