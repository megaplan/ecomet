-module(ecomet_test).

-export([dup_message_to_rabbit/2]).

-include("ecomet.hrl").
-include("rabbit_session.hrl").

-ifdef(DUP_TEST).

%%-----------------------------------------------------------------------------
%%
%% @doc modifies data and sends it to amqp. Somewhat of a poor's human simulator
%% The code here is under ifdef. The DUP_TEST is defined in the makefile.
%%
-spec dup_message_to_rabbit(#child{}, binary()) -> #child{}.

dup_message_to_rabbit(#child{id=Id} = St, Data) ->
    mpln_p_debug:pr({?MODULE, dup_message_to_rabbit, ?LINE, Id, Data},
                    St#child.debug, rb_msg, 6),
    Base = if
               byte_size(Data) > 64 ->
                   <<"init_">>;
               true ->
                   Data
           end,
    Rstr = ecomet_data:gen_id(8),
    New = <<Base/binary, Rstr/binary>>,
    dup_send_msg_q(St, New).

%%-----------------------------------------------------------------------------
%%
%% @doc modified version of send_msg_q that doesn't do websocket unframe data
%%
dup_send_msg_q(#child{conn=Conn, event=Rt_key, id=Id, id_r=Corr}=St, Data) ->
    mpln_p_debug:pr({?MODULE, dup_send_msg_q, ?LINE, Id, Data, St},
                    St#child.debug, run, 6),
    mpln_p_debug:pr({?MODULE, dup_send_msg_q, ?LINE, Data},
                    St#child.debug, run, 6),
    ecomet_rb:send_message(Conn#conn.channel, Conn#conn.exchange,
                           Rt_key, Data, Corr),
    St.
%%-----------------------------------------------------------------------------

-else.

%%-----------------------------------------------------------------------------
dup_message_to_rabbit(St, _Data) ->
    St.

%%-----------------------------------------------------------------------------

-endif.
