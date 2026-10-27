-- Provisional assumptions, not verified Forever mechanics. Rates are levels per hour.
RQ.DefaultPlanning = {
    innRate = 0.00625,
    outsideRate = 0.0015625,
    capLevels = 1.5,
    nearCapRatio = 0.9,
    maxLevel = 60,
    levelMilestones = { 25, 45, 60 },
    professionMilestones = { 150, 225, 300 },
    weights = {
        rested = 40,
        levelMilestone = 15,
        blocker = 25,
        dungeon = 15,
        professionMilestone = 10,
        lastSession = -10,
        stale = -5,
    },
}

RQ.PlanningFields = {
    { key = "innRate", label = "Inn rate (% of level / hour)", scale = 100, min = 0, max = 10 },
    { key = "outsideRate", label = "Outside rate (% of level / hour)", scale = 100, min = 0, max = 10 },
    { key = "capLevels", label = "Rested cap (% of a level)", scale = 100, min = 0.01, max = 10 },
    { key = "nearCapRatio", label = "Near cap (% of configured cap)", scale = 100, min = 0.01, max = 1 },
    { key = "maxLevel", label = "Configured maximum level", scale = 1, min = 1, max = 1000, integer = true },
}
