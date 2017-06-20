%%%-------------------------------------------------------------------
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%% Library to match Frame towards FrameSpec matches from subscriptions
%%%
%%% @end
%%% Created : 10. Feb 2017 14:04
%%%-------------------------------------------------------------------
-module(eda_frame_api).

-include("eda_frame.hrl").

%% API
-export([subscribe/1,
         subscribe/2,
         unsubscribe/1,
         unsubscribe/2,
         match/2,
         build_frame_spec/2,
         build_frame_spec/4,
         build_eda_frame/2,
         build_frame/2,
         build_frame/4]).

-export_type([frame_spec/0,
              frame/0,
              eda_frame/0,
              frame_event_name/0,
              frame_sequence_number/0,
              frame_event_data/0,
              frame_op_code/0,
              op_codes/0,
              event_names/0]).

-type frame_op_code() :: op_codes().
-type frame_event_name() :: event_names().
-type frame_sequence_number() :: integer().
-type frame_event_data() :: map() | integer().
-type frame() :: #{<<>> := frame_op_code(),
                   <<>> := frame_event_data(),
                   <<>> => frame_event_name(),
                   <<>> => frame_sequence_number()}.

-type frame_spec_op_code() :: op_codes() | '_'.
-type frame_spec_event_name() :: event_names() | '_'.
-type frame_spec_sequence_number() :: integer() | '_'.
-type frame_spec_event_data() :: map() | integer() | '_'.
-type frame_spec() :: #{<<>> => frame_spec_op_code() | '_',
                        <<>> => frame_spec_event_data() | '_',
                        <<>> => frame_spec_event_name() | '_',
                        <<>> => frame_spec_sequence_number()
                        | '_'}.

-type eda_frame() :: #{bot => pid() | atom(),
                       frame => frame() | frame_spec()}.

-type op_codes() :: ?OPCDispatch | ?OPCHeartbeat | ?OPCIdentify |
                    ?OPCStatusUpdate |
                    ?OPCVoiceStateUpdate | ?OPCVoiceServerPing | ?OPCResume |
                    ?OPCReconnect | ?OPCRequestGuildMembers |
                    ?OPCInvalidSession | ?OPCHello | ?OPCHeartbeatACK.

-type event_names() :: <<>>.

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Subscribe EdaFrameSpec for Process
%%
%% @end
%%--------------------------------------------------------------------
-spec(subscribe(EdaFrameSpec :: eda_frame_api:eda_frame()) ->
    ok | {error, Reason :: term()}).
subscribe(EdaFrameSpec) ->
    subscribe(EdaFrameSpec, self()).

-spec(subscribe(EdaFrameSpec :: eda_frame_api:eda_frame(), Pid :: pid()) ->
    ok | {error, Reason :: term()}).
subscribe(EdaFrameSpec, Pid) when is_map(EdaFrameSpec), is_pid(Pid) ->
    eda_frame_router:subscribe(EdaFrameSpec, Pid).

%%--------------------------------------------------------------------
%% @doc
%% Unsubscribe FrameSpec for Process
%%
%% @end
%%--------------------------------------------------------------------
-spec(unsubscribe(EdaFrameSpec :: eda_frame_api:eda_frame()) ->
    ok | {error, Reason :: term()}).
unsubscribe(EdaFrameSpec)
    when is_map(EdaFrameSpec) ->
    unsubscribe(EdaFrameSpec, self()).

-spec(unsubscribe(EdaFrameSpec :: eda_frame_api:eda_frame(), Pid :: pid()) ->
    ok | {error, Reason :: term()}).
unsubscribe(EdaFrameSpec, Pid)
    when is_map(EdaFrameSpec), is_pid(Pid) ->
    eda_frame_router:unsubscribe(EdaFrameSpec, Pid).

%%--------------------------------------------------------------------
%% @doc
%% Match Frame from Discord to FrameSpec
%%
%% @end
%%--------------------------------------------------------------------
-spec(match(EdaFrame :: eda_frame(), EdaFrameSpec :: eda_frame()) ->
    true | false).
match(Frame, FrameSpec)
    when is_map(Frame), is_map(FrameSpec) ->
    match_map(Frame, maps:to_list(FrameSpec)).

%%--------------------------------------------------------------------
%% @doc
%% Build FrameSpec
%%
%% @end
%%--------------------------------------------------------------------
-spec(build_frame_spec(OPCode :: frame_spec_op_code(),
                       EventData :: frame_spec_event_data()) ->
    {error, Reason :: term()} | frame_spec()).
