#include <SteamWorks>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
	name		= "SourceBans++ Discord Reports",
	author		= "RumbleFrog, SourceBans++ Dev Team",
	description = "Listens for ban & report forward and sends it to webhook endpoints",
	version		= "1.1.0",
	url			= "https://sbpp.github.io"
};

#include <sourcebanspp>
#include <sourcecomms>

enum
{
	Bans	 = 0,
	Mutes	 = 1,
	Gags	 = 2,
	Silences = 3,
	Reports	 = 4,
	Type_Count,
};

enum
{
	SteamID3	= 1 << 0,
	SteamID2	= 1 << 1,
	OnConfig	= 1 << 2,
	OnError		= 1 << 3,
	BansOn		= 1 << 4,
	MutesOn		= 1 << 5,
	GagsOn		= 1 << 6,
	SilencesOn	= 1 << 7,
	ReportsOn	= 1 << 8,
	HookParse	= 1 << 9,
}

stock char szHost[128], szHook[Type_Count][PLATFORM_MAX_PATH];
stock int g_iHook[Type_Count];
stock int g_iSettings;
stock int g_iEmbedColors[Type_Count] = { 0xDA1D87, 0x4362FA, 0x4362FA, 0x4362FA, 0xF9D942 };

public void OnPluginStart ()
{
	LoadTranslations( "sbpp_discord.phrases" );
	LoadTranslations( "sbpp_comms.phrases" );
	RegAdminCmd( "sm_discord_test", sm_discord_test_Handler, ADMFLAG_CONFIG | ADMFLAG_RCON, "Send test message to hook." );
	RegAdminCmd( "sm_discord_reload", sm_discord_reload_Handler, ADMFLAG_CONFIG, "Reload config." );
	OnConfigsExecuted();
	ReloadSettings();
}

public void OnConfigsExecuted ()
{
	FindConVar( "hostname" ).GetString( szHost, sizeof szHost );
	int ip[4];	
	if ( SteamWorks_GetPublicIP( ip ) ) {
		Format( szHost, sizeof szHost, "%s (%d.%d.%d.%d:%d)", szHost, ip[0], ip[1], ip[2], ip[3], FindConVar( "hostport" ).IntValue ); }
	else {
		int iIPB = FindConVar( "hostip" ).IntValue;
		Format( szHost, sizeof szHost, " %s (%d.%d.%d.%d:%d)", szHost, iIPB >> 24 & 0x000000FF, iIPB >> 16 & 0x000000FF, iIPB >> 8 & 0x000000FF, iIPB & 0x000000FF, FindConVar( "hostport" ).IntValue ); }
	if ( g_iSettings & OnConfig ) { ReloadSettings(); }
}

stock Action sm_discord_test_Handler (int iClient, int iArgs)
{
	if ( iArgs ) {
		char szBuf[9], szMessage[128];
		if ( iArgs > 1 ) { GetCmdArg( 2, szMessage, sizeof szMessage ); }
		GetCmdArg( 1, szBuf, sizeof szBuf );
		if ( StrEqual( "Bans", szBuf, false ) ) {
			iArgs = Bans; }
		else if ( StrEqual( "Silences", szBuf, false ) ) {
			iArgs = Silences; }
		else if ( StrEqual( "Mutes", szBuf, false ) ) {
			iArgs = Mutes; }
		else if ( StrEqual( "Gags", szBuf, false ) ) {
			iArgs = Gags; }
		else {
			iArgs = Reports; }
		SendEmbed( iClient, 0, szMessage[0] ? szMessage : "Testing message.", iArgs ); }
	else { ReplyToCommand( iClient, "Usage: sm_discord_test \"Type\" \"Message\"" ); }
	return Plugin_Handled;
}

stock Action sm_discord_reload_Handler (int iClient, int iArgs)
{
	ReloadSettings();
	return Plugin_Handled;
}

public void SBPP_OnBanPlayer (int iAdmin, int iTarget, int iTime, const char[] szReason)
{
	SendEmbed( iAdmin, iTarget, szReason, Bans, iTime );
}

public void SourceComms_OnBlockAdded (int iAdmin, int iTarget, int iTime, int iCommType, char[] szReason)
{
	SendEmbed( iAdmin, iTarget, szReason, iCommType, iTime );
}

public void SBPP_OnReportPlayer (int iReporter, int iTarget, const char[] szReason)
{
	SendEmbed( iReporter, iTarget, szReason, Reports );
}

