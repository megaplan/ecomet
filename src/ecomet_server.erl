%%%
%%% ecomet_server: server to create children to serve new websocket requests
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
%%% @doc server to create children to serve new comet requests. Upon a request
%%% from a underlying comet (sockjs) library. It connects
%%% to rabbit and creates children with amqp connection provided.
%%%

-module(ecomet_server).
-behaviour(gen_server).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([start/0, start_link/0, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([terminate/2, code_change/3]).
-export([add_rabbit_inc_own_stat/0, add_rabbit_inc_other_stat/0]).
-export([del_child/3]).
-export([add_sio/4, del_sio/1, sio_msg/3]).
-export([sjs_add/2, sjs_del/2, sjs_msg/3]).
-export([sjs_broadcast_msg/1]).
-export([get_stat_raw/0]).
-export([
    reload_config_signal/0,
         get_stat_procs/0,
         get_stat_procs_mem/0
        ]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include("ecomet.hrl").
-include("ecomet_nums.hrl").
-include("ecomet_server.hrl").
-include("ecomet_stat.hrl").
-include("rabbit_session.hrl").

%%%----------------------------------------------------------------------------
%%% gen_server callbacks
%%%----------------------------------------------------------------------------

init(_) ->
    C = ecomet_conf:get_config(),
    New = prepare_all(C),
    mpln_p_debug:pr({?MODULE, 'init done', ?LINE}, New#csr.debug, run, 1),
    {ok, New, ?T}.

%%-----------------------------------------------------------------------------
handle_call({add_sio, Mgr, Handler, Client, Sid}, _From, St) ->
    mpln_p_debug:pr({?MODULE, 'add_sio_child', ?LINE}, St#csr.debug, run, 2),
    {Res, New} = add_sio_child(St, Mgr, Handler, Client, Sid),
    {reply, Res, New};

handle_call({sjs_add, Sid, Conn}, _From, St) ->
    mpln_p_debug:pr({?MODULE, 'add_sjs_child', ?LINE, Sid},
                    St#csr.debug, run, 2),
    erpher_et:trace_me(45, ?MODULE, undefined, sockjs_add_child, Sid),
    {Res, New} = add_sjs_child(St, Sid, Conn),
    {reply, Res, New};

% @doc returns accumulated statistic as a list of tuples
% {atom(), {dict(), dict(), dict()}}
handle_call({get_stat, Tag}, _From, St) ->
    Res = prepare_stat_result(St, Tag),
    {reply, Res, St};

handle_call(status, _From, St) ->
    {reply, St, St};
handle_call(stop, _From, St) ->
    {stop, normal, ok, St};
handle_call(_N, _From, St) ->
    {reply, {error, unknown_request}, St}.

%%-----------------------------------------------------------------------------
handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(add_rabbit_inc_other_stat, St) ->
    New = add_msg_stat(St, inc_other),
    {noreply, New};
handle_cast(add_rabbit_inc_own_stat, St) ->
    New = add_msg_stat(St, inc_own),
    {noreply, New};
handle_cast({del_child, Pid, Type, Ref}, St) ->
    New = del_child_pid(St, Pid, Type, Ref),
    {noreply, New};
handle_cast({sio_msg, Pid, Sid, Data}, St) ->
    New = process_sio_msg(St, Pid, Sid, Data),
    {noreply, New};
handle_cast({del_sio, Pid}, St) ->
    New = del_sio_pid(St, Pid),
    {noreply, New};

handle_cast({sjs_del, Sid, Conn}, St) ->
    erpher_et:trace_me(45, ?MODULE, undefined, sockjs_del_child, Sid),
    New = del_sjs_pid2(St, Sid, Conn),
    {noreply, New};

handle_cast({sjs_msg, Sid, Conn, Data}, St) ->
    erpher_et:trace_me(40, ?MODULE, undefined, sockjs_message, {Sid, Data}),
    New = process_sjs_msg(St, Sid, Conn, Data),
    {noreply, New};

handle_cast({sjs_broadcast_msg, Data}, St) ->
    erpher_et:trace_me(40, ?MODULE, undefined, sockjs_broadcast_message, Data),
    New = process_sjs_broadcast_msg(St, Data),
    {noreply, New};

handle_cast(reload_config_signal, St) ->
    New = process_reload_config(St),
    {noreply, New};

handle_cast(_, St) ->
    {noreply, St}.

%%-----------------------------------------------------------------------------
terminate(_, _State) ->
    %yaws:stop(),
    ok.

%%-----------------------------------------------------------------------------
handle_info(timeout, State) ->
    New = periodic_check(State),
    {noreply, New};

handle_info(periodic_check, State) ->
    New = periodic_check(State),
    {noreply, New};

handle_info(periodic_send_stat, State) ->
    New = periodic_send_stat(State),
    {noreply, New};

handle_info(_, State) ->
    {noreply, State}.

%%-----------------------------------------------------------------------------
code_change(_Old_vsn, State, _Extra) ->
    {ok, State}.

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------

start() ->
    start_link().

%%-----------------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%-----------------------------------------------------------------------------
stop() ->
    gen_server:call(?MODULE, stop).

%%-----------------------------------------------------------------------------
%%
%% @doc requests for creating a new sockjs child
%% @since 2012-01-17 18:11
%%
sjs_add(Sid, Conn) ->
    gen_server:call(?MODULE, {sjs_add, Sid, Conn}).

%%
%% @doc requests for terminating a sockjs child
%% @since 2012-01-17 18:11
%%
sjs_del(Sid, Conn) ->
    gen_server:cast(?MODULE, {sjs_del, Sid, Conn}).

%%
%% @doc requests for sending a message to a sockjs child
%% @since 2012-01-17 18:11
%%
sjs_msg(Sid, Conn, Data) ->
    gen_server:cast(?MODULE, {sjs_msg, Sid, Conn, Data}).

%%
%% @doc requests for sending a message to all the sockjs children
%% @since 2012-01-23 15:24
%%
sjs_broadcast_msg(Data) ->
    gen_server:cast(?MODULE, {sjs_broadcast_msg, Data}).

%%-----------------------------------------------------------------------------
%%
%% @doc creates a process that talks to socket-io child started somewhere else.
%% 'no local' mode (amqp messages from the child should not return to this
%% child).
%% @since 2011-11-22 16:24
%%
-spec add_sio(pid(), atom(), pid(), any()) -> {ok, pid()}
                                              | {ok, pid(), any()}
                                              | {error, any()}.

add_sio(Manager, Handler, Client, Sid) ->
    gen_server:call(?MODULE, {add_sio, Manager, Handler, Client, Sid}).

%%-----------------------------------------------------------------------------
%%
%% @doc sends data from socket-io child to connection handler
%% @since 2011-11-23 14:45
%%
-spec sio_msg(pid(), any(), any()) -> ok.

sio_msg(Client, Sid, Data) ->
    gen_server:cast(?MODULE, {sio_msg, Client, Sid, Data}).

%%-----------------------------------------------------------------------------
%%
%% @doc deletes a process that talks to socket-io child
%% @since 2011-11-23 13:33
%%
-spec del_sio(pid()) -> ok.

del_sio(Client) ->
    gen_server:cast(?MODULE, {del_sio, Client}).

%%-----------------------------------------------------------------------------
%%
%% @doc deletes a child from an appropriate list of children
%% @since 2011-11-18 18:00
%%
-spec del_child(pid(), 'sio'|'sjs', reference()) -> ok.

del_child(Pid, Type, Ref) ->
    gen_server:cast(?MODULE, {del_child, Pid, Type, Ref}).

%%-----------------------------------------------------------------------------
%%
%% @doc updates statistic messages
%% @since 2011-10-28 16:21
%%
-spec add_rabbit_inc_own_stat() -> ok.

add_rabbit_inc_own_stat() ->
    gen_server:cast(?MODULE, add_rabbit_inc_own_stat).

%%-----------------------------------------------------------------------------
%%
%% @doc updates statistic messages
%% @since 2011-10-28 16:21
%%
-spec add_rabbit_inc_other_stat() -> ok.

add_rabbit_inc_other_stat() ->
    gen_server:cast(?MODULE, add_rabbit_inc_other_stat).

%%-----------------------------------------------------------------------------
get_stat_raw() ->
    gen_server:call(?MODULE, {get_stat, raw}).

get_stat_procs() ->
    gen_server:call(?MODULE, {get_stat, procs}).

get_stat_procs_mem() ->
    gen_server:call(?MODULE, {get_stat, procs_mem}).

%%-----------------------------------------------------------------------------
reload_config_signal() ->
    gen_server:cast(?MODULE, reload_config_signal).

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
%%
%% @doc calls supervisor to create child
%%
-spec do_start_child(reference(), list()) ->
                            {ok, pid()} | {ok, pid(), any()} | {error, any()}.

do_start_child(Id, Pars) ->
    Ch_conf = [Pars],
    StartFunc = {ecomet_conn_server, start_link, [Ch_conf]},
    Child = {Id, StartFunc, temporary, 1000, worker, [ecomet_conn_server]},
    supervisor:start_child(ecomet_conn_sup, Child).

%%-----------------------------------------------------------------------------
add_sio_child(St, Mgr, Handler, Client, Sid) ->
    Pars = [
            {sio_mgr, Mgr},
            {sio_hdl, Handler},
            {sio_cli, Client},
            {sio_sid, Sid},
            {no_local, true}, % FIXME: make it a var?
            {type, 'sio'}
           ],
    add_child(St, Pars).

%%-----------------------------------------------------------------------------
-spec add_sjs_child(#csr{}, any(), any()) -> {tuple(), #csr{}}.

add_sjs_child(St, Sid, Conn) ->
    New = add_msg_stat(St, 'sjs_child'),
    Pars = [
            {sjs_sid, Sid},
            {sjs_conn, Conn},
            {no_local, true}, % FIXME: make it a var?
            {type, 'sjs'}
           ],
    add_child(New, Pars).

%%-----------------------------------------------------------------------------
%%
%% @doc creates child, stores its pid in state, checks for error
%% @todo decide about policy on error
%%
-spec add_child(#csr{}, list()) ->
                       {{ok, pid()}, #csr{}}
                           | {{ok, pid(), any()}, #csr{}}
                           | {{error, any()}, #csr{}}.

add_child(St, Ext_pars) ->
    Id = make_ref(),
    Pars = Ext_pars ++ [{id, Id},
                        {conn, St#csr.conn},
                        {exchange_base, (St#csr.rses)#rses.exchange_base}
                        | St#csr.child_config],
    mpln_p_debug:pr({?MODULE, "start child prepared", ?LINE, Id, Pars},
                    St#csr.debug, child, 4),
    Res = do_start_child(Id, Pars),
    mpln_p_debug:pr({?MODULE, "start child result", ?LINE, Id, Pars, Res},
                    St#csr.debug, child, 4),
    Type = proplists:get_value(type, Ext_pars),
    case Res of
        {ok, Pid} ->
            erpher_et:trace_me(45, ?MODULE, undefined, 'start_child_ok',
                {Pars, Pid}),
            New_st = add_child_list(St, Type, Pid, Id, Ext_pars),
            {Res, New_st};
        {ok, Pid, _Info} ->
            erpher_et:trace_me(45, ?MODULE, undefined, 'start_child_ok',
                {Pars, Pid}),
            New_st = add_child_list(St, Type, Pid, Id, Ext_pars),
            {Res, New_st};
        {error, Reason} ->
            erpher_et:trace_me(50, ?MODULE, undefined, 'start_child_error',
                {Pars, Reason}),
            mpln_p_debug:pr({?MODULE, "start child error", ?LINE, Reason},
                            St#csr.debug, child, 1),
            check_error(St, Reason)
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc 
%%
start_socketio(#csr{socketio_config=S} = C) ->
    Res = do_start_socketio(C, proplists:get_value(port, S)),
    mpln_p_debug:pr({?MODULE, socketio_start, ?LINE, Res},
                    C#csr.debug, run, 1),
    Res.

%%-----------------------------------------------------------------------------
do_start_socketio(_C, undefined) ->
    {error, port_undefined};

do_start_socketio(_C, Port) ->
    Mod = 'ecomet_socketio_handler',
    {ok, Pid} = socketio_listener:start([{http_port, Port},
                                         {default_http_handler, Mod}]),
    EventMgr = socketio_listener:event_manager(Pid),
    ok = gen_event:add_handler(EventMgr, Mod, []),
    {ok, {EventMgr, Pid, self()}}.

%%-----------------------------------------------------------------------------
%%
%% @doc prepare log if it is defined in config
%% @since 2011-10-14 14:14
%%
-spec prepare_log(#csr{}) -> ok.

prepare_log(#csr{log=undefined}) ->
    ok;
prepare_log(#csr{log=Log}) ->
    mpln_misc_log:prepare_log(Log).

%%-----------------------------------------------------------------------------
%%
%% @doc prepares all the necessary things (log, rabbit, yaws, etc)
%%
-spec prepare_all(#csr{}) -> #csr{}.

prepare_all(C) ->
    Crb = prepare_rabbit(C),
    prepare_part(Crb).

%%
%% @doc prepares almost all the necessary things, except rabbit
%%
-spec prepare_part(#csr{}) -> #csr{}.

prepare_part(#csr{log_stat_interval=T} = C) ->
    prepare_log(C),
    New = prepare_stat(C),
    %start_socketio(C),
    ecomet_sockjs_handler:start(C),
    Ref = erlang:send_after(?T, self(), periodic_check),
    Tref = erlang:send_after(T * 1000, self(), periodic_send_stat),
    New#csr{timer=Ref, timer_stat=Tref}.

%%-----------------------------------------------------------------------------
%%
%% @doc prepares rabbit connection
%%
-spec prepare_rabbit(#csr{}) -> #csr{}.

prepare_rabbit(C) ->
    Conn = ecomet_rb:start(C#csr.rses),
    C#csr{conn=Conn}.

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
    C#csr{stat=St}.

%%-----------------------------------------------------------------------------
%%
%% @doc tries to reconnect to rabbit in case of do_start_child returns noproc,
%% which means the connection to rabbit is closed.
%% @todo decide which policy is better - connection restart or terminate itself
%%
check_error(St, {{noproc, _Reason}, _Other}) ->
    mpln_p_debug:pr({?MODULE, "check_error", ?LINE}, St#csr.debug, run, 3),
    New = reconnect(St),
    mpln_p_debug:pr({?MODULE, "check_error new st", ?LINE, New}, St#csr.debug, run, 6),
    {{error, noproc}, New};
check_error(St, Other) ->
    mpln_p_debug:pr({?MODULE, "check_error other", ?LINE}, St#csr.debug, run, 3),
    {{error, Other}, St}.

%%-----------------------------------------------------------------------------
%%
%% @doc does reconnect to rabbit
%%
reconnect(St) ->
    ecomet_rb:teardown_conn(St#csr.conn),
    prepare_rabbit(St).

%%-----------------------------------------------------------------------------
%%
%% @doc adds child info into appropriate list - either web socket or long poll
%% in dependence of given child type.
%%
-spec add_child_list(#csr{}, 'sio' | 'sjs', pid(), reference(),
                     list()) -> #csr{}.

add_child_list(St, Type, Pid, Id, Pars) ->
    Id_web = proplists:get_value(id_web, Pars),
    Data = #chi{pid=Pid, id=Id, id_web=Id_web, start=now()},
    add_child_list2(St, Type, Data, Pars).

add_child_list2(#csr{sio_children=C} = St, 'sio', Data, Pars) ->
    Ev_mgr = proplists:get_value(sio_mgr, Pars),
    Client = proplists:get_value(sio_cli, Pars),
    Sid = proplists:get_value(sio_sid, Pars),
    New = Data#chi{sio_mgr=Ev_mgr, sio_cli=Client, sio_sid=Sid},
    St#csr{sio_children=[New | C]};

add_child_list2(#csr{sjs_children=C} = St, 'sjs', Data, Pars) ->
    Conn = proplists:get_value(sjs_conn, Pars),
    Sid = proplists:get_value(sjs_sid, Pars),
    New = Data#chi{sjs_conn=Conn, sjs_sid=Sid},
    St#csr{sjs_children=[New | C]}.

%%-----------------------------------------------------------------------------
add_msg_stat(#csr{stat=#stat{rabbit=Rb_stat} = Stat} = State, Tag) ->
    New_rb_stat = ecomet_stat:add_server_stat(Rb_stat, Tag),
    New_stat = Stat#stat{rabbit=New_rb_stat},
    State#csr{stat = New_stat}.

%%-----------------------------------------------------------------------------
%%
%% @doc deletes sockjs related process from a list of children and terminates
%% them
%%
del_sjs_pid2(St, Ref, Conn) ->
    % gives an exception when trying to close already closed session
    Res = (catch sockjs:close(3000, "conn. closed.", Conn)),
    mpln_p_debug:pr({?MODULE, 'del_sjs_pid2', ?LINE, Ref, Conn, Res},
                    St#csr.debug, run, 3),
    F = fun(#chi{sjs_sid=X}) ->
                X == Ref
        end,
    proceed_del_sjs_pid(St, F).

del_sjs_pid(St, _Pid, Ref) ->
    mpln_p_debug:pr({?MODULE, 'del_sjs_pid', ?LINE, Ref, _Pid},
                    St#csr.debug, run, 2),
    F = fun(#chi{id=Id}) ->
                Id == Ref
        end,
    proceed_del_sjs_pid(St, F).

-spec proceed_del_sjs_pid(#csr{}, fun()) -> #csr{}.

proceed_del_sjs_pid(#csr{sjs_children=L} = St, F) ->
    {Del, Cont} = lists:partition(F, L),
    mpln_p_debug:pr({?MODULE, 'proceed_del_sjs_pid', ?LINE, Del, Cont},
                    St#csr.debug, run, 5),
    terminate_sjs_children(St, Del),
    St#csr{sjs_children = Cont}.

%%-----------------------------------------------------------------------------
%%
%% @doc deletes and terminates socket-io related process from a list of children
%%
del_sio_pid(#csr{sio_children=L} = St, Pid) ->
    mpln_p_debug:pr({?MODULE, del_sio_pid, ?LINE, Pid},
                    St#csr.debug, run, 4),
    F = fun(#chi{sio_cli=C_pid}) ->
                C_pid == Pid
        end,
    {Del, Cont} = lists:partition(F, L),
    mpln_p_debug:pr({?MODULE, del_sio_pid, ?LINE, Del, Cont},
                    St#csr.debug, run, 5),
    terminate_sio_children(St, Del),
    St#csr{sio_children = Cont}.

%%-----------------------------------------------------------------------------
%%
%% @doc terminates sockjs or socket-io related process
%%
terminate_sjs_children(St, List) ->
    terminate_sio_children(St, List).

terminate_sio_children(St, List) ->
    F = fun(#chi{pid=Pid}) ->
                Info = process_info(Pid),
                mpln_p_debug:pr({?MODULE, terminate_sio_children, ?LINE, Info},
                                St#csr.debug, run, 5),
                ecomet_conn_server:stop(Pid)
        end,
    lists:foreach(F, List).

%%-----------------------------------------------------------------------------
%%
%% @doc does periodic tasks
%% @todo get rid of it
%%
periodic_check(#csr{timer=Ref} = St) ->
    mpln_p_debug:pr({?MODULE, periodic_check, ?LINE}, St#csr.debug, run, 6),
    mpln_misc_run:cancel_timer(Ref),
    Nref = erlang:send_after(?T, self(), periodic_check),
    St#csr{timer=Nref}.

%%-----------------------------------------------------------------------------
%%
%% @doc sends stats and prepares timer for the next sending
%%
periodic_send_stat(#csr{timer_stat=Ref, log_stat_interval=T} = St) ->
    mpln_p_debug:pr({?MODULE, periodic_send_stat, ?LINE}, St#csr.debug, run, 6),
    mpln_misc_run:cancel_timer(Ref),
    send_stat(St),
    Nref = erlang:send_after(T * 1000, self(), periodic_send_stat),
    St#csr{timer_stat=Nref}.

%%-----------------------------------------------------------------------------
%%
%% @doc sends stats to ejobman_stat
%%
send_stat(#csr{sio_children=Sio, sjs_children=Sjs}) ->
    Len1 = length(Sio),
    Len2 = length(Sjs),
    ejobman_stat:add('ecomet', 'children', ['socketio', Len1]),
    ejobman_stat:add('ecomet', 'children', ['sockjs', Len2]),
    ejobman_stat:add('ecomet', 'children', ['total', Len1 + Len2]).

%%-----------------------------------------------------------------------------
%%
%% @doc sends data to every sockjs child
%%
process_sjs_broadcast_msg(#csr{sjs_children=Ch} = St, Data) ->
    New = add_msg_stat(St, 'broadcast'),
    [ecomet_conn_server:data_from_server(Pid, Data) || #chi{pid=Pid} <- Ch],
    New.

%%-----------------------------------------------------------------------------
%%
%% @doc creates a handler process if it's not done yet, charges the process
%% to do the work
%%
process_sjs_msg(St, Sid, Conn, Data) ->
    mpln_p_debug:pr({?MODULE, 'process_sjs_msg', ?LINE, Sid, Conn, Data},
                    St#csr.debug, run, 4),
    case check_sjs_child(St, Sid, Conn) of
        {{ok, Pid}, St_c} ->
            ecomet_conn_server:data_from_sjs(Pid, Data),
            St_c;
        {{ok, Pid, _}, St_c} ->
            ecomet_conn_server:data_from_sjs(Pid, Data),
            St_c;
        {{error, _Reason}, _St_c} ->
            St
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc creates a handler process if it's not done yet, charges the process
%% to do the work
%%
process_sio_msg(St, _Client, Sid, Data) ->
    case check_sio_child(St, Sid) of
        {{ok, Pid}, St_c} ->
            ecomet_conn_server:data_from_sio(Pid, Data),
            St_c;
        {{ok, Pid, _}, St_c} ->
            ecomet_conn_server:data_from_sio(Pid, Data),
            St_c;
        {{error, _Reason}, _St_c} ->
            St
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc checks whether the sockjs child with given id is alive. Creates
%% the one if it's not.
%%
-spec check_sjs_child(#csr{}, any(), any()) ->
                            {{ok, pid()}, #csr{}}
                                | {{ok, pid(), any()}, #csr{}}
                                | {{error, any()}, #csr{}}.

check_sjs_child(#csr{sjs_children = Ch} = St, Sid, Conn) ->
    case is_sjs_child_alive(St, Ch, Sid) of
        {true, I} ->
            {{ok, I#chi.pid}, St};
        {false, _} ->
            add_sjs_child(St, Sid, Conn)
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc checks whether the socket-io child with given id is alive. Creates
%% the one if it's not.
%%
-spec check_sio_child(#csr{}, any()) ->
                            {{ok, pid()}, #csr{}}
                                | {{ok, pid(), any()}, #csr{}}
                                | {{error, any()}, #csr{}}.

check_sio_child(#csr{sio_children = Ch} = St, Sid) ->
    case is_sio_child_alive(St, Ch, Sid) of
        {true, I} ->
            {{ok, I#chi.pid}, St};
        {false, _} ->
            add_sio_child(St, undefined, undefined, undefined, Sid)
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc finds socket-io child with given client id and checks whether it's
%% alive
%%
is_sio_child_alive(St, List, Id) ->
    mpln_p_debug:pr({?MODULE, "is_sio_child_alive", ?LINE, List, Id},
                    St#csr.debug, run, 4),
    L2 = [X || X <- List, X#chi.sio_sid == Id],
    mpln_p_debug:pr({?MODULE, "is_sio_child_alive", ?LINE, L2, Id},
                    St#csr.debug, run, 4),
    case L2 of
        [I | _] ->
            {is_process_alive(I#chi.pid), I};
        _ ->
            {false, undefined}
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc finds sockjs child with given client id and checks whether it's
%% alive
%%
is_sjs_child_alive(St, List, Id) ->
    mpln_p_debug:pr({?MODULE, "is_sjs_child_alive", ?LINE, List, Id},
                    St#csr.debug, run, 4),
    L2 = [X || X <- List, X#chi.sjs_sid == Id],
    mpln_p_debug:pr({?MODULE, "is_sjs_child_alive", ?LINE, L2, Id},
                    St#csr.debug, run, 4),
    case L2 of
        [I | _] ->
            {is_process_alive(I#chi.pid), I};
        _ ->
            {false, undefined}
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc deletes a child from a list of children
%%
del_child_pid(St, Pid, 'sio', _Ref) ->
    del_sio_pid(St, Pid);

del_child_pid(St, Pid, 'sjs', Ref) ->
    del_sjs_pid(St, Pid, Ref).

%%-----------------------------------------------------------------------------
%%
%% @doc returns accumulated statistic as a list of tuples
%% {atom(), dictionary()}, where dictionary is a dict of {time, tag} -> amount
%%
prepare_stat_result(#csr{stat=Stat}, raw) ->
    [{wsock, Stat#stat.wsock}, {rabbit, Stat#stat.rabbit}];

%%
%% @doc returns number of running comet processes
%%
prepare_stat_result(#csr{sjs_children=Ch}, procs) ->
    length(Ch);

%%
%% @doc returns number of running comet processes and their memory
%% consumption. This does not include memory of sockjs and webserver
%% processes.
%%
prepare_stat_result(#csr{sjs_children=Ch}, procs_mem) ->
    Len = length(Ch),
    Pids = [X#chi.pid || X <- Ch],
    Sum = estat_misc:fetch_sum_pids_memory(Pids),
    {Len, Sum}.

%%-----------------------------------------------------------------------------
%%
%% @doc fetches config from updated environment and stores it in the state
%%
-spec process_reload_config(#csr{}) -> #csr{}.

process_reload_config(St) ->
    C = ecomet_conf:get_config(St),
    prepare_part(C).

%%-----------------------------------------------------------------------------
