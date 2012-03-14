%%% 
%%% smoke_test_sup: main supervisor
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
%%% @since 2012-02-06 18:01
%%% @license MIT
%%% @doc main supervisor that spawns handler and child supervisor
%%% 

-module(smoke_test_sup).
-behaviour(supervisor).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([start_link/0, init/1]).

%%%----------------------------------------------------------------------------
%%% Defines
%%%----------------------------------------------------------------------------

-define(RESTARTS, 5).
-define(SECONDS, 2).

%%%----------------------------------------------------------------------------
%%% Supervisor callbacks
%%%----------------------------------------------------------------------------
init(_Args) ->
    Handler = {
        smoke_test_handler, {smoke_test_handler, start_link, []},
        permanent, 1000, worker, [smoke_test_handler]
        },
    Sup = {
        smoke_test_child_sup, {smoke_test_child_sup, start_link, []},
        transient, infinity, supervisor, [smoke_test_child_sup]
        },
    Rsup = {
        smoke_test_req_sup, {smoke_test_req_sup, start_link, []},
        transient, infinity, supervisor, [smoke_test_req_sup]
        },
    {ok, {{one_for_one, ?RESTARTS, ?SECONDS},
        [Rsup, Sup, Handler]}}.

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
-spec start_link() -> any().
%%
%% @doc calls supervisor:start_link to create smoke_test_supervisor
%%
start_link() ->
    supervisor:start_link({local, smoke_test_supervisor}, smoke_test_sup, []).

%%-----------------------------------------------------------------------------
