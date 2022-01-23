/*
    This script tracks Hitman 3 ingame time in LiveSplit.
    * It does NOT auto-split
    * It tracks time across levels and level restarts
    * It pauses in menus, including inventory
    * It does not pause at the end-level cutscene, only at the loading screen,
      so you should immediately skip the end-level cutscene.
*/
state("HITMAN3")
{
    // Total ingame time since start of level (including starting cutscene)
    float IGT: 0x0310C778, 0x108;

    // Time spent in starting cutscene or other scenes without player control, e.g. walking through curtain in Dubai.
    // Starts counting along with IGT, but pauses once cutscene ends. When player loses control in game, it jumps
    // to the value of IGT, counts again and pauses when player regains control.
    float CST: 0x0308EAC8, 0x898;
    
    // Alternate ingame time that starts after cutscene. Works for everything except start of Nightcall.
    // Does NOT stop at end-level cutscene, only when next screen starts loading.
    float ALT_IGT: 0x03BF8728, 0x108;
}

startup {
    print("[hitman asl] startup");
    vars.totalIGT = 0.0;
    refreshRate = 30;
}

start {
    if (vars.totalIGT > 0) {
        print("[hitman asl] livesplit reset");
        vars.totalIGT = 0.0;
    }
}

isLoading {
    return true;
}

gameTime {
    if (current.ALT_IGT > old.ALT_IGT) {
        vars.totalIGT += current.ALT_IGT - old.ALT_IGT;
    }
    else if (current.CST > 0 && current.IGT > old.IGT && current.IGT - current.CST > 0.05) {
        vars.totalIGT += current.IGT - old.IGT;
    }
    return TimeSpan.FromSeconds(vars.totalIGT);
}