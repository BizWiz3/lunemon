-- lunemon.luau
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

local POLL_INTERVAL = 0.5

local args = process.args
if #args == 0 then
    stdio.ewrite(stdio.color("red") .. "Usage: lunemon [--ignore <pattern>] <script.luau> [args...]\n" .. stdio.color("reset"))
    process.exit(1)
end

local targetScript = nil
local targetArgs = {}

-- Standard folders to ignore to save memory and CPU
local ignoredList = {
    ".git",
    ".gitignore",
    "lune_packages",
    "luau_packages",
    "Packages",
    "pesde.toml",
    "pesde.lock",
}

-- Basic argument parser
local i = 1
while i <= #args do
    local arg = args[i]
    if arg == "--ignore" then
        i = i + 1
        if args[i] then
            table.insert(ignoredList, args[i])
        end
    elseif not targetScript then
        targetScript = arg
    else
        table.insert(targetArgs, arg)
    end
    i = i + 1
end

if not targetScript then
    stdio.ewrite(stdio.color("red") .. "Error: No target script provided.\n" .. stdio.color("reset"))
    process.exit(1)
end

--- Checks if a directory or file matches the ignored list
local function isIgnored(name)
    for _, pattern in ignoredList do
        -- Simple substring match (e.g. if name is "pesde_packages")
        if string.find(name, pattern, 1, true) then
            return true
        end
    end
    return false
end

--- Recursively searches for files
local function getWatchableFiles(dir)
    local files = {}
    local ok, entries = pcall(fs.readDir, dir)
    if not ok then return files end

    for _, name in entries do
        if isIgnored(name) then
            continue
        end

        local path = dir .. "/" .. name
        local isDirOk, isDir = pcall(fs.isDir, path)
        
        if isDirOk and isDir then
            for _, subFile in getWatchableFiles(path) do
                table.insert(files, subFile)
            end
        else
            -- Watch Luau, Lua, JSON, and TOML files
            if name:match("%.luau?$") or name:match("%.json$") or name:match("%.toml$") then
                table.insert(files, path)
            end
        end
    end
    return files
end

--- Retrieves the modified timestamps
local function getModifiedTimes(files)
    local times = {}
    for _, file in files do
        local ok, meta = pcall(fs.metadata, file)
        if ok and meta then
            times[file] = meta.modifiedAt.unixTimestampMillis
        end
    end
    return times
end

local currentChild = nil

local function pipeStream(reader, isError)
    task.spawn(function()
        while true do
            local ok, chunk = pcall(function() return reader:read() end)
            if not ok or chunk == nil then break end
            
            if chunk ~= "" then
                if isError then
                    stdio.ewrite(stdio.color("red") .. chunk .. stdio.color("reset"))
                else
                    stdio.write(chunk)
                end
            end
        end
    end)
end

local function startProcess()
    if currentChild then
        pcall(function() currentChild:kill() end)
        currentChild = nil
    end

    stdio.write(stdio.color("green") .. "[lunemon] Starting ...\n" .. stdio.color("reset"))

    local execArgs = { "run", targetScript }
    for _, arg in targetArgs do
        table.insert(execArgs, arg)
    end

    local ok, child = pcall(process.create, "lune", execArgs, { env = process.env })

    if ok and child then
        currentChild = child
        if child.stdout then pipeStream(child.stdout, false) end
        if child.stderr then pipeStream(child.stderr, true) end
        
        task.spawn(function()
            local statusOk = pcall(function() return child:status() end)
            if statusOk and currentChild == child then
                stdio.ewrite(stdio.color("yellow") .. "\n[lunemon] Process exited.\n" .. stdio.color("reset"))
            end
        end)
    else
        stdio.ewrite(stdio.color("red") .. "[lunemon] Failed to start process.\n" .. stdio.color("reset"))
    end
end

-----------------------
-- Application Entry --
-----------------------

startProcess()

local lastFiles = getWatchableFiles(".")
local lastTimes = getModifiedTimes(lastFiles)

stdio.write(stdio.color("cyan") .. "[lunemon] Watching for file changes...\n" .. stdio.color("reset"))

while true do
    task.wait(POLL_INTERVAL)

    local currentFiles = getWatchableFiles(".")
    local currentTimes = getModifiedTimes(currentFiles)
    local changed = false

    for _, file in currentFiles do
        if lastTimes[file] ~= currentTimes[file] then
            stdio.write(stdio.color("yellow") .. "\n[lunemon] Restarting due to changes in " .. file .. "\n" .. stdio.color("reset"))
            changed = true
            break
        end
    end

    if not changed then
        for _, file in lastFiles do
            if not currentTimes[file] then
                stdio.write(stdio.color("yellow") .. "\n[lunemon] Restarting due to deletion of " .. file .. "\n" .. stdio.color("reset"))
                changed = true
                break
            end
        end
    end

    if changed then
        lastFiles = currentFiles
        lastTimes = currentTimes
        startProcess()
    end
end