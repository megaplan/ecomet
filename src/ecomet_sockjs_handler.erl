%%%
%%% ecomet_sockjs_handler: handler to create sockjs children
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
%%% @since 2012-01-17 18:39
%%% @license MIT
%%% @doc handler that starts sockjs app and gets requests to create children
%%% to serve new sockjs requests
%%%

-module(ecomet_sockjs_handler).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([start/1, dispatcher/2]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include("ecomet_server.hrl").

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
%%
%% @doc starts configured backend - currently cowboy only
%% @since 2012-01-17 18:39
%%
-spec start(#csr{}) -> ok.

start(#csr{sockjs_config=undefined} = C) ->
    mpln_p_debug:pr({?MODULE, 'init, sockjs undefined', ?LINE},
                    C#csr.debug, run, 0),
    ok;

start(#csr{sockjs_config=Sc} = C) ->
    mpln_p_debug:pr({?MODULE, 'init', ?LINE}, C#csr.debug, run, 1),
    Port = proplists:get_value(port, Sc),
    {Base, Base_p} = prepare_base(Sc),
    application:start(sockjs),
    {ok, HttpImpl} = application:get_env(sockjs, http_impl),
    case HttpImpl of
        misultin ->
            Fh  = fun(X) -> misultin_loop(C, X) end,
            Fws = fun(X) -> misultin_ws_loop(C, X) end,
            {ok, _} = misultin:start_link([{loop,        Fh},
                                           {ws_loop,     Fws},
                                           {ws_autoexit, false},
                                           {port,        Port}]);
        cowboy ->
            application:start(cowboy),
            Fn = fun(X1, X2) ->
                         service_echo(C, X1, X2)
                 end,
            StateEcho = sockjs_handler:init_state(
                          Base_p,
                          Fn,
                          [{cookie_needed, true},
                           {response_limit, 4096}]),
            VRoutes = [{[Base, '...'], sockjs_cowboy_handler, StateEcho},
                       {'_', ?MODULE, []}],
            Routes = [{'_',  VRoutes}], % any vhost

            cowboy:start_listener(http, 100,
                                  cowboy_tcp_transport, [{port,     Port}],
                                  cowboy_http_protocol, [{dispatch, Routes}])
    end,
    mpln_p_debug:pr({?MODULE, 'init done', ?LINE, Port}, C#csr.debug, run, 1),
    ok.

%%-----------------------------------------------------------------------------
%%
%% @doc returns tag (must match with the tag on a client's side) and fun for
%% handling data that comes from sockjs
%% @since 2012-01-17 18:39
%%
-spec dispatcher(atom(), undefined | string()) -> [{atom(), fun()}].

dispatcher(Tag, Sid) ->
    Fb = fun(Conn, Info) ->
                 bcast(Sid, Conn, Info)
         end,
    [
     {Tag, Fb}
    ].

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
%%
%% @doc handler of misultin's requests
%%
misultin_loop(C, Req) ->
    try
        handle(C, {misultin, Req})
    catch A:B ->
            mpln_p_debug:pr({?MODULE, 'misultin_loop', ?LINE,
                             A, B, erlang:get_stacktrace()},
                            C#csr.debug, run, 1),
            Req:respond(500, [], "500")
    end.

%%
%% @doc handler of misultin's web sockets
%%
misultin_ws_loop(C, Ws) ->
    {Receive, _} = ws_handle(C, {misultin, Ws}),
    sockjs_http:misultin_ws_loop(Ws, Receive).

%%-----------------------------------------------------------------------------
%%
%% @doc common handler of http requests
%%
handle(#csr{sockjs_config=Sc} = C, Req) ->
    mpln_p_debug:pr({?MODULE, 'handle', ?LINE}, C#csr.debug, http, 2),
    mpln_p_debug:pr({?MODULE, 'handle', ?LINE, Req}, C#csr.debug, http, 4),
    {Path0, Req1} = sockjs_http:path(Req),
    Path = clean_path(Path0),
    Sid = get_sid(C, Path),
    Tag = proplists:get_value(tag, Sc),
    case sockjs_filters:handle_req(
           Req1, Path, ecomet_sockjs_handler:dispatcher(Tag, Sid)) of
        nomatch ->
            static(Req1, Path);
        Req2    ->
            mpln_p_debug:pr({?MODULE, 'handle', ?LINE, 'req2', Sid, Path, Tag},
                            C#csr.debug, http, 3),
            Req2
    end.

%%
%% @doc common handler of web sockets
%%
ws_handle(#csr{sockjs_config=Sc} = C, Req) ->
    mpln_p_debug:pr({?MODULE, 'ws_handle', ?LINE}, C#csr.debug, http, 2),
    mpln_p_debug:pr({?MODULE, 'ws_handle', ?LINE, Req}, C#csr.debug, http, 4),
    {Path0, Req1} = sockjs_http:path(Req),
    Path = clean_path(Path0),
    Sid = get_sid(C, Path),
    Tag = proplists:get_value(tag, Sc),
    mpln_p_debug:pr({?MODULE, 'ws_handle', ?LINE, 'req2', Sid, Path, Tag},
                    C#csr.debug, http, 3),
    {Receive, _, _, _} = sockjs_filters:dispatch('GET', Path,
                             ecomet_sockjs_handler:dispatcher(Tag, Sid)),
    {Receive, Req1}.

%%-----------------------------------------------------------------------------
%%
%% @doc handler for static requests
%%
static(Req, Path) ->
    %% TODO unsafe
    LocalPath = filename:join([module_path(), "priv/www", Path]),
    case file:read_file(LocalPath) of
        {ok, Contents} ->
            sockjs_http:reply(200, [], Contents, Req);
        {error, _} ->
            sockjs_http:reply(404, [], "", Req)
    end.

module_path() ->
    {file, Here} = code:is_loaded(?MODULE),
    filename:dirname(filename:dirname(Here)).

clean_path("/")         -> "index.html";
clean_path("/" ++ Path) -> Path.

%%-----------------------------------------------------------------------------
%%
%% @doc removes leading tokens that are not related to a session id
%%
-spec get_sid(#csr{}, string()) -> undefined | string().

get_sid(#csr{sockjs_config=Sc}, Path) ->
    Ignore = proplists:get_value(sid_ignore_tokens, Sc, 2),
    case string:tokens(Path, "/") of
        L when is_list(L) andalso length(L) > Ignore ->
            lists:nth(Ignore + 1, L);
        _ ->
            undefined
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc handler for start/stop/data requests that come from sockjs
%%
-spec bcast(undefined | string(), any(), init | closed | {recv, any()}) -> ok.

bcast(Sid, Conn, init) ->
    ecomet_server:sjs_add(Sid, Conn),
    ok;

bcast(Sid, Conn, closed) ->
    ecomet_server:sjs_del(Sid, Conn),
    ok;

bcast(Sid, Conn, {recv, Data}) ->
    ecomet_server:sjs_msg(Sid, Conn, Data),
    ok.

%%-----------------------------------------------------------------------------
service_echo(C, Conn, {recv, Data}) ->
    error_logger:info_report({?MODULE, 'service_echo recv', ?LINE, Conn, Data}),
    mpln_p_debug:pr({?MODULE, 'service_echo recv', ?LINE, Conn, Data},
                    C#csr.debug, run, 4),
    sockjs:send(Data, Conn);

service_echo(C, _Conn, _Data) ->
    mpln_p_debug:pr({?MODULE, 'service_echo other', ?LINE, _Conn, _Data},
                    C#csr.debug, run, 4),
    ok.

%%-----------------------------------------------------------------------------
-spec prepare_base(list()) -> {binary(), binary()}.

prepare_base(List) ->
    Tag = proplists:get_value(tag, List),
    Base = mpln_misc_web:make_binary(Tag),
    Base_p = << <<"/">>/binary, Base/binary>>,
    {Base, Base_p}.

%%-----------------------------------------------------------------------------
