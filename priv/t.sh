#!/bin/sh

erl -pa ~/work/ecomet/ebin -pa ~/work/erpher_lib/ebin/ -pa ~/util/erlang/http/yaws-1.91/ebin/ -config ~/work/ecomet/priv/ecomet_server -name 'ecomet@localhost.localdomain' -setcookie ecomet

# [application:start(X) || X <- [sasl, crypto, public_key, ssl, ecomet_server]].