stock void ReloadSettings ()
{
	g_iSettings = 1;
	g_iEmbedColors = { 0xDA1D87, 0x4362FA, 0x4362FA, 0x4362FA, 0xF9D942 };
	SMCParser smc = new SMCParser();
	smc.OnEnterSection = Settings_Parce_NewSection;
	char szBuf[PLATFORM_MAX_PATH];
	BuildPath( Path_SM, szBuf, sizeof szBuf, "configs/sbpp/discord.cfg" );
	if ( FileExists( szBuf ) ) {
		SMCError err = smc.ParseFile( szBuf );
		if ( err != SMCError_Okay ) {
			PrintToServer( "%s", smc.GetErrorString( err, szBuf, sizeof szBuf ) ? szBuf : "Fatal parse error." ); } }
	g_iSettings = g_iSettings & ~HookParse; 
}

stock SMCResult Settings_Parce_NewSection (SMCParser smc, const char[] szSection, bool opt_quotes)
{
	if ( StrEqual( szSection, "Settings" ) ) {
		smc.OnKeyValue = Settings_Parce_Settings; }
	else if ( StrEqual( szSection, "Colors" ) ) {
		smc.OnKeyValue = Settings_Parce_Hooks; }
	else if ( StrEqual( szSection, "Hooks" ) ) {
		g_iSettings = g_iSettings | HookParse;
		smc.OnKeyValue = Settings_Parce_Hooks; }
	return SMCParse_Continue;
}

stock SMCResult Settings_Parce_Settings (SMCParser smc, const char[] szKey, const char[] szValue, bool key_quotes, bool value_quotes)
{
	if ( StrEqual( "SteamID Version", szKey, true ) ) {
		g_iSettings = (g_iSettings & ~3) | StringToInt( szValue ); }
	else if ( StrEqual( "Reload On", szKey, true ) ) {
		g_iSettings = g_iSettings | (StringToInt( szValue ) << 2); }
	return SMCParse_Continue;
}

stock SMCResult Settings_Parce_Hooks (SMCParser smc, const char[] szKey, const char[] szValue, bool key_quotes, bool value_quotes)
{
	if ( !StrEqual( "", szValue, true ) ) {
		int iType = -1;
		if ( StrEqual( "Reports", szKey, true ) ) {
			iType = Reports; }
		else if ( StrEqual( "Bans", szKey, true ) ) {
			iType = Bans; }
		else if ( StrEqual( "Silences", szKey, true ) ) {
			iType = Silences; }
		else if ( StrEqual( "Mutes", szKey, true ) ) {
			iType = Mutes; }
		else if ( StrEqual( "Gags", szKey, true ) ) {
			iType = Gags; }
		if ( iType != -1 ) {
			if ( g_iSettings & HookParse ) {
				int iType2 = -1;
				g_iSettings = g_iSettings | 1 << (iType + 4);
				if ( StrEqual( "Reports", szValue, true ) ) {
					iType2 = Reports; }
				else if ( StrEqual( "Bans", szValue, true ) ) {
					iType2 = Bans; }
				else if ( StrEqual( "Silences", szValue, true ) ) {
					iType2 = Silences; }
				else if ( StrEqual( "Mutes", szValue, true ) ) {
					iType2 = Mutes; }
				else if ( StrEqual( "Gags", szValue, true ) ) {
					iType2 = Gags; }
				if ( iType2 == -1 ) {
					strcopy( szHook[iType], sizeof szHook[], szValue );
					g_iHook[iType] = iType; }
				else {
					g_iHook[iType] = iType2; } }
			else { g_iEmbedColors[iType] = StringToInt( szValue, 16 ); } } }
	return SMCParse_Continue;
}

