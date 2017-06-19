%%%-------------------------------------------------------------------
%%% @author Stefan Hagdahl
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 09. Feb 2017 16:25
%%%-------------------------------------------------------------------
-module(eda_bot).
-author("Stefan Hagdahl").

-behaviour(gen_server).

%% API
-export([start_link/1,
         create_identify_message/1,
         send_frame/2]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%% include
-include("eda_bot.hrl").
-include("eda_frame.hrl").

-define(SERVER(Name), list_to_atom(lists:concat([?MODULE, "_", Name]))).

-record(state, {
    name :: string(),
    token :: string(),
    heartbeat :: integer(), %% milliseconds
    gateway_pid :: pid(),
    %% Indicate if ws is up or not
    ws_status = offline :: online | offline | upgrade,
    ws_seq_nr = 0 :: integer()
}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(Args :: map()) ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(#{name := Name, token := _Token, opts := _Options}=Args) ->
    gen_server:start_link({local, ?SERVER(Name)}, ?MODULE, Args, []);
start_link(Args) ->
    {error, {"Args doesn't contain name, token, opts keys", Args}}.

%%--------------------------------------------------------------------
%% @doc
%% Create identify message
%%
%% @end
%%--------------------------------------------------------------------
-spec(create_identify_message(Bot :: atom()) ->
    {ok, Frame :: eda_frame:frame()} | {error, Reason :: term()}).
create_identify_message(Bot) ->
    gen_server:call(?SERVER(Bot), {create_identify_message}).

%%--------------------------------------------------------------------
%% @doc
%% Send Frame
%%
%% @end
%%--------------------------------------------------------------------
-spec(send_frame(Bot :: atom(), Frame :: eda_frame:frame()) ->
    ok | {error, Reason :: term()}).
send_frame(Bot, Frame) ->
    gen_server:call(?SERVER(Bot), {send_frame, Frame}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init(#{name := Name, token := Token, opts := Opts}) ->
    %% TODO: Move to sup?
    application:ensure_all_started(gun),
    lager:start(),
    lager:set_loglevel(lager_console_backend, warning),
    BotHeartbeatId = lists:concat([eda_bot_heartbeat, "_", Name]),
    BotHeartbeatChildSpec = #{id => list_to_atom(BotHeartbeatId),
                              start => {eda_bot_heartbeat, start_link, [Name]},
                              restart => transient,
                              shutdown => 2000},
    %% TODO: If this process is started from same supervisor that will start
    %% eda_heartbeat then this next line will create a deadlock
    %% Echo bot should be started in eda_sup or eda_bot_sup together with
    %% eda_bot_heartbeat
    eda_sup:start_child(BotHeartbeatChildSpec),
    {ok, GatewayPid} = gun:open(?GatewayURL, ?GatewayPort,
                                #{protocols=>[http], trace=>false,
                                  ws_opts=>#{compress=>true}}),

    BotRestId = lists:concat([eda_rest, "_", Name]),
    BotRestChildSpec = #{id => list_to_atom(BotRestId),
                              start => {eda_rest, start_link,
                                        [#{name => Name, token => Token}]},
                              restart => transient,
                              shutdown => 2000},
    eda_sup:start_child(BotRestChildSpec),
    consider_tracing(self(), Opts),
    {ok, #state{name=Name, token=Token,
                gateway_pid=GatewayPid}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
                  State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_call({send_ws, DiscordFrame}, From,
            #state{gateway_pid=GatewayPid, name=Name,
                   ws_seq_nr=_SequenceNumber}=State)
    when is_map(DiscordFrame) ->
    lager:debug("[~p]: Received DiscordFrame from ~p:~n~p~n",
                [Name, From, DiscordFrame]),
    %% TODO: add function for adding sequence number to message
    gun:ws_send(GatewayPid, DiscordFrame),
    {reply, ok, State};
handle_call({create_identify_message}, _From, #state{token=Token}=State) ->
    Properties = #{<<"os">> => <<"linux">>,
                   <<"browser">> => list_to_bitstring(atom_to_list(?MODULE)),
                   <<"device">> => list_to_bitstring(atom_to_list(?MODULE)),
                   <<"referrer">> => <<"">>,
                   <<"referring_domain">> => <<"">>},
    Identify = #{<<"token">> => Token,
                 <<"properties">> => Properties,
                 <<"compress">> => false,
                 <<"large_threshold">> => 250},
    case eda_frame:build_frame(?OPCIdentify, Identify) of
        {error, Reason} ->
            {reply, {error, Reason}, State};
        Frame ->
            {reply, {ok, Frame}, State}
    end;
handle_call({send_frame, #{?FrameOPCode := ?OPCHeartbeat}=Frame}, _From,
            #state{gateway_pid=GatewayPid, ws_status=online,
                   ws_seq_nr=SequenceNumber, name=Name}=State) ->
    UpdatedFrame = maps:put(?FrameEventData, SequenceNumber, Frame),
    Payload = {text, jiffy:encode(UpdatedFrame)},
    gun:ws_send(GatewayPid, Payload),
    lager:debug("[~p]: Sending Payload(~p)", [Name, Payload]),
    {reply, ok, State};
handle_call({send_frame, Frame}, _From,
            #state{gateway_pid=GatewayPid, ws_status=online,
                   name=Name}=State) ->
    %% TODO: Payload and Frame variable naming should be changed because
    %% Frame is actually the Discord payload and the payload is the Frame
    Payload = {text, jiffy:encode(Frame)},
    gun:ws_send(GatewayPid, Payload),
    lager:debug("[~p]: Sending Payload(~p)", [Name, Payload]),
    {reply, ok, State};
handle_call({send_frame, Frame}, _From,
            #state{name=Name, ws_status=WSStatus}=State) ->
    lager:error("[~p]: Error sending Frame(~p) as websocket connection is "
                "~p", [Name, Frame, WSStatus]),
    {reply, {error, "websocket connection is not online"}, State};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_info({gun_up, GatewayPid, http},
            #state{gateway_pid=GatewayPid, name=Name}=State) ->
    lager:info("[~p]: Upgrading GatewayConnPid(~p) connection to websocket "
               "using Path(~p)",
               [Name, GatewayPid, ?GatewayWSPath]),
    gun:ws_upgrade(GatewayPid, ?GatewayWSPath),
    {noreply, State#state{ws_status=upgrade}};
handle_info({gun_up, _ConnPid, _Protocol}, State)  ->
    {noreply, State};

handle_info({gun_down, _ConnPid, _Protocol, _Reason,
             _KilledStreams, _UnProcessedStreams}=Msg,
            #state{name=Name}=State) ->
    lager:warning("[~p]: Unhandled info message(~p)~n"
                  "State:~p~n", [Name, Msg, State]),
    {noreply, State};

handle_info({gun_push, _ConnPid, _StreamRef, _NewStreamRef, _URI, _Headers}=Msg,
            #state{name=Name}=State) ->
    lager:warning("[~p]: Unhandled info message(~p)~n"
                  "State:~p~n", [Name, Msg, State]),
    {noreply, State};

handle_info({gun_response, GatewayPid, _, _, Status, Headers},
            #state{gateway_pid=GatewayPid,
                   name=Name, ws_status=upgrade}=State) ->
    lager:error("[~p]: Bad gun_response from GatewayPid(~p) with Status(~p)"
                " and Headers:~n~p~n",
                [Name, GatewayPid, Status, Headers]),
    lager:error("[~p]: ws_upgrade failed", [Name]),
    {stop, "failed websocket upgrade", State#state{ws_status=offline}};
handle_info({gun_response, _ConnPid, _StreamRef, _IsFin, _Status, _Headers}=Msg,
            #state{name=Name}=State) ->
    lager:warning("[~p]: Unhandled info message(~p)~n"
                  "State:~p~n", [Name, Msg, State]),
    {noreply, State};

handle_info({gun_data, _ConnPid, _StreamRef, _IsFin, _Data}=Msg,
            #state{name=Name}=State) ->
    lager:warning("[~p]: Unhandled info message(~p)~n"
                  "State:~p~n", [Name, Msg, State]),
    {noreply, State};

handle_info({gun_error, GatewayPid, _StreamRef, Reason},
            #state{gateway_pid=GatewayPid, name=Name}=State) ->
    lager:error("[~p]: Error(gun_error) from GatewayPid(~p) with Reason:~p~n~p",
                [Name, GatewayPid, Reason]),
    {noreply, State};
handle_info({gun_error, _ConnPid, _StreamRef, _Reason}=Msg,
            #state{name=Name}=State) ->
    lager:warning("[~p]: Unhandled info message(~p)~n"
                  "State:~p~n", [Name, Msg, State]),
    {noreply, State};
handle_info({gun_error, _ConnPid, _Reason}=Msg, #state{name=Name}=State) ->
    lager:warning("[~p]: Unhandled info message(~p)~n"
                  "State:~p~n", [Name, Msg, State]),
    {noreply, State};

handle_info({gun_ws_upgrade, GatewayPid, ok, Headers},
            #state{gateway_pid=GatewayPid, name=Name}=State) ->
    lager:info("[~p]: websocket upgraded successfully for GatewayPid(~p) "
               " with Headers(~p)",
               [Name, GatewayPid, Headers]),
    {noreply, State#state{ws_status=online}};
handle_info({gun_ws_upgrade, _ConnPid, ok, _Headers}=Msg,
            #state{name=Name}=State) ->
    lager:warning("[~p]: Unhandled info message(~p)~n"
                  "State:~p~n", [Name, Msg, State]),
    {noreply, State};

handle_info({gun_ws, GatewayPid, {text, JsonFrame}},
            #state{gateway_pid=GatewayPid, name=Name}=State) ->
    case jiffy:decode(JsonFrame, [return_maps]) of
        #{?FrameSequenceNumber := null}=Frame ->
            lager:debug("[~p]: Frame received from GatewayPid(~p):~n~p~n",
                        [Name, GatewayPid, Frame]),
            EdaFrame = eda_frame:build_eda_frame(Name, Frame),
            eda_frame_router:publish_frame(EdaFrame),
            {noreply, State};
        #{?FrameSequenceNumber := SequenceNumber}=Frame ->
            lager:debug("[~p]: Frame received from GatewayPid(~p):~n~p~n",
                        [Name, GatewayPid, Frame]),
            EdaFrame = eda_frame:build_eda_frame(Name, Frame),
            eda_frame_router:publish_frame(EdaFrame),
            {noreply, State#state{ws_seq_nr=SequenceNumber}};
        Frame when is_map(Frame) ->
            lager:debug("[~p]: Frame received from GatewayPid(~p):~n~p~n",
                        [Name, GatewayPid, Frame]),
            EdaFrame = eda_frame:build_eda_frame(Name, Frame),
            eda_frame_router:publish_frame(EdaFrame),
            {noreply, State};
        Frame ->
            lager:error("[~p]: unknown Frame received from "
                        "GatewayPid(~p):~n~p~n"
                        "JsonFrame:~p~n",
                        [Name, GatewayPid, Frame, JsonFrame]),
            {noreply, State}
    end;
handle_info({gun_ws, _ConnPid, _Frame}=Msg, #state{name=Name}=State) ->
    lager:warning("[~p]: Unhandled websocket message(~p)~n"
                  "State:~p~n", [Name, Msg, State]),
    {noreply, State};

handle_info(Info, State) ->
    lager:error("Unhandled Msg received:~n~p~n", [Info]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
                State :: #state{}) -> term()).
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
                  Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
consider_tracing(Pid, #{trace := true}) ->
    dbg:start(),
    dbg:tracer(),
    dbg:tpl(?MODULE, [{'_', [], [{return_trace}]}]),
    dbg:p(Pid, all);
consider_tracing(_, _) ->
    ok.