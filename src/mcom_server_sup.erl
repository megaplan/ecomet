-module(mcom_server_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, mcom_server_sup}, mcom_server_sup, []).

init(_Args) ->
    Ch = {
      mcom_srv, {mcom_server, start_link, []},
      permanent, 1000, worker, [mcom_server]
    },
    Csup = {
      mcom_conn_sup, {mcom_conn_sup, start_link, []},
      transient, infinity, supervisor, [mcom_conn_sup]
    },
    {ok, {{one_for_one, 3, 5},
          [Csup, Ch]}}.
