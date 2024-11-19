
-- ------------------------------------------------------------------------
-- math

function cos(x)
  return math.cos(math.rad(x * 360))
end

function sin(x)
  return -math.sin(math.rad(x * 360))
end

-- base1 modulo
function mod1(v, m)
  return ((v - 1) % m) + 1
end

function linlin(slo, shi, dlo, dhi, f)
  if slo < shi then
    return util.linlin(slo, shi, dlo, dhi, f)
  else
    return - util.linlin(shi, slo, dlo, dhi, f)
  end
end

-- -------------------------------------------------------------------------
-- tables

-- remove all element of table without changing its memory pointer
function tempty(t)
  for k, v in pairs(t) do
    t[k] = nil
  end
end

function tkeys(t)
  local t2 = {}
  for k, _ in pairs(t) do
    table.insert(t2, k)
  end
  return t2
end
