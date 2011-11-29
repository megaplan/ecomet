-include("ecomet_nums.hrl").

-ifndef(ecomet_server).
-define(ecomet_server, true).

% state of a server server
-record(csr, {
    ws_children = [], % web socket
    lp_children = [], % long poll
    sio_children = [], % socket-io
    lp_last_check,
    lp_check_interval = ?LP_CHECK_INTERVAL,
    lp_request_timeout = ?LP_REQUEST_TIMEOUT,
    lp_yaws = [], % yaws processes serving long polling
    lp_yaws_last_check,
    lp_yaws_check_interval = ?LP_YAWS_CHECK_INTERVAL,
    % time to terminate yaws long poll processes
    lp_yaws_request_timeout = ?LP_YAWS_REQUEST_TIMEOUT,
    child_config = [],
    yaws_config = [],
    socketio_config = [],
    log,
    conn, % #conn{}
    rses, % #rses{}
    stat, % #stat{}
    debug
}).

-endif.
