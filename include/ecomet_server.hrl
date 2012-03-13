-include("ecomet_nums.hrl").

-ifndef(ecomet_server).
-define(ecomet_server, true).

% state of a server server
-record(csr, {
    sio_children = [], % socket-io
    sjs_children = [], % sockjs
    child_config = [],
    socketio_config = [],
    sockjs_config = [],
    log,
    conn, % #conn{}
    rses, % #rses{}
    stat, % #stat{}
    timer :: reference(), % timer reference for periodic check
    timer_stat        :: reference(), % timer reference for periodic log stat
    log_stat_interval :: non_neg_integer(), % seconds
    smoke_test        :: undefined | broadcast, % for smoke test
    debug
}).

-endif.
