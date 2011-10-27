-module(ecomet_server_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ecomet_server_sup}, ecomet_server_sup, []).

init(_Args) ->
    Ch = {
      ecomet_srv, {ecomet_server, start_link, []},
      permanent, 1000, worker, [ecomet_server]
    },
    Csup = {
      ecomet_conn_sup, {ecomet_conn_sup, start_link, []},
      transient, infinity, supervisor, [ecomet_conn_sup]
    },
    {ok, {{one_for_one, 3, 5},
          [Csup, Ch]}}.
