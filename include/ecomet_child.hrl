-include("ecomet_nums.hrl").

-ifndef(ecomet_child).
-define(ecomet_child, true).

% state of a websocket worker
-record(child, {
    id, % ref
    id_r, % rand id for simulating no_local amqp consumer
    id_web, % rand id from long poll web page
    id_s, % user id to match messages from amqp (used in socket-io, sockjs part)
    start_time = {0,0,0},
    last_use = {0,0,0},
    idle_timeout = ?IDLE_TIMEOUT,
    sio_mgr, % socket-io event manager
    sio_hdl, % socket-io handler (module, in fact)
    sio_cli, % socket-io client
    sio_sid, % socket-io session id
    sio_auth_last = {0,0,0},
    sio_auth_recheck = ?SIO_AUTH_RECHECK_INTERVAL,
    sio_auth_url,
    sio_auth_host,
    sio_auth_cookie,
    sjs_sid,
    sjs_conn,
    clients = [], % in case of many requests with the very same id (quite unusual not to say sabotage)
    queue,
    qmax_dur = ?QUEUE_MAX_DUR, % microseconds
    qmax_len = ?QUEUE_MAX_LEN,
    debug,
    conn, % #conn{}
    exchange_base,
    routes = [], % routing keys
    no_local = false, % for amqp consumer setup
    type :: 'ws' | 'lp' | 'sio' | 'sjs', % web socket, long polling, socket-io, sockjs
    http_connect_timeout = ?HTTP_CONNECT_TIMEOUT,
    http_timeout = ?HTTP_TIMEOUT,
    user_data_as_auth_host :: undefined | boolean(),
    event,
    timer :: reference(), % timer for periodic checks
    timer_idle :: reference(), % timer for idle checks
    economize  :: hibernate | infinity, % gen_server default policy
    deep_memory_economize = true :: boolean(), % call gc on linked cowboy pids
    stat, % #stat{}
    jit_log_keep_n :: non_neg_integer(),
    jit_log_keep_time :: non_neg_integer(),
    jit_log_level = 0 :: integer(), % jit log level
    jit_log_status    :: ok | error,
    jit_log_data % ets table id
}).

-endif.
