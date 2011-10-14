%%%-----------------------------------------------------------------
%%% server to create servers for new websocket requests
%%%-----------------------------------------------------------------
-module(mcom_server).
-behaviour(gen_server).
-export([start/0, start_link/0, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([terminate/2, code_change/3]).
-export([add/0]).
-define(T, 1000).
-define(LOG, "/var/log/erpher/tws").

%-------------------------------------------------------------------
start() ->
    start_link().

%-------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%-------------------------------------------------------------------
stop() ->
    gen_server:call(?MODULE, stop).

%-------------------------------------------------------------------
init(_) ->
    prepare_log(),
    [application:start(X) || X <- [sasl, crypto, public_key, ssl]],
    start_yaws(),
    {ok, [], ?T}.

%-------------------------------------------------------------------
handle_call(restart, _From, St) ->
    New = restart_child(St),
    {reply, New, New, ?T};
handle_call(restart2, _From, St) ->
    New = restart_child(St, true),
    {reply, New, New, ?T};
handle_call(add, _From, St) ->
    {Res, New} = add_child(St),
    {reply, Res, New, ?T};
handle_call(status, _From, St) ->
    {reply, St, St, ?T};
handle_call(stop, _From, St) ->
    {stop, normal, ok, St};
handle_call(_N, _From, St) ->
    {reply, {error, unknown_request}, St, ?T}.

%-------------------------------------------------------------------
handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_, St) ->
    {noreply, St, ?T}.

%-------------------------------------------------------------------
terminate(_, _State) ->
    ok.

%-------------------------------------------------------------------
handle_info(_, State) ->
    {noreply, State, ?T}.

%-------------------------------------------------------------------
code_change(_Old_vsn, State, _Extra) ->
    {ok, State}.

%-------------------------------------------------------------------
do_start_child(Id) ->
    Ch_conf = [Id],
    StartFunc = {mcom_conn_server, start_link, [Ch_conf]},
    Child = {Id, StartFunc, temporary, 1000, worker, [mcom_conn_server]},
    supervisor:start_child(mcom_conn_sup, Child).

%-------------------------------------------------------------------
add_child(St) ->
    Id = make_ref(),
    Res = do_start_child(Id),
    error_logger:info_report({Id, Res}),
    case Res of
        {ok, Pid} ->
            {Res, [{Pid, Id} | St]};
        {ok, Pid, _Info} ->
            {Res, [{Pid, Id} | St]};
        {error, Reason} ->
            error_logger:info_report({error, Reason}),
            {error, St}
    end.

%-------------------------------------------------------------------
restart_child(St) ->
    restart_child(St, false).

%-------------------------------------------------------------------
restart_child(St, Flag) ->
    {Pid, Id} = get_rand_pid(St),
    P_info = process_info(Pid),
    error_logger:info_report({p_info, Pid, Id, P_info}),
    Res_t = supervisor:terminate_child(mcom_conn_sup, Id),
    error_logger:info_report({res_t, Res_t}),
    Res = start_del_spec(Flag, Id),
    Cleared = clear_pid(St, Id),
    case Res of
        {error, Reason} ->
            error_logger:info_report({error, Reason}),
            Cleared;
        {ok, Pid2} ->
            New = {Pid2, Id},
            [New | Cleared];
        {ok, Pid2, _} ->
            New = {Pid2, Id},
            [New | Cleared]
    end.

%-------------------------------------------------------------------
start_del_spec(true, Id) ->
    Res_d = supervisor:delete_child(mcom_conn_sup, Id),
    error_logger:info_report({res_d, Res_d}),
    Res = do_start_child(Id),
    error_logger:info_report({true, res, Res}),
    Res;
start_del_spec(false, Id) ->
    Res = supervisor:restart_child(mcom_conn_sup, Id),
    error_logger:info_report({false, res, Res}),
    Res.

%-------------------------------------------------------------------
get_rand_pid(St) ->
    Len = length(St),
    Idx = crypto:rand_uniform(0, Len),
    lists:nth(Idx+1, St).

%-------------------------------------------------------------------
clear_pid(St, Id0) ->
    F = fun ({_, Id}) when Id =:= Id0 ->
                false;
            (_) ->
                true
    end,
    lists:filter(F, St).

%-------------------------------------------------------------------
start_yaws() ->
    Docroot = "/var/www/01/www4",
    SconfList = y_cfg:sconf(Docroot),
    GconfList = y_cfg:gconf(),
    Id = "test_yaws",
    Res = yaws:start_embedded(Docroot, SconfList, GconfList, Id),
    error_logger:info_report(Res).

%-------------------------------------------------------------------
add() ->
    gen_server:call(?MODULE, add).

%-------------------------------------------------------------------
prepare_log() ->
    mpln_misc_log:prepare_log(?LOG).

%-------------------------------------------------------------------
