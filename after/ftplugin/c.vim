" Gets close to the MathWorks indentation standard as of Nov 2017
setlocal cinoptions=:0,N-s,g2,h2,(0,=4,l1,W4

" We first remove the double slash and add it after the triple slash,
" otherwise things seem to not work.
setlocal comments-=://
setlocal comments+=:///
setlocal comments+=://

setlocal completeopt=menu,preview,longest
setlocal pumheight=10

let &l:makeprg='g++ -g -O0 -std=c++2a %'
