let g:onetags#debug_on = 0
let g:onetags#tags_dir = '~/.vim/tags'
let g:onetags#autobuild = 1
let g:onetags#project_markers = [ '.onetags.json', '.git', 'setup.py',
            \ 'Makefile', 'CMakeLists.txt', 'pom.xml', '.projections.json',
            \ '.ycm_extra_conf.py' ]
let g:onetags#ft2ctags = {
            \ 'ant': 'Ant',
            \ 'awk': 'Awk',
            \ 'c': 'C',
            \ 'cobol': 'Cobol',
            \ 'cpp': 'C++',
            \ 'cs': 'C#',
            \ 'dosbatch': 'DosBatch',
            \ 'erlang': 'Erlang',
            \ 'fortran': 'Fortran',
            \ 'freebasic': 'Basic',
            \ 'go': 'Go',
            \ 'html': 'HTML',
            \ 'ibasic': 'Basic',
            \ 'java': 'Java',
            \ 'javascript': 'JavaScript',
            \ 'lex': 'Flex',
            \ 'lisp': 'Lisp',
            \ 'lua': 'Lua',
            \ 'make': 'Make',
            \ 'ocaml': 'OCaml',
            \ 'pascal': 'Pascal',
            \ 'perl': 'Perl',
            \ 'php': 'PHP',
            \ 'python': 'Python',
            \ 'rexx': 'REXX',
            \ 'ruby': 'Ruby',
            \ 'scheme': 'Scheme',
            \ 'sh': 'Sh',
            \ 'slang': 'SLang',
            \ 'sml': 'SML',
            \ 'sql': 'SQL',
            \ 'tcl': 'Tcl',
            \ 'tex': 'Tex',
            \ 'vera': 'Vera',
            \ 'verilog': 'Verilog',
            \ 'vhdl': 'VHDL',
            \ 'vim': 'Vim',
            \ 'winbatch': 'DosBatch',
            \ 'objc': 'ObjectiveC',
            \ 'matlab': 'MatLab',
            \ 'xmath': 'MatLab',
            \ 'yacc': 'YACC'
            \}
let g:onetags#external_tags_defaults = {}
let g:onetags#managed_external_tags_defaults = {}
let g:onetags#managed_external_tags_defaults["python"] = {"venv_{proj}": "$VIRTUAL_ENV/lib"}
if isdirectory('/usr/include')
    let g:onetags#managed_external_tags_defaults["cpp"] = {"usr_include": "/usr/include"}
    let g:onetags#managed_external_tags_defaults["c"] = {"usr_include": "/usr/include"}
endif
