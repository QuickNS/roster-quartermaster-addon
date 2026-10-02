local Prompt = { announced = false, Choose = RQ.SnapshotService.Register }
RQ.RegistrationPrompt = Prompt

function Prompt.Show(force)
    if force then
        Prompt.deferred = false
    elseif Prompt.deferred then
        return
    end
    local record = RQ.Database.Current()
    if not record then
        if force then
            RQ.Api.Print("Registration unavailable: current identity is unknown. Use /rq rescan and /rq diag.")
        end
        return
    end
    if record.registration ~= "pending" and not force then
        return
    end
    if not Prompt.announced or force then
        RQ.Api.Print("Register this character: /rq add, /rq link <slot>, or /rq ignore. Use /rq slots for choices.")
        Prompt.announced = true
    end
    local choices = {
        {
            label = "Add as new roster member",
            run = function()
                return Prompt.Choose("add")
            end,
        },
    }
    for _, id in ipairs(RQ.Util.Keys(RQDB.plannedRoster)) do
        local slot = RQDB.plannedRoster[id]
        if not slot.claimedBy or slot.claimedBy == RQCharDB.characterId then
            local slotId = id
            choices[#choices + 1] = {
                label = "Link: " .. (slot.plannedName or slotId) .. " (" .. slotId .. ")",
                run = function()
                    return Prompt.Choose("link", slotId)
                end,
            }
        end
    end
    choices[#choices + 1] = {
        label = "Ignore this character",
        run = function()
            return Prompt.Choose("ignore")
        end,
    }
    choices[#choices + 1] = {
        label = "Decide later",
        run = function()
            Prompt.deferred = true
            return true
        end,
    }
    RQ.Api.ShowRegistrationPrompt(
        "Register " .. (RQ.Character.DisplayName(record.identity) or "this character"),
        choices
    )
end
