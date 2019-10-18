#include <SteamWorks>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = {
	name		= "SourceBans++ Discord",
	author		= "Kotik. Fork of RumbleFrog, SourceBans++ Dev Team.",
	description = "Listens forwards of bans, comms, reports and sends it to Discord webhooks.",
	version		= "1.7.0-39",
	url			= "https://github.com/TheByKotik/sbpp_discord" };

#undef REQUIRE_PLUGIN
	#tryinclude <sourcebanspp>
	#tryinclude <sourcecomms>
#define REQUIRE_PLUGIN

enum	/* Types. */ {
	Type_Unknown = -1,
	Type_Ban,
	Type_Mute,
	Type_Gag,
	Type_Silence,
	Type_Report,
	Types, };
enum	/* g_iSettings. */ {
	Start_Reloads,
		OnConfig = Start_Reloads,
		OnMessage,
	Start_SteamID,
		SteamID3 = Start_SteamID,
		SteamID2,
	Start_Times,
		Time = Start_Times,
		Timestamp,
	Map,
	Start_Hooks,
		BansOn = Start_Hooks,
		MutesOn,
		GagsOn,
		SilencesOn,
		ReportsOn,
	HookParse = 1 << 31,
	SteamID	= (1 << SteamID3) + (1 << SteamID2),
	Times	= (1 << Time) + (1 << Timestamp),
	Reloads	= (1 << OnConfig) + (1 << OnMessage),
	Hooks	= (1 << BansOn) + (1 << MutesOn) + (1 << GagsOn) + (1 << SilencesOn) + (1 << ReportsOn), };
stock char g_szHost[128], g_szHook[Types][PLATFORM_MAX_PATH];
stock int g_iHook[Types], g_iSettings, g_iEmbedColors[Types] = { 0xDA1D87, 0x4362FA, 0x4362FA, 0x4362FA, 0xF9D942 };

public void OnPluginStart ()
{
	LoadTranslations( "sbpp_comms.phrases" );
	LoadTranslations( "sbpp_discord.phrases" );
	RegAdminCmd( "sm_discord_test", sm_discord_test_Handler, ADMFLAG_CONFIG | ADMFLAG_RCON, "Send test message to hook." );
	RegAdminCmd( "sm_discord_reload", sm_discord_reload_Handler, ADMFLAG_CONFIG, "Reload config of sbpp_discord." );
	OnConfigsExecuted();
	ReloadSettings();
}

public void OnConfigsExecuted ()
{
	FindConVar( "hostname" ).GetString( g_szHost, sizeof g_szHost );
	int iIP = SteamWorks_GetPublicIPCell();
	Format( g_szHost, sizeof g_szHost, "%s (%d.%d.%d.%d:%d)", g_szHost, iIP >> 24 & 0x000000FF, iIP >> 16 & 0x000000FF, iIP >> 8 & 0x000000FF, iIP & 0x000000FF, FindConVar( "hostport" ).IntValue );
	if ( g_iSettings & (1 << OnConfig) ) { ReloadSettings(); }
}

stock Action sm_discord_test_Handler (const int iClient, int iArgs)
{
	if ( iArgs ) {
		char szBuf[9], szMessage[128];
		GetCmdArg( 1, szBuf, sizeof szBuf );
		if ( iArgs > 1 ) { GetCmdArg( 2, szMessage, sizeof szMessage ); }
		iArgs = StringToType( szBuf );
		if ( iArgs != Type_Unknown ) {
			SendEmbed( iClient, 0, szMessage[0] ? szMessage : "(╯°□°）╯︵ ┻━┻", iArgs );
			ReplyToCommand( iClient, "%t", "Test message have been send." ); }
		else { ReplyToCommand( iClient, "%t", "Unknown hook type." ); } }
	else { ReplyToCommand( iClient, "%t", "Usage: sm_discord_test" ); }
	return Plugin_Handled;
}

