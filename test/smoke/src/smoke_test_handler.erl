%%%
%%% smoke_test_handler: gen_server that just starts a bunch of tests
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
%%% @since 2012-02-06 18:30
%%% @license MIT
%%% @doc a gen_server that starts tests upon a request
%%%

-module(smoke_test_handler).
-behaviour(gen_server).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([start/0, start_link/0, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([terminate/2, code_change/3]).

-export([get_stat/0, st/0, st/1, send_stat/5, reset_stat/0]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("child.hrl").
-include("smoke_test.hrl").

%%%----------------------------------------------------------------------------
%%% gen_server callbacks
%%%----------------------------------------------------------------------------
init(_) ->
    St = prepare_all(),
    process_flag(trap_exit, true), % to log stats
    mpln_p_debug:pr({?MODULE, 'init done', ?LINE}, St#sth.debug, run, 1),
    {ok, St}.
%%-----------------------------------------------------------------------------
%%
%% Handling call messages
%% @since 2012-02-06 18:30
%%
-spec handle_call(any(), any(), #sth{}) ->
    {reply , any(), #sth{}}
    | {stop, normal, ok, #sth{}}.

handle_call(run_smoke_test, _From, St) ->
    mpln_p_debug:pr({?MODULE, 'run_smoke_test', ?LINE}, St#sth.debug, run, 2),
    New = do_smoke_test(St),
    {reply, ok, New};

handle_call({run_smoke_test, List}, _From, St) ->
    mpln_p_debug:pr({?MODULE, 'run_smoke_test par', ?LINE, List},
                    St#sth.debug, run, 2),
    New = do_smoke_test(St, List),
    {reply, ok, New};

handle_call(stop, _From, St) ->
    {stop, normal, ok, St};

handle_call(status, _From, St) ->
    {reply, St, St};

handle_call(get_stat, _From, St) ->
    Res = get_result_stat(St),
    {reply, Res, St};

handle_call(_N, _From, St) ->
    mpln_p_debug:pr({?MODULE, 'other', ?LINE, _N}, St#sth.debug, run, 2),
    {reply, {error, unknown_request}, St}.

%%-----------------------------------------------------------------------------
%%
%% Handling cast messages
%% @since 2012-02-06 18:30
%%
-spec handle_cast(any(), #sth{}) -> any().

handle_cast(stop, St) ->
    {stop, normal, St};

handle_cast(reset_stat, St) ->
    New = St#sth{stat=#stat{}},
    {noreply, New};

handle_cast({smoke_test_result, Count, Ok, Err, Sum, Sq}, St) ->
    mpln_p_debug:pr({?MODULE, 'cast result', ?LINE, Count, Ok, Err, Sum, Sq},
                    St#sth.debug, run, 2),
    New = store_test_result(St, Count, Ok, Err, Sum, Sq),
    {noreply, New};

handle_cast(_N, St) ->
    mpln_p_debug:pr({?MODULE, 'cast other', ?LINE, _N}, St#sth.debug, run, 2),
    {noreply, St}.

%%-----------------------------------------------------------------------------
%%
%% @doc Note: it won't be called unless trap_exit is set
%%
terminate(_, State) ->
    log_stats(State),
    mpln_p_debug:pr({?MODULE, 'terminate', ?LINE}, State#sth.debug, run, 1),
    ok.

%%-----------------------------------------------------------------------------
%%
%% Handling all non call/cast messages
%% @since 2012-02-06 18:30
%%
-spec handle_info(any(), #sth{}) -> {noreply, #sth{}}.

handle_info({'DOWN', Mref, _, _Oid, _Info} = Msg, St) ->
    mpln_p_debug:pr({?MODULE, 'info_down', ?LINE, Msg}, St#sth.debug, run, 2),
    New = clean_child(St, Mref),
    log_result(New),
    {noreply, New};

handle_info(_Req, State) ->
    mpln_p_debug:pr({?MODULE, 'info_other', ?LINE, _Req},
                    State#sth.debug, run, 2),
    {noreply, State}.

%%-----------------------------------------------------------------------------
code_change(_Old_vsn, State, _Extra) ->
    {ok, State}.

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
-spec start() -> any().
%%
%% @doc starts handler gen_server
%% @since 2012-02-06 18:30
%%
start() ->
    start_link().

%%-----------------------------------------------------------------------------
-spec start_link() -> any().
%%
%% @doc starts handler gen_server with given config
%% @since 2012-02-06 18:30
%%
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%-----------------------------------------------------------------------------
-spec stop() -> any().
%%
%% @doc stops handler gen_server
%% @since 2012-02-06 18:30
%%
stop() ->
    gen_server:call(?MODULE, stop).

%%-----------------------------------------------------------------------------
%%
%% @doc asks smoke_test_handler for state of queues
%%
-spec get_stat() -> {tuple(), tuple()}.

get_stat() ->
    gen_server:call(?MODULE, get_stat).

%%-----------------------------------------------------------------------------
%%
%% @doc runs smoke_test
%%
-spec st() -> string().

st() ->
    gen_server:call(?MODULE, run_smoke_test).

-spec st([{atom(), any()}]) -> string().

st(List) ->
    gen_server:call(?MODULE, {run_smoke_test, List}).

%%-----------------------------------------------------------------------------
%%
%% @doc sends one child statistic to gen_server
%%
-spec send_stat(non_neg_integer(), non_neg_integer(), non_neg_integer(),
                float(), float()) -> ok.

send_stat(Count, Ok, Err, Sum, Sq) ->
    gen_server:cast(?MODULE, {smoke_test_result, Count, Ok, Err, Sum, Sq}).

%%-----------------------------------------------------------------------------
%%
%% @doc resets child statistic
%%
-spec reset_stat() -> ok.

reset_stat() ->
    gen_server:cast(?MODULE, reset_stat).

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
%%
%% @doc prepares necessary things
%%
-spec prepare_all() -> #sth{}.

prepare_all() ->
    [application:start(X) || X <- [sasl, public_key, crypto, ssl, inets]],
    L = application:get_all_env('smoke_test'),
    Log = proplists:get_value(log, L),
    prepare_log(Log),
    #sth{
          debug = proplists:get_value(debug, L, []),
          host = proplists:get_value(host, L),
          url = proplists:get_value(url, L),
          serv_tag = proplists:get_value(serv_tag, L),
          hz = proplists:get_value(hz, L, 1),
          count = proplists:get_value(count, L, 500),
          timeout = proplists:get_value(timeout, L, 10000),
          job_timeout = proplists:get_value(job_timeout, L, 120000),
          heartbeat_timeout = proplists:get_value(heartbeat_timeout, L, 25000),
          seconds = proplists:get_value(seconds, L, 20)
        }.

%%-----------------------------------------------------------------------------
%%
%% @doc prepare log file if it is defined
%%
prepare_log(undefined) ->
    ok;

prepare_log(Log) ->
    mpln_misc_log:prepare_log(Log).

%%-----------------------------------------------------------------------------
%%
%% @doc spawns children to do test using provided parameters
%%
-spec do_smoke_test(#sth{}, [{atom(), any()}]) -> #sth{}.

do_smoke_test(St, L) ->
    New = St#sth{
            count = proplists:get_value(count, L, St#sth.count),
            timeout = proplists:get_value(timeout, L, St#sth.timeout),
            job_timeout = proplists:get_value(job_timeout, L,
                                              St#sth.job_timeout),
            heartbeat_timeout = proplists:get_value(heartbeat_timeout, L,
                                                    St#sth.heartbeat_timeout),
            host = proplists:get_value(host, L, St#sth.host),
            url = proplists:get_value(url, L, St#sth.url),
            serv_tag = proplists:get_value(serv_tag, L, St#sth.serv_tag),
            hz = proplists:get_value(hz, L, St#sth.hz),
            seconds = proplists:get_value(seconds, L, St#sth.seconds)
           },
    #sth{children = Ch} = do_smoke_test(New),
    St#sth{children = Ch}.

%%
%% @doc spawns children to do test using parameters configured in app file
%%
-spec do_smoke_test(#sth{}) -> #sth{}.

do_smoke_test(#sth{children = Ch} = St) ->
    F = fun(_, Acc) ->
                prepare_one_child(St, Acc)
        end,
    Res = lists:foldl(F, [], lists:duplicate(St#sth.count, true)),
    St#sth{children = Res ++ Ch}.

%%-----------------------------------------------------------------------------
%%
%% @doc spawns one child
%%
-spec prepare_one_child(#sth{}, [#chi{}]) -> [#chi{}].

prepare_one_child(St, Ch) ->
    Ref = make_ref(),
    Params = [
              {id, Ref},
              {host, St#sth.host},
              {url, St#sth.url},
              {serv_tag, St#sth.serv_tag},
              {debug, St#sth.debug},
              {hz, St#sth.hz},
              {timeout, St#sth.timeout},
              {heartbeat_timeout, St#sth.heartbeat_timeout},
              {job_timeout, St#sth.job_timeout},
              {seconds, St#sth.seconds}
             ],
    smoke_test_misc:do_one_child(St#sth.debug, smoke_test_child_supervisor,
                                 Ch, Params).

%%-----------------------------------------------------------------------------
%%
%% @doc cleans terminated child info away from a list of children
%%
-spec clean_child(#sth{}, reference()) -> #sth{}.

clean_child(#sth{children = Ch} = St, Mref) ->
    F = fun(#chi{mon=X}) ->
                X == Mref
        end,
    {_Done, Cont} = lists:partition(F, Ch),
    mpln_p_debug:pr({?MODULE, 'clean_child', ?LINE, _Done, Cont},
                    St#sth.debug, run, 4),
    St#sth{children=Cont}.

%%-----------------------------------------------------------------------------
%%
%% @doc stores result of test into the state
%%
store_test_result(#sth{stat=Stat} = St, Count, Ok, Err, Sum, Sq) ->
    #stat{count=Count0, count_ok=Ok0, count_error=Err0,
          sum=Sum0, sum_sq=Sq0} = Stat,
    Nstat = Stat#stat{count=Count0+Count, count_ok=Ok0+Ok,
                      count_error=Err0+Err,
                      sum=Sum0+Sum, sum_sq=Sq0+Sq},
    St#sth{stat=Nstat}.

%%-----------------------------------------------------------------------------
%%
%% @doc return the accumulated statistic for jobs
%%
get_result_stat(#sth{stat=Stat}) ->
    #stat{count=Count, count_ok=Ok, count_error=Err, sum=Sum, sum_sq=Sq} = Stat,
    {Avg, Dev_ub, Dev_b} =
        if Count > 1 ->
                Avg0 = Sum / Count,
                % unbiased
                Var_ub = ((Sq / Count) - Avg0 * Avg0) * Count / (Count-1),
                % biased
                Var_b = (Sq / Count) - Avg0 * Avg0,
                Dev_ub0 = math:sqrt(Var_ub),
                Dev_b0 = math:sqrt(Var_b),
                {Avg0, Dev_ub0, Dev_b0};
           Count > 0 ->
                Avg0 = Sum / Count,
                Var_b = (Sq / Count) - Avg0 * Avg0,
                Dev_b0 = math:sqrt(Var_b),
                {Avg0, undefined, Dev_b0};
           true ->
                {undefined, undefined, undefined}
        end,
    {{Count, Ok, Err, Sum, Sq}, {Avg, Dev_ub, Dev_b}}.

%%-----------------------------------------------------------------------------
%%
%% @doc write statistic to log
%%
log_stats(#sth{stat=Stat} = State) ->
    #stat{count=Count, count_ok=Ok, count_error=Err, sum=Sum, sum_sq=Sq} = Stat,
    mpln_p_debug:pr({?MODULE, 'log_stats', ?LINE, 'src',
                     Count, Ok, Err, Sum, Sq},
                    State#sth.debug, run, 1),
    Res = get_result_stat(State),
    mpln_p_debug:pr({?MODULE, 'log_stats', ?LINE, 'res', Res},
                    State#sth.debug, run, 1).

%%-----------------------------------------------------------------------------
%%
%% @doc log resulting statistic when there are no more children
%%
log_result(#sth{children=[]} = St) ->
    log_stats(St);

log_result(_) ->
    ok.

%%-----------------------------------------------------------------------------
