%%%
%%% ecomet_conn_server: ecomet one connection server
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

-module(ecomet_conn_server).
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

-include("ecomet.hrl").
-include("ecomet_stat.hrl").
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
    C = ecomet_conf:get_child_config(List),
    New = prepare_all(C),
    mpln_p_debug:pr({?MODULE, init_done, ?LINE}, C#child.debug, run, 2),
    {ok, New, ?T}.

%%-----------------------------------------------------------------------------
handle_call(stop, _From, St) ->
    {stop, normal, ok, St};
handle_call(status, _From, St) ->
    New = do_smth(St),
    {reply, St, New, ?T};
handle_call(_N, _From, St) ->
    mpln_p_debug:pr({?MODULE, call_other, ?LINE, _N}, St#child.debug, run, 2),
    New = do_smth(St),
    {reply, {error, unknown_request}, New, ?T}.

%%-----------------------------------------------------------------------------
handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_N, St) ->
    mpln_p_debug:pr({?MODULE, cast_other, ?LINE, _N}, St#child.debug, run, 2),
    New = do_smth(St),
    {noreply, New, ?T}.

%%-----------------------------------------------------------------------------
terminate(_, _State) ->
    ok.

%%-----------------------------------------------------------------------------
%% @doc message from amqp
handle_info({#'basic.deliver'{delivery_tag = Tag}, Content} = _Req,
            #child{id=Id} = St) ->
    mpln_p_debug:pr({?MODULE, deliver, ?LINE, Id, _Req},
                    St#child.debug, rb_msg, 6),
    ecomet_rb:send_ack(St#child.conn, Tag),
    St_r = send_rabbit_msg(St, Content),
    New = do_smth(St_r),
    {noreply, New, ?T};

%% @doc amqp setup consumer confirmation
handle_info(#'basic.consume_ok'{consumer_tag = Tag},
            #child{id=Id,
                   conn=#conn{consumer_tag = Tag, consumer=undefined}} = St) ->
    mpln_p_debug:pr({?MODULE, consume_ok, ?LINE, Id, Tag},
                    St#child.debug, run, 2),
    New = do_smth(St),
    check_start_time(New);

%% @doc wrong amqp setup consumer confirmation
handle_info(timeout, #child{id=Id, conn=#conn{consumer=undefined}} = St) ->
    mpln_p_debug:pr({?MODULE, consume_extra, ?LINE, Id}, St#child.debug, run, 0),
    New = do_smth(St),
    check_start_time(New);

handle_info(timeout, St) ->
    New = do_smth(St),
    {noreply, New, ?T};

%% @doc init websocket ok
handle_info({ok, Sock}, #child{id=Id, type=ws, sock=undefined} = State) ->
    Lname = inet:sockname(Sock),
    Rname = inet:peername(Sock),
    Opts = inet:getopts(Sock, [active, reuseaddr]),
    mpln_p_debug:pr({?MODULE, socket_ok, ?LINE, Id, Sock, Lname, Rname, Opts},
                   State#child.debug, run, 2),
    New = do_smth(State),
    {noreply, New#child{sock=Sock}, ?T};

%% @doc init websocket failed
handle_info(_Other, #child{id=Id, type=ws, sock=undefined} = State) ->
    mpln_p_debug:pr({?MODULE, socket_discard, ?LINE, Id, _Other},
                    State#child.debug, run, 2),
    {stop, normal, State};

%% @doc data from websocket
handle_info({tcp, Sock, Data} = Msg, #child{id=Id, type=ws, sock=Sock} = St)
  when Sock =/= undefined ->
    mpln_p_debug:pr({?MODULE, tcp_data, ?LINE, Id, Msg},
                    St#child.debug, web_msg, 6),
    St_m= ecomet_handler_ws:send_msg_q(St, Data),
    New = do_smth(St_m),
    {noreply, New, ?T};

%% @doc websocket closed
handle_info({tcp_closed, Sock} = Msg, #child{id=Id, type=ws, sock=Sock} = St) ->
    mpln_p_debug:pr({?MODULE, tcp_closed, ?LINE, Id, Msg},
                    St#child.debug, run, 2),
    {stop, normal, St};

%% @doc long-poll init ok
handle_info({ok, Yaws_pid}, #child{id=Id, type=lp} = St) ->
    mpln_p_debug:pr({?MODULE, lp_init_ok, ?LINE, Id, Yaws_pid},
                    St#child.debug, run, 2),
    New = ecomet_handler_lp:send_init_chunk(St, Yaws_pid),
    {noreply, New, ?T};

%% @doc long-poll init failed
handle_info({discard, Yaws_pid}, #child{id=Id, type=lp, lp_sock=Sock} = St) ->
    mpln_p_debug:pr({?MODULE, lp_init_failed, ?LINE, Id, Yaws_pid},
                    St#child.debug, run, 2),
    yaws_api:stream_process_end(Sock, Yaws_pid),
    {stop, normal, St};

%% @doc unknown info
handle_info(_N, #child{id=Id} = St) ->
    mpln_p_debug:pr({?MODULE, info_other, ?LINE, Id, _N},
                    St#child.debug, run, 2),
    New = do_smth(St),
    {noreply, New, ?T}.

%%-----------------------------------------------------------------------------
code_change(_Old_vsn, State, _Extra) ->
    {ok, State}.

%%-----------------------------------------------------------------------------
%% Internal functions
%%-----------------------------------------------------------------------------
%%
%% @doc performs necessary preparations: own id, statistic, amqp
%%
-spec prepare_all(#child{}) -> #child{}.

prepare_all(C) ->
    Cid = prepare_id(C),
    Cst = prepare_stat(Cid),
    prepare_rabbit(Cst).

%%-----------------------------------------------------------------------------
%%
%% @doc initializes statistic
%%
prepare_stat(C) ->
    St = #stat{rabbit=
                   {
                 ecomet_stat:init(),
                 ecomet_stat:init(),
                 ecomet_stat:init()
                },
               wsock={
                 ecomet_stat:init(),
                 ecomet_stat:init(),
                 ecomet_stat:init()
                }
              },
    C#child{stat=St}.

%%-----------------------------------------------------------------------------
-spec prepare_rabbit(#child{}) -> #child{}.

prepare_rabbit(#child{conn=Conn, event=Event, no_local=No_local} = C) ->
    mpln_p_debug:pr({?MODULE, prepare_rabbit, ?LINE, C}, C#child.debug, run, 6),
    Consumer_tag = ecomet_rb:prepare_queue(Conn, Event, No_local),
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
%%
%% @doc creates uniq id to be used in filtering own messages returned by
%% rabbit which is lazy enough to not pay respect to no_local consumer flag
%%
prepare_id(St) ->
    Id = ecomet_data:gen_id(?OWN_ID_LEN),
    St#child{id_r = Id}.

%%-----------------------------------------------------------------------------
%%
%% @doc compares own id against the message's id, sends data received
%% from amqp to web client. Duplicates the message back to amqp.
%% @since 2011-10-14 15:40
%%
-spec send_rabbit_msg(#child{}, any()) -> #child{}.

send_rabbit_msg(#child{id=Id, id_r=Base, no_local=No_local} = St, Content) ->
    mpln_p_debug:pr({?MODULE, do_rabbit_msg, ?LINE, Id, Content},
                    St#child.debug, rb_msg, 6),
    {Payload, Corr_msg} = ecomet_rb:get_content_data(Content),
    case ecomet_data:is_our_id(Base, Corr_msg) of
        true when No_local == true ->
            mpln_p_debug:pr({?MODULE, do_rabbit_msg, our_id, ?LINE, Id},
                            St#child.debug, rb_msg, 5),
            ecomet_stat:add_own_msg(St);
        _ ->
            mpln_p_debug:pr({?MODULE, do_rabbit_msg, other_id, ?LINE, Id},
                            St#child.debug, rb_msg, 5),
            Stdup = ecomet_test:dup_message_to_rabbit(St, Payload), % FIXME: for debug only
            St_st = ecomet_stat:add_other_msg(Stdup),
            mpln_p_debug:pr({?MODULE, do_rabbit_msg, other_id, stat,
                             ?LINE, Id, St_st},
                            St#child.debug, stat, 6),
            proceed_send(St_st, Payload)
    end.

%%-----------------------------------------------------------------------------
proceed_send(#child{type=ws} = St, Content) ->
    ecomet_handler_ws:send_to_ws(St, Content);
proceed_send(#child{type=lp} = St, Content) ->
    ecomet_handler_lp:send_to_lp(St, Content).

%%-----------------------------------------------------------------------------
