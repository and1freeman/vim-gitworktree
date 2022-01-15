" TODO: load on worktree add. flag?
" TODO: add cmd autocomplete
" TODO: refactor autocomplete
" TODO: add worktree from head of specified branch
" TODO: make load command create worktree, if it doesn't exist
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


function! s:IsGitWorktree() abort
  call system('git rev-parse HEAD')
  return v:shell_error == 0
endfunction


function! s:IsBareRepo() abort
  return trim(system('git rev-parse --is-bare-repository'), " \n") ==# 'true'
endfunction


function! s:GetWorktrees() abort
  let worktrees = []

  for worktree in systemlist('git worktree list')
    let list = s:SplitAndFilter(worktree)

    if matchstr(worktree, '\s(\zsbare\ze)') ==# 'bare'
      continue
    endif

    let path = matchstr(worktree, '^\f*')
    let sha = matchstr(worktree, '\s\+\zs\x*\ze\s\+')
    let branch = matchstr(worktree, '\[\zs.*\ze\]')
    let is_detached = empty(branch)

    call extend(worktrees, [{ 'branch': branch, 'path': path, 'sha': sha, 'is_detached': is_detached }])
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


function! s:Load(...) abort
  if a:0 == 0
    call s:EchoWarning('No worktree provided')
    return
  endif

  let cwd = getcwd()
  let worktrees = s:GetWorktrees()

  " new worktree
  let [nwt, found] = s:Find({wt -> wt.branch ==# a:1 || wt.path ==# a:1}, worktrees)

  if !found
    call s:EchoWarning('Worktree not found: ' . a:1)
    return
  endif

  " current worktree
  let [cwt, found] = s:Find({wt -> wt.path ==# cwd}, worktrees)

  if found
    let cwt_path = cwt.path
    let cwt_branch = cwt.branch
    let cwt_sha = cwt.sha

    if (a:1 ==# cwt_branch || a:1 ==# cwt_path)
      let msg = 'Already in '  . cwt_path  .  (empty(cwt_branch)  ? '    ' .  cwt_sha . '  (detached HEAD)' : '    [' . cwt_branch . ']')

      call s:EchoWarning(msg)
      return
    endif
  endif

  let nwt_path = nwt.path
  let window_name = empty(nwt.branch) ? nwt.sha : nwt.branch

  if g:gitworktree_config.use_tmux
    " TODO: switch to window if already loaded?
    call system('tmux new-window -P -F "#{pane_id} #{window_id}" -n ' .  window_name . ' -c ' .  nwt_path . ' vim -c "clearjumps" .')
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

  exec 'cd ' . nwt_path
  exec 'Ntree ' . nwt_path
  exec 'clearjumps'
endfunction


function! s:Add(...) abort
  let cmd = 'git worktree add ' . join(a:000)
  echo system(cmd)
endfunction


" TODO: add --force flag support
function! s:Remove(...) abort
  let cmd = 'git worktree remove '

  let arg = a:000[0]
  let worktrees = s:GetWorktrees()

  let [rwt, found] = s:Find({wt -> wt.branch ==# arg || wt.branch ==# wt.path }, worktrees)

  if !found
    call s:EchoWarning('Worktree not found')
    return
  endif

  if rwt.path ==# getcwd()
    call s:EchoWarning('Can not remove current worktree')
    return
  endif

  echo system(cmd . rwt.path)
endfunction


function! s:List() abort
  echo system('git worktree list')
endfunction


function! s:RemoveComplete(lead, ...) abort
  if a:0 == 0 && empty(a:lead) || a:0 == 1 && !empty(a:lead)
    let arg = empty(a:000) ? '' : a:1
    let variants = map(s:GetWorktrees(), {_, wt -> wt.is_detached ? wt.path : wt.branch})
    return filter(variants, {_, r -> r =~# '^' . arg})
  endif

  return []
endfunction


function! s:LoadComplete(lead, ...) abort
  return call('s:RemoveComplete', extend([a:lead], a:000))
endfunction


let s:Commands = {
      \ 'add': function('s:Add'),
      \ 'list': function('s:List'),
      \ 'remove': function('s:Remove'),
      \ 'load': function('s:Load'),
      \ }


let s:CompletionFunctions = {
      \ 'add': {-> []},
      \ 'remove': function('s:RemoveComplete'),
      \ 'load': function('s:LoadComplete'),
      \ }


function! gitworktree#call(arg) abort
  let is_git_worktree = s:IsGitWorktree()

  if !is_git_worktree
    call s:EchoWarning('Not a git repo or worktree ' . getcwd())
    return
  endif

  let args = s:SplitAndFilter(empty(a:arg) ? 'list' : a:arg)
  let cmd = args[0]
  let params = args[1:-1]

  let Cmd = get(s:Commands, cmd, {... -> call('s:EchoWarning', ['Unknown command: ' . '"' . cmd . '"'])})

  call call(Cmd, params)
endfunction


function! gitworktree#complete(lead, line, pos) abort
  let args = s:SplitAndFilter(a:line)
  let cmds = keys(s:Commands)

  if len(args) == 1
    return cmds
  elseif len(args) == 2 && !empty(a:lead)
    return filter(cmds, {_, cmd -> cmd =~# '^' . args[1] })
  endif

  let CompletionFunction = get(s:CompletionFunctions, args[1], {-> []})

  return call(CompletionFunction, extend([a:lead], args[2:-1]))
endfunction
