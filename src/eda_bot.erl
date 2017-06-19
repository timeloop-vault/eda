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
         send_frame/2,
         rest_api/4]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%% include
-include("eda_bot.hrl").
-include("eda_rest.hrl").
-include("eda_frame.hrl").

-define(SERVER(Name), list_to_atom(lists:concat([?MODULE, "_", Name]))).

-record(state, {
    name :: string(),
    token :: string(),
    heartbeat :: integer(), %% milliseconds
    gateway_pid :: pid(),
    rest_pid :: pid(),
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

%%--------------------------------------------------------------------
%% @doc
%% Do Discord Rest API actions
%%
%% @end
%%--------------------------------------------------------------------
-spec(rest_api(Bot :: atom(), RequestMethod :: eda_rest_api:http_method(),
               Path :: string(), Body :: <<>>) ->
    ok | {error, Reason :: term()}).
%%TODO: Change to cast and let requester wait for response
rest_api(Bot, RequestMethod, Path, Body) ->
    gen_server:call(?SERVER(Bot), {rest_api, RequestMethod, Path, Body}, 20000).

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
    %% eda_app:start(a,b),eda_bot:start_link(#{name => mainframe, token => <<"Mjc4OTIzNzgzNjYwNzY1MjA2.C3zfzQ.Ikm_voH_3TRddb2NelL2NN-3YYc">>, opts => #{}}).
    %% {RequestMethod, Path, Body} = eda_rest:create_message(278599392540491787, "testing stuff").
    %% eda_bot:rest_api(mainframe, RequestMethod, Path, Body).
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

%%    {ok, RestPid} = gun:open(?RestURL, ?RestPort,
%%                             #{protocols=>[http], trace=>false}),
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
%%handle_call({rest_api, HttpMethod, Path, Body}, From,
%%            #state{name=Name, token=Token, rest_pid=RestPid,
%%                   rest_rate_limit=RestRateLimit,
%%                   rest_api_calls=RestApiCalls}=State)
%%    when HttpMethod =:= post ->
%%    Header = [{<<"content-type">>, "application/json"},
%%              {<<"Authorization">>,"Bot " ++ bitstring_to_list(Token)}],
%%    %% Rate limit rules:
%%    %% https://discordapp.com/developers/docs/topics/rate-limits
%%    %% Exception to the rule is deletion of messages which has it's own limit
%%    %% (DELETE/channels/{channel.id}/messages/)
%%    RateLimited =
%%    case check_rate_limit(RestRateLimit, Path) of
%%        {false, #{limit := Limit, remaining := Remaining,
%%                 reset := Reset}} ->
%%            lager:warning("[~p] Rest requests remaining for ~p is ~p out of ~p "
%%                        "and will be reset at ~p~n",
%%                        [Name, Path, Remaining, Limit,
%%                         calendar:gregorian_seconds_to_datetime(Reset)]),
%%            false;
%%        {true, #{limit := Limit, remaining := Remaining,
%%                  reset := Reset}} ->
%%            lager:warning("[~p] Rest requests remaining for ~p is ~p out of ~p "
%%                          "and will be reset at ~p~n",
%%                          [Name, Path, Remaining, Limit,
%%                           calendar:gregorian_seconds_to_datetime(Reset)]),
%%            Now = calendar:datetime_to_gregorian_seconds(
%%                calendar:universal_time()),
%%            %% TODO: This will cause a faulty reply in the end as the
%%            %% From will no be the gen_server it self or some other process
%%            %% that is no the requesting party
%%            ResendTime = Reset - Now,
%%            if
%%                ResendTime > 0 ->
%%                    timer:apply_interval(ResendTime * 1000, ?MODULE, rest_api,
%%                                         [Name, HttpMethod, Path, Body]);
%%                true ->
%%                    timer:apply_interval(0, ?MODULE, rest_api,
%%                                         [Name, HttpMethod, Path, Body])
%%            end,
%%            true;
%%        false ->
%%            lager:debug("[~p] No rate limits found for ~p~n", [Name, Path]),
%%            false
%%    end,
%%    case RateLimited of
%%        false ->
%%            StreamRef = gun:post(RestPid, Path, Header),
%%            gun:data(RestPid, StreamRef, fin, Body),
%%            lager:debug("[~p]: Posted to Path(~p) with Header(~p) Body:~p~n",
%%                        [Name, Path, Header, Body]),
%%            RestApiCall = #{reply => From, path => Path},
%%            UpdatedRestApiCalls = maps:put(StreamRef, RestApiCall,
%%                                           RestApiCalls),
%%            %% TODO: Update rate limit manually until next header has been read
%%            %% to ensure consistence
%%            UpdateRestRateLimit = decrease_rate_limit(Path, RestRateLimit, Name),
%%            {noreply, State#state{rest_api_calls=UpdatedRestApiCalls,
%%                                  rest_rate_limit=UpdateRestRateLimit}};
%%        true ->
%%            {noreply, State}
%%    end;
handle_call({rest_api, HttpMethod, Path, Body}, _From,
            #state{name=Name}=State) ->
    lager:error("[~p]: Error request method(~p) not supported "
                "for Path(~p) and Body:~p~n",
                [Name, HttpMethod, Path, Body]),
    {reply, {error, "request method not supported"}, State};
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