stock Action sm_discord_reload_Handler (const int iClient, const int iArgs)
{
	ReloadSettings();
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
#endif

#if defined _sourcecomms_included
public void SourceComms_OnBlockAdded (int iAdmin, int iTarget, int iTime, int iCommType, char[] szReason)
{
	SendEmbed( iAdmin, iTarget, szReason, iCommType, iTime );
}
#endif

stock void ReloadSettings ()
{
	g_iSettings = (1 << SteamID3);
	g_iEmbedColors = { 0xDA1D87, 0x4362FA, 0x4362FA, 0x4362FA, 0xF9D942 };
	SMCParser Parser = new SMCParser();
	Parser.OnEnterSection = Settings_Parce_NewSection;
	char szBuf[PLATFORM_MAX_PATH];
	BuildPath( Path_SM, szBuf, sizeof szBuf, "configs/sbpp/discord.cfg" );
	if ( FileExists( szBuf ) ) {
		SMCError Status = Parser.ParseFile( szBuf );
		if ( Status != SMCError_Okay ) { LogError(Parser.GetErrorString( Status, szBuf, sizeof szBuf ) ? szBuf : "%t", "Unknown config parse error." ); } }
	g_iSettings = g_iSettings & ~HookParse;
}

stock SMCResult Settings_Parce_NewSection (const SMCParser Parser, const char[] szSection, const bool opt_quotes)
{
	if ( !strcmp( szSection, "Settings" ) ) {
		Parser.OnKeyValue = Settings_Parce_Settings; }
	else if ( !strcmp( szSection, "Colors" ) ) {
		g_iSettings = g_iSettings & ~HookParse;
		Parser.OnKeyValue = Settings_Parce_Hooks; }
	else if ( !strcmp( szSection, "Hooks" ) ) {
		g_iSettings = g_iSettings | HookParse;
		Parser.OnKeyValue = Settings_Parce_Hooks; }
	return SMCParse_Continue;
}

stock SMCResult Settings_Parce_Settings (const SMCParser Parser, const char[] szKey, const char[] szValue, const bool key_quotes, const bool value_quotes)
{
	if ( !strcmp( "SteamID Version", szKey, true ) ) {
		g_iSettings = g_iSettings | ((StringToInt( szValue ) << Start_SteamID) & SteamID ); }
	else if ( !strcmp( "Reload On", szKey, true ) ) {
		g_iSettings = g_iSettings | ((StringToInt( szValue ) << Start_Reloads) & Reloads); }
	else if ( !strcmp( "Map", szKey, true ) ) {
		g_iSettings = g_iSettings | ((StringToInt( szValue ) & 1) << Map); }
	else if ( !strcmp( "Time", szKey, true ) ) {
		g_iSettings = g_iSettings | ((StringToInt( szValue ) << Start_Times) & Times); }
	return SMCParse_Continue;
}

stock SMCResult Settings_Parce_Hooks (const SMCParser Parser, const char[] szKey, const char[] szValue, const bool key_quotes, const bool value_quotes)
{
	if ( szValue[0] ) {
		int iTypeFrom = StringToType( szKey );
		if ( iTypeFrom != Type_Unknown ) {
			if ( g_iSettings & HookParse ) {
				int iTypeTo = StringToType( szValue );
				g_iSettings = g_iSettings | 1 << (iTypeFrom + Start_Hooks);
				if ( iTypeTo == Type_Unknown ) {
					strcopy( g_szHook[iTypeFrom], sizeof g_szHook[], szValue );
					g_iHook[iTypeFrom] = iTypeFrom; }
				else {
					g_iHook[iTypeFrom] = iTypeTo; } }
			else { g_iEmbedColors[iTypeFrom] = StringToInt( szValue, 16 ); } } }
	return SMCParse_Continue;
}

stock void SendEmbed (const int iAuthor, const int iTarget, const char[] szMessage, const int iType, const int iTime = -2)
{
	if ( g_iSettings & (1 << (g_iHook[iType] + Start_Hooks)) ) {
		if ( g_iSettings & (1 << OnMessage) ) { ReloadSettings(); }
		SetGlobalTransTarget( LANG_SERVER );
		char szJson[3072], szBuf[MAX_NAME_LENGTH*2+1], szBuf2[64], szBuf3[64], szBuf256[256];
		if ( IsValidClient( iTarget ) ) {
			GetClientName( iTarget, szBuf, sizeof szBuf );
			EscapeString( szBuf, sizeof szBuf );
			if ( g_iSettings & (1 << SteamID3) ) { GetClientAuthId( iTarget, AuthId_Steam3, szBuf2, sizeof szBuf2 ); }
			if ( g_iSettings & (1 << SteamID2) ) { GetClientAuthId( iTarget, AuthId_Steam2, szBuf3, sizeof szBuf3 ); }
			FormatEx( szBuf256, sizeof szBuf256, "%s %s%s%s%s", szBuf, (g_iSettings & (1 << SteamID3)) ? szBuf2 : "", (g_iSettings & (1 << SteamID2)) ? "[" : "", (g_iSettings & (1 << SteamID2)) ? szBuf3 : "", (g_iSettings & (1 << SteamID2)) ? "]" : ""  );
			FormatEx( szBuf, sizeof szBuf, "%t", "Violator" );
			AddField( szJson, sizeof szJson, szBuf, szBuf256 ); }
		if ( szMessage[0] ) {
			int iSize = strlen( szMessage )*2+1;
			char[] szMsg = new char[iSize];
			strcopy( szMsg, iSize, szMessage );
			EscapeString( szMsg, iSize );
			FormatEx( szBuf, sizeof szBuf, "%t", "Reason" );
			AddField( szJson, sizeof szJson, szBuf, szMsg ); }
		if ( iType < Type_Report && iTime > -2 ) {
			FormatEx( szBuf, sizeof szBuf, "%t", "Duration" );
			if ( !iTime ) {
				FormatEx( szBuf2, sizeof szBuf2, "%t", "ReasonPanel_Perm" ); }
			else if ( iTime == -1 ) {
				FormatEx( szBuf2, sizeof szBuf2, "%t", "ReasonPanel_Temp" ); }
			else {
				FormatEx( szBuf2, sizeof szBuf2, "%t", "ReasonPanel_Time", iTime ); }
			AddField( szJson, sizeof szJson, szBuf, szBuf2 ); }
		if ( iType > Type_Ban && iType < Type_Report ) {
			FormatEx( szBuf, sizeof szBuf, "%t", "CommType" );
			switch ( iType ) {
				case Type_Mute: FormatEx( szBuf2, sizeof szBuf2, "%t", "Mute");
				case Type_Gag: FormatEx( szBuf2, sizeof szBuf2, "%t", "Gag");
				case Type_Silence: FormatEx( szBuf2, sizeof szBuf2, "%t", "Silence"); }
			AddField( szJson, sizeof szJson, szBuf, szBuf2 ); }
		if ( g_iSettings & Times ) {
			int iTimestamp = GetTime();
			FormatEx( szBuf2, sizeof szBuf2, "%t", "Time" );
			if ( g_iSettings & (1 << Time) ) { FormatTime( szBuf3, sizeof szBuf3, "%Y.%m.%d — %H:%M:%S.", iTimestamp ); }
			if ( g_iSettings & (1 << Timestamp) ) {
				FormatEx( szBuf256, sizeof szBuf256, "%s%s%i%s", g_iSettings & (1 << Time) ? szBuf3 : "", g_iSettings & (1 << Time) ? " | " : "", iTimestamp, g_iSettings & (1 << Time) ? "." : "" );
				AddField( szJson, sizeof szJson, szBuf2, szBuf256 ); }
			else {
				AddField( szJson, sizeof szJson, szBuf2, szBuf3 ); } }
		if ( g_iSettings & (1 << Map) ) {
			GetCurrentMap( szBuf256, sizeof szBuf256 );
			FormatEx( szBuf2, sizeof szBuf2, "%t", "Map" );
			AddField( szJson, sizeof szJson, szBuf2, szBuf256 ); }
		if ( IsValidClient( iAuthor ) ) {
			GetClientName( iAuthor, szBuf, sizeof szBuf );
			Format( szBuf, sizeof szBuf, "[%s]", szBuf );	/* Bad fix for non printable chars nicknames. */
			EscapeString( szBuf, sizeof szBuf );
			GetClientAuthId( iAuthor, AuthId_SteamID64, szBuf2, sizeof szBuf2 );
			FormatEx( szBuf256, sizeof szBuf256, "\"url\": \"https://steamcommunity.com/profiles/%s\", \"name\": \"%s\"", szBuf2, szBuf ); }
		else {
			FormatEx( szBuf256, sizeof szBuf256, "\"name\": \"%t\"", "Author Console" ); }
		Format( szJson, sizeof szJson, "{\"username\": \"SourceBans++\", \"avatar_url\": \"https://sbpp.github.io/img/favicons/android-chrome-512x512.png\", \"embeds\": [{\"color\": %i, \"author\": {%s}, \"fields\": [%s], \"footer\": {\"text\": \"%s\", \"icon_url\": \"https://sbpp.github.io/img/favicons/android-chrome-512x512.png\"}}]}",
			g_iEmbedColors[iType],
			szBuf256,
			szJson,
			g_szHost );
		Handle hRequest = SteamWorks_CreateHTTPRequest( k_EHTTPMethodPOST, g_szHook[ g_iHook[iType] ] );
		if ( !hRequest || !SteamWorks_SetHTTPRequestGetOrPostParameter( hRequest, "payload_json", szJson ) || !SteamWorks_SetHTTPCallbacks( hRequest, OnHTTPRequestComplete ) || !SteamWorks_SendHTTPRequest( hRequest ) ) {
			LogError( "%t", "Create HTTP request failed." );
			delete hRequest; } }
}

stock void OnHTTPRequestComplete (Handle hRequest, const bool bFailure, const bool bRequestSuccessful, const EHTTPStatusCode eStatusCode)
{
	if ( bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode204NoContent ) { LogError( "%t", "HTTP request failed with code: %i.%s", eStatusCode, (eStatusCode == k_EHTTPStatusCodeInvalid || eStatusCode == k_EHTTPStatusCode200OK) ? " Webhooks url can be incorrect." : "Empty" ); }
	delete hRequest;
}

stock void AddField (char[] szJson, const int iMaxSize, const char[] szName, const char[] szValue, const bool bInline = false)
{
	Format( szJson, iMaxSize, "%s%s{\"name\": \"%s\", \"value\": \"%s\"%s}", szJson, szJson[0] ? ", " : "", szName, szValue, bInline ? ", \"inline\": true" : "" );
}

stock bool IsValidClient (const int iClient)
{
	return (iClient > 0 && iClient <= MaxClients && IsClientInGame( iClient ));
}

stock void EscapeString (char[] szStr, const int iMaxSize)
{
	ReplaceString( szStr, iMaxSize, "\\", "\\\\", false );
	ReplaceString( szStr, iMaxSize, "\"", "\\\"", false );
}

stock int StringToType (const char[] szStr)
{
	if ( !strcmp( "Bans", szStr, false ) ) { return Type_Ban; }
	else if	( !strcmp( "Silences", szStr, false ) ) { return Type_Silence; }
	else if	( !strcmp( "Mutes", szStr, false ) ) { return Type_Mute; }
	else if	( !strcmp( "Gags", szStr, false ) ) { return Type_Gag; }
	else if	( !strcmp( "Reports", szStr, false ) ) { return Type_Report; }
	else { return Type_Unknown; }
}