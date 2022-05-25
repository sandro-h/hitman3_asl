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
    // 48 8B 0D ? ? ? ? 48 89 15 ? ? ? ? 48 89 05 ? ? ? ? - 3.110.1.0 sig
    float IGT: 0x03195850, 0x108;

    // Time spent in starting cutscene or other scenes without player control, e.g. walking through curtain in Dubai.
    // Starts counting along with IGT, but pauses once cutscene ends. When player loses control in game, it jumps
    // to the value of IGT, counts again and pauses when player regains control.
    // 48 8B 0D ? ? ? ? F3 0F 10 0D ? ? ? ? 48 81 C1 ? ? ? ? 48 8B 7C 24 ? - 3.110.1.0 sig
    float CST: 0x03117B88, 0x898;
    
    // Alternate ingame time that starts after cutscene. Works for everything except start of Nightcall.
    // Does NOT stop at end-level cutscene, only when next screen starts loading.
    // 48 8B 1D ? ? ? ? 48 8D 4D ? 0F 29 B4 24 ? ? ? ? - 3.100.1 sig
    // 48 8B 1D ? ? ? ? 48 8D 4D F0 - 3.110.1.0 sig
    //
    // Correct offsets is 0x110
    // F3 0F 11 87 ? ? ? ? F3 0F 10 87 ? ? ? ? 0F 2F 05 ? ? ? ?  3.110.1.0 sig
    //   movss   dword ptr [rdi+110h], xmm0
    //
    float ALT_IGT: 0x03C81960, 0x110;
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
