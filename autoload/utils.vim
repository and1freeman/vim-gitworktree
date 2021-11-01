function! utils#EchoWarning(msg) abort
  echohl WarningMsg
  echo 'vim-gitworktree: ' . a:msg
  echohl None
endfunction


function! utils#FlattenList(list) abort
  let val = []

  for elem in a:list
    if type(elem) == type([])
      call extend(val, utils#FlattenList(elem))
    else
      call extend(val, [elem])
    endif
    unlet elem
  endfor

  return val
endfunction


function! utils#Find(predicate, list, ...) abort
  let item = len(a:000) ? a:000[0] : 0

  for el in a:list
    if call(a:predicate, [el])
      let item = el
      break
    endif
  endfor

  return item
endfunction
