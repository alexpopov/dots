" some tab shit
set tabstop=4				" 2 space tabs
set softtabstop=4 	" number of spaces in a tab when editing
set shiftwidth=4    " how much to shift by
set expandtab				" tabs vs spaces, mwahahaha

set scrolloff=12 " Keep 12 lines below and above the cursor

set mouse= " turn off mouse inputs

let mapleader="," " change leader to ,
let maplocalleader = '\'

colorscheme xcode
set autoread

"set termguicolors
" ???
"let &t_8f = "\[38;2;%lu;%lu;%lum"
"let &t_8b = "\[48;2;%lu;%lu;%lum"
" </???>

" remove whitespace at end of lines
autocmd BufWritePre * :%s/\s\+$//e

" remap window movement
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>

" map insert-mode movements
imap <C-f> <C-o>l
imap <C-b> <C-o>h

" numbers and make them relative
"set number
"set relativenumber

" split more reasonable
set splitbelow
set splitright

" misc settings
set noswapfile " recovery files are just a pain
set nobackup
set nowb
set ignorecase " case insensitive
set smartcase " all caps will be searched as all caps
set incsearch " incremental search
set hidden

set cmdheight=1
set updatetime=300 " diagnostic message time
set shortmess+=c
set signcolumn=no

" in theory, better diffing
set diffopt+=internal,algorithm:patience

call plug#begin()
Plug 'guns/xterm-color-table.vim'
Plug 'roxma/nvim-yarp'  " some thing for remote plugins
Plug 'vim-airline/vim-airline' " vim bottom-bar  + themes
Plug 'vim-airline/vim-airline-themes'
Plug 'scrooloose/nerdcommenter' " comment code out
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim' " extra vim bindings for fzf
Plug 'machakann/vim-Verdin' " autocomplete for vimscript
Plug 'Vimjas/vim-python-pep8-indent' " sane indentation for python
Plug 'easymotion/vim-easymotion'  " move quickly; bindings at bottom
Plug 'haya14busa/incsearch.vim'  " better incremental search
Plug 'tpope/vim-surround'        " surround stuff in shit
Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'voldikss/vim-floaterm'
Plug 'SirVer/ultisnips'
Plug 'honza/vim-snippets'
Plug 'neovim/nvim-lspconfig'
Plug 'numirias/semshi'  " awesome python highlighter
Plug 'rktjmp/lush.nvim' " themeing thing
Plug 'pwntester/nautilus.nvim'
Plug 'dylon/vim-antlr'
Plug 'solarnz/thrift.vim'
"Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'qpkorr/vim-bufkill'
Plug 'wesQ3/vim-windowswap'
call plug#end()

let g:UltiSnipsExpandTrigger="<c-y>"
let g:UltiSnipsJumpForwardTrigger="<c-b>"
let g:UltiSnipsJumpBackwardTrigger="<c-z>"
let g:UltiSnipsSnippetsDir=[$HOME.'/.config/nvim/UltiSnips']


" Nerd Commenter
let g:NERDDefaultAlign = 'left'

" Deoplete Completion
let g:deoplete#enable_at_startup = 1
call deoplete#custom#option('auto_complete_delay', 100)
function! s:check_back_space() abort "{{{
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~ '\s'
endfunction"}}}
call deoplete#custom#source('_', 'sorters', ['sorter_word'])
call deoplete#custom#source('ultisnips', 'rank', 7500)

lua << EOF
config = require('config')
EOF


" adds comment highlighting to JSON
autocmd FileType json syntax match Comment +\/\/.\+$+
" adds highlighting for Buck
autocmd BufRead,BufNewFile TARGETS setfiletype conf
autocmd BufRead,BufNewFile *.histedit.hg.txt setfiletype conf

" Use K to show documentation in preview window
nnoremap <silent> K :call <SID>show_documentation()<CR>

let g:python3_host_prog=expand('~/venv/bin/python')


"
" 'fff' setup
"
"                           30 high horizontal split
let g:fff#split = "30new"
"                           Open fff
nmap <Leader>fo :F<CR>

" Airline theme
let g:airline_theme='silver' "kind of mac-y
let g:airline_section_x = ''

" all leader rebindings will be here
" new tab new with <leader> t
map <localleader>t :tabnew<CR>

" Jump to matching delimiter; 'm' for 'match'
map <leader>m %

" Clear search
map <silent> <C-x> :nohl<CR>
map <silent> <leader>r :nohl<CR>

map <silent> <leader>fc /<<<<<<<\\|=======\\|>>>>>>><CR>

"
map <localleader>r :source ~/.config/nvim/init.vim<CR>
" reload color
map <localleader>rc :syntax sync fromstart<CR>
map <localleader>e :edit ~/.config/nvim/init.vim<CR>
map <localleader>b :edit ~/.bash_profile<CR>

"
" Fuzzy File Finder
"
map <leader>fa :Ag<CR>
map <leader>fb :Buffers<CR>
map <leader>fh :BLines<CR>
map <leader>fl :Lines<CR>
map <leader>ff :Files<CR>

map <localleader>fd :BLines<CR>^def<space>
map <localleader>fc :BLines<CR>^class<space>

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

autocmd FileType antlr4 call RegisterAntlrCommands()

"" Semshi bindings
map <leader>sr  :Semshi rename <CR>
map <leader>sgc :Semshi goto class next <CR>
map <leader>sgC :Semshi goto class prev <CR>
map <leader>sgf :Semshi goto function next <CR>
map <leader>sgF :Semshi goto function prev <CR>

let g:python_highlight_all = 1

" Delete Buffers
function! DeleteHiddenBuffers()
    let tpbl=[]
    call map(range(1, tabpagenr('$')), 'extend(tpbl, tabpagebuflist(v:val))')
    for buf in filter(range(1, bufnr('$')), 'bufexists(v:val) && index(tpbl, v:val)==-1')
        silent execute 'bwipeout' buf
    endfor
endfunction
map <localleader>bd :call DeleteHiddenBuffers()

function! ViewDiff()
    enew
    1,$ !hg diff
    setf diff
endfunction

map <localleader>hd :call ViewDiff()<CR>

"
" Float Term Setup
"
let g:floaterm_keymap_new    = '<F7>'
let g:floaterm_keymap_prev   = '<F8>'
let g:floaterm_keymap_next   = '<F9>'
let g:floaterm_keymap_toggle = '<F5>'
let g:floaterm_rootmarkers   = ['TARGETS']
let g:floaterm_position      = 'center'
let g:floaterm_width = 0.6

map <localleader>sn     :FloatermNew<Space>
map <localleader>sr     :FloatermNew buck run //upm<CR>


"
" Facebook Stuff
"
"
function! FbDiffusionLink()
    let url_prefix = "https://our.internmc.facebook.com/intern/diffusion/FBS/browse/master/"
    let current_file = expand('%:p')
    let fbcode_path = split(current_file, "fbsource/")
    let file_path = fbcode_path[1]
    let url = join([url_prefix, file_path, "?lines=", line(".")], "")
    execute "!" . "fburl" . " " . url
endfunction

command! FbDiffusionLink call FbDiffusionLink()

map <localleader>id :FbDiffusionLink<CR>

function! FbQueryOwner()
    let current_file = expand('%:p')
    let fbcode_path = split(current_file, "fbcode/upm/")
    let file_path = fbcode_path[1]
    execute "!" . "buck query " . "\"owner(" . file_path . ")\""
endfunction

command! FbQueryOwner call FbQueryOwner()

map <localleader>io :FbQueryOwner<CR>

command! PrintLspClients lua print(vim.inspect(vim.lsp.buf_get_clients()))
command! RestartLspClients lua require'config'.launch_pyls()
