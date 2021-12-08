state("HITMAN3")
{
    float IGT: 0x03B21A40, 0x108;
}

startup {
    print("[hitman asl] startup");
    vars.totalIGT = 0.0;
}

start {
    if (vars.totalIGT != 0.0) {
        print("[hitman asl] reset totalIGT");
        vars.totalIGT = 0.0;
    }
}

isLoading {
    return true;
}

gameTime {
    if (current.IGT < old.IGT) {
        print("[hitman asl] exit level, old.IGT=" + old.IGT + ", current.IGT=" + current.IGT);
        vars.totalIGT += old.IGT - current.IGT;
    }
    return TimeSpan.FromSeconds(vars.totalIGT + current.IGT);
}