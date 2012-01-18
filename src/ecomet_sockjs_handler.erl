-module(ecomet_sockjs_handler).
-export([start/0, dispatcher/1]).
-define(PORT, 8085).

start() ->
    mpln_p_debug:pr({?MODULE, 'start 1', ?LINE}, [], run, 0),
    Port = ?PORT,
    application:start(sockjs),
    mpln_p_debug:pr({?MODULE, 'start 2', ?LINE}, [], run, 0),
    {ok, HttpImpl} = application:get_env(sockjs, http_impl),
    mpln_p_debug:pr({?MODULE, 'start 3', ?LINE, HttpImpl}, [], run, 0),
    case HttpImpl of
        misultin ->
            {ok, _} = misultin:start_link([{loop,        fun misultin_loop/1},
                                           {ws_loop,     fun misultin_ws_loop/1},
                                           {ws_autoexit, false},
                                           {port,        Port}]);
        cowboy ->
            application:start(cowboy),
            mpln_p_debug:pr({?MODULE, 'start', ?LINE, 'cowboy ok'}, [], run, 0),
            Dispatch = [{'_', [{'_', sockjs_cowboy_handler,
                        {fun handle/1, fun ws_handle/1}}]}],
            cowboy:start_listener(http, 100,
                                  cowboy_tcp_transport, [{port,     Port}],
                                  cowboy_http_protocol, [{dispatch, Dispatch}])
    end,
    mpln_p_debug:pr({?MODULE, 'started', ?LINE, Port}, [], run, 0),
    ok.

%% --------------------------------------------------------------------------

misultin_loop(Req) ->
    try
        handle({misultin, Req})
    catch A:B ->
            io:format("~s ~p ~p~n", [A, B, erlang:get_stacktrace()]),
            Req:respond(500, [], "500")
    end.

misultin_ws_loop(Ws) ->
    {Receive, _} = ws_handle({misultin, Ws}),
    sockjs_http:misultin_ws_loop(Ws, Receive).

%% --------------------------------------------------------------------------

handle(Req) ->
    mpln_p_debug:pr({?MODULE, 'handle', ?LINE, Req}, [], run, 0),
    {Path0, Req1} = sockjs_http:path(Req),
    Path = clean_path(Path0),
    Sid = get_sid(Path),
    mpln_p_debug:pr({?MODULE, 'handle path', ?LINE, Sid, Path0, Path, Req1}, [], run, 0),
    case sockjs_filters:handle_req(
           Req1, Path, ecomet_sockjs_handler:dispatcher(Sid)) of
        nomatch ->
                   case Path of
                       "config.js" ->
                            Res2a = config_js(Req1),
                            mpln_p_debug:pr({?MODULE, 'handle case 2 config.js', ?LINE, Res2a}, [], run, 0),
                            Res2a;
                       _           ->
                            Res2b = static(Req1, Path),
                            mpln_p_debug:pr({?MODULE, 'handle case 2 other', ?LINE, Res2b}, [], run, 0),
                            Res2b
                   end;
        Req2    ->
                   mpln_p_debug:pr({?MODULE, 'handle case 1 req', ?LINE, Req2},
                        [], run, 0),
                   Req2
    end.

ws_handle(Req) ->
    mpln_p_debug:pr({?MODULE, 'ws_handle', ?LINE, Req}, [], run, 0),
    {Path0, Req1} = sockjs_http:path(Req),
    Path = clean_path(Path0),
    Sid = get_sid(Path),
    mpln_p_debug:pr({?MODULE, 'handle path', ?LINE, Sid, Path0, Path, Req1}, [], run, 0),
    {Receive, _, _, _} = sockjs_filters:dispatch('GET', Path,
                                                 ecomet_sockjs_handler:dispatcher(Sid)),
    {Receive, Req1}.

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

config_js(Req) ->
    Str_port = integer_to_list(?PORT),
    %% TODO parse the file? Good luck, it's JS not JSON.
    sockjs_http:reply(
      200, [{"content-type", "application/javascript"}],
      "var client_opts = {\"url\":\"http://localhost:" ++ Str_port ++ "\",\"disabled_transports\":[],\"sockjs_opts\":{\"devel\":true}};", Req).

clean_path("/")         -> "index.html";
clean_path("/" ++ Path) -> Path.

%% --------------------------------------------------------------------------
%% @doc only one leading token as a base!!!
get_sid(Path) ->
    case string:tokens(Path, "/") of
        [_Base, _Server, Client | _ ] ->
            Client;
        _ ->
            undefined
    end.

dispatcher(Sid) ->
    Fb = fun(Conn, Info) ->
                test_broadcast(Sid, Conn, Info)
        end,
    [
     {broadcast, Fb}
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
