/*
    This script is based on a version originally created by sandro-h and totally recoded by B3akers.
    This script tracks Hitman 3 ingame time in LiveSplit.
    * It does auto-split
    * It tracks time across levels and level restarts
    * It pauses in menus, including inventory
*/

/* 
    LICENSE (Zlib)
    Copyright (c) 2022 sandro-h
    This software is provided 'as-is', without any express or implied
    warranty. In no event will the authors be held liable for any damages
    arising from the use of this software.
    Permission is granted to anyone to use this software for any purpose,
    including commercial applications, and to alter it and redistribute it
    freely, subject to the following restrictions:
    1. The origin of this software must not be misrepresented; you must not
    claim that you wrote the original software. If you use this software
    in a product, an acknowledgment in the product documentation would be
    appreciated but is not required.
    2. Altered source versions must be plainly marked as such, and must not be
    misrepresented as being the original software.
    3. This notice may not be removed or altered from any source distribution.
*/


/*
ContractsManager = 48 8D 0D ? ? ? ? E8 ? ? ? ? 48 8D 4D E7 E8 ? ? ? ? F7 45 ? ? ? ? ?
	gateExited = C6 85 ? ? ? ? ? 48 8B 85 ? ? ? ? 48 85 C0
	Metadata.Location = 48 89 9E ? ? ? ? 49 8B CD
GameTimeManager = 48 89 05 ? ? ? ? 48 8B 05 ? ? ? ? 0F 57 C9
	GameTime = 4C 89 0D ? ? ? ? EB 5C (GameTime - GameTimeManager = 0x18)
		offset is 0x18, game uses direct one because object is allocated in .data
HudMissionTimerController = 48 8B 1D ? ? ? ? 48 85 DB 0F 84 ? ? ? ? 48 8B 43 28
	MissionStartTime = 0x40
*/

state("HITMAN3")
{

}

init
{
    var mainModule = modules.First();
    var baseAddress = mainModule.BaseAddress;

    var signaturesList = new List<Tuple<string, string, string, int>>()
    {
        new Tuple<string, string, string, int>("gateExited", "offset", "C6 85 ?? ?? ?? ?? ?? 48 8B 85 ?? ?? ?? ?? 48 85 C0", 0x2),
        new Tuple<string, string, string, int>("metadataLocation", "offset", "48 89 9E ?? ?? ?? ?? 49 8B CD", 0x3),
        new Tuple<string, string, string, int>("hudMissionTimeController", "pointer", "48 8B 1D ?? ?? ?? ?? 48 85 DB 0F 84 ?? ?? ?? ?? 48 8B 43 28", 0x3),
        new Tuple<string, string, string, int>("contractsManager", "pointer", "48 8D 0D ?? ?? ?? ?? E8 ?? ?? ?? ?? 48 8D 4D E7 E8 ?? ?? ?? ?? F7 45", 0x3),
        new Tuple<string, string, string, int>("gameTime", "pointer", "48 03 15 ?? ?? ?? ?? F3 48 0F 2A C2", 0x3),
        new Tuple<string, string, string, int>("onSaStatusUpdate", "function", "40 53 48 83 EC 20 48 8B D9 E8 ?? ?? ?? ?? 84 C0 74 11 48 8B CB", 0x0),
        new Tuple<string, string, string, int>("onKillEventObjectList", "pointer", "48 8D 0D ?? ?? ?? ?? 0F 11 4D E0 E8 ?? ?? ?? ?? 89 7D E8 48 8D 05 ?? ?? ?? ?? 48 89 45 E0 48 8D 55 E0", 0x3),
        new Tuple<string, string, string, int>("contractsEventEntityList", "pointer", "48 8D 0D ?? ?? ?? ?? 48 8B F8 E8 ?? ?? ?? ?? 84 C0 75 0F", 0x3)
    };

    //Version check if needed in future to change signatures
    //

    /*	
	var versionInfo = FileVersionInfo.GetVersionInfo(mainModule.FileName);
	if(versionInfo.FileVersion == "3.110.1.0")
	{
	
	
	}
	*/

    var e_lfanew = memory.ReadValue<int>(baseAddress + 0x3C);
    var SizeOfOptionalHeader = memory.ReadValue<short>(baseAddress + e_lfanew + 0x4 + 0x10);
    var textSectionBase = baseAddress + e_lfanew + 0x18 + SizeOfOptionalHeader;

    var textVirtualSize = memory.ReadValue<int>(textSectionBase + 0x08);
    var textVirtualAddress = memory.ReadValue<int>(textSectionBase + 0x0C);

    var gameAddresses = new Dictionary<string, int>();

    var scanner = new SignatureScanner(game, IntPtr.Add(baseAddress, textVirtualAddress), textVirtualSize);
    var sigScanTarget = new SigScanTarget();

    foreach (var signature in signaturesList)
    {
        sigScanTarget.AddSignature(signature.Item3);
    }

    var resultList = scanner.ScanAll(sigScanTarget).ToList();

    for (var i = 0; i < resultList.Count; i++)
    {
        var signature = signaturesList[i];
        var scanResult = resultList[i];
        if (signature.Item2 == "offset")
        {
            gameAddresses[signature.Item1] = memory.ReadValue<int>(scanResult + signature.Item4);
        }
        else if (signature.Item2 == "pointer")
        {
            gameAddresses[signature.Item1] = memory.ReadValue<int>(scanResult + signature.Item4) + (int)((ulong)scanResult - (ulong)baseAddress) + 0x7;
        }
        else if (signature.Item2 == "function")
        {
            gameAddresses[signature.Item1] = (int)((ulong)scanResult - (ulong)baseAddress);
        }
    }

    //Time in game is stored as binary microseconds in ulong
    //
    vars.time = new MemoryWatcher<ulong>(new DeepPointer(gameAddresses["gameTime"]));
    vars.hudMissionTimeController = new MemoryWatcher<ulong>(new DeepPointer(gameAddresses["hudMissionTimeController"]));
    vars.missionTime = new MemoryWatcher<ulong>(new DeepPointer(gameAddresses["hudMissionTimeController"], 0x40));
    vars.gateExited = new MemoryWatcher<bool>(new DeepPointer(gameAddresses["contractsManager"] + gameAddresses["gateExited"]));
    vars.metadataLocation = new StringWatcher(new DeepPointer(gameAddresses["contractsManager"] + gameAddresses["metadataLocation"], 0x00), 255);

    vars.onSaStatusUpdateOff = gameAddresses["onSaStatusUpdate"];
    vars.onKillEventObjectListOff = gameAddresses["onKillEventObjectList"];
    vars.contractsEventEntityList = gameAddresses["contractsEventEntityList"];
    vars.onExitGateEventPointer = (ulong)0;

    vars.silentAssassinStatus = false;
}

