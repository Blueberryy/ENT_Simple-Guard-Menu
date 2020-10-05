/*
 * SourceMod Entity Projects
 * by: Entity
 *
 * Copyright (C) 2020 Kőrösfalvi "Entity" Martin
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option) 
 * any later version.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 */
#include <sourcemod>
#include <cstrike>
#include <clientprefs>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>
#undef REQUIRE_PLUGIN
#include <sourcecomms>

#pragma semicolon 1
#pragma newdecls required

//Global
Handle RoundTimeTicker;
Handle TickerState = INVALID_HANDLE;
bool g_bEnabled = true;
bool g_bMutePrisoners = true;
bool g_bExtendTime = true;
bool g_bJetPack = true;
bool g_bTagging = true;
bool g_bFallDamage = true;

bool g_bTeamBlock = true;
bool g_bFriendlyFire = true;
bool g_bExtend = true;
bool g_bJP = true;
bool g_bTMute = true;
int g_RoundTime;
bool g_bIsClientCT[MAXPLAYERS + 1];
bool g_bLate;
bool g_bSourcomms;
char g_sColor[MAXPLAYERS+1][64];

bool g_bJetPackEnabled;

//Translations
char Prefix[128];
char t_Name[64];
char t_cmd_o[64];
char t_cmd_t[64];
char t_Team[64]; 

//ConVars
ConVar g_hEnabled;
ConVar g_hMutePrisoners;
ConVar g_hMutePrisonersDuration;
ConVar g_hExtendTime;
ConVar g_hJetpack;
ConVar g_hJetpackOneTime;
ConVar g_hFallDamage;
ConVar g_hTagging;
ConVar g_hDefaultBlock;
ConVar g_hDefaultFF;
ConVar g_hDefaultFD;
ConVar g_hDefaultJP;

ConVar g_hTeamBlock;
ConVar g_hFriendlyFire;
ConVar g_hTeammatesAreEnemies;
ConVar g_hRoundTime;
ConVar g_hFallDMG;
ConVar g_hJP;

