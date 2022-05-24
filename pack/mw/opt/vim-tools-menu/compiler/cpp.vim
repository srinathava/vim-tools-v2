set efm=
" A bunch of warnings which are benign.
let &efm .= '%-G%.%#UNIX_CXX_TEMP_DIR%.%#'
let &efm .= ',%-G%.%#undefined\ variable\ `DEBUG_FLAG%.%#'
let &efm .= ',%-G%.%#undefined\ variable\ `OBJ_DIR%.%#'
let &efm .= ',%-G%.%#undefined\ variable\ `VERBOSE%.%#'
let &efm .= ',%-G%.%#undefined\ variable\ `LIB_UT_LIB_DEPEND%.%#'
let &efm .= ',%-G%.%#undefined\ variable\ `BOLD_%.%#'
let &efm .= ',%-G%.%#javarules\.gnu\ is\ deprecated%.%#'
let &efm .= ',%-G%.%#msrc-action%.%#'
let &efm .= ',%-G%.%#Done\ prebuild%.%#'
let &efm .= ',%-G%.%#Done\ build%.%#'
let &efm .= ',%-G%.%#Running\ prebuild%.%#'
let &efm .= ',%-G%.%#Running\ build%.%#'
let &efm .= ',%-G%.%#is\ obsolete%.%#'
let &efm .= ',%-G%.%#include\ path\ is\ out-of-model%.%#'
let &efm .= ',%-G%.%#compflags\.gnu%.%#'
let &efm .= ',%-G%.%#build\ entering\ %.%#'
let &efm .= ',%-G%.%#build\ exiting\ %.%#'
let &efm .= ',%-GSwimlane\ %.%#'
let &efm .= ',%-GSBT%.%#'
let &efm .= ',%-GCompiling\ %.%#'
let &efm .= ',%-GThe\ makefile\ %.%#'
let &efm .= ',%-GPlease\ specify\ %.%#'
let &efm .= ',%-GUsing\ default\ %.%#'
let &efm .= ',%-GModule\ entry\ %.%#'
let &efm .= ',%-GBuild\ type\ %.%#'
let &efm .= ',%-GWarning\ level\ %.%#'
let &efm .= ',%-Gdistcc[%.%#'
let &efm .= ',%-W%.%#compflags\.gnu%.%#'
let &efm .= ',%+GIn file included from %f:%l:%c%.%#'
let &efm .= ',%+Ggmake: *** [%f:%l:%m'
let &efm .= ',%.%#from\ %f:%l%.%#,'
let &efm .= ',%f:\ In\ function\ %.%#=%m'
let &efm .= ',%*[^"]"%f"%*\D%l: %m'
let &efm .= ',"%f"%*\D%l: %m'
let &efm .= ',%-G%f:%l: (Each undeclared identifier is reported only once'
let &efm .= ',%-G%f:%l: for each function it appears in.)'
let &efm .= ',%+G%.%# Saving results in %f'
let &efm .= ',%f:%l:%c:%m'
let &efm .= ',%f:%l'
let &efm .= ',%f(%l):%m,%f:%l:%m,"%f"\, line %l%*\D%c%*[^ ] %m'
" comes from sbmake 
let &efm .= ",%Dgmake: Entering directory '%f'"
let &efm .= ",%Xgmake: Leaving directory '%f'"
" Comes from sbcc
let &efm .= ",%Dgmake: Entering directory `%f'"
let &efm .= ",%Xgmake: Leaving directory `%f'"
let &efm .= ',%-DMaking %*\a in %f'
let &efm .= ',%f|%l| %m '
