%%%
%%% ecomet_conn_server_sjs: miscellaneous functions for ecomet connection server
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
%%% @since 2012-01-19 12:04
%%% @license MIT
%%% @doc miscellaneous functions for ecomet connection server
%%%

-module(ecomet_conn_server_sjs).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([process_msg/2]).
-export([send/3]).
-export([recheck_auth/1]).
-export([process_msg_from_server/2]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

%-include_lib("socketio.hrl").
-include("ecomet_child.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
%%
%% @doc does recheck auth. If url/cookie are undefined then it means
%% the process has not received any auth info from a web client yet.
%%
-spec recheck_auth(#child{}) -> #child{}.

recheck_auth(#child{sio_auth_url=undefined, sio_auth_cookie=undefined,
                   id_s=undefined} = St) ->
    St;

recheck_auth(#child{sio_auth_url=Url, sio_auth_cookie=Cookie,
                    sio_auth_host=Host} = St) ->
    Res_auth = proceed_http_auth_req(St, Url, Cookie, Host),
    proceed_auth_msg(St#child{sio_auth_last=now()}, Res_auth,
                     [{<<"type">>, 'reauth'}]).

%%-----------------------------------------------------------------------------
%%
%% @doc forward data received from ecomet_server to sockjs connection
%% @since 2012-01-23 16:10
%%
-spec process_msg_from_server(#child{}, any()) -> #child{}.

process_msg_from_server(#child{id=Id, sjs_conn=Conn, sjs_sid=Sid} = St, Data) ->
    mpln_p_debug:pr({?MODULE, 'process_msg_from_server', ?LINE, Id, Sid, Data},
                    St#child.debug, run, 4),
    erpher_et:trace_me(50, {?MODULE, Id}, Sid, send_data_from_server, Data),
    sockjs:send(Data, Conn),
    St.

%%-----------------------------------------------------------------------------
%%
%% @doc processes data received from socket-io, stores auth data if presents
%% for later checks
%% @since 2011-11-24 12:40
%%
-spec process_msg(#child{}, binary()) -> #child{}.

process_msg(#child{id=Id, id_s=Uid} = St, Bin) ->
    Data = get_json_body(Bin),
    case ecomet_data_msg:get_auth_info(Data) of
        undefined when Uid == undefined ->
            erpher_et:trace_me(50, ?MODULE, Id, 'undefined uid',
                Bin),
            mpln_p_debug:pr({?MODULE, 'process_msg', ?LINE, 'no auth data', Id},
                            St#child.debug, run, 4),
            St;
        undefined ->
            erpher_et:trace_me(40, {?MODULE, Id}, Uid, 'use_current_exchange',
                Bin),
            Type = ecomet_data_msg:get_type(Data),
            proceed_type_msg(St, use_current_exchange, Type, Data,
                             <<"use_current_exchange">>);
        Auth ->
            {Res_auth, Url, Cookie, Host} = send_auth_req(St, Auth),
            proceed_auth_msg(St#child{sio_auth_url=Url,
                                      sio_auth_host=Host,
                                      sio_auth_cookie=Cookie}, Res_auth, Data)
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc sends content and routing key to sockjs client
%% @since 2011-11-24 12:40
%%
-spec send(#child{}, binary(), binary() | string()) -> #child{}.

send(#child{id=Id, id_s=undefined} = St, _Key, _Body) ->
    erpher_et:trace_me(48, ?MODULE, Id, 'send to undefined uid', _Body),
    St;
send(#child{id=Id, id_s=User, sjs_conn=Conn, sjs_sid=Sid} = St, Key, Body) ->
    Content = get_json_body(Body),
    mpln_p_debug:pr({?MODULE, 'send', ?LINE, Id, User, Sid, Conn,
                    Key, Body, Content}, St#child.debug, run, 5),
    Users = ecomet_data_msg:get_users(Content),
    Message = ecomet_data_msg:get_message(Content),
    case is_user_allowed(User, Users) of
        true ->
            mpln_p_debug:pr({?MODULE, 'send', ?LINE, allowed, Id, Sid, Message},
                            St#child.debug, run, 4),
            Data = [{<<"event">>, Key},
                {<<"user">>, User},
                {<<"message">>, Message}],
            % encoding hack here is necessary, because current socket-io
            % backend (namely, misultin) crashes on encoding cyrillic utf8.
            % Cowboy isn't tested yet for this.
            %Json = sockjs_util:encode({Data}), % for jiffy
            Json = mochijson2:encode(Data), % for mochijson2
            %Json = mochijson2:encode(Data),
            Json_b = iolist_to_binary(Json),
            %Json_s = binary_to_list(Json_b),
            mpln_p_debug:pr({?MODULE, 'send', ?LINE, json, Id, Sid, Data,
                             Json, Json_b}, St#child.debug, run, 6),
            Msg = Json_b, % for sockjs
            erpher_et:trace_me(40, ?MODULE, Id, 'send', Msg),
            sockjs:send(Msg, Conn),
            St;
        false ->
            St
    end.

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
%%
%% @doc checks if current user is in user list. Empty or undefined list of
%% users means "allow".
%%
is_user_allowed(_User, []) ->
    true;
is_user_allowed(_User, undefined) ->
    true;
is_user_allowed(User, Users) ->
    lists:member(User, Users).

%%-----------------------------------------------------------------------------
%%
%% @doc makes request to auth server. Returns http answer, auth url, auth cookie
%%
-spec send_auth_req(#child{}, list()) -> {{ok, any()} | {error, any()},
                                          binary(), binary(),
                                          undefined | binary()}.

send_auth_req(#child{id=Id} = St, Info) ->
    Url0 = ecomet_data_msg:get_auth_url(Info),
    Cookie = ecomet_data_msg:get_auth_cookie(Info),
    {Url, Host} = find_auth_host(St, Url0),
    Res = proceed_http_auth_req(St, Url, Cookie, Host),
    mpln_p_debug:pr({?MODULE, 'send_auth_req res', ?LINE, Id, Res},
                    St#child.debug, http, 6),
    {Res, Url, Cookie, Host}.

%%-----------------------------------------------------------------------------
%%
%% @doc extracts auth data from url and returns cleaned url and auth host
%% (login field of auth data)
%%
-spec find_auth_host(#child{}, binary()) -> {binary(), undefined | binary()}.

find_auth_host(#child{user_data_as_auth_host=true} = St, Url) ->
    Ustr = mpln_misc_web:make_string(Url),
    case http_uri:parse(Ustr) of
        {error, _Reason} ->
            {Url, undefined};
        {_, User_info, _, _, _, _} when User_info == "" ->
            {Url, undefined};
        {Scheme, User_info, Host, Port, Path, Query} ->
            Scheme_str = [atom_to_list(Scheme), "://"],
            Port_str = integer_to_list(Port),
            Str = [Scheme_str, "", Host, ":", Port_str, Path, Query],
            Res_url = unicode:characters_to_binary(Str),
            Auth_host = make_auth_host(User_info),
            mpln_p_debug:pr({?MODULE, 'find_auth_host', ?LINE,
                             Res_url, Auth_host}, St#child.debug, http, 4),
            {Res_url, Auth_host}
        end;

find_auth_host(_, Url) ->
    {Url, undefined}.
    
%%-----------------------------------------------------------------------------
%%
%% @doc splits input string with ":" and returns first token as a binary
%%
make_auth_host(Str) ->
    case string:tokens(Str, ":") of
        [H|_] ->
            iolist_to_binary(H);
        _ ->
            <<>>
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc creates http request (to perform client's auth on auth server),
%% sends it to a server, returns response
%%
proceed_http_auth_req(#child{id=Id, http_connect_timeout=Conn_t,
                             http_timeout=Http_t} = St, Url, Cookie, Host) ->
    Hdr = make_header(Cookie, Host),
    Req = make_req(mpln_misc_web:make_string(Url), Hdr),
    mpln_p_debug:pr({?MODULE, 'proceed_http_auth_req', ?LINE, Id, Req},
                    St#child.debug, http, 4),
    Res = httpc:request(post, Req,
                  [{timeout, Http_t}, {connect_timeout, Conn_t}],
                  [{body_format, binary}]),
    mpln_p_debug:pr({?MODULE, 'proceed_http_auth_req result', ?LINE, Id, Res},
                    St#child.debug, http, 5),
    Res.

%%-----------------------------------------------------------------------------
make_header(Cookie, undefined) ->
    make_header2(Cookie, []);

make_header(Cookie, Host) ->
    Hstr = mpln_misc_web:make_string(Host),
    make_header2(Cookie, [{"Host", Hstr}]).

make_header2(Cookie, List) ->
    Str = mpln_misc_web:make_string(Cookie),
    [{"cookie", Str}, {"User-Agent","erpher"} | List].

%%-----------------------------------------------------------------------------
make_req(Url, Hdr) ->
    {Url, Hdr, "application/x-www-form-urlencoded", <<>>}.

%%-----------------------------------------------------------------------------
%%
%% @doc checks auth data received from auth server
%%
proceed_auth_msg(#child{id=Id} = St, {ok, Info}, Data) ->
    erpher_et:trace_me(35, ?MODULE, Id, 'auth http ok', Data),
    {Uid, Exch} = process_auth_resp(St, Info),
    Type = ecomet_data_msg:get_type(Data),
    proceed_type_msg(St#child{id_s=Uid}, Exch, Type, Data, Info);

proceed_auth_msg(#child{id=Id,
                        sio_auth_url=Url,
                        sio_auth_host=Host,
                        sio_auth_cookie=Cookie
                       } = St, {error, Reason}, _Data) ->
    erpher_et:trace_me(45, ?MODULE, Id, 'auth http error', Reason),
    Bin = mpln_misc_web:make_term2_binary(Reason),
    Short = mpln_misc_web:sub_bin(Bin),
    erpher_jit_log:add_jit_msg(St#child.jit_log_data, Id,
                               'auth', 3,
                               ['http_error', Url, Host, Cookie, Short]),
    mpln_p_debug:pr({?MODULE, proceed_auth_msg, ?LINE, error, Id, Reason},
                    St#child.debug, run, 1),
    ecomet_conn_server:stop(self()),
    St#child{jit_log_status=error, id_s = undefined}.

%%-----------------------------------------------------------------------------
%%
%% @doc prepares queues and bindings
%%
-spec proceed_type_msg(#child{}, use_current_exchange | binary(),
                       reauth | binary(),
                       any(),
                       tuple() | binary()) -> #child{}.

proceed_type_msg(#child{id=Id, id_s=undefined,
                        sio_auth_url=Url,
                        sio_auth_host=Host,
                        sio_auth_cookie=Cookie
                       } = St, _, _, Data, Http_resp) ->
    mpln_p_debug:pr({?MODULE, proceed_type_msg, ?LINE, 'undefined id_s', Id},
                    St#child.debug, run, 2),
    erpher_et:trace_me(48, ?MODULE, Id, 'undefined user id',
        {Url, Host, Cookie, Http_resp, Data}),
    Short_rb = mpln_misc_web:make_term2_short_bin(Data),
    Short_http = mpln_misc_web:make_term2_short_bin(Http_resp),
    erpher_jit_log:add_jit_msg(St#child.jit_log_data, Id,
                               'auth', 3,
                               ['error', 'undefined user id',
                                Url, Host, Cookie, Short_rb, Short_http]),
    ecomet_conn_server:stop(self()),
    St#child{jit_log_status=error};

proceed_type_msg(#child{id=Id, conn=Conn, no_local=No_local,
                        routes=Routes} = St, Exchange, 'reauth', _Data, _) ->
    mpln_p_debug:pr({?MODULE, proceed_type_msg, ?LINE, reauth, Id, Exchange,
                     Routes}, St#child.debug, run, 5),
    erpher_et:trace_me(30, ?MODULE, Id, 'reauth', {Exchange, Routes}),
    New = ecomet_rb:prepare_queue_rebind(Conn, Exchange, Routes, [], No_local),
    St#child{conn = New};

proceed_type_msg(#child{id=Id, conn=Conn, no_local=No_local,
                        routes=Old_routes} = St, Exchange, <<"subscribe">>,
                 Data, _) ->
    Routes = ecomet_data_msg:get_routes(Data, []),
    erpher_et:trace_me(30, ?MODULE, Id, 'subscribe',
        {Exchange, Routes, Old_routes}),
    mpln_p_debug:pr({?MODULE, proceed_type_msg, ?LINE, subscribe, Id,
                     Exchange, Old_routes, Routes, Data},
                    St#child.debug, run, 5),
    New = case Exchange of
              use_current_exchange ->
                  ecomet_rb:prepare_queue_add_bind(Conn, Routes, No_local);
              _ ->
                  ecomet_rb:prepare_queue_rebind(Conn, Exchange,
                                                 Old_routes, Routes, No_local)
          end,
    St#child{conn = New, routes = Routes ++ Old_routes};

proceed_type_msg(#child{id=Id,
                        sio_auth_url=Url,
                        sio_auth_host=Host,
                        sio_auth_cookie=Cookie
                       } = St, _Exch, _Other, Data, Http_resp) ->
    erpher_et:trace_me(50, ?MODULE, Id, 'undefined type message', _Other),
    Short_rb = mpln_misc_web:make_term2_short_bin(Data),
    Short_http = mpln_misc_web:make_term2_short_bin(Http_resp),
    erpher_jit_log:add_jit_msg(St#child.jit_log_data, Id,
                               'auth', 3,
                               ['warning', 'undefined type message',
                                Url, Host, Cookie, Short_rb, Short_http]),
    mpln_p_debug:pr({?MODULE, proceed_type_msg, ?LINE, other, Id,
                     _Exch, _Other}, St#child.debug, run, 2),
    St.

%%-----------------------------------------------------------------------------
%%
%% @doc decodes json http response, creates exchange response is success,
%% returns user_id and exchange
%%
-spec process_auth_resp(#child{},
                        {
                          {string(), list(), any()} | {integer(), any()},
                          any()
                        }) -> {integer() | undefined, binary()}.

process_auth_resp(St, {{_, 200, _} = _Sline, _Hdr, Body}) ->
    proceed_process_auth_resp(St, Body);
process_auth_resp(St, {200 = _Scode, Body}) ->
    proceed_process_auth_resp(St, Body);
process_auth_resp(_, _) ->
    {undefined, <<>>}.

%%-----------------------------------------------------------------------------
%%
%% @doc decodes json http response, creates exchange. Returns user_id and
%% exchange
%%
proceed_process_auth_resp(#child{id=Id} = St, Body) ->
    case get_json_body(Body) of
        undefined ->
            Bin = mpln_misc_web:make_term2_binary(Body),
            Short = mpln_misc_web:sub_bin(Bin),
            erpher_et:trace_me(50, ?MODULE, Id, json_error, Body),
            erpher_jit_log:add_jit_msg(St#child.jit_log_data, Id,
                                       'auth', 3,
                                       {'json_error', Short}),
            {undefined, <<>>};
        Data ->
            X = create_exchange(St, Data),
            Uid = ecomet_data_msg:get_user_id(Data),
            % uids MUST come as strings in data, so json decoder would
            % return them as binaries. So we make the current user id
            % a binary for later check for allowed users
            erpher_et:trace_me(30, ?MODULE, {Id, proceed_process_auth_resp},
                json_ok, Data),
            Uid_bin = mpln_misc_web:make_binary(Uid),
            {Uid_bin, X}
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc decodes json data
%%
get_json_body(Body) ->
    case catch mochijson2:decode(Body) of
        {ok, {List}} when is_list(List) ->
            List;
        {ok, Data} ->
            Data;
        {'EXIT', _Reason} ->
            undefined;
        Data ->
            Data
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc creates topic exchange with name tail defined in the input data
%%
create_exchange(#child{conn=Conn, exchange_base=Base} = St, Data) ->
    Acc = ecomet_data_msg:get_account(Data),
    Exchange = <<Base/binary, Acc/binary>>,
    mpln_p_debug:pr({?MODULE, 'create_exchange', ?LINE, Exchange},
                    St#child.debug, run, 3),
    ecomet_rb:create_exchange(Conn, Exchange, <<"topic">>),
    Exchange.

%%%----------------------------------------------------------------------------
%%% EUnit tests
%%%----------------------------------------------------------------------------
-ifdef(TEST).

get_json() ->
    "{\"userId\":123,\"account\":\"acc_name_test\"}"
    .

get_json_test() ->
    B = get_json(),
    J0 = {struct,[{<<"userId">>,123},{<<"account">>,<<"acc_name_test">>}]},
    J1 = get_json_body(B),
    ?assert(J0 =:= J1).

get_auth_part() ->
    {<<"auth">>,
     [{<<"authUrl">>,<<"http://mdt-symfony/comet/auth">>},
      {<<"cookie">>,
       <<"socketio=websocket; PHPSESSID=qwerasdf45ty67u87i98o90p2d">>}]}.

get_msg() ->
    A = get_auth_part(),
    [{<<"type">>,<<"subscribe">>},
     {<<"routes">>,
      [<<"discuss.topic.comment.14">>,<<"user.live.notify">>]},
     A
    ].

get_auth_test() ->
    A0 = get_auth_part(),
    Data = get_msg(),
    A1b = ecomet_data_msg:get_auth_info(Data),
    A1 = {<<"auth">>, A1b},
    %?debugFmt("get_auth_test:~n~p~n~p~n~p~n", [A0, Data, A1]),
    ?assert(A0 =:= A1).

get_url_test() ->
    U0 = <<"http://mdt-symfony/comet/auth">>,
    Data = get_msg(),
    Info = ecomet_data_msg:get_auth_info(Data),
    U1 = ecomet_data_msg:get_auth_url(Info),
    %?debugFmt("get_url_test:~n~p~n~p~n", [U0, U1]),
    ?assert(U0 =:= U1).

get_cookie_test() ->
    C0 = <<"socketio=websocket; PHPSESSID=qwerasdf45ty67u87i98o90p2d">>,
    Data = get_msg(),
    Info = ecomet_data_msg:get_auth_info(Data),
    C1 = ecomet_data_msg:get_auth_cookie(Info),
    %?debugFmt("get_url_test:~n~p~n~p~n", [C0, C1]),
    ?assert(C0 =:= C1).

find_auth_host_test() ->
    St = #child{user_data_as_auth_host=true,
                debug=[]},
    Lst = [
           {
             <<"http://mdt-symfony/comet/auth">>, true,
             <<"http://mdt-symfony/comet/auth">>, undefined
            },
           {
             <<"http://mdt-symfony/comet/auth">>, false,
             <<"http://mdt-symfony/comet/auth">>, undefined
           },
           {
             <<"http://test.megaplan@mdt-symfony/comet/auth">>, true,
             <<"http://mdt-symfony:80/comet/auth">>, <<"test.megaplan">>
           },
           {
             <<"http://test.megaplan@mdt-symfony/comet/auth">>, false,
             <<"http://test.megaplan@mdt-symfony/comet/auth">>, undefined
           },
           {
             <<"http://test.megaplan#@mdt-symfony/comet/auth">>, true,
             <<"http://mdt-symfony:80/comet/auth">>, <<"test.megaplan#">>
           },
           {
             <<"http://test.megaplan#mdt-symfony/comet/auth">>, true,
             <<"http://test.megaplan#mdt-symfony/comet/auth">>, undefined
           }
          ],
    F = fun({Url, Flag, Url0, Hdr0} = _Item) ->
                Config = St#child{user_data_as_auth_host=Flag},
                Res = find_auth_host(Config, Url),
                %?debugFmt("find_auth_host_test:~n~p~n~p~n", [Item, Res]),
                ?assert({Url0, Hdr0} =:= Res)
        end,
    lists:foreach(F, Lst).

-endif.
%%-----------------------------------------------------------------------------
