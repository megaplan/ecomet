-module(st1).

-export([
        t/0,
        t/1,
        t2/0
        ]).

t() ->
    prepare(),
    smoke_test_handler:st().

t(List) ->
    prepare(),
    smoke_test_handler:st(List).

t2() ->
    t([{count, 1}, {seconds, 5}, {hz, 10}])
.

prepare() ->
    Apps = [crypto, public_key, ssl, inets, smoke_test],
    [application:start(X) || X <- Apps].

% httpc:request(post, {"http://localhost:8081/echo/000/UXqkbJ1P_2/xhr", [], "application/x-www-form-urlencoded", []}, [{timeout, 25100}, {connect_timeout, 1000}], [{body_format, binary}]).

% httpc:request(post, {"http://localhost:8081/echo/000/UXqkbJ1P_2/xhr_send", [], "application/x-www-form-urlencoded", <<"[\"#Ref<0.0.0.100>\"]">>}, [{timeout, 25100}, {connect_timeout, 1000}], [{body_format, binary}]).