update
{
    //There is no static pointer to HudSilentAssassinOptionController but we can use static list for on kill event which contains HudSilentAssassinOptionController
    //
    // That list is a simple std::vector with some struct, size of that struct is 0x20
    //	off 0x00 - event function handler
    //  off 0x18 - pointer to class
    //

    vars.silentAssassinStatus = false;

    var baseAddress = modules.First().BaseAddress;
    var addressFinal = IntPtr.Add(baseAddress, (int)vars.onKillEventObjectListOff);
    var listHeaderData = game.ReadBytes(addressFinal, 0x10);
    var listStart = BitConverter.ToUInt64(listHeaderData, 0x0);
    var listEnd = BitConverter.ToUInt64(listHeaderData, 0x8);
    var itemsCount = (int)(listEnd - listStart) / 0x20;
    var listData = game.ReadBytes((IntPtr)listStart, (int)(listEnd - listStart));

    for (var i = 0; i < itemsCount; i++)
    {
        var callbackFunction = BitConverter.ToUInt64(listData, (i * 0x20) + 0x00);
        if (callbackFunction != (ulong)IntPtr.Add(baseAddress, (int)vars.onSaStatusUpdateOff))
            continue;

        var hudSilentAssassinOptionController = BitConverter.ToUInt64(listData, (i * 0x20) + 0x18);
        if (hudSilentAssassinOptionController == 0)
            continue;

        //0x40 - spotted by camera should be false
        //0x41 - unnoticed spotted be true
        //0x42 - killed non target should be false
        //0x43 - body not found should be true (it's my guess so could be wrong)

        var assassinStatus = game.ReadBytes((IntPtr)(hudSilentAssassinOptionController + 0x40), 0x4);

        vars.silentAssassinStatus = assassinStatus[0] == 0x00
                                    && assassinStatus[1] == 0x01
                                    && assassinStatus[2] == 0x00
                                    && assassinStatus[3] == 0x01;

        break;
    }

    vars.canDoSplit = false;
    vars.time.Update(game);
    vars.hudMissionTimeController.Update(game);
    vars.missionTime.Update(game);
    vars.gateExited.Update(game);
    vars.metadataLocation.Update(game);

    //Find new exitgate event class when mission start
    //
    if (vars.missionTime.Old != vars.missionTime.Current && vars.missionTime.Current > 0)
    {
        var eventListPointer = IntPtr.Add(baseAddress, (int)vars.contractsEventEntityList);
        var eventListHeaderData = game.ReadBytes(eventListPointer, 0x10);

        var eventListStart = BitConverter.ToUInt64(eventListHeaderData, 0x0);
        var eventListEnd = BitConverter.ToUInt64(eventListHeaderData, 0x8);

        var eventListData = game.ReadBytes((IntPtr)eventListStart, (int)(eventListEnd - eventListStart));

        for (var i = 0; i < eventListData.Length; i += 0x8)
        {
            var currentEventPointer = BitConverter.ToUInt64(eventListData, i);
            if (currentEventPointer == 0)
                continue;

            var eventTriggerNamePointer = game.ReadValue<ulong>(IntPtr.Add((IntPtr)currentEventPointer, 0x40));
            if (eventTriggerNamePointer == 0)
                continue;

            var sb = new StringBuilder(64);

            if (game.ReadString((IntPtr)eventTriggerNamePointer, ReadStringType.AutoDetect, sb))
            {
                if (sb.ToString() == "exit_gate")
                {
                    vars.onExitGateEventPointer = currentEventPointer;
                    break;
                }
            }
        }
    }

    if (vars.onExitGateEventPointer > 0)
    {
        vars.currentExitTime = game.ReadValue<ulong>(IntPtr.Add((IntPtr)vars.onExitGateEventPointer, 0x50));
        if (vars.currentExitTime > 0)
        {
            vars.onExitGateEventPointer = 0;
        }
    }

    if (settings["unsplitrestart"] && vars.hudMissionTimeController.Current > 0 && vars.missionTime.Current == 0 && vars.lastSplitLocation == vars.metadataLocation.Current)
    {
        vars.timerModel.UndoSplit();
        vars.lastSplitLocation = "";
    }
}

