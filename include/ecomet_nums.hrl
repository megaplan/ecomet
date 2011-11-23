-ifndef(ecomet_nums).
-define(ecomet_nums, true).

-define(OWN_ID_LEN, 8).
-define(MSG_ID_LEN, 8).

-define(SETUP_CONSUMER_TIMEOUT, 10000). % milliseconds
-define(IDLE_TIMEOUT, 300). % seconds
-define(LP_REQUEST_TIMEOUT, 300). % seconds
-define(LP_CHECK_INTERVAL, 1000). % milliseconds
-define(LP_YAWS_CHECK_INTERVAL, 1000). % milliseconds
-define(LP_YAWS_REQUEST_TIMEOUT, 300). % seconds
-define(QUEUE_MAX_DUR, 20000000). % microseconds
-define(QUEUE_MAX_LEN, 100).
-define(T, 1000).
-define(TC, 0).

-define(LOG, "/var/log/erpher/ec").

-endif.
