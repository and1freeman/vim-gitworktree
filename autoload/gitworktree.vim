function! s:EchoWarning(msg) abort
  echohl WarningMsg
  echo 'vim-gitworktree: ' . a:msg
  echohl None
endfunction


function! s:LoadWorktree(path) abort
  " silent call s:UpdateWorktreesList()

  " if empty(a:path)
  "   return
  " endif

  " let cwd = getcwd()

  " let buffers_in_current_worktree = filter(getbufinfo({ 'buflisted' : 1 }), {_, buf -> s:isFileInsidePath(get(buf, 'name', ''), cwd)})
  " let modified_buffers = filter(deepcopy(buffers_in_current_worktree), {_, buf -> get(buf, 'changed', 0) == 1 })
  " let modified_buffers_names = map(deepcopy(modified_buffers), {_, buf -> fnamemodify(get(buf, 'name', ''), ':.')})

  " if len(modified_buffers)
  "   call s:EchoWarning("Can not change worktree. Following files are not saved:")
  "   echo join(modified_buffers_names, '\n')

  "   return
  " endif

  " let current_worktree = utils#Find({wtree -> get(wtree, 'is_current', 0)}, s:worktrees, {})
  " let new_worktree = utils#Find({wtree -> get(wtree, 'path', '') ==# a:path}, s:worktrees, {})

  " if empty(new_worktree)
  "   call s:EchoWarning('Can not find selected worktree. Try to update worktrees list.')
  "   return
  " endif

  " if get(current_worktree, 'path', 'NO_CURRENT') ==# get(new_worktree, 'path', 'NO_NEW')
  "   call s:EchoWarning('Already in ' . current_worktree.path . '. ' .  '[' . current_worktree.branch . ']')
  "   return
  " endif

  " for buffer in buffers_in_current_worktree
  "   exec ':bd ' . get(buffer, 'bufnr', -1)
  " endfor

  " let new_worktree_path = get(new_worktree, 'path')
  " exec ':cd ' . new_worktree_path . ' | e ' . new_worktree_path
endfunction


function! s:SplitAndFilter(string) abort
  return filter(split(a:string, ' '), {_, s -> !empty(s)})
endfunction

function! s:GetWorktrees() abort
  let worktrees = []

  for worktree in systemlist('git worktree list')
    let [path, _, branch] = s:SplitAndFilter(worktree)
    let branch = trim(branch, '[]')

    call extend(worktrees, [{ 'branch': branch, 'path': path }])
  endfor

  return worktrees
endfunction


function! s:AddSubCmd(...) abort
  let cmd = 'git worktree add ' . join(a:000)
  echo system(cmd)
endfunction


function! s:RemoveSubCmd(...) abort
  let cmd = 'git worktree remove ' . join(a:000)
  echo system(cmd)
endfunction


function! gitworktree#Call(arg) abort
  call system('git status')

  if v:shell_error > 0
    call s:EchoWarning('Not a git repo ' . getcwd())
    return
  endif

  if empty(a:arg)
    call s:ListWorktrees()
    return
  endif

  let args = s:SplitAndFilter(a:arg)
  let cmd = args[0]
  let params = args[1:-1]
  let cmd = 's:' . substitute(cmd, '\v^(\w)(.*)', '\u\1\e\2', '')

  if !exists('*' . cmd . 'SubCmd')
    call s:EchoWarning('Wrong command: ' . '"' . cmd[2:-1] . '".')
    return
  endif

  call call(function(cmd . 'SubCmd'), params)
endfunction


" TODO: flags and other options/commands
function! gitworktree#complete(lead, line, pos) abort
  let args = s:SplitAndFilter(a:line)

  " add
  if len(args) == 2 && 'add' =~# tolower(args[1]) && !empty(a:lead)
    return ['add']
  endif

  if len(args) >= 2 && tolower(args[1]) ==# 'add'
    return []
  endif

  " remove
  if len(args) == 2 && 'remove' =~# tolower(args[1]) && !empty(a:lead)
    return ['remove']
  endif

  if len(args) >= 2 && tolower(args[1]) ==# 'remove'
    let branches = map(s:GetWorktrees(), {_, wt -> get(wt, 'branch', '')})
    return filter(branches, {_, b -> b =~# '^' . a:lead && !empty(b) })
  endif


  if empty(a:lead)
    return ['add', 'remove']
  endif

  return []
endfunction


augroup detect_gitworktree_filetype
  autocmd!
  autocmd Filetype gitworktree
        \ nnoremap <silent><buffer> <cr> :call <sid>OnEnter()<cr>

  autocmd Filetype gitworktree
        \ autocmd BufUnload <buffer> call <sid>SetWindowClosed()
augroup END
