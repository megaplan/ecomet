-module(ecomet_conn_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

init(_Args) ->
    {ok, {{one_for_one, 3, 5},
        []}}.

start_link() ->
    supervisor:start_link({local, ecomet_conn_sup},
        ecomet_conn_sup,
        []).
