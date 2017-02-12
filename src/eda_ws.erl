%%%-------------------------------------------------------------------
%%% @author Stefan Hagdahl
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 08. Feb 2017 19:11
%%%-------------------------------------------------------------------
-module(eda_ws).
-export([start/0]).

-define(STATE, #{seq_nr => 0}).

-include("eda_ws.hrl").

%% eda_ws:start().
start() ->
    application:ensure_all_started(gun),
    {ok, GatewayConnPid} = gun:open(?DISCORDGATEWAYURL,
                                    ?DISCORDGATEWAYPORT,
                                    #{protocols=>[http],
                                      trace=>false,
                                      ws_opts=>#{compress=>true}}),

    {ok, RestApiConnPid} = gun:open(?DISCORDRESTAPIURL,
                                    ?DISCORDRESTAPIPORT,
                                    #{protocols=>[http],
                                      trace=>false}),

    receive_msg(GatewayConnPid, RestApiConnPid, ?STATE).

receive_msg(GatewayConnPid, RestApiConnPid, #{seq_nr := SequenceNumber}=State) ->
    receive
        {gun_up, GatewayConnPid, Protocol} ->
            io:format("receive conenction up for Gateway protocol: ~p~n", [Protocol]),
            gun:ws_upgrade(GatewayConnPid,"/?v=6&encoding=json"),
            receive_msg(GatewayConnPid, RestApiConnPid, State);
        {gun_up, RestApiConnPid, Protocol} ->
            io:format("receive conenction up for RestApi protocol: ~p~n", [Protocol]),
            receive_msg(GatewayConnPid, RestApiConnPid, State);
        {gun_data, RestApiConnPid, StreamRef, fin, _} ->
            gun:cancel(RestApiConnPid, StreamRef),
            receive_msg(GatewayConnPid, RestApiConnPid, State);
        {gun_response, _, _, _, _Status, Headers} ->
            io:format("Recieved message:~n~p~n", [Headers]),
            receive_msg(GatewayConnPid, RestApiConnPid, State);
        {gun_ws, GatewayConnPid, Frame} ->
            handle_frame(GatewayConnPid, RestApiConnPid, Frame),
            receive_msg(GatewayConnPid, RestApiConnPid, State);
        {gun_error, _, _, Reason} ->
            gun:close(GatewayConnPid),
            gun:close(RestApiConnPid),
            exit(Reason);
        {update_seq, NewSequenceNumber} ->
            receive_msg(GatewayConnPid, RestApiConnPid, State#{seq_nr => NewSequenceNumber});
        {heartbeat, HeartbeatInterval} ->
            Msg = create_discord_msg(?HEARTBEAT, SequenceNumber),
            io:format("Send Msg:~p~n", [Msg]),
            gun:ws_send(GatewayConnPid, Msg),
            create_heartbeat_timer(HeartbeatInterval),
            receive_msg(GatewayConnPid, RestApiConnPid, State);
        Event ->
            io:format("Received unknown message:~n~p~n", [Event]),
            receive_msg(GatewayConnPid, RestApiConnPid, State)
    after 120000 ->
        gun:close(GatewayConnPid),
        gun:close(RestApiConnPid),
        exit(timeout)
    end,
    gun:close(GatewayConnPid).

create_discord_msg(?HEARTBEAT, SequenceNumber) ->
    {text, jiffy:encode(#{?OPCODE => ?HEARTBEAT,
                          ?EVENTDATA => SequenceNumber})};
create_discord_msg(?IDENTIFY, _) ->
    GatewayIdentifyProperties = ?GATEWAYIDENTIFYPROPERTIES(<<"linux">>, <<"discord_bot_erl">>, <<"discord_bot_erl">>, <<"">>, <<"">>),
    {text, jiffy:encode(#{?OPCODE => ?IDENTIFY,
                          ?EVENTDATA => ?GATEWAYIDENTIFY(?BOTTOKEN, GatewayIdentifyProperties, false, 250)})}.

handle_frame(GatewayConnPid, RestApiConnPid, {text, BitString})
    when is_bitstring(BitString) ->
    io:format("BitString:~p~n", [BitString]),
    case jiffy:decode(BitString, [return_maps]) of
        PayloadStruct when is_map(PayloadStruct) ->
            parse_discord_gateway_payload(PayloadStruct, GatewayConnPid, RestApiConnPid);
        Something ->
            io:format("Problem decoding BitString:~p~nEnded up with Something:~p~n", [BitString,Something])
    end.

parse_discord_gateway_payload(#{?EVENTDATA := #{?HEARTBEATINTERVAL := HeartbeatInterval}, ?OPCODE := ?HELLO},
                              GatewayConnPid, _RestApiConnPid) ->
    io:format("Received HELLO from discord with heartbeat interval at ~p milliseconds~n", [HeartbeatInterval]),
    create_heartbeat_timer(HeartbeatInterval),
    Msg = create_discord_msg(?IDENTIFY, 0),
    io:format("Send Msg:~p~n", [Msg]),
    gun:ws_send(GatewayConnPid, Msg);
parse_discord_gateway_payload(#{?OPCODE := ?DISPATCH, ?EVENTNAME := ?EVENTMESSAGECREATE,
                                ?EVENTDATA := EventData, ?SEQUENCENUMBER := SequenceNumber},
                              _GatewayConnPid, RestApiConnPid) ->
    io:format("Message Create received:~p~n", [EventData]),
    self() ! {update_seq, SequenceNumber},
    act_on(?EVENTMESSAGECREATE, EventData, RestApiConnPid, SequenceNumber);
