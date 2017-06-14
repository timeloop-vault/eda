%%%-------------------------------------------------------------------
%%% @author Stefan Hagdahl
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 11. Feb 2017 00:27
%%%-------------------------------------------------------------------
-author("Stefan Hagdahl").

%% Define Payload structure
-define(FrameOPCode, <<"op">>).
-define(FrameEventName, <<"t">>).
-define(FrameEventData, <<"d">>).
-define(FrameSequenceNumber, <<"s">>).

%% Define OP Codes
-define(OPCDispatch, 0).            %%	dispatches an event
-define(OPCHeartbeat, 1).           %% used for ping checking
-define(OPCIdentify, 2).            %% used for client handshake
-define(OPCStatusUpdate, 3).        %%	used to update the client status
-define(OPCVoiceStateUpdate, 4).    %%	used to join/move/leave voice channels
-define(OPCVoiceServerPing, 5).     %% used for voice ping checking
-define(OPCResume, 6).              %% used to resume a closed connection
-define(OPCReconnect, 7).           %% used to tell clients to
                                 %% reconnect to the gateway
-define(OPCRequestGuildMembers, 8). %% used to request guild members
-define(OPCInvalidSession, 9).      %% used to notify client they have
                                 %% an invalid session id
-define(OPCHello, 10).              %% sent immediately after connecting, contains
                                 %% heartbeat and server debug information
-define(OPCHeartbeatACK, 11).       %% sent immediately following a client
                                 %% heartbeat that was received

%% Define a map of OP Codes for "op code check"
-define(OPCCheck, #{?OPCDispatch => true,
                    ?OPCHeartbeat => true,
                    ?OPCIdentify => true,
                    ?OPCStatusUpdate => true,
                    ?OPCVoiceStateUpdate => true,
                    ?OPCVoiceServerPing => true,
                    ?OPCResume => true,
                    ?OPCReconnect => true,
                    ?OPCRequestGuildMembers => true,
                    ?OPCInvalidSession => true,
                    ?OPCHello => true,
                    ?OPCHeartbeatACK => true}).

%% Define Event Names
-define(ENReady, <<"READY">>).
-define(ENResumed, <<"RESUMED">>).
-define(ENChannelCreate, <<"CHANNEL_CREATE">>).
-define(ENChannelUpdate, <<"CHANNEL_UPDATE">>).
-define(ENChannelDelete, <<"CHANNEL_DELETE">>).
-define(ENGuildCreate, <<"GUILD_CREATE">>).
-define(ENGuildUpdate, <<"GUILD_UPDATE">>).
-define(ENGuildDelete, <<"GUILD_DELETE">>).
-define(ENGuildBanAdd, <<"GUILD_BAN_ADD">>).
-define(ENGuildBanRemove, <<"GUILD_BAN_REMOVE">>).
-define(ENGuildEmojisUpdate, <<"GUILD_EMOJIS_UPDATE">>).
-define(ENGuildIntegrationsUpdate, <<"GUILD_INTEGRATIONS_UPDATE">>).
-define(ENGuildMemberAdd, <<"GUILD_MEMBER_ADD">>).
-define(ENGuildMemberRemove, <<"GUILD_MEMBER_REMOVE">>).
-define(ENGuildMemberUpdate, <<"GUILD_MEMBER_UPDATE">>).
-define(ENGuildMemberChunk, <<"GUILD_MEMBER_CHUNK">>).
-define(ENGuildRoleCreate, <<"GUILD_ROLE_CREATE">>).
-define(ENGuildRoleUpdate, <<"GUILD_ROLE_UPDATE">>).
-define(ENGuildRoleDelete, <<"GUILD_ROLE_DELETE">>).
-define(ENMessageCreate, <<"MESSAGE_CREATE">>).
-define(ENMessageUpdate, <<"MESSAGE_UPDATE">>).
-define(ENMessageDelete, <<"MESSAGE_DELETE">>).
-define(ENMessageDeleteBulk, <<"MESSAGE_DELETE_BULK">>).
-define(ENPresenceUpdate, <<"PRESENCE_UPDATE">>).
-define(ENTypingStart, <<"TYPING_START">>).
-define(ENUserSettingsUpdate, <<"USER_SETTINGS_UPDATE">>).
-define(ENUserUpdate, <<"USER_UPDATE">>).
-define(ENVoiceStatusUpdate, <<"VOICE_STATUS_UPDATE">>).
-define(ENVoiceServerUpdate, <<"VOICE_SERVER_UPDATE">>).

%% Define a map of event names for "event name check"
-define(ENCheck, #{?ENReady => true,
                   ?ENResumed => true,
                   ?ENChannelCreate => true,
                   ?ENChannelUpdate => true,
                   ?ENChannelDelete => true,
                   ?ENGuildCreate => true,
                   ?ENGuildUpdate => true,
                   ?ENGuildDelete => true,
                   ?ENGuildBanAdd => true,
                   ?ENGuildBanRemove => true,
                   ?ENGuildEmojisUpdate => true,
                   ?ENGuildIntegrationsUpdate => true,
                   ?ENGuildMemberAdd => true,
                   ?ENGuildMemberRemove => true,
                   ?ENGuildMemberUpdate => true,
                   ?ENGuildMemberChunk => true,
                   ?ENGuildRoleCreate => true,
                   ?ENGuildRoleUpdate => true,
                   ?ENGuildRoleDelete => true,
                   ?ENMessageCreate => true,
                   ?ENMessageUpdate => true,
                   ?ENMessageDelete => true,
                   ?ENMessageDeleteBulk => true,
                   ?ENPresenceUpdate => true,
                   ?ENTypingStart => true,
                   ?ENUserSettingsUpdate => true,
                   ?ENUserUpdate => true,
                   ?ENVoiceStatusUpdate => true,
                   ?ENVoiceServerUpdate => true}).