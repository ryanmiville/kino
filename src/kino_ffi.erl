-module(kino_ffi).

-export([
    server_start_link/1
]).

server_start_link(Arg) ->
    case gen_server:start_link(kino@server, Arg, []) of
        {ok, Pid} -> {ok, Pid};
        {error, Reason} -> {error, Reason}
    end.