public Plugin myinfo = 
{
	name = "[CSGO] JailBreak Guard Menu", 
	author = "Entity, Cruze", 
	description = "Simple Round Control menu for guards", 
	version = "1.4",
	url = "https://github.com/Sples1/Simple-Guard-Menu/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	MarkNativeAsOptional("SourceComms_SetClientMute");
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_hEnabled = CreateConVar("sm_gm_enabled", "1", "Enable the guardmenu system?", 0, true, 0.0, true, 1.0);
	g_hMutePrisoners = CreateConVar("sm_gm_mute", "1", "Enable prisoner mute part?", 0, true, 0.0, true, 1.0);
	g_hMutePrisonersDuration = CreateConVar("sm_gm_mute_duration", "1", "Duration to mute prisoners for? In minutes.");
	g_hExtendTime = CreateConVar("sm_gm_extend", "1", "Enable time extend part?", 0, true, 0.0, true, 1.0);
	g_hJetpack = CreateConVar("sm_gm_store_jetpack", "1", "Enable store jetpack part?", 0, true, 0.0, true, 1.0);
	g_hJetpackOneTime = CreateConVar("sm_gm_store_jetpack_onetime", "1", "Jetpack disable one time only?", 0, true, 0.0, true, 1.0);
	g_hFallDamage = CreateConVar("sm_gm_falldamage", "1", "Enable falldamage part?", 0, true, 0.0, true, 1.0);
	g_hTagging = CreateConVar("sm_gm_tagging", "1", "Enable player tagging part?", 0, true, 0.0, true, 1.0);
	g_hDefaultBlock = CreateConVar("sm_gm_defaultblock", "1", "The default state of TeamBlock", 0, true, 0.0, true, 1.0);
	g_hDefaultFF = CreateConVar("sm_gm_defaultff", "0", "The default state of FriendlyFire", 0, true, 0.0, true, 1.0);
	g_hDefaultFD = CreateConVar("sm_gm_defaultfd", "1", "The default state of FallDamage", 0, true, 0.0, true, 1.0);
	g_hDefaultJP = CreateConVar("sm_gm_defaultjp", "0.1", "The default state of Jetpack Fuel", 0, true, 0.0, true, 1.0);

	HookConVarChange(g_hEnabled, OnCvarChange_Enabled);
	HookConVarChange(g_hMutePrisoners, OnCvarChange_Mute);
	HookConVarChange(g_hExtendTime, OnCvarChange_Extend);
	HookConVarChange(g_hJetpack, OnCvarChange_Jetpack);
	HookConVarChange(g_hFallDamage, OnCvarChange_FallDamage);
	HookConVarChange(g_hTagging, OnCvarChange_Tagging);

	RegConsoleCmd("sm_guardmenu", Command_GuardMenu);
	RegConsoleCmd("sm_gm", Command_GuardMenu);

	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("round_start", OnRoundStart);
	HookEvent("round_end", OnRoundEnd);
	HookEvent("server_cvar", OnServerCvar, EventHookMode_Pre);

	g_hTeamBlock = FindConVar("mp_solid_teammates");
	g_hFriendlyFire = FindConVar("mp_friendlyfire");
	g_hTeammatesAreEnemies = FindConVar("mp_teammates_are_enemies");
	g_hRoundTime = FindConVar("mp_roundtime");
	g_hFallDMG = FindConVar("sv_falldamage_scale");
	g_hJP = FindConVar("sm_store_jetpack_minimum");

	AutoExecConfig(true, "guardmenu");
	LoadTranslations("guardmenu.phrases");

	if(g_bLate)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && IsPlayerAlive(i))
			{
				SDKHook(i, SDKHook_OnTakeDamage, BlockDamageForCT);
				if (GetClientTeam(i) == 3)
				{
					g_bIsClientCT[i] = true;
					CPrintToChat(i, "%s %t", Prefix, "StartMessage", t_Name, t_cmd_o, t_cmd_t);
				}
				else
				{
					g_bIsClientCT[i] = false;
				}
			}
		}
	}
	if(g_hJP == null)
	{
		g_bJetPackEnabled = false;
	}
	else
	{
		g_bJetPackEnabled = true;
	}
}

public void OnAllPluginsLoaded()
{
	g_bSourcomms = LibraryExists("sourcecomms");
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "sourcecomms"))
	{
		g_bSourcomms = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "sourcecomms"))
	{
		g_bSourcomms = false;
	}
}

public void OnMapStart()
{
	g_bEnabled = g_hEnabled.BoolValue;
	g_bMutePrisoners = g_hMutePrisoners.BoolValue;
	g_bExtendTime = g_hExtendTime.BoolValue;
	g_bJetPack = g_hJetpack.BoolValue;
	g_bTagging = g_hTagging.BoolValue;
	g_bFallDamage = g_hFallDamage.BoolValue;
	for(int i = 1; i <= MaxClients; i++)
	{
		g_sColor[i][0] = '\0';
	}
	
	Format(Prefix, sizeof(Prefix), "%t", "Prefix");
	Format(t_Name, sizeof(t_Name), "%t", "MenuName");
	Format(t_cmd_o, sizeof(t_cmd_o), "%t", "Command_Short");
	Format(t_cmd_t, sizeof(t_cmd_t), "%t", "Command_Long");
	Format(t_Team, sizeof(t_Team), "%t", "CT"); 
}

public void OnMapEnd()
{
	SetConVarInt(g_hFriendlyFire, 0, true, false);
	SetConVarInt(g_hTeammatesAreEnemies, 0, true, false);
}

public void OnCvarChange_Enabled(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if(StrEqual(newvalue, "1"))
	{
		g_bEnabled = true;
	}
	else if(StrEqual(newvalue, "0"))
	{
		g_bEnabled = false;
	}
}

