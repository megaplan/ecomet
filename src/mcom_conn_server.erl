%%%
%%% mcom_conn_server: mcom one connection server
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
%%% @doc server that handles one websocket connection: sends/receives
%%% data from/to client and amqp server
%%%

-module(mcom_conn_server).
-behaviour(gen_server).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([start/0, start_link/0, start_link/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([terminate/2, code_change/3]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include("mcom.hrl").
-include("rabbit_session.hrl").
-include_lib("amqp_client.hrl").

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
start() ->
    start_link().

%%-----------------------------------------------------------------------------
start_link() ->
    start_link(none).

%%-----------------------------------------------------------------------------
start_link(Conf) ->
    gen_server:start_link(?MODULE, Conf, []).

%%-----------------------------------------------------------------------------
stop(Pid) ->
    gen_server:call(Pid, stop).

%%%----------------------------------------------------------------------------
%%% gen_server callbacks
%%%----------------------------------------------------------------------------
init([List]) ->
    C = mcom_conf:get_child_config(List),
    New = prepare_all(C),
    mpln_p_debug:pr({?MODULE, init_done, ?LINE}, C#child.debug, run, 2),
    {ok, New, ?T}.

%%-----------------------------------------------------------------------------
handle_call(stop, _From, St) ->
    {stop, normal, ok, St};
handle_call(status, _From, St) ->
    {reply, St, St, ?T};
handle_call(_N, _From, St) ->
    mpln_p_debug:pr({?MODULE, call_other, ?LINE, _N}, St#child.debug, run, 2),
    {reply, {error, unknown_request}, St, ?T}.

%%-----------------------------------------------------------------------------
handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_N, St) ->
    mpln_p_debug:pr({?MODULE, cast_other, ?LINE, _N}, St#child.debug, run, 2),
    {noreply, St, ?T}.

%%-----------------------------------------------------------------------------
terminate(_, _State) ->
    ok.

%%-----------------------------------------------------------------------------
handle_info(#'basic.consume_ok'{consumer_tag = Tag},
            #child{conn=#conn{consumer_tag = Tag, consumer=undefined}} = St) ->
    mpln_p_debug:pr({?MODULE, consume_ok, ?LINE, Tag}, St#child.debug, run, 2),
    check_start_time(St);
handle_info(timeout, #child{conn=#conn{consumer=undefined}} = St) ->
    mpln_p_debug:pr({?MODULE, consume_extra, ?LINE}, St#child.debug, run, 0),
    check_start_time(St);
handle_info(timeout, State) ->
    New = do_smth(State),
    {noreply, New, ?T};
handle_info({ok, Sock}, #child{sock=undefined} = State) ->
    Lname = inet:sockname(Sock),
    Rname = inet:peername(Sock),
    Opts = inet:getopts(Sock, [active, reuseaddr]),
    mpln_p_debug:pr({?MODULE, socket_ok, ?LINE, Sock, Lname, Rname, Opts},
                   State#child.debug, run, 2),
    {noreply, State#child{sock=Sock}, ?T};
handle_info(_Other, #child{sock=undefined} = State) ->
    mpln_p_debug:pr({?MODULE, socket_discard, ?LINE, _Other},
                    State#child.debug, run, 2),
    {stop, normal, State};
handle_info({tcp, Sock, Data} = Msg, #child{sock = Sock} = State) ->
    mpln_p_debug:pr({?MODULE, tcp_data, ?LINE, Msg}, State#child.debug, msg, 6),
    New = mcom_handler_ws:send_msg_q(State, Sock, Data),
    {noreply, New, ?T};
handle_info({tcp_closed, Sock} = Msg, #child{sock = Sock} = State) ->
    mpln_p_debug:pr({?MODULE, tcp_closed, ?LINE, Msg}, State#child.debug,
                   run, 2),
    {stop, normal, State};
handle_info(_N, State) ->
    mpln_p_debug:pr({?MODULE, info_other, ?LINE, _N}, State#child.debug,
                   run, 2),
    {noreply, State, ?T}.

%%-----------------------------------------------------------------------------
code_change(_Old_vsn, State, _Extra) ->
    {ok, State}.

%%-----------------------------------------------------------------------------
%% Internal functions
%%-----------------------------------------------------------------------------
-spec prepare_all(#child{}) -> #child{}.

prepare_all(C) ->
    prepare_rabbit(C).

%%-----------------------------------------------------------------------------
-spec prepare_rabbit(#child{}) -> #child{}.

prepare_rabbit(#child{conn=Conn, event=Event} = C) ->
    Consumer_tag = mcom_rb:prepare_queue(Conn, Event),
    C#child{start_time=now(), conn=Conn#conn{consumer_tag=Consumer_tag}}.

%%-----------------------------------------------------------------------------
check_start_time(#child{start_time = T1} = State) ->
    T2 = now(),
    Diff = timer:now_diff(T2, T1),
    if  Diff > ?SETUP_CONSUMER_TIMEOUT ->
            {stop, consumer_setup_timeout, State};
        true ->
            New = State#child{conn=(State#child.conn)#conn{consumer=ok}},
            {noreply, New, ?T}
    end.

%%-----------------------------------------------------------------------------
do_smth(State) ->
    State.

%%-----------------------------------------------------------------------------
