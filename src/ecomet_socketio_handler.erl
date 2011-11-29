-module(ecomet_socketio_handler).

-include_lib("socketio.hrl").
-compile(export_all).
-behaviour(gen_event).

%% gen_event callbacks
-export([init/1, handle_event/2, handle_call/2, handle_info/2,
          terminate/2, code_change/3]).

-record(st, {
    ec_pid, % pid of ecomet_conn_server
    mgr,  % event manager
    client % web side process
}).

main() ->
    application:start(sasl),
    application:start(misultin),
    application:start(socketio),
%    {ok, Pid} = socketio_listener:start([{http_port, 7878}, 
%                                         {default_http_handler,?MODULE}]),
    {ok, Pid} = socketio_listener:start([{http_port, 7878}, 
                                         {default_http_handler,?MODULE}]),
    EventMgr = socketio_listener:event_manager(Pid),
    ok = gen_event:add_handler(EventMgr, ?MODULE,[]),
%    receive _ -> ok end.
    {EventMgr, Pid, self()}.

%% gen_event
init([]) ->
    mpln_p_debug:p("init, [], self: ~p~n", [self()], [], run, 0),
    {ok, #st{}}.

handle_event({client, Pid}, State) ->
    EventMgr = socketio_client:event_manager(Pid),
    Sid = socketio_client:session_id(Pid),
    Req = socketio_client:request(Pid),
    mpln_p_debug:p("~p::~p, client, ev_mgr: ~p, client: ~p, "
        "self: ~p~nsid: ~p~nreq: ~p~nstate: ~p~n",
        [?MODULE, ?LINE, EventMgr, Pid, self(), Sid, Req, State], [], run, 0),
    {ok, Ec_pid} = ecomet_server:add_sio(EventMgr, ?MODULE, Pid, Sid),
    New = #st{mgr=EventMgr, ec_pid=Ec_pid, client=Pid},
    ok = gen_event:add_handler(EventMgr, ?MODULE,[]),
    mpln_p_debug:p("~p::~p, client, ec_pid: ~p~n",
        [?MODULE, ?LINE, Ec_pid], [], run, 0),
    {ok, New};
handle_event({disconnect, Pid}, State) ->
    mpln_p_debug:p("~p::~p, disconnect, client: ~p, self: ~p~n"
        "state: ~p~n", [?MODULE, ?LINE, Pid, self(), State],
        [], run, 0),
    ecomet_server:del_sio(Pid),
    {ok, State};
handle_event({message, Client, #msg{content = _Content} = Msg}, State) ->
    EventMgr = socketio_client:event_manager(Client),
    Sid = socketio_client:session_id(Client),
    Req = socketio_client:request(Client),
    mpln_p_debug:p("~p::~p, message, ev_mgr: ~p, client: ~p, self: ~p~n"
        "sid: ~p~nreq: ~p~nstate: ~p~nmsg: ~p~n",
        [?MODULE, ?LINE, EventMgr, Client, self(),
        Sid, Req, State, Msg], [], run, 0),
    ecomet_server:sio_msg(Client, Sid, Msg),
    {ok, State};

handle_event(_E, State) ->
    mpln_p_debug:p("event other: ~p~n~p~n",[_E, State], [], run, 0),
    {ok, State}.

handle_call(status, State) ->
    mpln_p_debug:pr("handle_call: status", [], run, 0),
    {ok, State, State};
handle_call(Req, State) ->
    mpln_p_debug:p("handle_call other:~n~p~n~p~n", [Req, State], [], run, 0),
    {ok, ok, State}.

handle_info(_I, State) ->
    mpln_p_debug:p("info other: ~p~n~p~n",[_I, State], [], run, 0),
    {ok, State}.

terminate(_Reason, _State) ->
    mpln_p_debug:p("~p::~p, terminate, reason: ~p, self: ~p, st: ~p~n",
        [?MODULE, ?LINE, _Reason, self(), _State], [], run, 0),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
%%

handle_request(Method, Path, Req) ->
    mpln_p_debug:pr({Method, Path, Req}, [], run, 0),
    handle(Method, Path, Req).

%handle_http(Req) ->
%	% dispatch to rest
%	handle(Req:get(method), Req:resource([lowercase, urldecode]), Req).

handle('GET', [], Req) ->
    Req:file(filename:join([filename:dirname(code:which(?MODULE)), "index.html"]));

handle('GET', ["socket.io.js"], Req) ->
    Req:file(filename:join([filename:dirname(code:which(?MODULE)), "socket.io.js"]));

handle(_, _, Req) ->
	Req:ok([{"Content-Type", "text/plain"}], "Page not found.").