parse_discord_gateway_payload(#{?OPCODE := ?DISPATCH, ?EVENTNAME := EventName,
                                ?SEQUENCENUMBER := SequenceNumber, ?EVENTDATA := EventData}, _GatewayConnPid, _RestApiConnPid) ->
    io:format("Event (~p) receive:~p~n", [EventName, EventData]),
    self() ! {update_seq, SequenceNumber};
parse_discord_gateway_payload(#{?OPCODE := OPCode, ?EVENTNAME := EventName,
                                ?EVENTDATA := EventData, ?SEQUENCENUMBER := SequenceNumber}, _GatewayConnPid, _RestApiConnPid) ->
    io:format("Receive unknown payload~n"
              "OPCode:~p~n"
              "EventName:~p~n"
              "EventData:~p~n"
              "SequenceNumber:~p~n",
              [OPCode, EventName, EventData, SequenceNumber]),
    self() ! {update_seq, SequenceNumber}.

create_heartbeat_timer(HeartbeatInterval) ->
    case timer:send_after(HeartbeatInterval, {heartbeat, HeartbeatInterval}) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            io:format("Unable to create time for heartbeat interval because of reason:~p~n", [Reason]),
            ok
    end.

act_on(?EVENTMESSAGECREATE, #{<<"content">> := Content, <<"channel_id">> := ChannelId}, RestApiConnPid, _SequenceNumber) ->
    case Content of
        <<"!test">> ->
            Body = jiffy:encode(#{<<"content">> => <<"replying to request">>}),
            Path = ?API ++ ?CHANNELS(erlang:bitstring_to_list(ChannelId)) ++ ?MESSAGES,
            StreamRef = gun:post(RestApiConnPid, Path,
                                 [{<<"content-type">>, "application/json"},
                                  {<<"Authorization">>,"Bot Mjc4OTIzNzgzNjYwNzY1MjA2.C3zfzQ.Ikm_voH_3TRddb2NelL2NN-3YYc"}]),
            gun:data(RestApiConnPid, StreamRef, fin, Body),
            io:format("Sent Body:~p to Path:~p~n", [Body, Path]);
        Content ->
            ok
    end,
    ok.