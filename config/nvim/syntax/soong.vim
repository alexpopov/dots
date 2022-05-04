
if exists('b:current_syntax')
  finish
endif

syntax keyword soongKeyword
  \ true
  \ false

" Comment match more aggressively?
syntax region soongComment start="//" end="$" oneline keepend

" some_stuff = [ ... ]
syntax region soongTopGroup start='^\w' end='\[' oneline contains=soongTopGroupIdentifier
syntax match soongTopGroupIdentifier "\w\+" contained
" some_stuff { ... }
syntax region soongTopRule start='^\w' end='{' oneline contains=soongTopRuleIdentifier
syntax match soongTopRuleIdentifier '\w\+' contained containedin=soongTopRule

syntax region soongKey start='\w\+:' end=/\v[,\[$]/ oneline contains=soongStringRegion,soongKeyword,soongKeyIdentifier,soongValue,soongComment

" It will more greedily match later rules
syntax match soongValue '\w\+' contained
syntax match soongKeyIdentifier '\w\+:' contained containedin=soongKey

" String regions
syntax region soongStringRegion start=/\v"/ skip=/\v\\./ end=/\v"/ keepend contains=soongFileString,soongCFlag
syntax match soongFileString '\v".*[\.\/].*"' containedin=soongStringRegion
syntax match soongCFlag '"-.*"' containedin=soongStringRegion



" Context-less
highlight link soongComment Comment
highlight link soongKeyword Statement


highlight link soongKeyIdentifier Identifier
highlight link soongTopGroupIdentifier Constant
highlight link soongValue soongTopGroupIdentifier

highlight link soongTopRuleIdentifier XcodeBoldPink

" Strings
highlight link soongStringRegion soongTopGroupIdentifier
highlight link soongFileString XcodeRed
highlight link soongCFlag PreProc