startup
{
    vars.totalIGT = (ulong)0;
    vars.currentMissionTime = (ulong)0;
    vars.currentExitTime = (ulong)0;
    vars.disableReset = true;
    vars.timerModel = new TimerModel { CurrentState = timer }; // to use the undo split function
    vars.lastSplitLocation = "";
    refreshRate = 20;

    settings.Add("splitassassin", true, "Split mission only when SilentAssassin");
    settings.Add("useseconds", true, "Fix timer to seconds, after exit/restart mission");
    settings.Add("unsplitrestart", false, "UndoSplit when starting the same mission");

    settings.Add("autorestart", true, "Start/Restart timer on mission");
    {
        settings.Add("level1", true, "Paris", "autorestart");
        settings.Add("level2", false, "Sapienza", "autorestart");
        settings.Add("level3", false, "Marrakesh", "autorestart");
        settings.Add("level4", false, "Bangkok", "autorestart");
        settings.Add("level5", false, "Colorado", "autorestart");
        settings.Add("level6", false, "Hokkaido", "autorestart");

        settings.Add("level7", false, "New Zealand", "autorestart");
        settings.Add("level8", false, "Miami", "autorestart");
        settings.Add("level9", false, "Santa Fortuna", "autorestart");
        settings.Add("level10", false, "Mumbai", "autorestart");
        settings.Add("level11", false, "Whittleton Creek", "autorestart");
        settings.Add("level12", false, "Isle of Sgail", "autorestart");
        settings.Add("level13", false, "New York", "autorestart");
        settings.Add("level14", false, "Haven Island", "autorestart");
        settings.Add("level15", false, "Dubai", "autorestart");
        settings.Add("level16", false, "Dartmoor", "autorestart");
        settings.Add("level17", false, "Berlin", "autorestart");
        settings.Add("level18", false, "Chongqing", "autorestart");
        settings.Add("level19", false, "Mendoza", "autorestart");
        settings.Add("level20", false, "Carpathian Mountains", "autorestart");
    }

    vars.locationDescriptor = new Dictionary<string, string>()
    {
        {"LOCATION_PARIS", "level1"},
        {"LOCATION_COASTALTOWN_EBOLA", "level2"},
        {"LOCATION_COASTALTOWN", "level2"},
        {"LOCATION_COASTALTOWN_MOVIESET", "level2"},
        {"LOCATION_COASTALTOWN_NIGHT", "level2"},
        {"LOCATION_MARRAKECH_NIGHT", "level3"},
        {"LOCATION_MARRAKECH", "level3"},
        {"LOCATION_BANGKOK_ZIKA", "level4"},
        {"LOCATION_BANGKOK", "level4"},
        {"LOCATION_COLORADO_RABIES", "level5"},
        {"LOCATION_COLORADO", "level5"},
        {"LOCATION_HOKKAIDO_FLU", "level6"},
        {"LOCATION_HOKKAIDO", "level6"},
        {"LOCATION_NEWZEALAND", "level7"},
        {"LOCATION_MIAMI", "level8"},
        {"LOCATION_MIAMI_COTTONMOUTH", "level8"},
        {"LOCATION_COLOMBIA_ANACONDA", "level9"},
        {"LOCATION_COLOMBIA", "level9"},
        {"LOCATION_MUMBAI_KINGCOBRA", "level10"},
        {"LOCATION_MUMBAI", "level10"},
        {"LOCATION_NORTHAMERICA", "level11"},
        {"LOCATION_NORTHAMERICA_GARTERSNAKE", "level11"},
        {"LOCATION_NORTHSEA", "level12"},
        {"LOCATION_GREEDY_RACCOON", "level13"},
        {"LOCATION_OPULENT_STINGRAY", "level14"},
        {"LOCATION_GOLDEN_GECKO", "level15"},
        {"LOCATION_GOLDEN", "level15"},
        {"LOCATION_ANCESTRAL_BULLDOG", "level16"},
        {"LOCATION_ANCESTRAL_SMOOTHSNAKE", "level16"},
        {"LOCATION_ANCESTRAL", "level16"},
        {"LOCATION_EDGY_FOX", "level17"},
        {"LOCATION_EDGY", "level17"},
        {"LOCATION_WET_RAT", "level18"},
        {"LOCATION_WET", "level18"},
        {"LOCATION_ELEGANT_LLAMA", "level19"},
        {"LOCATION_ELEGANT", "level19"},
        {"LOCATION_TRAPPED_WOLVERINE", "level20"},
        {"LOCATION_TRAPPED", "level20"}
    };
}

