export @init

function initm(ex)
  quote
    if !@isdefined __inits__
      const __inits__ = []
    end
    if !@isdefined __init__
      __init__() = @init
    end
    push!(__inits__, () -> $ex)
    nothing
  end |> esc
end

function initm()
  :(for f in __inits__
      f()
    end) |> esc
end

macro init(args...)
  initm(args...)
end
