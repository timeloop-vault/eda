%%%-------------------------------------------------------------------
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 16. Jun 2017 11:00
%%%-------------------------------------------------------------------
-module(eda_rest_path).

-behaviour(gen_server).

%% API
-export([start_link/1,
         rest_call/4]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include("eda_rest.hrl").

-define(SERVER(Name, Path),
    list_to_atom(lists:concat([?MODULE, "_", Name, "_", Path]))).

-record(state, {
    name :: atom(),
    path :: string(),
    saved_calls = [] :: [#{from => pid(),
                           ref => term(),
                           call => #{http_method => eda_rest_api:http_method(),
                                     path => string(),
                                     body => iodata()}}],
    current_rate = ?DefaultRestRateLimit :: integer(),
    current_rate_limit = ?DefaultRestRateLimit :: integer(),
    unique_ids = #{} :: #{iteration => integer(),
                          list => list()},
    call_relay = #{} :: #{StreamRef :: reference() :=
                          #{relay => pid()}}
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
start_link(#{name := Name, path := Path}=Args) ->
    gen_server:start_link({local, ?SERVER(Name, Path)}, ?MODULE, Args, []).

%%--------------------------------------------------------------------
%% @doc
%% Rest call
%%
%% @end
%%--------------------------------------------------------------------
-spec(rest_call(Name :: atom(), HttpMethod :: eda_rest_api:http_method(),
                Path :: string(), Body :: iodata()) ->
    {ok, Ref :: term()} | {error, Reason :: term()}).
rest_call(Name, HttpMethod, Path, Body) ->
    PathName = ?SERVER(Name, Path),
    Children = supervisor:which_children(eda_sup),
    case lists:keyfind(PathName, 1, Children) of
        {_Id, Child, _Type, _Modules} when is_pid(Child) ->
            gen_server:call(Child,
                            {rest_call, HttpMethod, Path, Body}, 5000);
        {_Id, undefined, _Type, _Modules} ->
            %% Start child?
            ok;
        {_Id, restarting, _Type, _Modules} ->
            %% wait?
            ok;
        false ->
            %% Start Child
            case create_path_child(Name, Path) of
                {ok, Child} ->
                    gen_server:call(Child, {rest_call, HttpMethod,
                                            Path, Body}, 5000);
                {error, Reason} ->
                    {error, Reason}
            end
    end.

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
init(#{name := Name, path := Path}) ->
    UniqueIdsIteration = 0,
    UniqueIdsList = unique_ids(UniqueIdsIteration),
    {ok, #state{name=Name, path=Path,
                unique_ids=#{iteration => UniqueIdsIteration,
                             list => UniqueIdsList}}}.

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
handle_call({rest_call, post, Path, Body}, {Pid, _Tag},
            #state{current_rate=CurrentRate, name=Name,
                   saved_calls=SavedCalls, call_relay=CallRelay,
                   unique_ids=UniqueIds} = State) ->
    %% Create unique ref
    {Ref, UpdatedUniqueIds} = generate_ref(UniqueIds, Path),
    if
        CurrentRate == 0 ->
            lager:debug("[~p]: Rate limited for Path(~p)~n"
                        "Saving call for resend~n", [Name, Path]),
            Call = #{http_method => post, path => Path, body => Body},
            SavedCall = #{from => Pid, ref => Ref, call => Call},
            UpdatedSavedCalls = SavedCalls + [SavedCall],
            {reply, {ok, Ref}, State#state{saved_calls=UpdatedSavedCalls,
                                           unique_ids=UpdatedUniqueIds}};
        true ->
            lager:debug("[~p]: Executing Rest Call:~n"
                        "Path:~p~nHttpMethod:~p~Body:~p~n",
                        [Name, Path, post, Body]),
            {ok, StreamRef} = eda_rest:rest_call(Name, post, Path, Body),
            UpdateCallRelay = maps:put(StreamRef, #{relay => Pid}, CallRelay),
            {reply, {ok, Ref}, State#state{unique_ids=UpdatedUniqueIds,
                                           call_relay=UpdateCallRelay}}
    end;
handle_call({rest_call, HttpMethod, Path, Message}, From,
            #state{name=Name}=State) ->
    lager:error("[~p]: HttpMethod(~p) currently not supported.~n"
                "Message: ~p~nPath:~p~nFrom:~p~n",
                [Name, HttpMethod, Path, Message, From]),
    {reply, {error, http_method_not_supported}, State};
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
handle_info({rest_info, fin, StreamRef, _Status, _Headers}=Info,
            #state{call_relay=CallRelay, name=Name}=State) ->
    case maps:take(StreamRef, CallRelay) of
        {#{relay := From}, UpdateCallRelay} ->
            lager:debug("[~p]: Relay rest_info:~n~p~nTo:~p~n",
                        [Name, Info, From]),
            From ! Info,
            {noreply, State#state{call_relay=UpdateCallRelay}};
        error ->
            lager:error("[~p]: Rest info received without no relay "
                        "available:~p~n", [Name, Info]),
            {noreply, State}
    end;
handle_info({rest_info, nofin, StreamRef, _Status, _Headers}=Info,
            #state{call_relay=CallRelay, name=Name}=State) ->
    case maps:find(StreamRef, CallRelay) of
        {ok, #{relay := From}} ->
            lager:debug("[~p]: Relay rest_info:~n~p~nTo:~p~n",
                        [Name, Info, From]),
            From ! Info;
        error ->
            lager:error("[~p]: Rest info received without no relay "
                        "available:~p~n", [Name, Info])
    end,
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
create_path_child(Name, Path) ->
    BotRestPathId = ?SERVER(Name, Path),
    BotRestPathChild = #{id => BotRestPathId,
                         start => {eda_rest_path, start_link,
                                   [#{name => Name, path => Path}]},
                         restart => transient,
                         shutdown => 2000},
    case eda_sup:start_child(BotRestPathChild) of
        {ok, Child} ->
            {ok, Child};
        {ok, Child, _Info} ->
            {ok, Child};
        {error, Reason} ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Create list sequence between ?UniqueListStart and ?UniqueListEnd
%% based on Iteration
%%
%% @end
%%--------------------------------------------------------------------
unique_ids(Iteration) ->
    From = ?UniqueListStart + (?UniqueListEnd * Iteration),
    To = ?UniqueListEnd + (?UniqueListEnd * Iteration),
    lists:seq(From, To).

generate_ref(#{iteration := Iteration, list := []}, Path) ->
    UpdatedIteration = Iteration + 1,
    UniqueIdsList = unique_ids(Iteration),
    generate_ref(#{iteration => UpdatedIteration, list => UniqueIdsList}, Path);
generate_ref(#{list := [UniqueId|UniqueIdsRest]}=UniqueIds, Path) ->
    Ref = list_to_atom(lists:concat([Path, "_", UniqueId])),
    UpdatedUniqueIds = maps:put(list, UniqueIdsRest, UniqueIds),
    {Ref, UpdatedUniqueIds}.
