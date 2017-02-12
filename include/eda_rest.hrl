%%%-------------------------------------------------------------------
%%% @author Stefan Hagdahl
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. Feb 2017 00:43
%%%-------------------------------------------------------------------
-author("Stefan Hagdahl").


-define(RestRoot, "/api").
-define(RestCreateMessage(ChannelId),
    lists:concat([?RestRoot, "/channels/", ChannelId,"/messages"])).