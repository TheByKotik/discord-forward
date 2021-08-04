#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = {
	name        = "SourceBans++ Discord",
	author      = "Kotik. Fork of RumbleFrog, SourceBans++ Dev Team.",
	description = "Sends notifications to Discord about bans, comms and reports.",
	version     = "1.7.0-50",
	url         = "https://github.com/TheByKotik/sbpp_discord" };

#include <system2>
#undef REQUIRE_PLUGIN
	#tryinclude <sourcebanspp>
	#tryinclude <sourcecomms>

enum /* Types */ {
	Type_Unknown = -1,
	Type_Ban,
	Type_Mute,
	Type_Gag,
	Type_Silence,
	Type_Report,
	Types };

public const char g_sHookName[][] = { "Bans", "Mutes", "Gags", "Silences", "Reports" };

System2HTTPRequest g_hWebhook[Types];
DataPack g_dpWebhookIcon[Types], g_dpServerIcon, g_dpSBPP_URL;
char g_szHost[128], g_szIP[ 3 + 39 + 5 + 1 ] = "(";
int g_iType, g_iTimeshift, g_iEmbedColors[Types];
bool g_bFieldMap;

public void OnPluginStart ()
{
	LoadTranslations( "sbpp_discord.phrases" );

	RegAdminCmd( "sbpp_discord_test", sbpp_discord_test, ADMFLAG_CONFIG + ADMFLAG_RCON, "Send a test notification." );

	ConVar Cvar = FindConVar( "hostname" );
	Cvar.AddChangeHook( hostname_OnChanged );
	hostname_OnChanged( Cvar, "", "" );

	System2HTTPRequest hReq = new System2HTTPRequest( OnIPGetted, "http://checkip.dyndns.org" );
	hReq.GET();
	CloseHandle( hReq );

	SMCParser Parser = new SMCParser();
	Parser.OnEnterSection = Settings_Parce_OnEnterSection;
	Parser.OnKeyValue = Settings_Parse_Settings;
	char szBuf[PLATFORM_MAX_PATH];
	BuildPath( Path_SM, szBuf, sizeof szBuf, "configs/sbpp/discord.cfg" );
	if ( FileExists( szBuf ) ) {
		SMCError Error = Parser.ParseFile( szBuf );
		if ( !Error ) {
			for ( int i; i < Types; ++i ) {
				Resolve( g_hWebhook, i );
				Resolve( g_dpWebhookIcon, i ); } }
		else {
			LogError( Parser.GetErrorString( Error, szBuf, sizeof szBuf ) ? szBuf : "%t", "Unknown config parse error." ); } }
	else {
		LogError( "%t", "Config file '%s' not found.", szBuf ); }
}

Action sbpp_discord_test (const int iClient, const int iArgs)
{
	if ( iArgs ) {
		char szBuf[256];
		GetCmdArg( 1, szBuf, 10 );
		int iType = StringToType( szBuf );
		if ( iType != Type_Unknown ) {
			int iTime;
			if ( iArgs > 2 ) {
				GetCmdArg( 3, szBuf, 9 );
				iTime = StringToInt( szBuf ); }
			SendEmbed( iClient, iClient, iArgs > 1 && GetCmdArg( 2, szBuf, sizeof szBuf ) ? szBuf : "", iType, iTime );
			ReplyToCommand( iClient, "SB++ Discord: %t", "Test message have been send." ); }
		else {
			ReplyToCommand( iClient, "SB++ Discord: %t", "Unknown webhook." ); } }
	else {
		ReplyToCommand( iClient, "%t: %ssbpp_discord_test %t %t %t", "Syntax", GetCmdReplySource() == SM_REPLY_TO_CHAT ? "!" : "", "Name_of_webhook", "Message", "Duration" ); }
	return Plugin_Handled;
}

#if defined _sourcebanspp_included
public void SBPP_OnBanPlayer (int iAdmin, int iTarget, int iTime, const char[] szReason)
{
	SendEmbed( iTarget, iAdmin, szReason, Type_Ban, iTime );
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
	SendEmbed( iTarget, iAdmin, szReason, iCommType, iTime );
}
#else
	#warning "Compiled without SourceComms natives."
#endif

