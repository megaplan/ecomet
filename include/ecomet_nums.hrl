-ifndef(ecomet_nums).
-define(ecomet_nums, true).

-define(OWN_ID_LEN, 8).
-define(MSG_ID_LEN, 8).

-define(HTTP_CONNECT_TIMEOUT, 15000). % milliseconds
-define(HTTP_TIMEOUT, 60000). % milliseconds
-define(SETUP_CONSUMER_TIMEOUT, 10000). % milliseconds
-define(IDLE_TIMEOUT, 300). % seconds
-define(SIO_AUTH_RECHECK_INTERVAL, 300). % seconds
-define(QUEUE_MAX_DUR, 20000000). % microseconds
-define(QUEUE_MAX_LEN, 100).
-define(T, 1000).
-define(TC, 0).

-define(LOG, "/var/log/erpher/ec").

-endif.
