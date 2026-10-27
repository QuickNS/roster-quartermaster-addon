local Service = {}
RQ.ConfigTransferService = Service

local pending, rollback, sequence = nil, nil, 0

local function ready()
    if not RQ.Database.initialized then
        return false, "Configuration transfer unavailable: SavedVariables are not initialized."
    end
    return true
end

local function publish(account, character)
    RQDB, RQCharDB = account, character
    RQ.Database.NotifyChanged()
    RQ.Api.RefreshMinimapPosition()
end

function Service.ClearPending()
    -- Called at logout: neither preview nor rollback may survive the session.
    pending, rollback = nil, nil
end

function Service.Export()
    local ok, err = ready()
    if not ok then
        return false, err
    end
    local text
    text, err = RQ.ConfigTransfer.Export(RQDB)
    if not text then
        return false, err
    end
    if not RQ.Api.ShowCopyWindow or not RQ.Api.ShowCopyWindow("RQ configuration export", text) then
        RQ.Api.Print("Copy window unavailable; configuration follows as one unmodified string:")
        RQ.Api.Print(text)
    end
    return true, nil, text
end

function Service.Preview(text)
    pending = nil
    local ok, err = ready()
    if not ok then
        return false, err
    end
    local config
    config, err = RQ.ConfigTransfer.Decode(text)
    if not config then
        return false, err
    end
    local before
    before, err = RQ.ConfigTransfer.Extract(RQDB)
    if not before then
        return false, err
    end
    local account, character
    account, character, err = RQ.ConfigTransfer.Prepare(config, RQDB, RQCharDB, RQ.Database.activeId)
    if not account or not character then
        return false, err
    end
    local candidate
    candidate, err = RQ.ConfigTransfer.Extract(account)
    if not candidate then
        return false, err
    end
    local base, encoded, mirror
    base, err = RQ.ConfigTransfer.Encode(before)
    if not base then
        return false, err
    end
    encoded, err = RQ.ConfigTransfer.Encode(candidate)
    if not encoded then
        return false, err
    end
    mirror, err = RQ.ConfigTransfer.MirrorKey(RQCharDB)
    if not mirror then
        return false, err
    end
    sequence = sequence + 1
    local token = tostring(sequence) .. "-" .. RQ.ConfigTransfer.Checksum(encoded)
    pending = {
        config = config,
        base = base,
        mirror = mirror,
        candidate = encoded,
        token = token,
        activeId = RQ.Database.activeId,
    }
    for _, line in ipairs(RQ.ConfigTransfer.Preview(before, candidate)) do
        RQ.Api.Print(line)
    end
    RQ.Api.Print("Confirm this preview with /rq import-confirm " .. token .. "; cancel with /rq import-cancel.")
    return true, nil, token
end

function Service.Confirm(token)
    local ok, err = ready()
    if not ok then
        return false, err
    end
    if not pending or token ~= pending.token then
        return false, "No matching import preview; use its exact confirmation token."
    end
    local preview = pending
    pending = nil
    local base, mirror
    base, err = RQ.ConfigTransfer.Export(RQDB)
    if not base then
        return false, err
    end
    mirror, err = RQ.ConfigTransfer.MirrorKey(RQCharDB)
    if not mirror then
        return false, err
    end
    if base ~= preview.base or mirror ~= preview.mirror or preview.activeId ~= RQ.Database.activeId then
        return false, "Configuration changed since preview. Paste the import again for a new preview."
    end
    local account, character
    account, character, err = RQ.ConfigTransfer.Prepare(preview.config, RQDB, RQCharDB, RQ.Database.activeId)
    if not account or not character then
        return false, err
    end
    local encoded
    encoded, err = RQ.ConfigTransfer.Export(account)
    if not encoded then
        return false, err
    end
    if encoded ~= preview.candidate then
        return false, "Import candidate changed since preview. Paste it again."
    end
    rollback = preview.base
    publish(account, character)
    return true
end

function Service.Cancel()
    pending = nil
    return true
end

function Service.Rollback()
    local ok, err = ready()
    if not ok then
        return false, err
    end
    if not rollback then
        return false, "No configuration rollback available in this session."
    end
    local config
    config, err = RQ.ConfigTransfer.Decode(rollback)
    if not config then
        return false, err
    end
    local account, character
    account, character, err = RQ.ConfigTransfer.Prepare(config, RQDB, RQCharDB, RQ.Database.activeId)
    if not account or not character then
        return false, err
    end
    pending, rollback = nil, nil
    publish(account, character)
    return true
end

function Service.OpenImport()
    pending = nil
    local ok, err = ready()
    if not ok then
        return false, err
    end
    if
        RQ.Api.ShowCopyWindow
        and RQ.Api.ShowCopyWindow("RQ configuration import", "", function(text)
            local accepted, previewError = Service.Preview(text)
            if not accepted then
                RQ.Api.Print("Configuration import failed: " .. previewError)
            end
        end)
    then
        return true
    end
    return false, "Import window unavailable. Paste the complete export after /rq import, or retry out of combat."
end

function Service.Command(command, argument)
    argument = argument or ""
    if type(argument) ~= "string" then
        return false, "Configuration command argument must be text."
    end
    if command == "import" then
        if argument == "" then
            return Service.OpenImport()
        end
        return Service.Preview(argument)
    elseif command == "import-confirm" then
        return Service.Confirm(argument)
    end
    if argument ~= "" then
        return false, "This configuration command takes no arguments."
    end
    if command == "export" then
        return Service.Export()
    elseif command == "import-cancel" then
        return Service.Cancel()
    elseif command == "import-rollback" then
        return Service.Rollback()
    end
    return false, "Unknown configuration transfer command."
end