void SendEmbed (const int iAuthor, const int iTarget, const char[] szMessage, const int iType, int iTime = 0)
{
	#define IsValidClient(%0) (%0 > 0 && %0 <= MaxClients && IsClientInGame( %0 ))
	#define copy(%0) (iLen += strcopy( szJson[ iLen ], sizeof szJson, %0 ))
	#define format(%0,%1) (iLen += FormatEx( szJson[ iLen ], sizeof szJson, %0 , %1 ))
	#define append(%0) (szJson[ iLen++ ] = %0)
	#define new_field(%0); copy( "{\"name\":\"" ); format( "%t", %0 ); copy( "\",\"value\":\"" );

	if ( g_hWebhook[ iType ] ) {
		static char szJson[4196] = "payload_json={\"username\":\"SourceBans%%2B%%2B | ";
		static int iLen, iFields;
		
		SetGlobalTransTarget( LANG_SERVER );
		iLen = 47 + FormatEx( szJson[ 47 ], sizeof szJson, "%t", g_sHookName[ iType ] );
		copy( "\",\"avatar_url\":\"https://sbpp.github.io/img/favicons/android-chrome-512x512.png\",\"embeds\":[{\"color\":" );
		format( "%u", g_iEmbedColors[ iType ] );

		copy( ",\"author\":{\"name\":\"" );
		if ( IsValidClient( iAuthor ) ) {
			GetClientName( iAuthor, szJson[ iLen ], 256 );
			iLen += EscapeRequest( szJson[ iLen ], 256 );
			copy( "\"},\"description\":\"" );
			#define iClient iAuthor
			#include "inline/FormatPlayerLinks.sp"
			append( '"' ); }
		else { format( "%t" ... "\"}", "Console" ); }

		copy( ",\"thumbnail\":{\"url\":\"" );
		if ( g_dpWebhookIcon[ iType ] ) {
			g_dpWebhookIcon[ iType ].Reset();
			g_dpWebhookIcon[ iType ].ReadString( szJson[ iLen ], 512 );
			iLen += strlen( szJson[ iLen ] );
			append( '"' );
			append( '}' ); }
		else { copy( "https://sbpp.github.io/img/favicons/android-chrome-512x512.png" ... "\"}" ); }

		copy( ",\"footer\":{\"text\":\"" );
		copy( g_szHost );
		append( ' ' );
		copy( g_szIP );
		copy( "\",\"icon_url\":\"" );
		if ( g_dpServerIcon ) {
			g_dpServerIcon.Reset();
			g_dpServerIcon.ReadString( szJson[ iLen ], 512 );
			iLen += strlen( szJson[ iLen ] );
			append( '"' );
			append( '}' ); }
		else { copy( "https://sbpp.github.io/img/favicons/android-chrome-512x512.png" ... "\"}" ); }

		copy( ",\"timestamp\":\"" );
		FormatTime( szJson[ iLen ], sizeof szJson, "%FT%T", GetTime() - g_iTimeshift );
		iLen += strlen( szJson[ iLen ] );
		append( '"' );

		iFields = 0;
		copy( ",\"fields\":[" );

		if ( szMessage[0] ) {
			++iFields;
			new_field( iType == Type_Report ? "Message:" : "Reason:" );
			strcopy( szJson[ iLen ], 256, szMessage );
			iLen += EscapeMarkdown( szJson[ iLen ], 256 );
			append( '"' );
			append( '}' ); }

		if ( iType != Type_Report ) {
			if ( iFields++ ) { append( ',' ); }
			new_field( "Duration:" );
			if ( !iTime ) {
				format( "%t\"}", "Permanent." ); }
			else if ( iType != Type_Ban && iTime == -1 ) {
				format( "%t\"}", "Session." ); }
			else {
				#define T1 ... " {N == 1}"
				#define T2 ... " {N % 10 == 1 && N % 100 != 11}"
				#define T3 ... " {N % 10 > 1 && N % 10 < 5}"
				#define T4 ... " {N % 10 > 5 || N % 100 == 11}"
				#define generate_phrases(%0) { %0T1, %0T2, %0T3, %0T4 }

				static const char szTimes[][][] = {
					generate_phrases( "Years" ),
					generate_phrases( "Months" ),
					generate_phrases( "Weeks" ),
					generate_phrases( "Days" ),
					generate_phrases( "Hours" ),
					generate_phrases( "Minutes" ) };

				#undef T1
				#undef T2
				#undef T3
				#undef T4
				#undef generate_phrases

				static int i, iTimes[6];
				iTimes[0] = iTime / (365 * 24 * 60);
				iTime     = iTime % (365 * 24 * 60);
				iTimes[1] = iTime / (30 * 24 * 60);
				iTime     = iTime % (30 * 24 * 60);
				iTimes[2] = iTime / (7 * 24 * 60);
				iTime     = iTime % (7 * 24 * 60);
				iTimes[3] = iTime / (24 * 60);
				iTime     = iTime % (24 * 60);
				iTimes[4] = iTime / 60;
				iTimes[5] = iTime % 60;

				for ( i = 0; i < sizeof iTimes; ++i ) {
					if ( iTimes[i] ) {
						format( "%u ", iTimes[i] );
						if ( iTimes[i] == 1 ) {
							format( "%t", szTimes[i][0] ); }
						else if ( iTimes[i] % 10 == 1 ) {
							if ( iTimes[i] % 100 == 11 ) {
								format( "%t", szTimes[i][3] ); }
							else {
								format( "%t", szTimes[i][1] ); } }
						else if ( iTimes[i] % 10 > 5 ) {
							format( "%t", szTimes[i][2] ); }
						else {
							format( "%t", szTimes[i][3] ); }
						++i;
						break; } }

				for ( ; i < sizeof iTimes; ++i ) {
					if ( iTimes[i] ) {
						format( ", %u ", iTimes[i] );
						if ( iTimes[i] == 1 ) {
							format( "%t", szTimes[i][0] ); }
						else if ( iTimes[i] % 10 == 1 ) {
							if ( iTimes[i] % 100 == 11 ) {
								format( "%t", szTimes[i][3] ); }
							else {
								format( "%t", szTimes[i][1] ); } }
						else if ( iTimes[i] % 10 > 5 ) {
							format( "%t", szTimes[i][2] ); }
						else {
							format( "%t", szTimes[i][3] ); } } }
				append( '.' );
				append( '"' );
				append( '}' ); } }

		if ( IsValidClient( iTarget ) ) {
			if ( iFields++ ) { append( ',' ); }
			new_field( iType == Type_Report ? "Violator:" : "Blocked by:" );
			GetClientName( iTarget, szJson[ iLen ], 256 );
			iLen += EscapeMarkdown( szJson[ iLen ], 256 );
			append( '\\' );
			append( 'n' );
			#define iClient iTarget
			#include "inline/FormatPlayerLinks.sp"
			#undef iClient
			append( '"' );
			append( '}' ); }
		else if ( iType != Type_Report ) {
			if ( iFields++ ) { append( ',' ); }
			new_field( "Blocked by" );
			format( "%t\"}", "Console" ); }

		if ( g_bFieldMap ) {
			if ( iFields ) { append( ',' ); }
			new_field( "Map:" );
			iLen += GetCurrentMap( szJson[ iLen ], 256 );
			append( '"' );
			append( '}' ); }
		append( ']' );
		append( '}' );
		append( ']' );
		append( '}' );
		szJson[ iLen ] = '\0';

		g_hWebhook[ iType ].SetData( szJson );
		g_hWebhook[ iType ].POST(); }
	#undef IsValidClient
	#undef copy
	#undef format
	#undef append
	#undef new_field
}

