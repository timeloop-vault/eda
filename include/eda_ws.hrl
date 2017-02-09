%%%-------------------------------------------------------------------
%%% @author scripter
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 08. Feb 2017 21:55
%%%-------------------------------------------------------------------
-author("scripter").

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

-define(GATEWAYIDENTIFY(Token, Properties, Compress, LargeThreshold), #{<<"token">> => Token,
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