%%%
%%% mcom_conf: functions for config
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
%%% @doc functions related to config file read, config processing
%%%

-module(mcom_conf).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([get_config/0]).
-export([get_config_child/1]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("mcom.hrl").

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
%%
%% @doc fills in the child config with values from input list.
%% @since 2011-10-14 15:50
%%
-spec get_config_child(list()) -> #child{}.

get_config_child(List) ->
    #child{
        url_rewrite = proplists:get_value(url_rewrite, List, []),
        name = proplists:get_value(name, List),
        id = proplists:get_value(id, List),
        from = proplists:get_value(from, List),
        method = proplists:get_value(method, List, <<>>),
        url = proplists:get_value(url, List, <<>>),
        host = proplists:get_value(host, List),
        auth = proplists:get_value(auth, List),
        params = proplists:get_value(params, List, []),
        debug = proplists:get_value(debug, List, [])
    }.

%%-----------------------------------------------------------------------------
%%
%% @doc reads config file for receiver, fills in ejm record with configured
%% values
%% @since 2011-10-14 15:50
%%
-spec get_config() -> #csr{}.

get_config() ->
    List = get_config_list(),
    fill_config(List).

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
%%
%% @doc gets data from the list of key-value tuples and stores it into
%% ejm record
%% @since 2011-10-14 15:50
%%
-spec fill_config(list()) -> #csr{}.

fill_config(List) ->
    #csr{
        debug = proplists:get_value(debug, List, []),
        log = proplists:get_value(log, List)
    }.

%%-----------------------------------------------------------------------------
%%
%% @doc fetches the configuration from environment
%% @since 2011-10-14 15:50
%%
-spec get_config_list() -> list().

get_config_list() ->
    application:get_all_env('mcom').

%%%----------------------------------------------------------------------------
%%% EUnit tests
%%%----------------------------------------------------------------------------
-ifdef(TEST).
fill_config_test() ->
    #csr{debug=[], log=?LOG} = fill_config([]),
    #csr{debug=[{info, 5}, {run, 2}], log=?LOG} =
    fill_config([
        {debug, [{info, 5}, {run, 2}]}
        ]).
-endif.
%%-----------------------------------------------------------------------------
