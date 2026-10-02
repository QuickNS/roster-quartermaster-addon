local Prompt = { announced = false }
RQ.RegistrationPrompt = Prompt

function Prompt.Choose(action, slotId)
    local ok, err = RQ.Database.Register(action, slotId)
    if not ok then
        RQ.Api.Print("Registration failed: " .. err)
        return false
    end
    RQ.SnapshotService.CancelPending()
    if action ~= "ignore" then
        local captured, captureError = RQ.SnapshotService.Capture()
        if not captured then
            RQ.Api.Print("Snapshot not saved: " .. captureError)
        end
    end
    RQ.Api.HideRegistrationPrompt()
    RQ.Api.Print(
        action == "ignore" and "Character ignored. Use /rq register to reconsider."
            or "Roster registration saved. Use /rq roster."
    )
    return true
end

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
    RQ.Api.ShowRegistrationPrompt("Register " .. (record.identity.displayName or "this character"), choices)
end
