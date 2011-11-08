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
%%% @doc server to create children to serve new websocket requests. It connects
%%% to rabbit and creates children with connection provided.
%%%

-module(ecomet_server).
-behaviour(gen_server).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([start/0, start_link/0, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([terminate/2, code_change/3]).
-export([add_ws/1, add_ws/2, add_lp/3, add_lp/4]).
-export([add_rabbit_inc_own_stat/0, add_rabbit_inc_other_stat/0]).
-export([lp_get/3, lp_post/4]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include("ecomet.hrl").
-include("ecomet_stat.hrl").

%%%----------------------------------------------------------------------------
%%% gen_server callbacks
%%%----------------------------------------------------------------------------

init(_) ->
    C = ecomet_conf:get_config(),
    New = prepare_all(C),
    [application:start(X) || X <- [sasl, crypto, public_key, ssl]], % FIXME
    mpln_p_debug:pr({'init done', ?MODULE, ?LINE}, New#csr.debug, run, 1),
    {ok, New, ?T}.

%%-----------------------------------------------------------------------------
handle_call({post_lp_data, Event, No_local, Id, Data}, From, St) ->
    mpln_p_debug:pr({?MODULE, 'post_lp_data', ?LINE, Id}, St#csr.debug, run, 2),
    {Res, New} = process_lp_post(St, From, Event, No_local, Id, Data),
    {noreply, New, ?T};
handle_call({get_lp_data, Event, No_local, Id}, From, St) ->
    mpln_p_debug:pr({?MODULE, 'get_lp_data', ?LINE, Id}, St#csr.debug, run, 2),
    {Res, New} = process_lp_req(St, From, Event, No_local, Id),
    {noreply, New, ?T};
handle_call({add_lp, Sock, Event, No_local, Id}, _From, St) ->
    mpln_p_debug:pr({?MODULE, 'add_lp_child', ?LINE, Id}, St#csr.debug, run, 2),
    {Res, New} = check_lp_child(St, Sock, Event, No_local, Id),
    {reply, Res, New, ?T};
handle_call({add_ws, Event, No_local}, _From, St) ->
    mpln_p_debug:pr({?MODULE, 'add_ws_child', ?LINE}, St#csr.debug, run, 2),
    {Res, New} = add_ws_child(St, Event, No_local),
    {reply, Res, New, ?T};
handle_call(status, _From, St) ->
    {reply, St, St, ?T};
handle_call(stop, _From, St) ->
    {stop, normal, ok, St};
handle_call(_N, _From, St) ->
    {reply, {error, unknown_request}, St, ?T}.

%%-----------------------------------------------------------------------------
handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(add_rabbit_inc_other_stat, St) ->
    New = add_msg_stat(St, inc_other),
    {noreply, New, ?T};
handle_cast(add_rabbit_inc_own_stat, St) ->
    New = add_msg_stat(St, inc_own),
    {noreply, New, ?T};
handle_cast(_, St) ->
    {noreply, St, ?T}.

%%-----------------------------------------------------------------------------
terminate(_, _State) ->
    yaws:stop(),
    ok.

%%-----------------------------------------------------------------------------
handle_info(_, State) ->
    {noreply, State, ?T}.

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
%% @doc creates a websocket child with 'no local' mode (amqp messages from
%% the child should not return to this child).
%% @since 2011-10-26 14:14
%%
-spec add_ws(binary()) -> ok.

add_ws(Event) ->
    add_ws(Event, true).

%%-----------------------------------------------------------------------------
%%
%% @doc creates a websocket child with respect to 'no local' mode
%% @since 2011-10-26 14:14
%%
-spec add_ws(binary(), boolean()) -> ok.

add_ws(Event, true) ->
    gen_server:call(?MODULE, {add_ws, Event, true});
add_ws(Event, _) ->
    gen_server:call(?MODULE, {add_ws, Event, false}).

%%-----------------------------------------------------------------------------
%%
%% @doc creates a long-polling child with 'no local' mode
%% (amqp messages from the child should not return to this child).
%% @since 2011-10-26 14:14
%%
-spec add_lp(any(), binary(), non_neg_integer()) -> ok.

add_lp(Sock, Event, Id) ->
    add_lp(Sock, Event, true, Id).

%%-----------------------------------------------------------------------------
%%
%% @doc creates a long-polling child with respect to 'no local' mode
%% @since 2011-10-26 14:14
%%
-spec add_lp(any(), binary(), boolean(), non_neg_integer()) -> ok.

add_lp(Sock, Event, true, Id) ->
    gen_server:call(?MODULE, {add_lp, Sock, Event, true, Id});
add_lp(Sock, Event, _, Id) ->
    gen_server:call(?MODULE, {add_lp, Sock, Event, false, Id}).

%%-----------------------------------------------------------------------------
%%
%% @doc gets data for long poll client, creating a handler process if
%% necessary that will handle a session for the given id.
%% @since 2011-11-03 12:26
%%
-spec lp_get(any(), boolean(), non_neg_integer()) -> {ok, binary()}
                                                              | {error, any()}.

lp_get(Event, true, Id) ->
    gen_server:call(?MODULE, {get_lp_data, Event, true, Id}, infinity);
lp_get(Event, _, Id) ->
    gen_server:call(?MODULE, {get_lp_data, Event, false, Id}, infinity).

%%-----------------------------------------------------------------------------
%%
%% @doc gets data for long poll client, creating a handler process if
%% necessary that will handle a session for the given id.
%% @since 2011-11-03 12:26
%%
-spec lp_post(any(), boolean(), non_neg_integer(), binary()) -> {ok, binary()}
                                                              | {error, any()}.

lp_post(Event, true, Id, Data) ->
    gen_server:call(?MODULE, {post_lp_data, Event, true, Id, Data}, infinity);
lp_post(Event, _, Id, Data) ->
    gen_server:call(?MODULE, {post_lp_data, Event, false, Id, Data}, infinity).

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
add_lp_child(St, Sock, Event, No_local, Id) ->
    add_child(St, Sock, Event, No_local, 'lp', Id).
    
%%-----------------------------------------------------------------------------
add_ws_child(St, Event, No_local) ->
    add_child(St, undefined, Event, No_local, 'ws', undefined).
    
%%-----------------------------------------------------------------------------
%%
%% @doc creates child, stores its pid in state, checks for error
%%
-spec add_child(#csr{}, any(), any(), boolean(), 'ws' | 'lp',
                undefined | non_neg_integer()) ->
                       {{ok, pid()}, #csr{}}
                           | {{ok, pid(), any()}, #csr{}}
                           | {error, #csr{}}.

add_child(St, Sock, Event, No_local, Type, Id_web) ->
    Id = make_ref(),
    Pars = [{id, Id},
            {id_web, Id_web},
            {event, Event},
            {no_local, No_local},
            {conn, St#csr.conn},
            {lp_sock, Sock},
            {type, Type}
            | St#csr.child_config],
    Res = do_start_child(Id, Pars),
    mpln_p_debug:pr({?MODULE, "start child result", ?LINE, Id, Pars, Res},
                    St#csr.debug, child, 4),
    case Res of
        {ok, Pid} ->
            New_st = add_child_list(St, Type, Pid, Id, Id_web),
            {Res, New_st};
        {ok, Pid, _Info} ->
            New_st = add_child_list(St, Type, Pid, Id, Id_web),
            {Res, New_st};
        {error, Reason} ->
            mpln_p_debug:pr({?MODULE, "start child error", ?LINE, Reason},
                            St#csr.debug, child, 1),
            check_error(St, Reason)
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc gets config for yaws and starts embedded yaws server
%%
start_yaws(C) ->
    Y = C#csr.yaws_config,
    Docroot = proplists:get_value(docroot, Y, ""),
    SconfList = proplists:get_value(sconf, Y, []),
    GconfList = proplists:get_value(gconf, Y, []),
    Id = proplists:get_value(id, Y, "test_yaws_stub"),
    mpln_p_debug:pr({?MODULE, start_yaws, ?LINE, Y,
                     Docroot, SconfList, GconfList, Id}, C#csr.debug, run, 4),
    Res = yaws:start_embedded(Docroot, SconfList, GconfList, Id),
    mpln_p_debug:pr({?MODULE, start_yaws, ?LINE, Res}, C#csr.debug, run, 3).

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
    prepare_log(C),
    Cst = prepare_stat(C),
    New = prepare_rabbit(Cst),
    start_yaws(C),
    New.

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
    mpln_p_debug:pr({?MODULE, "check_error", ?LINE}, St#csr.debug, run, 2),
    New = reconnect(St),
    mpln_p_debug:pr({?MODULE, "check_error new st", ?LINE, New}, St#csr.debug, run, 2),
    {error, New};
check_error(St, _Other) ->
    mpln_p_debug:pr({?MODULE, "check_error other", ?LINE}, St#csr.debug, run, 2),
    {error, St}.

%%-----------------------------------------------------------------------------
%%
%% @doc does reconnect to rabbit
%%
reconnect(St) ->
    ecomet_rb:teardown_conn(St#csr.conn),
    prepare_rabbit(St).

%%-----------------------------------------------------------------------------
%%
%% @doc checks whether the child with given id is alive. If yes, then
%% charges it to do some work, otherwise creates the one
%%
-spec check_lp_child(#csr{}, any(), binary(), boolean(), non_neg_integer()) ->
                            {{ok, pid()}, #csr{}}
                                | {{ok, pid(), any()}, #csr{}}
                                | {error, #csr{}}.

check_lp_child(#csr{lp_children = Ch} = St, Sock, Event, No_local, Id) ->
    case is_child_alive(St, Ch, Id) of
        {true, I} ->
            charge_child(St, I#chi.pid);
        {false, _} ->
            add_lp_child(St, Sock, Event, No_local, Id)
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc finds child with given id and checks whether it's alive
%%
is_child_alive(St, List, Id) ->
    mpln_p_debug:pr({?MODULE, "is_child_alive", ?LINE, List, Id},
                    St#csr.debug, run, 4),
    L2 = [X || X <- List, X#chi.id_web == Id],
    mpln_p_debug:pr({?MODULE, "is_child_alive", ?LINE, L2, Id},
                    St#csr.debug, run, 4),
    case L2 of
        [I | _] ->
            {is_process_alive(I#chi.pid), I};
        _ ->
            {false, undefined}
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc child just waits for incoming messages from amqp. All we need
%% here is to return its pid.
%%
-spec charge_child(#csr{}, pid()) -> {{ok, pid()}, #csr{}}.

charge_child(St, Pid) ->
    mpln_p_debug:pr({?MODULE, "charge child", ?LINE, Pid},
                    St#csr.debug, child, 4),
    {{ok, Pid}, St}.

%%-----------------------------------------------------------------------------
%%
%% @doc adds child info into appropriate list - either web socket or long poll
%% in dependence of given child type.
%%
add_child_list(St, Type, Pid, Id, Id_web) ->
    Data = #chi{pid=Pid, id=Id, id_web=Id_web, start=now()},
    add_child_list2(St, Type, Data).

add_child_list2(#csr{ws_children=C} = St, 'ws', Data) ->
    St#csr{ws_children=[Data | C]};
add_child_list2(#csr{lp_children=C} = St, 'lp', Data) ->
    St#csr{lp_children=[Data | C]}.

%%-----------------------------------------------------------------------------
%%
%% @doc creates a handler process if it's not done yet, charges the process
%% to do the work
%%
-spec process_lp_req(#csr{}, any(), any(), boolean(), non_neg_integer()) -> {
                      {ok, binary()} | {error, any()},
                      #csr{}
                     }.

process_lp_req(St, From, Event, No_local, Id) ->
    case check_lp_child(St, undefined, Event, No_local, Id) of
        {{ok, Pid}, St_c} ->
            Res = ecomet_conn_server:get_lp_data(Pid, From),
            {Res, St_c};
        {{ok, Pid, _Info}, St_c} ->
            Res = ecomet_conn_server:get_lp_data(Pid, From),
            {Res, St_c};
        {error, _Reason} = Res ->
            {Res, St}
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc creates a handler process if it's not done yet, charges the process
%% to handle the post request
%%
-spec process_lp_post(#csr{}, any(), any(), boolean(),  non_neg_integer(),
                      binary()) ->
                             {
                       {ok, binary()} | {error, any()},
                       #csr{}
                      }.

process_lp_post(St, From, Event, No_local, Id, Data) ->
    case check_lp_child(St, undefined, Event, No_local, Id) of
        {{ok, Pid}, St_c} ->
            Res = ecomet_conn_server:post_lp_data(Pid, From, Data),
            {Res, St_c};
        {{ok, Pid, _Info}, St_c} ->
            Res = ecomet_conn_server:post_lp_data(Pid, From, Data),
            {Res, St_c};
        {error, _Reason} = Res ->
            {Res, St}
    end.

%%-----------------------------------------------------------------------------
add_msg_stat(#csr{stat=#stat{rabbit=Rb_stat} = Stat} = State, Tag) ->
    New_rb_stat = ecomet_stat:add_server_stat(Rb_stat, Tag),
    New_stat = Stat#stat{rabbit=New_rb_stat},
    State#csr{stat = New_stat}.

%%-----------------------------------------------------------------------------
