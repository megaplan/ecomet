-ifndef(mcom_params).
-define(mcom_params, true).

-define(ID_LEN, 8).
-define(SETUP_CONSUMER_TIMEOUT, 10000).
-define(T, 1000).
-define(TC, 0).
-define(LOG, "/var/log/erpher/mc").
-define(CONF, "mcom.conf").

% state of a websocket worker
-record(child, {
    id,
    id_r, % rand id for simulating no_local amqp consumer
    start_time = {0,0,0},
    sock,
    debug,
    conn, % #conn{}
    no_local = false, % for amqp consumer setup
    event
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