public void OnCvarChange_Mute(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if(StrEqual(newvalue, "1"))
	{
		g_bMutePrisoners = true;
		g_bTMute = true;
	}
	else if(StrEqual(newvalue, "0"))
	{
		g_bMutePrisoners = false;
		g_bTMute = false;
	}
}

public void OnCvarChange_Extend(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if(StrEqual(newvalue, "1"))
	{
		g_bExtendTime = true;
		g_bExtend = true;
	}
	else if(StrEqual(newvalue, "0"))
	{
		g_bExtendTime = false;
		g_bExtend = false;
	}
}

public void OnCvarChange_Jetpack(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if(StrEqual(newvalue, "1"))
	{
		g_bJP = true;
		g_bJetPack = true;
	}
	else if(StrEqual(newvalue, "0"))
	{
		g_bJP = true;
		g_bJetPack = false;
	}
}

public void OnCvarChange_Tagging(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if(StrEqual(newvalue, "1"))
	{
		g_bTagging = true;
	}
	else if(StrEqual(newvalue, "0"))
	{
		g_bTagging = false;
	}
}

public void OnCvarChange_FallDamage(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if(StrEqual(newvalue, "1"))
	{
		g_bFallDamage = true;
	}
	else if(StrEqual(newvalue, "0"))
	{
		g_bFallDamage = false;
	}
}

public Action Timer_RoundTimeLeft(Handle timer, int RoundTime)
{
	if(g_RoundTime == 5)
	{
		return Plugin_Stop;
	}
	else
	{
		if(g_RoundTime != 0)
		{
			g_RoundTime = g_RoundTime - 1;
		}
	}
	return Plugin_Continue;
}

public Action OnServerCvar(Handle event, const char[] name, bool dontBroadcast)
{
	char sConVarName[64];
	sConVarName[0] = '\0';
	GetEventString(event, "cvarname", sConVarName, sizeof(sConVarName));
	if (StrContains(sConVarName, "mp_friendlyfire", false) >= 0 || StrContains(sConVarName, "mp_solid_teammates", false) >= 0 || StrContains(sConVarName, "sv_alltalk", false) >= 0 || StrContains(sConVarName, "sv_full_alltalk", false) >= 0 || StrContains(sConVarName, "sv_deadtalk", false) >= 0 || StrContains(sConVarName, "mp_teammates_are_enemies", false) >= 0)
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}  

public Action Command_GuardMenu(int client, int args)
{
	if (!g_bEnabled)
	{
		CPrintToChat(client, "%s %t", Prefix, "TurnedOff", t_Name);
		return Plugin_Handled;
	}

	if(client)
	{
		if(g_bIsClientCT[client])
		{
		
			if(IsPlayerAlive(client))
			{
				ShowGuardMenu(client);
			}
			else
			{
				CPrintToChat(client, "%s %t", Prefix, "TurnedOff");
			}
		}
		else
		{
			CPrintToChat(client, "%s %t", Prefix, "OnlyGuards", t_Name, t_Team);
		}
	}
	else
	{
		CPrintToChat(client, "%s %t", Prefix, "MustBeInGame");
	}
	return Plugin_Handled;
}

