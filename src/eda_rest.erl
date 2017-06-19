%%%-------------------------------------------------------------------
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 16. Jun 2017 11:06
%%%-------------------------------------------------------------------
-module(eda_rest).

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

-define(SERVER(Name), list_to_atom(lists:concat([?MODULE, "_", Name]))).

-record(state, {
    name :: string(),
    token :: string(),
    rest_pid :: pid(),
    rest_calls = #{} :: #{StreamRef :: reference() :=
                          #{reply := pid()}}
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
start_link(#{name := Name, token := _Token}=Args) ->
    gen_server:start_link({local, ?SERVER(Name)}, ?MODULE, Args, []);
start_link(Args) ->
    {error, {"Args doesn't contain name, token", Args}}.

%%--------------------------------------------------------------------
%% @doc
%% Rest call
%%
%% @end
%%--------------------------------------------------------------------
-spec(rest_call(Name :: atom(), HttpMethod :: eda_rest_api:http_method(),
                Path :: string(), Body :: iodata()) -> term()).
rest_call(Name, HttpMethod, Path, Body) ->
    gen_server:call(?SERVER(Name), {rest_call, HttpMethod, Path, Body}, 5000).

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
init(#{name := Name, token := Token}) ->
    {ok, RestPid} = gun:open(?RestURL, ?RestPort,
                             #{protocols=>[http], trace=>false}),
    {ok, #state{name=Name, token=Token, rest_pid=RestPid}}.

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
handle_call({rest_call, HttpMethod, Path, Body}, {Pid, _Tag},
            #state{name=Name, token=Token, rest_pid=RestPid,
                   rest_calls=RestCalls}=State)
    when HttpMethod =:= post ->
    Header = [{<<"content-type">>, "application/json"},
              {<<"Authorization">>,"Bot " ++ bitstring_to_list(Token)}],
    StreamRef = gun:post(RestPid, Path, Header),
    gun:data(RestPid, StreamRef, fin, Body),
    lager:debug("[~p]: Posted to Path(~p) with Header(~p) Body:~p~n",
                [Name, Path, Header, Body]),
    RestCall = #{reply => Pid},
    UpdatedRestCalls = maps:put(StreamRef, RestCall,
                                RestCalls),
    {reply, {ok, StreamRef}, State#state{rest_calls=UpdatedRestCalls}};
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
handle_info({gun_up, RestPid, _Protocol},
            #state{rest_pid=RestPid, name=Name}=State) ->
    lager:debug("[~p]: Connection up for RestPid(~p)",
                [Name, RestPid]),
    {noreply, State};
handle_info({gun_up, _ConnPid, _Protocol}, State)  ->
    {noreply, State};

handle_info({gun_down, RestPid, _Protocol, Reason,
             _KilledStream, _UnProcessedStreams},
            #state{rest_pid=RestPid, name=Name}=State) ->
    lager:warning("[~p]: Connection down for RestPid(~p) Reason:~n~p~n",
                  [Name, RestPid, Reason]),
    {noreply, State};
handle_info({gun_down, _ConnPid, _Protocol, _Reason,
             _KilledStreams, _UnProcessedStreams}=Msg,
            #state{name=Name}=State) ->
    lager:warning("[~p]: Unhandled info message(~p)~n"
                  "State:~p~n", [Name, Msg, State]),
    {noreply, State};

handle_info({gun_response, RestPid, StreamRef, nofin, Status, Headers},
            #state{name=Name, rest_pid=RestPid,
                   rest_calls=RestCalls} = State) ->
    case maps:find(StreamRef, RestCalls) of
        {ok, #{reply := From}} ->
            lager:warning("[~p]: Receive response from Rest with status(~p) "
                          "and headers:~p~n", [Name, Status, Headers]),
            From ! {rest_info, nofin, StreamRef, Status, Headers},
            {noreply, State};
        error ->
            lager:error("[~p]: Recieved response from Rest with status(~p)"
                        " and headers:~p~n with unknown caller",
                        [Name, Status, Headers]),
            {noreply, State}
    end;
handle_info({gun_response, RestPid, StreamRef, fin, Status, Headers},
            #state{name=Name, rest_pid=RestPid,
                   rest_calls=RestCalls} = State) ->
    case maps:find(StreamRef, RestCalls) of
        {ok, #{reply := From}} ->
            lager:warning("[~p]: Receive response from Rest with status(~p) "
                          "and headers:~p~n", [Name, Status, Headers]),
            From ! {rest_info, fin, StreamRef, Status, Headers},
            UpdatedRestApiCalls = maps:remove(StreamRef, RestCalls),
            {noreply, State#state{rest_calls=UpdatedRestApiCalls}};
        error ->
            lager:error("[~p]: Recieved response from Rest with status(~p)"
                        " and headers:~p~n with unknown caller",
                        [Name, Status, Headers]),
            {noreply, State}
    end;
handle_info({gun_response, _ConnPid, _StreamRef, _IsFin, _Status, _Headers}=Msg,
            #state{name=Name}=State) ->
    lager:warning("[~p]: Unhandled info message(~p)~n"
                  "State:~p~n", [Name, Msg, State]),
    {noreply, State};

handle_info({gun_data, RestPid, StreamRef, nofin, Data},
            #state{name=Name, rest_pid=RestPid,
                   rest_calls=RestCalls} = State) ->
    case maps:find(StreamRef, RestCalls) of
        {ok, #{reply := From}} ->
            lager:debug("[~p]: Receive data response from Rest with data:~p",
                        [Name, Data]),
            From ! {rest_data, nofin, StreamRef, Data};
        error ->
            lager:error("[~p]: Recieved data response from Rest "
                        "with data(~p)",[Name, Data])
    end,
    {noreply, State};
handle_info({gun_data, RestPid, StreamRef, fin, Data},
            #state{name=Name, rest_pid=RestPid,
                   rest_calls=RestCalls} = State) ->
    case maps:find(StreamRef, RestCalls) of
        {ok, #{reply := From}} ->
            lager:debug("[~p]: Receive data response from RestAPI with data:~p",
                        [Name, Data]),
            From ! {rest_data, fin, StreamRef, Data},
            UpdatedRestApiCalls = maps:remove(StreamRef, RestCalls),
            {noreply, State#state{rest_calls=UpdatedRestApiCalls}};
        error ->
            lager:error("[~p]: Recieved data response from RestAPI "
                        "with data(~p)",[Name, Data]),
            {noreply, State}
    end;
handle_info({gun_data, _ConnPid, _StreamRef, _IsFin, _Data}=Msg,
            #state{name=Name}=State) ->
    lager:warning("[~p]: Unhandled info message(~p)~n"
                  "State:~p~n", [Name, Msg, State]),
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
