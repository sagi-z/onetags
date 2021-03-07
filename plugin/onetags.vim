" Last Change:	2021 March 03
" Maintainer:	Sagi Zeevi <sagi.zeevi@gmail.com>
" License:      MIT


if exists("g:loaded_onetags")
    finish
endif
let g:loaded_onetags = 1

" temporarily change compatible option
let s:save_cpo = &cpo
set cpo&vim

function! s:Dbg(msg)
    if g:onetags#debug_on
        echom a:msg
    endif
endfunction


" Holds a mapping of files/directories to a project directory
let s:proj_dir = {}

" Holds information for project directories - gathered automatically and from config
let s:projs_cfg = {}

" Holds a generated prefix of files/directories per project
let s:tags_prefix = {}

" Holds a job per project directory
let s:jobs = {}

" make sure we have where to put the tag files
silent call mkdir(fnamemodify(g:onetags#tags_dir, ':p'), 'p')


" Assert we're working with a filetype we can handle
function! s:Filetype(ft='', throw=1)
    let ft = a:ft
    if ft == ''
        let ft = &l:filetype
    endif
    if ft == '' || ! has_key(g:onetags#ft2ctags, ft)
        if a:throw
            throw 'Unsupported filetype "' . ft . '" for file '. expand('%:p')
        else
            let fg = ''
        endif
    endif
    return ft
endfunction


" Try to get the project dir for a file according to markers in self/parent directories.
" If that fails and it is under the global getcwd then that global getcwd is
" the project dir.
" Otherwise we don't handle this file/dir.
function! s:proj_dir.entry(file_dir='')
    let file_dir = a:file_dir
    if file_dir == ''
        let file_dir = expand('%:p:h')
    else
        " This works if file_dir is a directory or a file
        let file_dir = fnamemodify(file_dir, '%:p:h')
    endif
    if g:onetags#debug_on | call s:Dbg('proj_dir.entry called for ' . file_dir) | endif
    if ! has_key(self, file_dir)
        let proj_dir = file_dir
        while proj_dir != $HOME && proj_dir != '/'
            for marker in g:onetags#project_markers
                if filereadable(proj_dir . '/' . marker)
                    break
                endif
            endfor
            let proj_dir = fnamemodify(proj_dir , ":h")
        endwhile
        if proj_dir == $HOME || proj_dir == '/'
            let global_proj_dir = getcwd(-1)
            if stridx(file_dir, global_proj_dir) == 0
                let proj_dir = global_proj_dir
            else
                throw 'No project detected for ' . file_dir
            endif
        endif
        let self[file_dir] = proj_dir
    endif
    if g:onetags#debug_on | call s:Dbg('proj_dir for ' . file_dir . ' is ' . self[file_dir]) | endif
    return self[file_dir]
endfunction


function! s:proj_dir.is_managed(file='')
    if a:file == ''
        let file = expand('%:p:h')
    else
        let file = fnamemodify(a:file, '%:p:h')
    endif
    return has_key(self, file)
endfunction


function! s:projs_cfg.entry(proj_dir)
    if ! has_key(self, a:proj_dir)
        let cfg = a:proj_dir . '/.onetags.json'
        if filereadable(cfg)
            if executable('cat')
                let cmd = 'cat ' . cfg
            else
                let cmd = 'type ' . cfg
            endif
            try
                let entry = json_decode(trim(system(cmd)))
                if g:onetags#debug_on | call s:Dbg('Loaded config for ' . a:proj_dir . ': ' . string(entry)) | endif
                let evaluated_entry = deepcopy(entry)
                for ft in keys(entry)
                    let ft_entry = entry[ft]
                    if has_key(ft_entry, 'external_tags') && ! empty(ft_entry['external_tags'])
                        let evaluated_entry[ft].external_tags = []
                        for tagsfile in ft_entry.external_tags
                            call add(evaluated_entry[ft].external_tags, fnamemodify(tagsfile, ':p'))
                        endfor
                    endif
                    if has_key(ft_entry, 'managed_external_tags') && ! empty(ft_entry.managed_external_tags)
                        let evaluated_entry[ft].managed_external_tags = {}
                        let proj_name = fnamemodify(a:proj_dir, ':t')
                        for [expr, val] in items(ft_entry.managed_external_tags)
                            let expr = substitute(expr, '{proj}', proj_name, 'g')
                            let tagsfile = fnamemodify(g:onetags#tags_dir, ':p:h') . '/external_tags.' . ft . '.' . expr . '.tags'
                            let evaluated_entry[ft].managed_external_tags[tagsfile] = val
                        endfor
                    endif
                endfor
                let entry = evaluated_entry
                if g:onetags#debug_on | call s:Dbg('evaluated_entry is ' . string(entry)) | endif
            catch /.*/
                echoerr "An error in project file '" . cfg . "' triggered: " . v:exception
                let entry = {}
            endtry
        else
            let entry = {}
        endif
        let self[a:proj_dir] = entry
    endif
    return self[a:proj_dir]
endfunction


" Not disabled per project unless specified in project config file
function! s:projs_cfg.autobuild_disabled(proj_dir)
    let cfg_entry = self.entry(a:proj_dir)
    if has_key(cfg_entry, 'autobuild_disabled')
       return cfg_entry['autobuild_disabled']
   else
   return 0
endfunction


function! s:projs_cfg.ft_entry(proj_dir='', ft='')
    let ft = s:Filetype(a:ft)
    let proj_dir = s:proj_dir.entry(a:proj_dir)
    let proj_entry = self.entry(proj_dir)
    if has_key(proj_entry, ft)
        let ft_entry = proj_entry[ft]
    else
        let ft_entry = {}
    endif
    " Make sure we have a sane entry even if we read from a file
    if ! has_key(ft_entry, 'tagsfile')
        let tagsfile = s:Tagsfile(ft)
        let ft_entry['tagsfile'] = tagsfile
    endif
    if ! has_key(ft_entry, 'external_tags')
        let ft_entry['external_tags'] = []
    endif
    if ! has_key(ft_entry, 'managed_external_tags')
        let ft_entry['managed_external_tags'] = {}
    endif
    if ! has_key(ft_entry, 'tags_str')
        let other_tags = 'tags,TAGS'
        if ! empty(ft_entry.external_tags)
            let other_tags = join(ft_entry.external_tags, ',') . ',' . other_tags
        endif
        if ! empty(ft_entry.managed_external_tags)
            let other_tags = join(keys(ft_entry.managed_external_tags), ',') . ',' . other_tags
        endif
        let ft_entry['tags_str'] = ft_entry.tagsfile . ',' . other_tags
    endif
    return ft_entry
endfunction


function! s:jobs.proj_entry(file_dir='')
    let proj_dir = s:proj_dir.entry(a:file_dir)
    if ! has_key(self, proj_dir)
        let self[proj_dir] = {}
    endif
    return self[proj_dir]
endfunction

function! s:jobs.ft_entry(ft='', file_dir='')
    let ft = s:Filetype(a:ft)
    let proj_dir_entry = self.proj_entry(a:file_dir)
    if ! has_key(proj_dir_entry, ft)
        let proj_dir_entry[ft] = {'job': v:none, 'waiting': 0}
    endif
    return proj_dir_entry[ft]
endfunction


function! s:tags_prefix.entry()
    let file_dir = expand('%:p:h')
    if ! has_key(self, file_dir)
        let proj_dir = s:proj_dir.entry(file_dir)
        let self[file_dir] = substitute(proj_dir, '\/', '.', 'g')
    endif
    return self[file_dir]
endfunction


function! s:Tagsfile(ft='')
    try
        let ft = s:Filetype(a:ft)
    catch /.*/
        return ''
    endtry
    return fnamemodify(g:onetags#tags_dir, ':p:h') . '/' . ft . s:tags_prefix.entry() . '.tags'
endfunction


function! s:TagsfileTmp(tagsfile)
    return a:tagsfile . '.running'
endfunction


function! s:CtagsProjCommand(ft, tagsfile)
    if g:onetags#debug_on | call s:Dbg("CtagsProjCommand") | endif
    if ! executable('fd')
       throw 'Please install fd (https://github.com/sharkdp/fd).'
    endif
    let srcs = join(systemlist("fd --search-path '" . s:proj_dir.entry() . "' -a -t f"), ' ')
    if v:shell_error != 0
        throw srcs
    endif
    let cmd = 'ctags -f ' . fnamemodify(a:tagsfile, ":p") . ' --languages=' . g:onetags#ft2ctags[a:ft] . ' ' . srcs
    if g:onetags#debug_on | call s:Dbg("cmd: " . cmd) | endif
    return cmd
endfunction


function! s:CtagsExternalCommand(ft, tagsfile, directory)
    if g:onetags#debug_on | call s:Dbg("CtagsExternalCommand") | endif
    if ! executable('fd')
       throw 'Please install fd (https://github.com/sharkdp/fd).'
    endif
    let tmpfile = tempname()
    let srcs = join(systemlist('fd --search-path "' . a:directory . '" -a -t f > ' . tmpfile), ' ')
    if v:shell_error != 0
        throw srcs
    endif
    let cmd = 'ctags -f ' . fnamemodify(a:tagsfile, ":p") . ' --languages=' . g:onetags#ft2ctags[a:ft] . ' -L ' . tmpfile
    if g:onetags#debug_on | call s:Dbg("cmd: " . cmd) | endif
    return cmd
endfunction


function! s:RefreshProjTagsDone(ft, proj_dir, tmp_tagsfile, tagsfile, msg, exitval)
    if g:onetags#debug_on | call s:Dbg('RefreshProjTagsDone()') | endif
    let ft_entry = s:jobs.ft_entry(a:ft, a:proj_dir)
    if a:exitval != 0
        let info = job_info(ft_entry.job)
        echoerr 'Job "' . string(info.cmd) . '" failed with error "' . job.exitval . '"'
        call delete(a:tmp_tagsfile)
    else
        if g:onetags#debug_on | call s:Dbg('rename(' . a:tmp_tagsfile . ', ' . a:tagsfile . ')') | endif
        call rename(a:tmp_tagsfile, a:tagsfile)
    endif
    let ft_entry.job = v:none
    if ft_entry.waiting
        let ft_entry.waiting = 0
        call s:RefreshProjTags(a:ft, a:proj_dir)
    endif
endfunction


function! s:RefreshProjTags(ft='', proj_dir='')
    if g:onetags#debug_on | call s:Dbg('RefreshProjTags invoked.') | endif
    let ft = s:Filetype(a:ft)
    let proj_dir = s:proj_dir.entry(a:proj_dir)
    let ft_entry = s:jobs.ft_entry(a:ft, a:proj_dir)
    if ft_entry.job isnot v:none
        let ft_entry.waiting = 1
        if g:onetags#debug_on | call s:Dbg('Another ctags is running for this filetype, will rerun automatically when it is done.') | endif
        return
    endif
    let tagsfile = s:Tagsfile()
    let tmp_tagsfile = s:TagsfileTmp(tagsfile)
    let cmd = s:CtagsProjCommand(ft, tmp_tagsfile)
    let ft_entry.job = job_start(cmd, {"exit_cb": funcref("<SID>RefreshProjTagsDone", [ft, proj_dir, tmp_tagsfile, tagsfile])})
endfunction


function! s:RefreshExternalTags(ft='', proj_dir='')
    if g:onetags#debug_on | call s:Dbg('RefreshExternalTags invoked.') | endif
    let ft = s:Filetype(a:ft)
    let proj_dir = s:proj_dir.entry(a:proj_dir)
    let cfg_ft_entry = s:projs_cfg.ft_entry(proj_dir, ft)
    if empty(cfg_ft_entry.managed_external_tags)
        echo "No managed external tags, use :OnetagsProjCfg to add."
    else
        for [tagsfile, directory] in items(cfg_ft_entry.managed_external_tags)
            let cmd = s:CtagsExternalCommand(ft, tagsfile, directory)
            echo "Start generating " . tagsfile . " for " . directory
            let output = system(cmd)
            if v:shell_error
                echoerr "Error generating " . tagsfile
                echoerr output
            else
                echo "Done generating " . tagsfile
            endif
        endfor
    endif
endfunction


function! s:ProjSettings(proj_dir='')
    let proj_file = s:proj_dir.entry(a:proj_dir) . '/' . '.onetags.json'
    try
        exe "b " . proj_file
    catch /.*/
        if g:onetags#debug_on | call s:Dbg('ProjSettings() new proj_file in ' . proj_file) | endif
        let ft = s:Filetype('', 0)
        exe "e " . proj_file
        if ft != '' && ! filereadable(proj_file)
            call setline(line('$'), '{')
            call append(line('$'), '    "' . ft . '": {')
            call append(line('$'), '        "autobuild_disabled": 0,')
            call append(line('$'), '        "external_tags": [')
            if has_key(g:onetags#external_tags_defaults, ft)
                for k in g:onetags#external_tags_defaults[ft]
                    call append(line('$'), '            "' . k . '",')
                endfor
                normal G$x
            endif
            call append(line('$'), '        ],')
            call append(line('$'), '        "managed_external_tags": {')
            if has_key(g:onetags#managed_external_tags_defaults, ft)
                for [k, v] in items(g:onetags#managed_external_tags_defaults[ft])
                    call append(line('$'), '            "' . k . '": "' . v . '",')
                endfor
                normal G$x
            endif
            call append(line('$'), '        }')
            call append(line('$'), '    }')
            call append(line('$'), '}')
            normal 1G
        endif
    endtry
endfunction


function! s:SetTags()
    try
        if g:onetags#debug_on | call s:Dbg('SetTags called') | endif
        let ft_entry = s:projs_cfg.ft_entry()
        let tags_str = ft_entry.tags_str
        if tags_str != ''
            if g:onetags#debug_on | call s:Dbg('SetTags to ' . tags_str) | endif
            let &l:tags = tags_str
            if g:onetags#autobuild && ! filereadable(ft_entry.tagsfile)
                call s:RefreshProjTags()
            endif
        endif
    catch /.*/
        if g:onetags#debug_on | call s:Dbg('SetTags failed :' . v:exception) | endif
    endtry
endfunction


function! s:ProjReload(proj_dir='')
    let proj_dir = s:proj_dir.entry(a:proj_dir)
    unlet s:projs_cfg[proj_dir]
    call s:SetTags()
endfunction


function! s:HandleWritePost()
    if g:onetags#autobuild && s:Filetype('', 0) != '' && s:proj_dir.is_managed()
        let proj_dir = s:proj_dir.entry()
        if ! s:projs_cfg.autobuild_disabled(proj_dir)
            let ft_entry = s:jobs.ft_entry()
            let ft_entry.waiting = 1
        endif
    endif
endfunction


function! s:CheckPendingUpdate()
    if g:onetags#autobuild && s:Filetype('', 0) != '' && s:proj_dir.is_managed()
        let proj_dir = s:proj_dir.entry()
        if ! s:projs_cfg.autobuild_disabled(proj_dir)
            let ft_entry = s:jobs.ft_entry()
            if ft_entry.waiting
                call s:RefreshProjTags()
            endif
        endif
    endif
endfunction


augroup onetags
    autocmd!
    autocmd BufEnter * call <SID>SetTags()
    autocmd BufWritePost * call <SID>HandleWritePost()
    autocmd BufLeave * call <SID>CheckPendingUpdate()
    autocmd CursorHold * call <SID>CheckPendingUpdate()
augroup end


if !exists(":OnetagsRebuild")
    command -nargs=*  OnetagsRebuild  :call <SID>RefreshProjTags(<q-args>)
endif
if !exists(":OnetagsRebuildExternal")
    command -nargs=*  OnetagsRebuildExternal  :call <SID>RefreshExternalTags(<q-args>)
endif
if !exists(":OnetagsProjCfg")
    command -nargs=?  OnetagsProjCfg  :call <SID>ProjSettings(<q-args>)
endif
if !exists(":OnetagsProjReload")
    command -nargs=?  OnetagsProjReload  :call <SID>ProjReload(<q-args>)
endif


" restore compatible option
let &cpo = s:save_cpo
unlet s:save_cpo
