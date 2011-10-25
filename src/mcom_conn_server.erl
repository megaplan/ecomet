%%%----------------------------------------------------------------------------
%%% websocket connection server
%%%----------------------------------------------------------------------------
-module(mcom_conn_server).
-behaviour(gen_server).


-export([start/0, start_link/0, start_link/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([terminate/2, code_change/3]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include("mcom.hrl").
-include("rabbit_session.hrl").
-include_lib("amqp_client.hrl").

%------------------------------------------------------------------------------
start() ->
    start_link().

%------------------------------------------------------------------------------
start_link() ->
    start_link(none).

%------------------------------------------------------------------------------
start_link(Conf) ->
    gen_server:start_link(?MODULE, Conf, []).

%------------------------------------------------------------------------------
stop(Pid) ->
    gen_server:call(Pid, stop).

%------------------------------------------------------------------------------
init([List]) ->
    C = mcom_conf:get_child_config(List),
    New = prepare_all(C),
    {ok, New, ?T}.

%------------------------------------------------------------------------------
handle_call(stop, _From, St) ->
    {stop, normal, ok, St};
handle_call(status, _From, St) ->
    {reply, St, St, ?T};
handle_call(_N, _From, St) ->
    error_logger:info_report({unknown_call, ?MODULE, ?LINE, _N}),
    {reply, {error, unknown_request}, St, ?T}.

%------------------------------------------------------------------------------
handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_N, St) ->
    error_logger:info_report({unknown_cast, ?MODULE, ?LINE, _N}),
    {noreply, St, ?T}.

%------------------------------------------------------------------------------
terminate(_, _State) ->
    ok.

%------------------------------------------------------------------------------
handle_info(#'basic.consume_ok'{consumer_tag = Tag},
            #child{conn=#conn{consumer_tag = Tag, consumer=undefined}}=State) ->
    check_start_time(State);
handle_info(timeout, #child{conn=#conn{consumer=undefined}} = State) ->
    check_start_time(State);
handle_info(timeout, State) ->
    New = do_smth(State),
    {noreply, New, ?T};
handle_info({ok, Sock}, #child{sock=undefined} = State) ->
    Lname = inet:sockname(Sock),
    Rname = inet:peername(Sock),
    Opts = inet:getopts(Sock, [active, reuseaddr]),
    error_logger:info_report({?MODULE, ?LINE, socket_ok, Sock, Lname, Rname, Opts}),
    {noreply, State#child{sock=Sock}, ?T};
handle_info(_Other, #child{sock=undefined} = State) ->
    error_logger:info_report({?MODULE, ?LINE, socket_discard, _Other}),
    {stop, normal, State};
handle_info({tcp, Sock, Data} = Msg, #child{sock = Sock} = State) ->
    error_logger:info_report({tcp, ?MODULE, ?LINE, Msg}),
    New = mcom_handler_ws:send_msg_q(State, Sock, Data),
    {noreply, New, ?T};
handle_info({tcp_closed, Sock} = Msg, #child{sock = Sock} = State) ->
    error_logger:info_report({tcp_closed, ?MODULE, ?LINE, Msg}),
    {stop, normal, State};
handle_info(_N, State) ->
    error_logger:info_report({unknown_info, ?MODULE, ?LINE, _N}),
    {noreply, State, ?T}.

%------------------------------------------------------------------------------
code_change(_Old_vsn, State, _Extra) ->
    {ok, State}.

%------------------------------------------------------------------------------
-spec prepare_all(#child{}) -> #child{}.

prepare_all(C) ->
    prepare_rabbit(C).

%------------------------------------------------------------------------------
-spec prepare_rabbit(#child{}) -> #child{}.

prepare_rabbit(#child{conn=Conn, event=Event} = C) ->
    Consumer_tag = mcom_rb:prepare_queue(Conn, Event),
    C#child{conn=Conn#conn{consumer_tag=Consumer_tag}}.

%------------------------------------------------------------------------------
check_start_time(#child{start_time = T1} = State) ->
    T2 = now(),
    Diff = timer:now_diff(T2, T1),
    if  Diff > ?SETUP_CONSUMER_TIMEOUT ->
            {stop, consumer_setup_timeout, State};
        true ->
            New = State#child{conn=(State#child.conn)#conn{consumer=ok}},
            {noreply, New, ?T}
    end.

%------------------------------------------------------------------------------
do_smth(State) ->
    State.

%------------------------------------------------------------------------------
