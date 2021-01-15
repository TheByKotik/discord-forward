#include <system2>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = {
	name		= "SourceBans++ Discord",
	author		= "Kotik. Fork of RumbleFrog, SourceBans++ Dev Team.",
	description = "Listens forwards of bans, comms, reports and sends it to Discord webhooks.",
	version		= "1.7.0-48",
	url			= "https://github.com/TheByKotik/sbpp_discord" };

#undef REQUIRE_PLUGIN
	#tryinclude <sourcebanspp>
	#tryinclude <sourcecomms>
#define REQUIRE_PLUGIN

enum /* Types. */ {
	Type_Unknown = -1,
	Type_Ban,
	Type_Mute,
	Type_Gag,
	Type_Silence,
	Type_Report,
	Types };
enum /* g_iSettings. */ {
	g_iSettings_Reload					= 0,
		g_iSettings_Reload_OnConfigs		= 1 << 0,
		g_iSettings_Reload_OnSend			= 1 << 1,
	g_iSettings_SteamID					= 2,
		g_iSettings_SteamID3				= 1 << 2,
		g_iSettings_SteamID2				= 1 << 3,
		g_iSettings_SteamID64				= 1 << 4,
	g_iSettings_Map						= 5,
		g_iSettings_Map_Path				= 1 << 5,
	g_iSettings_Time					= 6,
		g_iSettings_Time_Date				= 1 << 6,
		g_iSettings_Time_Timestamp			= 1 << 7,
	g_iSettings_Section_Reload	= g_iSettings_Reload_OnConfigs | g_iSettings_Reload_OnSend,
	g_iSettings_Section_SteamID	= g_iSettings_SteamID3 | g_iSettings_SteamID2 | g_iSettings_SteamID64,
	g_iSettings_Section_Map		= g_iSettings_Map_Path,
	g_iSettings_Section_Time	= g_iSettings_Time_Date | g_iSettings_Time_Timestamp };
int g_iSettings, g_iType, g_iEmbedColors[Types];
char g_szHost[128], g_szIP[24] = "(";
DataPack g_dpWebhookIcon[Types], g_dpServerIcon;
System2HTTPRequest g_hWebhook[Types];

#define IsValidClient(%0) (%0 > 0 && %0 <= MaxClients && IsClientInGame( %0 ))

public void OnPluginStart ()
{
	LoadTranslations( "sbpp_comms.phrases" );
	LoadTranslations( "sbpp_discord.phrases" );
	RegAdminCmd( "sm_discord_test", sm_discord_test_Handler, ADMFLAG_CONFIG | ADMFLAG_RCON, "Send test message to hook." );
	RegAdminCmd( "sm_discord_reload", sm_discord_reload_Handler, ADMFLAG_CONFIG, "Reload config of sbpp_discord." );
	ConVar Cvar = FindConVar( "hostname" );
	Cvar.AddChangeHook( hostname_OnChanged );
	hostname_OnChanged( Cvar, "", "" );
	Settings_Reload();
}

public void OnConfigsExecuted ()
{
	if ( g_iSettings & g_iSettings_Reload_OnConfigs ) { Settings_Reload(); }
}

void OnIPGetted (const bool bSuccess, const char[] szError, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method)
{
	int i = 1;
	if ( bSuccess && response.StatusCode == 200 ) {
		response.GetContent( g_szIP[1], sizeof g_szIP-1, 76, "<" );
		i = strlen( g_szIP )-1; }
	FormatEx( g_szIP[i], sizeof g_szIP-i, ":%i)", FindConVar( "hostport" ).IntValue );
}

void hostname_OnChanged (const ConVar Cvar, const char[] szOld, const char[] szNew)
{
	Cvar.GetString( g_szHost, sizeof g_szHost );
	EscapeRequest( g_szHost, sizeof g_szHost );
}

