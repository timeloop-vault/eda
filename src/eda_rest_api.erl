%%%-------------------------------------------------------------------
%%% @author Stefan Hagdahl
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. Feb 2017 00:38
%%%-------------------------------------------------------------------
-module(eda_rest_api).
-author("Stefan Hagdahl").

%% API
-export([send_channel_message/3,
         create_message/2,
         parse_http_headers/1]).
-export_type([http_method/0]).

-include("eda_rest.hrl").

-type http_method() :: get | put | patch | delete | post.

%%--------------------------------------------------------------------
%% Create Object for API
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Create Body for API
%%--------------------------------------------------------------------
%%--------------------------------------------------------------------
%% @doc
%% Send channel message
%%
%% @end
%%--------------------------------------------------------------------
-spec(send_channel_message(ChannelId :: term(), Message :: string(),
                           BotName :: atom() | string()) ->
    {ok, Ref :: term()} | {error, Reason :: term()}).
send_channel_message(ChannelId, Message, BotName) ->
    {HttpMethod, Path, Body} = create_message(ChannelId, Message),
    eda_rest_path:rest_call(BotName, HttpMethod, Path, Body).

%%--------------------------------------------------------------------
%% @doc
%% Create Message
%% https://discordapp.com/developers/docs/resources/channel#create-message
%%
%% @end
%%--------------------------------------------------------------------
-spec(create_message(ChannelId :: term(), Content :: string()) ->
    {HttpMethod :: http_method(), Path :: string(), Body :: iodata()} |
    {error, Reason :: term()}).
create_message(ChannelId, Content) ->
    Path = ?RestCreateMessage(ChannelId),
    Body = #{<<"content">> => unicode:characters_to_binary(Content)},
    {post, Path, jiffy:encode(Body)}.

%%--------------------------------------------------------------------
%% @doc
%% Parse http headers
%%
%% @end
%%--------------------------------------------------------------------
-spec(parse_http_headers(Headers :: [bitstring()]) ->
    ParsedHeaders :: #{}).
parse_http_headers(Headers) ->
    parse_http_headers(Headers, #{}).

%%%===================================================================
%%% Internal functions
%%%===================================================================
parse_http_headers([], ParsedHeaders) ->
    ParsedHeaders;
parse_http_headers([{?RestRateLimit, Limit}| Rest], ParsedHeaders) ->
    ConvertedLimit = list_to_integer(bitstring_to_list(Limit)),
    UpdatedParsedHeader = maps:put(rate_limit, ConvertedLimit, ParsedHeaders),
    parse_http_headers(Rest, UpdatedParsedHeader);
parse_http_headers([{?RestRateLimitGlobal, Global}| Rest], ParsedHeaders) ->
    ConvertedGlobal = list_to_atom(bitstring_to_list(Global)),
    UpdatedParsedHeader = maps:put(rate_limit_global, ConvertedGlobal,
                                   ParsedHeaders),
    parse_http_headers(Rest, UpdatedParsedHeader);
parse_http_headers([{?RestRateLimitRemaining, Remaining}| Rest], ParsedHeaders) ->
    ConvertedRemaining = list_to_integer(bitstring_to_list(Remaining)),
    UpdatedParsedHeader = maps:put(rate_limit_remaining, ConvertedRemaining,
                                   ParsedHeaders),
    parse_http_headers(Rest, UpdatedParsedHeader);
parse_http_headers([{?RestRateLimitReset, Reset}| Rest], ParsedHeaders) ->
    ConvertedReset = list_to_integer(bitstring_to_list(Reset)),
    UpdatedParsedHeaders = maps:put(rate_limit_reset, ConvertedReset,
                                    ParsedHeaders),
    parse_http_headers(Rest, UpdatedParsedHeaders);
parse_http_headers([_| Rest], ParsedHeaders) ->
    parse_http_headers(Rest, ParsedHeaders).