%% The purpose of this module is to find out the type of the input
%% of each function that's in the scope of the tests, and assign the
%% right PropEr type information to them (so that the right generator can be used)
-module(typing).

-compile(export_all). % Exports all functions
-compile(debug_info).

-spec add_types([{atom(), string(), integer()}]) ->
    [{atom(), atom(), [proper_types:rich_result(proper_types:fin_type())]}].
add_types(Funs) ->
    lists:map(fun({Module, F, A}) ->
                      {Module,
                       erlang:list_to_atom(F),
                       lists:map(fun(Arg) ->
                                         get_type({Module, Arg})
                                 end,
                                 get_args(Module, F, A))}
              end,
              Funs).

-spec get_type({atom(), string()}) ->
    proper_types:rich_result(proper_types:fin_type()).
get_type({Module, TypeStr}) ->
    proper_typeserver:start(),
    {_, Type} = proper_typeserver:translate_type({Module, TypeStr}),
    proper_typeserver:stop(),
    Type.

% Gets back the list of arguments for given function, using the -specs statements in the source
-spec get_args(atom(), string(), integer()) -> [string()].
get_args(Module, F, A) ->
    Specs = lists:map(fun(X) -> parse_spec(X) end, get_specs(Module)),
    Funs = lists:search(fun({FunName,Args}) -> (FunName =:= F) and
                                               ((length(Args)) =:= A) end, Specs),
    case Funs of
        {value, {_, ArgList}} -> ArgList;
        false                 -> [] % TODO Handle this case
    end.

% Extracts all the function specs from a given module
-spec get_specs(atom()) -> [string()].
get_specs(Module) ->
    FileName = erlang:atom_to_list(Module) ++ ".erl",
    {_, File} = file:read_file(FileName),
    Source = erlang:binary_to_list(File),
    Lines = string:split(Source, "\n", all),
    lists:filter(fun(X) -> lists:prefix("-spec", X) end, Lines).

% Given a function spec, gives back the name and input types
-spec parse_spec(string()) -> {string(), [string()]}.
parse_spec(SpecStr) ->
    Clean = hd(string:split(string:slice(SpecStr, 6), " ->")),
    [FunName,ArgsStr] = string:split(Clean, "("),
    Args = string:split(lists:droplast(ArgsStr), ",", all),
    {FunName, Args}.