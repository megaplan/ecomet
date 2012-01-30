%%%
%%% ecomet_conf: functions for config
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

-module(ecomet_conf).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([get_config/0, get_child_config/1]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("ecomet.hrl").
-include("ecomet_child.hrl").
-include("ecomet_server.hrl").
-include("rabbit_session.hrl").

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
%%
%% @doc reads config file for receiver, fills in csr record with configured
%% values
%% @since 2011-10-14 15:50
%%
-spec get_config() -> #csr{}.

get_config() ->
    List = get_config_list(),
    fill_config(List).

%%-----------------------------------------------------------------------------
%%
%% @doc reads config file for receiver, fills in csr record with configured
%% values
%% @since 2011-10-14 15:50
%%
get_child_config(List) ->
    #child{
        user_data_as_auth_host = proplists:get_value(user_data_as_auth_host,
                                                     List, false),
        sio_auth_recheck = proplists:get_value(
                                      sio_auth_recheck_interval,
                                      List, ?SIO_AUTH_RECHECK_INTERVAL),
        idle_timeout = proplists:get_value(idle_timeout, List),
        http_connect_timeout = proplists:get_value(http_connect_timeout,
                                                   List, ?IDLE_TIMEOUT),
        http_timeout = proplists:get_value(http_timeout, List, ?IDLE_TIMEOUT),
        qmax_dur = proplists:get_value(qmax_dur, List, ?QUEUE_MAX_DUR),
        qmax_len = proplists:get_value(qmax_len, List, ?QUEUE_MAX_LEN),
        id_web = proplists:get_value(id_web, List),
        type = proplists:get_value(type, List, ws),
        no_local = proplists:get_value(no_local, List, false),
        conn = proplists:get_value(conn, List, #rses{}),
        debug = proplists:get_value(debug, List, []),
        sio_mgr = proplists:get_value(sio_mgr, List),
        sio_hdl = proplists:get_value(sio_hdl, List),
        sio_cli = proplists:get_value(sio_cli, List),
        sio_sid = proplists:get_value(sio_sid, List),
        sjs_sid = proplists:get_value(sjs_sid, List),
        sjs_conn = proplists:get_value(sjs_conn, List),
        exchange_base = proplists:get_value(exchange_base, List, <<>>),
        event = make_event_bin(List),
        id = proplists:get_value(id, List)
    }.

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
%%
%% @doc extracts event and converts it to binary
%%
make_event_bin(List) ->
    case proplists:get_value(event, List) of
        E when is_list(E) -> iolist_to_binary(E);
%        E when is_atom(E) -> atom_to_binary(E, latin1);
        E                 -> E
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc gets data from the list of key-value tuples and stores it into
%% csr record
%% @since 2011-10-14 15:50
%%
-spec fill_config(list()) -> #csr{}.

fill_config(List) ->
    Child_config = proplists:get_value(child_config, List, []),
    #csr{
        rses = ecomet_conf_rabbit:stuff_rabbit_with(List),
        lp_request_timeout = 5 + proplists:get_value(lp_request_timeout,
                                                     Child_config,
                                                     ?LP_REQUEST_TIMEOUT),
        lp_check_interval = proplists:get_value(lp_check_interval, List,
                                   ?LP_CHECK_INTERVAL),
        lp_yaws_request_timeout = proplists:get_value(
                                    lp_yaws_request_timeout, List,
                                    ?LP_YAWS_REQUEST_TIMEOUT),
        lp_yaws_check_interval = proplists:get_value(
                                   lp_yaws_check_interval, List,
                                   ?LP_YAWS_CHECK_INTERVAL),
        yaws_config = proplists:get_value(yaws_config, List, []),
        socketio_config = proplists:get_value(socketio_config, List, []),
        sockjs_config = proplists:get_value(sockjs_config, List, []),
        debug = proplists:get_value(debug, List, []),
        child_config = Child_config,
        log = proplists:get_value(log, List)
    }.

%%-----------------------------------------------------------------------------
%%
%% @doc fetches the configuration from environment
%% @since 2011-10-14 15:50
%%
-spec get_config_list() -> list().

get_config_list() ->
    application:get_all_env('ecomet').

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