start
{
    if (settings.StartEnabled && settings["autorestart"])
    {
        if (vars.missionTime.Current == 0)
        {
            string settingKey = string.Empty;
            if (vars.locationDescriptor.TryGetValue(vars.metadataLocation.Current, out settingKey))
            {
                if (settings[settingKey])
                {
                    vars.currentMissionTime = (ulong)0;
                    vars.totalIGT = (ulong)0;
                    return true;
                }
            }
        }
    }
    else
    {
        if (vars.totalIGT > 0)
        {
            vars.currentMissionTime = (ulong)0;
            vars.totalIGT = (ulong)0;
        }
    }

    return false;
}

reset
{
    if (vars.missionTime.Current > 0)
    {
        vars.disableReset = false;
    }

    if (settings.ResetEnabled
        && vars.disableReset == false
        && settings["autorestart"]
        && vars.gateExited.Current == false
        && vars.missionTime.Current == 0
        && vars.hudMissionTimeController.Current > 0)
    {
        string settingKey = string.Empty;
        if (vars.locationDescriptor.TryGetValue(vars.metadataLocation.Current, out settingKey))
        {
            if (settings[settingKey])
            {
                vars.disableReset = true;
                return true;
            }
        }
    }

    return false;
}

isLoading
{
    return true;
}

gameTime
{
    if (vars.hudMissionTimeController.Current > 0
        && vars.missionTime.Current > 0
        && vars.time.Current > vars.missionTime.Current)
    {
        if (vars.gateExited.Current == false)
            vars.currentMissionTime = vars.time.Current - vars.missionTime.Current;
        else if (vars.currentExitTime > 0)
        {
            vars.currentMissionTime = vars.currentExitTime - vars.missionTime.Current;
            vars.currentExitTime = (ulong)0;
        }
    }

    //Check if we restart/exit mission
    //
    if (vars.currentMissionTime > 0)
    {
        if ((vars.currentMissionTime > 0 && vars.gateExited.Current == true) ||
            (vars.missionTime.Current == 0 && vars.hudMissionTimeController.Current > 0))
        {
            if (settings["useseconds"])
            {
                //We use bit operation to convert it to seconds, it sets first 20 bits to 0
                //
                vars.currentMissionTime &= ~((ulong)0xFFFFF);
            }

            if (vars.gateExited.Current)
            {
                vars.canDoSplit = true;
            }

            vars.totalIGT += vars.currentMissionTime;
            vars.currentMissionTime = (ulong)0;
        }
    }

    //We have to convert microseconds to seconds since it's binary format we have to use 2^-20 (0.00000095367432) // decimal 10^-6, 1000000μs is 1s
    //
    return TimeSpan.FromSeconds((double)(vars.totalIGT + vars.currentMissionTime) * 0.00000095367432);
}

split
{
    //Split when exited mission
    //
    if (settings.SplitEnabled && (!settings["splitassassin"] || vars.silentAssassinStatus) && vars.hudMissionTimeController.Current > 0 && vars.canDoSplit)
    {
        vars.lastSplitLocation = vars.metadataLocation.Current;
        return true;
    }
    return false;
}
