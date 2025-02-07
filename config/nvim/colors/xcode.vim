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
hi Normal       ctermfg=234 ctermbg=15 guifg=234 guibg=231 " black
hi NonText      ctermfg=11 ctermbg=15 " orange on white
hi LineNr       ctermfg=239 ctermbg=NONE " grey
hi StatusLine   ctermfg=249 ctermbg=238
hi StatusLineNC ctermfg=241 ctermbg=249
hi VertSplit    ctermfg=255 ctermbg=255 " Vertical Split Line
hi Folded       ctermbg=252 ctermfg=233
hi FoldColumn   cterm=NONE ctermbg=NONE
hi link Title Normal
hi Visual       ctermbg=153
hi Error        ctermfg=15 ctermbg=124
hi link SpecialKey Error

hi XcodeGreen ctermfg=22
hi XcodeTeal  ctermfg=30
hi XcodeBoldPink cterm=bold ctermfg=163
hi XcodePink  ctermfg=163
hi XcodeRed   ctermfg=160
hi XcodeBrown ctermfg=094
hi XcodeBoldBlue cterm=bold ctermfg=020
hi XcodeBlue  ctermfg=020
hi XcodePurple ctermfg=054
hi XcodeGrey  ctermfg=251

hi! link DiagnosticHint XcodeGrey

hi! link @keyword XcodePink
hi! link @variable.builtin XcodePink
hi! link @variable XcodeTeal
hi! link @namespace XcodePurple
hi! link @punctuation Normal
hi! link @operator Normal
hi! link @attribute.builtin XcodeBrown
hi! link @attribute XcodeBrown

" Syntax highlighting
hi! link Comment XcodeGreen
hi! Todo         ctermfg=9 " red-ish salmon?
hi! default link Constant XcodePurple
hi! default link String XcodeRed
hi! default link Identifier XcodeTeal
hi! default link Function Normal
hi! default link Type XcodePurple
hi! default link Statement XcodePink
hi! Keyword      ctermfg=091
hi! default link PreProc XcodeBrown
hi! Number       ctermfg=020 " blue
hi! Special      ctermfg=091 " <C-l> etc, purple
hi! Search       cterm=underline ctermbg=153 ctermfg=236 " ? doesn't work
hi! Delimiter    cterm=bold ctermfg=126
hi! default link Parens Normal

" Diff colours
hi link DiffAdded Comment
hi link diffRemoved String
hi link DiffChange pythonCustomFunc
hi link diffLine pythonStatement
hi link diffFile Identifier

hi link NvimInternalError Error

" Javascript
hi javaScriptReserved ctermfg=126
hi javaScriptNumber ctermfg=020
hi javaScriptFuncArg ctermfg=055
hi javascriptBlock ctermfg=030
hi javascriptIdentifier ctermfg=126
hi javascriptBOMHistoryProp ctermfg=016
hi javascriptObjectLabel ctermfg=016


" HTML
hi htmlArg ctermfg=030
hi htmlString ctermfg=020
hi htmlComment ctermfg=28
hi link htmlCommentPart htmlComment
hi htmlTag ctermfg=244
hi link htmlTagN htmlTag
hi link htmlEndTag htmlTag

" NerdTree
hi NerdTreeDirSlash cterm=NONE ctermfg=231 ctermbg=231
hi NerdTreeCWD cterm=NONE ctermfg=241 ctermbg=NONE

