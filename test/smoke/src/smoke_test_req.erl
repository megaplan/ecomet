%%%
%%% smoke_test_req: async request created by a dynamically added worker
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
%%% @since 2012-02-07 18:24
%%% @license MIT
%%% @doc async request that is created by a dynamically added worker
%%%

-module(smoke_test_req).
-behaviour(gen_server).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------
-export([start/0, start_link/0, start_link/1, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([terminate/2, code_change/3]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include("req.hrl").

-define(TC, 1).

%%%----------------------------------------------------------------------------
%%% gen_server callbacks
%%%----------------------------------------------------------------------------
init(Params) ->
    C = prepare_all(Params),
    mpln_p_debug:pr({?MODULE, 'init done', ?LINE, C#req.id, self()},
        C#req.debug, run, 2),
    {ok, C, ?TC}.

%%-----------------------------------------------------------------------------
%%
%% Handling call messages
%% @since 2012-02-07 14:42
%%
-spec handle_call(any(), any(), #req{}) ->
                         {stop, normal, ok, #req{}}
                             | {reply, any(), #req{}}.

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
-spec handle_cast(any(), #req{}) -> {stop, normal, #req{}}
                                          | {noreply, #req{}}.

handle_cast(stop, St) ->
    {stop, normal, St};

handle_cast(_, St) ->
    {noreply, St}.

%%-----------------------------------------------------------------------------
terminate(_, #req{id=Id, status=Status, start=Start, parent=Pid} = State) ->
    Now = now(),
    Dur = timer:now_diff(Now, Start),
    smoke_test_child:job_result(Pid, Id, Status, Dur),
    mpln_p_debug:pr({?MODULE, terminate, ?LINE, Id, self()},
        State#req.debug, run, 2),
    ok.

%%-----------------------------------------------------------------------------
%%
%% Handling all non call/cast messages
%%
-spec handle_info(any(), #req{}) -> {noreply, #req{}}.

handle_info(timeout, State) ->
    mpln_p_debug:pr({?MODULE, 'timeout', ?LINE}, State#req.debug, run, 6),
    New = add_job(State),
    {noreply, New};

handle_info(_Req, State) ->
    mpln_p_debug:pr({?MODULE, other, ?LINE, _Req, State#req.id, self()},
        State#req.debug, run, 2),
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
    gen_server:call(self(), stop).

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
%%
%% @doc prepares necessary things
%%
-spec prepare_all(list()) -> #req{}.

prepare_all(L) ->
    #req{
          start = now(),
          parent = proplists:get_value(parent, L),
          id = proplists:get_value(id, L),
          serv_tag = proplists:get_value(serv_tag, L),
          ses_sn = proplists:get_value(ses_sn, L, 0),
          ses_base = proplists:get_value(ses_base, L),
          debug = proplists:get_value(debug, L, []),
          host = proplists:get_value(host, L),
          url = proplists:get_value(url, L),
          method = proplists:get_value(method, L),
          heartbeat_timeout = proplists:get_value(heartbeat_timeout, L),
          timeout = proplists:get_value(timeout, L)
        }.

%%-----------------------------------------------------------------------------
add_job(St) ->
    Res = smoke_test_job:add_job(St),
    gen_server:cast(self(), stop),
    St#req{status=Res}.

%%-----------------------------------------------------------------------------
