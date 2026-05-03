(("Protected by GameGuard")):gsub(".+", function(a)
	WM_32 = a;
end);
return (function(...)
	return (function(Z, W, p, Y, I, a, B, P, f, F, b, r, U, m, M, y, h)
		m, M, U, b, P, F, f, r, h, y = function(a)
				F[a] = F[a] - 1;
				if 0 == F[a] then
					F[a], y[a] = nil, nil;
				end;
			end, 0, function(a, Y)
				local W = h(Y);
				local p = function(...)
						return r(a, { ... }, Y, W);
					end;
				return p;
			end, function(a)
				local r, Y = 1, a[1];
				while Y do
					F[Y], r = F[Y] - 1, 1 + r;
					if 0 == F[Y] then
						F[Y], y[Y] = nil, nil;
					end;
					Y = a[r];
				end;
			end, function()
				M = 1 + M;
				F[M] = 1;
				return M;
			end, {}, function(a, Y)
				local W = h(Y);
				local p = function(p, B, I, Z, y)
						return r(a, {
							p,
							B,
							I,
							Z,
							y,
						}, Y, W);
					end;
				return p;
			end, function(r, W, p, B)
				local P, y, F, Z;
				while r do
					do
						if r < 9162906 then
							if r < 3550359 then
								Z, y, r = 1, W[1], 0;
								F, P = r, Z;
								r = 15707036;
							elseif r < 5895811 then
								Z, P, y, F, r = {}, nil, nil, nil, a.JGyRApNXAQKJk;
							else
								y = W;
								r = f(3213485, {});
								F, Z = r, 1000;
								r = F(Z);
								F, Z, r = nil, {}, a.WNz6E6nAorQB;
							end;
						else
							if r < 13064229 then
								Z = "print";
								r = a[Z];
								Z = r(F);
								r = P;
								Z = F + P;
								F, P = r, Z;
								r = 15707036;
							else
								r = F < y;
								r = r and 10421422 or 3887233;
							end;
						end;
					end;
				end;
				r = #B;
				return Y(Z);
			end, function(a)
				for r = 1, #a, 1 do
					F[a[r]] = 1 + F[a[r]];
				end;
				if W then
					local r = W(true);
					local Y = B(r);
					Y.__index, Y.__gc, Y.__len = a, b, function()
							return -3014469;
						end;
					return r;
				else
					return p({}, { __gc = b, __index = a, __len = function()
							return -3014469;
						end });
				end;
			end, {};
		return (U(7904390, {}))(Y(Z));
	end)({ ... }, newproxy, setmetatable, unpack or table.unpack, select, getfenv and getfenv() or _ENV, getmetatable);
end)(...);