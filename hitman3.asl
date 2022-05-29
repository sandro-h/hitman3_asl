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
    Func<string, List<byte>> convertSigToByteArray = (sig) =>
    {
        List<byte> bytes = new List<byte>();

        var stringBytes = sig.Split(' ');

        foreach (var stringByte in stringBytes)
        {
            if (stringByte.Contains("?"))
            {
                bytes.Add(0xFF);
                continue;
            }

            bytes.Add(Convert.ToByte(stringByte, 16));
        }

        return bytes;
    };

    var mainModule = modules.First();
    var baseAddress = mainModule.BaseAddress;

    var signaturesList = new[]
    {
        new { name = "gateExited", type = "offset", read = 0x2, sig = convertSigToByteArray("C6 85 ? ? ? ? ? 48 8B 85 ? ? ? ? 48 85 C0"), state = new int[] { 0, 0, 0 }},
        new { name = "metadataLocation", type = "offset", read = 0x3, sig = convertSigToByteArray("48 89 9E ? ? ? ? 49 8B CD"), state = new int[] { 0, 0, 0 }},
        new { name = "hudMissionTimeController", type = "pointer", read = 0x3, sig = convertSigToByteArray("48 8B 1D ? ? ? ? 48 85 DB 0F 84 ? ? ? ? 48 8B 43 28"), state = new int[] { 0, 0, 0 }},
        new { name = "contractsManager", type = "pointer", read = 0x3, sig = convertSigToByteArray("48 8D 0D ? ? ? ? E8 ? ? ? ? 48 8D 4D E7 E8 ? ? ? ? F7 45 ? ? ? ? ?"), state = new int[] { 0, 0, 0 }},
        new { name = "gameTime", type = "pointer", read = 0x3, sig = convertSigToByteArray("4C 89 0D ? ? ? ? EB 5C"), state = new int[] { 0, 0, 0 }}
    }.ToList();

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

    var textSectionData = memory.ReadBytes(baseAddress + textVirtualAddress, textVirtualSize);

    //We probably could use internaly class SignatureScanner but it dosen't support multiple signatures at the same time
    //

    for (var i = 0; i < textSectionData.Length; i++)
    {
        bool finish = true;

        foreach (var signature in signaturesList)
        {
            if (signature.state[0] == 1)
                continue;

            finish = false;

            var currentIndex = signature.state[1];

            if (signature.sig[currentIndex] == 0xFF
            || signature.sig[currentIndex] == textSectionData[i])
            {
                if ((currentIndex + 1) == signature.sig.Count)
                {
                    var sigAddress = baseAddress + textVirtualAddress + (i - currentIndex);

                    if (signature.type == "offset")
                    {
                        signature.state[2] = memory.ReadValue<int>(sigAddress + signature.read);
                    }
                    else if (signature.type == "pointer")
                    {
                        signature.state[2] = memory.ReadValue<int>(sigAddress + signature.read) + textVirtualAddress + (i - currentIndex) + 0x7;
                    }

                    signature.state[0] = 1;
                }
                signature.state[1]++;
                continue;
            }

            signature.state[1] = 0;
        }

        if (finish)
            break;
    }

    var gameAddresses = new Dictionary<string, int>();

    foreach (var signature in signaturesList)
    {
        gameAddresses[signature.name] = signature.state[2];
    }

    vars.timePointer = new DeepPointer(gameAddresses["gameTime"]);
    vars.hudMissionTimeControllerPointer = new DeepPointer(gameAddresses["hudMissionTimeController"]);
    vars.missionTimePointer = new DeepPointer(gameAddresses["hudMissionTimeController"], 0x40);
    vars.gateExitedPointer = new DeepPointer(gameAddresses["contractsManager"] + gameAddresses["gateExited"]);
    vars.metadataLocationPointer = new DeepPointer(gameAddresses["contractsManager"] + gameAddresses["metadataLocation"], 0x00);

    //I don't know how to modify pointers in state so will create my own variables
    //
    // Fix me please?
    //

    vars.currentTime = (ulong)0;
    vars.currentHudMissionTimer = (ulong)0;
    vars.currentMissionTime = (ulong)0;
    vars.currentGateExited = false;
    vars.currentMetadataLocation = "";

    vars.oldTime = (ulong)0;
    vars.oldHudMissionTimer = (ulong)0;
    vars.oldMissionTime = (ulong)0;
    vars.oldGateExited = false;
    vars.oldMetadataLocation = "";
}

update
{
    vars.oldTime = vars.currentTime;
    vars.oldHudMissionTimer = vars.currentHudMissionTimer;
    vars.oldMissionTime = vars.currentMissionTime;
    vars.oldGateExited = vars.currentGateExited;
    vars.oldMetadataLocation = vars.currentMetadataLocation;

    vars.currentTime = vars.timePointer.Deref<ulong>(game);
    vars.currentHudMissionTimer = vars.hudMissionTimeControllerPointer.Deref<ulong>(game);
    if (vars.currentHudMissionTimer > 0)
        vars.currentMissionTime = vars.missionTimePointer.Deref<ulong>(game);
    else
        vars.currentMissionTime = (ulong)0;
    vars.currentGateExited = vars.gateExitedPointer.Deref<bool>(game);
    vars.currentMetadataLocation = vars.metadataLocationPointer.DerefString(game, 255, "");
}

startup
{
    vars.totalIGT = (ulong)0;
    vars.disableReset = true;
    refreshRate = 20;

    settings.Add("useseconds", true, "Fix timer to seconds, after exit/restart mission");

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
        if (vars.currentMissionTime == 0)
        {
            string settingKey = string.Empty;
            if (vars.locationDescriptor.TryGetValue(vars.currentMetadataLocation, out settingKey))
            {
                if (settings[settingKey])
                {
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
            vars.totalIGT = (ulong)0;
        }
    }

    return false;
}

reset
{
    if (vars.currentMissionTime > 0)
    {
        vars.disableReset = false;
    }

    if (settings.ResetEnabled
        && vars.disableReset == false
        && settings["autorestart"]
        && vars.currentGateExited == false
        && vars.currentMissionTime == 0
        && vars.currentHudMissionTimer > 0)
    {
        string settingKey = string.Empty;
        if (vars.locationDescriptor.TryGetValue(vars.currentMetadataLocation, out settingKey))
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

split
{
    //Split when exited mission
    //
    return settings.SplitEnabled && vars.currentHudMissionTimer > 0 && vars.oldGateExited == false && vars.currentGateExited == true;
}

isLoading
{
    return true;
}

gameTime
{
    if (vars.currentTime > vars.oldTime && vars.currentMissionTime > 0
        && vars.oldTime >= vars.currentMissionTime
        && vars.currentGateExited == false)
    {
        vars.totalIGT += vars.currentTime - vars.oldTime;
    }

    if (settings["useseconds"])
    {
        //Fix timer to seconds only
        //
        if ((vars.oldGateExited == false && vars.currentGateExited == true) ||
            (vars.currentMissionTime == 0 && vars.currentHudMissionTimer > 0))
        {
            vars.totalIGT &= ~((ulong)0xFFFFF);
        }
    }
    return TimeSpan.FromSeconds((double)vars.totalIGT * 0.00000095367432);
}
