%%%
%%% ecomet_stat: misc stat functions
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
%%% @doc statistic functions
%%%

-module(ecomet_stat).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([add_own_msg/1, add_other_msg/1, init/0]).
-export([add_server_stat/2]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include("ecomet_child.hrl").
-include("ecomet_stat.hrl").

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
%%
%% @doc updates any server statistic for given tag
%% @since 2011-11-08 17:19
%%
-spec add_server_stat(T, atom()) -> T.

add_server_stat(Storages, Tag) ->
    {Dstat, Hstat, Mstat} = Storages,
    Mnew = add_min_stat(Mstat, Tag),
    Hnew = add_hour_stat(Hstat, Tag),
    {Dstat, Hnew, Mnew}.

%%-----------------------------------------------------------------------------
%%
%% @doc updates statistic for own incoming messages
%% @since 2011-10-28 15:21
%%

-spec add_own_msg(#child{}) -> #child{}.

add_own_msg(#child{stat=St} = State) ->
    Tag = 'inc_own',
    New = add_timed_stat(St, Tag),
    ecomet_server:add_rabbit_inc_own_stat(),
    State#child{stat=New}.

%%-----------------------------------------------------------------------------
%%
%% @doc updates statistic for other incoming messages
%% @since 2011-10-28 16:01
%%

-spec add_other_msg(#child{}) -> #child{}.

add_other_msg(#child{stat=St} = State) ->
    Tag = 'inc_other',
    New = add_timed_stat(St, Tag),
    ecomet_server:add_rabbit_inc_other_stat(),
    State#child{stat=New}.

%%-----------------------------------------------------------------------------
%%
%% @doc inits statistic storage
%% @since 2011-10-28 16:31
%%
-spec init() -> dict().

init() ->
    dict:new().

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
%%
%% @doc updates statistic for given type for minutes and hours
%%
-spec add_timed_stat(#stat{}, atom()) -> #stat{}.

add_timed_stat(St, Tag) ->
    {Dstat, Hstat, Mstat} = St#stat.rabbit,
    Mnew = add_min_stat(Mstat, Tag),
    Hnew = add_hour_stat(Hstat, Tag),
    St#stat{rabbit={Dstat, Hnew, Mnew}}.

%%-----------------------------------------------------------------------------
add_min_stat(Mstat, Tag) ->
    Mkey = ecomet_data:make_minute_key(),
    add_msg(Mstat, Mkey, Tag).

%%-----------------------------------------------------------------------------
add_hour_stat(Mstat, Tag) ->
    Mkey = ecomet_data:make_hour_key(),
    add_msg(Mstat, Mkey, Tag).

%%-----------------------------------------------------------------------------
%%
%% @doc updates statistic for given time and type
%%

add_msg(Stat, Time, Tag) ->
    Key = {Time, Tag},
    case dict:find(Key, Stat) of
        {ok, Val} when is_integer(Val) ->
            dict:store(Key, Val+1, Stat);
        _ ->
            dict:store(Key, 1, Stat)
    end.

%%-----------------------------------------------------------------------------
