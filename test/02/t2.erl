% send a bunch of test messages to ecomet_server for broadcasting
-module(t2).
-compile(export_all).

t() ->
    t(1).

t(End) ->
    t(1, End).

t(Beg, End) ->
    [
    begin
        Bnum = mpln_misc_web:make_binary(B),
        Bin = << <<"test:">>/binary, Bnum/binary>>,
        ecomet_server:sjs_broadcast_msg(Bin)
    end || B <- lists:seq(Beg, End)].