public void SendEmbed_Callback (const bool bSuccess, const char[] szError, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method)
{
	if ( bSuccess && response && response.StatusCode != 204 ) { LogError( "%t", "HTTP request failed with code: %u.%t", response.StatusCode, (response.StatusCode == 0 || response.StatusCode == 200) ? " Webhook url can be incorrect." : "" ); }
}

int EscapeMarkdown (char[] szStr, const int iSize)
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
	return EscapeRequest( szStr, iSize );
}

int EscapeRequest (char[] szStr, const int iSize)
{
	ReplaceString( szStr, iSize, "\"", "\\\"" );
	ReplaceString( szStr, iSize, "\\", "\\\\" );
	ReplaceString( szStr, iSize, "&", "%%26" );
	ReplaceString( szStr, iSize, "+", "%%2B" );

	int iLen = strlen( szStr );
	if ( iLen == iSize-1 ) {	/* Stripping backslashes which can escape quote sign in JSON. */
		while ( --iLen != -1 && szStr[ iLen ] == '\\' ) {}
		szStr[ iSize - 1 - ((iSize - 2 - iLen) % 2) ] = '\0'; }

	return strlen( szStr );
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

void Resolve (Handle[] hRedir, const int iType, const int it = 0)
{
	if ( it < Types ) {
		int i = view_as<int>( hRedir[ iType ] );
		if ( i > Type_Unknown + 1 && i < Types + 1 ) {
			Resolve( hRedir, --i, it + 1 );
			hRedir[ iType ] = view_as<int>( hRedir[i] ) > Types || view_as<int>( hRedir[i] ) < Type_Unknown + 1 ? CloneHandle( hRedir[ i ] ) : INVALID_HANDLE; } }
	else { hRedir[ iType ] = INVALID_HANDLE; }
}

SMCResult Settings_Parce_OnEnterSection (const SMCParser Parser, const char[] szSection, const bool opt_quotes)
{
	if ( !strcmp( szSection, "Webhooks" ) ) {
		Parser.OnKeyValue = Settings_Parse_Hooks; }
	else {
		g_iType = StringToType( szSection ); }
	return SMCParse_Continue;
}

SMCResult Settings_Parse_Settings (const SMCParser Parser, const char[] szKey, const char[] szValue, const bool key_quotes, const bool value_quotes)
{
	if ( szValue[0] ) {
		if (      !strcmp( szKey, "SourceBans++ URL" ) ) {
			g_dpSBPP_URL = new DataPack();
			g_dpSBPP_URL.WriteString( szValue ); }
		else if ( !strcmp( szKey, "Server icon URL" ) ) {
			g_dpServerIcon = new DataPack();
			g_dpServerIcon.WriteString( szValue ); }
		else if ( !strcmp( szKey, "Timezone shift" ) ) {
			g_iTimeshift = StringToInt( szValue ); }
		else if ( !strcmp( szKey, "Field with map" ) ) {
			g_bFieldMap = szValue[0] == 'y'; } }
	return SMCParse_Continue;
}

SMCResult Settings_Parse_Hooks (const SMCParser Parser, const char[] szKey, const char[] szValue, const bool key_quotes, const bool value_quotes)
{
	if ( szValue[0] && g_iType != Type_Unknown ) {
		if (      !strcmp( szKey, "Color" ) ) {
			g_iEmbedColors[ g_iType ] = StringToInt( szValue, 16 ); }
		else if ( !strcmp( szKey, "Icon" ) ) {
			int iRedir = StringToType( szValue );
			if ( iRedir == Type_Unknown ) {
				g_dpWebhookIcon[ g_iType ] = new DataPack();
				g_dpWebhookIcon[ g_iType ].WriteString( szValue ); }
			else {
				g_dpWebhookIcon[ g_iType ] = view_as<DataPack>( iRedir + 1 ); } }
		else if ( !strcmp( szKey, "Webhook" ) ) {
			int iRedir = StringToType( szValue );
			if ( iRedir == Type_Unknown ) {
				g_hWebhook[ g_iType ] = new System2HTTPRequest( SendEmbed_Callback, szValue ); }
			else {
				g_hWebhook[ g_iType ] = view_as<System2HTTPRequest>( iRedir + 1 ); } } }
	return SMCParse_Continue;
}

void hostname_OnChanged (const ConVar Cvar, const char[] szOld, const char[] szNew)
{
	Cvar.GetString( g_szHost, sizeof g_szHost );
	EscapeRequest( g_szHost, sizeof g_szHost );
}

public void OnIPGetted (const bool bSuccess, const char[] szError, const System2HTTPRequest request, const System2HTTPResponse response, const HTTPRequestMethod method)
{
	int i = 1;
	if ( bSuccess && response && response.StatusCode == 200 ) {
		response.GetContent( g_szIP[1], 39 + 1, 76, "<", false );
		i = strlen( g_szIP[1] ) + 1; }
	g_szIP[i] = ':';
	FindConVar( "hostport" ).GetString( g_szIP[++i], 5 + 1 );
	i += strlen( g_szIP[i] );
	g_szIP[i] = ')';
	g_szIP[++i] = '\0';
}