build_frame_spec(OPCode, EventData) ->
    FrameInput = [{op_code, OPCode}, {event_data, EventData}],
    Valid = valid_frame_input(FrameInput, FrameInput),
    case Valid of
        ok ->
            #{?FrameOPCode => OPCode,
              ?FrameEventData => EventData};
        {error, Reason} ->
            lager:error("Error building FrameSpec with OPCode(~p), "
                        "EventData(~p) "
                        "Reason:~p",
                        [OPCode, EventData, Reason]),
            {error, "Error with one of the arguments"}
    end.


%% TODO: Check that if OPCode != 0 then EventName + SequenceNumber will make
%% FrameSpec useless as it will never match
%% https://discordapp.com/developers/docs/topics/gateway#gateway-op-codespayloads
-spec(build_frame_spec(OPCode :: frame_spec_op_code(),
                       EventData :: frame_spec_event_data(),
                       EventName :: frame_spec_event_name(),
                       SequenceNumber :: frame_spec_sequence_number()) ->
    {error, Reason :: term()} | frame_spec()).
build_frame_spec(OPCode, EventData, EventName, SequenceNumber) ->
    FrameInput = [{op_code, OPCode}, {event_data, EventData},
                  {event_name, EventName}, {sequence_number, SequenceNumber}],
    Valid = valid_frame_input(FrameInput, FrameInput),
    case Valid of
        ok ->
            #{?FrameOPCode => OPCode,
              ?FrameEventData => EventData,
              ?FrameEventName => EventName,
              ?FrameSequenceNumber => SequenceNumber};
        {error, Reason} ->
            lager:error("Error building FrameSpec with OPCode(~p), "
                        "EventData(~p), EventName(~p), SequenceNumber(~p) "
                        "Reason:~p",
                        [OPCode, EventData, EventName, SequenceNumber, Reason]),
            {error, "Error with one of the arguments"}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Build Eda Frame
%%
%% @end
%%--------------------------------------------------------------------
-spec(build_eda_frame(Bot :: pid() | atom(), Frame :: frame() | eda_frame()) ->
    {error, Reason :: term()} | eda_frame()).
build_eda_frame(Bot, Frame)
    when is_pid(Bot) orelse is_atom(Bot), is_map(Frame) ->
    #{bot => Bot,
      frame => Frame};
build_eda_frame(Bot, Frame) ->
    lager:error("Error building Eda Frame with Bot(~p), "
                "Frame(~p)",
                [Bot, Frame]),
    {error, "Error with one of the arguments"}.

%%--------------------------------------------------------------------
%% @doc
%% Build Frame
%%
%% @end
%%--------------------------------------------------------------------
-spec(build_frame(OPCode :: frame_op_code(),
                  EventData :: frame_event_data()) ->
    {error, Reason :: term()} | frame()).
build_frame(OPCode, EventData) ->
    FrameInput = [{op_code, OPCode}, {event_data, EventData}],
    %% TODO: Fix validator for frame as valid_frame_input accepts '_'
    Valid = valid_frame_input(FrameInput, FrameInput),
    case Valid of
        ok ->
            #{?FrameOPCode => OPCode,
              ?FrameEventData => EventData};
        {error, Reason} ->
            lager:error("Error building Frame with OPCode(~p), "
                        "EventData(~p) "
                        "Reason:~p",
                        [OPCode, EventData, Reason]),
            {error, "Error with one of the arguments"}
    end.


%% TODO: Check that if OPCode != 0 then EventName + SequenceNumber will make
%% FrameSpec useless as it will never match
%% https://discordapp.com/developers/docs/topics/gateway#gateway-op-codespayloads
-spec(build_frame(OPCode :: frame_op_code(),
                  EventData :: frame_event_data(),
                  EventName :: frame_event_name(),
                  SequenceNumber :: frame_sequence_number()) ->
    {error, Reason :: term()} | frame_spec()).
build_frame(OPCode, EventData, EventName, SequenceNumber) ->
    FrameInput = [{op_code, OPCode}, {event_data, EventData},
                  {event_name, EventName}, {sequence_number, SequenceNumber}],
    %% TODO: Fix validator for frame as valid_frame_input accepts '_'
    Valid = valid_frame_input(FrameInput, FrameInput),
    case Valid of
        ok ->
            #{?FrameOPCode => OPCode,
              ?FrameEventData => EventData,
              ?FrameEventName => EventName,
              ?FrameSequenceNumber => SequenceNumber};
        {error, Reason} ->
            lager:error("Error building Spec with OPCode(~p), "
                        "EventData(~p), EventName(~p), SequenceNumber(~p) "
                        "Reason:~p",
                        [OPCode, EventData, EventName, SequenceNumber, Reason]),
            {error, "Error with one of the arguments"}
    end.
