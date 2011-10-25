-module(mcom_handler_ws).

-export([send_msg_q/3]).

-include("mcom.hrl").


send_msg_q(St, Sock, Data) ->
    Payload = yaws_api:websocket_unframe_data(Data),
    mpln_p_debug:pr({?MODULE, send_msg_q, ?LINE, Payload},
                    St#child.debug, ws, 6),
    L = binary_to_list(Payload),
    New = lists:reverse(L),
    yaws_api:websocket_send(Sock, New),
    yaws_api:websocket_setopts(Sock, [{active, once}]),
    St.