stock void SendEmbed (int iAuthor, int iTarget, const char[] szMessage, int iType, int iTime = 0)
{
	if ( g_iSettings & (1 << (g_iHook[iType] + 4)) ) {
		SetGlobalTransTarget( LANG_SERVER );
		char szJson[2048], szBuf[MAX_NAME_LENGTH], szBuf2[64], szBuf3[64], szBuf256[256];
		if ( IsValidClient( iTarget ) ) {
			GetClientName( iTarget, szBuf, sizeof szBuf );
			if ( g_iSettings & SteamID3 ) { GetClientAuthId( iTarget, AuthId_Steam3, szBuf2, sizeof szBuf2 ); }
			if ( g_iSettings & SteamID2 ) { GetClientAuthId( iTarget, AuthId_Steam2, szBuf3, sizeof szBuf3 ); }
			FormatEx( szBuf256, sizeof szBuf256, "%s %s%s%s%s", szBuf, (g_iSettings & SteamID3) ? szBuf2 : "", (g_iSettings & SteamID2) ? "[" : "", (g_iSettings & SteamID2) ? szBuf3 : "", (g_iSettings & SteamID2) ? "]" : ""  );
			FormatEx( szBuf, sizeof szBuf, "%t", "Violator" );
			AddField( szJson, sizeof szJson, szBuf, szBuf256 ); }
		if ( szMessage[0] ) {
			FormatEx( szBuf, sizeof szBuf, "%t", "Reason" );
			AddField( szJson, sizeof szJson, szBuf, szMessage ); }
		if ( iType < Reports ) {
			FormatEx( szBuf, sizeof szBuf, "%t", "Duration" );
			if ( !iTime ) {
				FormatEx( szBuf2, sizeof szBuf2, "%t", "ReasonPanel_Perm" ); }
			else if ( iTime == -1 ) {
				FormatEx( szBuf2, sizeof szBuf2, "%t", "ReasonPanel_Temp" ); }
			else {
				FormatEx( szBuf2, sizeof szBuf2, "%t", "ReasonPanel_Time", iTime ); }
			AddField( szJson, sizeof szJson, szBuf, szBuf2 ); }
		if ( iType > Bans && iType < Reports ) {
			FormatEx( szBuf, sizeof szBuf, "%t", "CommType" );
			switch ( iType ) {
				case Mutes: FormatEx( szBuf2, sizeof szBuf2, "%t", "Mute");
				case Gags: FormatEx( szBuf2, sizeof szBuf2, "%t", "Gag");
				case Silences: FormatEx( szBuf2, sizeof szBuf2, "%t", "Silence"); }
			AddField( szJson, sizeof szJson, szBuf, szBuf2 ); }
		if ( IsValidClient( iAuthor ) ) {
			GetClientName( iAuthor, szBuf, sizeof szBuf );
			GetClientAuthId( iAuthor, AuthId_SteamID64, szBuf2, sizeof szBuf2 );
			FormatEx( szBuf256, sizeof szBuf256, "\"url\": \"https://steamcommunity.com/profiles/%s\", \"name\": \"%s\"", szBuf2, szBuf ); }
		else {
			FormatEx( szBuf256, sizeof szBuf256, "\"name\": \"%t\"", "Author Console" ); }
		Format( szJson, sizeof szJson, "{\"username\": \"SourceBans++\", \"avatar_url\": \"https://sbpp.github.io/img/favicons/android-chrome-512x512.png\", \"embeds\": [{\"color\": %i, \"author\": {%s}, \"fields\": [%s], \"footer\": {\"text\": \"%s\", \"icon_url\": \"https://sbpp.github.io/img/favicons/android-chrome-512x512.png\"}}]}",
			g_iEmbedColors[iType],
			szBuf256,
			szJson,
			szHost );
		Handle hRequest = SteamWorks_CreateHTTPRequest( k_EHTTPMethodPOST, szHook[ g_iHook[iType] ] );
		if ( !hRequest || !SteamWorks_SetHTTPRequestGetOrPostParameter( hRequest, "payload_json", szJson ) || !SteamWorks_SetHTTPCallbacks( hRequest, OnHTTPRequestComplete ) || !SteamWorks_SendHTTPRequest( hRequest ) ) {
			if ( g_iSettings & OnError ) {
				ReloadSettings();
				LogError( "HTTP request failed." );
				delete hRequest; } } }
}

stock void OnHTTPRequestComplete (Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
	if ( bFailure || !bRequestSuccessful && eStatusCode != k_EHTTPStatusCode200OK ) {
		if ( g_iSettings & OnError ) { ReloadSettings(); }
		LogError( "HTTP request failed." ); }
	delete hRequest;
}

stock void AddField (char[] szJson, int iMaxSize, char[] szName, const char[] szValue, bool bInline = false)
{
	Format( szJson, iMaxSize, "%s%s{\"name\": \"%s\", \"value\": \"%s\"%s}", szJson, szJson[0] ? ", " : "", szName, szValue, bInline ? ", \"inline\": true" : "" );
}

stock bool IsValidClient (int iClient)
{
	return (iClient > 0 && iClient <= MaxClients && IsClientInGame( iClient ));
}