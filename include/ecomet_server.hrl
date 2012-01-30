-include("ecomet_nums.hrl").

-ifndef(ecomet_server).
-define(ecomet_server, true).

% state of a server server
-record(csr, {
    ws_children = [], % web socket
    sio_children = [], % socket-io
    sjs_children = [], % sockjs
    lp_yaws = [], % yaws processes serving long polling
    lp_yaws_last_check,
    lp_yaws_check_interval = ?LP_YAWS_CHECK_INTERVAL,
    % time to terminate yaws long poll processes
    lp_yaws_request_timeout = ?LP_YAWS_REQUEST_TIMEOUT,
    child_config = [],
    yaws_config = [],
    socketio_config = [],
    sockjs_config = [],
    log,
    conn, % #conn{}
    rses, % #rses{}
    stat, % #stat{}
    timer :: reference(), % timer reference for periodic check
    debug
}).

-endif.
