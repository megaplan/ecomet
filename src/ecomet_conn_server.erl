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
-export([data_from_sio/2]).
-export([data_from_sjs/2]).
-export([data_from_server/2]).

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
    process_flag(trap_exit, true),
    C = ecomet_conf:get_child_config(List),
    mpln_p_debug:pr({?MODULE, init_start, ?LINE}, C#child.debug, run, 3),
    New = prepare_all(C),
    mpln_p_debug:pr({?MODULE, init, ?LINE, New}, C#child.debug, run, 6),
    mpln_p_debug:pr({?MODULE, init_done, ?LINE, New#child.id, New#child.id_web},
        C#child.debug, run, 2),
    erpher_et:trace_me(45, ?MODULE, New#child.id, init, New#child.sjs_sid),
    {ok, New, New#child.economize}.

%%-----------------------------------------------------------------------------
handle_call(stop, _From, St) ->
    {stop, normal, ok, St};

handle_call(status, _From, St) ->
    {reply, St, St, St#child.economize};

handle_call(_N, _From, St) ->
    mpln_p_debug:pr({?MODULE, call_other, ?LINE, _N}, St#child.debug, run, 2),
    {reply, {error, unknown_request}, St, St#child.economize}.

%%-----------------------------------------------------------------------------
handle_cast(stop, St) ->
    {stop, normal, St};

handle_cast({data_from_server, Data}, #child{id=Id, sjs_sid=Sid} = St) ->
    mpln_p_debug:pr({?MODULE, data_from_server, ?LINE, Id},
        St#child.debug, run, 2),
    mpln_p_debug:pr({?MODULE, data_from_server, ?LINE, Id, Data},
                    St#child.debug, web_msg, 6),
    erpher_et:trace_me(50, {?MODULE, Id}, Sid, data_from_server, Data),
    St_r = ecomet_conn_server_sjs:process_msg_from_server(St, Data),
    New = update_idle(St_r),
    call_gc(New),
    {noreply, New, New#child.economize};

handle_cast({data_from_sjs, Data}, #child{id=Id, sjs_sid=Sid} = St) ->
    mpln_p_debug:pr({?MODULE, data_from_sjs, ?LINE, Id},
        St#child.debug, run, 2),
    mpln_p_debug:pr({?MODULE, data_from_sjs, ?LINE, Id, Data},
                    St#child.debug, web_msg, 6),
    erpher_et:trace_me(50, {?MODULE, Id}, Sid, data_from_sjs, Data),
    St_r = ecomet_conn_server_sjs:process_msg(St, Data),
    New = update_idle(St_r),
    call_gc(New),
    {noreply, New, New#child.economize};

handle_cast({data_from_sio, Data}, #child{id=Id} = St) ->
    mpln_p_debug:pr({?MODULE, data_from_sio, ?LINE, Id},
        St#child.debug, run, 2),
    mpln_p_debug:pr({?MODULE, data_from_sio, ?LINE, Id, Data},
                    St#child.debug, web_msg, 6),
    St_r = ecomet_conn_server_sio:process_sio(St, Data),
    New = update_idle(St_r),
    {noreply, New, New#child.economize};

handle_cast(_N, #child{id=Id} = St) ->
    mpln_p_debug:pr({?MODULE, cast_other, ?LINE, Id, _N},
        St#child.debug, run, 2),
    {noreply, St, St#child.economize}.

%%-----------------------------------------------------------------------------
terminate(_, #child{id=Id, type=Type, conn=Conn, sjs_conn=Sconn} = St) ->
    erpher_et:trace_me(45, ?MODULE, Id, terminate, Sconn),
    Res_t = ecomet_rb:teardown_tags(Conn),
    Res_q = ecomet_rb:teardown_queues(Conn),
    ecomet_server:del_child(self(), Type, Id),
    if Type == 'sjs' ->
            catch sockjs:close(3000, "conn. closed", Sconn);
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
    erpher_et:trace_me(30, ?MODULE, Id, 'basic.deliver', Req),
    mpln_p_debug:pr({?MODULE, deliver, ?LINE, Id, Req},
                    St#child.debug, rb_msg, 6),
    ecomet_rb:send_ack(St#child.conn, Tag),
    New = send_rabbit_msg(St, Req),
    {noreply, New, New#child.economize};

%% @doc amqp setup consumer confirmation. In fact, unnecessary for case
%% of list of consumers
handle_info(#'basic.consume_ok'{consumer_tag = Tag}, #child{id=Id} = St) ->
    mpln_p_debug:pr({?MODULE, consume_ok, ?LINE, Id, Tag},
                    St#child.debug, run, 3),
    New = St#child{conn=(St#child.conn)#conn{consumer=ok}},
    {noreply, New, New#child.economize};

handle_info(timeout, St) ->
    New = periodic_check(St),
    {noreply, New, New#child.economize};

handle_info(idle_timeout, St) ->
    New = check_idle(St),
    {noreply, New, New#child.economize};

handle_info(periodic_check, St) ->
    New = periodic_check(St),
    {noreply, New, New#child.economize};

%% @doc unknown info
handle_info(_N, #child{id=Id} = St) ->
    mpln_p_debug:pr({?MODULE, info_other, ?LINE, Id, _N},
                    St#child.debug, run, 2),
    {noreply, St, St#child.economize}.

%%-----------------------------------------------------------------------------
code_change(_Old_vsn, State, _Extra) ->
    {ok, State}.

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
%%
%% @doc used for broadcast by ecomet_server
%% @since 2012-01-23 16:02
%%
data_from_server(Pid, Data) ->
    gen_server:cast(Pid, {data_from_server, Data}).

%%
%% @doc forwards data to a connection server which interacts
%% as a mediator between sockjs library and ecomet server
%% @since 2012-01-23 16:52
%%
data_from_sjs(Pid, Data) ->
    gen_server:cast(Pid, {data_from_sjs, Data}).

%%-----------------------------------------------------------------------------
data_from_sio(Pid, Data) ->
    gen_server:cast(Pid, {data_from_sio, Data}).

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

prepare_all(#child{sio_auth_recheck=T} = C) ->
    Now = now(),
    Cq = prepare_queue(C#child{start_time=Now, last_use=Now}),
    Cid = prepare_id(Cq),
    Cst = prepare_stat(Cid),
    Cr = prepare_rabbit(Cst),
    Ci = prepare_idle_check(Cr),
    Ref = erlang:send_after(T * 1000, self(), periodic_check),
    Ci#child{timer=Ref}.

%%-----------------------------------------------------------------------------
%%
%% @doc prepare timer for idle checks
%%
prepare_idle_check(#child{idle_timeout=T} = C) when is_integer(T) ->
    Iref = erlang:send_after(T * 1000, self(), idle_timeout),
    C#child{timer_idle=Iref};

prepare_idle_check(C) ->
    C.

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
-spec periodic_check(#child{}) -> #child{}.

periodic_check(#child{id=Id, queue=Q, qmax_dur=Dur, qmax_len=Max, timer=Ref,
                      sio_auth_recheck=T} = State) ->
    mpln_misc_run:cancel_timer(Ref),
    Qnew = clean_queue(Q, Dur, Max),
    St_c = State#child{queue=Qnew},
    St_a = check_auth(St_c),
    St_sent = send_queued_msg(St_a),
    mpln_p_debug:pr({?MODULE, periodic_check, ?LINE, Id, St_sent},
                    St_sent#child.debug, run, 7),
    Nref = erlang:send_after(T * 1000, self(), periodic_check),
    St_sent#child{timer=Nref}.

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
    ecomet_conn_server_sio:send(St, Key, Content).

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
%% @doc updates idle timer on GET/POST requests.
%%
update_idle(St) ->
    St#child{last_use=now()}.

%%-----------------------------------------------------------------------------
%%
%% @doc checks idle timer and casts stop to itself if it is more than
%% configured limit. Does not check socket-io processes. Does not check
%% in case of undefined limit
%%
check_idle(#child{type='sio'} = St) ->
    St;

check_idle(#child{idle_timeout=undefined} = St) ->
    St;

check_idle(#child{id=Id, id_web=Id_web, idle_timeout=Idle, last_use=T,
                 timer_idle=Ref} = St) ->
    mpln_misc_run:cancel_timer(Ref),
    Now = now(),
    Delta = timer:now_diff(Now, T),
    if Delta > Idle * 1000000 ->
            mpln_p_debug:pr({?MODULE, "stop on idle", ?LINE, Id, Id_web},
                            St#child.debug, run, 2),
            gen_server:cast(self(), stop),
            St#child{timer_idle=undefined};
       true ->
            Iref = erlang:send_after(Idle * 1000, self(), idle_timeout),
            St#child{timer_idle=Iref}
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
%% @doc call garbage collect for sockjs and cowboy processes
%% if deep_memory_economize in the config is true
%%
call_gc(#child{deep_memory_economize=true,
                 sjs_conn={sockjs_session,{_, Pid}}}) when is_pid(Pid) ->
    erlang:garbage_collect(Pid),
    case process_info(Pid, links) of
        {links, List} ->
            Cowboy = fetch_cowboy(List),
            [erlang:garbage_collect(X) || X <- Cowboy];
        _ ->
            ok
    end;

call_gc(_) ->
    ok.

%%-----------------------------------------------------------------------------
%%
%% @doc find cowboy processes
%%
fetch_cowboy(List) ->
    Info_list = [{X, process_info(X, initial_call)} || X <- List],
    [X || {X, {initial_call,{cowboy_http_protocol,init,_}}} <- Info_list].

%%-----------------------------------------------------------------------------
