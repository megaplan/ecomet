%%%
%%% smoke_test_child: dynamically added worker
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
%%% @since 2012-02-07 14:42
%%% @license MIT
%%% @doc dynamically added worker that does the real thing.
%%%

-module(smoke_test_child).
-behaviour(gen_server).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------
-export([start/0, start_link/0, start_link/1, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([terminate/2, code_change/3]).
-export([
         job_result/4
        ]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("child.hrl").
-include("smoke_test.hrl").

-define(TC, 1).
-define(BASE_LEN, 6).

%%%----------------------------------------------------------------------------
%%% gen_server callbacks
%%%----------------------------------------------------------------------------
init(Params) ->
    C = prepare_all(Params),
    process_flag(trap_exit, true), % to send stats
    mpln_p_debug:pr({?MODULE, 'init done', ?LINE, C#child.id, self()},
        C#child.debug, run, 2),
    {ok, C}.

%%-----------------------------------------------------------------------------
%%
%% Handling call messages
%% @since 2012-02-07 14:42
%%
-spec handle_call(any(), any(), #child{}) ->
                         {stop, normal, ok, #child{}}
                             | {reply, any(), #child{}}.

handle_call(stop, _From, St) ->
    {stop, normal, ok, St};

handle_call(status, _From, St) ->
    {reply, St, St};

handle_call(_N, _From, St) ->
    {reply, {error, unknown_request}, St}.

%%-----------------------------------------------------------------------------
%%
%% Handling cast messages
%% @since 2012-02-07 14:42
%%
-spec handle_cast(any(), #child{}) -> {stop, normal, #child{}}
                                          | {noreply, #child{}}.

handle_cast(stop, St) ->
    {stop, normal, St};

handle_cast({job_result, Id, Status, Dur}, St) ->
    New = update_job_result(St, Id, Status, Dur),
    {noreply, New};

handle_cast(_, St) ->
    {noreply, St}.

%%-----------------------------------------------------------------------------
terminate(_, #child{id=Id} = State) ->
    send_stat(State),
    mpln_p_debug:pr({?MODULE, terminate, ?LINE, Id, self()},
        State#child.debug, run, 2),
    ok.

%%-----------------------------------------------------------------------------
%%
%% Handling all non call/cast messages
%%
-spec handle_info(any(), #child{}) -> {noreply, #child{}}.

handle_info(last_job_timeout, #child{id=Id} = St) ->
    mpln_p_debug:pr({?MODULE, 'info last_job_timeout', ?LINE, Id},
                    St#child.debug, run, 3),
    % we waited 1000/Hz + Timeout. All the jobs must be terminated by now.
    {stop, normal, St};

handle_info({job_timeout, Jid}, #child{id=Id} = State) ->
    mpln_p_debug:pr({?MODULE, 'info job_timeout', ?LINE, Id},
                    State#child.debug, run, 6),
    New = stop_job(State, Jid),
    {noreply, New};

handle_info(periodic_check, #child{id=Id} = State) ->
    mpln_p_debug:pr({?MODULE, 'info periodic_check', ?LINE, Id},
                    State#child.debug, run, 6),
    New = periodic_check(State),
    {noreply, New};

handle_info({'DOWN', Mref, _, Obj, _}, #child{id=Id} = St) ->
    mpln_p_debug:pr({?MODULE, 'info down', ?LINE, Id, self(), Mref, Obj},
                    St#child.debug, run, 2),
    New = job_done(St, Mref),
    {noreply, New};

handle_info(_Req, State) ->
    mpln_p_debug:pr({?MODULE, other, ?LINE, _Req, State#child.id, self()},
        State#child.debug, run, 2),
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
    start_link([]).

start_link(Params) ->
    gen_server:start_link(?MODULE, Params, []).

%%-----------------------------------------------------------------------------
stop() ->
    gen_server:call(?MODULE, stop).

%%-----------------------------------------------------------------------------
%%
%% @doc send job result
%% @since 2012-03-07 17:58
%%
-spec job_result(pid(), reference(), ok | error, non_neg_integer()) -> ok.

job_result(Pid, Id, Status, Dur) ->
    gen_server:cast(Pid, {job_result, Id, Status, Dur}).

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
%%
%% @doc prepares necessary things
%%
-spec prepare_all(list()) -> #child{}.

prepare_all(L) ->
    Hz = proplists:get_value(hz, L),
    Seconds = proplists:get_value(seconds, L),
    Cnt = Seconds * Hz,
    Bstr = base64:encode(crypto:rand_bytes(?BASE_LEN)),
    Base_bin = binary:replace(Bstr, [<<"=">>, <<"/">>], <<"z">>, [global]),
    Base = binary_to_list(Base_bin),
    #child{
          serv_tag = proplists:get_value(serv_tag, L),
          ses_sn = 0,
          ses_base = Base,
          id = proplists:get_value(id, L),
          debug = proplists:get_value(debug, L, []),
          timeout = proplists:get_value(timeout, L),
          job_timeout = proplists:get_value(job_timeout, L),
          heartbeat_timeout = proplists:get_value(heartbeat_timeout, L),
          url = proplists:get_value(url, L),
          host = proplists:get_value(host, L),
          method = proplists:get_value(method, L),
          hz = Hz,
          seconds = Seconds,
          cnt = Cnt,
          timer = erlang:send_after(trunc(1 + 1000/Hz), self(), periodic_check)
        }.

%%-----------------------------------------------------------------------------
%%
%% @doc start job and start timer for it
%%
-spec periodic_check(#child{}) -> #child{}.

periodic_check(#child{cnt=0, job_timeout=T} = State) ->
    erlang:send_after(T, self(), last_job_timeout),
    State;

periodic_check(#child{cnt=Cnt, hz=Hz, timer=Ref} = State) ->
    mpln_misc_run:cancel_timer(Ref),
    New = add_job(State),
    Nref = erlang:send_after(trunc(1 + 1000/Hz), self(), periodic_check),
    New#child{cnt=Cnt-1, timer=Nref}.

%%-----------------------------------------------------------------------------
%%
%% @doc terminates job if it still works
%%
stop_job(#child{jobs=Jobs} = St, Id) ->
    F = fun(#chi{id=X}) ->
                X == Id
        end,
    {Found, Rest} = lists:partition(F, Jobs),
    case Found of
        [] ->
            ok;
        [C] ->
            smoke_test_misc:stop_child(St#child.debug,
                                       smoke_test_request_supervisor,
                                       C#chi.pid)
    end,
    St#child{jobs=Rest}.

%%-----------------------------------------------------------------------------
%%
%% @doc starts new job and stores job info into state
%%
-spec add_job(#child{}) -> #child{}.

add_job(#child{jobs=Jobs, job_timeout=T, ses_sn=Sn} = St) ->
    Ref = make_ref(),
    case prepare_one_job(St, Ref, T) of
        [C] ->
            erlang:send_after(T, self(), {job_timeout, C#chi.id}),
            St#child{jobs=[C|Jobs], ses_sn=Sn+1};
        _ -> % error
            St
        end.

%%-----------------------------------------------------------------------------
%%
%% @doc creates parameters and starts job process with the parameters
%%
-spec prepare_one_job(#child{}, reference(), non_neg_integer()) -> [#chi{}].

prepare_one_job(#child{serv_tag=Tag, ses_sn=Sn, ses_base=Sbase,
                       heartbeat_timeout=Htime,
                       host=Host} = St,
                Ref, Time) ->
    Params = [
              {id, Ref},
              {parent, self()},
              {serv_tag, Tag},
              {ses_sn, Sn},
              {ses_base, Sbase},
              {debug, St#child.debug},
              {host, Host},
              {url, St#child.url},
              {method, St#child.method},
              {params, make_params(St)},
              {heartbeat_timeout, Htime},
              {timeout, Time}
             ],
    smoke_test_misc:do_one_child(St#child.debug,
                                 smoke_test_request_supervisor,
                                 [], Params).

%%-----------------------------------------------------------------------------
%%
%% @doc sends job statistic to the handler
%%
send_stat(#child{stat=Stat}) ->
    #stat{count=Count, count_ok=Ok, count_error=Err, sum=Sum, sum_sq=Sq} = Stat,
    smoke_test_handler:send_stat(Count, Ok, Err, Sum, Sq).

%%-----------------------------------------------------------------------------
make_params(St) ->
    []
    .

%%-----------------------------------------------------------------------------
%%
%% @doc updates stat for the terminated job and removes it from the list of jobs
%%
job_done(#child{jobs=Jobs} = St, Mref) ->
    F = fun(#chi{mon=X}) ->
                X == Mref
        end,
    {Found, Rest} = lists:partition(F, Jobs),
    Stu = update_stat(St, Found),
    Stu#child{jobs=Rest}.

%%-----------------------------------------------------------------------------
%%
%% @doc updates stat for the job
%%
update_stat(St, []) ->
    St;

update_stat(St, [#chi{dur=D} = J]) when is_integer(D) ->
    Dur = D / 1000.0,
    proceed_update_stat(St, J, Dur);

update_stat(St, [J]) ->
    Now = now(),
    Dur = timer:now_diff(Now, J#chi.start) / 1000.0,
    proceed_update_stat(St, J, Dur).

proceed_update_stat(#child{stat=Stat} = St, J, Dur) ->
    Nstat = smoke_test_misc:update_stat(Stat, J#chi.status, Dur),
    St#child{stat=Nstat}.

%%-----------------------------------------------------------------------------
%%
%% @doc update duration and status for job
%%
update_job_result(#child{jobs=Jobs} = St, Id, Status, Dur) ->
    F = fun(X) ->
                update_one_job(X, Id, Status, Dur)
        end,
    New_jobs = lists:map(F, Jobs),
    St#child{jobs=New_jobs}.

%%-----------------------------------------------------------------------------
%%
%% @doc update one job with status and duration
%%
update_one_job(#chi{id=Id} = X, Id, Status, Dur) ->
    X#chi{status=Status, dur=Dur};

update_one_job(X, _, _, _) ->
    X.

%%-----------------------------------------------------------------------------
