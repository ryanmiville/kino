-module(kino_ffi).

-export([identity/1, gen_server_format_status/1, convert_handle_info_request/1,
         add_get/3]).

gen_server_format_status(Status) ->
    NewStatus =
        maps:map(fun (state, {state, State, _Builder}) ->
                         State;
                     (_, Value) ->
                         Value
                 end,
                 Status),
    io:format("~p~n", [NewStatus]),
    NewStatus.

convert_handle_info_request({'DOWN', Ref, process, Pid, Reason}) ->
    {process_down, Pid, Ref, Reason};
convert_handle_info_request(timeout) ->
    timeout;
convert_handle_info_request(Other) ->
    {unexpected, Other}.

identity(X) ->
    X.

add_get(Array, Index, Amount) ->
    try
        {ok, atomics:add_get(Array, Index + 1, Amount)}
    catch
        error:badarg ->
            {error, nil}
    end.
