
define mframe
  printf "%s", SF::dbstackFrame(1)
end

define hstack
  set print elements 0
  printf "%s", SF::GetHybridStack($arg0,$arg1,$arg2,$arg3)
end



