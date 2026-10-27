local Prompt = { announced = false, Choose = RQ.SnapshotService.Register }
RQ.RegistrationPrompt = Prompt

function Prompt.Show(force)
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
        RQ.Api.Print("Register this character: /rq add or /rq ignore.")
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
    choices[#choices + 1] = {
        label = "Ignore this character",
        run = function()
            return Prompt.Choose("ignore")
        end,
    }
    RQ.Api.ShowRegistrationPrompt(
        "Register " .. (RQ.Character.DisplayName(record.identity) or "this character"),
        choices
    )
end
