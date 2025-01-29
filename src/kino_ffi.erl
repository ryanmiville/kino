-module(kino_ffi).

-export([convert_starter_result/1, server_start_link/1, dynamic_supervisor_start_child/2,
         supervisor_start_link/1, supervisor_start_child/2]).

server_start_link(Arg) ->
    case gen_server:start_link(kino@internal@gen_server, Arg, []) of
        {ok, Pid} ->
            {ok, Pid};
        {error, Reason} ->
            {error, Reason}
    end.

supervisor_start_link(Arg) ->
    case supervisor:start_link(kino@internal@supervisor, Arg) of
        {ok, P} ->
            {ok, P};
        {error, E} ->
            {error, {init_crashed, E}}
    end.

supervisor_start_child(SupRef, ChildSpec) ->
    case supervisor:start_child(SupRef, ChildSpec) of
        {ok, P} ->
            {ok, {P, nil}};
        {ok, P, Info} ->
            {ok, {P, Info}};
        {error, E} ->
            {error, E}
    end.

dynamic_supervisor_start_child(SupRef, ChildSpec) ->
    case supervisor:start_child(SupRef, ChildSpec) of
        {ok, P} ->
            {ok, {P, nil}};
        {ok, P, Info} ->
            {ok, {P, Info}};
        {error, E} ->
            {error, E}
    end.

convert_starter_result(Res) ->
    case Res of
        {ok, {Pid, Info}} ->
            {ok, Pid, Info};
        {error, E} ->
            {error, E}
    end.
