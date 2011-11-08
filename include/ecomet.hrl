-ifndef(ecomet_params).
-define(ecomet_params, true).

-define(OWN_ID_LEN, 8).
-define(MSG_ID_LEN, 8).
-define(SETUP_CONSUMER_TIMEOUT, 10000). % milliseconds
-define(IDLE_TIMEOUT, 300). % seconds
-define(LP_REQUEST_TIMEOUT, 300). % seconds
-define(QUEUE_MAX_DUR, 20000000). % microseconds
-define(QUEUE_MAX_LEN, 100).
-define(T, 1000).
-define(TC, 0).
-define(LOG, "/var/log/erpher/ec").
%-define(CONF, "ecomet.conf").

% state of a websocket worker
-record(child, {
    id,
    id_r, % rand id for simulating no_local amqp consumer
    id_web, % rand id from long poll web page
    start_time = {0,0,0},
    last_use = {0,0,0},
    idle_timeout = ?IDLE_TIMEOUT,
    lp_request_timeout = ?LP_REQUEST_TIMEOUT,
    sock,
    lp_sock, % for long poll
    yaws_pid, % for long poll
    clients = [], % in case of many requests with the very same id (quite unusual not to say sabotage)
    queue,
    qmax_dur = ?QUEUE_MAX_DUR, % microseconds
    qmax_len = ?QUEUE_MAX_LEN,
    debug,
    conn, % #conn{}
    no_local = false, % for amqp consumer setup
    type :: 'ws' | 'lp', % web socket or long polling
    event,
    stat % #stat{}
}).

-record(cli, {
    from,
    start={0,0,0} % time in now() format
}).

-record(chi, {
    pid,
    id,
    id_web,
    start={0,0,0} % time in now() format
}).

% state of a server server
-record(csr, {
    ws_children = [], % web socket
    lp_children = [], % long poll
    child_config = [],
    yaws_config = [],
    log,
    conn, % #conn{}
    rses, % #rses{}
    stat, % #stat{}
    debug
}).

-endif.
