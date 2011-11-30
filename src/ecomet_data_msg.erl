%%%
%%% ecomet_data_msg: ecomet data functions
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
%%% @since 2011-11-24 13:00
%%% @license MIT
%%% @doc ecomet data related functions
%%%

-module(ecomet_data_msg).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([get_type/1, get_rest_info/1, get_method/1, get_url/1]).
-export([get_time/1, get_params/1, get_host/1]).
-export([get_auth_info/1, get_auth_user/1, get_auth_password/1]).
-export([get_auth_type/1, get_auth_data_list/1]).
-export([get_auth_keys/1]).
-export([get_group/1]).
-export([get_auth_url/1, get_auth_cookie/1, get_account/1, get_user_id/1]).
-export([get_routes/1]).
-export([get_message/1, get_users/1]).

%%%----------------------------------------------------------------------------
%%% Public API
%%%----------------------------------------------------------------------------
-spec get_group(any()) -> any().
%%
%% @doc Extracts value for "group" item
%% @since 2011-11-24 13:11
%%
get_group(Data) ->
    get_value(Data, <<"group">>).

%%-----------------------------------------------------------------------------
-spec get_type(any()) -> any().
%%
%% @doc Extracts value for "type" item
%% @since 2011-11-24
%%
get_type(Data) ->
    get_value(Data, <<"type">>).

%%-----------------------------------------------------------------------------
-spec get_rest_info(any()) -> any().
%%
%% @doc Extracts value for "info" item
%% @since 2011-11-24
%%
get_rest_info(Data) ->
    get_value(Data, <<"info">>).

%%-----------------------------------------------------------------------------
-spec get_method(any()) -> any().
%%
%% @doc Extracts value for "method" item
%% @since 2011-11-24
%%
get_method(Data) ->
    get_value(Data, <<"method">>).

%%-----------------------------------------------------------------------------
-spec get_url(any()) -> any().
%%
%% @doc Extracts value for "url" item
%% @since 2011-11-24
%%
get_url(Data) ->
    get_value(Data, <<"url">>).

%%-----------------------------------------------------------------------------
-spec get_host(any()) -> any().
%%
%% @doc Extracts value for "host" item
%% @since 2011-11-24 13:11
%%
get_host(Data) ->
    get_value(Data, <<"host">>).

%%-----------------------------------------------------------------------------
%%
%% @doc Extracts value for "params" item
%% @since 2011-11-24 13:11
%%
-spec get_params(any()) -> list().

get_params(Data) ->
    case get_value(Data, <<"params">>) of
        {struct, List} when is_list(List) ->
            List;
        _ ->
            []
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc Extracts value for "run_time" item
%% @since 2011-11-24 13:11
%%
-spec get_time(any()) -> any().

get_time(Data) ->
    get_value(Data, <<"run_time">>).

%%-----------------------------------------------------------------------------
%%
%% @doc Extracts value for "auth_info" item
%% @since 2011-11-24 13:11
%%
-spec get_auth_info(any()) -> any().

get_auth_info(Data) ->
    get_value(Data, <<"auth">>).

%%-----------------------------------------------------------------------------
%%
%% @doc Extracts value for auth url
%% @since 2011-11-24 13:11
%%
-spec get_auth_url(any()) -> any().

get_auth_url(Data) ->
    get_value(Data, <<"authUrl">>).

%%-----------------------------------------------------------------------------
%%
%% @doc Extracts value for auth cookie
%% @since 2011-11-24 13:11
%%
-spec get_auth_cookie(any()) -> any().

get_auth_cookie(Data) ->
    get_value(Data, <<"cookie">>).

%%-----------------------------------------------------------------------------
%%
%% @doc Extracts value for user id
%% @since 2011-11-24 13:11
%%
-spec get_user_id(any()) -> any().

get_user_id(Data) ->
    get_value(Data, <<"userId">>).

%%-----------------------------------------------------------------------------
%%
%% @doc extracts list of routes
%% @since 2011-11-25 12:41
%%
-spec get_routes(any()) -> any().

get_routes(Data) ->
    get_value(Data, <<"routes">>).

%%-----------------------------------------------------------------------------
%%
%% @doc extracts message
%% @since 2011-11-30 15:43
%%
-spec get_message(any()) -> any().

get_message(Data) ->
    get_value(Data, <<"message">>).

%%-----------------------------------------------------------------------------
%%
%% @doc extracts list of allowed users
%% @since 2011-11-30 15:43
%%
-spec get_users(any()) -> any().

get_users(Data) ->
    get_value(Data, <<"allowedUsers">>).

%%-----------------------------------------------------------------------------
%%
%% @doc Extracts value for auth cookie
%% @since 2011-11-24 13:11
%%
-spec get_account(any()) -> any().

get_account(Data) ->
    get_value(Data, <<"account">>).

%%-----------------------------------------------------------------------------
%%
%% @doc Extracts value for "type" item
%% @since 2011-11-24 13:11
%%
-spec get_auth_type(any()) -> any().

get_auth_type(Data) ->
    get_value(Data, <<"type">>).

%%-----------------------------------------------------------------------------
%%
%% @doc Extracts value for "user" item
%% @since 2011-11-24 13:11
%%
-spec get_auth_user(any()) -> any().

get_auth_user(Data) ->
    get_value(Data, <<"user">>).

%%-----------------------------------------------------------------------------
%%
%% @doc Extracts value for "key" item
%% @since 2011-11-24 13:11
%%
-spec get_auth_keys(any()) -> any().

get_auth_keys(Data) ->
    A = get_value(Data, <<"authKey">>),
    S = get_value(Data, <<"secretKey">>),
    {A, S}.

%%-----------------------------------------------------------------------------
%%
%% @doc Extracts value for "struct" list
%% @since 2011-11-24 13:11
%%
-spec get_auth_data_list(any()) -> any().

get_auth_data_list({struct, Data}) when is_list(Data) ->
    Data;
get_auth_data_list(_) ->
    [].

%%-----------------------------------------------------------------------------
%%
%% @doc Extracts value for "password" item
%% @since 2011-11-24 13:11
%%
-spec get_auth_password(any()) -> any().

get_auth_password(Data) ->
    get_value(Data, <<"password">>).

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------

-spec get_value(any(), binary()) -> any().
%%
%% @doc Extracts value for tagged item
%%
get_value({struct, List}, Tag) when is_list(List) ->
    case proplists:get_value(Tag, List) of
        {struct, Data} when is_list(Data) ->
            Data;
        Other ->
            Other
        end;
get_value(List, Tag) when is_list(List) ->
    proplists:get_value(Tag, List);
get_value(_Data, _Tag) ->
    undefined.

%%-----------------------------------------------------------------------------
