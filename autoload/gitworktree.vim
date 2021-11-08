" TODO: add tmux support

let g:gitworktree_config = {
      \ 'use_tmux': 1,
      \ }

function! s:EchoWarning(msg) abort
  echohl WarningMsg
  echo 'vim-gitworktree: ' . a:msg
  echohl None
endfunction

function! s:Find(predicate, list) abort
  let item = {}
  let found = 0

  for el in a:list
    if call(a:predicate, [el])
      let item = el
      let found = 1
      break
    endif
  endfor

  return [item, found]
endfunction

function! s:IsFileInsidePath(filename, path) abort
  if !len(a:filename)
    return 0
  endif

  let modified = fnamemodify(a:filename, ':p')
  return filereadable(modified) && len(matchstr(modified, a:path)) > 0
endfunction


function! s:SplitAndFilter(string) abort
  return filter(split(a:string, ' '), {_, s -> !empty(s)})
endfunction


function! s:IsBareRepo() abort
  return trim(system('git rev-parse --is-bare-repository'), " \n") ==# 'true'
endfunction

function! s:GetWorktrees() abort
  let worktrees = []

  for worktree in systemlist('git worktree list')
    let list = s:SplitAndFilter(worktree)

    if trim(list[1],'()') ==# 'bare'
      continue
    endif

    let path = list[0]
    let branch = trim(list[2], '[]')

    call extend(worktrees, [{ 'branch': branch, 'path': path }])
  endfor

  return worktrees
endfunction


function! s:GetCurrentBranch() abort
  if s:IsBareRepo()
    return ''
  else
    return trim(system('git branch --show-current'), " \n")
  endif
endfunction


function! s:LoadSubCmd(...) abort
  if a:0 == 0
    call s:EchoWarning('No worktree provided.')
    return
  endif

  let branch = a:1

  let cwd = getcwd()
  let worktrees = s:GetWorktrees()
  let [current_worktree, found] = s:Find({wt -> get(wt, 'path', '') ==# cwd}, worktrees)

  if found && branch ==# current_worktree.branch
    call s:EchoWarning('Already in ' . current_worktree.path . ' [' . branch . ']')
    return
  endif

  let [new_worktree, found] = s:Find({wt -> get(wt, 'branch', '') ==# branch}, worktrees)

  if !found
    call s:EchoWarning('Worktree not found: ' . a:1)
    return
  endif

  let new_worktree_path = get(new_worktree, 'path')

  if g:gitworktree_config.use_tmux
    " TODO: switch to window if already loaded?
    call system('tmux new-window -P -F "#{pane_id} #{window_id}" -c ' .  new_worktree_path . ' vim .')
    return
  endif

  let buffers_in_current_worktree = filter(getbufinfo({ 'buflisted' : 1 }), {_, buf -> s:IsFileInsidePath(get(buf, 'name', ''), cwd)})
  let modified_buffers = filter(deepcopy(buffers_in_current_worktree), {_, buf -> get(buf, 'changed', 0) == 1 })
  let modified_buffers_names = map(deepcopy(modified_buffers), {_, buf -> fnamemodify(get(buf, 'name', ''), ':.')})


  if !empty(modified_buffers)
    call s:EchoWarning("Can not change worktree. Following files are not saved:")
    echo join(modified_buffers_names, '\n')

    return
  endif

  for buffer in buffers_in_current_worktree
    exec 'bd ' . get(buffer, 'bufnr', -1)
  endfor

  exec 'cd ' . new_worktree_path
  exec 'Ntree ' . new_worktree_path
  exec 'clearjumps'
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
  call system('git rev-parse HEAD')

  if v:shell_error > 0
    call s:EchoWarning('Not a git repo ' . getcwd())
    return
  endif

  if empty(a:arg)
    echo system('git worktree list')
    return
  endif

  let args = s:SplitAndFilter(a:arg)
  let cmd = args[0]
  let params = args[1:-1]
  let cmd = substitute(cmd, '\v^(\w)(.*)', 's:\u\1\e\2', '')

  if !exists('*' . cmd . 'SubCmd')
    call s:EchoWarning('Wrong command: ' . '"' . cmd[2:-1] . '".')
    return
  endif

  call call(function(cmd . 'SubCmd'), params)
endfunction


" TODO: flags and other options/commands
" TODO: add cmd completion for branches
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
    let current_branch = s:GetCurrentBranch()
    return filter(branches, {_, b -> b =~# '^' . a:lead && b !=# current_branch })
  endif

  " load
  if len(args) == 2 && 'load' =~# tolower(args[1]) && !empty(a:lead)
    return ['load']
  endif

  if len(args) >= 2 && tolower(args[1]) ==# 'load'
    let branches = map(s:GetWorktrees(), {_, wt -> get(wt, 'branch', '')})
    let current_branch = s:GetCurrentBranch()
    return filter(branches, {_, b -> b =~# '^' . a:lead && b !=# current_branch })
  endif


  if empty(a:lead)
    return ['add', 'remove', 'load']
  endif

  return []
endfunction
