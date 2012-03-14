%%%
%%% smoke_test_misc: common functions for spawning children
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
%%% @since 2012-02-07 17:53
%%% @license MIT
%%% @doc common functions for spawning children
%%%

-module(smoke_test_misc).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([do_one_child/4, update_stat/3, stop_child/3]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include("child.hrl").
-include("stat.hrl").

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
%%
%% @since 2012-02-07 17:53
%%
-spec stop_child(list(), atom(), pid()) -> any().

stop_child(Debug, Sup, Pid) ->
    case supervisor:terminate_child(Sup, Pid) of
        ok ->
            ok;
        {error, _Reason} = Res ->
            mpln_p_debug:pr({?MODULE, 'stop_child error', ?LINE, Sup, Pid, Res},
                            Debug, run, 1),
            Res
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc spawns a child for given supervisor, activates monitor for the child
%% @since 2012-02-07 17:53
%%
-spec do_one_child(list(), atom(), [#chi{}], list()) -> [#chi{}].

do_one_child(Debug, Sup, Ch, Params) ->
    Id = proplists:get_value(id, Params),
    Res = supervisor:start_child(Sup, [Params]),
    mpln_p_debug:pr({?MODULE, 'do_one_child res', ?LINE, Res},
                    Debug, run, 5),
    case Res of
        {ok, Pid} ->
            add_child(Ch, Pid, Id);
        {ok, Pid, _Info} ->
            add_child(Ch, Pid, Id);
        _ ->
            mpln_p_debug:pr({?MODULE, 'do_one_child res', ?LINE, 'error',
                             Params, Res}, Debug, run, 1),
            Ch
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc updates job statistic
%%
-spec update_stat(#stat{}, ok | error, float()) -> #stat{}.

update_stat(#stat{count=Count, sum=Sum, sum_sq=Sq, count_ok=Ok} = Stat, ok,
            Dur) ->
    Stat#stat{count=Count+1, sum=Sum+Dur, sum_sq=Sq + Dur*Dur, count_ok=Ok+1};

update_stat(#stat{count=Count, sum=Sum, sum_sq=Sq, count_error=E} = Stat, error,
            Dur) ->
    Stat#stat{count=Count+1, sum=Sum+Dur, sum_sq=Sq + Dur*Dur, count_error=E+1}.

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
%%
%% @doc activates monitor for new process and stores the process data in
%% a result list
%%
-spec add_child([#chi{}], pid(), reference()) -> [#chi{}].

add_child(Children, Pid, Id) ->
    Mref = erlang:monitor(process, Pid),
    Ch = #chi{pid = Pid, id = Id, start = now(), mon=Mref},
    [Ch | Children].

%%-----------------------------------------------------------------------------