stock void ShowGuardMenu(int client, int index = 0)
{
	char sTB[64], t_Extend[64], t_MuteT[64], t_TagP[64], t_TagRP[64], t_UnTagP[64], t_UnTagAll[64], sFF[64], sFD[64], sJP[64];
	Format(t_Extend, sizeof(t_Extend), "%t", "RoundExtend");
	Format(t_MuteT, sizeof(t_MuteT), "%t", "MutePrisoners");
	Format(t_TagRP, sizeof(t_TagRP), "%t", "TagRandomPlayer");
	Format(t_TagP, sizeof(t_TagP), "%t", "TagPlayer");
	Format(t_UnTagP, sizeof(t_UnTagP), "%t", "UnTagPlayer");
	Format(t_UnTagAll, sizeof(t_UnTagAll), "%t", "UnTagAll");

	Menu menu = new Menu(GuardMenuChoice);
	menu.SetTitle("GuardMenu - By Entity");

	if(GetConVarInt(g_hTeamBlock) == 1)
	{
		Format(sTB, sizeof(sTB), "%t", "TeamBlockOff");
		menu.AddItem("teamblock", sTB, g_bTeamBlock ? 0 : 1);
	}
	else
	{
		Format(sTB, sizeof(sTB), "%t", "TeamBlockOn");
		menu.AddItem("teamblock", sTB, g_bTeamBlock ? 0 : 1);
	}
	if(GetConVarInt(g_hFriendlyFire) == 0)
	{
		Format(sFF, sizeof(sFF), "%t", "FriendlyFireOn");
		menu.AddItem("friendlyfire", sFF, g_bFriendlyFire ? 0 : 1);
	}
	else
	{
		Format(sFF, sizeof(sFF), "%t", "FriendlyFireOff");
		menu.AddItem("friendlyfire", sFF, g_bFriendlyFire ? 0 : 1);
	}
	if(g_bJetPackEnabled)
	{
		if(GetConVarFloat(g_hJP) == 0.5)
		{
			Format(sJP, sizeof(sJP), "%t", "JetPackOn");
			menu.AddItem("jetpack", sJP, g_bJetPack&&g_bJP ? 0 : 1);
		}
		else
		{
			Format(sJP, sizeof(sJP), "%t", "JetPackOff");
			menu.AddItem("jetpack", sJP, g_bJetPack&&g_bJP ? 0 : 1);
		}
	}
	if(GetConVarInt(g_hFallDMG) == 0)
	{
		Format(sFD, sizeof(sFD), "%t", "FallDamageOn");
		menu.AddItem("falldamage", sFD, g_bFallDamage ? 0 : 1);
	}
	else
	{
		Format(sFD, sizeof(sFD), "%t", "FallDamageOff");
		menu.AddItem("falldamage", sFD, g_bFallDamage ? 0 : 1);
	}
	menu.AddItem("extend", t_Extend, g_bExtendTime&&g_bExtend ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("mutet", t_MuteT, g_bMutePrisoners&&g_bTMute ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("tagrp", t_TagRP, g_bTagging ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("tagfd", t_TagP, g_bTagging ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("untagfd", t_UnTagP, g_bTagging ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("untagall", t_UnTagAll, g_bTagging ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.DisplayAt(client, index, MENU_TIME_FOREVER);
}

public int GuardMenuChoice(Menu menu, MenuAction action, int client, int itemNum)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	if(action == MenuAction_Select)
	{
		if (!g_bEnabled)
		{
			CPrintToChat(client, "%s %t", Prefix, "TurnedOff", t_Name);
			return;
		}
		
		char info[64];
		GetMenuItem(menu, itemNum, info, sizeof(info));
		if(StrEqual(info, "teamblock"))
		{
			if (GetConVarInt(g_hTeamBlock) == 1)
			{
				SetConVarInt(g_hTeamBlock, 0, true, false);
				CPrintToChatAll("%s %t", Prefix, "TeamBlockTurnedOff", client);
			}
			else
			{
				SetConVarInt(g_hTeamBlock, 1, true, false);
				CPrintToChatAll("%s %t", Prefix, "TeamBlockTurnedOn", client);
			}
			ShowGuardMenu(client, GetMenuSelectionPosition());
		}
		if(StrEqual(info, "friendlyfire"))
		{
			if (GetConVarInt(g_hFriendlyFire) == 1)
			{
				SetConVarInt(g_hFriendlyFire, 0, true, false);
				SetConVarInt(g_hTeammatesAreEnemies, 0, true, false);
				CPrintToChatAll("%s %t", Prefix, "FriendlyFireTurnedOff", client);
			}
			else
			{
				SetConVarInt(g_hFriendlyFire, 1, true, false);
				SetConVarInt(g_hTeammatesAreEnemies, 1, true, false);
				CPrintToChatAll("%s %t", Prefix, "FriendlyFireTurnedOn", client);
			}
			ShowGuardMenu(client, GetMenuSelectionPosition());
		}
		if(StrEqual(info, "jetpack"))
		{
			if(GetConVarFloat(g_hJP) == 0.5)
			{
				SetConVarFloat(g_hJP, 0.1, true, false);
				CPrintToChatAll("%s %t", Prefix, "JetPackTurnedOn", client);
			}
			else
			{
				SetConVarFloat(g_hJP, 0.5, true, false);
				CPrintToChatAll("%s %t", Prefix, "JetPackTurnedOff", client);
			}
			if(g_hJetpackOneTime.BoolValue && GetConVarFloat(g_hJP) == GetConVarFloat(g_hDefaultJP))
			{
				g_bJP = false;
			}
			ShowGuardMenu(client, GetMenuSelectionPosition());
		}
		if(StrEqual(info, "falldamage"))
		{
			if(GetConVarInt(g_hFallDMG) == 1)
			{
				SetConVarInt(g_hFallDMG, 0, true, false);
				CPrintToChatAll("%s %t", Prefix, "FallDamageTurnedOff", client);
			}
			else
			{
				SetConVarInt(g_hFallDMG, 1, true, false);
				CPrintToChatAll("%s %t", Prefix, "FallDamageTurnedOn", client);
			}
			ShowGuardMenu(client, GetMenuSelectionPosition());
		}
		if(StrEqual(info, "extend"))
		{
			if (g_RoundTime > 5)
			{
				g_bExtend = false;				
				GameRules_SetProp("m_iRoundTime", GameRules_GetProp("m_iRoundTime", 4, 0)+300, 4, 0, true);
				g_RoundTime = g_RoundTime + 300;
				CPrintToChatAll("%s %t", Prefix, "RoundExtended", client);
			}
			else
			{
				CPrintToChat(client, "%s %t", Prefix, "ExtendDenied");
			}
			ShowGuardMenu(client, GetMenuSelectionPosition());
		}
		if(StrEqual(info, "mutet"))
		{
			if (g_RoundTime > 60)
			{
				g_bTMute = false;
				for(int i = 1; i <= MaxClients; i++)
				{
					if(IsClientInGame(i))
					{
						if(GetClientTeam(i) == CS_TEAM_T)
						{
							if(g_bSourcomms)
							{
								SourceComms_SetClientMute(i, true, g_hMutePrisonersDuration.IntValue, true, "GuardMenu");
							}
							else
							{
								SetClientListeningFlags(i, VOICE_MUTED);
								CreateTimer(g_hMutePrisonersDuration.FloatValue*60, Timer_UnMute, _, TIMER_FLAG_NO_MAPCHANGE);
							}
						}
					}
				}
				CPrintToChatAll("%s %t", Prefix, "PrisonersMuted", client);
			}
			else
			{
				CPrintToChat(client, "%s %t", Prefix, "MuteDeined");
			}
			ShowGuardMenu(client, GetMenuSelectionPosition());
		}
		if(StrEqual(info, "tagrp"))
		{
			if(GetAliveCount() % 2 == 1)
			{
				CPrintToChat(client, "%s %t", Prefix, "OddNumberT");
				ShowGuardMenu(client, GetMenuSelectionPosition());
				return;
			}
			else if(GetAliveCount() == 0)
			{
				CPrintToChat(client, "%s %t", Prefix, "NoAliveT");
				ShowGuardMenu(client, GetMenuSelectionPosition());
				return;
			}
			ShowTeamColorMenu(client);
		}
		if(StrEqual(info, "tagfd"))
		{
			ShowColorMenu(client);
			CPrintToChat(client, "%s %t", Prefix, "SelectColor");
		}
		if(StrEqual(info, "untagfd"))
		{
			int TargetID = GetClientAimTarget(client, true);
			if(TargetID == -1)
			{
				CPrintToChat(client, "%s %t", Prefix, "TargetNotFound");
				ShowGuardMenu(client, GetMenuSelectionPosition());
				return;
			}
			Command_UnTagPlayer(client, TargetID);
			CPrintToChatAll("%s %t", Prefix, "UnTagged", client, TargetID);
			ShowGuardMenu(client, GetMenuSelectionPosition());
		}
		if(StrEqual(info, "untagall"))
		{
			for(int i = 1; i <= MaxClients; i++)
			{
				Command_UnTagPlayer(client, i);
			}
			CPrintToChatAll("%s %t", Prefix, "UnTaggedAll", client);
			ShowGuardMenu(client, GetMenuSelectionPosition());
		}
	}
}

public Action Timer_UnMute(Handle timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			if(GetClientTeam(i) == CS_TEAM_T && GetClientListeningFlags(i) == VOICE_MUTED)
			{
				SetClientListeningFlags(i, VOICE_NORMAL);
			}
		}
	}
}

stock void ShowTeamColorMenu(int client)
{
	Menu menu = new Menu(Menu_Handler2);
	menu.SetTitle("Team 1 color?");
	menu.AddItem("green", "Green");
	menu.AddItem("blue", "Blue");
	menu.AddItem("pink", "Pink");
	menu.AddItem("yellow", "Yellow");
	menu.AddItem("cyan", "Cyan");
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, 30);
}

stock void ShowColorTeamMenu2(int client)
{
	Menu menu = new Menu(Menu_Handler3);
	menu.SetTitle("Team 2 color?");
	menu.AddItem("green", "Green");
	menu.AddItem("blue", "Blue");
	menu.AddItem("pink", "Pink");
	menu.AddItem("yellow", "Yellow");
	menu.AddItem("cyan", "Cyan");
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, 30);
}

public int Menu_Handler2(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		if (!g_bEnabled)
		{
			CPrintToChat(client, "%s %t", Prefix, "TurnedOff", t_Name);
			return;
		}
		char info[64];
		GetMenuItem(menu, item, info, sizeof(info));
		if (StrEqual(info, "green"))
		{
			ColorRandomAlivePlayer(0, 255, 0, "Green", true);
		}
		if (StrEqual(info, "blue"))
		{
			ColorRandomAlivePlayer(0, 0, 255, "Blue", true);
		}
		if (StrEqual(info, "pink"))
		{
			ColorRandomAlivePlayer(255, 0, 128, "Pink", true);
		}
		if (StrEqual(info, "yellow"))
		{
			ColorRandomAlivePlayer(255, 255, 0, "Yellow", true);
		}
		if (StrEqual(info, "cyan"))
		{
			ColorRandomAlivePlayer(0, 255, 255, "Cyan", true);
		}
		ShowColorTeamMenu2(client);
	}
	if (action == MenuAction_Cancel)
	{
		if(item == MenuCancel_ExitBack)
		{
			ShowGuardMenu(client);
		}
	}
	if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int Menu_Handler3(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		if (!g_bEnabled)
		{
			CPrintToChat(client, "%s %t", Prefix, "TurnedOff", t_Name);
			return;
		}
		char info[64];
		GetMenuItem(menu, item, info, sizeof(info));
		if (StrEqual(info, "green"))
		{
			ColorRandomAlivePlayer(0, 255, 0, "Green", false);
		}
		if (StrEqual(info, "blue"))
		{
			ColorRandomAlivePlayer(0, 0, 255, "Blue", false);
		}
		if (StrEqual(info, "pink"))
		{
			ColorRandomAlivePlayer(255, 0, 128, "Pink", false);
		}
		if (StrEqual(info, "yellow"))
		{
			ColorRandomAlivePlayer(255, 255, 0, "Yellow", false);
		}
		if (StrEqual(info, "cyan"))
		{
			ColorRandomAlivePlayer(0, 255, 255, "Cyan", false);
		}
		ShowGuardMenu(client);
	}
	if (action == MenuAction_Cancel)
	{
		if(item == MenuCancel_ExitBack)
		{
			ShowGuardMenu(client);
		}
	}
	if (action == MenuAction_End)
	{
		delete menu;
	}
}

