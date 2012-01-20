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
%%% @doc server that handles one comet/websocket connection: sends/receives
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
-export([get_lp_data/2]).
-export([post_lp_data/3]).
-export([subscribe/4]).
-export([data_from_sio/2]).
-export([data_from_sjs/2]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include("ecomet_nums.hrl").
-include("ecomet.hrl").
-include("ecomet_child.hrl").
-include("ecomet_stat.hrl").
-include("rabbit_session.hrl").
-include_lib("amqp_client.hrl").

%%%----------------------------------------------------------------------------
%%% gen_server callbacks
%%%----------------------------------------------------------------------------
init([List]) ->
    C = ecomet_conf:get_child_config(List),
    mpln_p_debug:pr({?MODULE, init_start, ?LINE}, C#child.debug, run, 3),
    New = prepare_all(C),
    mpln_p_debug:pr({?MODULE, init, ?LINE, New}, C#child.debug, run, 6),
    mpln_p_debug:pr({?MODULE, init_done, ?LINE}, C#child.debug, run, 2),
    {ok, New, ?T}.

%%-----------------------------------------------------------------------------
%% @doc subscribe request from client via ecomet_server
handle_call({subscribe, Client, Event, No_local}, _From, #child{id=Id} = St) ->
    mpln_p_debug:pr({?MODULE, subscribe, ?LINE, Id}, St#child.debug, run, 3),
    St_s = do_subscribe(St, Client, Event, No_local),
    St_i = update_idle(St_s),
    New = do_smth(St_i),
    {reply, ok, New, ?T};

%% @doc post request from client via ecomet_server
handle_call({post_lp_data, Client, Data}, _From, St) ->
    St_r = process_lp_post(St, Client, Data),
    St_i = update_idle(St_r),
    New = do_smth(St_i),
    {reply, ok, New, ?T};

%% @doc call from client via ecomet_server for long poll data
%% @todo make it 'noreply' (is it necessary?)
handle_call({get_lp_data, Client}, _From, #child{clients=C} = St) ->
    C_dat = #cli{from=Client, start=now()},
    St_r = send_one_queued_msg(St#child{clients=[C_dat|C]}),
    St_i = update_idle(St_r),
    New = do_smth(St_i),
    {reply, ok, New, ?T};

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

handle_cast({data_from_sjs, Data}, St) ->
    mpln_p_debug:pr({?MODULE, data_from_sjs, ?LINE}, St#child.debug, run, 2),
    mpln_p_debug:pr({?MODULE, data_from_sjs, ?LINE, Data},
                    St#child.debug, run, 6),
    St_r = ecomet_conn_server_sjs:process_msg(St, Data),
    St_i = update_idle(St_r),
    New = do_smth(St_i),
    {noreply, New, ?T};

handle_cast({data_from_sio, Data}, St) ->
    mpln_p_debug:pr({?MODULE, data_from_sio, ?LINE}, St#child.debug, run, 2),
    St_r = ecomet_conn_server_sio:process_sio(St, Data),
    St_i = update_idle(St_r),
    New = do_smth(St_i),
    {noreply, New, ?T};

handle_cast(_N, St) ->
    mpln_p_debug:pr({?MODULE, cast_other, ?LINE, _N}, St#child.debug, run, 2),
    New = do_smth(St),
    {noreply, New, ?T}.

%%-----------------------------------------------------------------------------
terminate(_, #child{id=Id, type=Type, conn=Conn, sjs_conn=Sconn} = St) ->
    Res_t = ecomet_rb:teardown_tags(Conn),
    Res_q = ecomet_rb:teardown_queues(Conn),
    ecomet_server:del_child(self(), Type, Id),
    if Type == 'sjs' ->
            catch Sconn:close(3000, "conn. closed");
       true ->
            ok
    end,
    mpln_p_debug:pr({?MODULE, terminate, ?LINE, Id, Res_t, Res_q},
                    St#child.debug, run, 2),
    ok.

%%-----------------------------------------------------------------------------
%% @doc message from amqp
handle_info({#'basic.deliver'{delivery_tag=Tag}, _Content} = Req,
            #child{id=Id} = St) ->
    mpln_p_debug:pr({?MODULE, deliver, ?LINE, Id, Req},
                    St#child.debug, rb_msg, 6),
    ecomet_rb:send_ack(St#child.conn, Tag),
    St_r = send_rabbit_msg(St, Req),
    New = do_smth(St_r),
    {noreply, New, ?T};

%% @doc amqp setup consumer confirmation. In fact, unnecessary for case
%% of list of consumers
handle_info(#'basic.consume_ok'{consumer_tag = Tag}, #child{id=Id} = St) ->
    mpln_p_debug:pr({?MODULE, consume_ok, ?LINE, Id, Tag},
                    St#child.debug, run, 2),
    New = do_smth(St#child{conn=(St#child.conn)#conn{consumer=ok}}),
    {noreply, New, ?T};

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

%% @doc unknown info
handle_info(_N, #child{id=Id} = St) ->
    mpln_p_debug:pr({?MODULE, info_other, ?LINE, Id, _N},
                    St#child.debug, run, 2),
    New = do_smth(St),
    {noreply, New, ?T}.

%%-----------------------------------------------------------------------------
code_change(_Old_vsn, State, _Extra) ->
    {ok, State}.

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
data_from_sjs(Pid, Data) ->
    gen_server:cast(Pid, {data_from_sjs, Data}).

%%-----------------------------------------------------------------------------
data_from_sio(Pid, Data) ->
    gen_server:cast(Pid, {data_from_sio, Data}).

%%-----------------------------------------------------------------------------
get_lp_data(Pid, From) ->
    get_lp_data(Pid, From, infinity).

get_lp_data(Pid, From, Timeout) ->
    % FIXME: should be cast
    gen_server:call(Pid, {get_lp_data, From}, Timeout).

%%-----------------------------------------------------------------------------
post_lp_data(Pid, From, Data) ->
    post_lp_data(Pid, From, Data, infinity).

post_lp_data(Pid, From, Data, Timeout) ->
    % FIXME: should be cast
    gen_server:call(Pid, {post_lp_data, From, Data}, Timeout).

%%-----------------------------------------------------------------------------
subscribe(Pid, From, Event, No_local) ->
    subscribe(Pid, From, Event, No_local, infinity).

subscribe(Pid, From, Event, No_local, Timeout) ->
    % FIXME: should be cast
    gen_server:call(Pid, {subscribe, From, Event, No_local}, Timeout).

%%-----------------------------------------------------------------------------
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
    gen_server:cast(Pid, stop).

%%-----------------------------------------------------------------------------
%% Internal functions
%%-----------------------------------------------------------------------------
%%
%% @doc performs necessary preparations: own id, statistic, amqp
%%
-spec prepare_all(#child{}) -> #child{}.

prepare_all(C) ->
    Now = now(),
    Cq = prepare_queue(C#child{start_time=Now, last_use=Now}),
    Cid = prepare_id(Cq),
    Cst = prepare_stat(Cid),
    prepare_rabbit(Cst).

%%-----------------------------------------------------------------------------
%%
%% @doc initializes queue for received (amqp) messages
%%
prepare_queue(C) ->
    C#child{queue = queue:new()}.

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
%%
%% @doc prepares rabbit-mq if event is defined
%%
-spec prepare_rabbit(#child{}) -> #child{}.

prepare_rabbit(#child{event=undefined} = C) ->
    % exchanges and queues will be created on web messages data
    C;
prepare_rabbit(#child{conn=Conn, event=Event, no_local=No_local} = C) ->
    mpln_p_debug:pr({?MODULE, prepare_rabbit, ?LINE, C}, C#child.debug, run, 6),
    New_conn = ecomet_rb:prepare_queue_bind_one(Conn, Event, No_local),
    mpln_p_debug:pr({?MODULE, prepare_rabbit_queue, ?LINE, New_conn},
                    C#child.debug, run, 3),
    C#child{conn=New_conn}.

%%-----------------------------------------------------------------------------
%%
%% @doc does periodic things: clean queue, send queued messages, etc
%%
do_smth(#child{id=Id, queue=Q, qmax_dur=Dur, qmax_len=Max} = State) ->
    check_idle(State),
    Qnew = clean_queue(Q, Dur, Max),
    St_c = clean_clients(State#child{queue=Qnew}),
    St_a = check_auth(St_c),
    St_sent = send_queued_msg(St_a),
    mpln_p_debug:pr({?MODULE, do_smth, ?LINE, Id, St_sent},
                    St_sent#child.debug, run, 7),
    St_sent.

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
-spec send_rabbit_msg(#child{}, {#'basic.deliver'{}, any()}) -> #child{}.

send_rabbit_msg(#child{id=Id, id_r=Base, no_local=No_local} = St,
                {Dinfo, Content} = Req) ->
    mpln_p_debug:pr({?MODULE, do_rabbit_msg, ?LINE, Id, Req},
                    St#child.debug, rb_msg, 7),
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
                            St_st#child.debug, stat, 6),
            proceed_send(St_st, Dinfo, Payload)
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc proceeds sending the amqp message to anysocket or stores it
%% in a queue for later fetching it by long polling
%%
proceed_send(#child{type=sjs} = St, #'basic.deliver'{routing_key=Key},
             Content) ->
    ecomet_conn_server_sjs:send(St, Key, Content);

proceed_send(#child{type=sio} = St, #'basic.deliver'{routing_key=Key},
             Content) ->
    ecomet_conn_server_sio:send(St, Key, Content);
proceed_send(#child{type=ws} = St, _, Content) ->
    ecomet_handler_ws:send_to_ws(St, Content);
proceed_send(#child{type=lp} = St, _, Content) ->
    St_p = store_msg(St, Content),
    St_p.

%%-----------------------------------------------------------------------------
%%
%% @doc stores message in the state's queue for later transmission
%%
-spec store_msg(#child{}, binary()) -> #child{}.

store_msg(#child{queue = Q} = St, Data) ->
    Item = {now(), Data},
    Qnew = queue:in(Item, Q),
    St#child{queue=Qnew}.

%%-----------------------------------------------------------------------------
%%
%% @doc removes too old or surplus messages from the queue
%%
-spec clean_queue(queue(), non_neg_integer(), non_neg_integer()) -> queue().

clean_queue(Q, Dur, Max) ->
    Qlen = clean_queue_by_len(Q, Max),
    clean_queue_by_time(Qlen, Dur).

%%-----------------------------------------------------------------------------
%%
%% @doc gets rid the queue of ancient messages
%%
clean_queue_by_time(Q, Dur) ->
    Now = now(),
    F = fun({Time, _Data}) ->
                timer:now_diff(Now, Time) < Dur
        end,
    queue:filter(F, Q).

%%-----------------------------------------------------------------------------
%%
%% @doc cleands the queue from surplus messages
%%
clean_queue_by_len(Q, Max) ->
    Len = queue:len(Q),
    if Len > Max ->
            F = fun(_, Qacc) ->
                        {_, Qres} = queue:out(Qacc),
                        Qres
                end,
            Delta = Len - Max,
            lists:foldl(F, Q, lists:duplicate(Delta, true));
       true ->
            Q
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc sends one item to the client
%%
send_one_response(St, #cli{from=Client}, Item) ->
    Resp = make_response(Item),
    {ok, Dup_data} = Resp,
    ecomet_test:dup_message_to_rabbit(St, Dup_data), % FIXME: for debug only
    gen_server:reply(Client, Resp).

%%-----------------------------------------------------------------------------
%%
%% @doc creates a response to send to the wire
%%
make_response({_Time, Data}) ->
    Body = <<
             "<pre>",
             Data/binary,
             "</pre>"
           >>,
    {ok, Body}.

%%-----------------------------------------------------------------------------
%%
%% @doc sends a response if there is information available
%% to the original client (which called ecomet_server).
%%
send_msg_if_any(#child{queue=Q, clients=[C|T]} = St, Wipe) ->
    case queue:out(Q) of
        {{value, Item}, Q2} when Wipe == true ->
            send_one_response(St, C, Item),
            send_msg_if_any(St#child{queue=Q2, clients=T}, Wipe);
        {{value, Item}, Q2} ->
            send_one_response(St, C, Item),
            St#child{queue=Q2, clients=T};
        _ ->
            St
    end;
send_msg_if_any(#child{clients=[]} = St, _) ->
    St.

%%-----------------------------------------------------------------------------
%%
%% @doc sends all available messages to the original clients
%%
send_queued_msg(St) ->
    send_msg_if_any(St, true).

%%-----------------------------------------------------------------------------
%%
%% @doc sends one available message to the original client
%%
send_one_queued_msg(St) ->
    send_msg_if_any(St, false).

%%-----------------------------------------------------------------------------
%%
%% @doc sends data to amqp, returns ok to original client
%%
process_lp_post(#child{conn=Conn, event=Rt_key, id_r=Corr} = St,
           Client, Data) ->
    ecomet_rb:send_message(Conn#conn.channel, Conn#conn.exchange,
                           Rt_key, Data, Corr),
    Resp = make_response_post(),
    gen_server:reply(Client, Resp),
    St.

%%-----------------------------------------------------------------------------
make_response_post() ->
    {ok, "posted ok"}.

%%-----------------------------------------------------------------------------
%%
%% @doc updates idle timer on GET/POST requests.
%%
update_idle(St) ->
    St#child{last_use=now()}.

%%-----------------------------------------------------------------------------
%%
%% @doc checks idle timer and casts stop to itself if it is more than
%% configured limit. Does not check socket-io processes.
%%
check_idle(#child{type='sio'}) ->
    ok;
check_idle(#child{id=Id, id_web=Id_web, idle_timeout=Idle, last_use=T} = St) ->
    Now = now(),
    Delta = timer:now_diff(Now, T),
    if Delta > Idle * 1000000 ->
            mpln_p_debug:pr({?MODULE, "stop on idle", ?LINE, Id, Id_web},
                            St#child.debug, run, 2),
            gen_server:cast(self(), stop);
       true ->
            ok
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc performs auth check if the configured time limit is up
%%
check_auth(#child{sio_auth_last=Last, sio_auth_recheck=Interval} = St) ->
    Now = now(),
    Delta = timer:now_diff(Now, Last),
    if Delta > Interval * 1000000 ->
            ecomet_conn_server_sjs:recheck_auth(St);
       true ->
            St
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc removes old requests from long poll clients
%%
clean_clients(#child{lp_request_timeout=Timeout, clients=C} = St) ->
    Now = now(),
    F = fun(#cli{start=T}) ->
                timer:now_diff(Now, T) =< Timeout * 1000000
        end,
    New = lists:filter(F, C),
    St#child{clients=New}.

%%-----------------------------------------------------------------------------
%%
%% @doc subscribes itself to messages with the given routing key
%%
-spec do_subscribe(#child{}, any(), string() | binary(), boolean()) -> #child{}.

do_subscribe(St, Client, Event, No_local) ->
    New = prepare_rabbit(St#child{event=Event, no_local=No_local}),
    gen_server:reply(Client, ok),
    New.

%%-----------------------------------------------------------------------------
