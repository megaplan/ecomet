%%%
%%% ecomet_handler_ws: handler for one websocket
%%%
%%% Copyright (c) 2011 Megaplan Ltd. (Russia)
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"),
%%% to deal in the Software without restriction, including without limitation
%%% the rights to use, copy, modify, merge, publish, distribute, sublicense,
%%% and/or sell copies of the Software, and to permit persons to whom
%%% the Software is furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included
%%% in all copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
%%% MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
%%% IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
%%% CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
%%% TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
%%% SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
%%%
%%% @author arkdro <arkdro@gmail.com>
%%% @since 2011-10-14 15:40
%%% @license MIT
%%% @doc handles one websocket: sends/receives data to/from client/amqp
%%%

-module(ecomet_handler_ws).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([send_msg_q/2, do_rabbit_msg/2]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include("ecomet.hrl").
-include("rabbit_session.hrl").

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
%%
%% @doc sends data received from websocket to amqp
%% @since 2011-10-26 15:40
%%
send_msg_q(#child{conn=Conn, event=Rt_key, id_r=Id} = St, Data) ->
    mpln_p_debug:pr({?MODULE, send_msg_q, ?LINE, St}, St#child.debug, run, 6),
    Payload = yaws_api:websocket_unframe_data(Data),
    L = binary_to_list(Payload),
    New = lists:reverse(L),
    New_r = list_to_binary(New),
    Res_data = <<Id/binary, New_r/binary>>,
    mpln_p_debug:pr({?MODULE, send_msg_q, ?LINE, Res_data}, St#child.debug, run, 6),
    ecomet_rb:send_message(Conn#conn.channel, Conn#conn.exchange, Rt_key, Res_data),
    St.

%%-----------------------------------------------------------------------------
%%
%% @doc sends data received from amqp to websocket
%% @since 2011-10-14 15:40
%%
do_rabbit_msg(#child{id_r=I1} = St, <<I2:?ID_LEN/binary, _/binary>>)
  when I1 == I2 ->
    St;
do_rabbit_msg(St, Data) ->
    send_to_ws(St, Data).

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
%%
%% @doc sends data to websocket
%%
send_to_ws(#child{sock=Sock} = St, Data) ->
    mpln_p_debug:pr({?MODULE, send_to_ws, ?LINE, Data}, St#child.debug, ws, 6),
    yaws_api:websocket_send(Sock, Data),
    yaws_api:websocket_setopts(Sock, [{active, once}]),
    St.

%%-----------------------------------------------------------------------------
