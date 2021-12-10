state("HITMAN3")
{
    // Total ingame time including starting cutscene
    float IGT: 0x03071FB8, 0x10C;
    // Time spent in starting cutscene
    float CST: 0x02FF4CA8, 0x898;
}

startup {
    print("[hitman asl] startup");
    vars.totalIGT = 0.0;
    vars.realIGT = 0.0;
    vars.realIGT_old = 0.0;
}

start {
    if (vars.totalIGT + vars.realIGT + vars.realIGT_old > 0.1) {
        print("[hitman asl] reset");
        vars.totalIGT = 0.0;
        vars.realIGT = 0.0;
        vars.realIGT_old = 0.0;
    }
}

update {
    if (current.CST > 0.0) {
        vars.realIGT_old = vars.realIGT;
        vars.realIGT = current.IGT - current.CST;
    }
}

isLoading {
    return true;
}

gameTime {
    
    if (vars.realIGT_old - vars.realIGT > 0.1) {
        vars.totalIGT += vars.realIGT_old - vars.realIGT;
    }
    
    return TimeSpan.FromSeconds(vars.totalIGT + vars.realIGT);
}