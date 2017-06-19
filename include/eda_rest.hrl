%%%-------------------------------------------------------------------
%%% @author Stefan Hagdahl
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. Feb 2017 00:43
%%%-------------------------------------------------------------------
-author("Stefan Hagdahl").

-define(RestURL, "discordapp.com").
-define(RestPort, 443).

-define(RestRoot, "/api").
-define(RestCreateMessage(ChannelId),
    lists:concat([?RestRoot, "/channels/", ChannelId,"/messages"])).
-define(RestRateLimit, <<"x-ratelimit-limit">>).
-define(RestRateLimitRemaining, <<"x-ratelimit-remaining">>).
-define(RestRateLimitReset, <<"x-ratelimit-reset">>).
-define(RestRateLimitGlobal, <<"x-ratelimit-global">>).
-define(Epoch0, 62167219200).
-define(DefaultRestRateLimit, 5).

-define(UniqueListStart, 1).
-define(UniqueListEnd, 50).