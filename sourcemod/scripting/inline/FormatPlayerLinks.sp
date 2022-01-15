			// #define iClient
			if ( g_dpSBPP_URL ) {
				int iLenOfURL, iLenOfID, iAccountID = GetSteamAccountID( iClient );
				copy( "*[bans](" );
				g_dpSBPP_URL.Reset();
				g_dpSBPP_URL.ReadString( szJson[ iLen ], 128 );
				iLen += (iLenOfURL = strlen( szJson[ iLen ] ));
				copy( "/index.php?p=banlist%%26searchText=" );
				iLen += (iLenOfID = FormatEx( szJson[ iLen ], sizeof szJson, "%u:%u", iAccountID & 1, iAccountID >> 1 ));
				copy( ")* | *[comms](" );
				iLen += strcopy( szJson[ iLen ], iLenOfURL + 1, szJson[ iLen - 14 - iLenOfID - 19 - 16 - iLenOfURL ] );
				copy( "/index.php?p=comms" );
				iLen += strcopy( szJson[ iLen ], iLenOfID + 19 + 1, szJson[ iLen - 18 - iLenOfURL - 14 - iLenOfID - 19 ] );
				copy( ")* | *[steam](https://steamcommunity.com/profiles/" ); }
			else { copy( "\\n*[steam](https://steamcommunity.com/profiles/" ); }
			GetClientAuthId( iClient, AuthId_SteamID64, szJson[ iLen ], 22 );
			iLen += strlen( szJson[ iLen ] );
			copy( ")* | *[rep](https://steamrep.com/profiles/" );
			GetClientAuthId( iClient, AuthId_SteamID64, szJson[ iLen ], 22 );
			iLen += strlen( szJson[ iLen ] );
			append( ')' );
			append( '*' );
			#undef iClient