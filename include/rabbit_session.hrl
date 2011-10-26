-ifndef(rabbit_session).
-define(rabbit_session, true).

-record(rses, {
    'host' = "127.0.0.1",
    'port' = 5672,
    'user' = <<"guest">>,
    'password' = <<"guest">>,
    'vhost' = <<"/">>,
    'exchange' = <<"negacom">>,
    'exchange_type' = <<"topic">>,
    'queue' = <<"mc_queue">>,
    'routing_key' = <<"test_topless">>
}).

-record(conn, {
    'channel' = false,
    'connection' = false,
    'consumer_tag',
    'consumer',
    'exchange',
    'ticket'
}).

-endif.
