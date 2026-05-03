return {
    LuaVersion = "Lua51",
    VarNamePrefix = "",
    NameGenerator = "MangledShuffled",
    PrettyPrint = true,
    Seed = 0,
    Steps = {
        { Name = "WatermarkCheck", Settings = { Content = "Protected by Lua VirtualBox by FireflyProtector.xyz" } },
        { Name = "Vmify", Settings = {} },
        { Name = "WrapInFunction", Settings = {} },
    },
}
