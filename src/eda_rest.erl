%%%-------------------------------------------------------------------
%%% @author Stefan Hagdahl
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. Feb 2017 00:38
%%%-------------------------------------------------------------------
-module(eda_rest).
-author("Stefan Hagdahl").

%% API
-export([create_message/2]).
-export_type([request_method/0]).

-include("eda_rest.hrl").

-type request_method() :: get | put | patch | delete | post.

%%--------------------------------------------------------------------
%% Create Object for API
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Create Body for API
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% Create Message
%% https://discordapp.com/developers/docs/resources/channel#create-message
%%
%% @end
%%--------------------------------------------------------------------
-spec(create_message(ChannelId :: term(), Content :: string()) ->
    {RequestMethod :: request_method(), Path :: string(), Body :: iodata()} | {error, Reason :: term()}).
create_message(ChannelId, Content) ->
    Path = ?RestCreateMessage(ChannelId),
    Body = #{<<"content">> => unicode:characters_to_binary(Content)},
    {post, Path, jiffy:encode(Body)}.