stock void ShowColorMenu(int client)
{
	Menu menu = new Menu(Menu_Handler);
	menu.SetTitle("Tag color");
	menu.AddItem("green", "Green");
	menu.AddItem("blue", "Blue");
	menu.AddItem("pink", "Pink");
	menu.AddItem("yellow", "Yellow");
	menu.AddItem("cyan", "Cyan");
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, 30);
}

public int Menu_Handler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		if (!g_bEnabled)
		{
			CPrintToChat(client, "%s %t", Prefix, "TurnedOff", t_Name);
			return;
		}
		char info[64];
		GetMenuItem(menu, item, info, sizeof(info));
		int TargetID = GetClientAimTarget(client, true);
		if(TargetID == -1)
		{
			CPrintToChat(client, "%s %t", Prefix, "TargetNotFound");
			ShowColorMenu(client);
			return;
		}
		if (StrEqual(info, "green"))
		{
			Command_TagPlayer(client, TargetID, 0, 255, 0, "Green");
		}
		if (StrEqual(info, "blue"))
		{
			Command_TagPlayer(client, TargetID, 0, 0, 255, "Blue");
		}
		if (StrEqual(info, "pink"))
		{
			Command_TagPlayer(client, TargetID, 255, 0, 128, "Pink");
		}
		if (StrEqual(info, "yellow"))
		{
			Command_TagPlayer(client, TargetID, 255, 255, 0, "Yellow");
		}
		if (StrEqual(info, "cyan"))
		{
			Command_TagPlayer(client, TargetID, 0, 255, 255, "Cyan");
		}
		ShowGuardMenu(client);
	}
	if (action == MenuAction_Cancel)
	{
		if(item == MenuCancel_ExitBack)
		{
			ShowGuardMenu(client);
		}
	}
	if (action == MenuAction_End)
	{
		delete menu;
	}
}

