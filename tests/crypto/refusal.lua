--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The refusal check the crypto.kpp scripts share (see run.sh).

local refusal = {}

function refusal.check(object, peer)
	local secret, err = object:sharedsecret(peer)
	assert(secret == nil, "sharedsecret answered a secret for a key the curve refuses")
	assert(err == "EINVAL", "sharedsecret answered " .. tostring(err) .. " where EINVAL was expected")
end

return refusal

