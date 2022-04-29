" Name: xcode
" Purpose: xcode default colorscheme to cterm
" Maintainer: Christian Ohlin Jansson (john.christian.ohlin@gmail.com)
"
" @version: 1.0.0

set background=light

hi clear

if exists("syntax_on")
  syntax reset
endif

let colors_name = "xcode"


" Vim >= 7.0 specific colours
if version >= 700
  hi CursorLine   cterm=NONE ctermfg=NONE ctermbg=NONE
  hi CursorColumn ctermbg=236
  hi MatchParen   cterm=NONE  ctermfg=016 ctermbg=226
  hi Pmenu        ctermfg=016 ctermbg=255
  hi PmenuSel     ctermfg=020 ctermbg=253
endif

" General colours
hi Cursor       ctermfg=020 ctermbg=016 " blue
hi Normal       ctermfg=016 ctermbg=231 " black
hi NonText      ctermfg=231 ctermbg=231 " white
hi LineNr       ctermfg=239 ctermbg=NONE " grey
hi StatusLine   ctermfg=249 ctermbg=238
hi StatusLineNC ctermfg=241 ctermbg=249
hi VertSplit    ctermfg=255 ctermbg=255 " Vertical Split Line
hi Folded       ctermbg=252 ctermfg=233
hi FoldColumn   cterm=NONE ctermbg=NONE
hi Title        ctermfg=016
hi Visual       ctermbg=153
hi SpecialKey   ctermfg=126 ctermbg=153
hi Error        ctermfg=231 ctermbg=124

"" Syntax highlighting
" single line comment; green
hi Comment      ctermfg=28
"" purplish blue
hi Constant cterm=bold ctermfg=5
"" red
hi String       ctermfg=160
hi link Character String

hi link Boolean Statement

"" blue
hi Number       ctermfg=020
hi link Float Number

"hi Identifier ctermfg=30
hi link Function Normal

" Statement and subgroup is keywords
hi Statement        cterm=bold ctermfg=163
" if, then else, endif, switch, etc
hi link Conditional Statement
" for, do, while, etc.
hi link Repeat      Statement
" case, default, etc.
hi link Label       Statement
" sizeof, +, *, etc.
hi link Operator    Normal
" any other keyword
hi link Keyword     Statement
" try, catch, throw
hi link Exception   Statement

hi link Self        Statement

hi Type         ctermfg=091 " purple

hi link BuiltinFunction Type
hi link BuiltinType Type

hi Identifier   ctermfg=30 " syntax file needs to be better to identify

hi PreProc      ctermfg=094 " tealy color
hi Special      ctermfg=091 " <C-l> etc, purple
hi Search       cterm=underline ctermbg=153 ctermfg=236 " ? doesn't work
hi link Delimiter   Normal
hi link Parens      Normal

"" Diff colours
""hi link DiffAdded Comment
""hi link diffRemoved String
""hi link DiffChange pythonCustomFunc
""hi link diffLine pythonStatement
""hi link diffFile Identifier


