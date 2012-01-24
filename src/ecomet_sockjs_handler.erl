%%%
%%% ecomet_server: server to create children to serve new websocket requests
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
%%% @doc server to create children to serve new websocket requests. It connects
%%% to rabbit and creates children with connection provided.
%%%

-module(ecomet_sockjs_handler).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([start/1, dispatcher/1]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include("ecomet_server.hrl").

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------

start(#csr{sockjs_config=Sc} = C) ->
    mpln_p_debug:pr({?MODULE, 'init', ?LINE}, C#csr.debug, run, 1),
    Port = proplists:get_value(port, Sc),
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
            Fh  = fun(X) -> handle(C, X) end,
            Fws = fun(X) -> ws_handle(C, X) end,
            Dispatch = [{'_', [{'_', sockjs_cowboy_handler,
                        {Fh, Fws}}]}],
            cowboy:start_listener(http, 100,
                                  cowboy_tcp_transport, [{port,     Port}],
                                  cowboy_http_protocol, [{dispatch, Dispatch}])
    end,
    mpln_p_debug:pr({?MODULE, 'init done', ?LINE, Port}, C#csr.debug, run, 1),
    ok.

%%-----------------------------------------------------------------------------

misultin_loop(C, Req) ->
    try
        handle(C, {misultin, Req})
    catch A:B ->
            mpln_p_debug:pr({?MODULE, 'misultin_loop', ?LINE,
                             A, B, erlang:get_stacktrace()},
                             C#csr.debug, run, 1),
            Req:respond(500, [], "500")
    end.

misultin_ws_loop(C, Ws) ->
    {Receive, _} = ws_handle(C, {misultin, Ws}),
    sockjs_http:misultin_ws_loop(Ws, Receive).

%%-----------------------------------------------------------------------------

handle(C, Req) ->
    mpln_p_debug:pr({?MODULE, 'handle', ?LINE}, C#csr.debug, http, 2),
    mpln_p_debug:pr({?MODULE, 'handle', ?LINE, Req}, C#csr.debug, http, 4),
    {Path0, Req1} = sockjs_http:path(Req),
    Path = clean_path(Path0),
    Sid = get_sid(C, Path),
    case sockjs_filters:handle_req(
           Req1, Path, ecomet_sockjs_handler:dispatcher(Sid)) of
        nomatch ->
                   case Path of
                       "config.js" ->
                            Res2a = config_js(C, Req1),
                            Res2a;
                       _           ->
                            Res2b = static(Req1, Path),
                            Res2b
                   end;
        Req2    ->
            mpln_p_debug:pr({?MODULE, 'handle', ?LINE, 'req2', Sid, Path},
                            C#csr.debug, http, 3),
                   Req2
    end.

ws_handle(C, Req) ->
    mpln_p_debug:pr({?MODULE, 'ws_handle', ?LINE}, C#csr.debug, http, 2),
    mpln_p_debug:pr({?MODULE, 'ws_handle', ?LINE, Req}, C#csr.debug, http, 4),
    {Path0, Req1} = sockjs_http:path(Req),
    Path = clean_path(Path0),
    Sid = get_sid(C, Path),
    mpln_p_debug:pr({?MODULE, 'ws_handle', ?LINE, 'req2', Sid, Path},
                    C#csr.debug, http, 3),
    {Receive, _, _, _} = sockjs_filters:dispatch('GET', Path,
                                                 ecomet_sockjs_handler:dispatcher(Sid)),
    {Receive, Req1}.

%%-----------------------------------------------------------------------------
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

config_js(#csr{sockjs_config=Sc}, Req) ->
    Port = proplists:get_value(port, Sc),
    Str_port = integer_to_list(Port),
    %% TODO parse the file? Good luck, it's JS not JSON.
    sockjs_http:reply(
      200, [{"content-type", "application/javascript"}],
      "var client_opts = {\"url\":\"http://localhost:" ++ Str_port ++ "\",\"disabled_transports\":[],\"sockjs_opts\":{\"devel\":true}};", Req).

clean_path("/")         -> "index.html";
clean_path("/" ++ Path) -> Path.

%%-----------------------------------------------------------------------------
%%
%% @doc removes leading tokens that are not related to a session id
%%
get_sid(#csr{sockjs_config=Sc}, Path) ->
    Ignore = proplists:get_value(sid_ignore_tokens, Sc, 2),
    case string:tokens(Path, "/") of
        L when is_list(L) andalso length(L) > Ignore ->
            lists:nth(Ignore + 1, L);
        _ ->
            undefined
    end.

dispatcher(Sid) ->
    Fb = fun(Conn, Info) ->
                test_broadcast(Sid, Conn, Info)
        end,
    [
     {ecomet, Fb}
    ].

test_broadcast(Sid, Conn, init) ->
    mpln_p_debug:pr({?MODULE, 'test_broadcast init', ?LINE, Sid, Conn}, [], run, 0),
    ecomet_server:sjs_add(Sid, Conn),
    ok;
test_broadcast(Sid, Conn, closed) ->
    mpln_p_debug:pr({?MODULE, 'test_broadcast closed', ?LINE, Sid, Conn}, [], run, 0),
    ecomet_server:sjs_del(Sid, Conn),
    ok;
test_broadcast(Sid, Conn, {recv, Data}) ->
    mpln_p_debug:pr({?MODULE, 'test_broadcast recv', ?LINE, Sid, Conn, Data}, [], run, 0),
    ecomet_server:sjs_msg(Sid, Conn, Data),
    ok.