Action sm_discord_test_Handler (const int iClient, int iArgs)
{
	if ( iArgs ) {
		char szBuf[9], szMessage[128];
		GetCmdArg( 1, szBuf, sizeof szBuf );
		if ( iArgs > 1 ) { GetCmdArg( 2, szMessage, sizeof szMessage ); }
		iArgs = StringToType( szBuf );
		if ( iArgs != Type_Unknown ) {
			SendEmbed( iClient, iClient, szMessage[0] ? szMessage : "(╯°□°）╯︵ ┻━┻", iArgs );
			ReplyToCommand( iClient, "%t", "Test message have been send." ); }
		else { ReplyToCommand( iClient, "%t", "Unknown hook type." ); } }
	else { ReplyToCommand( iClient, "%t", "Usage: sm_discord_test" ); }
	return Plugin_Handled;
}

Action sm_discord_reload_Handler (const int iClient, const int iArgs)
{
	Settings_Reload();
	ReplyToCommand( iClient, "%t", "Config have been reloaded." );
	return Plugin_Handled;
}

#if defined _sourcebanspp_included
public void SBPP_OnBanPlayer (int iAdmin, int iTarget, int iTime, const char[] szReason)
{
	SendEmbed( iAdmin, iTarget, szReason, Type_Ban, iTime );
}

public void SBPP_OnReportPlayer (int iReporter, int iTarget, const char[] szReason)
{
	SendEmbed( iReporter, iTarget, szReason, Type_Report );
}
#else
	#warning "Compiled without SourceBans natives."
#endif

#if defined _sourcecomms_included
public void SourceComms_OnBlockAdded (int iAdmin, int iTarget, int iTime, int iCommType, char[] szReason)
{
	SendEmbed( iAdmin, iTarget, szReason, iCommType, iTime );
}
#else
	#warning "Compiled without SourceComms natives."
#endif

