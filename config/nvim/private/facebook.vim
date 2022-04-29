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
