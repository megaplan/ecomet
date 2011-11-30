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
-export([get_content_data/1]).
-export([create_exchange/3]).
-export([teardown_tags/1, teardown_queues/1]).
-export([prepare_queue_bind_many/3, prepare_queue_bind_many/4]).
-export([prepare_queue_bind_one/3]).

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
-spec create_exchange(#conn{}, binary(), binary()) -> any().

create_exchange(#conn{channel=Channel, ticket=Ticket}, Exchange, Type) ->
    ExchangeDeclare = #'exchange.declare'{ticket = Ticket,
        exchange = Exchange, type= Type,
        passive = false, durable = true,
        auto_delete=false, internal = false,
        nowait = false, arguments = []},
    #'exchange.declare_ok'{} = amqp_channel:call(Channel, ExchangeDeclare).

%%-----------------------------------------------------------------------------
%%
%% @doc cancels stored consumers
%% @since 2011-11-29 13:28
%%
-spec teardown_tags(#conn{}) -> any().

teardown_tags(#conn{channel = Channel, consumer_tags = Tags}) ->
    [cancel_consumer(Channel, X) || {_Q, X} <- Tags].

%%-----------------------------------------------------------------------------
%%
%% @doc cancels all the queues stored in #conn{}
%% @since 2011-11-30 12:03
%%
-spec teardown_queues(#conn{}) -> any().

teardown_queues(#conn{channel=Channel, consumer_tags=Tags, ticket=Ticket}) ->
    F = fun({Q, _}) ->
                D = #'queue.delete'{ticket = Ticket,
                                    queue = Q,
                                    if_unused = false,
                                    if_empty = false,
                                    nowait = false},
                #'queue.delete_ok'{} = amqp_channel:call(Channel, D)
        end,
    lists:map(F, Tags).

%%-----------------------------------------------------------------------------
%%
%% @doc cancels consumers, closes channel, closes connection
%% @since 2011-10-25 13:30
%%
-spec teardown(#conn{}) -> ok.

teardown(#conn{connection = Connection, channel = Channel} = Conn) ->
    teardown_tags(Conn),
    amqp_channel:close(Channel),
    amqp_connection:close(Connection).

%%-----------------------------------------------------------------------------
%%
%% @doc cancels consumer, closes channel, closes connection
%% @since 2011-10-25 13:30
%%
-spec teardown_conn(#conn{}) -> ok.

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
%% @doc creates a queue, binds it to many routing keys, returns
%% conn record with queue and consumer tags added
%% @since 2011-11-29 14:10
%%
-spec prepare_queue_bind_many(#conn{}, binary(), [binary()], boolean()) ->
                                     #conn{}.

prepare_queue_bind_many(Conn, Exchange, Keys, No_local) ->
    prepare_queue_bind_many(Conn#conn{exchange=Exchange}, Keys, No_local).

-spec prepare_queue_bind_many(#conn{}, [binary()], boolean()) -> #conn{}.

prepare_queue_bind_many(#conn{channel=Channel, consumer_tags=Tags} = Conn,
                        Keys, No_local) ->
    Queue = create_queue(Conn),
    F = fun(K) ->
                bind_queue(Conn, Queue, K)
        end,
    lists:foreach(F, Keys),
    Tag = setup_consumer(Channel, Queue, No_local),
    Conn#conn{consumer_tags = [{Queue, Tag} | Tags]}.

%%-----------------------------------------------------------------------------
%%
%% @doc creates a queue, binds it to a routing key, returns
%% conn record with queue and consumer tag added
%% @since 2011-11-29 14:10
%%
-spec prepare_queue_bind_one(#conn{}, binary(), boolean()) -> #conn{}.

prepare_queue_bind_one(Conn, Key, No_local) ->
    prepare_queue_bind_many(Conn, [Key], No_local).

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
%%
%% @doc creates queue, binds it to routing key
%% @since 2011-10-25 14:40
%%
-spec create_queue(#conn{}) -> binary().

create_queue(#conn{channel=Channel, ticket=Ticket}) ->

    QueueDeclare = #'queue.declare'{ticket = Ticket,
        passive = false, durable = true,
        exclusive = true, auto_delete = false,
        nowait = false, arguments = []},
    #'queue.declare_ok'{queue = Q} = amqp_channel:call(Channel, QueueDeclare),
    Q.

%%-----------------------------------------------------------------------------
%%
%% @doc bind queue to the binding key
%%
bind_queue(#conn{channel=Channel, exchange=X, ticket=Ticket}, Queue,
              Bind_key) ->
    QueueBind = #'queue.bind'{ticket = Ticket,
        exchange = X,
        queue = Queue,
        routing_key = Bind_key,
        nowait = false, arguments = []},
    #'queue.bind_ok'{} = amqp_channel:call(Channel, QueueBind).

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

%%-----------------------------------------------------------------------------
