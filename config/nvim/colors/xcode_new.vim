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
hi Normal       ctermfg=235 ctermbg=231 " black
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

hi XcodeGreen ctermfg=028
hi XcodeGrey  ctermfg=242
hi XcodeTeal  ctermfg=242
hi XcodeBoldPink cterm=bold ctermfg=126
hi XcodePink  ctermfg=163
hi XcodeRed   ctermfg=160
hi XcodeBrown ctermfg=094
hi XcodeBoldBlue cterm=bold ctermfg=20
hi XcodeBlue  ctermfg=020
hi XcodePurple ctermfg=054

hi! link @keyword XcodeBoldPink
hi! link @variable.builtin XcodeBoldPink
hi! link @punctuation Normal
hi! link @operator Normal
hi! link @attribute.builtin XcodeBrown
" Syntax highlighting
hi! link Comment XcodeGreen
hi! Todo         ctermfg=9 " red-ish salmon?
hi! default link Constant XcodePurple
hi! default link String XcodeRed
hi! default link Identifier XcodeTeal
hi! Function     ctermfg=016 " black
hi! default link Type XcodePurple
hi! Statement    cterm=bold ctermfg=163 " seems to highlight built-ins like 'hi' in vim
hi! Keyword      ctermfg=091
hi! default link PreProc XcodeBrown
hi! Number       ctermfg=020 " blue
hi! Special      ctermfg=091 " <C-l> etc, purple
hi! Search       cterm=underline ctermbg=153 ctermfg=236 " ? doesn't work
hi! Delimiter    cterm=bold ctermfg=126
hi! Parens       ctermfg=016

" Diff colours
hi link DiffAdded Comment
hi link diffRemoved String
hi link DiffChange pythonCustomFunc
hi link diffLine pythonStatement
hi link diffFile Identifier


" Python
hi pythonBuiltin            ctermfg=091 " int, str, etc -- purple
hi pythonBuiltinFunc        ctermfg=091 " various built-in functions
hi pythonBuiltinObj         ctermfg=094 " some dunders
hi pythonBuiltinType        ctermfg=091 " various built-in types
hi pythonCustomFunc         ctermfg=030 " ?
"hi pythonDottedName         ctermfg=226 " ? doesn't worK
hi pythonFunction           ctermfg=226 " ?
hi pythonDecorator          ctermfg=094 " @udf for example
hi pythonInclude            ctermfg=094  " Python imports, etc
hi pythonImport             ctermfg=094  " Pythin imports
hi pythonInstances          ctermfg=226 " ?
hi pythonFunction           ctermfg=16 " ?
hi pythonStatement          cterm=bold ctermfg=163 " class, return, def, pass, etc
hi pythonConditional        cterm=bold ctermfg=163 " if else etc
hi pythonRepeat	            cterm=bold ctermfg=163 " while, for
hi pythonOperator           cterm=bold ctermfg=163 " and, or
hi pythonException          cterm=bold ctermfg=163 " raise
hi pythonExClass            ctermfg=091 " raise
hi pythonSingleton          ctermfg=091
hi pythonBuiltinConstant    ctermfg=226
hi pythonBoolean            cterm=bold ctermfg=163 " True, False
hi pythonAttribute          ctermfg=226
hi pythonString             ctermfg=160
hi pythonQuotes             ctermfg=160
hi docstring                ctermfg=28
hi pythonClassVar           cterm=bold ctermfg=163 " self, cls
hi pythonNone               cterm=bold ctermfg=163 " None
hi pythonRun                ctermfg=28
hi pythonTodo               ctermfg=160
hi pythonClass              ctermfg=30
hi pythonFuncArgs           ctermfg=30


"autocmd Filetype python call SetColors()
"function SetColors()
    ""syn keyword pythonBuiltin class def pass return with as nonlocal
    "syn keyword pythonBoolean   True False None
    "syn keyword pythonOperator  self cls
    "syn keyword pythonDecorator dataclass udf staticmethod
    "syn keyword pythonBuiltin List Any Dict Iterator Mapping Optional Sequence
    "syn keyword pythonBuiltin Tuple Type TypeVar Union cast
    ""syn match pythonStatement /,/
    "syn match pythonInclude /__[a-z]\+/ " doesn't work :(

    ""syn match docstring /"""\_.\{-}"""/
"endfunction

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

