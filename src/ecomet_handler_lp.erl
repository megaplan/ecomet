%%%
%%% ecomet_handler_lp: ecomet handler for long polling
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
%%% @since 2011-11-01 14:50
%%% @license MIT
%%% @doc handler module that contains long polling functions
%%%

-module(ecomet_handler_lp).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([send_init_chunk/2, send_chunk/2, send_to_lp/2]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include("ecomet.hrl").

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
%%
%% @doc sends debug text to long polled socket. Unnecessary.
%% @since 2011-11-01 17:57
%% @todo remove it
%%
-spec send_init_chunk(#child{}, pid()) -> #child{}.

send_init_chunk(St, Yaws_pid) ->
    %Data = "chunk init lp done",
    %send_chunk(St, Data),
    St#child{yaws_pid = Yaws_pid}.

%%-----------------------------------------------------------------------------
%%
%% @doc sends data to long polled socket.
%% @since 2011-11-01 17:57
%%
-spec send_chunk(#child{}, iolist()) -> ok.

send_chunk(#child{lp_sock=Sock, id=Id, yaws_pid=Yaws_pid} = St, Data) ->
    mpln_p_debug:pr({?MODULE, send_to_lp, ?LINE, Id, Data},
                    St#child.debug, lp, 6),
    yaws_api:stream_process_deliver(Sock, Data),
    %timer:sleep(300),
    yaws_api:stream_process_end(Sock, Yaws_pid).
    

%%-----------------------------------------------------------------------------
%%
%% @doc sends data with 'pre' html tags around it to long polled socket
%% @since 2011-11-01 17:57
%%
-spec send_to_lp(#child{}, binary() | iolist()) -> #child{}.

send_to_lp(#child{id=Id} = St, Data) ->
    mpln_p_debug:pr({?MODULE, send_to_lp, ?LINE, Id, Data},
                    St#child.debug, lp, 6),
    New = ["<pre>", Data, "</pre>\n"],
    send_chunk(St, New),
    St.
    
%%-----------------------------------------------------------------------------
