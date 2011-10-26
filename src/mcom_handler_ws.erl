-module(mcom_handler_ws).

-export([send_msg_q/2, do_rabbit_msg/2]).

-include("mcom.hrl").

send_msg_q(St, Data) ->
    Payload = yaws_api:websocket_unframe_data(Data),
    L = binary_to_list(Payload),
    New = lists:reverse(L),
    do_send(St, New).

do_rabbit_msg(St, Data) ->
    do_send(St, Data).

do_send(#child{sock=Sock} = St, Data) ->
    mpln_p_debug:pr({?MODULE, do_send, ?LINE, Data}, St#child.debug, ws, 6),
    yaws_api:websocket_send(Sock, Data),
    yaws_api:websocket_setopts(Sock, [{active, once}]),
    St.
