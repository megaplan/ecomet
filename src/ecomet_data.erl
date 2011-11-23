%%%
%%% ecomet_data: misc data functions
%%%
%%% Copyright (c) 2011 Megaplan Ltd. (Russia)
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"),
%%% to deal in the Software without restriction, including without limitation
%%% the rights to use, copy, modify, merge, publish, distribute, sublicense,
%%% and/or sell copies of the Software, and to permit persons to whom
%%% the Software is furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included
%%% in all copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
%%% MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
%%% IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
%%% CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
%%% TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
%%% SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
%%%
%%% @author arkdro <arkdro@gmail.com>
%%% @since 2011-10-27 16:51
%%% @license MIT
%%% @doc misc data functions
%%%

-module(ecomet_data).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([gen_id/0, gen_id/1]).
-export([make_minute_key/0, make_minute_key/1]).
-export([make_hour_key/0, make_hour_key/1]).
-export([is_our_id/2]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include("ecomet_nums.hrl").

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
%%
%% @doc creates random id and returns it as encoded binary base64 string
%% of length N
%% @since 2011-10-27 16:51
%%
-spec gen_id() -> binary().

gen_id() ->
    gen_id(?OWN_ID_LEN).

-spec gen_id(non_neg_integer()) -> binary().

gen_id(Len) ->
    crypto:start(),
    Data = crypto:rand_bytes(Len),
    <<Id:Len/binary, _/binary>> = base64:encode(Data),
    Id.

%%-----------------------------------------------------------------------------
%%
%% @doc creates minute based key from datetime to use in statistic
%%
make_minute_key() ->
    Now = now(),
    T = calendar:now_to_local_time(Now),
    make_minute_key(T).

make_minute_key({D, {H, M, _S}}) ->
    {D, {H, M, 0}}.

%%-----------------------------------------------------------------------------
%%
%% @doc creates hour based key from datetime to use in statistic
%%
make_hour_key() ->
    Now = now(),
    T = calendar:now_to_local_time(Now),
    make_hour_key(T).

make_hour_key({D, {H, _M, _S}}) ->
    {D, {H, 0, 0}}.

%%-----------------------------------------------------------------------------
%%
%% @checks whether the received id is our own id
%%
-spec is_our_id(binary(), any()) -> boolean().

is_our_id(Base, Id) ->
    Base == Id.

%%-----------------------------------------------------------------------------
