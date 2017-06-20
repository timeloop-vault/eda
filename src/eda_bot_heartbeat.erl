%%%-------------------------------------------------------------------
%%% @author Stefan Hagdahl
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%% Handle heartbeat messages from web socket connection for Bot
%%%
%%% @end
%%% Created : 11. Feb 2017 00:17
%%%-------------------------------------------------------------------
-module(eda_bot_heartbeat).
-author("Stefan Hagdahl").

-behaviour(gen_server).

-include("eda_frame.hrl").

%% API
-export([start_link/1,
         trigger_heartbeat/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(SERVER(Bot), list_to_atom(lists:concat([?MODULE, "_", Bot]))).

-record(state, {
    heartbeat_interval = 0 :: integer(),
    trigger_heartbeat_ref :: timer:tref(),
    bot :: atom(),
    name :: atom()
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
-spec(start_link(Bot :: atom()) ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Bot)
    when is_atom(Bot) ->
    gen_server:start_link({local, ?SERVER(Bot)}, ?MODULE, [Bot, ?SERVER(Bot)], []).

%%--------------------------------------------------------------------
%% @doc
%% Trigger heartbeat
%%
%% @end
%%--------------------------------------------------------------------
-spec(trigger_heartbeat(Name :: atom()) -> ok).
trigger_heartbeat(Name)
    when is_atom(Name) ->
    gen_server:cast(Name, {trigger_heartbeat});
trigger_heartbeat(Name) ->
    lager:error("Error triggering heartbeat with Name(~p)", [Name]).

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
init([Bot, Name]) ->
    HeartbeatACKFrameSpec = eda_frame_api:build_frame_spec(?OPCHeartbeatACK, '_'),
    HelloFrameSpec = eda_frame_api:build_frame_spec(?OPCHello, '_'),
    HelloEdaFrameSpec = eda_frame_api:build_eda_frame(Bot, HelloFrameSpec),
    HeartbeatACKEdaFrameSpec =
    eda_frame_api:build_eda_frame(Bot, HeartbeatACKFrameSpec),
    case init_subscriptions([HeartbeatACKEdaFrameSpec, HelloEdaFrameSpec]) of
        {error, Reason} ->
            {stop, Reason};
        ok ->
            {ok, #state{bot=Bot, name=Name}}
    end.

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
handle_cast({trigger_heartbeat}, #state{bot=Bot}=State) ->
    lager:debug("trigger heartbeat"),
    eda_bot:send_frame(Bot, #{?FrameOPCode => ?OPCHeartbeat}),
    {noreply, State};
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
handle_info({frame, #{bot := Bot,
                      frame := #{?FrameOPCode := ?OPCHello,
                                 ?FrameEventData := EventData}=HelloFrame}},
            #state{bot=Bot, name=Name,
                   trigger_heartbeat_ref=OldTRef}=State) ->
    case OldTRef of
        undefined ->
            ok;
        OldTRef ->
            timer:cancel(OldTRef)
    end,
    %% Frame of heartbeat every x milliseconds
    lager:debug("Received Hello:~p~n", [HelloFrame]),
    #{<<"heartbeat_interval">> := HeartbeatInterval} = EventData,
    case eda_bot:create_identify_message(Bot) of
        {ok, Frame} ->
            case eda_bot:send_frame(Bot, Frame) of
                ok ->
                    case timer:apply_interval(HeartbeatInterval, ?MODULE,
                                         trigger_heartbeat, [Name]) of
                        {ok, TRef} ->
                            lager:debug("Created heartbeat trigger "
                                        "for Bot(~p)", [Name]),
                            {noreply,
                             State#state{trigger_heartbeat_ref=TRef,
                                         heartbeat_interval=HeartbeatInterval}};
                        {error, Reason} ->
                            lager:error("[~p]: Error creating timer for "
                                        "heartbeat trigger for Bot(~P) "
                                        "Reason:~p~n", [Name, Reason]),
                            {noreply,
                             State#state{trigger_heartbeat_ref=undefined}}
                    end;
                {error, Reason} ->
                    lager:error("[~p]: Error sending identify message "
                                "for Bot(~p) "
                                "with Reason:~p~n", [Name, Bot, Reason]),
                    {noreply, State#state{trigger_heartbeat_ref=undefined}}
            end;
        {error, Reason} ->
            %% TODO: Failing this should initiate stop of eda_bot(Bot)
            lager:error("[~p]: Error creating identify message for Bot(~p) "
                        "with Reason:~p~n", [Name, Bot, Reason]),
            {noreply, State#state{trigger_heartbeat_ref=undefined}}
    end;
handle_info({frame, #{bot := Bot,
                      frame := #{?FrameOPCode := ?OPCHeartbeatACK}}=Frame},
            #state{name=Name}=State) ->
    lager:debug("[~p]: Received heartbeat ack for Bot(~p):~p~n",
                [Name, Bot, Frame]),
    {noreply, State};
handle_info(_Info, State) ->
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
init_subscriptions([]) ->
    ok;
init_subscriptions([FrameSpec|Rest]) ->
    case eda_frame_api:subscribe(FrameSpec) of
        ok ->
            init_subscriptions(Rest);
        Error ->
            Error
    end.