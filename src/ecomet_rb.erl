%%%
%%% ecomet_rb: RabbitMQ interaction
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

-module(ecomet_rb).

%%%----------------------------------------------------------------------------
%%% Includes
%%%----------------------------------------------------------------------------

-include_lib("amqp_client.hrl").
-include("rabbit_session.hrl").

%%%----------------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------------

-export([start/1]).
-export([teardown/1, teardown_conn/1, send_message/4, send_message/5]).
-export([send_ack/2]).
-export([prepare_queue/3]).
-export([prepare_queue_conn/4]).
-export([get_content_data/1]).
-export([cancel_consumer/2]).
-export([create_exchange/3]).

%%%----------------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------------
%%
%% @doc extract payload and id from amqp message
%% @since 2011-10-27 17:50
%%
-spec get_content_data(#amqp_msg{}) -> {binary(), binary()}.

get_content_data(Content) ->
    Payload = Content#amqp_msg.payload,
    Id = get_prop_id(Content#amqp_msg.props),
    {Payload, Id}.

%%-----------------------------------------------------------------------------
%%
%% @doc does all the AMQP client preparations, namely: connection, channel,
%% queue, exchange, binding.
%% @since 2011-10-25 13:30
%%
-spec start(#rses{}) -> #conn{}.

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

    create_exchange(#conn{ticket=Ticket, channel=Channel}, X, Xtype),

    #conn{channel=Channel,
        connection=Connection,
        exchange=X,
        ticket=Ticket}.

%%-----------------------------------------------------------------------------
create_exchange(#conn{channel=Channel, ticket=Ticket}, Exchange, Type) ->
    ExchangeDeclare = #'exchange.declare'{ticket = Ticket,
        exchange = Exchange, type= Type,
        passive = false, durable = true,
        auto_delete=false, internal = false,
        nowait = false, arguments = []},
    #'exchange.declare_ok'{} = amqp_channel:call(Channel, ExchangeDeclare).

%%-----------------------------------------------------------------------------
%%
%% @doc cancels consumers, closes channel, closes connection
%% @since 2011-10-25 13:30
%%
teardown(#conn{connection = Connection,
        channel = Channel,
        consumer_tags = Tags}) ->
    [cancel_consumer(Channel, X) || X <- Tags],
    amqp_channel:close(Channel),
    amqp_connection:close(Connection)
.
%%-----------------------------------------------------------------------------
%%
%% @doc cancels consumer, closes channel, closes connection
%% @since 2011-10-25 13:30
%%
teardown_conn(#conn{connection = Connection, channel = Channel}) ->
    amqp_channel:close(Channel),
    amqp_connection:close(Connection).

%%-----------------------------------------------------------------------------
%%
%% @doc sends acknowledge for AMQP message.
%% @since 2011-10-25 13:30
%%
-spec send_ack(#conn{}, any()) -> any().

send_ack(Conn, Tag) ->
    Channel = Conn#conn.channel,
    amqp_channel:call(Channel, #'basic.ack'{delivery_tag = Tag}).

%%-----------------------------------------------------------------------------
%%
%% @doc prepares AMQP message with given payload and calls publishing
%% @since 2011-10-25 13:30
%%
-spec send_message(any(), binary(), binary(), binary()) -> ok.

send_message(Channel, X, RoutingKey, Payload) ->
    Msg = #amqp_msg{payload = Payload},
    send_message2(Channel, X, RoutingKey, Msg).

%%-----------------------------------------------------------------------------
%%
%% @doc prepares AMQP message with given payload and id
%% and calls publishing
%% @since 2011-10-25 13:30
%%
-spec send_message(any(), binary(), binary(), binary(), binary()) -> ok.

send_message(Channel, X, RoutingKey, Payload, Id) ->
    Props = make_prop_id(Id),
    Msg = #amqp_msg{payload = Payload, props = Props},
    send_message2(Channel, X, RoutingKey, Msg).

%%-----------------------------------------------------------------------------
%%
%% @doc creates queue, binds it to routing key, returns a conn record
%% with the new consumer tag added
%% @since 2011-11-25 13:08
%%
-spec prepare_queue_conn(#conn{}, binary(), binary(), boolean()) -> #conn{}.

prepare_queue_conn(#conn{consumer_tags=List} = Conn, Exchange, Key, No_local) ->
    Tag = prepare_queue(Conn#conn{exchange=Exchange}, Key, No_local),
    Conn#conn{consumer_tags = [Tag | List], exchange = Exchange}.

%%-----------------------------------------------------------------------------
%%
%% @doc creates queue, binds it to routing key
%% @since 2011-10-25 14:40
%%
-spec prepare_queue(#conn{}, binary(), boolean()) -> binary().

prepare_queue(#conn{channel=Channel, exchange=X, ticket=Ticket},
              Bind_key, No_local) ->

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

    setup_consumer(Channel, Q, No_local).

%%-----------------------------------------------------------------------------
%%
%% @doc cancels consumer
%% @since 2011-10-25 13:30
%%
cancel_consumer(_Channel, undefined) ->
    ok;
cancel_consumer(Channel, ConsumerTag) ->
    % After the consumer is finished interacting with the queue,
    % it can deregister itself
    BasicCancel = #'basic.cancel'{consumer_tag = ConsumerTag,
        nowait = false},
    #'basic.cancel_ok'{consumer_tag = ConsumerTag} =
        amqp_channel:call(Channel,BasicCancel).

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
%%
%% @doc setups consumer for given queue at given exchange
%% Rabbit ignores no_local at the moment, so it is handled in our connection
%% handler later
%% @since 2011-10-25 13:30
%%
-spec setup_consumer(any(), any(), boolean()) -> any().

setup_consumer(Channel, Q, No_local) ->
    BasicConsume = #'basic.consume'{queue = Q, no_ack = false,
                                    no_local = No_local
                                   },
    #'basic.consume_ok'{consumer_tag = ConsumerTag}
        = amqp_channel:subscribe(Channel, BasicConsume, self()),
    ConsumerTag
.
%%-----------------------------------------------------------------------------
%%
%% @doc publishes supplied message to amqp channel
%%
send_message2(Channel, X, RoutingKey, Msg) ->
    Publish = #'basic.publish'{exchange = X, routing_key = RoutingKey},
    amqp_channel:cast(Channel, Publish, Msg).

%%-----------------------------------------------------------------------------
%%
%% @doc creates amqp basic property with given id
%%
-spec make_prop_id(binary()) -> #'P_basic'{}.

make_prop_id(Id) ->
    #'P_basic'{correlation_id = Id}.

%%-----------------------------------------------------------------------------
%%
%% @doc extracts id from amqp basic property
%%
-spec get_prop_id(#'P_basic'{}) -> binary().

get_prop_id(Props) ->
    Props#'P_basic'.correlation_id.

%%-----------------------------------------------------------------------------
