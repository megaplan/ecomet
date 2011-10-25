%%%
%%% mcom_rb: RabbitMQ interaction
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
%%% @since 2011-10-25 13:30
%%% @license MIT
%%% @doc RabbitMQ interaction
%%%

-module(mcom_rb).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include_lib("amqp_client.hrl").
-include("rabbit_session.hrl").

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([start/1]).
-export([teardown/1, send_reply/4]).
-export([send_ack/2]).
-export([prepare_queue/2]).

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
%%
%% @doc does all the AMQP client preparations, namely: connection, channel,
%% queue, exchange, binding.
%% @since 2011-07-15
%%
-spec start(#rses{}) -> {ok, #conn{}}.

start(Rses) ->
    Host = Rses#rses.host,
    Port = Rses#rses.port,
    User = Rses#rses.user,
    Password = Rses#rses.password,
    Vhost = Rses#rses.vhost,
    X = Rses#rses.exchange,
    Xtype = Rses#rses.exchange_type,
    {ok, Connection} = amqp_connection:start(network, #amqp_params{
        username = User,
        password = Password,
        host = Host,
        port = Port,
        virtual_host = Vhost
        }),
    {ok, Channel} = amqp_connection:open_channel(Connection),
    Access = #'access.request'{realm = Vhost,
        exclusive = false,
        passive = true,
        active = true,
        write = true,
        read = true},
    #'access.request_ok'{ticket = Ticket} = amqp_channel:call(Channel, Access),

    ExchangeDeclare = #'exchange.declare'{ticket = Ticket,
        exchange = X, type= Xtype,
        passive = false, durable = true,
        auto_delete=false, internal = false,
        nowait = false, arguments = []},
    #'exchange.declare_ok'{} = amqp_channel:call(Channel, ExchangeDeclare),

    {ok, #conn{channel=Channel,
        connection=Connection,
        exchange=X,
        ticket=Ticket}
    }.

%%-----------------------------------------------------------------------------
%%
%% @doc cancels consumer, closes channel, closes connection
%% @since 2011-07-15
%%
teardown(#conn{connection = Connection,
        channel = Channel,
        consumer_tag = ConsumerTag}) ->
    cancel_consumer(Channel, ConsumerTag),
    amqp_channel:close(Channel),
    amqp_connection:close(Connection)
.
%%-----------------------------------------------------------------------------
%%
%% @doc sends reply with particular routing key
%% @since 2011-07-15
%%
send_reply(Channel, X, Rt_key, Payload) ->
    io:format("send_reply rt, payload:~n~p~n~p~n", [Rt_key, Payload]),
    send_message(Channel, X, Rt_key, Payload)
.
%%-----------------------------------------------------------------------------
%%
%% @doc sends acknowledge for AMQP message.
%% @since 2011-07-15
%%
-spec send_ack(#conn{}, any()) -> any().

send_ack(Conn, Tag) ->
    Channel = Conn#conn.channel,
    amqp_channel:call(Channel, #'basic.ack'{delivery_tag = Tag}).

%%-----------------------------------------------------------------------------
%%
%% @doc creates queue, binds it to routing key
%% @since 2011-10-25 14:40
%%
prepare_queue(#conn{channel=Channel, exchange=X, ticket=Ticket}, Bind_key) ->

    QueueDeclare = #'queue.declare'{ticket = Ticket,
        passive = false, durable = true,
        exclusive = true, auto_delete = true,
        nowait = false, arguments = []},
    #'queue.declare_ok'{queue = Q} = amqp_channel:call(Channel, QueueDeclare),

    QueueBind = #'queue.bind'{ticket = Ticket,
        exchange = X,
        queue = Q,
        routing_key = Bind_key,
        nowait = false, arguments = []},
    #'queue.bind_ok'{} = amqp_channel:call(Channel, QueueBind),

    {ok, ConsumerTag} = setup_consumer(Channel, Q),
    ConsumerTag.

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
%%
%% @doc publishes AMQP message with given payload to exchange
%% @since 2011-07-15
%%
-spec send_message(any(), any(), any(), any()) -> ok.

send_message(Channel, X, RoutingKey, Payload) ->
    Publish = #'basic.publish'{exchange = X, routing_key = RoutingKey},
    amqp_channel:cast(Channel, Publish, #amqp_msg{payload = Payload}).

%%-----------------------------------------------------------------------------
%%
%% @doc setups consumer for given queue at given exchange
%% @since 2011-07-15
%%
setup_consumer(Channel, Q) ->
    BasicConsume = #'basic.consume'{queue = Q, no_ack = false },
    #'basic.consume_ok'{consumer_tag = ConsumerTag}
        = amqp_channel:subscribe(Channel, BasicConsume, self()),
    ConsumerTag
.
%%-----------------------------------------------------------------------------
%%
%% @doc cancels consumer
%% @since 2011-07-15
%%
cancel_consumer(Channel, ConsumerTag) ->
    % After the consumer is finished interacting with the queue,
    % it can deregister itself
    BasicCancel = #'basic.cancel'{consumer_tag = ConsumerTag,
        nowait = false},
    #'basic.cancel_ok'{consumer_tag = ConsumerTag} =
        amqp_channel:call(Channel,BasicCancel)
.
%%-----------------------------------------------------------------------------