void SendEmbed (const int iAuthor, const int iTarget, const char[] szMessage, const int iType, const int iTime = 0)
{
	if ( g_iSettings & g_iSettings_Reload_OnSend ) { Settings_Reload(); }
	if ( g_hWebhook[ iType ] ) {
		SetGlobalTransTarget( LANG_SERVER );
		static char szJson[3038 + sizeof g_szHost-1 + sizeof g_szIP-1] = "payload_json={\"username\": \"SourceBans++\", \"avatar_url\": \"https://sbpp.github.io/img/favicons/android-chrome-512x512.png\", \"embeds\": [{\"color\": ";
		int iFields, iLen = 143 + FormatEx( szJson[143], 10+24+1, "%i, \"author\": {\"name\": \"> ", g_iEmbedColors[iType] );
		if ( IsValidClient( iAuthor ) ) {
			GetClientName( iAuthor, szJson[iLen], 255-2+1 );
			EscapeRequest( szJson[iLen], 255-2+1 );
			iLen += strlen( szJson[iLen] );
			iLen += strcopy( szJson[iLen], 47+1, "\", \"url\": \"https://steamcommunity.com/profiles/" );
			GetClientAuthId( iAuthor, AuthId_SteamID64, szJson[iLen], 20+1 );
			iLen += strlen( szJson[iLen] );
			iLen += strcopy( szJson[iLen], 15+1, "\"}, \"fields\": [" ); }
		else { iLen += FormatEx( szJson[iLen], 15+63+1, "%t\"}, \"fields\": [", "Author Console" ); }
		if ( IsValidClient( iTarget ) ) {
			iLen += FormatEx( szJson[iLen], 23+63+1, "{\"name\": \"%t\", \"value\": \"", "Violator" );
			GetClientName( iTarget, szJson[iLen], 255-3-18-24-36-20+1 ); // 3 = ' []', 18 = SteamID3, 24 = SteamID2 + [], 36 = SteamURL, 20 = SteamID64;
			EscapeMarkdown( szJson[iLen], 255-3-18-24-36-20+1 );
			szJson[ iLen += strlen( szJson[iLen] ) ] = ' ';
			++iLen;
			if ( g_iSettings & g_iSettings_SteamID64 ) { szJson[iLen++] = '['; }
			if ( g_iSettings & g_iSettings_SteamID3 && GetClientAuthId( iTarget, AuthId_Steam3, szJson[iLen], 18+1 ) ) { iLen += strlen( szJson[iLen] ); }
			if ( g_iSettings & g_iSettings_SteamID2 ) {
				szJson[iLen++] = '[';
				GetClientAuthId( iTarget, AuthId_Steam2, szJson[iLen], 22+1 );
				szJson[ iLen += strlen( szJson[iLen] ) ] = ']';
				++iLen; }
			if ( g_iSettings & g_iSettings_SteamID64 ) {
				if ( szJson[iLen-1] == '[' ) { iLen += strcopy( szJson[iLen], 7+1, "[steam]" ); }
				szJson[iLen++] = ']';
				szJson[iLen++] = '(';
				iLen += strcopy( szJson[iLen], 47+1, "https://steamcommunity.com/profiles/" );
				GetClientAuthId( iTarget, AuthId_SteamID64, szJson[iLen], 20+1 );
				iLen += strlen( szJson[iLen] );
				szJson[iLen++] = ')'; }
			szJson[ iLen++ ] = '\"';
			szJson[ iLen++ ] = '}';
			++iFields; }
		if ( szMessage[0] ) {
			if ( iFields++ ) { szJson[ iLen++ ] = ','; }
			iLen += FormatEx( szJson[iLen], 23+63+1, "{\"name\": \"%t\", \"value\": \"", "Reason" );
			strcopy( szJson[iLen], 255+1, szMessage );
			EscapeMarkdown( szJson[iLen], 255+1 );
			szJson[ iLen += strlen( szJson[iLen] ) ] = '\"';
			++iLen;
			szJson[ iLen++ ] = '}'; }
		if ( iType != Type_Report ) {
			if ( iType > Type_Ban ) {
				if ( iFields++ ) { szJson[ iLen++ ] = ','; }
				iLen += FormatEx( szJson[iLen], 23+63+63+2+1, "{\"name\": \"%t\", \"value\": \"%t\"}", "CommType", iType == Type_Mute ? "Mute" : iType == Type_Gag ? "Gag" : "Silence" ); }
			if ( iFields++ ) { szJson[ iLen++ ] = ','; }
			iLen += FormatEx( szJson[iLen], 23+63+63+2+1, "{\"name\": \"%t\", \"value\": \"%t\"}", "Duration", !iTime ? "ReasonPanel_Perm" : iTime == -1 ? "ReasonPanel_Temp" : "ReasonPanel_Time", iTime ); }
		if ( g_iSettings & g_iSettings_Map_Path ) {
			if ( iFields++ ) { szJson[ iLen++ ] = ','; }
			iLen += FormatEx( szJson[iLen], 23+63+1, "{\"name\": \"%t\", \"value\": \"", "Map" );
			GetCurrentMap( szJson[iLen], 255+1 );
			szJson[ iLen += strlen( szJson[iLen] ) ] = '\"';
			++iLen;
			szJson[ iLen++ ] = '}'; }
		if ( g_iSettings & g_iSettings_Section_Time ) {
			if ( iFields++ ) { szJson[ iLen++ ] = ','; }
			iLen += FormatEx( szJson[iLen], 23+63+1, "{\"name\": \"%t\", \"value\": \"", "Time" );
			int iTimestamp = GetTime();
			if ( g_iSettings & g_iSettings_Time_Date ) {
				FormatTime( szJson[iLen], 20+1, "%Y.%m.%d, %H:%M:%S", iTimestamp );
				if ( (iLen += 20), g_iSettings & g_iSettings_Time_Timestamp ) { iLen += FormatEx( szJson[iLen], 6+10+1, " ... %i.", iTimestamp ); }
				else { szJson[ iLen++ ] = '.'; } }
			else { iLen += FormatEx( szJson[iLen], 10+1+1, "%i.", iTimestamp ); }
			szJson[ iLen++ ] = '\"';
			szJson[ iLen++ ] = '}'; }
		iLen += strcopy( szJson[iLen], 22+1, "],\"thumbnail\":{\"url\":\"" );
		if ( g_dpWebhookIcon[ iType ] ) {
			g_dpWebhookIcon[ iType ].ReadString( szJson[iLen], 512 );
			g_dpWebhookIcon[ iType ].Reset();
			iLen += strlen( szJson[iLen] );
			szJson[iLen++] = '"';
			szJson[iLen++] = '}';
			szJson[iLen++] = ','; }
		else { iLen += strcopy( szJson[iLen], 62+3+1, "https://sbpp.github.io/img/favicons/android-chrome-512x512.png" ... "\"}," ); }
		iLen += FormatEx( szJson[iLen], 33 + sizeof g_szHost-1 + sizeof g_szIP-1 + 1, "\"footer\":{\"text\":\"%s %s\",\"icon_url\":\"", g_szHost, g_szIP );
		if ( g_dpServerIcon ) {
			g_dpServerIcon.ReadString( szJson[iLen], 512 );
			g_dpServerIcon.Reset();
			iLen += strlen( szJson[iLen] );
			szJson[iLen++] = '"';
			szJson[iLen++] = '}';
			szJson[iLen++] = '}';
			szJson[iLen++] = ']';
			szJson[iLen++] = '}';
			szJson[iLen] = '\0'; }
		else { iLen += strcopy( szJson[iLen], 62+5+1, "https://sbpp.github.io/img/favicons/android-chrome-512x512.png" ... "\"}}]}" ); }
		g_hWebhook[ iType ].SetData( szJson );
		g_hWebhook[ iType ].POST(); }
}

