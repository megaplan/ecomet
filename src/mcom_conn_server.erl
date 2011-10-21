%%%-----------------------------------------------------------------
%%% websocket connection server
%%%-----------------------------------------------------------------
-module(mcom_conn_server).
-behaviour(gen_server).
-export([start/0, start_link/0, start_link/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([terminate/2, code_change/3]).
-define(T, 1000).

%-------------------------------------------------------------------
start() ->
    start_link().

%-------------------------------------------------------------------
start_link() ->
    start_link(none).

%-------------------------------------------------------------------
start_link(Conf) ->
    gen_server:start_link(?MODULE, Conf, []).

%-------------------------------------------------------------------
stop(Pid) ->
    gen_server:call(Pid, stop).

%-------------------------------------------------------------------
init([List]) ->
    C = mcom_config:get_child_config(List),
    {ok, C, ?T}.

%-------------------------------------------------------------------
handle_call(stop, _From, St) ->
    {stop, normal, ok, St};
handle_call(status, _From, St) ->
    {reply, St, St, ?T};
handle_call(_N, _From, St) ->
    error_logger:info_report({unknown_call, ?MODULE, ?LINE, _N}),
    {reply, {error, unknown_request}, St, ?T}.

%-------------------------------------------------------------------
handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_N, St) ->
    error_logger:info_report({unknown_cast, ?MODULE, ?LINE, _N}),
    {noreply, St, ?T}.

%-------------------------------------------------------------------
terminate(_, _State) ->
    ok.

%-------------------------------------------------------------------
handle_info(timeout, State) ->
    {noreply, State, ?T};
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
    Payload = yaws_api:websocket_unframe_data(Data),
    error_logger:info_report({tcp_payload, ?MODULE, ?LINE, Payload}),
    L = binary_to_list(Payload),
    New = lists:reverse(L),
    yaws_api:websocket_send(Sock, New),
    yaws_api:websocket_setopts(Sock, [{active, once}]),
    {noreply, State, ?T};
handle_info({tcp_closed, Sock} = Msg, #child{sock = Sock} = State) ->
    error_logger:info_report({tcp_closed, ?MODULE, ?LINE, Msg}),
    {stop, normal, State};
handle_info(_N, State) ->
    error_logger:info_report({unknown_info, ?MODULE, ?LINE, _N}),
    {noreply, State, ?T}.

%-------------------------------------------------------------------
code_change(_Old_vsn, State, _Extra) ->
    {ok, State}.

%-------------------------------------------------------------------
