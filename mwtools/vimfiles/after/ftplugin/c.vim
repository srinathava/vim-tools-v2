setlocal cinoptions=:0,g2,h2,(0,:2,=2,l1,W4

" We first remove the double slash and add it after the triple slash,
" otherwise things seem to not work.
setlocal comments-=://
setlocal comments+=:///
setlocal comments+=://

setlocal completeopt=menu,preview,longest
setlocal pumheight=10
