-- Discard page-load results after a newer navigation or page close.
local M = {}

function M.begin(host)
    host._weread_home_generation = (host._weread_home_generation or 0) + 1
    return host._weread_home_generation
end

function M.isCurrent(host, generation)
    return host._weread_home_generation == generation
end

return M