%%%===================================================================
%%% Internal functions
%%%===================================================================
match_map(Frame, []) ->
    lager:debug("End of match FrameSpec towards Frame(~p)", [Frame]),
    true;
match_map(Frame, [{Key, Value}|Rest] = FrameSpec)
    when is_map(Frame) ->
    Match =
    case Frame of
        #{Key := FrameValue} when is_map(FrameValue), is_map(Value) ->
            lager:debug("Found Key(~p) from FrameSpec(~p) in Frame(~p)",
                        [Key, FrameSpec, Frame]),
            lager:debug("Progressing deeper as is_map(FrameValue) == true"),
            match_map(FrameValue, maps:to_list(Value));
        #{Key := FrameValue} when is_list(FrameValue), is_list(Value) ->
            lager:debug("Found Key(~p) from FrameSpec(~p) in Frame(~p)",
                        [Key, FrameSpec, Frame]),
            lager:debug("Progressing deeper as is_list(FrameValue) == true"),
            match_list(FrameValue, Value);
        #{Key := FrameValue} when Value == '_' ->
            lager:debug("Found Key(~p) and Value(~p) from "
                        "FrameSpec(~p) in Frame(~p)",
                        [Key, FrameValue, FrameSpec, Frame]),
            true;
        #{Key := Value} ->
            lager:debug("Found Key(~p) and Value(~p) from "
                        "FrameSpec(~p) in Frame(~p)",
                        [Key, Value, FrameSpec, Frame]),
            true;
        _ ->
            lager:debug("Frame(~p) didn't match FrameSpec(~p)",
                        [Frame, FrameSpec]),
            false
    end,
    case Match of
        true ->
            match_map(Frame, Rest);
        false ->
            false
    end.

match_list(Frame, []) ->
    lager:debug("End of match FrameSpec towards Frame(~p)", [Frame]),
    true;
match_list(Frame, ['_'|Rest]) ->
    lager:debug("Skipping FrameSpecValue('_') for Frame(~p)", [Frame]),
    match_list(Frame, Rest);
match_list(Frame, [Value|Rest])
    when is_list(Frame) ->
    lager:debug("Trying to match Value(~p) towards list of values(~p)",
                [Value, Frame]),
    case match_in_list(Value, Frame) of
        true ->
            match_list(Frame, Rest);
        false ->
            false
    end.

match_in_list(Match, []) ->
    lager:debug("No Match(~p) found in list", [Match]),
    false;
match_in_list(Value, [Value|_Rest]) ->
    lager:debug("Match(~p) found in list", [Value]),
    true;
match_in_list(Match, [Value|Rest])
    when is_map(Match), is_map(Value) ->
    lager:debug("Trying to match Value(~p) towards map(~p)", [Match, Value]),
    case match_map(Value, maps:to_list(Match)) of
        true ->
            true;
        false ->
            match_in_list(Match, Rest)
    end;
match_in_list(Match, [Value|Rest]) ->
    lager:debug("Value(~p) didn't match Match(~p), continuing with Rest(~p)",
                [Value, Match, Rest]),
    match_in_list(Match, Rest).

valid_frame_input([], _) ->
    ok;
valid_frame_input([{op_code, OPCode}|Rest], FrameInput) ->
    case {OPCode, ?OPCCheck} of
        {'_', _} ->
            valid_frame_input(Rest, FrameInput);
        {_, #{OPCode := true}} ->
            valid_frame_input(Rest, FrameInput);
        _ ->
            {error, {"Invalid type of OPCode:" ++ lists:concat([OPCode])}}
    end;
valid_frame_input([{event_name, EventName}|Rest], FrameInput) ->
    case {EventName, ?ENCheck} of
        {'_', _} ->
            valid_frame_input(Rest, FrameInput);
        {_, #{EventName := true}} ->
            valid_frame_input(Rest, FrameInput);
        _ ->
            {error, {"Invalid type of EventName:" ++ lists:concat([EventName])}}
    end;
valid_frame_input([{event_data, EventData}|Rest], FrameInput) ->
    lager:warning("No validation of EventData:~p", [EventData]),
    valid_frame_input(Rest, FrameInput);
valid_frame_input([{sequence_number, SequenceNumber}|Rest], FrameInput) ->
    lager:warning("No validation of SequenceNumber:~p", [SequenceNumber]),
    valid_frame_input(Rest, FrameInput).