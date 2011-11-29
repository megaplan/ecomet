%%%
%%% ecomet_conn_server_sio: miscellaneous functions for ecomet connection server
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
%%% @since 2011-11-24 12:40
%%% @license MIT
%%% @doc miscellaneous functions for ecomet connection server
%%%

-module(ecomet_conn_server_sio).

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([process_sio/2]).
-export([send/3]).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include_lib("socketio.hrl").
-include("ecomet_child.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
%%
%% @doc processes data received from socket-io
%%
-spec process_sio(#child{}, #msg{}) -> #child{}.

process_sio(St, #msg{content=Data}) ->
    Auth = ecomet_data_msg:get_auth_info(Data),
    Res_auth = do_auth(St, Auth),
    case Res_auth of
        {ok, Info} ->
            {Uid, Exch} = process_auth_resp(St, Info),
            Type = ecomet_data_msg:get_type(Data),
            proceed_type_msg(St#child{id_q=Uid}, Exch, Type, Data);
        {error, _Reason} ->
            St
    end.

%%-----------------------------------------------------------------------------
%%
%% @doc sends content and routing key to socket-io client
%%
-spec send(#child{}, binary(), binary() | string()) -> #child{}.

send(#child{sio_cli=Client} = St, Key, Content) ->
    Data = [{<<"event">>, Key}, {<<"message">>, Content}],
    Msg = #msg{json=true, content=Data},
    socketio_client:send(Client, Msg),
    St.

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
%%
%% @doc makes request to auth server. Returns http answer.
%%
-spec do_auth(#child{}, list()) -> {ok, any()} | {error, any()}.

do_auth(#child{http_connect_timeout=Conn_t, http_timeout=Http_t} = St, Info) ->
    Url = ecomet_data_msg:get_auth_url(Info),
    Cookie = ecomet_data_msg:get_auth_cookie(Info),
    Hdr = make_header(Cookie),
    Req = make_req(mpln_misc_web:make_string(Url), Hdr),
    mpln_p_debug:pr({?MODULE, 'do_auth', ?LINE, Req}, St#child.debug, run, 4),
    Res = http:request(post, Req,
        [{timeout, Http_t}, {connect_timeout, Conn_t}],
        []),
    mpln_p_debug:pr({?MODULE, 'do_auth res', ?LINE, Res},
                    St#child.debug, run, 5),
    Res.

%%-----------------------------------------------------------------------------
make_header(Cookie) ->
    Str = mpln_misc_web:make_string(Cookie),
    [
     {"cookie", Str}
     ].

%%-----------------------------------------------------------------------------
make_req(Url, Hdr) ->
    {Url, Hdr, "application/x-www-form-urlencoded", <<>>}.

%%-----------------------------------------------------------------------------
%%
%% @doc prepares queues and bindings
%%
-spec proceed_type_msg(#child{}, binary(), binary(), any()) -> #child{}.

proceed_type_msg(#child{id=Id, id_q=undefined} = St, _, _, _) ->
    mpln_p_debug:pr({?MODULE, "proceed_type_msg undefined id_q", ?LINE,
                     Id}, St#child.debug, run, 4),
    St;
proceed_type_msg(#child{conn=Conn, sio_cli=Client, no_local=No_local} = St,
                 Exchange, <<"subscribe">>, Data) ->
    mpln_p_debug:pr({?MODULE, proceed_type_msg, ?LINE, Exchange, Client, Data},
                    St#child.debug, run, 5),
    Routes = ecomet_data_msg:get_routes(Data),
    New = ecomet_rb:prepare_queue_bind_many(Conn, Exchange, Routes, No_local),
    St#child{conn = New};
proceed_type_msg(St, _Exch, _Other, _Data) ->
    mpln_p_debug:pr({?MODULE, 'proceed_type_msg other', ?LINE, _Exch, _Other},
                    St#child.debug, run, 2),
    St.

%%-----------------------------------------------------------------------------
%%
%% @doc decodes json http response, creates exchange, returns user_id and
%% exchange
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
proceed_process_auth_resp(St, Body) ->
    Data = get_json_body(Body),
    X = create_exchange(St, Data),
    {ecomet_data_msg:get_user_id(Data), X}.

%%-----------------------------------------------------------------------------
%%
%% @doc decodes json data
%%
get_json_body(Body) ->
    case catch mochijson2:decode(Body) of
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

-endif.
%%-----------------------------------------------------------------------------
