%%%-------------------------------------------------------------------
%% @doc discord_bot_erl top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(eda_sup).

-behaviour(supervisor).

%% API
-export([start_link/0,
         start_child/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%--------------------------------------------------------------------
%% @doc
%% Start child
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_child(ChildSpec :: supervisor:child_spec()) ->
    {ok, Child :: supervisor:child()} |
    {ok, Child :: supervisor:child(), Info :: term()} |
    {error, supervisor:startchild_err()}).
start_child(ChildSpec) ->
    supervisor:start_child(?SERVER, ChildSpec).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    SupFlags = #{strategy => one_for_one,
                 intensity => 5,
                 period => 5},
    EdaFrameRouterChildSpec = #{id => eda_frame_router,
                                start => {eda_frame_router, start_link, []},
                                restart => transient,
                                shutdown => 10000},
    {ok, {SupFlags, [EdaFrameRouterChildSpec]}}.

%%====================================================================
%% Internal functions
%%====================================================================
