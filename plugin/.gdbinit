
define mframe
  printf "%s", SF::dbstackFrame(1)
end

define hstack
  set print elements 0
  printf "%s", SF::GetHybridStack($arg0,$arg1,$arg2,$arg3)
end
define pmxval
   if $argc == 2
       printf "%s", SF::GetMLValueStr($arg0,$arg1)
   else
       printf "%s", SF::GetMLValueStr($arg0,"")
   end
end
set height 0
set breakpoint pending on
breaksegv

define load_sf_libs
    sb-auto-load-libs libmw\(stateflow\|sf_\)
    sb-auto-load-libs libmw\(cg_ir\|cgir_support\|cgir_xform\)
    sb-auto-load-libs libmw\(mcr\|fl\|sl_services\)
    sb-auto-load-libs sf_sfun
    sb-auto-load-libs sf_req
    #sb-auto-load-libs sf_builtin
    #sb-auto-load-libs sf.mexa64
end

define quick_attach_sf
    set auto-solib-add off
    attach $arg0
    load_sf_libs
end



