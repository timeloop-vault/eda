%%%-------------------------------------------------------------------
%%% @author Stefan Hagdahl
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 09. Feb 2017 22:51
%%%-------------------------------------------------------------------
-module(eda_frame_router).
-author("Stefan Hagdahl").

-behaviour(gen_server).

%% API
-export([start_link/0,
         publish_frame/1,
         subscribe/1,
         subscribe/2,
         unsubscribe/1,
         unsubscribe/2]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
    subscriptions = #{} :: #{eda_frame_api:eda_frame() =>
                             PidList :: list(pid())}
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
-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc
%% Publish EDA Frame to frame router for routing to subscribers
%%
%% @end
%%--------------------------------------------------------------------
%% TODO: Add "FROM Bot" to message so that receiving end knows which
%% end-point bot to use for sending data
-spec(publish_frame(EdaFrame :: eda_frame_api:eda_frame()) -> ok).
publish_frame(EdaFrame) ->
    gen_server:cast(?SERVER, {publish_frame, EdaFrame}).

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
    gen_server:call(?SERVER, {subscribe, EdaFrameSpec, Pid}).

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
    gen_server:call(?SERVER, {unsubscribe, EdaFrameSpec, Pid}).

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
init([]) ->
    {ok, #state{}}.

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
                     {reply, Reply :: term(), NewState :: #state{},
                      timeout() | hibernate} |
                     {noreply, NewState :: #state{}} |
                     {noreply, NewState :: #state{}, timeout() | hibernate} |
                     {stop, Reason :: term(), Reply :: term(),
                      NewState :: #state{}} |
                     {stop, Reason :: term(), NewState :: #state{}}).
handle_call({subscribe, #{frame := _}=EdaFrameSpec, Pid}, _From,
            #state{subscriptions=Subscriptions}=State)
    when is_map(EdaFrameSpec), is_pid(Pid) ->
    UpdatedSubscriptions =
    case maps:find(EdaFrameSpec, Subscriptions) of
        error ->
            maps:put(EdaFrameSpec, [Pid], Subscriptions);
        {ok, PidList} when is_list(PidList) ->
            maps:put(EdaFrameSpec, [Pid] ++ PidList, Subscriptions);
        {ok, UnexpectedResult} ->
            lager:error("Error adding EdaFrameSpec(~p) from "
                        "Pid(~p) to Subscriptions(~p) "
                        "because of UnexpectedResult(~p)",
                        [EdaFrameSpec, Pid,
                         Subscriptions, UnexpectedResult]),
            {reply, {error, "Subscription list returned unexpected value: "
            ++ lists:concat(UnexpectedResult)}, State}
    end,
    lager:debug("EdaFrameSpec(~p) from Pid(~p) added to Subscriptions(~p)",
                [EdaFrameSpec, Pid, UpdatedSubscriptions]),
    {reply, ok, State#state{subscriptions=UpdatedSubscriptions}};
handle_call({unsubscribe, #{frame := _}=EdaFrameSpec, Pid}, _From,
            #state{subscriptions=Subscriptions}=State)
    when is_map(EdaFrameSpec), is_pid(Pid) ->
    UpdateSubscriptions =
    case maps:find(EdaFrameSpec, Subscriptions) of
        error ->
            lager:error("Error removing EdaFrameSpec(~p) from Pid(~p) in "
            "Subscriptions(~p) Reason(EdaFrameSpec doesn't exist)",
                [EdaFrameSpec, Pid, Subscriptions]),
            {reply, {error, "Subsciption doesn't exist"}, State};
        {ok, [Pid]} ->
            maps:remove(EdaFrameSpec, Subscriptions);
        {ok, PidList} ->
            maps:put(EdaFrameSpec, lists:delete(Pid, PidList), Subscriptions)
    end,
    lager:debug("EdaFrameSpec(~p) from Pid(~p) removed from Subscriptions(~p)",
                [EdaFrameSpec, Pid, UpdateSubscriptions]),
    {reply, ok, State#state{subscriptions=UpdateSubscriptions}};
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
handle_cast({publish_frame, #{bot := _Bot, frame := _Frame} = EdaFrame},
            #state{subscriptions=Subscriptions}=State) ->
    lager:debug("[~p] Received EdaFrame(~p)~n"
                "Current subscriptions:~p~n",
                [?SERVER, EdaFrame, Subscriptions]),
    SubscriptionList = maps:to_list(Subscriptions),
    lists:foreach(
        fun({EdaFrameSpec, PidList})
               when is_map(EdaFrameSpec), is_list(PidList) ->
            case eda_frame_api:match(EdaFrame, EdaFrameSpec) of
                true ->
                    send_notifications({frame, EdaFrame}, PidList);
                false ->
                    ok
            end;
           ({EdaFrameSpec, UnexpectedValue}) ->
               lager:error("Unexpected Value(~p) returned from "
                           "Subscription(~p) while looking for "
                           "EdaFrameSpec(~p)",
                           [UnexpectedValue, Subscriptions,
                            EdaFrameSpec])
        end,
        SubscriptionList),

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

%%--------------------------------------------------------------------
%% @doc
%% Send notification of Frame to subscribers with matching FrameSpec
%%
%% @end
%%--------------------------------------------------------------------
send_notifications(_Notification, []) ->
    ok;
send_notifications(Notification, [Pid|Rest])
    when is_pid(Pid) ->
    Pid ! Notification,
    send_notifications(Notification, Rest);
send_notifications(Notification, [Pid|Rest]) ->
    lager:error("Error sending notification of Frame(~p) to Pid(~p)",
                [Notification, Pid]),
    send_notifications(Notification, Rest).