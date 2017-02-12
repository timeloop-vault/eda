%%%-------------------------------------------------------------------
%%% @author Stefan Hagdahl
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 08. Feb 2017 21:55
%%%-------------------------------------------------------------------
-author("Stefan Hagdahl").

-define(DISCORDGATEWAYURL, "gateway.discord.gg").
-define(DISCORDGATEWAYPORT, 443).
-define(BOTTOKEN, <<"Mjc4OTIzNzgzNjYwNzY1MjA2.C3zfzQ.Ikm_voH_3TRddb2NelL2NN-3YYc">>).

-define(DISCORDRESTAPIURL, "discordapp.com").
-define(DISCORDRESTAPIPORT, 443).

-define(GATEWAYWSPATH, "/?v=6&encoding=json").

-define(DISPATCH, 0).            %%	dispatches an event
-define(HEARTBEAT, 1).           %% used for ping checking
-define(IDENTIFY, 2).            %% used for client handshake
-define(STATUSUPDATE, 3).        %%	used to update the client status
-define(VOICESTATEUPDATE, 4).    %%	used to join/move/leave voice channels
-define(VOICESERVERPING, 5).     %% used for voice ping checking
-define(RESUME, 6).              %% used to resume a closed connection
-define(RECONNECT, 7).           %% used to tell clients to reconnect to the gateway
-define(REQUESTGUILDMEMBERS, 8). %% used to request guild members
-define(INVALIDSESSION, 9).      %% used to notify client they have an invalid session id
-define(HELLO, 10).              %% sent immediately after connecting, contains heartbeat and server debug information
-define(HEARTBACKACK, 11).       %% sent immediately following a client heartbeat that was received

-define(OPCODE, <<"op">>).
-define(EVENTDATA, <<"d">>).
-define(SEQUENCENUMBER, <<"s">>).
-define(EVENTNAME, <<"t">>).

-define(HEARTBEATINTERVAL, <<"heartbeat_interval">>).

-define(GATEWAYIDENTIFY(Token, Properties, Compress, LargeThreshold),
    #{<<"token">> => Token,
      <<"properties">> => Properties,
      <<"compress">> => Compress,
      <<"large_threshold">> => LargeThreshold}).
-define(GATEWAYIDENTIFYPROPERTIES(OS, Browser, Device, Referrer, ReferringDomain),
        #{<<"os">> => OS,
          <<"browser">> => Browser,
          <<"device">> => Device,
          <<"referrer">> => Referrer,
          <<"referring_domain">> => ReferringDomain}).

%% Event Names
-define(EVENTMESSAGECREATE, <<"MESSAGE_CREATE">>).

%% Rest API endpoints
-define(API, "/api").
-define(CHANNELS(Id), "/channels/" ++ Id).
-define(MESSAGES, "/messages").


-define(MSG,#{
    <<"attachments">> => [],
    <<"tts">> => false,
    <<"embeds">> => [],
    <<"timestamp">> => <<"2017-02-10T14:00:50.546000+00:00">>,
    <<"mention_everyone">> => false,
    <<"id">> => <<"279612649304621056">>,
    <<"pinned">> => false,
    <<"edited_timestamp">> => null,
    <<"author">> => #{
        <<"username">> => <<"TopiC">>,
        <<"discriminator">> => <<"9064">>,
        <<"id">> => <<"200639393755561984">>,
        <<"avatar">> => null},
    <<"mention_roles">> => [],
    <<"content">> => <<"hehe börja precis 😄">>,
    <<"channel_id">> => <<"199982778471809024">>,
    <<"mentions">> => [],
    <<"type">> => 0
}).