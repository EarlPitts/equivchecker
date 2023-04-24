-module(diff).

-export([diff/2]).

parse_diff(DiffStr) ->
    [_|Files] = string:split(DiffStr, "diff --git ", all),
    Lines = lists:map(fun(Str) -> string:split(Str, "\n", all) end, Files),
    LinesByFiles = lists:map(fun([H,_,_,_|T]) -> {extract_file(H),lists:droplast(T)} end, Lines),
    lists:map(fun({FileName, DiffLines}) ->
                                     {FileName,
                                      tl(lists:foldr(fun add/2, [[]], DiffLines))} end,
                             LinesByFiles).

-spec extract_diffs(string()) -> {string(), [string()]}.
extract_diffs(Diff) ->
    [_|Files] = string:split(Diff, "diff --git ", all),
    Lines = lists:map(fun(X) -> string:split(X, "\n", all) end, Files),
    lists:map(fun([H|T]) -> {extract_file(H),T} end, Lines).

-spec extract_file(string()) -> string().
extract_file(DiffLine) ->
    Options = [global, {capture, [1], list}],
    {match, [[FileName]]} = re:run(DiffLine,".*/(.*\.erl).*", Options),
    FileName.

-spec is_function_sig(string()) -> boolean().
is_function_sig(Line) ->
    % Regexp for finding top-level function definitions
    case re:run(Line, "^[^-[:space:]%].*\\(.*?\\).*", []) of
        nomatch -> false;
        _       -> true
    end.

-spec get_name_and_arity(string()) -> {string(), integer()}.
get_name_and_arity(FunStr) ->
    Options = [global, {capture, [1], list}],
    {match, [[Fun]]} = re:run(FunStr, "^(.*?\\(.*?\\)).*", Options),
    {ok, Toks, _} = erl_scan:string(Fun ++ "."),
    {ok, [{call, _, {atom, _, Name}, Args}]} = erl_parse:parse_exprs(Toks),
    {atom_to_list(Name), length(Args)}.


add(Line, [LastHunk|Hunks]) ->
    case string:prefix(Line, "@@") of
        nomatch     -> [lists:append([Line],LastHunk)|Hunks];
        _Otherwise  -> [[],lists:append([Line],LastHunk)|Hunks]
    end.

%%% Accessors %%%

get_funcs({_, {_, OrigFun, _}, {_, RefacFun, _}}) ->
    {OrigFun, RefacFun}. 


hunks_by_file(FileName, Hunks) ->
    % TODO: this can be false
    lists:filter(fun({HunkFileName, _, _}) -> FileName =:= HunkFileName end, Hunks).

%%% Construct Hunks %%%

% TODO This needs the files already read in, `git diff --name-only`
diff(DiffStr, Sources) ->
    HunkLinesByFile = parse_diff(DiffStr),
    lists:flatmap(fun({FileName,Hunks}) ->
                          {_, Source} = lists:keyfind(FileName, 1, Sources),
                          lists:map(fun(Hunk) -> hunk(Hunk, FileName, Source) end, Hunks) end,
                  HunkLinesByFile).

% {{[x,y,z], {277, 279}}}
% {{[lines], {start, end}}, {[lines], {start, end}}}
hunk([Header|DiffLines], FileName, {OrigSource, RefacSource}) ->
    Options = [{capture, [1,2,3,4], list}],
    % Captures the line numbers and optionally the length for multiline hunks
    Pattern = "@@ -(\\d+),?(\\d?).*\\+(\\d+),?(\\d?).*",
    {match,[OrigStart, OrigLen, RefacStart, RefacLen]} = re:run(Header, Pattern, Options),
    OrigLines = lists:map(fun([_|Line]) -> Line end,
                          lists:filter(fun([FstChar|_]) -> [FstChar] =:= "-" end,
                                       DiffLines)),
    RefacLines = lists:map(fun([_|Line]) -> Line end,
                           lists:filter(fun([FstChar|_]) -> [FstChar] =:= "+" end,
                                        DiffLines)),
    {OF, OA} = find_function(OrigSource, erlang:list_to_integer(OrigStart)),
    {RF, RA} = find_function(RefacSource, erlang:list_to_integer(RefacStart)),
    M = erlang:list_to_atom(filename:rootname(FileName, ".erl")),
    case {OrigLen, RefacLen} of
        {[], []}   -> {FileName, {OrigLines, {M, OF, OA}, {erlang:list_to_integer(OrigStart), 0}},
                       {RefacLines, {M, RF, RA}, {erlang:list_to_integer(RefacStart), 0}}};
        {[], _}    -> {FileName, {OrigLines, {M, OF, OA}, {erlang:list_to_integer(OrigStart), 0}},
                       {RefacLines, {M, RF, RA}, {erlang:list_to_integer(RefacStart), RefacLen}}};
        {_, []}    -> {FileName, {OrigLines, {M, OF, OA}, {erlang:list_to_integer(OrigStart), OrigLen}},
                       {RefacLines, {M, RF, RA}, {erlang:list_to_integer(RefacStart), 0}}};
        _Otherwise -> {FileName, {OrigLines, {M, OF, OA}, {erlang:list_to_integer(OrigStart), erlang:list_to_integer(OrigLen)}},
                       {RefacLines, {M, RF, RA}, {erlang:list_to_integer(RefacStart), erlang:list_to_integer(RefacLen)}}}
    end.
    
find_function(Source, LineNum) ->
    Signature = (lists:dropwhile(fun(Line) -> not(is_function_sig(Line)) end,
                    lists:reverse(lists:sublist(Source, LineNum)))),
    case Signature of
        []         -> {"", ""}; % TODO: Not a diff in a function, mostly export list elements
        _Otherwise -> get_name_and_arity(Signature)
    end.
