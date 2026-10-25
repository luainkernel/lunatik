--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The check of forward() that the tc copy and macsec callbacks share.

local forward = {}

-- nil when forward() of skb raises the refusal, what it did instead otherwise
function forward.refuses(skb, refusal)
	local ok, err = pcall(skb.forward, skb)
	if ok then
		return "forward() sent it"
	elseif not err:find(refusal, 1, true) then
		return err
	end
end

return forward