void SendEmbed_Callback (const bool bSuccess, const char[] szError, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method)
{
	if ( !bSuccess || szError[0] || response.StatusCode != 204 ) { LogError( "%t", "HTTP request failed with code: %i.%s", response.StatusCode, (response.StatusCode == 0 || response.StatusCode == 200) ? " Webhooks url can be incorrect." : "Empty" ); }
}

void EscapeMarkdown (char[] szStr, const int iSize)
{
	ReplaceString( szStr, iSize, "\\", "\\\\" );
	ReplaceString( szStr, iSize, "`", "\\`" );
	ReplaceString( szStr, iSize, "*", "\\*" );
	ReplaceString( szStr, iSize, "_", "\\_" );
	ReplaceString( szStr, iSize, "~", "\\~" );
	ReplaceString( szStr, iSize, "#", "\\#" );
	ReplaceString( szStr, iSize, "@", "\\@" );
	ReplaceString( szStr, iSize, ">", "\\>" );
	ReplaceString( szStr, iSize, "[", "\\[" );
	ReplaceString( szStr, iSize, "]", "\\]" );
	ReplaceString( szStr, iSize, "(", "\\(" );
	ReplaceString( szStr, iSize, ")", "\\)" );
	EscapeRequest( szStr, iSize );
}

void EscapeRequest (char[] szStr, const int iSize)
{
	ReplaceString( szStr, iSize, "\"", "\\\"" );
	ReplaceString( szStr, iSize, "\\", "\\\\" );
	int i = strlen( szStr );
	if ( i == iSize-1 ) {
		while ( --i != -1 && szStr[i] == '\\' ) {}
		szStr[ iSize-1-((iSize-2-i)%2) ] = '\0'; }
}

void Settings_Reload ()
{
	System2HTTPRequest hReq = new System2HTTPRequest( OnIPGetted, "http://checkip.dyndns.org" );
	hReq.GET();
	CloseHandle( hReq );
	int i;
	for ( ; i < Types; ++i ) {
		delete g_hWebhook[i];
		delete g_dpWebhookIcon[i]; }
	delete g_dpServerIcon;
	g_iSettings = g_iSettings_SteamID3;
	g_iEmbedColors = { 0xDA1D87, 0x4362FA, 0x4362FA, 0x4362FA, 0xF9D942 };
	SMCParser Parser = new SMCParser();
	Parser.OnEnterSection = Settings_Parce_OnEnterSection;
	char szBuf[PLATFORM_MAX_PATH];
	BuildPath( Path_SM, szBuf, sizeof szBuf, "configs/sbpp/discord.cfg" );
	if ( FileExists( szBuf ) ) {
		SMCError Status = Parser.ParseFile( szBuf );
		if ( Status != SMCError_Okay ) { LogError( Parser.GetErrorString( Status, szBuf, sizeof szBuf ) ? szBuf : "%t", "Unknown config parse error." ); } }
	for ( i = 0; i < Types; ++i ) {
		Resolve( g_hWebhook, i );
		Resolve( g_dpWebhookIcon, i ); }
}

