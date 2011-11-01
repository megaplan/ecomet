-ifndef(ecomet_params).
-define(ecomet_params, true).

-define(OWN_ID_LEN, 8).
-define(MSG_ID_LEN, 8).
-define(SETUP_CONSUMER_TIMEOUT, 10000).
-define(T, 1000).
-define(TC, 0).
-define(LOG, "/var/log/erpher/ec").
%-define(CONF, "ecomet.conf").

% state of a websocket worker
-record(child, {
    id,
    id_r, % rand id for simulating no_local amqp consumer
    start_time = {0,0,0},
    sock,
    lp_sock, % for long poll
    yaws_pid, % for long poll
    debug,
    conn, % #conn{}
    no_local = false, % for amqp consumer setup
    type :: 'ws' | 'lp', % web socket or long polling
    event,
    stat % #stat{}
}).

-record(chi, {
    pid,
    id,
    mon,
    os_pid,
    start={0,0,0} % time in now() format
}).

% state of a server server
-record(csr, {
    children = [],
    child_config = [],
    yaws_config = [],
    log,
    conn, % #conn{}
    rses, % #rses{}
    debug
}).

-endif.