stock void Command_TagPlayer(int client, int target, int r, int g, int b, char[] color)
{
	if (target != -1 && IsClientInGame(target) && IsPlayerAlive(target))
	{
		strcopy(g_sColor[target], sizeof(g_sColor), color);
		SetEntityRenderColor(target, r, g, b, 255);
		CPrintToChatAll("%s %t", Prefix, "Tagged", client, target, color);
	}
}

stock void Command_UnTagPlayer(int client, int target)
{
	if(target != -1 && IsClientInGame(target) && IsPlayerAlive(target))
	{
		g_sColor[target][0] = '\0';
		SetEntityRenderColor(target, 255, 255, 255, 255);
	}
}

public Action OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int IsClientCT = GetClientTeam(client);
	if (IsClientCT == 3)
	{
		g_bIsClientCT[client] = true;
		CPrintToChat(client, "%s %t", Prefix, "StartMessage", t_Name, t_cmd_o, t_cmd_t);
	}
	else
	{
		g_bIsClientCT[client] = false;
	}
	SDKHook(client, SDKHook_OnTakeDamage, BlockDamageForCT);
}


public Action BlockDamageForCT(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if(victim < 1 || victim > MaxClients || attacker < 1 || attacker > MaxClients)
	{
		return Plugin_Continue;
	}
	int VictimTeam = GetClientTeam(victim);
	int AttackerTeam = GetClientTeam(attacker);
	if(GetConVarInt(g_hFriendlyFire) == 1 && VictimTeam == 3 && AttackerTeam == 3)
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action OnRoundStart(Event event, char[] name, bool dontBroadcast)
{
	if(!g_bMutePrisoners)
	{
		g_bTMute = false;
	}
	if(!g_bExtendTime)
	{
		g_bExtend = false;
	}
	if(!g_bJetPack)
	{
		g_bJP = false;
	}
	g_RoundTime = GetConVarInt(g_hRoundTime) * 60;
	if(TickerState == INVALID_HANDLE)
	{
		RoundTimeTicker = CreateTimer(1.0, Timer_RoundTimeLeft, g_RoundTime, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		KillTimer(RoundTimeTicker);
		RoundTimeTicker = CreateTimer(1.0, Timer_RoundTimeLeft, g_RoundTime, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action OnRoundEnd(Event event, char[] name, bool dontBroadcast)
{
	if(TickerState != INVALID_HANDLE)
	{
		KillTimer(RoundTimeTicker);
	}

	if(g_bMutePrisoners)
	{
		g_bTMute = true;
	}

	if(g_bExtendTime)
	{
		g_bExtend = true;
	}
	
	if(g_bJetPack)
	{
		g_bJP = true;
	}

	if(GetConVarInt(g_hDefaultBlock) == 1)
	{
		SetConVarInt(g_hTeamBlock, 1, true, false);
	}
	else
	{
		SetConVarInt(g_hTeamBlock, 0, true, false);
	}
	
	if(GetConVarInt(g_hDefaultFF) == 1)
	{
		SetConVarInt(g_hFriendlyFire, 1, true, false);
		SetConVarInt(g_hTeammatesAreEnemies, 1, true, false);
	}
	else
	{
		SetConVarInt(g_hFriendlyFire, 0, true, false);
		SetConVarInt(g_hTeammatesAreEnemies, 0, true, false);
	}
	
	if(GetConVarInt(g_hDefaultFD) == 1)
	{
		SetConVarInt(g_hFallDMG, 1, true, false);
	}
	else
	{
		SetConVarInt(g_hFallDMG, 0, true, false);
	}
	
	if(g_bJetPackEnabled)
	{
		if(GetConVarFloat(g_hDefaultJP) == 0.1)
		{
			SetConVarFloat(g_hJP, 0.1, true, false);
		}
		else
		{
			SetConVarFloat(g_hJP, 0.5, true, false);
		}
	}
	
	if(g_bTagging)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && IsPlayerAlive(i))
			{
				SetEntityRenderColor(i, 255, 255, 255, 255);
			}
			g_sColor[i][0] = '\0';
		}
	}
}

public void OnClientPutInServer(int client)
{
	g_sColor[client][0] = '\0';
}

public void OnClientDisconnect(int client)
{
	if(g_sColor[client][0] == '\0')
	{
		return;
	}
	CPrintToChatAll("%s %t", Prefix, "TaggedPlayerLeft", client, g_sColor[client]);
	g_sColor[client][0] = '\0';
}

stock void ColorRandomAlivePlayer(int r, int g, int b, char[] color, bool checkalive)
{
	int iAlive;
	if(checkalive)
	{
		iAlive = GetAliveCount()/2;
		for(int i = 1; i <= MaxClients; i++)
		{
			if(iAlive && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T && g_sColor[i][0] == '\0')
			{
				CPrintToChatAll("%s %t", Prefix, "TaggedTeam", checkalive ? 1:2, i);
				SetEntityRenderColor(i, r, g, b, 255);
				strcopy(g_sColor[i], sizeof(g_sColor), color);
				iAlive--;
			}
		}
	}
	else
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T && g_sColor[i][0] == '\0')
			{
				CPrintToChatAll("%s %t", Prefix, "TaggedTeam", checkalive ? 1:2, i);
				SetEntityRenderColor(i, r, g, b, 255);
				strcopy(g_sColor[i], sizeof(g_sColor), color);
			}
		}
	}
}

int GetAliveCount()
{
	int iAlive=0;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T && !IsClientSourceTV(i) && g_sColor[i][0] == '\0')
		{
			iAlive++;
		}
	}
	return iAlive;
}