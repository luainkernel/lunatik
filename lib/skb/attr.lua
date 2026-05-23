--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Socket buffer operations.
-- This module provides a higher-level abstraction over the `skb` module.
--
-- @module skb.attr
-- @see skb
--

local mt = {
	__index = function(self, key)
		local getter = self._skb["get" .. key]
		if type(getter) == "function" then
			return getter(self._skb)
		end

		local method = self._skb[key]
		if type(method) == "function" then
			return function(_, ...)
				return method(self._skb, ...)
			end
		end
	end,

	__newindex = function(self, key, val)
		local setter = self._skb["set" .. key]
		if type(setter) == "function" then
			return setter(self._skb, val)
		end

		error("skb field '" .. key .. "' is read-only or does not exist")
	end,
}

return function(raw_skb)
	return setmetatable({ _skb = raw_skb }, mt)
end