SMCResult Settings_Parce_OnEnterSection (const SMCParser Parser, const char[] szSection, const bool opt_quotes)
{
	if ( !strcmp( szSection, "Settings" ) ) {
		Parser.OnKeyValue = Settings_Parse_Settings; }
	else if ( !strcmp( szSection, "Hooks" ) ) {
		Parser.OnKeyValue = Settings_Parse_Hooks; }
	else {
		g_iType = StringToType( szSection ); }
	return SMCParse_Continue;
}

SMCResult Settings_Parse_Settings (const SMCParser Parser, const char[] szKey, const char[] szValue, const bool key_quotes, const bool value_quotes)
{
	if ( szValue[0] ) {
		#define SetFlags(%0,%1) (g_iSettings & ~%0 | StringToInt( szValue ) << %1 & %0)
		if ( !strcmp( "Reload On", szKey ) ) {
			g_iSettings = SetFlags( g_iSettings_Section_Reload, g_iSettings_Reload ); }
		else if ( !strcmp( "SteamID Version", szKey ) ) {
			g_iSettings = SetFlags( g_iSettings_Section_SteamID, g_iSettings_SteamID ); }
		else if ( !strcmp( "Map", szKey ) ) {
			g_iSettings = SetFlags( g_iSettings_Section_Map, g_iSettings_Map ); }
		else if ( !strcmp( "Time", szKey ) ) {
			g_iSettings = SetFlags( g_iSettings_Section_Time, g_iSettings_Time ); }
		#undef SetFlags
		else if ( !strcmp( "Server Icon URL", szKey ) ) {
			g_dpServerIcon = new DataPack();
			g_dpServerIcon.WriteString( szValue );
			g_dpServerIcon.Reset(); } }
	return SMCParse_Continue;
}

SMCResult Settings_Parse_Hooks (const SMCParser Parser, const char[] szKey, const char[] szValue, const bool key_quotes, const bool value_quotes)
{
	if ( szValue[0] && g_iType != Type_Unknown ) {
		if ( !strcmp( "Color", szKey ) ) {
			g_iEmbedColors[g_iType] = StringToInt( szValue, 16 ); }
		else if ( !strcmp( "Icon", szKey ) ) {
			int iRedir = StringToType( szValue );
			if ( iRedir == Type_Unknown ) {
				g_dpWebhookIcon[ g_iType ] = new DataPack();
				g_dpWebhookIcon[ g_iType ].WriteString( szValue );
				g_dpWebhookIcon[ g_iType ].Reset(); }
			else {
				g_dpWebhookIcon[ g_iType ] = view_as<DataPack>( iRedir + 1 ); } }
		else if ( !strcmp( "Webhook", szKey ) ) {
			int iRedir = StringToType( szValue );
			if ( iRedir == Type_Unknown ) {
				g_hWebhook[ g_iType ] = new System2HTTPRequest( SendEmbed_Callback, szValue ); }
			else {
				g_hWebhook[ g_iType ] = view_as<System2HTTPRequest>( iRedir + 1 ); } } }
	return SMCParse_Continue;
}

void Resolve (Handle[] hRedir, const int iType, const int it = 0)
{
	if ( it < Types ) {
		int i = view_as<int>( hRedir[ iType ] ) - 1;
		if ( i != Type_Unknown && i < Types ) {
			Resolve( hRedir, i, it + 1 );
			hRedir[ iType ] = view_as<int>( hRedir[i] ) > Types ? CloneHandle( hRedir[ i ] ) : INVALID_HANDLE; } }
	else { hRedir[ iType ] = INVALID_HANDLE; }
}

int StringToType (const char[] szStr)
{
	if ( !strcmp( "Bans", szStr, false ) ) { return Type_Ban; }
	else if	( !strcmp( "Silences", szStr, false ) ) { return Type_Silence; }
	else if	( !strcmp( "Mutes", szStr, false ) ) { return Type_Mute; }
	else if	( !strcmp( "Gags", szStr, false ) ) { return Type_Gag; }
	else if	( !strcmp( "Reports", szStr, false ) ) { return Type_Report; }
	else { return Type_Unknown; }
}