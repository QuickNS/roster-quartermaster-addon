local Data = {
    version = 1,
    evidence = "General WoW reference; Forever recipes, gear eligibility and trainer locations require verification.",
    reference = "https://warcraft.wiki.gg/wiki/Profession",
    professions = {
        [164] = {
            name = "Blacksmithing",
            utility = "Weapons and metal armor",
            classes = { WARRIOR = true, PALADIN = true },
            reference = "Blacksmithing",
        },
        [165] = {
            name = "Leatherworking",
            utility = "Leather/mail armor and armor kits",
            classes = { DRUID = true, ROGUE = true, HUNTER = true, SHAMAN = true },
            reference = "Leatherworking",
        },
        [171] = { name = "Alchemy", utility = "Consumables for all classes", reference = "Alchemy" },
        [182] = { name = "Herbalism", gathering = true, utility = "Herbs for consumables", reference = "Alchemy" },
        [186] = { name = "Mining", gathering = true, utility = "Metal supply", reference = "Blacksmithing" },
        [197] = {
            name = "Tailoring",
            utility = "Bags and cloth armor",
            classes = { MAGE = true, PRIEST = true, WARLOCK = true },
            reference = "Tailoring",
        },
        [202] = {
            name = "Engineering",
            utility = "Personal tools; many items require Engineering",
            classes = { HUNTER = true },
            reference = "Engineering",
        },
        [333] = { name = "Enchanting", utility = "Equipment enhancements and disenchanting", reference = "Enchanting" },
        [393] = { name = "Skinning", gathering = true, utility = "Leather supply", reference = "Leatherworking" },
    },
    links = {
        { source = 182, target = 171, label = "Herbalism supplies Alchemy", reference = "Alchemy" },
        { source = 186, target = 164, label = "Mining supplies Blacksmithing", reference = "Blacksmithing" },
        { source = 186, target = 202, label = "Mining supplies Engineering", reference = "Engineering" },
        { source = 393, target = 165, label = "Skinning supplies Leatherworking", reference = "Leatherworking" },
        {
            source = 197,
            target = 333,
            label = "Tailoring can supply disenchantable equipment",
            reference = "Enchanting",
        },
    },
}
RQ.ProfessionRelationships = Data
